#!/usr/bin/env bash
# =====================================================================
# Halley-7 · Prepara la base de datos PostgreSQL (sin Docker)
# Responsable: Integrante 2 (Java + BD)
#
# Uso (desde cualquier carpeta):
#     ./scripts/setup_db.sh              crea o actualiza la base
#     ./scripts/setup_db.sh --reiniciar  BORRA la base y la crea de cero
#                                        (solo para desarrollo; pide confirmar)
#
# Qué hace, en orden:
#   1. Carga config/halley.env.
#   2. Crea el rol de la aplicación si no existe (y actualiza su clave).
#   3. Crea la base si no existe, con el administrador como dueño.
#   4. Aplica db/schema.sql, db/triggers.sql y db/semillas.sql.
#
# Es idempotente: correrlo dos veces seguidas no falla ni duplica nada.
# En Windows se ejecuta desde Git Bash o WSL.
# =====================================================================

# -e: salir ante cualquier error; -u: error si se usa una variable sin
# definir; -o pipefail: un fallo dentro de una tubería (|) también cuenta.
set -euo pipefail

# psql debe leer los .sql y los CSV como UTF-8. En Windows usa WIN1252 por
# defecto y rompe las tildes (Valcarcel, Almacen, estacion).
export PGCLIENTENCODING=UTF8
# Ir a la raíz del repositorio (la carpeta padre de scripts/), para que
# las rutas relativas (db/..., data/entrada/...) funcionen siempre.
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

# ---------------------------------------------------------------------
# 1. Configuración
# ---------------------------------------------------------------------
if [[ ! -f config/halley.env ]]; then
    echo "ERROR: no existe config/halley.env" >&2
    echo "       Cópienlo del ejemplo:  cp config/halley.env.example config/halley.env" >&2
    exit 1
fi
# "set -a" exporta automáticamente todas las variables que se definan
# al leer el archivo; "set +a" lo apaga.
# Se lee a través de "tr -d '\r'" por si alguien guardó el archivo con
# saltos de línea de Windows (CRLF): sin esto, bash fallaría o dejaría
# un \r pegado al final de la clave.
set -a
# shellcheck disable=SC1090
source <(tr -d '\r' < config/halley.env)
set +a

# ---------------------------------------------------------------------
# Función auxiliar: ejecuta psql como ADMINISTRADOR.
#   $1 = base a la que se conecta; el resto se pasa tal cual a psql.
# PGPASSWORD le pasa la clave a psql sin dejarla en la línea de comandos.
# PGOPTIONS oculta los avisos "already exists, skipping" de la 2.ª vez.
# ON_ERROR_STOP=1 hace que psql termine con error ante el primer fallo
# (sin esto, psql seguiría y el script creería que todo salió bien).
# ---------------------------------------------------------------------
psql_admin() {
    local base="$1"; shift
    PGPASSWORD="$HALLEY_DB_ADMIN_PASSWORD" PGOPTIONS="-c client_min_messages=warning" psql \
        -h "$HALLEY_DB_HOST" -p "$HALLEY_DB_PORT" -U "$HALLEY_DB_ADMIN_USER" \
        -d "$base" -X -q -v ON_ERROR_STOP=1 "$@"
}

# Verificar antes de empezar que el servidor responde.
if ! psql_admin postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
    echo "ERROR: no me pude conectar a PostgreSQL en $HALLEY_DB_HOST:$HALLEY_DB_PORT" >&2
    echo "       como '$HALLEY_DB_ADMIN_USER'. ¿Está encendido? ¿La clave es correcta?" >&2
    exit 1
fi

# ---------------------------------------------------------------------
# Opción --reiniciar (solo desarrollo)
# Las tablas solo-anexo no permiten DELETE, así que para empezar de cero
# se borra la BASE completa. Nunca se usa con evidencia real.
# ---------------------------------------------------------------------
if [[ "${1:-}" == "--reiniciar" ]]; then
    read -r -p "Esto BORRA la base '$HALLEY_DB_NAME' con toda su evidencia. Escriba SI para continuar: " ok
    if [[ "$ok" != "SI" ]]; then
        echo "Cancelado."; exit 0
    fi
    psql_admin postgres -c "DROP DATABASE IF EXISTS \"$HALLEY_DB_NAME\" WITH (FORCE)"
    echo "Base '$HALLEY_DB_NAME' borrada."
fi

# ---------------------------------------------------------------------
# 2. Rol de la aplicación
# CREATE ROLE no tiene "IF NOT EXISTS", así que se arma la orden con
# format() solo si el rol no existe y se ejecuta con \gexec.
# %I pone comillas de identificador y %L comillas de texto: así una clave
# con comillas o espacios no rompe la orden (ni permite inyección SQL).
# Luego se actualiza la clave siempre, por si cambió en halley.env.
# ---------------------------------------------------------------------
psql_admin postgres -v usuario="$HALLEY_DB_USER" -v clave="$HALLEY_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'usuario', :'clave')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'usuario')
\gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'usuario', :'clave')
\gexec
SQL
echo "Rol de la aplicación '$HALLEY_DB_USER' listo."

# ---------------------------------------------------------------------
# 3. Base de datos
# CREATE DATABASE tampoco puede ir dentro de un bloque condicional, así
# que se usa el mismo truco de format() + \gexec. El dueño es el
# administrador: el rol de la app NO es dueño (no puede tocar triggers).
# ---------------------------------------------------------------------
psql_admin postgres -v base="$HALLEY_DB_NAME" -v usuario="$HALLEY_DB_USER" <<'SQL'
SELECT format('CREATE DATABASE %I ENCODING ''UTF8'' TEMPLATE template0', :'base')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'base')
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'base', :'usuario')
\gexec
SQL
echo "Base '$HALLEY_DB_NAME' lista."

# ---------------------------------------------------------------------
# 4. Esquema, triggers y semillas (en ese orden: los triggers necesitan
#    las tablas, y las semillas necesitan las tablas de referencia).
# ---------------------------------------------------------------------
psql_admin "$HALLEY_DB_NAME" -f db/schema.sql
echo "Esquema aplicado."

psql_admin "$HALLEY_DB_NAME" -v app_user="$HALLEY_DB_USER" -f db/triggers.sql
echo "Triggers y permisos aplicados."

psql_admin "$HALLEY_DB_NAME" -f db/semillas.sql
echo "Datos de referencia cargados."

# Resumen final: cuántas filas hay en las tablas de referencia.
psql_admin "$HALLEY_DB_NAME" -tA -F ' ' <<'SQL'
SELECT 'personas:', count(*) FROM personas
UNION ALL SELECT 'tarjetas:', count(*) FROM tarjetas
UNION ALL SELECT 'accesos:',  count(*) FROM accesos
UNION ALL SELECT 'modulos:',  count(*) FROM modulos
UNION ALL SELECT 'puertas:',  count(*) FROM puertas
UNION ALL SELECT 'alias:',    count(*) FROM alias;
SQL
echo "Listo: base '$HALLEY_DB_NAME' preparada."

