----------------------------------------------------------------
--                                                    2016.07.01
-- |
-- Module      :  Language.Hakaru.CodeGen.HOAS.Statement
-- Copyright   :  Copyright (c) 2016 the Hakaru team
-- License     :  BSD3
-- Maintainer  :  zsulliva@indiana.edu
-- Stability   :  experimental
-- Portability :  GHC-only
--
-- Provides tools for building C statements
--
----------------------------------------------------------------

module Language.Hakaru.CodeGen.HOAS.Statement
  ( assignS
  , assignExprS
  , exitS
  , printS
  , labelS
  , returnS

  -- control flow
  , whileS
  , doWhileS
  , forS
  , ifS
  , listOfIfsS
  , guardS
  , compoundGuardS
  , gotoS
  ) where

import Language.C.Syntax.AST
import Language.C.Data.Node
import Language.C.Data.Ident

import Language.Hakaru.CodeGen.HOAS.Expression

node :: NodeInfo
node = undefNode

assignS :: Ident -> CExpr -> CStat
assignS var expr = CExpr (Just (CAssign CAssignOp
                                        (CVar var node)
                                        expr
                                        node))
                         node

assignExprS :: CExpr -> CExpr -> CStat
assignExprS var expr = CExpr (Just (CAssign CAssignOp
                                            var
                                            expr
                                            node))
                             node
gotoS :: Ident -> CStat
gotoS i = CGoto i node

exitS :: CStat
exitS = CReturn (Just $ intConstE 0) node

printS :: String -> CStat
printS s = CExpr (Just $ printE s) node

labelS :: Ident -> CStat
labelS i = CLabel i (CCont node) [] node

returnS :: CExpr -> CStat
returnS e = CReturn (Just e) node

-- Control Flow

whileS :: CExpr -> [CStat] -> CStat
whileS b stmts = CWhile b (CCompound [] (fmap CBlockStmt stmts) node) False node

doWhileS :: CExpr -> [CStat] -> CStat
doWhileS b stmts = CWhile b (CCompound [] (fmap CBlockStmt stmts) node) True node

forS :: CExpr -> CExpr -> CExpr -> [CStat] -> CStat
forS = undefined


ifS :: CExpr -> CStat -> CStat -> CStat
ifS e thn els = CIf e thn (Just els) node

guardS :: CExpr -> CStat -> CStat
guardS e thn = CIf e thn Nothing node

compoundGuardS :: CExpr -> [CStat] -> CStat
compoundGuardS b stmts = guardS b (CCompound [] (fmap CBlockStmt stmts) node)

-- | will produce a series of if and else ifs
--   Such as:
--    if <bool> <stat>;
--    else if <bool> <stat>;
--    else if <bool> <stat>;
--    ...
listOfIfsS :: [(CExpr,CStat)] -> CStat
listOfIfsS []         = error "listOfIfsS on empty list"
listOfIfsS ((b,s):[]) = guardS b s
listOfIfsS ((b,s):xs) = ifS b s (listOfIfsS xs)
