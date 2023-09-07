{-# LANGUAGE QuantifiedConstraints #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Eta reduce" #-}

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Control.Heftia.Trans where

import Control.Effect.Class (LiftIns (LiftIns), unliftIns, type (~>))
import Control.Effect.Class.Machinery.HFunctor (HFunctor, hfmap)
import Control.Freer.Trans (TransFreer, interpretFT, liftInsT, liftLowerFT)
import Control.Monad.Identity (IdentityT (IdentityT), runIdentityT)

class (forall sig f. c f => c (h sig f)) => TransHeftia c h | h -> c where
    {-# MINIMAL liftSigT, liftLowerHT, (hoistHeftia, runElaborateH | elaborateHT) #-}

    -- | Lift a /signature/ into a Heftia monad transformer.
    liftSigT :: HFunctor sig => sig (h sig f) a -> h sig f a

    transformHT ::
        (c f, HFunctor sig, HFunctor sig') =>
        (forall g. sig g ~> sig' g) ->
        h sig f ~> h sig' f
    transformHT f = translateT f
    {-# INLINE transformHT #-}

    -- | Translate /signature/s embedded in a Heftia monad transformer.
    translateT ::
        (c f, HFunctor sig, HFunctor sig') =>
        (sig (h sig' f) ~> sig' (h sig' f)) ->
        h sig f ~> h sig' f
    translateT f = elaborateHT liftLowerHT (liftSigT . f)
    {-# INLINE translateT #-}

    liftLowerHT :: forall sig f. (c f, HFunctor sig) => f ~> h sig f

    -- | Translate an underlying monad.
    hoistHeftia :: (c f, c g, HFunctor sig) => (f ~> g) -> h sig f ~> h sig g
    hoistHeftia phi = elaborateHT (liftLowerHT . phi) liftSigT
    {-# INLINE hoistHeftia #-}

    interpretLowerH :: (HFunctor sig, c f, c g) => (f ~> h sig g) -> h sig f ~> h sig g
    interpretLowerH f = elaborateHT f liftSigT
    {-# INLINE interpretLowerH #-}

    runElaborateH :: (c f, HFunctor sig) => (sig f ~> f) -> h sig f ~> f
    default runElaborateH :: (c f, c (IdentityT f), HFunctor sig) => (sig f ~> f) -> h sig f ~> f
    runElaborateH f = runIdentityT . elaborateHT IdentityT (IdentityT . f . hfmap runIdentityT)
    {-# INLINE runElaborateH #-}

    elaborateHT :: (c f, c g, HFunctor sig) => (f ~> g) -> (sig g ~> g) -> h sig f ~> g
    elaborateHT f i = runElaborateH i . hoistHeftia f
    {-# INLINE elaborateHT #-}

    reelaborateHT :: (c f, HFunctor sig) => (sig (h sig f) ~> h sig f) -> h sig f ~> h sig f
    reelaborateHT = elaborateHT liftLowerHT
    {-# INLINE reelaborateHT #-}

heftiaToFreer ::
    (TransHeftia c h, TransFreer c' fr, c f, c (fr ins f), c' f) =>
    h (LiftIns ins) f ~> fr ins f
heftiaToFreer a = ($ a) $ elaborateHT liftLowerFT (liftInsT . unliftIns)
{-# INLINE heftiaToFreer #-}

freerToHeftia ::
    (TransHeftia c h, TransFreer c' fr, c' f, c' (fr ins f), c' (h (LiftIns ins) f), c f) =>
    fr ins f ~> h (LiftIns ins) f
freerToHeftia a = ($ a) $ interpretFT liftLowerHT (liftSigT . LiftIns)
{-# INLINE freerToHeftia #-}
