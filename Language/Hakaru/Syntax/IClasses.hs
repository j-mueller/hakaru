-- TODO: move this file somewhere else, like "Language.Hakaru.IClasses"
{-# LANGUAGE CPP
           , Rank2Types
           , PolyKinds
           , DataKinds
           , TypeOperators
           , GADTs
           , ScopedTypeVariables
           #-}
{-# OPTIONS_GHC -Wall -fwarn-tabs #-}
----------------------------------------------------------------
--                                                    2015.08.19
-- |
-- Module      :  Language.Hakaru.Syntax.IClasses
-- Copyright   :  Copyright (c) 2015 the Hakaru team
-- License     :  BSD3
-- Maintainer  :  wren@community.haskell.org
-- Stability   :  experimental
-- Portability :  GHC-only
--
-- A collection of classes generalizing standard classes in order
-- to support indexed types.
--
-- TODO: DeriveDataTypeable for all our newtypes?
----------------------------------------------------------------
module Language.Hakaru.Syntax.IClasses
    ( Lift1(..)
    , Lift2(..)
    , List1(..)
    -- * Showing indexed types
    , Show1(..), shows1, showList1
    , Show2(..), shows2, showList2
    -- ** Some more-generic helper functions
    , showListWith
    , showTuple
    -- ** some helpers for implementing the instances
    , showParen_0
    , showParen_1
    , showParen_2
    , showParen_01
    , showParen_02
    , showParen_11
    , showParen_22
    , showParen_111
    -- * Equality
    , Eq1(..)
    , Eq2(..)
    -- * Generalized abstract nonsense
    , Functor11(..)
    , Functor21(..)
    , Functor22(..)
    , Fix11(..), cata11, ana11, hylo11
    , Foldable11(..)
    , Foldable21(..)
    , Foldable22(..)
    ) where

#if __GLASGOW_HASKELL__ < 710
import Data.Monoid
#endif

----------------------------------------------------------------
-- | Any unindexed type can be lifted to be (trivially) @k@-indexed.
newtype Lift1 (a :: *) (i :: k) =
    Lift1 { unLift1 :: a }
    
newtype Lift2 (a :: *) (i :: k1) (j :: k2) =
    Lift2 { unLift2 :: a }


----------------------------------------------------------------
infixr 5 `Cons1`

-- | A list of 1-indexed elements, itself indexed by the list of indices
data List1 :: (k -> *) -> [k] -> * where
    Nil1  :: List1 a '[]
    Cons1 :: a x -> List1 a xs -> List1 a (x ': xs)

instance Show1 a => Show1 (List1 a) where
    showsPrec1 _ Nil1         = showString     "Nil1"
    showsPrec1 p (Cons1 x xs) = showParen_11 p "Cons1" x xs

instance Show1 a => Show (List1 a xs) where
    showsPrec = showsPrec1
    show      = show1

instance Eq1 a  => Eq1 (List1 a) where
    eq1 Nil1         Nil1         = True
    eq1 (Cons1 x xs) (Cons1 y ys) = eq1 x y && eq1 xs ys
    eq1 _            _            = False

instance Eq1 a  => Eq (List1 a xs) where
    (==) = eq1

instance Functor11 List1 where
    fmap11 _ Nil1         = Nil1
    fmap11 f (Cons1 x xs) = Cons1 (f x) (fmap11 f xs)

instance Foldable11 List1 where
    foldMap11 _ Nil1         = mempty
    foldMap11 f (Cons1 x xs) = f x `mappend` foldMap11 f xs

----------------------------------------------------------------
-- TODO: cf., <http://hackage.haskell.org/package/abt-0.1.1.0>
-- | Uniform variant of Show for @k@-indexed types. This differs
-- from @transformers:@'Data.Functor.Classes.Show1' in being
-- polykinded, like it ought to be.
--
-- Alas, I don't think there's any way to derive instances the way
-- we can derive for 'Show'.
class Show1 (a :: k -> *) where
    {-# MINIMAL showsPrec1 | show1 #-}

    showsPrec1 :: Int -> a i -> ShowS
    showsPrec1 _ x s = show1 x ++ s

    show1 :: a i -> String
    show1 x = shows1 x ""

shows1 :: (Show1 a) => a i -> ShowS
shows1 =  showsPrec1 0


showList1 :: Show1 a => [a i] -> ShowS
showList1 = showListWith shows1

-- This implementation taken from 'showList' in base-4.8:"GHC.Show",
-- generalizing over the showing function.
showListWith :: (a -> ShowS) -> [a] -> ShowS
showListWith f = start
    where
    start []     s = "[]" ++ s
    start (x:xs) s = '[' : f x (go xs)
        where
        go []     = ']' : s
        go (y:ys) = ',' : f y (go ys)

-- This implementation taken from 'show_tuple' in base-4.8:"GHC.Show",
-- verbatim.
showTuple :: [ShowS] -> ShowS
showTuple ss
    = showChar '('
    . foldr1 (\s r -> s . showChar ',' . r) ss
    . showChar ')'

{-
-- BUG: these require (Show (i::k)) in the class definition of Show1
instance Show1 Maybe where
    showsPrec1 = showsPrec
    show1      = show

instance Show1 [] where
    showsPrec1 = showsPrec
    show1      = show

instance Show1 ((,) a) where
    showsPrec1 = showsPrec
    show1      = show

instance Show1 (Either a) where
    showsPrec1 = showsPrec
    show1      = show
-}

instance Show a => Show1 (Lift1 a) where
    showsPrec1 p (Lift1 x) = showsPrec p x
    show1        (Lift1 x) = show x


----------------------------------------------------------------
-- TODO: how to show that @Show2 a@ implies @Show1 (a i)@ for all @i@... This is needed for 'Datum'
class Show2 (a :: k1 -> k2 -> *) where
    {-# MINIMAL showsPrec2 | show2 #-}

    showsPrec2 :: Int -> a i j -> ShowS
    showsPrec2 _ x s = show2 x ++ s

    show2 :: a i j -> String
    show2 x = shows2 x ""

shows2 :: (Show2 a) => a i j -> ShowS
shows2 =  showsPrec2 0

showList2 :: Show2 a => [a i j] -> ShowS
showList2 = showListWith shows2


instance Show a => Show2 (Lift2 a) where
    showsPrec2 p (Lift2 x) = showsPrec p x
    show2        (Lift2 x) = show x

instance Show a => Show1 (Lift2 a i) where
    showsPrec1 p (Lift2 x) = showsPrec p x
    show1        (Lift2 x) = show x

----------------------------------------------------------------
showParen_0 :: Show a => Int -> String -> a -> ShowS
showParen_0 p s e =
    showParen (p > 9)
        ( showString s
        . showString " "
        . showsPrec 11 e
        )

showParen_1 :: Show1 a => Int -> String -> a i -> ShowS
showParen_1 p s e =
    showParen (p > 9)
        ( showString s
        . showString " "
        . showsPrec1 11 e
        )

showParen_2 :: Show2 a => Int -> String -> a i j -> ShowS
showParen_2 p s e =
    showParen (p > 9)
        ( showString s
        . showString " "
        . showsPrec2 11 e
        )

showParen_01 :: (Show b, Show1 a) => Int -> String -> b -> a i -> ShowS
showParen_01 p s e1 e2 =
    showParen (p > 9)
        ( showString s
        . showString " "
        . showsPrec  11 e1
        . showString " "
        . showsPrec1 11 e2
        )
        
showParen_02 :: (Show b, Show2 a) => Int -> String -> b -> a i j -> ShowS
showParen_02 p s e1 e2 =
    showParen (p > 9)
        ( showString s
        . showString " "
        . showsPrec  11 e1
        . showString " "
        . showsPrec2 11 e2
        )

showParen_11 :: (Show1 a, Show1 b) => Int -> String -> a i -> b j -> ShowS
showParen_11 p s e1 e2 =
    showParen (p > 9)
        ( showString s
        . showString " "
        . showsPrec1 11 e1
        . showString " "
        . showsPrec1 11 e2
        )

showParen_22 :: (Show2 a, Show2 b) => Int -> String -> a i1 j1 -> b i2 j2 -> ShowS
showParen_22 p s e1 e2 =
    showParen (p > 9)
        ( showString s
        . showString " "
        . showsPrec2 11 e1
        . showString " "
        . showsPrec2 11 e2
        )

showParen_111
    :: (Show1 a, Show1 b, Show1 c)
    => Int -> String -> a i -> b j -> c k -> ShowS
showParen_111 p s e1 e2 e3 =
    showParen (p > 9)
        ( showString s
        . showString " "
        . showsPrec1 11 e1
        . showString " "
        . showsPrec1 11 e2
        . showString " "
        . showsPrec1 11 e3
        )

----------------------------------------------------------------
----------------------------------------------------------------
-- | Uniform variant of 'Eq' for @k@-indexed types. N.B., this
-- function returns term equality. We assume the indices match up.
--
-- Alas, I don't think there's any way to derive instances the way
-- we can derive for 'Eq'.
class Eq1 (a :: k -> *) where
    eq1 :: a i -> a i -> Bool

instance Eq a => Eq1 (Lift1 a) where
    eq1 (Lift1 a) (Lift1 b) = a == b

----------------------------------------------------------------
class Eq2 (a :: k1 -> k2 -> *) where
    eq2 :: a i j -> a i j -> Bool


----------------------------------------------------------------
----------------------------------------------------------------
-- | A functor on the category of @k@-indexed types (i.e., from @k@-indexed types to @k@-indexed types). We unify the two indices, because that seems the most helpful for what we're doing; we could, of course, offer a different variant that maps @k1@-indexed types to @k2@-indexed types...
--
-- Alas, I don't think there's any way to derive instances the way
-- we can derive for 'Functor'.
class Functor11 (f :: (k1 -> *) -> k2 -> *) where
    fmap11 :: (forall i. a i -> b i) -> f a j -> f b j


-- | A functor from @(k1,k2)@-indexed types to @k3@-indexed types.
class Functor21 (f :: (k1 -> k2 -> *) -> k3 -> *) where
    fmap21 :: (forall h i. a h i -> b h i) -> f a j -> f b j

-- | A functor from @(k1,k2)@-indexed types to @(k3,k4)@-indexed types.
class Functor22 (f :: (k1 -> k2 -> *) -> k3 -> k4 -> *) where
    fmap22 :: (forall h i. a h i -> b h i) -> f a j l -> f b j l


----------------------------------------------------------------
newtype Fix11 (f :: (k -> *) -> k -> *) (i :: k) =
    Fix11 { unFix11 :: f (Fix11 f) i }

cata11
    :: forall f a j
    .  (Functor11 f)
    => (forall i. f a i -> a i)
    -> Fix11 f j -> a j
cata11 alg = go
    where
    go :: forall j'. Fix11 f j' -> a j'
    go = alg . fmap11 go . unFix11

ana11
    :: forall f a j
    .  (Functor11 f)
    => (forall i. a i -> f a i)
    -> a j -> Fix11 f j
ana11 coalg = go
    where
    go :: forall j'. a j' -> Fix11 f j'
    go = Fix11 . fmap11 go . coalg

hylo11
    :: forall f a b j
    .  (Functor11 f)
    => (forall i. a i -> f a i)
    -> (forall i. f b i -> b i)
    -> a j
    -> b j
hylo11 coalg alg = go
    where
    go :: forall j'. a j' -> b j'
    go = alg . fmap11 go . coalg

-- TODO: a tracing evaluator: <http://www.timphilipwilliams.com/posts/2013-01-16-fixing-gadts.html>


----------------------------------------------------------------
-- TODO: in theory we could define some Monoid1 class to avoid the
-- explicit dependency on Lift1 in fold1's type. But we'd need that
-- Monoid1 class to have some sort of notion of combining things
-- at different indices...

-- | A foldable functor on the category of @k@-indexed types.
--
-- Alas, I don't think there's any way to derive instances the way
-- we can derive for 'Foldable'.
class Functor11 f => Foldable11 (f :: (k1 -> *) -> k2 -> *) where
    {-# MINIMAL fold11 | foldMap11 #-}

    fold11 :: (Monoid m) => f (Lift1 m) i -> m
    fold11 = foldMap11 unLift1

    foldMap11 :: (Monoid m) => (forall i. a i -> m) -> f a j -> m
    foldMap11 f = fold11 . fmap11 (Lift1 . f)

-- TODO: standard Foldable wrappers 'and11', 'or11', 'all11', 'any11',...



class Functor21 f => Foldable21 (f :: (k1 -> k2 -> *) -> k3 -> *) where
    {-# MINIMAL fold21 | foldMap21 #-}

    fold21 :: (Monoid m) => f (Lift2 m) j -> m
    fold21 = foldMap21 unLift2

    foldMap21 :: (Monoid m) => (forall h i. a h i -> m) -> f a j -> m
    foldMap21 f = fold21 . fmap21 (Lift2 . f)
    

class Functor22 f
    =>
    Foldable22 (f :: (k1 -> k2 -> *) -> k3 -> k4 -> *)
    where
    {-# MINIMAL fold22 | foldMap22 #-}

    fold22 :: (Monoid m) => f (Lift2 m) j l -> m
    fold22 = foldMap22 unLift2

    foldMap22 :: (Monoid m) => (forall h i. a h i -> m) -> f a j l -> m
    foldMap22 f = fold22 . fmap22 (Lift2 . f)

----------------------------------------------------------------
----------------------------------------------------------- fin.
