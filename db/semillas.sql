-- =====================================================================
-- Halley-7 · Datos de referencia (semillas)
-- Responsable: Integrante 2 (Java + BD)
--
-- Llena las tablas de referencia. Las personas, tarjetas, accesos y
-- puertas se leen DIRECTAMENTE de data/entrada/personal.csv y
-- data/entrada/estacion.csv (no se vuelven a escribir a mano, para no
-- introducir errores de copia). Lo que no está en ningún archivo (nombres
-- de los módulos, palanca de P8, alias) sale del enunciado o de una
-- decisión del equipo, y se indica en cada caso.
--
-- Se ejecuta desde la RAÍZ del repositorio (setup_db.sh se encarga),
-- porque \copy usa rutas relativas a la carpeta actual.
-- Es idempotente: ON CONFLICT DO NOTHING evita duplicar filas.
-- =====================================================================

-- Si algo falla, se detiene y no deja datos a medias.
\set ON_ERROR_STOP on
BEGIN;

-- ---------------------------------------------------------------------
-- Módulos (los nombres vienen de la tabla de la sección 2 del enunciado)
-- ---------------------------------------------------------------------
INSERT INTO modulos (id, nombre, interior) VALUES
    ('COM',   'Comedor',        TRUE),
    ('DOR',   'Dormitorios',    TRUE),
    ('LAB-A', 'Laboratorio A',  TRUE),
    ('LAB-B', 'Laboratorio B',  TRUE),
    ('GEN',   'Generadores',    TRUE),
    ('RAD',   'Sala de radio',  TRUE),
    ('ALM',   'Almacén',        TRUE),
    ('EXT',   'Exterior',       FALSE)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Puertas (desde estacion.csv)
-- Se carga primero a una tabla temporal con las columnas tal como vienen
-- y luego se transforma. Las tablas temporales desaparecen al cerrar
-- la sesión.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_estacion (
    puerta TEXT, modulo_1 TEXT, modulo_2 TEXT, lector_tarjeta TEXT
);
\copy tmp_estacion FROM 'data/entrada/estacion.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO puertas (id, modulo_1, modulo_2, lector_tarjeta, palanca_emergencia)
SELECT trim(puerta),
       trim(modulo_1),
       trim(modulo_2),
       trim(lector_tarjeta) = 'si',
       -- El enunciado (sección 2) dice que P8 tiene una palanca de
       -- emergencia que abre sin tarjeta y sin dejar registro.
       trim(puerta) = 'P8'
FROM tmp_estacion
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Personas, tarjetas y accesos (desde personal.csv)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_personal (
    tarjeta TEXT, nombre TEXT, cargo TEXT, accesos TEXT
);
\copy tmp_personal FROM 'data/entrada/personal.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Identificador canónico = apellido (última palabra del nombre), en
-- minúsculas y sin tildes. 'Irene Valcárcel' -> 'valcarcel'.
INSERT INTO personas (id, nombre, cargo)
SELECT translate(lower(regexp_replace(trim(nombre), '^.*\s', '')), 'áéíóúüñ', 'aeiouun'),
       trim(nombre),
       trim(cargo)
FROM tmp_personal
ON CONFLICT (id) DO NOTHING;

INSERT INTO tarjetas (codigo, persona_id)
SELECT trim(t.tarjeta), p.id
FROM tmp_personal t
JOIN personas p ON p.nombre = trim(t.nombre)
ON CONFLICT (codigo) DO NOTHING;

-- "P2 P3 P4" se parte por espacios en una fila por puerta.
INSERT INTO accesos (tarjeta_codigo, puerta_id)
SELECT trim(t.tarjeta), puerta
FROM tmp_personal t,
     regexp_split_to_table(trim(t.accesos), '\s+') AS puerta
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- Fuentes de datos
-- ---------------------------------------------------------------------
INSERT INTO fuentes (id, archivo, clase, formato, nota_hora) VALUES
    ('tarjetas',    'tarjetas.csv',    'evidencia',  'CSV separado por comas',
                    'ISO 8601 sin zona (UTC según el enunciado)'),
    ('radio',       'radio.txt',       'evidencia',  'Texto: [HH:MM] Hablante: mensaje',
                    'Solo HH:MM; la fecha 14/06/2041 está en el encabezado'),
    ('energia',     'energia.json',    'evidencia',  'JSON con lista de registros',
                    'ISO 8601 sin zona (UTC)'),
    ('presencia',   'presencia.csv',   'evidencia',  'CSV separado por punto y coma',
                    'HH.MM con punto; sin fecha'),
    ('temperatura', 'temperatura.csv', 'evidencia',  'CSV separado por comas',
                    'Epoch en segundos (UTC)'),
    ('bitacora',    'bitacora.txt',    'evidencia',  'Texto libre manuscrito digitalizado',
                    'DD/MM y a veces HH:MM, algunas aproximadas'),
    ('personal',    'personal.csv',    'referencia', 'CSV separado por comas', 'No aplica'),
    ('estacion',    'estacion.csv',    'referencia', 'CSV separado por comas', 'No aplica'),
    ('vivo',        NULL,              'vivo',       'JSON por HTTP desde el receptor de Julia',
                    'ISO 8601 en UTC')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Alias (decisión del equipo en la Fase 1; ver docs/catalogo_problemas.md)
-- "doc" y "la doctora" tienen DOS filas: son ambiguos a propósito.
-- ---------------------------------------------------------------------
INSERT INTO alias (texto, persona_id, motivo) VALUES
    ('jefe',        'okafor',    'Okafor es el jefe de estación (personal.csv)'),
    ('luka',        'petrov',    'Diminutivo de Lucas; habla desde la radio, donde está Petrov'),
    ('irene',       'valcarcel', 'Nombre de pila de Irene Valcárcel'),
    ('marta ruiz',  'ruiz',      'Nombre completo de Marta Ruiz'),
    ('doc',         'vidal',     'Ambiguo: Vidal es médico'),
    ('doc',         'valcarcel', 'Ambiguo: a Valcárcel se le llama "la doctora"'),
    ('la doctora',  'vidal',     'Ambiguo: Vidal es médico'),
    ('la doctora',  'valcarcel', 'Ambiguo: el enunciado la llama "la doctora Valcárcel"')
ON CONFLICT DO NOTHING;

-- Los apellidos también son alias de sí mismos ("Okafor", "Petrov", "Vidal").
INSERT INTO alias (texto, persona_id, motivo)
SELECT id, id, 'Apellido de la persona'
FROM personas
ON CONFLICT DO NOTHING;

COMMIT;