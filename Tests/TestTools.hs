module Tests.TestTools where

import Language.Hakaru.Expect (Expect(unExpect), Expect')
import Language.Hakaru.Maple (Maple, runMaple)
import Language.Hakaru.Simplify (Simplify, Any(unAny), simplify)
import Language.Hakaru.PrettyPrint (runPrettyPrint)
import Text.PrettyPrint (render)
import Data.List

import Test.HUnit


-- assert that we get a result and that no error is thrown
assertResult :: String -> Assertion
assertResult s = assertBool "no result" $ not $ null s

assertJust :: Maybe a -> Assertion
assertJust (Just _) = assertBool "" True
assertJust Nothing  = assertBool "expected Just but got Nothing" False

testS :: (Simplify a) => Expect Maple a -> IO ()
testS t = do
    putStrLn "" -- format output better
    p <- simplify t
    let s = (render . runPrettyPrint . unAny) p
    assertResult s

testMaple :: Expect Maple a -> IO ()
testMaple t = assertResult $ runMaple (unExpect t) 0

testMapleEqual :: Expect Maple a -> Expect Maple a -> IO ()
testMapleEqual t1 t2 = do
    let r1 = rm t1
    let r2 = rm t2
    assertEqual "testMapleEqual: false" r1 r2
    where rm t = runMaple (unExpect t) 0

ignore :: a -> Assertion
ignore _ = assertFailure "ignored"  -- ignoring a test reports as a failure

-- Runs a single test from a TestList given its index
runTestI :: Test -> Int -> IO Counts
runTestI (TestList ts) i = runTestTT $ ts !! i

-- Runs a single test from a TestList given its label
runTestN :: Test -> String -> IO Counts
runTestN (TestList ts) l = case find hasLab ts of
                                Just t -> runTestTT t
                                Nothing -> runTestTT $ l ~: assertFailure $ "no test with label " ++ l
                           where hasLab (TestLabel lab _) = lab == l