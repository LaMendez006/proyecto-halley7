-- =====================================================================
-- Halley-7 · Triggers solo-anexo y permisos (PostgreSQL 16)
-- Responsable: Integrante 2 (Java + BD)
--
-- Se aplica DESPUÉS de schema.sql, con un usuario administrador, desde
-- scripts/setup_db.sh. Es idempotente: se puede correr varias veces.
--
-- Necesita la variable de psql "app_user" (el rol con el que se conecta
-- Java). setup_db.sh la pasa así:  psql -v app_user=halley -f db/triggers.sql
--
-- Hay DOS barreras independientes para que la evidencia no cambie:
--   1. Triggers: aunque alguien tenga permiso, un UPDATE, DELETE o
--      TRUNCATE sobre una tabla solo-anexo lanza un error.
--   2. Permisos: el rol de la aplicación ni siquiera tiene permiso de
--      UPDATE, DELETE ni TRUNCATE; solo INSERT y SELECT.
-- Si una barrera falla (por ejemplo, un superusuario desactiva el
-- trigger), la cadena de hashes sigue delatando la alteración.
-- =====================================================================

-- Si falta la variable, psql se detiene aquí con un error claro en vez
-- de seguir con permisos a medias.
\if :{?app_user}
\else
  \echo 'ERROR: falta la variable app_user (psql -v app_user=...)'
  \quit
\endif

-- La función que usan todos los triggers. TG_TABLE_NAME y TG_OP son
-- variables que PostgreSQL llena solo: nombre de la tabla y operación.
CREATE OR REPLACE FUNCTION bloquear_modificacion() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'La tabla % es solo-anexo: % no está permitido', TG_TABLE_NAME, TG_OP
        USING ERRCODE = 'insufficient_privilege';   -- código SQLSTATE 42501
END;
$$ LANGUAGE plpgsql;

-- Se crean dos triggers por tabla:
--   * BEFORE UPDATE OR DELETE ... FOR EACH ROW  -> bloquea cambios fila a fila.
--   * BEFORE TRUNCATE ... FOR EACH STATEMENT    -> TRUNCATE no pasa por los
--     triggers de fila, así que necesita el suyo propio.
-- CREATE OR REPLACE TRIGGER existe desde PostgreSQL 14 y hace que el
-- script sea idempotente.
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'evidencia', 'problemas', 'problema_evidencia', 'correcciones',
        'consultas', 'respuestas', 'respuesta_evidencia', 'cadena'
    ] LOOP
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER %I BEFORE UPDATE OR DELETE ON %I
                 FOR EACH ROW EXECUTE FUNCTION bloquear_modificacion()',
            t || '_solo_anexo', t);
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER %I BEFORE TRUNCATE ON %I
                 FOR EACH STATEMENT EXECUTE FUNCTION bloquear_modificacion()',
            t || '_sin_truncate', t);
    END LOOP;
END;
$$;


-- ---------------------------------------------------------------------
-- PERMISOS DEL ROL DE LA APLICACIÓN
-- El dueño de las tablas es el administrador (quien corre setup_db.sh),
-- NO el rol de la aplicación. Así Java no puede desactivar triggers ni
-- cambiar el esquema: eso solo lo puede hacer el dueño.
-- ---------------------------------------------------------------------

-- Primero se quita todo, para partir de cero en cada ejecución.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM :"app_user";

-- Puede usar el esquema (ver y nombrar objetos), pero no crear en él.
GRANT USAGE ON SCHEMA public TO :"app_user";

-- Tablas de referencia: solo lectura. Se llenan con db/semillas.sql.
GRANT SELECT ON personas, tarjetas, modulos, puertas, accesos, fuentes, alias, alias_resuelto
    TO :"app_user";

-- Tablas solo-anexo: leer e insertar, nada más.
GRANT SELECT, INSERT ON evidencia, problemas, problema_evidencia, correcciones,
                        consultas, respuestas, respuesta_evidencia, cadena
    TO :"app_user";

-- Nota para Java: como el rol no tiene UPDATE, tampoco puede usar
-- SELECT ... FOR UPDATE (PostgreSQL exige permiso de UPDATE para eso).
-- Por eso, para que dos inserciones simultáneas no rompan la cadena,
-- Java usará pg_advisory_xact_lock(), que no necesita permisos especiales.

-- Explícito (aunque ya se quitó arriba), para que quede documentado.
REVOKE UPDATE, DELETE, TRUNCATE ON evidencia, problemas, problema_evidencia, correcciones,
                                   consultas, respuestas, respuesta_evidencia, cadena
    FROM :"app_user";