-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Control.Effect.Handler.Heftia.Except where

import Control.Effect.Class (type (~>))
import Control.Effect.Class.Except (CatchS (Catch), ThrowI (Throw))
import Control.Effect.Freer (Fre, interposeK, interposeT, interpretK, interpretT)
import Control.Monad.Trans.Cont (ContT (ContT), evalContT)
import Control.Monad.Trans.Except (ExceptT (ExceptT), runExceptT, throwE)
import Data.Free.Sum (Sum, type (<))

-- | Elaborate the 'Catch' effect using the 'ExceptT' monad transformer.
elaborateExceptT ::
    (ThrowI e < Sum es, Monad m) =>
    (CatchS e) (Fre es m) ~> Fre es m
elaborateExceptT (Catch action (hdl :: e -> Fre es m a)) = do
    r <- runExceptT $ ($ action) $ interposeT \(Throw (e :: e)) -> throwE e
    case r of
        Left e -> hdl e
        Right a -> pure a

-- | Elaborate the 'Catch' effect using the 'ContT' continuation monad transformer.
elaborateExceptK ::
    (ThrowI e < Sum es, Monad m) =>
    (CatchS e) (Fre es m) ~> Fre es m
elaborateExceptK (Catch action (hdl :: e -> Fre es m a)) =
    evalContT $ ($ action) $ interposeK \(Throw (e :: e)) ->
        ContT \_ -> hdl e

-- | Interpret the 'Throw' effect using the 'ExceptT' monad transformer.
interpretThrowT :: Monad m => Fre (ThrowI e ': es) m ~> ExceptT e (Fre es m)
interpretThrowT = interpretT \(Throw e) -> throwE e
{-# INLINE interpretThrowT #-}

-- | Interpret the 'Throw' effect using the 'ContT' continuation monad transformer.
interpretThrowK :: Monad m => Fre (ThrowI e ': es) m a -> Fre es m (Either e a)
interpretThrowK a =
    evalContT $ ($ Right <$> a) $ interpretK \(Throw e) ->
        ContT \_ -> pure $ Left e
