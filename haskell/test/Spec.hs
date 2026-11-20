{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Data.Either (isLeft)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Hora

-- | Hora del 14/06/2041 en UTC, para escribir los resultados esperados.
del14 :: Integer -> Integer -> Integer -> UTCTime
del14 h m s = UTCTime (fromGregorian 2041 6 14) (secondsToDiffTime (h * 3600 + m * 60 + s))

main :: IO ()
main = hspec $ do
  describe "parseEpoch" $ do
    it "2254786200 es 01:30 UTC del 14/06/2041" $
      parseEpoch 2254786200 `shouldBe` del14 1 30 0
    it "los extremos de la caída de temperatura: 01:50 y 02:00" $ do
      parseEpoch 2254787400 `shouldBe` del14 1 50 0
      parseEpoch 2254788000 `shouldBe` del14 2 0 0

  describe "parseHHMMpunto" $ do
    it "convierte 01.30" $
      parseHHMMpunto diaDelCaso "01.30" `shouldBe` Right (del14 1 30 0)
    it "acepta medianoche" $
      parseHHMMpunto diaDelCaso "00.00" `shouldBe` Right (del14 0 0 0)
    it "acepta un dígito (1.5 es 01:05)" $
      parseHHMMpunto diaDelCaso "1.5" `shouldBe` Right (del14 1 5 0)
    it "rechaza una hora inválida (25.99)" $
      parseHHMMpunto diaDelCaso "25.99" `shouldSatisfy` isLeft
    it "rechaza texto corrupto" $
      parseHHMMpunto diaDelCaso "0#.4?" `shouldSatisfy` isLeft

  describe "parseHHMMdospuntos" $
    it "convierte 01:47" $
      parseHHMMdospuntos diaDelCaso "01:47" `shouldBe` Right (del14 1 47 0)

  describe "parseIsoSinZona" $ do
    it "convierte una hora de tarjeta" $
      parseIsoSinZona "2041-06-14T01:20:33" `shouldBe` Right (del14 1 20 33)
    it "rechaza la fila corrupta" $
      parseIsoSinZona "2041-06-14T0#:4?:1?" `shouldSatisfy` isLeft