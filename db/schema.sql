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