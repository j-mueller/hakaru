{-# LANGUAGE DataKinds,
             FlexibleContexts,
             GADTs,
             KindSignatures #-}

----------------------------------------------------------------
--                                                    2016.07.01
-- |
-- Module      :  Language.Hakaru.CodeGen.HOAS.Expression
-- Copyright   :  Copyright (c) 2016 the Hakaru team
-- License     :  BSD3
-- Maintainer  :  zsulliva@indiana.edu
-- Stability   :  experimental
-- Portability :  GHC-only
--
--   HOAS provides a higher order abstract syntax for building
-- C ASTs
--
----------------------------------------------------------------

module Language.Hakaru.CodeGen.HOAS.Expression
  ( -- math.h functions
    log1p
  , log
  , expm1
  , exp
  , sqrt

  -- memory operations
  , malloc
  , free

  , rand
  , sizeof

  , castE
  , condE

  , constExpr
  , intConstE
  , floatConstE
  , (^>)
  , (^<)
  , (^==)
  , (^||)
  , (^&&)
  , (^*)
  , (^/)
  , (^-)
  , (^+)

  , varE
  , memberE
  , (^!)
  , stringE
  , stringVarE
  , nullaryE
  , unaryE
  , printE
  , binaryOp
  ) where

import Language.Hakaru.Syntax.AST
import Language.Hakaru.Types.HClasses

import Language.C.Data.Ident
import Language.C.Data.Node
import Language.C.Syntax.Constants
import Language.C.Syntax.AST

import Prelude hiding (log,exp,sqrt)

node :: NodeInfo
node = undefNode

constExpr :: CConstant NodeInfo -> CExpr
constExpr = CConst

stringE :: String -> CExpr
stringE x = constExpr $ CStrConst (cString x) node

unaryE :: String -> CExpr -> CExpr
unaryE s x = CCall (CVar (builtinIdent s) node) [x] node

nullaryE :: String -> CExpr
nullaryE s = CCall (CVar (builtinIdent s) node) [] node

rand :: CExpr
rand = nullaryE "rand"

printE :: String -> CExpr
printE s = unaryE "printf" (stringE s)

log1p,log,expm1,exp,sqrt,malloc,free,sizeof
  :: CExpr -> CExpr
log1p  = unaryE "log1p"
log    = unaryE "log"
expm1  = unaryE "expm1"
exp    = unaryE "exp"
sqrt   = unaryE "sqrt"
malloc = unaryE "malloc"
free   = unaryE "free"
sizeof = unaryE "sizeof"

stringVarE :: String -> CExpr
stringVarE s = CVar (builtinIdent s) node

varE :: Ident -> CExpr
varE x = CVar x node

(^<),(^>),(^==),(^||),(^&&),(^*),(^/),(^-),(^+)
  :: CExpr -> CExpr -> CExpr
a ^< b  = CBinary CLeOp a b node
a ^> b  = CBinary CGrOp a b node
a ^== b = CBinary CEqOp a b node
a ^|| b = CBinary CLorOp a b node
a ^&& b = CBinary CAndOp a b node
a ^* b  = CBinary CMulOp a b node
a ^/ b  = CBinary CDivOp a b node
a ^- b  = CBinary CSubOp a b node
a ^+ b  = CBinary CAddOp a b node

intConstE :: Integer -> CExpr
intConstE x = constExpr $ CIntConst (cInteger x) node

floatConstE :: Float -> CExpr
floatConstE x = constExpr $ CFloatConst (cFloat x) node

binaryOp :: NaryOp a -> CExpr -> CExpr -> CExpr
binaryOp (Sum HSemiring_Prob)  a b = CBinary CAddOp (exp a) (exp b) node
binaryOp (Prod HSemiring_Prob) a b = CBinary CAddOp a b node
binaryOp (Sum _)               a b = CBinary CAddOp a b node
binaryOp (Prod _)              a b = CBinary CMulOp a b node


castE :: CTypeSpec -> CExpr -> CExpr
castE t e = CCast (CDecl [CTypeSpec t] [] node) e node

condE :: CExpr -> CExpr -> CExpr -> CExpr
condE cond thn els = CCond cond (Just thn) els node

memberE :: CExpr -> Ident -> CExpr
memberE var ident = CMember var ident False node

-- infix memberE
(^!) :: CExpr -> Ident -> CExpr
(^!) = memberE
