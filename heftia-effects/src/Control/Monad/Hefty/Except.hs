-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

{- |
Copyright   :  (c) 2023 Sayo Koyoneda
License     :  MPL-2.0 (see the LICENSE file)
Maintainer  :  ymdfield@outlook.jp
Portability :  portable

Interpreters for the t'Data.Effect.Except.Throw' / t'Data.Effect.Except.Catch' effects.
-}
module Control.Monad.Hefty.Except (
    module Control.Monad.Hefty.Except,
    module Data.Effect.Except,
)
where

import Control.Exception (Exception)
import Control.Monad.Hefty (
    Eff,
    Interpreter,
    interposeWith,
    interpret,
    interpretBy,
    interpretH,
    (&),
    type (<<|),
    type (<|),
    type (~>),
    type (~~>),
 )
import Data.Effect.Except
import Data.Effect.Unlift (UnliftIO)
import UnliftIO (throwIO)
import UnliftIO qualified as IO

runExcept :: Eff '[Catch e] (Throw e ': r) a -> Eff '[] r (Either e a)
runExcept = runThrow . runCatch

runThrow :: Eff '[] (Throw e ': r) a -> Eff '[] r (Either e a)
runThrow = interpretBy (pure . Right) handleThrow

runCatch :: (Throw e <| ef) => Eff '[Catch e] ef ~> Eff '[] ef
runCatch = interpretH elabCatch

handleThrow :: Interpreter (Throw e) (Eff '[] r) (Either e a)
handleThrow (Throw e) _ = pure $ Left e
{-# INLINE handleThrow #-}

elabCatch :: (Throw e <| ef) => Catch e ~~> Eff '[] ef
elabCatch (Catch action hdl) = action & interposeWith \(Throw e) _ -> hdl e
{-# INLINE elabCatch #-}

runThrowIO
    :: forall e eh ef
     . (IO <| ef, Exception e)
    => Eff eh (Throw e ': ef) ~> Eff eh ef
runThrowIO = interpret \(Throw e) -> throwIO e

runCatchIO
    :: forall e eh ef
     . (UnliftIO <<| eh, IO <| ef, Exception e)
    => Eff (Catch e ': eh) ef ~> Eff eh ef
runCatchIO = interpretH \(Catch action hdl) -> IO.catch action hdl
