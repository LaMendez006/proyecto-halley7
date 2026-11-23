-- =====================================================================
-- Halley-7 · Esquema de la base de datos (PostgreSQL 16)
-- Responsable: Integrante 2 (Java + BD)
--
-- Este archivo se puede aplicar varias veces sin fallar (idempotente):
-- todas las tablas usan CREATE TABLE IF NOT EXISTS. Lo ejecuta
-- scripts/setup_db.sh con un usuario administrador.
--
-- El esquema tiene dos grupos de tablas:
--   1. Tablas de REFERENCIA (esta sección): describen la estación tal
--      como es (personas, tarjetas, módulos, puertas, fuentes, alias).
--      Salen de personal.csv, estacion.csv y del enunciado.
--   2. Tablas de EVIDENCIA, solo-anexo (siguiente sección): lo que la
--      estación registró, los problemas, las correcciones, las consultas
--      y las respuestas. Esas nunca se modifican ni se borran.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. TABLAS DE REFERENCIA
-- ---------------------------------------------------------------------

-- Las seis personas de la estación.
-- id es el identificador canónico que usan los cuatro lenguajes
-- (Haskell, Prolog, Java y Julia). Se arma con el apellido en
-- minúsculas y sin tildes: okafor, vidal, ruiz, petrov, kimura, valcarcel.
CREATE TABLE IF NOT EXISTS personas (
    id      TEXT PRIMARY KEY,
    nombre  TEXT NOT NULL UNIQUE,   -- nombre completo tal como aparece en personal.csv
    cargo   TEXT NOT NULL
);

-- Tarjetas de acceso: cada tarjeta pertenece a una persona.
-- OJO: aquí NO se guarda que Petrov perdió su tarjeta. Ese hecho viene
-- de la bitácora (12/06), es decir, es EVIDENCIA y no referencia. Si lo
-- pusiéramos aquí, lo estaríamos tratando como verdad indiscutible y
-- no podríamos citar de dónde salió.
CREATE TABLE IF NOT EXISTS tarjetas (
    codigo      TEXT PRIMARY KEY,   -- p. ej. 'LP-04'
    persona_id  TEXT NOT NULL UNIQUE REFERENCES personas(id)
);

-- Módulos de la estación. EXT es el exterior (la plataforma de hielo).
CREATE TABLE IF NOT EXISTS modulos (
    id      TEXT PRIMARY KEY,       -- 'COM', 'DOR', 'LAB-A', ... (código oficial)
    nombre  TEXT NOT NULL,          -- 'Comedor', 'Dormitorios', ...
    interior BOOLEAN NOT NULL       -- FALSE solo para EXT
);

-- Puertas: cada una une dos módulos (el grafo de la estación).
-- El grafo es NO dirigido: la puerta se puede cruzar en ambos sentidos;
-- el orden modulo_1 / modulo_2 es solo el del archivo estacion.csv.
CREATE TABLE IF NOT EXISTS puertas (
    id                  TEXT PRIMARY KEY,                    -- 'P1' ... 'P8'
    modulo_1            TEXT NOT NULL REFERENCES modulos(id),
    modulo_2            TEXT NOT NULL REFERENCES modulos(id),
    lector_tarjeta      BOOLEAN NOT NULL,                    -- TRUE si registra tarjetas
    palanca_emergencia  BOOLEAN NOT NULL DEFAULT FALSE,      -- solo P8: abre sin tarjeta y sin registro
    CHECK (modulo_1 <> modulo_2)
);

-- Qué puertas puede abrir cada tarjeta (columna "accesos" de personal.csv,
-- que viene como "P2 P3 P4" y aquí se guarda una fila por puerta).
-- Es una relación muchos-a-muchos entre tarjetas y puertas.
CREATE TABLE IF NOT EXISTS accesos (
    tarjeta_codigo  TEXT NOT NULL REFERENCES tarjetas(codigo),
    puerta_id       TEXT NOT NULL REFERENCES puertas(id),
    PRIMARY KEY (tarjeta_codigo, puerta_id)
);

-- Fuentes de datos. Además de los 8 archivos, hay una fuente "vivo"
-- para las lecturas que llegan del simulador de Julia.
CREATE TABLE IF NOT EXISTS fuentes (
    id            TEXT PRIMARY KEY,   -- 'tarjetas', 'radio', 'energia', ...
    archivo       TEXT,               -- nombre del archivo original (NULL para 'vivo')
    clase         TEXT NOT NULL CHECK (clase IN ('evidencia', 'referencia', 'vivo')),
    formato       TEXT NOT NULL,      -- descripción corta del formato
    nota_hora     TEXT NOT NULL       -- cómo viene la hora en esta fuente
);

-- Alias: formas en que las fuentes nombran a las personas
-- ("jefe", "Luka", "Irene", "doc"...).
-- Un alias puede apuntar a VARIAS personas: si hay más de una fila con
-- el mismo texto, ese alias es AMBIGUO. Así "doc" tiene dos filas
-- (vidal y valcarcel) y el sistema puede responder con ambas opciones
-- en vez de elegir una al azar. Se guarda en minúsculas.
CREATE TABLE IF NOT EXISTS alias (
    texto       TEXT NOT NULL CHECK (texto = lower(texto)),
    persona_id  TEXT NOT NULL REFERENCES personas(id),
    motivo      TEXT NOT NULL,        -- por qué el equipo decidió esta equivalencia
    PRIMARY KEY (texto, persona_id)
);

-- Vista de ayuda: cada alias con su lista de candidatos y si es ambiguo.
CREATE OR REPLACE VIEW alias_resuelto AS
SELECT texto,
       array_agg(persona_id ORDER BY persona_id) AS candidatos,
       count(*) > 1                              AS ambiguo
FROM alias
GROUP BY texto;



-- ---------------------------------------------------------------------
-- 2. TABLAS DE EVIDENCIA (SOLO-ANEXO)
--
-- Regla del proyecto: estas tablas solo reciben INSERT. Nunca UPDATE ni
-- DELETE. Eso lo garantizan los triggers de db/triggers.sql y los
-- permisos del rol de la aplicación.
--
-- Todas tienen dos identificadores:
--   seq : número automático y creciente que da el orden de llegada.
--   id  : identificador legible que viaja en los JSON ('tarj-000123',
--         'prob-0007'...). Es TEXTO porque así lo genera Haskell.
-- ---------------------------------------------------------------------

-- Cada registro de evidencia: una línea de un archivo, una lectura en
-- vivo o una evidencia derivada (por ejemplo, una anomalía que detecta Julia).
CREATE TABLE IF NOT EXISTS evidencia (
    seq             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id              TEXT NOT NULL UNIQUE,
    fuente_id       TEXT NOT NULL REFERENCES fuentes(id),

    -- De dónde salió el registro:
    --   archivo  = una de las 6 fuentes recuperadas (vía Haskell)
    --   vivo     = lectura que llegó del simulador (vía Julia)
    --   derivada = la calculó el sistema (anomalía). Se marca para no
    --              mezclarla nunca con el dato crudo.
    origen          TEXT NOT NULL CHECK (origen IN ('archivo', 'vivo', 'derivada')),
    linea           INT,                    -- línea del archivo original (NULL si es en vivo)

    -- Qué pasó. Coincide con los constructores de TipoEvento en Haskell.
    tipo            TEXT NOT NULL CHECK (tipo IN (
                        'acceso_tarjeta', 'conteo_personas', 'presencia_sin_energia',
                        'lectura_temperatura', 'corte_energia', 'energia_restablecida',
                        'consumo_electrico', 'mensaje_radio', 'nota_bitacora',
                        'anomalia_temperatura')),

    -- Quién. persona_texto guarda el nombre TAL COMO apareció ("doc",
    -- "Luka"); persona_id es la identidad canónica si se pudo resolver.
    -- Si el alias es ambiguo, persona_id queda NULL y los candidatos se
    -- obtienen uniendo persona_texto con la tabla alias.
    persona_texto   TEXT,
    persona_id      TEXT REFERENCES personas(id),
    tarjeta_codigo  TEXT REFERENCES tarjetas(codigo),   -- NULL si la tarjeta es ilegible ('AK-0?')
    modulo_id       TEXT REFERENCES modulos(id),
    puerta_id       TEXT REFERENCES puertas(id),

    -- Cuándo. Siempre en UTC. Se conserva además la hora original tal
    -- como venía ('01.30', '2254786200', '01:50 aprox.').
    ts_utc          TIMESTAMPTZ,
    ts_precision    TEXT NOT NULL CHECK (ts_precision IN ('exacta', 'aproximada', 'desconocida')),
    ts_margen_min   INT  NOT NULL DEFAULT 0 CHECK (ts_margen_min >= 0),
    ts_original     TEXT,

    -- Estado del registro. Los corruptos y duplicados SE GUARDAN (no se
    -- descartan), pero Prolog no los usa como prueba.
    estado          TEXT NOT NULL CHECK (estado IN (
                        'valido', 'sospechoso', 'ambiguo', 'duplicado', 'corrupto')),

    -- Datos propios de cada tipo (valor de temperatura, módulos afectados
    -- por un corte, texto del mensaje de radio...). Se usa JSONB porque
    -- cada tipo de evento trae campos distintos.
    datos           JSONB NOT NULL DEFAULT '{}'::jsonb,
    crudo           TEXT  NOT NULL,          -- la línea original, intacta
    recibido_en     TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Coherencia de la hora: si es exacta o aproximada debe existir;
    -- si es desconocida no puede tener valor.
    CHECK ((ts_precision = 'desconocida') = (ts_utc IS NULL)),
    -- Solo una hora aproximada puede tener margen.
    CHECK (ts_precision = 'aproximada' OR ts_margen_min = 0)
);

-- Índices para las búsquedas más comunes (por hora, persona y módulo).
CREATE INDEX IF NOT EXISTS evidencia_ts_idx      ON evidencia (ts_utc);
CREATE INDEX IF NOT EXISTS evidencia_persona_idx ON evidencia (persona_id);
CREATE INDEX IF NOT EXISTS evidencia_modulo_idx  ON evidencia (modulo_id);

-- Problemas encontrados en las fuentes. Coincide con TipoProblema en Haskell.
CREATE TABLE IF NOT EXISTS problemas (
    seq             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id              TEXT NOT NULL UNIQUE,
    fuente_id       TEXT NOT NULL REFERENCES fuentes(id),
    linea           INT,
    tipo            TEXT NOT NULL CHECK (tipo IN (
                        'duplicado', 'corrupto', 'separador_distinto', 'hora_formato_raro',
                        'fecha_ausente', 'linea_fusionada', 'modulo_nombre_alterno',
                        'alias_usado', 'alias_ambiguo', 'contradiccion',
                        'tarjeta_sospechosa')),
    descripcion     TEXT NOT NULL,
    crudo           TEXT,
    severidad       TEXT NOT NULL CHECK (severidad IN ('baja', 'media', 'alta')),
    registrado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Qué evidencia sustenta cada problema. Una contradicción, por ejemplo,
-- apunta a tres registros: energía 01:40, radio 01:47 y bitácora 01:50.
-- Es una tabla aparte (y no un arreglo) para poder poner llaves foráneas.
CREATE TABLE IF NOT EXISTS problema_evidencia (
    problema_id     TEXT NOT NULL REFERENCES problemas(id),
    evidencia_id    TEXT NOT NULL REFERENCES evidencia(id),
    PRIMARY KEY (problema_id, evidencia_id)
);

-- Correcciones enviadas por las agencias. NUNCA tocan la fila original:
-- se guardan como una nueva versión de un campo. La vista
-- evidencia_corregida (se agrega en un commit posterior) aplica la última
-- versión de cada campo sobre la evidencia original.
CREATE TABLE IF NOT EXISTS correcciones (
    seq             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id              TEXT NOT NULL UNIQUE,
    evidencia_id    TEXT NOT NULL REFERENCES evidencia(id),
    version         INT  NOT NULL CHECK (version >= 1),   -- 1, 2, 3... por registro de evidencia
    campo           TEXT NOT NULL CHECK (campo IN (
                        'ts_utc', 'persona_id', 'tarjeta_codigo', 'modulo_id', 'estado')),
    valor_nuevo     TEXT,                    -- como texto; Java lo valida según el campo
    motivo          TEXT NOT NULL,           -- p. ej. 'reloj del lector P4 adelantado 3 min'
    autor           TEXT NOT NULL,           -- agencia o investigador que la envía
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (evidencia_id, version)
);

-- Preguntas que hacen los investigadores.
-- snapshot_version es el número de la última entrada de la cadena de
-- hashes que se tuvo en cuenta (ver tabla cadena). Con ese número se
-- puede reconstruir exactamente qué evidencia y qué correcciones existían
-- cuando se hizo la pregunta.
CREATE TABLE IF NOT EXISTS consultas (
    seq               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id                TEXT NOT NULL UNIQUE,
    investigador_id   TEXT NOT NULL,
    pregunta          JSONB NOT NULL,        -- el JSON de consulta del contrato
    snapshot_version  BIGINT NOT NULL CHECK (snapshot_version >= 0),
    vista             TEXT NOT NULL CHECK (vista IN ('original', 'corregida')),
    creado_en         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Respuestas. Una por consulta. Se guarda el JSON completo para poder
-- compararlo después con una reconstrucción.
CREATE TABLE IF NOT EXISTS respuestas (
    seq             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id              TEXT NOT NULL UNIQUE,
    consulta_id     TEXT NOT NULL UNIQUE REFERENCES consultas(id),
    resultado       TEXT NOT NULL CHECK (resultado IN ('posible', 'imposible', 'no_se_puede_saber')),
    razon           TEXT NOT NULL,
    contenido       JSONB NOT NULL,          -- respuesta completa tal como la devolvió Prolog
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Evidencia citada por cada respuesta.
CREATE TABLE IF NOT EXISTS respuesta_evidencia (
    respuesta_id    TEXT NOT NULL REFERENCES respuestas(id),
    evidencia_id    TEXT NOT NULL REFERENCES evidencia(id),
    PRIMARY KEY (respuesta_id, evidencia_id)
);

-- Cadena de hashes GLOBAL. Cada registro que entra a una tabla
-- solo-anexo agrega aquí un eslabón:
--     hash = SHA-256( hash_anterior || contenido_canonico_del_registro )
-- El primer eslabón usa como hash_anterior 64 ceros (el "génesis").
-- Si alguien altera una fila, al recalcular su hash ya no coincide y el
-- verificador señala el eslabón exacto. Como hay una sola cadena para
-- todas las tablas, seq da además un orden total de todo lo que entró.
-- El contenido canónico lo calcula Java (se documenta en ese commit).
CREATE TABLE IF NOT EXISTS cadena (
    seq             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabla           TEXT NOT NULL CHECK (tabla IN (
                        'evidencia', 'problemas', 'correcciones', 'consultas', 'respuestas')),
    registro_id     TEXT NOT NULL,           -- el id del registro en esa tabla
    hash_anterior   CHAR(64) NOT NULL CHECK (hash_anterior ~ '^[0-9a-f]{64}$'),
    hash            CHAR(64) NOT NULL UNIQUE CHECK (hash ~ '^[0-9a-f]{64}$'),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tabla, registro_id)              -- cada registro entra a la cadena una sola vez
);