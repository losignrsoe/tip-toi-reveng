import Options.Applicative

import System.FilePath
import Numeric
import Data.List (intercalate)
import Options.Applicative.Help.Chunk
import Data.Monoid

import Types
import RangeParser
import Commands
import Utils

-- Parameter parsing

optionParser :: ParserInfo (IO ())
optionParser =
    info (helper <*> (conf <**> cmd)) $
    progDesc $ "tttool-" ++ tttoolVersion ++ " -- The swiss army knife for the Tiptoi hacker"
  where
    conf = pure Conf <*> transscript <*> dpi <*> pixelSize

    transscript = optional $ strOption $ mconcat
        [ long "transscript"
        , short 't'
        , metavar "FILE"
        , help "Mapping from media file indices to plaintext. This should be a ';'-separated file, with OID codes in the first column and plain text in the second"
        ]

    dpi = option (only [1200,600] auto) $ mconcat
        [ long "dpi"
        , metavar "DPI"
        , value 1200
        , showDefault
        , help "Use this resolution in dpi when creating OID-Codes"
        ]

    pixelSize = option (only [1,2] auto) $ mconcat
        [ long "pixel-size"
        , metavar "N"
        , value 1
        , showDefault
        , help "Use this many pixels per dot in when creating OID-Codes."
        ]

    cmd = subparser $ mconcat
        [ cmdSep "GME creation commands:"
        , assembleCmd
        , cmdSep ""

        , cmdSep "OID code creation commands:"
        , oidTableCmd
        , oidCodesCmd
        , oidCodeCmd
        , cmdSep ""

        , cmdSep "GME analysis commands:"
        , infoCmd
        , exportCmd
        , scriptsCmd
        , scriptCmd
        , gamesCmd
        , lintCmd
        , segmentsCmd
        , segmentCmd
        , explainCmd
        , holesCmd
        , rewriteCmd
        , cmdSep ""

        , cmdSep "GME extraction commands:"
        , mediaCmd
        , binariesCmd
        , cmdSep ""

        , cmdSep "Simulation commands:"
        , playCmd
        ]

only :: (Eq a, Show a) => [a] -> ReadM a -> ReadM a
only valid r = do
    x <- r
    if x `elem` valid then return x
                      else readerError msg
  where msg = "Sorry, supported values are only: " ++ intercalate ", " (map show valid)

cmdSep :: String -> Mod CommandFields a
cmdSep s = command s $ info empty mempty


-- Common option Parsers

gmeFileParser :: Parser FilePath
gmeFileParser = strArgument $ mconcat
    [ metavar "GME"
    , help "GME file to read"
    ]

yamlFileParser :: Parser FilePath
yamlFileParser = strArgument $ mconcat
    [ metavar "YAML"
    , help "Yaml file to read"
    ]

rawSwitchParser :: Parser Bool
rawSwitchParser = switch $ mconcat
    [ long "raw"
    , help "print the scripts in their raw form"
    ]

-- Individual commands

infoCmd :: Mod CommandFields (Conf -> IO ())
infoCmd =
    command "info" $
    info (helper <*> parser) $
    progDesc "Print general information about a GME file"
  where
    parser = flip dumpInfo <$> gmeFileParser


mediaCmd :: Mod CommandFields (Conf -> IO ())
mediaCmd =
    command "media" $
    info (helper <*> parser) $
    progDesc "dumps all audio samples"
  where
    parser = const <$> (dumpAudioTo <$> mediaDirParser <*> gmeFileParser)

    mediaDirParser :: Parser FilePath
    mediaDirParser = strOption $ mconcat
        [ long "dir"
        , short 'd'
        , metavar "DIR"
        , help "Media output directory"
        , value "media"
        , showDefault
        ]

scriptsCmd :: Mod CommandFields (Conf -> IO ())
scriptsCmd =
    command "scripts" $
    info (helper <*> parser) $
    progDesc "prints the decoded scripts for each OID"
  where
    parser = (\r f c -> dumpScripts c r Nothing f)
        <$> rawSwitchParser
        <*> gmeFileParser


scriptCmd :: Mod CommandFields (Conf -> IO ())
scriptCmd =
    command "script" $
    info (helper <*> parser) $
    progDesc "prints the decoded scripts for a specific OID"
  where
    parser = (\r f n c -> dumpScripts c r (Just n) f)
        <$> rawSwitchParser
        <*> gmeFileParser
        <*> scriptParser

    scriptParser = argument auto $ mconcat
        [ metavar "OID"
        , help "OID to look up"
        ]

binariesCmd :: Mod CommandFields (Conf -> IO ())
binariesCmd =
    command "binaries" $
    info (helper <*> parser) $
    progDesc "dumps all binaries"
  where
    parser = const <$> (dumpBinariesTo <$> binariesDirParser <*> gmeFileParser)

    binariesDirParser :: Parser FilePath
    binariesDirParser = strOption $ mconcat
        [ long "dir"
        , short 'd'
        , metavar "DIR"
        , help "Binaries output directory"
        , value "binaries"
        , showDefault
        ]

gamesCmd :: Mod CommandFields (Conf -> IO ())
gamesCmd =
    command "games" $
    info (helper <*> parser) $
    progDesc "prints the decoded games"
  where
    parser = flip dumpGames <$> gmeFileParser

lintCmd :: Mod CommandFields (Conf -> IO ())
lintCmd =
    command "lint" $
    info (helper <*> parser) $
    progDesc "checks for errors in the file or in this program"
  where
    parser = const <$> (lint <$> gmeFileParser)

segmentsCmd :: Mod CommandFields (Conf -> IO ())
segmentsCmd =
    command "segments" $
    info (helper <*> parser) $
    progDesc "lists all known parts of the file, with description."
  where
    parser = const <$> (segments <$> gmeFileParser)


segmentCmd :: Mod CommandFields (Conf -> IO ())
segmentCmd =
    command "segment" $
    info (helper <*> parser) $
    progDesc "prints the decoded scripts for a specific OID"
  where
    parser = (\f n c -> findPosition n f)
        <$> gmeFileParser
        <*> offsetParser

    offsetParser = argument hexReadM $ mconcat
        [ metavar "POS"
        , help "offset into the file to look up, in bytes"
        ]

    hexReadM :: ReadM Integer
    hexReadM = eitherReader go
      where go n | Just int <- readMaybe n = return int
                 | [(int,[])] <- readHex n = return int
                 | otherwise               = Left $ "Cannot parse offset " ++ n

holesCmd :: Mod CommandFields (Conf -> IO ())
holesCmd =
    command "holes" $
    info (helper <*> parser) $
    progDesc "lists all unknown parts of the file."
  where
    parser = const <$> (unknown_segments <$> gmeFileParser)

explainCmd :: Mod CommandFields (Conf -> IO ())
explainCmd =
    command "explain" $
    info (helper <*> parser) $
    progDesc "print a hexdump of a GME file with descriptions"
  where
    parser = const <$> (explain <$> gmeFileParser)

playCmd :: Mod CommandFields (Conf -> IO ())
playCmd =
    command "play" $
    info (helper <*> parser) $
    progDesc "interactively play a GME file"
  where
    parser = flip play <$> gmeFileParser


rewriteCmd :: Mod CommandFields (Conf -> IO ())
rewriteCmd =
    command "rewrite" $
    info (helper <*> parser) $
    progDesc "parses the file and reads it again (for debugging)"
  where
    parser = const <$> (rewrite <$> gmeFileParser <*> outFileParser)

    outFileParser :: Parser FilePath
    outFileParser = strArgument $ mconcat
        [ metavar "OUT"
        , help "GME file to write"
        ]

twoFiles :: String -> (FilePath -> FilePath -> a) -> (FilePath -> Maybe FilePath -> a)
twoFiles suffix go inFile (Just outFile) = go inFile outFile
twoFiles suffix go inFile Nothing = go inFile outFile
  where outFile = dropExtension inFile <.> suffix


exportCmd :: Mod CommandFields (Conf -> IO ())
exportCmd =
    command "export" $
    info (helper <*> parser) $
    progDesc "dumps the file in the human-readable yaml format"
  where
    parser = const <$> (twoFiles "yaml" export <$> gmeFileParser <*> outFileParser)

    outFileParser :: Parser (Maybe FilePath)
    outFileParser = optional $ strArgument $ mconcat
        [ metavar "OUT"
        , help "YAML file to write"
        ]

assembleCmd :: Mod CommandFields (Conf -> IO ())
assembleCmd =
    command "assemble" $
    info (helper <*> parser) $
    progDesc "creates a gme file from the given source"
  where
    parser = const <$> (twoFiles "gme" assemble <$> yamlFileParser <*> outFileParser)

    outFileParser :: Parser (Maybe FilePath)
    outFileParser = optional $ strArgument $ mconcat
        [ metavar "OUT"
        , help "GME file to write"
        ]

oidTableCmd :: Mod CommandFields (Conf -> IO ())
oidTableCmd =
    command "oid-table" $
    info (helper <*> parser) $
    progDesc "creates a PDF file with all codes in the yaml file"
  where
    parser = const <$> (twoFiles "pdf" genOidTable <$> yamlFileParser <*> outFileParser)

    outFileParser :: Parser (Maybe FilePath)
    outFileParser = optional $ strArgument $ mconcat
        [ metavar "OUT"
        , help "PDF file to write"
        ]

oidCodesCmd :: Mod CommandFields (Conf -> IO ())
oidCodesCmd =
    command "oid-codes" $
    info (helper <*> parser) $
    progDesc "creates PNG files for every OID in the yaml file." <>
    footer "Uses oid-<product-id>-<scriptname or code>.png as the file name."
  where
    parser = flip genPNGsForFile <$> yamlFileParser

oidCodeCmd :: Mod CommandFields (Conf -> IO ())
oidCodeCmd =
    command "oid-code" $
    info (helper <*> parser) $
    progDesc "creates PNG files for each given code(s)" <>
    footerDoc foot
  where
    foot = unChunk $ vsepChunks
        [ paragraph "Uses oid-<code>.png as the file name."
        , paragraph $ "Note that it used to work to call \"tttool oid-code foo.yaml\". " ++
                      "Please use \"tttool oid-codes\" for that now."
        ]

    parser =(\raw range c -> genPNGsForCodes raw c range) <$> rawCodeSwitchParser <*> codeRangeParser

    codeRangeParser :: Parser [Word16]
    codeRangeParser = argument (eitherReader parseRange) $ mconcat
        [ metavar "RANGE"
        , help "OID range, for example e.g. 1,3,1000-1085."
        ]

    rawCodeSwitchParser :: Parser Bool
    rawCodeSwitchParser = switch $ mconcat
        [ long "raw"
        , help "take the given codes as \"raw codes\" (rarely needed)"
        ]

main :: IO ()
main = do
    act <- execParser optionParser
    act
