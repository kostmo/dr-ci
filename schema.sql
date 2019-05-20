--
-- PostgreSQL database dump
--

-- Dumped from database version 10.8 (Ubuntu 10.8-1.pgdg18.04+1)
-- Dumped by pg_dump version 10.8 (Ubuntu 10.8-1.pgdg18.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: loganci; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE loganci WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


ALTER DATABASE loganci OWNER TO postgres;

\connect loganci

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: build_steps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.build_steps (
    id integer NOT NULL,
    build integer,
    name text,
    is_timeout boolean
);


ALTER TABLE public.build_steps OWNER TO postgres;

--
-- Name: TABLE build_steps; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.build_steps IS 'There should be zero or one build steps associated with a build, depending on whether the CircleCI JSON build structure indicates that one of the steps failed.

This is known before the console logs are "scanned".';


--
-- Name: matches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.matches (
    id integer NOT NULL,
    build_step integer,
    pattern integer,
    line_number integer,
    line_text text,
    span_start integer,
    span_end integer,
    scan_id integer
);


ALTER TABLE public.matches OWNER TO postgres;

--
-- Name: matches_for_build; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.matches_for_build WITH (security_barrier='false') AS
 SELECT matches.pattern AS pat,
    build_steps.build,
    build_steps.name AS step_name
   FROM (public.matches
     JOIN public.build_steps ON ((matches.build_step = build_steps.id)));


ALTER TABLE public.matches_for_build OWNER TO postgres;

--
-- Name: build_match_repetitions; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.build_match_repetitions WITH (security_barrier='false') AS
 SELECT matches_for_build.build,
    matches_for_build.pat,
    count(*) AS repetitions
   FROM public.matches_for_build
  GROUP BY matches_for_build.pat, matches_for_build.build;


ALTER TABLE public.build_match_repetitions OWNER TO postgres;

--
-- Name: patterns; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.patterns (
    expression text,
    id integer NOT NULL,
    description text,
    regex boolean,
    has_nondeterministic_values boolean,
    is_retired boolean DEFAULT false NOT NULL,
    specificity integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.patterns OWNER TO postgres;

--
-- Name: best_pattern_match_for_builds; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.best_pattern_match_for_builds WITH (security_barrier='false') AS
 SELECT DISTINCT ON (build_match_repetitions.build) build_match_repetitions.build,
    build_match_repetitions.pat AS pattern_id,
    patterns.expression,
    patterns.regex,
    patterns.has_nondeterministic_values,
    patterns.is_retired,
    patterns.specificity,
    count(build_match_repetitions.pat) OVER (PARTITION BY build_match_repetitions.build) AS distinct_matching_pattern_count,
    sum(build_match_repetitions.repetitions) OVER (PARTITION BY build_match_repetitions.build) AS total_pattern_matches
   FROM (public.build_match_repetitions
     JOIN public.patterns ON ((build_match_repetitions.pat = patterns.id)))
  ORDER BY build_match_repetitions.build, patterns.specificity DESC, patterns.is_retired, patterns.regex, patterns.id DESC;


ALTER TABLE public.best_pattern_match_for_builds OWNER TO postgres;

--
-- Name: builds; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.builds (
    build_num integer NOT NULL,
    vcs_revision character(40),
    queued_at timestamp with time zone,
    job_name text,
    branch character varying
);


ALTER TABLE public.builds OWNER TO postgres;

--
-- Name: aggregated_build_matches; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.aggregated_build_matches WITH (security_barrier='false') AS
 SELECT best_pattern_match_for_builds.pattern_id AS pat,
    count(best_pattern_match_for_builds.build) AS matching_build_count,
    max(builds.queued_at) AS most_recent,
    min(builds.queued_at) AS earliest
   FROM (public.best_pattern_match_for_builds
     JOIN public.builds ON ((builds.build_num = best_pattern_match_for_builds.build)))
  GROUP BY best_pattern_match_for_builds.pattern_id;


ALTER TABLE public.aggregated_build_matches OWNER TO postgres;

--
-- Name: log_metadata; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.log_metadata (
    line_count integer NOT NULL,
    byte_count integer NOT NULL,
    step integer NOT NULL,
    content text
);


ALTER TABLE public.log_metadata OWNER TO postgres;

--
-- Name: matches_with_log_metadata; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.matches_with_log_metadata WITH (security_barrier='false') AS
 SELECT matches.id,
    matches.build_step,
    matches.pattern,
    matches.line_number,
    matches.line_text,
    matches.span_start,
    matches.span_end,
    matches.scan_id,
    log_metadata.line_count,
    log_metadata.byte_count,
    log_metadata.step,
    build_steps.name AS step_name,
    build_steps.build AS build_num
   FROM ((public.matches
     LEFT JOIN public.log_metadata ON ((log_metadata.step = matches.build_step)))
     LEFT JOIN public.build_steps ON ((build_steps.id = log_metadata.step)));


ALTER TABLE public.matches_with_log_metadata OWNER TO postgres;

--
-- Name: best_pattern_match_augmented_builds; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.best_pattern_match_augmented_builds WITH (security_barrier='false') AS
 SELECT DISTINCT ON (best_pattern_match_for_builds.build) best_pattern_match_for_builds.build,
    matches_with_log_metadata.step_name,
    matches_with_log_metadata.line_number,
    matches_with_log_metadata.line_count,
    matches_with_log_metadata.line_text,
    matches_with_log_metadata.span_start,
    matches_with_log_metadata.span_end,
    builds.vcs_revision,
    builds.queued_at,
    builds.job_name,
    builds.branch,
    best_pattern_match_for_builds.pattern_id
   FROM ((public.best_pattern_match_for_builds
     JOIN public.matches_with_log_metadata ON (((matches_with_log_metadata.pattern = best_pattern_match_for_builds.pattern_id) AND (matches_with_log_metadata.build_num = best_pattern_match_for_builds.build))))
     JOIN public.builds ON ((builds.build_num = best_pattern_match_for_builds.build)))
  ORDER BY best_pattern_match_for_builds.build DESC, matches_with_log_metadata.line_number;


ALTER TABLE public.best_pattern_match_augmented_builds OWNER TO postgres;

--
-- Name: broken_revisions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.broken_revisions (
    id integer NOT NULL,
    revision character(40) NOT NULL,
    reporter text,
    "timestamp" timestamp with time zone DEFAULT now(),
    is_broken boolean NOT NULL,
    notes text,
    implicated_revision character(40)
);


ALTER TABLE public.broken_revisions OWNER TO postgres;

--
-- Name: broken_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.broken_revisions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.broken_revisions_id_seq OWNER TO postgres;

--
-- Name: broken_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.broken_revisions_id_seq OWNED BY public.broken_revisions.id;


--
-- Name: build_steps_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.build_steps_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.build_steps_id_seq OWNER TO postgres;

--
-- Name: build_steps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.build_steps_id_seq OWNED BY public.build_steps.id;


--
-- Name: builds_join_steps; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.builds_join_steps AS
 SELECT build_steps.id AS step_id,
    build_steps.name AS step_name,
    builds.build_num,
    builds.vcs_revision,
    builds.queued_at,
    builds.job_name,
    builds.branch
   FROM (public.build_steps
     LEFT JOIN public.builds ON ((builds.build_num = build_steps.build)))
  ORDER BY builds.vcs_revision, builds.build_num DESC;


ALTER TABLE public.builds_join_steps OWNER TO postgres;

--
-- Name: latest_broken_revision_reports; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.latest_broken_revision_reports AS
 SELECT DISTINCT ON (broken_revisions.revision) broken_revisions.id,
    broken_revisions.revision,
    broken_revisions.reporter,
    broken_revisions."timestamp",
    broken_revisions.is_broken,
    broken_revisions.notes,
    broken_revisions.implicated_revision
   FROM public.broken_revisions
  ORDER BY broken_revisions.revision, broken_revisions.id DESC;


ALTER TABLE public.latest_broken_revision_reports OWNER TO postgres;

--
-- Name: builds_with_reports; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.builds_with_reports WITH (security_barrier='false') AS
 SELECT builds_join_steps.step_id,
    builds_join_steps.step_name,
    builds_join_steps.build_num,
    builds_join_steps.vcs_revision,
    builds_join_steps.queued_at,
    builds_join_steps.job_name,
    builds_join_steps.branch,
    latest_broken_revision_reports.reporter,
    latest_broken_revision_reports.is_broken,
    latest_broken_revision_reports."timestamp" AS report_timestamp,
    latest_broken_revision_reports.notes AS breakage_notes,
    latest_broken_revision_reports.implicated_revision,
    latest_broken_revision_reports.id AS report_id
   FROM (public.builds_join_steps
     LEFT JOIN public.latest_broken_revision_reports ON ((latest_broken_revision_reports.revision = builds_join_steps.vcs_revision)))
  ORDER BY COALESCE(latest_broken_revision_reports.is_broken, false) DESC, builds_join_steps.build_num DESC;


ALTER TABLE public.builds_with_reports OWNER TO postgres;

--
-- Name: created_github_statuses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.created_github_statuses (
    id bigint NOT NULL,
    url text,
    state character varying(7),
    description text,
    target_url text,
    context text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    sha1 character(40),
    project text,
    repo text
);


ALTER TABLE public.created_github_statuses OWNER TO postgres;

--
-- Name: idiopathic_build_failures; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.idiopathic_build_failures WITH (security_barrier='false') AS
 SELECT build_steps.build,
    builds.branch
   FROM (public.build_steps
     JOIN public.builds ON ((build_steps.build = builds.build_num)))
  WHERE (build_steps.name IS NULL);


ALTER TABLE public.idiopathic_build_failures OWNER TO postgres;

--
-- Name: job_failure_frequencies; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.job_failure_frequencies AS
 SELECT builds.job_name,
    count(*) AS freq,
    max(builds.queued_at) AS last
   FROM public.builds
  GROUP BY builds.job_name
  ORDER BY (count(*)) DESC, builds.job_name;


ALTER TABLE public.job_failure_frequencies OWNER TO postgres;

--
-- Name: match_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.match_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.match_id_seq OWNER TO postgres;

--
-- Name: match_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.match_id_seq OWNED BY public.matches.id;


--
-- Name: pattern_authorship; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pattern_authorship (
    pattern integer NOT NULL,
    author text,
    created timestamp with time zone DEFAULT now()
);


ALTER TABLE public.pattern_authorship OWNER TO postgres;

--
-- Name: pattern_step_applicability; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pattern_step_applicability (
    id integer NOT NULL,
    pattern integer,
    step_name text
);


ALTER TABLE public.pattern_step_applicability OWNER TO postgres;

--
-- Name: pattern_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pattern_tags (
    pattern integer NOT NULL,
    tag character varying(20) NOT NULL
);


ALTER TABLE public.pattern_tags OWNER TO postgres;

--
-- Name: patterns_augmented; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.patterns_augmented WITH (security_barrier='false') AS
 SELECT patterns.expression,
    patterns.id,
    patterns.description,
    patterns.regex,
    patterns.has_nondeterministic_values,
    patterns.is_retired,
    patterns.specificity,
    COALESCE(foo.tags, ''::text) AS tags,
    COALESCE(bar.steps, ''::text) AS steps,
    pattern_authorship.author,
    pattern_authorship.created
   FROM (((public.patterns
     LEFT JOIN ( SELECT pattern_tags.pattern,
            string_agg((pattern_tags.tag)::text, ';'::text) AS tags
           FROM public.pattern_tags
          GROUP BY pattern_tags.pattern) foo ON ((foo.pattern = patterns.id)))
     LEFT JOIN ( SELECT pattern_step_applicability.pattern,
            string_agg(pattern_step_applicability.step_name, ';'::text) AS steps
           FROM public.pattern_step_applicability
          GROUP BY pattern_step_applicability.pattern) bar ON ((bar.pattern = patterns.id)))
     LEFT JOIN public.pattern_authorship ON ((pattern_authorship.pattern = patterns.id)));


ALTER TABLE public.patterns_augmented OWNER TO postgres;

--
-- Name: pattern_frequency_summary; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.pattern_frequency_summary AS
 SELECT patterns_augmented.expression,
    patterns_augmented.description,
    COALESCE(aggregated_build_matches.matching_build_count, (0)::bigint) AS matching_build_count,
    aggregated_build_matches.most_recent,
    aggregated_build_matches.earliest,
    patterns_augmented.id,
    patterns_augmented.regex,
    patterns_augmented.specificity,
    patterns_augmented.tags,
    patterns_augmented.steps
   FROM (public.patterns_augmented
     LEFT JOIN public.aggregated_build_matches ON ((patterns_augmented.id = aggregated_build_matches.pat)));


ALTER TABLE public.pattern_frequency_summary OWNER TO postgres;

--
-- Name: pattern_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pattern_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.pattern_id_seq OWNER TO postgres;

--
-- Name: pattern_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pattern_id_seq OWNED BY public.patterns.id;


--
-- Name: pattern_step_applicability_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pattern_step_applicability_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.pattern_step_applicability_id_seq OWNER TO postgres;

--
-- Name: pattern_step_applicability_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pattern_step_applicability_id_seq OWNED BY public.pattern_step_applicability.id;


--
-- Name: scannable_build_steps; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.scannable_build_steps AS
 SELECT builds.build_num,
    build_steps.id AS step_id,
    build_steps.name AS step_name
   FROM (public.builds
     LEFT JOIN public.build_steps ON ((builds.build_num = build_steps.build)))
  WHERE ((build_steps.name IS NOT NULL) AND (NOT build_steps.is_timeout));


ALTER TABLE public.scannable_build_steps OWNER TO postgres;

--
-- Name: scanned_patterns; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scanned_patterns (
    scan integer NOT NULL,
    newest_pattern integer NOT NULL,
    build integer NOT NULL
);


ALTER TABLE public.scanned_patterns OWNER TO postgres;

--
-- Name: scans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scans (
    id integer NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now(),
    latest_pattern_id integer NOT NULL
);


ALTER TABLE public.scans OWNER TO postgres;

--
-- Name: scans_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.scans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.scans_id_seq OWNER TO postgres;

--
-- Name: scans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.scans_id_seq OWNED BY public.scans.id;


--
-- Name: unattributed_failed_builds; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.unattributed_failed_builds WITH (security_barrier='false') AS
 SELECT foo.build,
    builds.branch
   FROM (( SELECT build_steps.build
           FROM (public.build_steps
             LEFT JOIN public.matches ON ((matches.build_step = build_steps.id)))
          WHERE ((matches.pattern IS NULL) AND (build_steps.name IS NOT NULL) AND (NOT build_steps.is_timeout))) foo
     JOIN public.builds ON ((foo.build = builds.build_num)));


ALTER TABLE public.unattributed_failed_builds OWNER TO postgres;

--
-- Name: unscanned_patterns; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.unscanned_patterns WITH (security_barrier='false') AS
 SELECT foo.build_num,
    count(foo.patt) AS patt_count,
    string_agg((foo.patt)::text, ','::text ORDER BY foo.patt) AS unscanned_patts
   FROM (( SELECT patterns.id AS patt,
            scannable_build_steps.build_num
           FROM public.patterns,
            public.scannable_build_steps) foo
     LEFT JOIN public.scanned_patterns ON (((foo.patt = scanned_patterns.newest_pattern) AND (foo.build_num = scanned_patterns.build))))
  WHERE (scanned_patterns.scan IS NULL)
  GROUP BY foo.build_num;


ALTER TABLE public.unscanned_patterns OWNER TO postgres;

--
-- Name: unvisited_builds; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.unvisited_builds AS
 SELECT builds.build_num
   FROM (public.builds
     LEFT JOIN public.build_steps ON ((builds.build_num = build_steps.build)))
  WHERE (build_steps.id IS NULL);


ALTER TABLE public.unvisited_builds OWNER TO postgres;

--
-- Name: broken_revisions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.broken_revisions ALTER COLUMN id SET DEFAULT nextval('public.broken_revisions_id_seq'::regclass);


--
-- Name: build_steps id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.build_steps ALTER COLUMN id SET DEFAULT nextval('public.build_steps_id_seq'::regclass);


--
-- Name: matches id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches ALTER COLUMN id SET DEFAULT nextval('public.match_id_seq'::regclass);


--
-- Name: pattern_step_applicability id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pattern_step_applicability ALTER COLUMN id SET DEFAULT nextval('public.pattern_step_applicability_id_seq'::regclass);


--
-- Name: patterns id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patterns ALTER COLUMN id SET DEFAULT nextval('public.pattern_id_seq'::regclass);


--
-- Name: scans id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scans ALTER COLUMN id SET DEFAULT nextval('public.scans_id_seq'::regclass);


--
-- Name: broken_revisions broken_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.broken_revisions
    ADD CONSTRAINT broken_revisions_pkey PRIMARY KEY (id);


--
-- Name: builds build_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.builds
    ADD CONSTRAINT build_pkey PRIMARY KEY (build_num);


--
-- Name: build_steps build_steps_build_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.build_steps
    ADD CONSTRAINT build_steps_build_name_key UNIQUE (build, name);


--
-- Name: build_steps build_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.build_steps
    ADD CONSTRAINT build_steps_pkey PRIMARY KEY (id);


--
-- Name: created_github_statuses created_github_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.created_github_statuses
    ADD CONSTRAINT created_github_statuses_pkey PRIMARY KEY (id);


--
-- Name: log_metadata log_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_metadata
    ADD CONSTRAINT log_metadata_pkey PRIMARY KEY (step);


--
-- Name: matches match_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT match_pkey PRIMARY KEY (id);


--
-- Name: pattern_authorship pattern_authorship_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pattern_authorship
    ADD CONSTRAINT pattern_authorship_pkey PRIMARY KEY (pattern);


--
-- Name: patterns pattern_expression_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patterns
    ADD CONSTRAINT pattern_expression_key UNIQUE (expression);


--
-- Name: patterns pattern_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patterns
    ADD CONSTRAINT pattern_pkey PRIMARY KEY (id);


--
-- Name: pattern_step_applicability pattern_step_applicability_pattern_step_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pattern_step_applicability
    ADD CONSTRAINT pattern_step_applicability_pattern_step_name_key UNIQUE (pattern, step_name);


--
-- Name: pattern_step_applicability pattern_step_applicability_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pattern_step_applicability
    ADD CONSTRAINT pattern_step_applicability_pkey PRIMARY KEY (id);


--
-- Name: pattern_tags pattern_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pattern_tags
    ADD CONSTRAINT pattern_tags_pkey PRIMARY KEY (pattern, tag);


--
-- Name: scanned_patterns scanned_patterns_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scanned_patterns
    ADD CONSTRAINT scanned_patterns_pkey PRIMARY KEY (scan, newest_pattern, build);


--
-- Name: scans scans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scans
    ADD CONSTRAINT scans_pkey PRIMARY KEY (id);


--
-- Name: fk_build_step_build; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fk_build_step_build ON public.build_steps USING btree (build);


--
-- Name: fk_build_step_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fk_build_step_id ON public.matches USING btree (build_step);


--
-- Name: fk_pattern_step; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fk_pattern_step ON public.pattern_step_applicability USING btree (pattern);


--
-- Name: fk_patternid; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fk_patternid ON public.scans USING btree (latest_pattern_id);


--
-- Name: fk_scan_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fk_scan_id ON public.matches USING btree (scan_id);


--
-- Name: fk_tag_pattern; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fk_tag_pattern ON public.pattern_tags USING btree (pattern);


--
-- Name: fki_fk_build; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fki_fk_build ON public.scanned_patterns USING btree (build);


--
-- Name: fki_fk_pattern; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fki_fk_pattern ON public.scanned_patterns USING btree (newest_pattern);


--
-- Name: fki_fk_scan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fki_fk_scan ON public.scanned_patterns USING btree (scan);


--
-- Name: build_steps build_steps_build_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.build_steps
    ADD CONSTRAINT build_steps_build_fkey FOREIGN KEY (build) REFERENCES public.builds(build_num);


--
-- Name: scanned_patterns fk_pattern; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scanned_patterns
    ADD CONSTRAINT fk_pattern FOREIGN KEY (newest_pattern) REFERENCES public.patterns(id);


--
-- Name: scanned_patterns fk_scan; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scanned_patterns
    ADD CONSTRAINT fk_scan FOREIGN KEY (scan) REFERENCES public.scans(id);


--
-- Name: log_metadata log_metadata_step_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_metadata
    ADD CONSTRAINT log_metadata_step_fkey FOREIGN KEY (step) REFERENCES public.build_steps(id);


--
-- Name: matches match_pattern_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT match_pattern_fkey FOREIGN KEY (pattern) REFERENCES public.patterns(id);


--
-- Name: matches matches_build_step_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_build_step_fkey FOREIGN KEY (build_step) REFERENCES public.build_steps(id);


--
-- Name: matches matches_scan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_scan_id_fkey FOREIGN KEY (scan_id) REFERENCES public.scans(id);


--
-- Name: pattern_authorship pattern_authorship_pattern_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pattern_authorship
    ADD CONSTRAINT pattern_authorship_pattern_fkey FOREIGN KEY (pattern) REFERENCES public.patterns(id);


--
-- Name: pattern_step_applicability pattern_step_applicability_pattern_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pattern_step_applicability
    ADD CONSTRAINT pattern_step_applicability_pattern_fkey FOREIGN KEY (pattern) REFERENCES public.patterns(id);


--
-- Name: pattern_tags pattern_tags_pattern_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pattern_tags
    ADD CONSTRAINT pattern_tags_pattern_fkey FOREIGN KEY (pattern) REFERENCES public.patterns(id);


--
-- Name: scanned_patterns scanned_patterns_build_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scanned_patterns
    ADD CONSTRAINT scanned_patterns_build_fkey FOREIGN KEY (build) REFERENCES public.builds(build_num);


--
-- Name: scans scans_latest_pattern_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scans
    ADD CONSTRAINT scans_latest_pattern_id_fkey FOREIGN KEY (latest_pattern_id) REFERENCES public.patterns(id);


--
-- Name: TABLE build_steps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.build_steps TO logan;


--
-- Name: TABLE matches; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.matches TO logan;


--
-- Name: TABLE matches_for_build; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.matches_for_build TO logan;


--
-- Name: TABLE build_match_repetitions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.build_match_repetitions TO logan;


--
-- Name: TABLE patterns; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.patterns TO logan;


--
-- Name: TABLE best_pattern_match_for_builds; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.best_pattern_match_for_builds TO logan;


--
-- Name: TABLE builds; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.builds TO logan;


--
-- Name: TABLE aggregated_build_matches; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.aggregated_build_matches TO logan;


--
-- Name: TABLE log_metadata; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.log_metadata TO logan;


--
-- Name: TABLE matches_with_log_metadata; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.matches_with_log_metadata TO logan;


--
-- Name: TABLE best_pattern_match_augmented_builds; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.best_pattern_match_augmented_builds TO logan;


--
-- Name: TABLE broken_revisions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.broken_revisions TO logan;


--
-- Name: SEQUENCE broken_revisions_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.broken_revisions_id_seq TO logan;


--
-- Name: SEQUENCE build_steps_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.build_steps_id_seq TO logan;


--
-- Name: TABLE builds_join_steps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.builds_join_steps TO logan;


--
-- Name: TABLE latest_broken_revision_reports; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.latest_broken_revision_reports TO logan;


--
-- Name: TABLE builds_with_reports; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.builds_with_reports TO logan;


--
-- Name: TABLE created_github_statuses; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.created_github_statuses TO logan;


--
-- Name: TABLE idiopathic_build_failures; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.idiopathic_build_failures TO logan;


--
-- Name: TABLE job_failure_frequencies; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.job_failure_frequencies TO logan;


--
-- Name: SEQUENCE match_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.match_id_seq TO logan;


--
-- Name: TABLE pattern_authorship; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pattern_authorship TO logan;


--
-- Name: TABLE pattern_step_applicability; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pattern_step_applicability TO logan;


--
-- Name: TABLE pattern_tags; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pattern_tags TO logan;


--
-- Name: TABLE patterns_augmented; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.patterns_augmented TO logan;


--
-- Name: TABLE pattern_frequency_summary; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pattern_frequency_summary TO logan;


--
-- Name: SEQUENCE pattern_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.pattern_id_seq TO logan;


--
-- Name: SEQUENCE pattern_step_applicability_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.pattern_step_applicability_id_seq TO logan;


--
-- Name: TABLE scannable_build_steps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scannable_build_steps TO logan;


--
-- Name: TABLE scanned_patterns; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scanned_patterns TO logan;


--
-- Name: TABLE scans; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scans TO logan;


--
-- Name: SEQUENCE scans_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.scans_id_seq TO logan;


--
-- Name: TABLE unattributed_failed_builds; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.unattributed_failed_builds TO logan;


--
-- Name: TABLE unscanned_patterns; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.unscanned_patterns TO logan;


--
-- Name: TABLE unvisited_builds; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.unvisited_builds TO logan;


--
-- PostgreSQL database dump complete
--

