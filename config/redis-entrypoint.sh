# filepath: config/redis-entrypoint.sh

#!/bin/sh
# Lee la contraseña desde Docker Secret y lanza Redis con ella.
# Docker NO interpola secrets en 'command:', por eso usamos un entrypoint.
set -e
REDIS_PASSWORD=$(cat /run/secrets/redis_secret 2>/dev/null || echo "")
if [ -z "$REDIS_PASSWORD" ]; then
    echo "❌ redis_secret no encontrado en /run/secrets/redis_secret"
    exit 1
fi
exec redis-server \
    --requirepass "$REDIS_PASSWORD" \
    --maxmemory 64mb \
    --maxmemory-policy allkeys-lru \
    --save "" \
    --appendonly no \
    --loglevel warning