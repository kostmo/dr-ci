module MyUtils where

import           Control.Monad       (join)

import           Data.Hashable       (Hashable)
import           Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap


binTuplesByFirstAsMap :: (Eq a, Hashable a, Foldable z, Applicative t, Monoid (t b)) =>
   z (a, b) -> HashMap a (t b)
binTuplesByFirstAsMap =
  foldr (uncurry (HashMap.insertWith mappend) . fmap pure) HashMap.empty


binTuplesByFirst :: (Eq a, Hashable a) => [(a, b)] -> [(a, [b])]
binTuplesByFirst = HashMap.toList . binTuplesByFirstAsMap


-- | duplicates the argument into both members of the tuple
duple :: a -> (a, a)
duple = join (,)


-- | Given a function and a value, create a pair
-- where the first element is the value, and the
-- second element is the function applied to the value
derivePair :: (a -> b) -> a -> (a, b)
derivePair g = fmap g . duple


quote :: String -> String
quote x = "\"" <> x <> "\""