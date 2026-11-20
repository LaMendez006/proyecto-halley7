-- Moldeado del problema
module Tipos
  ( Fuente (..), Modulo (..), Puerta (..), Tarjeta (..), Sensor (..)
  , ResultadoAcceso (..), PersonaId (..), Persona (..), HoraEvidencia (..)
  , TipoEvento (..), EstadoEvento (..), Evento (..)
  , Severidad (..), TipoProblema (..), Problema (..)
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)

-- | Las seis fuentes de evidencia.
data Fuente = Tarjetas | Radio | Energia | Presencia | Temperatura | Bitacora
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Los módulos de la estación. 
data Modulo = COM | DOR | LabA | LabB | GEN | RAD | ALM | EXT
  deriving (Eq, Ord, Show, Enum, Bounded)

newtype Puerta  = Puerta Int      deriving (Eq, Ord, Show)  
newtype Tarjeta = Tarjeta Text    deriving (Eq, Ord, Show)  
data Sensor = TAlm | TExt         deriving (Eq, Show)

data ResultadoAcceso = Concedido | Denegado deriving (Eq, Show)

newtype PersonaId = PersonaId Text deriving (Eq, Ord, Show) 

-- | Quién es la persona de un registro: conocida, ambigua o sin identificar.
data Persona
  = Conocida PersonaId
  | Ambigua [PersonaId]    
  | Desconocida Text      
  deriving (Eq, Show)

-- | Cuándo ocurrió algo, con honestidad sobre la precisión.
data HoraEvidencia
  = Exacta UTCTime
  | Aproximada UTCTime Int 
  | HoraDesconocida
  deriving (Eq, Show)

-- | Qué pasó. Cada constructor trae solo los datos que le corresponden.
data TipoEvento
  = AccesoTarjeta Tarjeta Puerta Modulo Modulo ResultadoAcceso 
  | ConteoPersonas Modulo Int
  | PresenciaSinEnergia
  | LecturaTemperatura Sensor Double
  | CorteEnergia [Modulo]
  | EnergiaRestablecida
  | ConsumoElectrico [(Modulo, Double)]
  | MensajeRadio Text Text           
  | NotaBitacora Text
  deriving (Eq, Show)

data EstadoEvento = Valido | Sospechoso | Ambiguo deriving (Eq, Show)

-- | Un registro de evidencia ya validado, con hora UTC e identidad unificadas.
data Evento = Evento
  { evId      :: Text              
  , evFuente  :: Fuente
  , evLinea   :: Int               
  , evHora    :: HoraEvidencia
  , evPersona :: Maybe Persona     
  , evTipo    :: TipoEvento
  , evEstado  :: EstadoEvento
  , evCrudo   :: Text              
  } deriving (Eq, Show)

data Severidad = Baja | Media | Alta deriving (Eq, Ord, Show)

data TipoProblema
  = Duplicado | Corrupto | SeparadorDistinto | HoraFormatoRaro | FechaAusente
  | LineaFusionada | ModuloNombreAlterno | AliasUsado | AliasAmbiguo
  | Contradiccion | TarjetaSospechosa
  deriving (Eq, Show)

-- | Un dato que no se pudo usar tal cual. Se conserva con su motivo.
data Problema = Problema
  { pId          :: Text
  , pFuente      :: Fuente
  , pLinea       :: Int
  , pTipo        :: TipoProblema
  , pDescripcion :: Text
  , pCrudo       :: Text
  , pSeveridad   :: Severidad
  , pEvidencia   :: [Text]       
  } deriving (Eq, Show)