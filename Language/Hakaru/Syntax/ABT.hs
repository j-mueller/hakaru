{-# LANGUAGE CPP
           , ScopedTypeVariables
           , GADTs
           , DeriveDataTypeable
           , DataKinds
           , PolyKinds
           , TypeOperators
           #-}

{-# OPTIONS_GHC -Wall -fwarn-tabs #-}
----------------------------------------------------------------
--                                                    2015.07.04
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
-- adding variables and binding; and each 'ABT' type (1) provides
-- some additional annotations at each recursion site, and then (2)
-- ties the knot to produce the recursive trees. For an introduction
-- to this technique\/approach, see:
--
--    * <http://semantic-domain.blogspot.co.uk/2015/03/abstract-binding-trees.html>
--
--    * <http://semantic-domain.blogspot.co.uk/2015/03/abstract-binding-trees-addendum.html>
--
-- TODO: simultaneous multiple substitution
----------------------------------------------------------------
module Language.Hakaru.Syntax.ABT
    (
    -- * Our basic notion of variables\/names.
      Variable(..)
    , varName
    , varID
    -- * The abstract binding tree interface
    , ABTException(..)
    -- See note about exposing 'View', 'viewABT', and 'unviewABT'
    , View(..)
    , unviewABT
    , ABT(..)
    , caseVarSyn
    , isBind
    -- ** Capture avoiding substitution for any 'ABT'
    , subst
    -- ** Constructing first-order trees with a HOAS-like API
    -- cf., <http://comonad.com/reader/2014/fast-circular-substitution/>
    , maxBind
    , binder
    -- *** Highly experimental
    , List1(..)
    , Hint(..)
    , multibinder
    -- ** Some ABT instances
    , TrivialABT()
    , FreeVarsABT()
    ) where

import           Data.Typeable     (Typeable)
import           Data.Text         (Text)
import           Data.Sequence     (Seq)
import           Data.Set          (Set)
import qualified Data.Set          as Set
import           Data.Function     (on)
import qualified Data.Foldable     as F
#if __GLASGOW_HASKELL__ < 710
import           Data.Monoid
#endif
import           Control.Exception (Exception, throw)

import Language.Hakaru.Syntax.Nat
import Language.Hakaru.Syntax.IClasses
import Language.Hakaru.Syntax.DataKind
import Language.Hakaru.Syntax.TypeEq
import Language.Hakaru.Syntax.AST

----------------------------------------------------------------
----------------------------------------------------------------
-- TODO: actually define 'Variable' as something legit
-- TODO: should we make this type abstract?
--
-- TODO: maybe have @Variable a@ instead, with @SomeVariable@ to
-- package up the existential?
--
-- TODO: we may want to parameterize ABTs over their implementation
-- of Variable, so that we can use strict\/unpacked Nats everywhere
-- once we're done building the tree with 'binder'... Or, since we
-- unpack Variable in View, maybe it'd be better to parameterize
-- the ABT by its concrete view? If we did that, then we could
-- define a specialized Bind for FreeVarsABT, in order to keep track
-- of whether the bound variable occurs or not (for defining
-- 'caseBind' precisely).
--
-- | A variable is a pair of some hint for the name ('varName') and
-- some unique identifier ('varID'). N.B., the unique identifier
-- is lazy so that we can tie-the-knot in 'binder'. Also, N.B., the
-- 'Eq' and 'Ord' instances only check the 'varID' and ignore the
-- 'varName'.
data Variable = Variable {-# UNPACK #-} !Text Nat
    deriving (Read, Show)

-- | Project out the string the user suggested as a name for the
-- variable. N.B., this name does not uniquely identify the variable;
-- it is only a hint for how to show the variable when we need to
-- print things out.
varName :: Variable -> Text
varName (Variable name _) = name

-- | Project out the unique identifier for the variable.
varID :: Variable -> Nat
varID (Variable _ i) = i

instance Eq Variable where
    (==) = (==) `on` varID

instance Ord Variable where
    compare = compare `on` varID


----------------------------------------------------------------
-- TODO: should we abstract over 'AST' like neelk does for @signature@?
--
-- TODO: remove the singleton type for 'Var', and infer it instead?
--
-- TODO: distinguish between free and bound variables, a~la Locally
-- Nameless? also cf., <http://hackage.haskell.org/package/abt>
--
-- TODO: (?) index by the /local/ environment (or size thereof).
-- That is, Syn and Var would be @Z@, whereas Bind would take @n@
-- to @S n@ (or @[]@ and taking @xs@ to some @x:xs@, respectively).
-- This way, the 'AST' could actually specify when it expects an
-- Bind term. Doing this would give us improved type-safety of the
-- syntax tree, and should still free us from worrying about the
-- issues that tracking a /global/ environment would cause (like
-- worrying about weakening, etc),
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
data View :: (Hakaru -> *) -> Hakaru -> * where

    Syn  :: !(AST abt a) -> View abt a

    -- HACK: alas we need to keep the Sing in order to make 'subst' typesafe... Is there any way to work around that? Maybe only define substitution for well-typed ABTs (i.e., what we produce via typechecking a plain ABT)? If we can manage to get rid of the Sing, then 'biner' and 'multibinder' would become much simpler. Alas, it looks like we also need it for 'inferType' to be well-typed... How can we avoid that?
    --
    -- TODO: what are the overhead costs of storing a Sing? Would
    -- it be cheaper to store the SingI dictionary (and a Proxy,
    -- as necessary)?
    Var  :: {-# UNPACK #-} !Variable -> !(Sing a) -> View abt a

    -- N.B., this constructor is recursive, thus minimizing the
    -- memory overhead of whatever annotations our ABT stores (we
    -- only annotate once, at the top of a chaing of 'Bind's, rather
    -- than before each one). However, in the 'ABT' class, we provide
    -- an API as if things went straight back to @abt@. Doing so
    -- requires that 'caseBind' is part of the class so that we
    -- can push whatever annotations down over one single level of
    -- 'Bind', rather than pushing over all of them at once and
    -- then needing to reconstruct all but the first one.
    Bind :: {-# UNPACK #-} !Variable -> !(View abt a) -> View abt a


instance Functor1 View where
    fmap1 f (Syn  t)   = Syn (fmap1 f t)
    fmap1 _ (Var  x p) = Var  x p
    fmap1 f (Bind x e) = Bind x (fmap1 f e)


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
            . showsPrec 11 s
            )
    showsPrec1 p (Bind x v) =
        showParen (p > 9)
            ( showString "Bind "
            . showsPrec  11 x
            . showString " "
            . showsPrec1 11 v
            )

instance Show1 abt => Show (View abt a) where
    showsPrec = showsPrec1
    show      = show1


-- TODO: neelk includes 'subst' in the signature. Any reason we should?
class ABT (abt :: Hakaru -> *) where
    syn  :: AST abt a          -> abt a
    var  :: Variable -> Sing a -> abt a
    bind :: Variable -> abt  a -> abt a

    -- TODO: better name. "unbind"? "fromBind"?
    --
    -- When the left side is defined, we have the following laws:
    -- > caseBind e bind == e
    -- > caseBind (bind x e) k == k x (unviewABT $ viewABT e)
    -- However, we do not necessarily have the following:
    -- > caseBind (bind x e) k == k x e
    -- because the definition of 'caseBind' for 'FreeVarsABT'
    -- is not exact.
    --
    -- | Assume the ABT is 'Bind' and then project out the components.
    -- If the ABT is not 'Bind', then this function will throw an
    -- 'ExpectedBindException' error.
    caseBind :: abt a -> (Variable -> abt a -> r) -> r

    -- See note about exposing 'View', 'viewABT', and 'unviewABT'.
    -- We could replace 'viewABT' with a case-elimination version...
    viewABT  :: abt a -> View abt a

    -- TODO: use our own VarSet type (e.g., @IntMap Variable@) instead of @Set Variable@?
    freeVars :: abt a -> Set Variable

    -- TODO: add a function for checking alpha-equivalence? Other stuff?
    -- TODO: does it make sense to have the functions for generating fresh variable names here? or does that belong in a separate class?


isBind :: (ABT abt) => abt a -> Bool
isBind e =
    case viewABT e of
    Bind _ _ -> True
    _        -> False


-- See note about exposing 'View', 'viewABT', and 'unviewABT'
unviewABT :: (ABT abt) => View abt a -> abt a
unviewABT (Syn  t)   = syn  t
unviewABT (Var  x p) = var  x p
unviewABT (Bind x v) = bind x (unviewABT v)


data ABTException
    = ExpectedBindException
    | ExpectedVarSynException
    | SubstitutionTypeError
    deriving (Show, Typeable)

instance Exception ABTException


-- | Assume the ABT is not 'Bind' and then project out the components.
-- If the ABT is in fact 'Bind', then this function will throw an
-- 'ExpectedVarSynException' error.
caseVarSyn
    :: (ABT abt)
    => abt a
    -> (Variable -> Sing a -> r)
    -> (AST abt a          -> r)
    -> r
caseVarSyn e var_ syn_ =
    case viewABT e of
    Syn  t   -> syn_ t
    Var  x p -> var_ x p
    Bind _ _ -> throw ExpectedVarSynException -- TODO: add call-site info


----------------------------------------------------------------
-- | A trivial ABT with no annotations. The 'freeVars' method is
-- very expensive for this ABT, because we have to traverse the
-- term every time we want to get it. Use 'FreeVarsABT' to fix this.
newtype TrivialABT (a :: Hakaru) =
    TrivialABT (View TrivialABT a)

instance ABT TrivialABT where
    syn  t                = TrivialABT (Syn  t)
    var  x p              = TrivialABT (Var  x p)
    bind x (TrivialABT v) = TrivialABT (Bind x v)

    caseBind (TrivialABT v) k =
        case v of
        Bind x v' -> k x (TrivialABT v')
        _         -> throw ExpectedBindException -- TODO: add info about the call-site

    viewABT (TrivialABT v) = v

    freeVars = go . viewABT
        where
        go (Syn  t)   = foldMap1 freeVars t
        go (Var  x _) = Set.singleton x
        go (Bind x v) = Set.delete x (go v)


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
            . showsPrec 11 s
            )
    showsPrec1 p (TrivialABT (Bind x v)) =
        showParen (p > 9)
            ( showString "bind "
            . showsPrec  11 x
            . showString " "
            . showsPrec1 11 (TrivialABT v) -- HACK: use caseBind
            )

instance Show (TrivialABT a) where
    showsPrec = showsPrec1
    show      = show1

----------------------------------------------------------------
-- TODO: replace @Set Variable@ with @Map Variable Hakaru@ or @Map
-- Variable (Some (Sing :: Hakaru -> *))@ though that belongs more
-- in a different ABT instance produced by type-checking, rather
-- than belonging here...
--
-- TODO: replace @Set Variable@ with @Map Variable Nat@ where the
-- Nat is the number of times the variable occurs. That way, we can
-- tell when a bound variable is unused or only used only once (and
-- hence performing beta\/let reduction would be a guaranteed win),
-- and if it's used more than once then we can use the number of
-- occurances in our heuristic for deciding whether reduction would
-- be a win or not.
--
-- TODO: generalize this pattern for any monoidal annotation?
-- TODO: does keeping the set lazy allow us to use 'binder'? At what performance cost?
--
-- | An ABT which keeps track of free variables. The 'freeVars'
-- method is /O(1)/ for this ABT. N.B., the memoized set of free
-- variables is lazy so that we can tie-the-knot in 'binder'
-- without interfering with our memos.
data FreeVarsABT (a :: Hakaru)
    = FreeVarsABT (Set Variable) !(View FreeVarsABT a)
    -- N.B., Set is a monoid with {Set.empty; Set.union; Set.unions}
    -- For a lot of code, the other component ordering would be
    -- nicer; but this ordering gives a more intelligible Show instance.

instance ABT FreeVarsABT where
    syn  t                    = FreeVarsABT (foldMap1 freeVars t) (Syn  t)
    var  x p                  = FreeVarsABT (Set.singleton x)     (Var  x p)
    bind x (FreeVarsABT xs v) = FreeVarsABT (Set.delete x xs)     (Bind x v)

    -- N.B., when we go under the binder, the variable @x@ may not
    -- actually be used, but we add it to the set of freeVars
    -- anyways. The reasoning is thus: this function is mainly used
    -- in defining 'subst', and for that purpose it's important to
    -- track all the variables which /could be/ free, so that we
    -- can freshen appropriately. It may be safe to not include @x@
    -- when @x@ is not actually used in @v'@, but it's best not to
    -- risk it. Moreover, once we add support for open terms (i.e.,
    -- truly-free variables) then we'll need to account for the
    -- fact that the variable @x@ may come to be used in the grounding
    -- of the open term, even though it's not used in the part of
    -- the term we already know.
    caseBind (FreeVarsABT xs v) k =
        case v of
        Bind x v' -> k x (FreeVarsABT (Set.insert x xs) v')
        _         -> throw ExpectedBindException -- TODO: add info about the call-site

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
    | x `Set.member` xs = Variable (varName x) $! 1 + varID (Set.findMax xs)
    | otherwise         = x


-- | Rename a free variable. Does nothing if the variable is bound.
rename :: forall abt a. (ABT abt) => Variable -> Variable -> abt a -> abt a
rename x y = start
    where
    start :: forall b. abt b -> abt b
    start e = loop e (viewABT e)

    -- TODO: is it actually worth passing around the @e@? Benchmark.
    loop :: forall b. abt b -> View abt b -> abt b
    loop _ (Syn t)  = syn (fmap1 start t)
    loop e (Var z p)
        | x == z    = var y p
        | otherwise = e
    loop e (Bind z v)
        | x == z    = e
        | otherwise = bind z $ loop (caseBind e $ const id) v


-- TODO: keep track of a variable renaming environment, and do renaming on the fly rather than traversing the ABT repeatedly.
--
-- | Perform capture-avoiding substitution. This function will
-- either preserve type-safety or else throw an 'SubstitutionTypeError'.
-- N.B., to ensure timely throwing of exceptions, the 'AST' and
-- 'ABT' should have strict 'fmap1' definitions.
subst
    :: forall abt a b
    .  (ABT abt)
    => Variable
    -> abt a
    -> Sing a
    -> abt b
    -> abt b
subst x e e_typ = start
    where
    start :: forall c. abt c -> abt c
    start f = loop f (viewABT f)

    -- TODO: is it actually worth passing around the @f@? Benchmark.
    loop :: forall c. abt c -> View abt c -> abt c
    loop _ (Syn t)    = syn $! fmap1 start t
    loop f (Var z z_typ)
        | x == z      =
            case jmEq z_typ e_typ of
            Just Refl -> e
            Nothing   -> throw SubstitutionTypeError
        | otherwise   = f
    loop f (Bind z _)
        | x == z      = f
        | otherwise   =
            -- TODO: even if we don't come up with a smarter way
            -- of freshening variables, it'd be better to just pass
            -- both sets to 'freshen' directly and then check them
            -- each; rather than paying for taking their union every
            -- time we go under a binder like this.
            let z' = freshen z (freeVars e `mappend` freeVars f) in
            -- HACK: the 'rename' function requires an ABT not a
            -- View, so we have to use 'caseBind' to give its
            -- input and then 'viewABT' to discard the topmost
            -- annotation. We really should find a way to eliminate
            -- that overhead.
            caseBind f $ \_ f' ->
                bind z' . loop f' . viewABT $ rename z z' f'


----------------------------------------------------------------
----------------------------------------------------------------
-- TODO: Memoizing the highest bound seen so far (from the bottom-up)
-- breaks our ability to tie-the-knot in 'binder'. However, when
-- it comes to program transformations, it might make sense to
-- memoize the largest binder the transformation passes under (cf.,
-- the discussion in the paper about program transformations). Of
-- course, we could also use some Locally Nameless style approach
-- to deal with that issue...


-- N.B., we define this as a standalone class in order to avoid
-- imposing additional type-class constraints on functions that use
-- it. However, do note that our ability to do this is tied to the
-- fact that our 'ABT' class hard-codes the 'View', 'AST', and
-- 'Variable' types. The first two are important so that we can
-- simply give their 'bound' definitions inline. The last is important
-- for knowing that the implementation of variables has the laziness
-- we need. If we end up deciding to have the 'ABT' class abstract
-- over any of those three types, then we'll need to move this into
-- a type class again.


-- | Return the largest 'varID' of variable /binding sites/ (i.e.,
-- of variables bound by the 'Bind' constructor).
--
-- N.B., this should return 0 for the bound variables themselves.
-- For performance, we don't traverse into the body under those
-- binders. (If all terms are constructed via 'binder', then
-- soundness is guaranteed without needing to traverse under
-- binders.)
maxBind :: (ABT abt) => abt a -> Nat
maxBind = go_View . viewABT
    where
    -- For multibinders (i.e., nested uses of Bind) we recurse
    -- through the whole binder, just to be sure. However, we should
    -- be able to just look at the first binder, since whenever we
    -- figure out how to do multibinders we can prolly arrange for
    -- the first one to be the largest.
    go_View :: (ABT abt) => View abt a -> Nat
    go_View = go 0
        where
        go 0 (Syn  t)   = go_AST t
        go n (Syn  _)   = n -- Don't go under binders
        go n (Var  _ _) = n -- Don't look at variable *uses*
        go n (Bind x v) = go (n `max` varID x) v

    -- N.B., we needn't traverse into any type annotations, since we
    -- don't have dependent types, hence no term variables can appear
    -- in the types.
    go_AST :: (ABT abt) => AST abt a -> Nat
    go_AST (Lam_        e)        = maxBind e
    go_AST (App_        e1 e2)    = maxBind e1 `max` maxBind e2
    go_AST (Let_        e1 e2)    = maxBind e1 `max` maxBind e2
    go_AST (Fix_        e)        = maxBind e
    go_AST (Ann_        _  e)     = maxBind e
    go_AST (PrimOp_     _)        = 0
    go_AST (NaryOp_     _  es)    = go_Sequence es
    go_AST (Value_      _)        = 0
    go_AST (CoerceTo_   _  e)     = maxBind e
    go_AST (UnsafeFrom_ _  e)     = maxBind e
    go_AST Empty_                 = 0
    go_AST (Array_      e1 e2)    = maxBind e1 `max` maxBind e2
    go_AST (Datum_ (Datum d))     = go_DatumCode d
    go_AST (Case_       e  bs)    = maxBind e  `max` go_Branches bs
    go_AST (Measure_    _)        = 0
    go_AST (Bind_       e1 e2)    = maxBind e1 `max` maxBind e2
    go_AST (Superpose_  pes)      = go_Pairs pes
    
    go_DatumCode :: (ABT abt) => DatumCode xss abt a -> Nat
    go_DatumCode (Inr d) = go_DatumCode   d
    go_DatumCode (Inl d) = go_DatumStruct d
    
    go_DatumStruct :: (ABT abt) => DatumStruct xs abt a -> Nat
    go_DatumStruct (Et d1 d2) = go_DatumFun d1 `max` go_DatumStruct d2
    go_DatumStruct Done       = 0
    
    go_DatumFun :: (ABT abt) => DatumFun x abt a -> Nat
    go_DatumFun (Konst e) = maxBind e
    go_DatumFun (Ident e) = maxBind e

    -- HACK: can't use 'foldMap1' unless we newtype wrap up the Nats to say which monoid we mean.
    -- N.B., the Prelude's 'maximum' throws an error on empty lists!
    go_Sequence :: (ABT abt) => Seq (abt a) -> Nat
    go_Sequence =
        F.foldl' (\n e -> n `max` maxBind e) 0
    go_Pairs :: (ABT abt) => [(abt a, abt b)] -> Nat
    go_Pairs =
        F.foldl' (\n (e1,e2) -> n `max` maxBind e1 `max` maxBind e2) 0
    go_Branches :: (ABT abt) => [Branch a abt b] -> Nat
    go_Branches =
        F.foldl' (\n b -> n `max` maxBind (branchBody b)) 0


-- | A combinator for defining a HOAS-like API for our syntax.
-- Because our 'AST' is first-order, we cannot actually have any
-- exotic terms in our language. In principle, this function could
-- be used to do exotic things when constructing those non-exotic
-- terms; however, trying to do anything other than change the
-- variable's name hint will cause things to explode (since it'll
-- interfere with our tying-the-knot).
binder
    :: (ABT abt)
    => Text                     -- ^ The variable's name hint
    -> Sing a                   -- ^ The variable's type
    -> (abt a -> abt b)         -- ^ Build the binder's body from a variable
    -> abt b
binder name typ hoas = bind x body
    where
    body = hoas (var x typ)
    x    = Variable name (maxBind body + 1)


data List1 :: (k -> *) -> [k] -> * where
    Nil  :: List1 a '[]
    Cons :: a x -> List1 a xs -> List1 a (x ': xs)

instance Show1 a => Show1 (List1 a) where
    showsPrec1 _ Nil         = showString     "Nil"
    showsPrec1 p (Cons x xs) = showParen_11 p "Cons" x xs

instance Show1 a => Show (List1 a xs) where
    showsPrec = showsPrec1
    show      = show1

data Hint :: Hakaru -> * where
    Hint :: !Text -> !(Sing a) -> Hint a

instance Show1 Hint where
    showsPrec1 p (Hint x s) = showParen_01 p "Hint" x s

instance Show (Hint a) where
    showsPrec = showsPrec1
    show      = show1
    
data VS :: Hakaru -> * where
    VS :: {-# UNPACK #-} !Variable -> !(Sing a) -> VS a

-- this typechecks, and it works! 
-- BUG: but it seems fairly unusable. We must give explicit type signatures to any lambdas passed as the second argument, otherwise it complains about not knowing enough about the types in @xs@... Also, the uncurriedness of it isn't very HOAS-like
multibinder
    :: (ABT abt) => List1 Hint xs -> (List1 abt xs -> abt b) -> abt b
multibinder names hoas = binds vars body
    where
    vars = go 0 names
        where
        -- BUG: this puts the largest binder on the inside
        go :: Nat -> List1 Hint xs -> List1 VS xs
        go _ Nil                         = Nil
        go n (Cons (Hint name typ) rest) = 
            Cons (VS (Variable name $ maxBind body + n) typ)
                ((go $! n + 1) rest)
    body = hoas (go vars)
        where
        go :: ABT abt => List1 VS xs -> List1 abt xs
        go Nil                    = Nil
        go (Cons (VS x typ) rest) = Cons (var x typ) (go rest)
    
    binds :: ABT abt => List1 VS xs -> abt a -> abt a
    binds Nil                  = id
    binds (Cons (VS x _) rest) = bind x . binds rest

----------------------------------------------------------------
----------------------------------------------------------- fin.
