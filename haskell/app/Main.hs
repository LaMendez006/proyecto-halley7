{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Exception (SomeException, try)
import qualified Data.ByteString.Lazy.Char8 as BL
import Network.HTTP.Client
  (Manager, defaultManagerSettings, httpLbs, newManager, parseRequest, responseBody)

-- | Nombre y URL de cada servicio de los compañeros.
servicios :: [(String, String)]
servicios =
  [ ("java",   "http://localhost:8080/ping")
  , ("prolog", "http://localhost:8082/ping")
  , ("julia",  "http://localhost:8083/ping")
  ]

-- | Hace GET a un servicio e imprime su respuesta (o el error si no contesta).
pingServicio :: Manager -> (String, String) -> IO ()
pingServicio gestor (nombre, url) = do
  resultado <- try $ do
    peticion  <- parseRequest url
    respuesta <- httpLbs peticion gestor
    pure (BL.unpack (responseBody respuesta))
  case resultado of
    Right cuerpo -> putStrLn (nombre ++ " -> " ++ cuerpo)
    Left (e :: SomeException) -> putStrLn (nombre ++ " -> NO RESPONDE: " ++ show e)

main :: IO ()
main = do
  gestor <- newManager defaultManagerSettings
  mapM_ (pingServicio gestor) servicios