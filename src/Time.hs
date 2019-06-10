{-# LANGUAGE TemplateHaskell #-}

module Time where

import OurPrelude

import qualified Data.Text as T
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime, iso8601DateFormat)

-- $setup
-- >>> import Data.Time.Format (parseTimeOrError)
-- >>> let exampleCurrentTime = parseTimeOrError False defaultTimeLocale "%Y-%-m-%-d" "2019-06-06" :: UTCTime
--

data Time m a where
  Now :: Time m UTCTime

makeSem ''Time

runIO :: Member (Lift IO) r => Sem (Time ': r) a -> Sem r a
runIO =
  interpret $ \case
    Now -> sendM getCurrentTim
e
runPure :: UTCTime -> Sem (Time ': r) a -> Sem r a
runPure t =
  interpret $ \case
    Now -> pure t

-- | Return the UTC time 1 hour ago
--
-- Examples:
--
-- >>> run $ runPure exampleCurrentTime oneHourAgo
-- 2019-06-05 23:00:00 UTC
oneHourAgo :: Member Time r => Sem r UTCTime
oneHourAgo = now <&> addUTCTime (fromInteger $ -60 * 60)

-- | Return the UTC time 2 hours ago
--
-- Examples:
--
-- >>> run $ runPure exampleCurrentTime twoHoursAgo
-- 2019-06-05 22:00:00 UTC
twoHoursAgo :: Member Time r => Sem r UTCTime
twoHoursAgo = now <&> addUTCTime (fromInteger $ -60 * 60 * 2)

-- | Return the current ISO8601 date and time without timezone
--
-- TODO: switch to Data.Time.Format.ISO8601 once time-1.9.0 is available
-- unix depends on an earlier version currently https://github.com/haskell/unix/issues/131
--
-- Examples:
--
-- >>> run $ runPure exampleCurrentTime runDate
-- "2019-06-06T00:00:00"
runDate :: Member Time r => Sem r Text
runDate =
  now <&> formatTime defaultTimeLocale (iso8601DateFormat (Just "%H:%M:%S")) <&>
  T.pack
