# filepath: scripts/setup.sh
#!/bin/bash
# scripts/setup.sh
# ══════════════════════════════════════════════════════════════════════════════
# Script de configuración inicial del proyecto NOMBRE_DEL_PROYECTO
#
# Uso:
#   En desarrollo:  ./scripts/setup.sh
#   En producción:  ./scripts/setup.sh --prod
#
# ¿Qué hace?
#   - Verifica UID y dependencias (docker, make)
#   - Crea .env (desarrollo) o .env.production (producción) desde la plantilla
#   - Genera JWT_SECRET automáticamente con openssl (desarrollo)
#   - Crea la base de datos si no existe
#   - Construye las imágenes Docker
#   - Crea carpetas de logs con permisos correctos
# ══════════════════════════════════════════════════════════════════════════════

set -e          # Salir si hay cualquier error
set -u          # Error si se usa variable no definida
set -o pipefail # El pipe falla si falla cualquier comando

# ─── Colores ─────────────────────────────────────────────────────────────────
# Por qué printf en vez de echo:
#   'echo' sin -e no interpreta \033 (secuencias ANSI).
#   'echo -e' sí las interpreta en bash, pero NO es portable a /bin/sh.
#   'printf "%b"' siempre interpreta \033 y es el estándar POSIX portable.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Helpers con printf (portable y consistente) ──────────────────────────────
print_line() { printf "%b\n" "$*"; }
error()      { printf "%b\n" "${RED}❌ $1${NC}" >&2; exit 1; }
success()    { printf "%b\n" "${GREEN}✅ $1${NC}"; }
warning()    { printf "%b\n" "${YELLOW}⚠️  $1${NC}"; }
info()       { printf "%b\n" "${BLUE}ℹ️  $1${NC}"; }

# ─── Modo: desarrollo o producción ───────────────────────────────────────────
MODE="development"
ENV_FILE=".env"
ENV_TEMPLATE=".env.example"

if [ "${1:-}" = "--prod" ]; then
    MODE="production"
    ENV_FILE=".env.production"
    ENV_TEMPLATE=".env.prod.example"
fi

print_line ""
print_line "${CYAN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
print_line "${CYAN}${BOLD}║     🐳  NOMBRE_DEL_PROYECTO — Setup (modo: ${MODE})${NC}"
print_line "${CYAN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
print_line ""

# ─── 1. Verificar UID ────────────────────────────────────────────────────────
print_line "🔍 Verificando UID..."
USER_ID=$(id -u)
if [ "$USER_ID" != "1000" ]; then
    warning "Tu UID es $USER_ID, pero Docker espera UID 1000"
    warning "Esto puede causar problemas de permisos con volúmenes"
    read -r -p "¿Continuar de todas formas? (y/n) " REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]] || exit 1
else
    success "UID 1000 correcto"
fi

# ─── 2. Verificar Docker y Make ──────────────────────────────────────────────
print_line ""
print_line "🐳 Verificando dependencias..."
command -v docker >/dev/null 2>&1 \
    || error "Docker no instalado. Instala con: curl -fsSL https://get.docker.com | sh"
docker compose version >/dev/null 2>&1 \
    || error "Docker Compose v2 no disponible"
success "Docker OK: $(docker --version)"

# make es necesario en producción para secrets-init y en desarrollo para todos los targets
command -v make >/dev/null 2>&1 \
    || error "make no instalado. Instala con: sudo apt-get install -y make"
success "make OK: $(make --version | head -1)"

# ─── 3. Configurar archivo de entorno ────────────────────────────────────────
print_line ""
print_line "📄 Configurando ${ENV_FILE}..."

if [ -f "$ENV_FILE" ]; then
    success "${ENV_FILE} ya existe"
else
    if [ ! -f "$ENV_TEMPLATE" ]; then
        error "Plantilla ${ENV_TEMPLATE} no encontrada"
    fi
    cp "$ENV_TEMPLATE" "$ENV_FILE"
    success "${ENV_FILE} creado desde ${ENV_TEMPLATE}"

    if [ "$MODE" = "production" ]; then
        warning ""
        warning "PRODUCCIÓN: Edita ${ENV_FILE} con los valores reales"
        warning "NO pongas DB_PASSWORD aquí — usa Docker Secrets:"
        warning "  make secrets-init && make secrets-check"
        warning ""
        chmod 600 "$ENV_FILE"
        success "Permisos 600 aplicados a ${ENV_FILE}"
    else
        warning "Configura las credenciales en ${ENV_FILE} antes de continuar"
        # vi es el único editor POSIX garantizado en todos los sistemas.
        # nano y otros pueden no estar instalados en servidores bare-metal o Alpine.
        ${EDITOR:-vi} "$ENV_FILE"
    fi
fi

# ─── 4. Generar METRICS_PASSWORD automáticamente (solo desarrollo) ─────────────────
# En producción el METRICS_PASSWORD va en Docker Secrets (secrets/metrics_password.txt),
# no en .env.production. En desarrollo sí va en .env para mayor comodidad,
# pero debe ser un valor real, nunca el placeholder del template.
if [ "$MODE" = "development" ]; then
    METRICS_PASSWORD_CURRENT=$(grep -v "^#" "$ENV_FILE" | grep "^METRICS_PASSWORD=" | cut -d'=' -f2)
    # Detectar cualquier placeholder: valor vacío, o que contenga 'genera_con' o 'CAMBIAR_'
    # Esto cubre: 'genera_con_openssl_rand_base64_24' y 'CAMBIAR_genera_con_openssl_rand_base64_24'
    if [ -z "$METRICS_PASSWORD_CURRENT" ] || printf "%s" "$METRICS_PASSWORD_CURRENT" | grep -qE "^(CAMBIAR_)?genera_con"; then
        METRICS_PASSWORD_GENERATED=$(openssl rand -base64 24)
        # sed portable: '|' como delimitador porque base64 puede contener '/'
        # Reemplaza cualquier línea METRICS_PASSWORD=<placeholder> con el valor generado
        sed -i "s|METRICS_PASSWORD=.*genera_con.*|METRICS_PASSWORD=${METRICS_PASSWORD_GENERATED}|" "$ENV_FILE"
        success "METRICS_PASSWORD generado automáticamente con openssl rand -base64 24"
    else
        success "METRICS_PASSWORD ya configurado"
    fi
fi

# ─── 5. Generar JWT_SECRET automáticamente (solo desarrollo) ─────────────────
# En producción el JWT_SECRET va en Docker Secrets (secrets/jwt_secret.txt),
# no en .env.production. En desarrollo sí va en .env para mayor comodidad,
# pero debe ser un valor real, nunca el placeholder del template.
if [ "$MODE" = "development" ]; then
    JWT_CURRENT=$(grep -v "^#" "$ENV_FILE" | grep "^JWT_SECRET=" | cut -d'=' -f2)
    # Detectar cualquier placeholder: valor vacío, o que contenga 'genera_con' o 'CAMBIAR_'
    # Esto cubre: 'genera_con_openssl_rand_base64_48' y 'CAMBIAR_genera_con_openssl_rand_base64_48'
    if [ -z "$JWT_CURRENT" ] || printf "%s" "$JWT_CURRENT" | grep -qE "^(CAMBIAR_)?genera_con"; then
        JWT_GENERATED=$(openssl rand -base64 48)
        # sed portable: '|' como delimitador porque base64 puede contener '/'
        # Reemplaza cualquier línea JWT_SECRET=<placeholder> con el valor generado
        sed -i "s|JWT_SECRET=.*genera_con.*|JWT_SECRET=${JWT_GENERATED}|" "$ENV_FILE"
        success "JWT_SECRET generado automáticamente con openssl rand -base64 48"
    else
        success "JWT_SECRET ya configurado"
    fi
fi

# ─── 6. Generar PEPPER_SECRET automáticamente (solo desarrollo) ─────────────────
# En producción el PEPPER_SECRET va en Docker Secrets (secrets/pepper_secret.txt),
# no en .env.production. En desarrollo sí va en .env para mayor comodidad,
# pero debe ser un valor real, nunca el placeholder del template.
if [ "$MODE" = "development" ]; then
    PEPPER_CURRENT=$(grep -v "^#" "$ENV_FILE" | grep "^PEPPER_SECRET=" | cut -d'=' -f2)
    # Detectar cualquier placeholder: valor vacío, o que contenga 'genera_con' o 'CAMBIAR_'
    # Esto cubre: 'genera_con_openssl_rand_base64_48' y 'CAMBIAR_genera_con_openssl_rand_base64_48'
    if [ -z "$PEPPER_CURRENT" ] || printf "%s" "$PEPPER_CURRENT" | grep -qE "^(CAMBIAR_)?genera_con"; then
        PEPPER_GENERATED=$(openssl rand -base64 32)
        # sed portable: '|' como delimitador porque base64 puede contener '/'
        # Reemplaza cualquier línea PEPPER_SECRET=<placeholder> con el valor generado
        sed -i "s|PEPPER_SECRET=.*genera_con.*|PEPPER_SECRET=${PEPPER_GENERATED}|" "$ENV_FILE"
        success "PEPPER_SECRET generado automáticamente con openssl rand -base64 32"
    else
        success "PEPPER_SECRET ya configurado"
    fi
fi

# ─── 7. Generar COOKIE_SECRET automáticamente (solo desarrollo) ─────────────────
# En producción el COOKIE_SECRET va en Docker Secrets (secrets/cookie_secret.txt),
# no en .env.production. En desarrollo sí va en .env para mayor comodidad,
# pero debe ser un valor real, nunca el placeholder del template.
if [ "$MODE" = "development" ]; then
    COOKIE_CURRENT=$(grep -v "^#" "$ENV_FILE" | grep "^COOKIE_SECRET=" | cut -d'=' -f2)
    # Detectar cualquier placeholder: valor vacío, o que contenga 'genera_con' o 'CAMBIAR_'
    # Esto cubre: 'genera_con_openssl_rand_hex_48' y 'CAMBIAR_genera_con_openssl_rand_hex_48'
    if [ -z "$COOKIE_CURRENT" ] || printf "%s" "$COOKIE_CURRENT" | grep -qE "^(CAMBIAR_)?genera_con"; then
        COOKIE_GENERATED=$(openssl rand -hex 48) # hex es suficiente para un secreto de cookie, no necesita base64
        # sed portable: '|' como delimitador porque hex puede contener '/'
        # Reemplaza cualquier línea COOKIE_SECRET=<placeholder> con el valor generado
        sed -i "s|COOKIE_SECRET=.*genera_con.*|COOKIE_SECRET=${COOKIE_GENERATED}|" "$ENV_FILE"
        success "COOKIE_SECRET generado automáticamente con openssl rand -hex 48"
    else
        success "COOKIE_SECRET ya configurado"
    fi
fi

# ─── 8. Generar REDIS_PASSWORD automáticamente (solo desarrollo) ─────────────────
# En producción el REDIS_PASSWORD va en Docker Secrets (secrets/redis_secret.txt),
# no en .env.production. En desarrollo sí va en .env para mayor comodidad,
# pero debe ser un valor real, nunca el placeholder del template.
if [ "$MODE" = "development" ]; then
    REDIS_CURRENT=$(grep -v "^#" "$ENV_FILE" | grep "^REDIS_PASSWORD=" | cut -d'=' -f2)
    # Detectar cualquier placeholder: valor vacío, o que contenga 'genera_con' o 'CAMBIAR_'
    # Esto cubre: 'genera_con_openssl_rand_hex_48' y 'CAMBIAR_genera_con_openssl_rand_hex_48'
    if [ -z "$REDIS_CURRENT" ] || printf "%s" "$REDIS_CURRENT" | grep -qE "^(CAMBIAR_)?genera_con"; then
        REDIS_GENERATED=$(openssl rand -hex 32) # hex es suficiente para un secreto de redis, no necesita base64
        # sed portable: '|' como delimitador porque hex puede contener '/'
        # Reemplaza cualquier línea REDIS_PASSWORD=<placeholder> con el valor generado
        sed -i "s|REDIS_PASSWORD=.*genera_con.*|REDIS_PASSWORD=${REDIS_GENERATED}|" "$ENV_FILE"
        success "REDIS_PASSWORD generado automáticamente con openssl rand -hex 48"
    else
        success "REDIS_PASSWORD ya configurado"
    fi
fi

# ─── 9. Generar SWAGGER_PASSWORD automáticamente (solo desarrollo) ─────────────────
# En producción el SWAGGER_PASSWORD va deshabilitado (SWAGGER_ENABLED=false),
# no en .env.production. En desarrollo sí va en .env para mayor comodidad,
# pero debe ser un valor real, nunca el placeholder del template.
if [ "$MODE" = "development" ]; then
    SWAGGER_PASSWORD_CURRENT=$(grep -v "^#" "$ENV_FILE" | grep "^SWAGGER_PASSWORD=" | cut -d'=' -f2)
    # Detectar cualquier placeholder: valor vacío, o que contenga 'genera_con' o 'CAMBIAR_'
    # Esto cubre: 'genera_con_openssl_rand_base64_12' y 'CAMBIAR_genera_con_openssl_rand_base64_12'
    if [ -z "$SWAGGER_PASSWORD_CURRENT" ] || printf "%s" "$SWAGGER_PASSWORD_CURRENT" | grep -qE "^(CAMBIAR_)?genera_con"; then
        SWAGGER_PASSWORD_GENERATED=$(openssl rand -base64 12)
        # sed portable: '|' como delimitador porque base64 puede contener '/'
        # Reemplaza cualquier línea SWAGGER_PASSWORD=<placeholder> con el valor generado
        sed -i "s|SWAGGER_PASSWORD=.*genera_con.*|SWAGGER_PASSWORD=${SWAGGER_PASSWORD_GENERATED}|" "$ENV_FILE"
        success "SWAGGER_PASSWORD generado automáticamente con openssl rand -base64 12"
    else
        success "SWAGGER_PASSWORD ya configurado"
    fi
fi

# ─── 10. En producción: verificar que DB_PASSWORD no esté en .env.production ──
if [ "$MODE" = "production" ]; then
    if grep -v "^#" "$ENV_FILE" | grep -q "DB_PASSWORD="; then
        PW_LINE=$(grep -v "^#" "$ENV_FILE" | grep "DB_PASSWORD=" | head -1)
        PW_VALUE=$(printf "%s" "$PW_LINE" | cut -d'=' -f2)
        if [ -n "$PW_VALUE" ] && [ "$PW_VALUE" != "REPLACE_WITH_SECRET" ]; then
            warning "DB_PASSWORD está en ${ENV_FILE} — considera moverlo a Docker Secrets"
            warning "Ver: make secrets-init"
        fi
    fi
fi

# ─── 11. Verificar PostgreSQL (solo en desarrollo) ────────────────────────────
if [ "$MODE" = "development" ]; then
    print_line ""
    print_line "🗄️  Verificando PostgreSQL..."
    command -v psql >/dev/null 2>&1 \
        || error "PostgreSQL no instalado: sudo apt install postgresql"
    success "PostgreSQL instalado"

    DB_NAME=$(grep -v "^#" "$ENV_FILE" | grep "^DB_NAME=" | cut -d'=' -f2)
    DB_USER=$(grep -v "^#" "$ENV_FILE" | grep "^DB_USER=" | cut -d'=' -f2)
    DB_PASSWORD=$(grep -v "^#" "$ENV_FILE" | grep "^DB_PASSWORD=" | cut -d'=' -f2)
    DB_READ_ONLY_USER=$(grep -v "^#" "$ENV_FILE" | grep "^DB_READ_ONLY_USER=" | cut -d'=' -f2)
    DB_READ_ONLY_PASSWORD=$(grep -v "^#" "$ENV_FILE" | grep "^DB_READ_ONLY_PASSWORD=" | cut -d'=' -f2)

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then
        warning "DB_NAME o DB_USER no configurados en ${ENV_FILE} — saltando creación de DB"
    else
        print_line "🗄️  Configurando base de datos: ${DB_NAME}..."
        if ! sudo -u postgres psql -lqt | cut -d\| -f1 | grep -qw "$DB_NAME"; then
            # IMPORTANTE: la contraseña se pasa via PGPASSWORD, NO interpolada en el SQL.
            # Interpolar directamente causaría fallo o inyección si la contraseña
            # contiene comillas simples (ej: "it's"), caracteres especiales o espacios.
            PGPASSWORD="$DB_PASSWORD" sudo -u postgres psql <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF
            # Crear usuario de solo lectura para reports-api
            if [ -n "$DB_READ_ONLY_USER" ] && [ -n "$DB_READ_ONLY_PASSWORD" ]; then
                PGPASSWORD="$DB_PASSWORD" sudo -u postgres psql -d "$DB_NAME" <<EOF
CREATE USER ${DB_READ_ONLY_USER} WITH PASSWORD '${DB_READ_ONLY_PASSWORD}';
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${DB_READ_ONLY_USER};
GRANT USAGE ON SCHEMA public TO ${DB_READ_ONLY_USER};
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${DB_READ_ONLY_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${DB_READ_ONLY_USER};
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO ${DB_READ_ONLY_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO ${DB_READ_ONLY_USER};
EOF
                success "Usuario read-only '${DB_READ_ONLY_USER}' creado"
            fi
            success "Base de datos '${DB_NAME}' creada"
        else
            success "Base de datos '${DB_NAME}' ya existe"
        fi
    fi
fi

# ─── 12. En producción: inicializar secretos ──────────────────────────────────
if [ "$MODE" = "production" ]; then
    print_line ""
    print_line "🔐 Verificando secretos..."
    # make ya fue verificado en el paso 2 — seguro llamarlo aquí
    if [ ! -d "secrets" ]; then
        info "Ejecutando make secrets-init..."
        make secrets-init
    else
        make secrets-check 2>/dev/null \
            && success "Secretos configurados" \
            || warning "Secretos pendientes de configurar — edita secrets/*.txt"
    fi
fi

# ─── 13. Build Docker ─────────────────────────────────────────────────────────
print_line ""
print_line "🔨 Construyendo imágenes Docker..."
if [ "$MODE" = "production" ]; then
    docker compose -f docker-compose.yml -f docker-compose.prod.yml build
else
    docker compose build
fi
success "Imágenes construidas"

# ─── 14. Crear carpetas de logs ───────────────────────────────────────────────
print_line ""
print_line "📁 Creando carpetas de logs..."
mkdir -p logs/backend logs/reports
if [ "$(id -u)" = "1000" ]; then
    success "Permisos de logs OK"
else
    sudo chown -R 1000:1000 logs 2>/dev/null \
        && success "Permisos de logs configurados" \
        || warning "Ejecuta manualmente: sudo chown -R 1000:1000 logs"
fi

# ─── Resumen ─────────────────────────────────────────────────────────────────
print_line ""
print_line "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_line "${GREEN}${BOLD}  ✅ Configuración completada (modo: ${MODE})${NC}"
print_line "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_line ""

if [ "$MODE" = "development" ]; then
    print_line "  Comandos útiles:"
    print_line "    make dev            # Arrancar en desarrollo"
    print_line "    make db-migrate     # Aplicar migraciones de base de datos"
    print_line "    make doctor         # Verificar entorno"
    print_line "    make troubleshoot   # Tips de solución a problemas"
    print_line "    make audit-full     # Pipeline de seguridad"
    print_line "    make logs           # Ver logs"
    print_line "    make stop           # Detener"
else
    print_line "  Próximos pasos:"
    print_line "    make secrets-check       # Verificar secretos"
    print_line "    make prod                # Deploy" con validaciones + migraciones + up
    print_line "    make logs                # Ver logs"
    print_line "    make audit-full          # Auditoría completa"
fi
print_line ""
