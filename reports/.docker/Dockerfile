# filepath: reports/.docker/Dockerfile
# ══════════════════════════════════════════════════════════════════════════════
# REPORTS API - PYTHON/FLASK - DESARROLLO
# ══════════════════════════════════════════════════════════════════════════════
# Imagen base: Python 3.12 sobre Debian 12 (Bookworm) Slim
# Tamaño: ~150MB (vs ~1GB de la imagen completa)
# ══════════════════════════════════════════════════════════════════════════════

# ┌──────────────────────────────────────────────────────────────────────────┐
# │ ETAPA 1: BUILDER                                                         │
# │ Propósito: Compilar paquetes Python con extensiones C                    │
# └──────────────────────────────────────────────────────────────────────────┘
FROM python:3.12-slim@sha256:9e01bf1ae5db7649a236da7be1e94ffbbbdd7a93f867dd0d8d5720d9e1f89fab AS deps

# ─── Dependencias del sistema ─────────────────────────────────────────────────
# Herramientas necesarias para compilar paquetes Python con extensiones C
RUN apt-get update && apt-get install -y --no-install-recommends \
    # curl: Healthcheck de Docker Compose
    curl \
    # ca-certificates: Certificados SSL/TLS para requests HTTPS
    ca-certificates \
    # tini: Init system para manejar señales y procesos zombie (recomendado para Python)
    tini \
    # libpq5: Librería runtime de PostgreSQL (NO headers -dev, solo runtime)
    # Nota: psycopg2 fue compilado en builder con libpq-dev, aquí solo necesita libpq5
    libpq5 \
    # build-essential: Compiladores C/C++ (gcc, g++, make) para extensiones Python
    build-essential \
    # libpq-dev: Headers de PostgreSQL necesarios para compilar psycopg2
    libpq-dev \
    # gcc: Compilador C específico (incluido en build-essential pero explícito)
    gcc \
    # libfreetype6-dev: Librería para renderizado de fuentes en PDFs (reportlab)
    libfreetype6-dev \
    # zlib1g-dev: Librería de compresión para pandas y openpyxl (archivos Excel)
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# ─── Variables de entorno Python ──────────────────────────────────────────────
# PYTHONDONTWRITEBYTECODE=1: Evita generar archivos .pyc (reduce tamaño, mejora build)
ENV PYTHONDONTWRITEBYTECODE=1
# PYTHONUNBUFFERED=1: Logs en tiempo real (no buffereados)
ENV PYTHONUNBUFFERED=1

# ─── Directorio de trabajo ───────────────────────────────────────────────────
WORKDIR /app

# ─── Instalación de dependencias Python ───────────────────────────────────────
# Instalación de dependencias (como root)
COPY requirements.txt .

# pip install: Instalación de paquetes (pandas, flask, reportlab, etc.)
# --no-cache-dir: No guarda cache de pip (reduce tamaño de imagen)
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ┌──────────────────────────────────────────────────────────────────────────┐
# │ ETAPA 2: RUNNER (IMAGEN FINAL)                                           │
# │ Propósito: Solo runtime, sin herramientas de compilación                 │
# └──────────────────────────────────────────────────────────────────────────┘
FROM python:3.12-slim@sha256:9e01bf1ae5db7649a236da7be1e94ffbbbdd7a93f867dd0d8d5720d9e1f89fab AS dev

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

LABEL org.opencontainers.image.title="${PROJECT_NAME} Reports API"
LABEL org.opencontainers.image.description="Python API for NOMBRE_DEL_PROYECTO platform reports"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.version="${GIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/tu-usuario/nombre_del_proyecto"
LABEL org.opencontainers.image.url="https://github.com/tu-usuario/nombre_del_proyecto"
LABEL org.opencontainers.image.vendor="NOMBRE_DEL_PROYECTO"
LABEL org.opencontainers.image.authors="Tu Nombre <tu@email.com>"
LABEL maintainer="contacto@tudominio.com"

# ─── Dependencias del sistema ─────────────────────────────────────────────────
# Solo las necesarias para ejecutar la aplicación, sin herramientas de compilación
RUN apt-get update && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/*

# ─── Directorio de trabajo ───────────────────────────────────────────────────
WORKDIR /app

# ─── Copia de dependencias desde etapa deps ──────────────────────────────────
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

# ─── Usuario no-root ──────────────────────────────────────────────────────────
# Seguridad: El contenedor corre con UID 1000 (consistente con Node.js)
RUN groupadd -g 1000 nombre_del_proyecto && \
    useradd -u 1000 -g nombre_del_proyecto -m nombre_del_proyecto && \
    chown -R nombre_del_proyecto:nombre_del_proyecto /app

# ─── Usuario no-root ──────────────────────────────────────────────────────────
# Seguridad: El proceso corre sin privilegios de root
USER nombre_del_proyecto

# # ─── Instalación de dependencias Python ───────────────────────────────────────
# # Se copian primero requirements.txt para cache de Docker
# COPY --chown=nombre_del_proyecto:nombre_del_proyecto requirements.txt .

# # ─── Código de la aplicación ──────────────────────────────────────────────────
# COPY --chown=nombre_del_proyecto:nombre_del_proyecto . .

# ─── Puerto expuesto ──────────────────────────────────────────────────────────
# ARG: Variable de build-time (se pasa desde docker-compose.yml)
# Valor por defecto si no se pasa build-arg
ARG PORT_REPORTS=5000
# ARG → ENV para que persista en runtime y esté disponible para la aplicación
ENV PORT_REPORTS=${PORT_REPORTS}
# EXPOSE: Documenta qué puerto usa internamente el contenedor (metadata)
# Nota: No abre puertos, solo es documentación para docker ps y -P
EXPOSE ${PORT_REPORTS}

ENV FLASK_APP=main.py
ENV FLASK_DEBUG=1

# ─── tini como ENTRYPOINT ─────────────────────────────────────────────────────
# entrypoint: tini para manejo correcto de señales (graceful shutdown)
# tini gestiona señales POSIX correctamente:
# - SIGTERM se propaga al proceso hijo (graceful shutdown)
# - Previene procesos zombie
# - Docker stop funciona en < 10s (sin tini puede tardar 30s de timeout)
ENTRYPOINT ["/usr/bin/tini", "--"]

# ─── Comando de inicio ────────────────────────────────────────────────────────
# python main.py: Ejecuta Flask development server con auto-reload
# CMD ["python", "main.py"]
CMD ["flask", "run", "--host=0.0.0.0"]
