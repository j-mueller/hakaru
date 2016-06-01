{-# LANGUAGE FlexibleContexts
           , GADTs
           , Rank2Types
           , ScopedTypeVariables
           , DataKinds
           , TypeOperators
           #-}

{-# OPTIONS_GHC -Wall -fwarn-tabs #-}
---------------------------------------------------------------
module Language.Hakaru.Syntax.AST.Transforms where

import Language.Hakaru.Syntax.ABT
import Language.Hakaru.Syntax.AST
import Language.Hakaru.Syntax.TypeOf
import Language.Hakaru.Syntax.IClasses
import Language.Hakaru.Types.DataKind

import Language.Hakaru.Expect       (expect)
import Language.Hakaru.Disintegrate (determine, observe)

underLam
    :: (ABT Term abt, Monad m)
    => (abt '[] b -> m (abt '[] b))
    -> abt '[] (a ':-> b)
    -> m (abt '[] (a ':-> b))
underLam f e = caseVarSyn e (return . var) $ \t ->
                   case t of
                   Lam_ :$ e1 :* End ->
                       caseBind e1 $ \x e1' -> do
                           e1'' <- f e1'
                           return . syn $
                                  Lam_  :$ (bind x e1'' :* End)

                   Let_ :$ e1 :* e2 :* End ->
                        case jmEq1 (typeOf e1) (typeOf e) of
                          Just Refl -> do
                               e1' <- underLam f e1
                               return . syn $
                                      Let_ :$ e1' :* e2 :* End
                          Nothing   -> caseBind e2 $ \x e2' -> do
                                         e2'' <- underLam f e2'
                                         return . syn $
                                                Let_ :$ e1 :* (bind x e2'') :* End

                   _ -> error "TODO: underLam"


expandTransformations
    :: forall abt a
    . (ABT Term abt)
    => abt '[] a -> abt '[] a
expandTransformations =
    cataABT var bind alg
    where 
    alg :: forall b. Term abt b -> abt '[] b
    alg t =
        case t of
        Expect  :$ e1 :* e2 :* End -> expect  e1 e2
        Observe :$ e1 :* e2 :* End ->
          case determine (observe e1 e2) of
          Just t' -> t'
          Nothing -> syn t
        _                         -> syn t
        
