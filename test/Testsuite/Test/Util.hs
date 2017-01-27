{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

-- | Various testing utilities.
module Test.Util (
    scaled,
    allEnums,
    arbitrary0,
    arbitrary1,
    arbitrary2,
    arbitrary3,

    (==*==),
) where



import Data.Ratio
import Data.Text.Prettyprint.Doc

import Test.QuickCheck
import Test.UtilTH



-- | Scale the size parameter of a Quickcheck generator by a 'Ratio'. Useful
-- to implement exponential cutoff for recursive generators.
scaled
    :: Ratio Int
    -> Gen a
    -> Gen a
scaled factor = scale (\n -> n * numerator factor `quot` denominator factor)

allEnums :: (Enum a, Bounded a) => Gen a
allEnums = elements [minBound ..]

$(arbitraryN 0)
$(arbitraryN 1)
$(arbitraryN 2)
$(arbitraryN 3)

infix 4 ==*==
(==*==) :: (Eq a, Pretty a) => a -> a -> Property
x ==*== y = counterexample example (x == y)
  where
    example = (show . align . vsep) [pretty x, "is not equal to", pretty y]
