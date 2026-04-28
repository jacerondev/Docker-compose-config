# filepath: scripts/deploy-prod.sh
#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# Script de deploy a producción — NOMBRE_DEL_PROYECTO
#
# Uso: ./scripts/deploy-prod.sh
# Requiere: ejecutar desde /opt/nombre_del_proyecto con .env.production y secrets/ listos
# ══════════════════════════════════════════════════════════════════════════════

set -e
set -u
set -o pipefail

# ─── Colores ─────────────────────────────────────────────────────────────────
# Por qué printf en vez de echo:
#   'echo' sin -e no interpreta \033 (secuencias ANSI).
#   'printf "%b"' siempre las interpreta — es el estándar POSIX portable.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Helpers con printf ───────────────────────────────────────────────────────
print_line() { printf "%b\n" "$*"; }
error()      { printf "%b\n" "${RED}❌ $1${NC}" >&2; exit 1; }
success()    { printf "%b\n" "${GREEN}✅ $1${NC}"; }
warning()    { printf "%b\n" "${YELLOW}⚠️  $1${NC}"; }

# ─── Función: verificar versión mínima ───────────────────────────────────────
check_version() {
    local tool="$1" current="$2" required_major="$3"
    local current_major
    current_major=$(printf "%s" "$current" | cut -d. -f1)
    if [ "$current_major" -lt "$required_major" ]; then
        error "$tool $current demasiado antiguo. Se requiere $required_major.x+"
    fi
    success "$tool $current"
}

# ─── 1. Verificar prerrequisitos ─────────────────────────────────────────────
print_line "🔍 Verificando prerrequisitos..."
command -v docker >/dev/null 2>&1             || error "Docker no instalado"
docker compose version >/dev/null 2>&1        || error "Docker Compose v2 no disponible"

check_version "Docker" \
    "$(docker version --format '{{.Server.Version}}' 2>/dev/null || printf '0.0.0')" 20
check_version "Docker Compose" \
    "$(docker compose version --short 2>/dev/null || printf '0.0.0')" 2

if [ -z "${TAG:-}" ]; then
    error "TAG no definido. El deploy requiere una imagen con tag específico."
    error "Ejecutar: export TAG=<sha> && make prod"
    exit 1
fi

# ─── 2. Verificar directorio de trabajo ──────────────────────────────────────
DEPLOY_DIR="${DEPLOY_DIR:-/opt/nombre_del_proyecto}"
if [ ! -f "${DEPLOY_DIR}/.env.production" ]; then
    if [ -f "${DEPLOY_DIR}/.env" ]; then
        warning ".env.production no encontrado — usando .env (considera migrar a .env.production)"
        ENV_FILE="${DEPLOY_DIR}/.env"
    else
        error "Archivo de entorno no encontrado en ${DEPLOY_DIR}/
  Crea .env.production desde: cp .env.prod.example .env.production"
    fi
else
    ENV_FILE="${DEPLOY_DIR}/.env.production"
fi

# ─── 3. Aplicar permisos estrictos al archivo de entorno ─────────────────────
print_line "🔒 Configurando permisos de ${ENV_FILE}..."
sudo chmod 600 "${ENV_FILE}"
sudo chown root:root "${ENV_FILE}"
PERMS=$(stat -c "%a" "${ENV_FILE}")
[ "$PERMS" = "600" ] || error "Permisos incorrectos: $PERMS (esperado: 600)"
success "Permisos ${ENV_FILE}: 600"

# ─── 4. Verificar secretos ───────────────────────────────────────────────────
print_line "🔐 Verificando secretos..."
SECRETS_DIR="${DEPLOY_DIR}/secrets"
if [ ! -d "${SECRETS_DIR}" ]; then
    error "Carpeta secrets/ no encontrada en ${DEPLOY_DIR}/
  Ejecuta: make secrets-init && make secrets-check"
fi

SECRETS_OK=true
# IMPORTANTE: jwt_secret.txt debe verificarse — si falta, el backend arranca
# pero falla en runtime al intentar firmar o verificar tokens JWT.
# Todos los secretos declarados en docker-compose.prod.yml deben estar aquí.
for secret_file in \
    "${SECRETS_DIR}/db_password.txt" \
    "${SECRETS_DIR}/db_user.txt" \
    "${SECRETS_DIR}/db_read_only_password.txt" \
    "${SECRETS_DIR}/db_read_only_user.txt" \
    "${SECRETS_DIR}/jwt_secret.txt" \
    "${SECRETS_DIR}/pepper_secret.txt" \
    "${SECRETS_DIR}/cookie_secret.txt" \
    "${SECRETS_DIR}/redis_secret.txt" \
    "${SECRETS_DIR}/slack_webhook_url.txt" \
    "${SECRETS_DIR}/metrics_password.txt"; do
    if [ ! -f "$secret_file" ]; then
        print_line "${RED}❌ Falta: ${secret_file}${NC}"
        SECRETS_OK=false
    elif grep -q "REEMPLAZA_CON" "$secret_file" 2>/dev/null; then
        print_line "${RED}❌ Placeholder sin reemplazar: ${secret_file}${NC}"
        SECRETS_OK=false
    else
        print_line "${GREEN}✅ OK: ${secret_file}${NC}"
    fi
done

[ "$SECRETS_OK" = true ] || error "Secretos pendientes. Edita los archivos en secrets/"

# ─── 4b. Verificar variables críticas de producción ─────────────────────────
print_line ""
print_line "🔎 Verificando variables críticas de producción..."

# Leer .env.production para validar (sin exportar al shell — solo verificación)
_env_node=$(grep "^NODE_ENV=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
_env_auth=$(grep "^AUTH_MODE=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
_env_jwt=$(grep "^JWT_SECRET=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
_env_pepper=$(grep "^PEPPER_SECRET=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
_env_cookie=$(grep "^COOKIE_SECRET=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
_env_redis=$(grep "^REDIS_SECRET=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
_env_swagger_password=$(grep "^SWAGGER_PASSWORD=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
_env_metrics=$(grep "^METRICS_PASSWORD=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
_env_swagger=$(grep "^SWAGGER_ENABLED=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')

[ "${_env_node}" = "production" ] \
    || error "NODE_ENV debe ser 'production' en ${ENV_FILE} (actual: '${_env_node:-no definido}')"
success "NODE_ENV=production"

[ "${_env_auth}" = "real" ] \
    || error "AUTH_MODE debe ser 'real' en ${ENV_FILE} (actual: '${_env_auth:-no definido}')"
success "AUTH_MODE=real"


# Verificar que METRICS_PASSWORD no sea el placeholder
case "${_env_metrics}" in
    CAMBIAR_*|"") error "METRICS_PASSWORD tiene un valor placeholder o está vacío en ${ENV_FILE}" ;;
    *) success "METRICS_PASSWORD definido" ;;
esac

# Verificar que JWT_SECRET no sea el placeholder
case "${_env_jwt}" in
    CAMBIAR_*|"") error "JWT_SECRET tiene un valor placeholder o está vacío en ${ENV_FILE}" ;;
    *) success "JWT_SECRET definido" ;;
esac

# Verificar que PEPPER_SECRET no sea el placeholder
case "${_env_pepper}" in
    CAMBIAR_*|"") error "PEPPER_SECRET tiene un valor placeholder o está vacío en ${ENV_FILE}" ;;
    *) success "PEPPER_SECRET definido" ;;
esac

# Verificar que COOKIE_SECRET no sea el placeholder
case "${_env_cookie}" in
    CAMBIAR_*|"") error "COOKIE_SECRET tiene un valor placeholder o está vacío en ${ENV_FILE}" ;;
    *) success "COOKIE_SECRET definido" ;;
esac

# Verificar que REDIS_SECRET no sea el placeholder
case "${_env_redis}" in
    CAMBIAR_*|"") error "REDIS_SECRET tiene un valor placeholder o está vacío en ${ENV_FILE}" ;;
    *) success "REDIS_SECRET definido" ;;
esac

# Verificar que SWAGGER_PASSWORD no sea el placeholder
case "${_env_swagger_password}" in
    CAMBIAR_*|"") error "SWAGGER_PASSWORD tiene un valor placeholder o está vacío en ${ENV_FILE}" ;;
    *) success "SWAGGER_PASSWORD definido" ;;
esac

# Swagger debe estar deshabilitado en producción
[ "${_env_swagger}" != "true" ] \
    || warning "SWAGGER_ENABLED=true detectado en producción — considera deshabilitarlo"

unset _env_node _env_auth _env_jwt _env_cookie _env_redis _env_swagger_password _env_swagger

# Verificar que los secrets de DB no usan el usuario postgres
if grep -q "^postgres$" secrets/db_user.txt 2>/dev/null; then
    echo "❌ secrets/db_user.txt contiene 'postgres' (superusuario). Usar usuario de aplicación."
    exit 1
fi

# ─── 5. Crear carpetas de logs ───────────────────────────────────────────────
print_line "📁 Preparando logs..."
mkdir -p "${DEPLOY_DIR}/logs/backend" "${DEPLOY_DIR}/logs/reports"
sudo chown -R 1000:1000 "${DEPLOY_DIR}/logs"
success "Logs preparados"

# ─── 5b. Ejecutar migraciones de base de datos ───────────────────────────────
# OBLIGATORIO: las migraciones deben correr ANTES de levantar los contenedores
# para evitar que la app arranque contra un schema desactualizado.
# Si la migración falla, el deploy se detiene aquí (set -e lo garantiza).
print_line ""
print_line "🗄️  Ejecutando migraciones de base de datos..."

# Verifica que el backend pueda conectarse a la BD antes de migrar
# Usa una imagen temporal con las mismas credenciales para correr el CLI de TypeORM
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
    run --rm --no-deps backend \
    node node_modules/.bin/typeorm migration:run -d dist/ormconfig.js \
    || error "Migraciones fallaron. Deploy abortado."

success "Migraciones aplicadas correctamente"

# ─── 6. Deploy ───────────────────────────────────────────────────────────────
print_line ""
print_line "🚀 Iniciando deploy..."
cd "${DEPLOY_DIR}"
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

# ─── 7. Verificar salud ──────────────────────────────────────────────────────
print_line ""
print_line "🏥 Verificando salud de los servicios (espera hasta 90s)..."
MAX_WAIT=90
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $MAX_WAIT ]; do
    HEALTHY=$(docker compose ps --format json 2>/dev/null \
        | python3 -c "import sys,json; [print(c.get('Health','')) for c in [json.loads(l) for l in sys.stdin if l.strip()]]" 2>/dev/null \
        | grep -c "healthy" || printf "0")

    if [ "$HEALTHY" -ge 3 ]; then
        success "Todos los servicios healthy (${ELAPSED}s)"
        break
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    warning "Timeout: algunos servicios pueden no estar healthy aún"
    docker compose ps
fi

print_line ""
print_line "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_line "${GREEN}${BOLD}  ✅ Deploy completado${NC}"
print_line "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_line ""
print_line "  Comandos útiles:"
print_line "    make logs            # Ver logs en tiempo real"
print_line "    docker stats         # Ver uso de CPU/RAM (verifica mem_limit)"
print_line "    make troubleshoot    # Tips de solución a problemas"
print_line "    make audit-full      # Auditoría completa post-deploy"
print_line ""
