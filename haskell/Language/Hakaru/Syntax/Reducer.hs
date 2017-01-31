{-# LANGUAGE DataKinds
           , GADTs
           , KindSignatures
           , Rank2Types
           #-}

module Language.Hakaru.Syntax.Reducer where

import Language.Hakaru.Types.DataKind
import Language.Hakaru.Types.HClasses

data Reducer (abt :: [Hakaru] -> Hakaru -> *)
             (xs  :: [Hakaru])
             (a :: Hakaru) where
     Red_Add
         :: HSemiring a
         -> abt xs a
         -> Reducer abt xs a
     Red_Index
         :: abt xs 'HNat               -- size of resulting array
         -> abt ( 'HNat ': xs ) 'HNat  -- index into array (bound i)
         -> Reducer abt ( 'HNat ': xs) a
         -> Reducer abt xs a


