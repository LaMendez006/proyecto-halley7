{-# LANGUAGE OverloadedStrings #-}

-- | Una sola noción de hora: todo termina en 'UTCTime'.
module Hora
  ( diaDelCaso, margenMinuto, margenAprox
  , parseEpoch, parseHHMMpunto, parseHHMMdospuntos, parseIsoSinZona
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time
  (Day, UTCTime (..), defaultTimeLocale, fromGregorian, parseTimeM, secondsToDiffTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Text.Read (readMaybe)

-- | Presencia y radio solo traen la hora, no la fecha: se asume la noche del caso.
diaDelCaso :: Day
diaDelCaso = fromGregorian 2041 6 14

-- | Márgenes en minutos
margenMinuto, margenAprox :: Int
margenMinuto = 1    -- fuentes con resolución de minuto (presencia, radio)
margenAprox  = 10   -- "aprox." de la bitácora

-- | Epoch (segundos desde 1970) a UTC. Total: nunca falla.
parseEpoch :: Integer -> UTCTime
parseEpoch = posixSecondsToUTCTime . fromIntegral

-- | "01.30" (presencia).
parseHHMMpunto :: Day -> Text -> Either Text UTCTime
parseHHMMpunto = parseHoraMinuto '.'

-- | "01:47" (radio, bitácora).
parseHHMMdospuntos :: Day -> Text -> Either Text UTCTime
parseHHMMdospuntos = parseHoraMinuto ':'

-- | "2041-06-14T01:20:33" sin zona (tarjetas, energía): se interpreta como UTC.
parseIsoSinZona :: Text -> Either Text UTCTime
parseIsoSinZona crudo =
  maybe (Left ("fecha-hora ISO inválida: " <> crudo)) Right
    (parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S" (T.unpack (T.strip crudo)))

-- | Lógica común de "HH<sep>MM". Valida el rango en vez de confiar en el dato.
parseHoraMinuto :: Char -> Day -> Text -> Either Text UTCTime
parseHoraMinuto sep dia crudo =
  case T.splitOn (T.singleton sep) (T.strip crudo) of
    [hTxt, mTxt] -> do
      h <- entero crudo hTxt
      m <- entero crudo mTxt
      if h `elem` [0 .. 23] && m `elem` [0 .. 59]
        then Right (UTCTime dia (secondsToDiffTime (fromIntegral (h * 3600 + m * 60))))
        else Left ("hora fuera de rango: " <> crudo)
    _ -> Left ("formato de hora no reconocido: " <> crudo)

-- | Texto a entero, con un error que dice en qué dato falló.
entero :: Text -> Text -> Either Text Int
entero crudo t = maybe (Left ("no es un número en: " <> crudo)) Right (readMaybe (T.unpack t))