{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Main where
import Data.Text (Text)
import Data.Kind (Type)
import Data.Effect.TH (makeEffectF, makeEffectH)
import Data.Hefty.Extensible (type (<|), type (<<|), ForallHFunctor)
import Control.Effect.ExtensibleChurch (runEff, type (:!!))
import Control.Effect (type (~>), sendIns)
import Control.Effect.Hefty (interpretRec, interposeRec, interpretRecH, interposeRec, raise, raiseH, interposeRecH)
import qualified Data.Text.IO as T
import Data.Time (UTCTime, getCurrentTime)
import qualified Data.Text as T
import Data.Effect.State (get, modify)
import Control.Effect.Handler.Heftia.State (evalState)
import Data.Function ((&))
import Control.Monad (when)
import Control.Effect.Handler.Heftia.Reader (interpretReader)
import Data.Effect.Reader (local, ask)
import Data.Time.Format.ISO8601 (iso8601Show)
import Control.Arrow ((>>>))

data Log a where
    Logging :: Text -> Log ()

makeEffectF [''Log]

logToIO :: (IO <| r, ForallHFunctor eh) => eh :!! LLog ': r ~> eh :!! r
logToIO = interpretRec \(Logging msg) -> sendIns $ T.putStrLn msg

data Time a where
    CurrentTime :: Time UTCTime

makeEffectF [''Time]

timeToIO :: (IO <| r, ForallHFunctor eh) => eh :!! (LTime ': r) ~> eh :!! r
timeToIO = interpretRec \CurrentTime -> sendIns getCurrentTime

logWithTime :: (Log <| ef, Time <| ef, ForallHFunctor eh) => eh :!! ef ~> eh :!! ef
logWithTime = interposeRec \(Logging msg) -> do
    t <- currentTime
    logging $ "[" <> T.pack (show t) <> "] " <> msg

-- | An effect that introduces a scope that represents a chunk of logs.
data LogChunk f (a :: Type) where
    LogChunk ::
        -- | chunk name
        Text ->
        f a ->
        LogChunk f a

makeEffectH [''LogChunk]

-- | Ignore chunk names and output logs in log chunks as they are.
runLogChunk :: ForallHFunctor eh => (LogChunk ': eh) :!! ef ~> eh :!! ef
runLogChunk = interpretRecH \(LogChunk _ m) -> m

-- | Limit the number of logs in a log chunk to the first @n@ logs.
limitLogChunk
    ::  forall eh ef. (LogChunk <<| eh, Log <| {- LState Int ': -} ef) =>
        Int -> LogChunk ('[] :!! ef) ~> LogChunk ('[] :!! ef)
limitLogChunk n (LogChunk chunkName a) =
    LogChunk chunkName . evalState @Int 0 $
        raise a & interposeRec \(Logging msg) -> do
            count <- get
            when (count <= n) do
                if count == n
                    then logging "LOG OMITTED..."
                    else logging msg

                modify @Int (+ 1)

data FileSystem a where
    Mkdir :: FilePath -> FileSystem ()
    WriteToFile :: FilePath -> String -> FileSystem ()

makeEffectF [''FileSystem]

runDummyFS :: (IO <| r, ForallHFunctor eh) => eh :!! (LFileSystem ': r) ~> eh :!! r
runDummyFS = interpretRec \case
    Mkdir path ->
        sendIns $ putStrLn $ "<runDummyFS> mkdir " <> path
    WriteToFile path content ->
        sendIns $ putStrLn $ "<runDummyFS> writeToFile " <> path <> " : " <> content

-- | Create directories according to the log-chunk structure and save one log in one file.
saveLogChunk
    :: forall eh ef. (LogChunk <<| eh, Log <| ef, FileSystem <| ef, Time <| ef, ForallHFunctor eh) =>
        eh :!! ef ~> eh :!! ef
saveLogChunk =
        raise >>> raiseH
    >>> (   interposeRecH @LogChunk \(LogChunk chunkName a) -> do
                chunkBeginAt <- currentTime
                let dirName = iso8601Show chunkBeginAt ++ "-" ++ T.unpack chunkName
                local @FilePath (++ dirName ++ "/") do
                    logChunkPath <- ask
                    mkdir logChunkPath
                    a & interposeRec \(Logging msg) -> do
                        logAt <- currentTime
                        logging msg
                        writeToFile (logChunkPath ++ iso8601Show logAt ++ ".log") (show msg)
        )
    >>> interpretReader @FilePath "./log/"

logExample :: (LogChunk <<| eh, Log <| ef, IO <| ef) => (eh :!! ef) ()
logExample =
    logChunk "scope1" do
        logging "foo"
        logging "bar"
        logging "baz"
        logging "qux"

        sendIns $ putStrLn "------"

        logChunk "scope2" do
            logging "hoge"
            logging "piyo"
            logging "fuga"
            logging "hogera"

        sendIns $ putStrLn "------"

        logging "quux"
        logging "foobar"

main :: IO ()
main =
    runEff @IO
      . logToIO
      . timeToIO
      . runDummyFS
      . runLogChunk
      . saveLogChunk
      $ do
        logExample

{-
<runDummyFS> mkdir ./log/2024-07-06T12:31:45.230925641Z-scope1/
foo
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231047059Z.log : "foo"
bar
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231079049Z.log : "bar"
baz
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231103074Z.log : "baz"
qux
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231125807Z.log : "qux"
------
<runDummyFS> mkdir ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.23115415Z-scope2/
hoge
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231179508Z.log : "hoge"
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.23115415Z-scope2/2024-07-06T12:31:45.231177534Z.log : "hoge"
piyo
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231225564Z.log : "piyo"
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.23115415Z-scope2/2024-07-06T12:31:45.231223681Z.log : "piyo"
fuga
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231270128Z.log : "fuga"
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.23115415Z-scope2/2024-07-06T12:31:45.231268194Z.log : "fuga"
hogera
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231313499Z.log : "hogera"
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.23115415Z-scope2/2024-07-06T12:31:45.231311516Z.log : "hogera"
------
quux
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231360958Z.log : "quux"
foobar
<runDummyFS> writeToFile ./log/2024-07-06T12:31:45.230925641Z-scope1/2024-07-06T12:31:45.231384543Z.log : "foobar"
-}
