{-# LANGUAGE NumDecimals       #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module Test.Machine.Evaluate (tests) where

-- TODO: Important tests to add:
--   - Only case does evaluation
--   - Don't forget to add the variables closed over in let(rec)
--   - Primops can only be applied to primitive ints, not int-valued variables.
--     For example, `add2 = () \n (x,y) -> +# x y` is wrong: unboxing-boxing
--     needs to be done.

import           Data.Monoid
import           Data.Text
import qualified Data.Text                as T
import           Test.Tasty
import           Test.Tasty.HUnit

import           Stg.Language
import           Stg.Language.Prettyprint
import           Stg.Machine
import           Stg.Machine.Env
import           Stg.Machine.Heap         as H
import           Stg.Machine.Types
import           Stg.Parser

import           Test.Orphans.Machine     ()



tests :: TestTree
tests = testGroup "Evaluate"
    [ testGroup "Closure reduction"
        [ testGroup "Function application"
            [ funcapp_simple ]
        , testGroup "Default-only case"
            [ defaultOnlyCase_unboundAlgebraic
            , defaultOnlyCase_boundAlgebraic
            , defaultOnlyCase_unboundPrimitive
            , defaultOnlyCase_boundPrimitive ]
        , testGroup "Algebraic case"
            [ algebraicCase_normalMatch
            , algebraicCase_defaultUnboundMatch
            , algebraicCase_defaultBoundMatch ]
        , testGroup "Primitive case"
            [ primitiveCase_normalMatch
            , primitiveCase_defaultUnboundMatch
            , primitiveCase_defaultBoundMatch
            ]
        , testGroup "Let"
            [ letBinding
            , letrecBinding
            , letMultiBinding
            , letNestedBinding
            , letrecMultiBinding ]
        , testGroup "Primitive functions"
            [ addition ]
        , testGroup "Programs"
            [ program_add3
            , program_foldrSum ]
        ]
    ]

defaultOnlyCase_unboundAlgebraic :: TestTree
defaultOnlyCase_unboundAlgebraic = closureReductionTest defClosureReductionSpec
    { testName = "Unbound, algebraic scrutinee"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> case x () of
            default -> x ();
        x = () \n () -> Success ()
        |] }

defaultOnlyCase_boundAlgebraic :: TestTree
defaultOnlyCase_boundAlgebraic = closureReductionTest defClosureReductionSpec
    { testName = "Bound, algebraic scrutinee"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> case x () of
            x -> x ();
        x = () \n () -> Success ()
        |] }

defaultOnlyCase_unboundPrimitive :: TestTree
defaultOnlyCase_unboundPrimitive = closureReductionTest defClosureReductionSpec
    { testName = "Unbound, primitive scrutinee"
    , successPredicate = "main" ==> [stg| () \n () -> 1# |]
    , source = [stg|
        main = () \u () -> case x () of
            default -> x ();
        x = () \n () -> 1#
        |] }

defaultOnlyCase_boundPrimitive :: TestTree
defaultOnlyCase_boundPrimitive = closureReductionTest defClosureReductionSpec
    { testName = "Bound, primitive scrutinee"
    , successPredicate = "main" ==> [stg| () \n () -> 1# |]
    , source = [stg|
        main = () \u () -> case x () of
            x -> x ();
        x = () \n () -> 1#
        |] }

algebraicCase_normalMatch :: TestTree
algebraicCase_normalMatch = closureReductionTest defClosureReductionSpec
    { testName = "Successful"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> case Nothing () of
            Nothing () -> Success ();
            default    -> TestFail ()
        |] }

algebraicCase_defaultUnboundMatch :: TestTree
algebraicCase_defaultUnboundMatch = closureReductionTest defClosureReductionSpec
    { testName = "Unbound default"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> case Nothing () of
            Just (x) -> TestFail ();
            default  -> Success ()
        |] }

algebraicCase_defaultBoundMatch :: TestTree
algebraicCase_defaultBoundMatch = closureReductionTest defClosureReductionSpec
    { testName = "Bound default"
    , successPredicate = "main" ==> [stg| () \n () -> Nothing () |]
    , source = [stg|
        main = () \u () -> case Nothing () of
            Just (x) -> TestFail ();
            v -> v ()

        |] }

primitiveCase_normalMatch :: TestTree
primitiveCase_normalMatch = closureReductionTest defClosureReductionSpec
    { testName = "Successful"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> case 1# of
            1#      -> Success ();
            default -> TestFail ()
        |] }

primitiveCase_defaultUnboundMatch :: TestTree
primitiveCase_defaultUnboundMatch = closureReductionTest defClosureReductionSpec
    { testName = "Unbound default"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> case 1# of
            0#      -> TestFail ();
            123#    -> TestFail ();
            default -> Success ()
        |] }

primitiveCase_defaultBoundMatch :: TestTree
primitiveCase_defaultBoundMatch = closureReductionTest defClosureReductionSpec
    { testName = "Bound default"
    , successPredicate = "main" ==> [stg| () \n () -> 1# |]
    , source = [stg|
        main = () \u () -> case 1# of
            0#   -> TestFail ();
            123# -> TestFail ();
            x    -> x ()
        |] }

letBinding :: TestTree
letBinding = closureReductionTest defClosureReductionSpec
    { testName = "let with a single binding"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> let x = () \n () -> Success ()
                           in x ()
        |] }

letrecBinding :: TestTree
letrecBinding = closureReductionTest defClosureReductionSpec
    { testName = "letrec with a single binding"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> letrec x = () \n () -> Success ()
                           in x ()
        |] }

letMultiBinding :: TestTree
letMultiBinding = closureReductionTest defClosureReductionSpec
    { testName = "let with two bindings"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () ->
            let id = () \n (x) -> x ();
                one = () \n () -> Int (1#)
            in case id (one) of
                Int (y) -> case y () of
                    1# -> Success ();
                    wrong -> TestFail (wrong);
                default -> Error ()
        |] }

letNestedBinding :: TestTree
letNestedBinding = closureReductionTest defClosureReductionSpec
    { testName = "let with nested bindings"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () ->
            let id = () \n (x) -> x ();
                one = () \n () -> Int (1#)
            in let idOne = (id, one) \n () -> case id (one) of
                          v -> v ()
               in case idOne () of
                   Int (y) -> case y () of
                       1# -> Success ();
                       wrong -> TestFail (wrong);
                   default -> Error ()
        |] }

letrecMultiBinding :: TestTree
letrecMultiBinding = closureReductionTest defClosureReductionSpec
    { testName = "letrec with nested bindings"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> letrec id = () \n (x) -> x ();
                                  idOne = (id, one) \n () -> case id (one) of
                                      v -> v ();
                                  one = () \n () -> Int (1#)
                           in case idOne () of
                               Int (y) -> case y () of
                                   1# -> Success ();
                                   default -> TestFail ();
                               default -> Error ()
        |] }

addition :: TestTree
addition = closureReductionTest defClosureReductionSpec
    { testName = "Adding numbers"
    , successPredicate = "main" ==> [stg| () \n () -> 3# |]
    , source = [stg|
        add = () \n (x, y) -> case +# x y of
            v -> Int (v);
        main = () \u () -> add (1#, 2#)
        |] }

funcapp_simple :: TestTree
funcapp_simple = closureReductionTest defClosureReductionSpec
    { testName = "Simple function application"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , source = [stg|
        main = () \u () -> case id (unit) of
            Unit () -> Success ();
            default -> TestFail ();
        id = () \n (x) -> x ();
        unit = () \n () -> Unit ()
        |] }

program_add3 :: TestTree
program_add3 = closureReductionTest defClosureReductionSpec
    { testName = "add3(x,y,z) = x+y+z"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , maxSteps = 100
    , source = [stg|
        add3 = () \n (x,y,z) -> case x () of
            Int (i) -> case y () of
                Int (j) -> case +# i j of
                    12345# -> 1#; -- type hint FIXME
                    ij -> case z () of
                        Int (k) -> case +# ij k of
                            12345# -> 1#; -- type hint FIXME
                            ijk -> Int (ijk);
                        default -> Error ()
                default -> Error ()
            default -> Error ();

        one   = () \n () -> Int (1#);
        two   = () \n () -> Int (2#);
        three = () \n () -> Int (3#);
        main = () \u () -> case add3 (one, two, three) of
            Int (i) -> case i () of
                6# -> Success ();
                wrongResult -> TestFail (wrongResult);
            default -> Error ()
        |] }

program_foldrSum :: TestTree
program_foldrSum = closureReductionTest defClosureReductionSpec
    { testName = "Sum of list via foldr"
    , successPredicate = "main" ==> [stg| () \n () -> Success () |]
    , maxSteps = 128
    , source = [stg|
        foldr = () \n (f, z, xs) -> case xs () of
            Nil () -> z ();
            Cons (y,ys) ->
                let rest = (f,z,ys) \n () -> foldr (f,z,ys)
                in f (y, rest);
            default -> Error ();

        add2 = () \n (x,y) -> case x () of
            Int (x') -> case y () of
                Int (y') -> case +# x' y' of
                    1# -> Int (1#); -- FIXME type hint
                    v -> Int (v);
                default -> Error ();
            default -> Error ();

        zero = () \n () -> Int (0#);

        sum = () \n (xs) -> foldr (add2, zero, xs);

        cons = () \n (x,xs) -> Cons (x,xs);
        nil = () \n () -> Nil ();
        list = () \u () ->
            letrec one   = () \n () -> Int (1#);
                   two   = () \n () -> Int (2#);
                   three = () \n () -> Int (3#);
                   list3    = (three)          \n () -> cons (three, nil);
                   list23   = (two, list3)     \n () -> cons (two,   list3);
                   list123  = (one, list23)    \n () -> cons (one,   list23);
                   list3123 = (three, list123) \n () -> cons (three, list123)
            in list3123 ();

        main = () \u () -> case sum (list) of
            Int (i) -> case i () of
                9# -> Success ();
                wrongResult -> TestFail (wrongResult);
            default -> Error ()
        |] }


-- | Specifies a test that is based on the reduction of a closure.
data ClosureReductionSpec = ClosureReductionSpec
    { testName         :: Text
        -- ^ Test name to display in the test overview.

    , successPredicate :: StgState -> Bool
        -- ^ Test predicate to determine whether the desired state has been
        -- reached.

    , source           :: Program
        -- ^ STG program to run.

    , maxSteps         :: Integer
        -- ^ Maximum number of steps to take
    }

defClosureReductionSpec :: ClosureReductionSpec
defClosureReductionSpec = ClosureReductionSpec
    { testName = "Default closure reduction test template"
    , successPredicate = const True
    , source = [stg| main = () \n () -> Unit () |]
    , maxSteps = 32 }

-- | Evaluate the @main@ closure of a STG program, and check whether the
-- machine state satisfies a predicate when it is evaluated.
closureReductionTest :: ClosureReductionSpec -> TestTree
closureReductionTest testSpec = testCase (T.unpack (testName testSpec)) test
  where
    program = initialState "main" (source testSpec)
    finalState = evalUntil (maxSteps testSpec) (successPredicate testSpec) program
    test = case stgInfo finalState of
        HaltedByPredicate -> pure ()
        _otherwise -> (assertFailure . T.unpack . T.unlines)
            [ "STG failed to satisfy predicate: "
                <> prettyprintAnsi (stgInfo finalState)
            , "Final state:"
            , prettyprintAnsi finalState ]

-- | Build a state predicate that asserts that a certain 'Var' maps to
-- a 'LambdaForm' in the heap.
(==>) :: Var -> LambdaForm -> StgState -> Bool
var ==> lambdaForm = \state -> case varLookup state var of
    VarLookupClosure (Closure lf _) -> lf == lambdaForm
    _otherwise                      -> False

-- | Used as the result of 'varLookup'.
data VarLookupResult =
      VarLookupError Text
    | VarLookupPrim Integer
    | VarLookupClosure Closure
    deriving (Eq, Ord, Show)

-- | Look up the value of a 'Var' on the 'Heap' of a 'StgState'.
varLookup :: StgState -> Var -> VarLookupResult
varLookup state var =
    case globalVal (stgGlobals state) var of
        Nothing -> VarLookupError "not found in globals"
        Just (Addr addr) -> case H.lookup addr (stgHeap state) of
            Just closure -> VarLookupClosure closure
            Nothing -> VarLookupError "not found on heap"
        Just (PrimInt i) -> VarLookupPrim i
