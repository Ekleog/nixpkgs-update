{-# LANGUAGE PartialTypeSignatures #-}

module OurPrelude
  ( (>>>)
  , (<|>)
  , (<>)
  , (<&>)
  , (&)
  , module Control.Error
  , module Control.Monad.Except
  , module Control.Monad.Trans.Class
  , module Control.Monad.IO.Class
  , module Data.Bifunctor
  , module System.Process.Typed
  , module Polysemy
  , Set
  , Text
  , Vector
  , interpolate
  , tshow
  , tryIOTextET
  , whenM
  , ourReadProcessInterleaved_
  , silently
  , bytestringToText
  ) where

import Control.Applicative ((<|>))
import Control.Category ((>>>))
import Control.Error
import Control.Monad.Except
import Control.Monad.IO.Class
import Control.Monad.Trans.Class
import Data.Bifunctor
import qualified Data.ByteString.Lazy as BSL
import Data.Function ((&))
import Data.Functor ((<&>))
import Data.Semigroup ((<>))
import Data.Set (Set)
import Data.Text (Text, pack)
import qualified Data.Text.Encoding as T
import Data.Vector (Vector)
import Language.Haskell.TH.Quote
import qualified NeatInterpolation
import Polysemy
import System.Process.Typed hiding (setEnv)

interpolate :: QuasiQuoter
interpolate = NeatInterpolation.text

tshow :: Show a => a -> Text
tshow = show >>> pack

tryIOTextET :: MonadIO m => IO a -> ExceptT Text m a
tryIOTextET = syncIO >>> fmapLT tshow

whenM :: Monad m => m Bool -> m () -> m ()
whenM c a = c >>= \res -> when res a

bytestringToText :: BSL.ByteString -> Text
bytestringToText = BSL.toStrict >>> T.decodeUtf8

ourReadProcessInterleaved_ ::
     MonadIO m
  => ProcessConfig stdin stdoutIgnored stderrIgnored
  -> ExceptT Text m Text
ourReadProcessInterleaved_ processConfig =
  readProcessInterleaved_ processConfig & tryIOTextET & fmapRT bytestringToText

silently :: ProcessConfig stdin stdout stderr -> ProcessConfig () () ()
silently t = setStdin closed $ setStdout closed $ setStderr closed t
