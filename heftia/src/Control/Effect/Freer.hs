{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE UndecidableInstances #-}

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Control.Effect.Freer where

import Control.Applicative (Alternative)
import Control.Effect.Class (
    EffectDataHandler,
    EffectsVia (EffectsVia),
    Instruction,
    SendIns,
    runEffectsVia,
    sendIns,
    type (~>),
 )
import Control.Freer.Trans (
    TransFreer,
    interpretFT,
    liftInsT,
    liftLowerFT,
    reinterpretFT,
    runInterpretF,
    transformT,
 )
import Control.Freer.Trans.Final (FreerFinalT)
import Control.Monad (MonadPlus)
import Control.Monad.Cont (ContT (ContT), runContT)
import Control.Monad.Trans (MonadTrans, lift)
import Control.Monad.Trans.Freer (MonadTransFreer, interpretMK, interpretMT, reinterpretMK, reinterpretMT)
import Data.Coerce (Coercible, coerce)
import Data.Free.Sum (SumUnion)
import Data.Free.Union (
    IsMember,
    Member,
    Union,
    absurdUnion,
    decomp,
    inject,
    project,
    weakenL,
    weakenR,
 )
import Data.Kind (Type)

newtype
    FreerUnion
        (fr :: Instruction -> (Type -> Type) -> Type -> Type)
        u
        (es :: [Instruction])
        f
        a = FreerUnion {runFreerUnion :: fr (u es) f a}
    deriving newtype (Functor, Applicative, Alternative, Monad, MonadPlus)
    deriving stock (Foldable, Traversable)

type FreerEffects fr u es f = EffectsVia EffectDataHandler (FreerUnion fr u es f)

runFreerEffects :: FreerEffects fr u es f ~> fr (u es) f
runFreerEffects = runFreerUnion . runEffectsVia
{-# INLINE runFreerEffects #-}

freerEffects :: fr (u es) f ~> FreerEffects fr u es f
freerEffects = EffectsVia . FreerUnion
{-# INLINE freerEffects #-}

newtype FreerUnionForSend handleHere fr u es f a = FreerUnionForSend
    {runFreerUnionForSend :: FreerUnion fr u es f a}
    deriving newtype (Functor, Applicative, Alternative, Monad, MonadPlus)
    deriving stock (Foldable, Traversable)

instance SendIns e (FreerUnionForSend (e `IsMember` es) fr u es f) => SendIns e (FreerUnion fr u es f) where
    sendIns = runFreerUnionForSend @(e `IsMember` es) . sendIns
    {-# INLINE sendIns #-}

instance
    (TransFreer c fr, Union u, Member u e es) =>
    SendIns e (FreerUnionForSend 'True fr u es f)
    where
    sendIns = FreerUnionForSend . FreerUnion . liftInsT . inject
    {-# INLINE sendIns #-}

instance (TransFreer c fr, SendIns e f, c f) => SendIns e (FreerUnionForSend 'False fr u es f) where
    sendIns = FreerUnionForSend . FreerUnion . liftLowerFT . sendIns
    {-# INLINE sendIns #-}

interpret ::
    (TransFreer c fr, Union u, c f) =>
    (e ~> FreerEffects fr u es f) ->
    FreerEffects fr u (e ': es) f ~> FreerEffects fr u es f
interpret i a =
    freerEffects $ ($ runFreerEffects a) $ interpretFT liftLowerFT \u ->
        case decomp u of
            Left e -> runFreerEffects $ i e
            Right e -> liftInsT e

interpretT ::
    forall t fr u e es f.
    (MonadTransFreer fr, Union u, MonadTrans t, Monad f, Monad (t (FreerEffects fr u es f))) =>
    (e ~> t (FreerEffects fr u es f)) ->
    FreerEffects fr u (e ': es) f ~> t (FreerEffects fr u es f)
interpretT i = interpretMT i . splitFreerEffects @_ @fr
{-# INLINE interpretT #-}

interpretK ::
    (MonadTransFreer fr, Union u, Monad f) =>
    (a -> FreerEffects fr u es f r) ->
    (forall x. (x -> FreerEffects fr u es f r) -> e x -> FreerEffects fr u es f r) ->
    FreerEffects fr u (e ': es) f a ->
    FreerEffects fr u es f r
interpretK k i = (`runContT` k) . interpretContT \e -> ContT (`i` e)
{-# INLINE interpretK #-}

interpretContT ::
    forall r fr u e es f.
    (MonadTransFreer fr, Union u, Monad f) =>
    (e ~> ContT r (FreerEffects fr u es f)) ->
    FreerEffects fr u (e ': es) f ~> ContT r (FreerEffects fr u es f)
interpretContT i = interpretMK i . splitFreerEffects @_ @fr
{-# INLINE interpretContT #-}

reinterpret ::
    (TransFreer c fr, Union u, c f) =>
    (e ~> FreerEffects fr u (e ': es) f) ->
    FreerEffects fr u (e ': es) f ~> FreerEffects fr u (e ': es) f
reinterpret i a =
    freerEffects $ ($ runFreerEffects a) $ reinterpretFT \u ->
        case decomp u of
            Left e -> runFreerEffects $ i e
            Right e -> liftInsT $ weakenR e

transform ::
    (TransFreer c fr, Union u, c f) =>
    (e ~> e') ->
    FreerEffects fr u (e ': es) f ~> FreerEffects fr u (e' ': es) f
transform f a =
    freerEffects $ ($ runFreerEffects a) $ transformT \u ->
        case decomp u of
            Left e -> weakenL $ f e
            Right e -> weakenR e

interpose ::
    forall e fr u es f c.
    (TransFreer c fr, Union u, Member u e es, c f) =>
    (e ~> FreerEffects fr u es f) ->
    FreerEffects fr u es f ~> FreerEffects fr u es f
interpose f a =
    freerEffects $ ($ runFreerEffects a) $ reinterpretFT \u ->
        case project @_ @e u of
            Just e -> runFreerEffects $ f e
            Nothing -> liftInsT u

interposeT ::
    forall e t fr u es m.
    ( MonadTransFreer fr
    , Union u
    , Member u e es
    , Monad m
    , MonadTrans t
    , forall m1 m2 x. Coercible m1 m2 => Coercible (t m1 x) (t m2 x)
    , Monad (t (fr (u es) m))
    ) =>
    (e ~> t (FreerEffects fr u es m)) ->
    FreerEffects fr u es m ~> t (FreerEffects fr u es m)
interposeT f a =
    hoistT @(fr (u es) m) $ ($ runFreerEffects a) $ reinterpretMT \u ->
        case project @_ @e u of
            Just e -> hoistT $ f e
            Nothing -> lift $ liftInsT u
  where
    hoistT :: Coercible (t m1 a) (t m2 a) => t m1 a -> t m2 a
    hoistT = coerce
    {-# INLINE hoistT #-}

interposeK ::
    (MonadTransFreer fr, Union u, Member u e es, Monad m) =>
    (a -> FreerEffects fr u es m r) ->
    (forall x. (x -> FreerEffects fr u es m r) -> e x -> FreerEffects fr u es m r) ->
    FreerEffects fr u es m a ->
    FreerEffects fr u es m r
interposeK k i = (`runContT` k) . interposeContT \e -> ContT (`i` e)
{-# INLINE interposeK #-}

interposeContT ::
    forall e r fr u es m.
    (MonadTransFreer fr, Union u, Member u e es, Monad m) =>
    (e ~> ContT r (FreerEffects fr u es m)) ->
    FreerEffects fr u es m ~> ContT r (FreerEffects fr u es m)
interposeContT f a =
    hoistContT $ ($ runFreerEffects a) $ reinterpretMK \u ->
        case project @_ @e u of
            Just e -> hoistContT $ f e
            Nothing -> lift $ liftInsT u
  where
    hoistContT :: Coercible m1 m2 => ContT r m1 a -> ContT r m2 a
    hoistContT = coerce
    {-# INLINE hoistContT #-}

intercept ::
    forall e fr u es f c.
    (TransFreer c fr, Union u, Member u e es, c f) =>
    (e ~> e) ->
    FreerEffects fr u es f ~> FreerEffects fr u es f
intercept f a =
    freerEffects $ ($ runFreerEffects a) $ transformT \u ->
        case project @_ @e u of
            Just e -> inject $ f e
            Nothing -> u

raiseUnder ::
    forall e' e es fr u f c.
    (TransFreer c fr, Union u, c f) =>
    FreerEffects fr u (e ': es) f ~> FreerEffects fr u (e ': e' ': es) f
raiseUnder a =
    freerEffects
        . ($ runFreerEffects a)
        $ transformT \u -> case decomp u of
            Left e -> weakenL e
            Right e -> weakenR $ weakenR e

interpreted :: (TransFreer c h, c f, Union u) => FreerEffects h u '[] f ~> f
interpreted = runInterpretF absurdUnion . runFreerEffects
{-# INLINE interpreted #-}

splitFreerEffects ::
    (TransFreer c fr', TransFreer c fr, c f, c (FreerEffects fr u es f), Union u) =>
    FreerEffects fr u (e ': es) f ~> fr' e (FreerEffects fr u es f)
splitFreerEffects a =
    ($ runFreerEffects a) $ interpretFT (liftLowerFT . freerEffects . liftLowerFT) \u ->
        case decomp u of
            Left e -> liftInsT e
            Right e -> liftLowerFT $ freerEffects $ liftInsT e

liftLower :: (TransFreer c fr, c f) => f ~> FreerEffects fr u es f
liftLower = freerEffects . liftLowerFT

type Fre es f = FreerEffects (FreerFinalT Monad) SumUnion es f
type FreA es f = FreerEffects (FreerFinalT Applicative) SumUnion es f

type e <: es = Member SumUnion e es
