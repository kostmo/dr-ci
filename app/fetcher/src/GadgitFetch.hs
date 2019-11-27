{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module GadgitFetch where

import           Control.Monad.IO.Class     (liftIO)
import           Control.Monad.Trans.Except (ExceptT (ExceptT), except,
                                             runExceptT)
import           Data.Aeson                 (FromJSON, eitherDecode,
                                             genericParseJSON, parseJSON,
                                             toJSON)
import           Data.Either.Utils          (maybeToEither)
import qualified Data.Maybe                 as Maybe
import qualified Data.Text                  as T
import           GHC.Generics
import qualified Network.HTTP.Client        as NC
import           Network.Wreq               as NW

import qualified Builds
import qualified FetchHelpers
import qualified JsonUtils


gadgitUrlPrefix :: String
gadgitUrlPrefix = "http://gadgit.pytorch.org"


-- | Note: "result" and "error" are mutually exclusive
data GadgitResponse a = GadgitResponse {
    _result  :: Maybe a
  , _success :: Bool
  , _error   :: Maybe String
  } deriving (Show, Generic)

instance (FromJSON a) => FromJSON (GadgitResponse a) where
  parseJSON = genericParseJSON JsonUtils.dropUnderscore



data PullRequestHeadAssociationInnerResponse = PullRequestHeadAssociationInnerResponse {
    _pr_number :: Builds.PullRequestNumber
  , _output    :: GadgitResponse Builds.RawCommit
  } deriving (Show, Generic)

instance FromJSON PullRequestHeadAssociationInnerResponse where
  parseJSON = genericParseJSON JsonUtils.dropUnderscore


processResult :: (a -> w) -> GadgitResponse a -> Either String w
processResult f decoded_json = if _success decoded_json
    then maybeToEither "API indicates success but has no result!" $ f <$> _result decoded_json
    else Left $ unwords [
        "Webservice error:"
      , Maybe.fromMaybe "<none>" $ _error decoded_json
      ]


-- | Handles errors on individual items
getPullRequestHeadCommitsBulk ::
     [Builds.PullRequestNumber]
  -> IO (Either String [(Builds.PullRequestNumber, Either String Builds.RawCommit)])
getPullRequestHeadCommitsBulk pr_numbers = runExceptT $ do
  response <- ExceptT $ liftIO $ FetchHelpers.safeGetUrl $
    NW.post url_string $ toJSON pr_numbers

  decoded_json <- except $ eitherDecode $ NC.responseBody response
  outer_response <- except $ processResult id decoded_json
  return $ map f outer_response
  where
    f (PullRequestHeadAssociationInnerResponse p out) = (p, processResult id out)
    url_string = gadgitUrlPrefix <> "/bulk-pull-request-heads"


getSinglePullRequestHeadCommit ::
     Builds.PullRequestNumber
  -> IO (Either String Builds.RawCommit)
getSinglePullRequestHeadCommit (Builds.PullRequestNumber pr_num) = runExceptT $ do

  response <- ExceptT $ liftIO $ FetchHelpers.safeGetUrl $ NW.get url_string
  decoded_json <- except $ eitherDecode $ NC.responseBody response
  except $ processResult Builds.RawCommit decoded_json
  where
    url_string = gadgitUrlPrefix <> "/pr-head-commit/" <> show pr_num


getContainingPRs :: Builds.RawCommit -> IO (Either String [Builds.PullRequestNumber])
getContainingPRs (Builds.RawCommit sha1) = runExceptT $ do

  response <- ExceptT $ liftIO $ FetchHelpers.safeGetUrl $ NW.get url_string
  decoded_json <- except $ eitherDecode $ NC.responseBody response
  except $ processResult (map Builds.PullRequestNumber) decoded_json

  where
    url_string = gadgitUrlPrefix <> "/head-of-pull-requests/" <> T.unpack sha1
