# filepath: backend/.docker/Dockerfile
# ══════════════════════════════════════════════════════════════════════════════
# BACKEND - NESTJS - DESARROLLO
# ══════════════════════════════════════════════════════════════════════════════
# Imagen base: Node.js 24 LTS sobre Debian 12 (Bookworm) Slim
# Tamaño: ~170MB (vs ~1GB de la imagen completa)
# ══════════════════════════════════════════════════════════════════════════════

# ┌──────────────────────────────────────────────────────────────────────────┐
# │ ETAPA 1: BUILDER                                                         │
# │ Propósito: Compilar TypeScript → JavaScript                              │
# └──────────────────────────────────────────────────────────────────────────┘
FROM node:24-slim@sha256:a81a03dd965b4052269a57fac857004022b522a4bf06e7a739e25e18bce45af2 AS deps

# ─── Dependencias del sistema ─────────────────────────────────────────────────
# Se instalan herramientas necesarias para el funcionamiento del contenedor
RUN apt-get update && apt-get install -y --no-install-recommends \
    # curl: Requerido para healthchecks de Docker Compose
    curl \
    # ca-certificates: Certificados SSL/TLS para requests HTTPS seguros
    ca-certificates \
    # tini: Requerido para manejo correcto de señales (graceful shutdown)
    tini \
    # Limpieza: Elimina listas de paquetes para reducir el tamaño de la imagen
    && rm -rf /var/lib/apt/lists/*

# ─── Directorio de trabajo ───────────────────────────────────────────────────
WORKDIR /usr/src/app

# ─── Corepack y pnpm ─────────────────────────────────────────────────────────
# Es posible fijar la versión de pnpm con pnpm@10.x en lugar de latest para mayor estabilidad
ARG PNPM_VERSION=10.32.1
RUN corepack enable && corepack prepare pnpm@${PNPM_VERSION} --activate

# ─── Instalación de dependencias ─────────────────────────────────────────────
# Se copian primero package*.json para aprovechar el cache de Docker
# Si el código cambia pero package.json no, Docker reutiliza esta capa
COPY --chown=node:node package.json pnpm-lock.yaml ./

# pnpm ci: Instalación limpia basada en package-lock.json (reproducible)
# --include=dev: Incluye devDependencies (TypeScript, @types/*, etc.)
# --force: Limpia el cache de pnpm para reducir tamaño de imagen
RUN pnpm install --frozen-lockfile --ignore-scripts --include=dev && pnpm cache clean --force

# ┌──────────────────────────────────────────────────────────────────────────┐
# │ ETAPA 2: RUNNER (IMAGEN FINAL)                                           │
# │ Propósito: Solo runtime, sin herramientas de build                       │
# └──────────────────────────────────────────────────────────────────────────┘
FROM node:24-slim@sha256:a81a03dd965b4052269a57fac857004022b522a4bf06e7a739e25e18bce45af2 AS dev

# ─── Metadata de la imagen ───────────────────────────────────────────────────
# PROYECTO PERSONAL - AJUSTA ESTOS VALORES (ACTUAL UN MIEMBRO DE LA ORGANIZACIÓN)
# En producción, los labels de imagen aparecen en docker inspect y en registries, lo que puede exponer que se
# usa esta plantilla base y dar pistas sobre la estructura del proyecto
# Si quieres ocultar esta información, puedes cambiar el valor de estos labels o eliminarlos por completo
# (aunque no es recomendable eliminar los labels, ya que son útiles para la gestión de imágenes y contenedores)
# Completar los labels antes del primer deploy productivo, o generarlos dinámicamente en el CI con variables de entorno
ARG BUILD_DATE
ARG GIT_SHA
ARG PROJECT_NAME=NOMBRE_DEL_PROYECTO

LABEL org.opencontainers.image.title="${PROJECT_NAME} Backend API"
LABEL org.opencontainers.image.description="NestJS API for NOMBRE_DEL_PROYECTO platform"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.version="${GIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/tu-usuario/nombre_del_proyecto"
LABEL org.opencontainers.image.url="https://github.com/tu-usuario/nombre_del_proyecto"
LABEL org.opencontainers.image.vendor="NOMBRE_DEL_PROYECTO"
LABEL org.opencontainers.image.authors="Tu Nombre <tu@email.com>"
LABEL maintainer="contacto@tudominio.com"

# ─── Directorio de trabajo ───────────────────────────────────────────────────
WORKDIR /usr/src/app

# ─── Usuario no-root ──────────────────────────────────────────────────────────
# Seguridad: El contenedor NO corre como root (UID 1000 = usuario 'node')
# Esto previene escalación de privilegios si el contenedor es comprometido
RUN chown -R node:node /usr/src/app

# ─── Usuario no-root ──────────────────────────────────────────────────────────
# Seguridad: El proceso corre sin privilegios de root
USER node

# ─── Código de la aplicación ──────────────────────────────────────────────────
# COPY --chown=node:node . .
COPY --from=deps /usr/src/app/node_modules ./node_modules

# ─── Puerto expuesto ──────────────────────────────────────────────────────────
# ARG: Variable de build-time (se pasa desde docker-compose.yml)
# Valor por defecto si no se pasa build-arg
ARG PORT_BACKEND=4000
# ARG → ENV para que persista en runtime y esté disponible para la aplicación
ENV PORT_BACKEND=${PORT_BACKEND}
# EXPOSE: Documenta qué puerto usa internamente el contenedor (metadata)
# Nota: No abre puertos, solo es documentación para docker ps y -P
EXPOSE ${PORT_BACKEND}

# ─── tini como ENTRYPOINT ─────────────────────────────────────────────────────
# entrypoint: tini para manejo correcto de señales (graceful shutdown)
# tini gestiona señales POSIX correctamente:
# - SIGTERM se propaga al proceso hijo (graceful shutdown)
# - Previene procesos zombie
# - Docker stop funciona en < 10s (sin tini puede tardar 30s de timeout)
ENTRYPOINT ["/usr/bin/tini", "--"]

# ─── Comando de inicio ────────────────────────────────────────────────────────
# pnpm run start:dev: Ejecuta NestJS en modo watch (hot reload)
# El "--" pasa argumentos adicionales a Nest CLI si los hay
CMD ["pnpm", "run", "start:dev", "--"]
