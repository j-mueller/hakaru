{-# LANGUAGE ScopedTypeVariables
           , GADTs
           , DeriveDataTypeable
           , DataKinds
           , PolyKinds
           #-}

{-# OPTIONS_GHC -Wall -fwarn-tabs #-}
----------------------------------------------------------------
--                                                    2015.06.28
-- |
-- Module      :  Language.Hakaru.Syntax.ABT
-- Copyright   :  Copyright (c) 2015 the Hakaru team
-- License     :  BSD3
-- Maintainer  :  wren@community.haskell.org
-- Stability   :  experimental
-- Portability :  GHC-only
--
-- The interface for abstract binding trees. Given the generating
-- functor 'AST': the non-recursive 'View' type extends 'AST' by
-- adding variables and binding; and each 'ABT' type  (1) provides
-- some additional annotations at each recursion site, and then (2)
-- ties the knot to produce the recursive trees.
--
-- TODO: simultaneous multiple substitution
----------------------------------------------------------------
module Language.Hakaru.Syntax.ABT
    (
    -- * Our basic notion of variables\/names.
      Variable(..)
    , varHint
    , varId
    -- * The abstract binding tree interface
    -- See note about exposing 'View', 'viewABT', and 'unviewABT'
    , View(..), unviewABT
    , ABT(..), caseVarSynABT
    , subst
    , ABTException(..)
    -- ** Some ABT instances
    , TrivialABT()
    , FreeVarsABT()
    ) where

import           Data.Typeable     (Typeable)
import           Data.Set          (Set)
import qualified Data.Set          as Set
import           Data.Function     (on)
import           Data.Monoid
import           Control.Exception (Exception, throw)

import Language.Hakaru.Syntax.IClasses
import Language.Hakaru.Syntax.DataKind
import Language.Hakaru.Syntax.TypeEq (Sing, SingI, toSing, TypeEq(Refl), jmEq)
import Language.Hakaru.Syntax.AST

----------------------------------------------------------------
----------------------------------------------------------------
-- TODO: actually define 'Variable' as something legit
-- TODO: maybe have @Variable a@ instead, with @SomeVariable@ to package up the existential?
-- N.B., This is lazy in its components!
-- TODO: finish combining the \"fast circular substitution\" pearl with the ABT framework.
-- <http://comonad.com/reader/2014/fast-circular-substitution/>
data Variable = Variable String Int
    deriving (Read, Show)

-- | Project out the string the user suggested as a name for the variable.
varHint :: Variable -> String
varHint (Variable n _) = n

-- | Project out the unique identifier for the variable.
varId :: Variable -> Int
varId (Variable _ i) = i

instance Eq Variable where
    (==) = (==) `on` varId

instance Ord Variable where
    compare = compare `on` varId

-- | Generate a new variable with the same hint as the old one.
-- N.B., the new variable is not guaranteed to be fresh! To do that,
-- we'd need some sort of name supply, and thus would need to be
-- monadic.
prime :: Variable -> Variable
prime (Variable n i) = Variable n (i + 1)

----------------------------------------------------------------
-- TODO: go back to the name \"Abs\"(traction), and figure out some
-- other name for the \"Abs\"(olute value) PrimOp to avoid conflict.
-- Or maybe call it \"Bind\"(er) and then come up with some other
-- name for the HMeasure monadic bind operator?
-- <http://semantic-domain.blogspot.co.uk/2015/03/abstract-binding-trees.html>
--
-- <http://semantic-domain.blogspot.co.uk/2015/03/abstract-binding-trees-addendum.html>
-- <https://gist.github.com/neel-krishnaswami/834b892327271e348f79>
-- TODO: abstract over 'AST' like neelk does for @signature@?
-- TODO: remove the proxy type for 'Var', and infer it instead?
-- TODO: distinguish between free and bound variables, a~la Locally
-- Nameless? also cf., <http://hackage.haskell.org/package/abt>
--
-- | The raw view of abstract binding trees, to separate out variables
-- and binders from (1) the rest of syntax (cf., 'AST'), and (2)
-- whatever annotations (cf., the 'ABT' instances).
--
-- HACK: We only want to expose the patterns generated by this type,
-- not the constructors themselves. That way, callers must use the
-- smart constructors of the ABT class.
--
-- BUG: if we don't expose this type, then clients can't define
-- their own ABT instances (without reinventing their own copy of
-- this type)...
data View :: (Hakaru * -> *) -> Hakaru * -> * where

    Syn  :: !(AST abt a) -> View abt a

    -- TODO: what are the overhead costs of storing a Sing? Would
    -- it be cheaper to store the SingI dictionary (and a Proxy,
    -- as necessary)?
    Var  :: {-# UNPACK #-} !Variable -> !(Sing a) -> View abt a

    -- N.B., this constructor is recursive, thus minimizing the
    -- memory overhead of whatever annotations our ABT stores (we
    -- only annotate once, at the top of a chaing of 'Open's, rather
    -- than before each one). However, in the 'ABT' class, we provide
    -- an API as if things went straight back to @abt@. Doing so
    -- requires that 'caseOpenABT' is part of the class so that we
    -- can push whatever annotations down over one single level of
    -- 'Open', rather than pushing over all of them at once and
    -- then needing to reconstruct all but the first one.
    Open :: {-# UNPACK #-} !Variable -> View abt a -> View abt a


instance Functor1 View where
    fmap1 f (Syn  t)   = Syn (fmap1 f t)
    fmap1 _ (Var  x p) = Var  x p
    fmap1 f (Open x e) = Open x (fmap1 f e)


instance Show1 abt => Show1 (View abt) where
    showsPrec1 p (Syn t) =
        showParen (p > 9)
            ( showString "Syn "
            . showsPrec1 11 t
            )
    showsPrec1 p (Var x s) =
        showParen (p > 9)
            ( showString "Var "
            . showsPrec  11 x
            . showString " "
            . showsPrec  11 s
            )
    showsPrec1 p (Open x e) =
        showParen (p > 9)
            ( showString "Open "
            . showsPrec  11 x
            . showString " "
            . showsPrec1 11 e
            )

instance Show1 abt => Show (View abt a) where
    showsPrec = showsPrec1
    show      = show1


-- TODO: neelk includes 'subst' in the signature. Any reason we should?
class ABT (abt :: Hakaru * -> *) where
    syn      :: AST abt a          -> abt a
    var      :: Variable -> Sing a -> abt a
    open     :: Variable -> abt  a -> abt a

    -- | Assume the ABT is 'Open' and then project out the components.
    -- If the ABT is not 'Open', then this function will throw an
    -- 'ExpectedOpenException' error.
    caseOpenABT :: abt a -> (Variable -> abt a -> r) -> r

    -- See note about exposing 'View', 'viewABT', and 'unviewABT'.
    -- We could replace 'viewABT' with a case-elimination version...
    viewABT  :: abt a -> View abt a

    freeVars :: abt a -> Set Variable
    -- TODO: add a function for checking alpha-equivalence? Other stuff?
    -- TODO: does it make sense ot have the functions for generating fresh variable names here? or does that belong in a separate class?


-- See note about exposing 'View', 'viewABT', and 'unviewABT'
unviewABT :: (ABT abt) => View abt a -> abt a
unviewABT (Syn  t)   = syn  t
unviewABT (Var  x p) = var  x p
unviewABT (Open x v) = open x (unviewABT v)


data ABTException
    = ExpectedOpenException
    | ExpectedVarSynException
    | SubstitutionTypeError
    deriving (Show, Typeable)

instance Exception ABTException


-- | Assume the ABT is not 'Open' and then project out the components.
-- If the ABT is in fact 'Open', then this function will throw an
-- 'ExpectedVarSynException' error.
caseVarSynABT
    :: (ABT abt)
    => abt a
    -> (Variable -> Sing a -> r)
    -> (AST abt a          -> r)
    -> r
caseVarSynABT e var_ syn_ =
    case viewABT e of
    Syn  t   -> syn_ t
    Var  x p -> var_ x p
    Open _ _ -> throw ExpectedVarSynException -- TODO: add call-site info


----------------------------------------------------------------
-- A trivial ABT with no annotations
newtype TrivialABT (a :: Hakaru *) =
    TrivialABT { unTrivialABT :: View TrivialABT a }

instance ABT TrivialABT where
    syn  t                = TrivialABT (Syn  t)
    var  x p              = TrivialABT (Var  x p)
    open x (TrivialABT v) = TrivialABT (Open x v)

    caseOpenABT (TrivialABT v) k =
        case v of
        Open x v' -> k x (TrivialABT v')
        _         -> throw ExpectedOpenException -- TODO: add info about the call-site

    viewABT (TrivialABT v) = v

    -- This is very expensive! use 'FreeVarsABT' to fix that
    freeVars = go . unTrivialABT
        where
        go (Syn  t)   = foldMap1 freeVars t
        go (Var  x _) = Set.singleton x
        go (Open x v) = Set.delete x (go v)


instance Show1 TrivialABT where
    {-
    -- Print the concrete data constructors:
    showsPrec1 p (TrivialABT v) =
        showParen (p > 9)
            ( showString "TrivialABT "
            . showsPrec1 11 v
            )
    -}
    -- Do something a bit prettier. (Because we print the smart
    -- constructors, this output can also be cut-and-pasted to work
    -- for any ABT instance.)
    showsPrec1 p (TrivialABT (Syn t)) =
        showParen (p > 9)
            ( showString "syn "
            . showsPrec1 11 t
            )
    showsPrec1 p (TrivialABT (Var x s)) =
        showParen (p > 9)
            ( showString "var "
            . showsPrec  11 x
            . showString " "
            . showsPrec  11 s
            )
    showsPrec1 p (TrivialABT (Open x v)) =
        showParen (p > 9)
            ( showString "open "
            . showsPrec  11 x
            . showString " "
            . showsPrec1 11 (TrivialABT v) -- HACK: use caseOpenABT
            )

instance Show (TrivialABT a) where
    showsPrec = showsPrec1
    show      = show1

----------------------------------------------------------------
-- TODO: replace @Set Variable@ with @Map Variable (Hakaru Star)@;
-- though that belongs more in the type-checking than in this
-- FreeVarsABT itself...
-- TODO: generalize this pattern for any monoidal annotation?
--
-- | An ABT which keeps track of free variables.
data FreeVarsABT (a :: Hakaru *)
    = FreeVarsABT !(Set Variable) !(View FreeVarsABT a)
    -- N.B., Set is a monoid with {Set.empty; Set.union; Set.unions}
    -- For a lot of code, the other component ordering would be
    -- nicer; but this ordering gives a more intelligible Show instance.

instance ABT FreeVarsABT where
    syn  t                    = FreeVarsABT (foldMap1 freeVars t) (Syn  t)
    var  x p                  = FreeVarsABT (Set.singleton x)     (Var  x p)
    open x (FreeVarsABT xs v) = FreeVarsABT (Set.delete x xs)     (Open x v)

    caseOpenABT (FreeVarsABT xs v) k =
        case v of
        Open x v' -> k x (FreeVarsABT (Set.insert x xs) v')
        _         -> throw ExpectedOpenException -- TODO: add info about the call-site

    viewABT  (FreeVarsABT _  v) = v

    freeVars (FreeVarsABT xs _) = xs


instance Show1 FreeVarsABT where
    showsPrec1 p (FreeVarsABT xs v) =
        showParen (p > 9)
            ( showString "FreeVarsABT "
            . showsPrec  11 xs
            . showString " "
            . showsPrec1 11 v
            )

instance Show (FreeVarsABT a) where
    showsPrec = showsPrec1
    show      = show1

----------------------------------------------------------------
----------------------------------------------------------------
-- TODO: something smarter
freshen :: Variable -> Set Variable -> Variable
freshen x xs
    | x `Set.member` xs = freshen (prime x) xs
    | otherwise         = x

-- | Rename a free variable. Does nothing if the variable is bound.
rename :: forall abt a. (ABT abt) => Variable -> Variable -> abt a -> abt a
rename x y = start
    where
    start :: forall b. abt b -> abt b
    start e = loop e (viewABT e)

    loop :: forall b. abt b -> View abt b -> abt b
    loop _ (Syn t)  = syn (fmap1 start t)
    loop e (Var z p)
        | x == z    = var y p
        | otherwise = e
    loop e (Open z v)
        | x == z    = e
        | otherwise = open z (loop (caseOpenABT e $ const id) v)


-- N.B., this /is/ guaranteed to preserve type safety— provided it doesn't throw an exception.
subst
    :: forall abt a b
    .  (SingI a, ABT abt)
    => Variable
    -> abt a
    -> abt b
    -> abt b
subst x e = start
    where
    start :: forall c. abt c -> abt c
    start f = loop f (viewABT f)

    loop :: forall c. abt c -> View abt c -> abt c
    loop _ (Syn t)    = syn (fmap1 start t)
    loop f (Var z p)
        | x == z      =
            case jmEq p (toSing e) of
            Just Refl -> e
            Nothing   -> throw SubstitutionTypeError
        | otherwise   = f
    loop f (Open z _)
        | x == z      = f
        | otherwise   =
            let z' = freshen z (freeVars e `mappend` freeVars f) in
            -- HACK: using 'caseOpenABT' is redundant, it just pushes the annotations down over \"@Open z@\" and onto the @v@
            -- HACK: how much work is wasted by using 'viewABT' to eliminate the annotations after renaming?
            caseOpenABT f $ \_ f' ->
                open z' (loop f' . viewABT $ rename z z' f')

----------------------------------------------------------------
----------------------------------------------------------- fin.
