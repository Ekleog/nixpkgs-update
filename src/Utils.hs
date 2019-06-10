{-# LANGUAGE ExtendedDefaultRules #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -fno-warn-type-defaults #-}

module Utils
  ( Options(..)
  , Version
  , UpdateEnv(..)
  , setupNixpkgs
  , tRead
  , parseUpdates
  , overwriteErrorT
  , branchName
  , runtimeDir
  , srcOrMain
  , prTitle
  , eTError
  ) where

import OurPrelude

import Data.Bits ((.|.))
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, setCurrentDirectory)
import System.Environment.XDG.BaseDir
import System.Posix.Directory (createDirectory)
import System.Posix.Env (getEnv, setEnv)
import System.Posix.Files
  ( directoryMode
  , fileExist
  , groupModes
  , otherExecuteMode
  , otherReadMode
  , ownerModes
  )
import System.Posix.Temp (mkdtemp)
import System.Posix.Types (FileMode)
import qualified System.Process.Typed

default (T.Text)

type Version = Text

data Options = Options
  { dryRun :: Bool
  , githubToken :: Text
  } deriving (Show)

data UpdateEnv = UpdateEnv
  { packageName :: Text
  , oldVersion :: Version
  , newVersion :: Version
  , options :: Options
  }

prTitle :: UpdateEnv -> Text -> Text
prTitle updateEnv attrPath =
  let oV = oldVersion updateEnv
      nV = newVersion updateEnv
   in [interpolate| $attrPath: $oV -> $nV |]

regDirMode :: FileMode
regDirMode =
  directoryMode .|. ownerModes .|. groupModes .|. otherReadMode .|.
  otherExecuteMode

xdgRuntimeDir :: MonadIO m => ExceptT Text m FilePath
xdgRuntimeDir = do
  xDir <-
    noteT "Could not get environment variable XDG_RUNTIME_DIR" $
    MaybeT $ liftIO $ getEnv "XDG_RUNTIME_DIR"
  xDirExists <- liftIO $ doesDirectoryExist xDir
  tryAssert ("XDG_RUNTIME_DIR " <> T.pack xDir <> " does not exist.") xDirExists
  let dir = xDir <> "/nixpkgs-update"
  dirExists <- liftIO $ fileExist dir
  unless
    dirExists
    (liftIO $
     putStrLn "creating xdgRuntimeDir" >> createDirectory dir regDirMode)
  return dir

tmpRuntimeDir :: MonadIO m => ExceptT Text m FilePath
tmpRuntimeDir = do
  dir <- liftIO $ mkdtemp "nixpkgs-update"
  dirExists <- liftIO $ doesDirectoryExist dir
  tryAssert
    ("Temporary directory " <> T.pack dir <> " does not exist.")
    dirExists
  return dir

runtimeDir :: IO FilePath
runtimeDir = do
  r <-
    runExceptT
      (xdgRuntimeDir <|> tmpRuntimeDir <|>
       throwE
         "Failed to create runtimeDir from XDG_RUNTIME_DIR or tmp directory")
  case r of
    Right dir -> return dir
    Left e -> error $ T.unpack e

setupNixpkgs :: Options -> IO ()
setupNixpkgs o = do
  fp <- getUserCacheDir "nixpkgs"
  exists <- doesDirectoryExist fp
  unless exists $ do
    proc "hub" ["clone", "nixpkgs", fp] & -- requires that user has forked nixpkgs
      System.Process.Typed.setEnv
        [("GITHUB_TOKEN" :: String, githubToken o & T.unpack)] &
      runProcess_
    setCurrentDirectory fp
    shell "git remote add upstream https://github.com/NixOS/nixpkgs" &
      runProcess_
    shell "git fetch upstream" & runProcess_
  setCurrentDirectory fp
  setEnv "NIX_PATH" ("nixpkgs=" <> fp) True

overwriteErrorT :: Member (Error Text) r => Text -> Sem r a -> Sem r a
overwriteErrorT t = flip catch (const (throw t))

branchName :: UpdateEnv -> Text
branchName ue = "auto-update/" <> packageName ue

parseUpdates :: Text -> [Either Text (Text, Version, Version)]
parseUpdates = map (toTriple . T.words) . T.lines
  where
    toTriple :: [Text] -> Either Text (Text, Version, Version)
    toTriple [package, oldVer, newVer] = Right (package, oldVer, newVer)
    toTriple line = Left $ "Unable to parse update: " <> T.unwords line

tRead :: Read a => Text -> a
tRead = read . T.unpack

srcOrMain ::
     Members '[ Lift IO, Error Text] r => (Text -> Sem r a) -> Text -> Sem r a
srcOrMain et attrPath = et (attrPath <> ".src") `catch` const (et attrPath)

eTError :: Member (Error e) r => ExceptT e (Sem r) a -> Sem r a
eTError et = do
  e <- runExceptT et
  case e of
    Left err -> throw err
    Right a -> return a
