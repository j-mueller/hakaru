{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE EmptyCase                  #-}
{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE PolyKinds                  #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}

{-# OPTIONS_GHC -Wall -fwarn-tabs #-}
----------------------------------------------------------------
--                                                    2017.02.01
-- |
-- Module      :  Language.Hakaru.Syntax.Prune
-- Copyright   :  Copyright (c) 2016 the Hakaru team
-- License     :  BSD3
-- Maintainer  :
-- Stability   :  experimental
-- Portability :  GHC-only
--
--
----------------------------------------------------------------
module Language.Hakaru.Syntax.Prune where

import           Control.Monad.Reader
import           Data.Maybe

import           Language.Hakaru.Syntax.Unroll (rename)
import           Language.Hakaru.Syntax.ABT    hiding (rename)
import           Language.Hakaru.Syntax.AST
import           Language.Hakaru.Syntax.Variable
import           Language.Hakaru.Syntax.AST.Eq
import           Language.Hakaru.Syntax.IClasses
import           Language.Hakaru.Syntax.TypeOf
import           Language.Hakaru.Types.DataKind

-- A Simple pass for pruning the unused let bindings from an AST.

updateEnv :: forall (a :: Hakaru) . Variable a -> Variable a -> Varmap -> Varmap
updateEnv vin vout = insertAssoc (Assoc vin vout)

newtype PruneM a = PruneM { runPruneM :: Reader Varmap a }
  deriving (Functor, Applicative, Monad, MonadReader Varmap, MonadFix)

lookupEnv
  :: forall abt (a :: Hakaru)
  .  Variable a
  -> Varmap
  -> Variable a
lookupEnv v = fromMaybe v . lookupAssoc v

prune
  :: (ABT Term abt)
  => abt '[] a
  -> abt '[] a
prune = flip runReader emptyAssocs . runPruneM . prune'

prune'
  :: forall abt xs a . (ABT Term abt)
  => abt xs a
  -> PruneM (abt xs a)
prune' = loop . viewABT
  where
    loop :: forall (b :: Hakaru) ys . View (Term abt) ys b -> PruneM (abt ys b)
    loop (Var v)    = (var . lookupEnv v) `fmap` ask
    loop (Syn s)    = pruneTerm s
    loop (Bind v b) = rename v (loop b)

pruneTerm
  :: (ABT Term abt)
  => Term abt a
  -> PruneM (abt '[] a)
pruneTerm (Let_ :$ rhs :* body :* End) =
  caseBind body $ \v body' ->
  let frees     = freeVars body'
      mklet r b = syn (Let_ :$ r :* b :* End)
  in case memberVarSet v frees of
       False -> prune' body'
       True  -> mklet <$> prune' rhs <*> rename v (prune' body')

pruneTerm term = fmap syn $ traverse21 prune' term
