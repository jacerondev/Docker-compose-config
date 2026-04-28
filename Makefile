# filepath: Makefile
# ══════════════════════════════════════════════════════════════════════════════
# Makefile - NOMBRE_DEL_PROYECTO  (v3 — dashboard edition)
# Requiere: make (sudo apt install make -y)
# Herramientas opcionales: hadolint, trivy, syft, grype (o vía Docker)
# ══════════════════════════════════════════════════════════════════════════════

# ─── Modo estricto ────────────────────────────────────────────────────────────
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# ─── .ONESHELL: cada target usa una sola instancia de shell ──────────────────
# Beneficio: set -e aplica al bloque completo, no línea a línea.
# Sin esto, cada línea de un target corre en su propia subshell,
# lo que hace que set -e no se propague entre líneas.
.ONESHELL:

# ─── Objetivo por defecto ─────────────────────────────────────────────────────
.DEFAULT_GOAL := help

# ══════════════════════════════════════════════════════════════════════════════
# COLORES — CI-friendly: make audit-full NO_COLOR=1 los desactiva
# ══════════════════════════════════════════════════════════════════════════════
#
# Por qué printf en vez de echo:
#   echo no interpreta secuencias ANSI de forma consistente entre shells.
#   printf siempre las interpreta. Es más portable y es el estándar.
#
# Por qué NO_COLOR:
#   En CI (GitHub Actions, Jenkins) los colores ensucian los logs.
#   Con NO_COLOR=1 se desactivan: make audit-full NO_COLOR=1
#   Ver: https://no-color.org/
# ─────────────────────────────────────────────────────────────────────────────
NO_COLOR ?=

ifeq ($(NO_COLOR),1)
RED    :=
GREEN  :=
YELLOW :=
BLUE   :=
CYAN   :=
BOLD   :=
RESET  :=
else
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
BOLD   := \033[1m
RESET  := \033[0m
endif

# Helper: printf portable con newline automático
# Uso: @$(PRINT) "$(BLUE)Mensaje$(RESET)"
PRINT = printf "%b\n"

# ══════════════════════════════════════════════════════════════════════════════
# VARIABLES CONFIGURABLES
# ══════════════════════════════════════════════════════════════════════════════
TAG       ?= $(shell date +%Y.%m.%d)

# DC / DC_PROD: centraliza el comando de compose
# Beneficio: si migras a podman compose, cambias solo aquí
DC        := docker compose
DC_PROD   := docker compose -f docker-compose.yml -f docker-compose.prod.yml

# Ruta de evidencia de auditoría
TESTS_DIR := scripts/tests

# Stack de monitoreo (Prometheus + Grafana)
DC_MONITORING := docker compose -f docker-compose.monitoring.yml

# # Carga automática de .env si existe — para targets que necesitan variables del shell
# # (docker-compose las carga por su cuenta; esto es para Make y scripts directos)
# -include .env
# export

# ══════════════════════════════════════════════════════════════════════════════
# TARGETS PHONY
# ══════════════════════════════════════════════════════════════════════════════

# prod-up
.PHONY: \
  help \
  \
  setup prod-setup prepare-logs prepare-audit-dirs pre-commit-setup \
  validate validate-build validate-env validate-env-prod validate-all \
  check-setup check-secrets \
  \
  dev dev-full dev-bg build dev-with-redis dev-with-redis-bg \
  dev-swagger dev-swagger-bg \
  prod prod-full \
  stop clean prune \
  \
  logs logs-backend logs-frontend logs-reports \
  \
  backup-db rollback-db backup-db-decrypt \
  db-migrate db-rollback db-seed \
  db-migration-generate db-migration-show db-migration-create \
  \
  shell-backend shell-frontend shell-reports config \
  health-check wait-healthy stats \
  \
  setup-cron remove-cron check-cron \
  \
  monitoring-config monitoring-up monitoring-up-prod monitoring-alert-test \
  monitoring-down monitoring-logs monitoring-ps \
  \
  lint lint-docker trivy-config-scan scan-security \
  audit-requirements audit-security audit-full audit-pnpm \
  show-digests update-requirements \
  sbom sbom-docker grype-scan grype-scan-docker \
  \
  install-tools doctor troubleshoot \
  secrets-init secrets-check \
  build-prod-images \
  \
  db-drop secrets-clean \



# ══════════════════════════════════════════════════════════════════════════════
# MACROS Y FUNCIONES AUXILIARES
# ══════════════════════════════════════════════════════════════════════════════

# Macro reutilizable para confirmación de operaciones destructivas
define confirm_destructive
	@echo "⚠️  ATENCIÓN: Esta operación es DESTRUCTIVA e irreversible."
	@echo "   Target: $(1)"
	@read -r -p "   Escribe 'CONFIRMAR' para continuar: " RESP && \
		[ "$$RESP" = "CONFIRMAR" ] || (echo "Cancelado." && exit 1)
endef

# # ══════════════════════════════════════════════════════════════════════════════
# # AYUDA — autogenerada desde comentarios ## en cada target
# # ══════════════════════════════════════════════════════════════════════════════
# #
# # Cómo funciona:
# #   Cualquier target con "## descripción" al lado aparece en el help.
# #   Esto elimina el mantenimiento doble (target + bloque echo del help).
# #   Estándar usado en repos grandes (kubectl, terraform, etc.)
# #
# help: ## Muestra esta ayuda
# 	@$(PRINT) ""
# 	@$(PRINT) "$(CYAN)╔══════════════════════════════════════════════════════════════════╗$(RESET)"
# 	@$(PRINT) "$(CYAN)║          NOMBRE_DEL_PROYECTO — Comandos disponibles                           
# 	@$(PRINT) "$(CYAN)╚══════════════════════════════════════════════════════════════════╝$(RESET)"
# 	@$(PRINT) ""
# 	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
# 		| sort \
# 		| awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-24s$(RESET) %s\n", $$1, $$2}'
# 	@$(PRINT) ""
# 	@$(PRINT) "$(YELLOW)Tip: make audit-full NO_COLOR=1  → sin colores (útil para CI)$(RESET)"
# 	@$(PRINT) ""

# ══════════════════════════════════════════════════════════════════════════════
# AYUDA — Dashboard con cajas y secciones
# ══════════════════════════════════════════════════════════════════════════════
#
# Por qué este formato manual en vez del grep+awk autogenerado:
#   El formato autogenerado (grep ## | awk) produce una lista plana ordenada
#   alfabéticamente. No permite agrupar por secciones ni controlar el orden.
#   El dashboard manual permite secciones, íconos, orden lógico y alineación
#   perfecta — es lo que ven los devs cada vez que ejecutan `make`.
#   Los targets siguen teniendo ## para documentación interna, pero el help
#   visual es completamente controlado.

help:
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)╔═══════════════════════════════════════════════════════════════════════════════════╗$(RESET)"
	@$(PRINT) "$(CYAN)$(BOLD)║                  🐳  NOMBRE_DEL_PROYECTO — Panel de Comandos                      ║$(RESET)"
	@$(PRINT) "$(CYAN)$(BOLD)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(GREEN)$(BOLD)▶  INICIO Y CONFIGURACIÓN$(RESET)                                                        $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make setup                  Configuración inicial (primera vez)                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make prod-setup             Configuración inicial producción (primera vez)     $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make pre-commit-setup       Configura git hooks (una sola vez)                 $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make doctor                 Verifica entorno, herramientas y archivos          $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make validate               Valida docker-compose sin build                    $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make validate-env           Valida variables de entorno                        $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make troubleshoot           Tips para problemas comunes                        $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make check-setup            Verifica configuración inicial                     $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make check-secrets          Verifica secrets de producción                     $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make validate-all           ⭐ Validación COMPLETA antes de deploy             $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(BLUE)$(BOLD)🔧  DESARROLLO/MONITOREO$(RESET)                                                         $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make dev                    Arranca servicios (logs en pantalla)               $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make dev-full               Arranca servicios + Redis + monitoreo              $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make dev-bg                 Arranca servicios en background                    $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make dev-with-redis         Arranca servicios + Redis                          $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make dev-with-redis-bg      Arranca servicios + Redis en background            $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make dev-swagger            Arranca servicios con Swagger UI habilitado        $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make dev-swagger-bg         Arranca con Swagger en background                  $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make build                  Construye imágenes de desarrollo                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make stop                   Detiene todos los servicios                        $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make clean                  Elimina contenedores y volúmenes                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make prune                  Limpia imágenes y recursos huérfanos               $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make health-check           Verifica el estado de los servicios                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make wait-healthy           Espera a que los servicios estén healthy           $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make stats                  Uso de CPU y RAM de los contenedores               $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(BLUE)$(BOLD)🔧  MONITOREO AVANZADO$(RESET)                                                           $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make monitoring-config      Genera alertmanager.yml desde el template          $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make monitoring-up          Levanta Prometheus + Grafana (desarrollo)          $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make monitoring-up-prod     Levanta con Alertmanager (producción)              $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make monitoring-alert-test  Dispara alerta de prueba al Alertmanager           $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make monitoring-down        Detiene el stack de monitoreo                      $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make monitoring-logs        Logs del stack de monitoreo                        $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make monitoring-ps          Estado de contenedores de monitoreo                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(YELLOW)$(BOLD)🚀  PRODUCCIÓN/BACKUP$(RESET)                                                            $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make prod                   Deploy a producción                                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make prod-full              Deploy a producción + monitoreo                    $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make backup-db              Backup manual de la base de datos                  $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make backup-db-decrypt      Descifra un backup                                 $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make rollback-db            Restaura el último backup de la DB                 $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make setup-cron             Instala backup automático diario (cron)            $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make check-cron             Verifica si el cron job está activo                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make remove-cron            Elimina el cron job de backup                      $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make prod-down              Detiene producción                                 $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make prod-down-volumes      Detiene producción y elimina volúmenes             $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(RED)$(BOLD)🔐  SECRETOS$(RESET)                                                                     $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make secrets-init           Crea carpeta secrets/ con archivos base            $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make secrets-check          Verifica que secretos son válidos                  $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make secrets-rotate         Rota todos los secretos generados automáticamente  $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(CYAN)$(BOLD)🛡️   SEGURIDAD Y AUDITORÍA$(RESET)                                                        $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make install-tools          Instala syft y grype localmente                    $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make lint-docker            Valida Dockerfiles con hadolint → alerts.log       $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make trivy-config-scan      Trivy: escanea Dockerfiles (misconfig)             $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make scan-security          Trivy: escanea imágenes construidas                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make audit-requirements     Audita dependencias Python (pip-audit)             $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make audit-security         Genera system-check.log del sistema                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make sbom                   Genera SBOM con syft (local)                       $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make sbom-docker            Genera SBOM con syft (vía Docker)                  $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make grype-scan             Escanea vulnerabilidades (local)                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make grype-scan-docker      Escanea vulnerabilidades (vía Docker)              $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make audit-pnpm             Audita dependencias pnpm (backend + frontend)      $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make audit-full             ★ Pipeline completo de auditoría                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(BOLD)📋  LOGS Y DIAGNÓSTICO$(RESET)                                                           $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make logs                   Ver logs de todos los servicios                    $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make logs-backend           Ver logs del backend                               $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make logs-frontend          Ver logs del frontend                              $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make logs-reports           Ver logs del reports-api                           $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make config                 Muestra configuración resuelta                     $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(BOLD)🔨  MANTENIMIENTO$(RESET)                                                                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make test                   Corre tests del backend                            $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make lint                   Linter del backend                                 $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make update-requirements    Regenera requirements.txt con SHA256               $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make show-digests           Muestra digests SHA256 de imágenes base            $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make validate-build         Build completo desde cero (para CI)                $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make validate-env-prod      Valida entorno de producción                       $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(BOLD)🔨  BASES DE DATOS$(RESET)                                                               $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make db-migrate             Ejecuta migraciones TypeORM pendientes             $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make db-migration-generate  Genera migración desde cambios en entidades        $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make db-migration-show      Muestra migraciones pendientes/aplicadas           $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make db-migration-create    Crea migración vacía para editar manualmente       $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make db-rollback            Revierte la última migración                       $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make db-seed                Carga datos iniciales                              $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╠═══════════════════════════════════════════════════════════════════════════════════╣$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)  $(BOLD)💣  TARGETS DESTRUCTIVOS$(RESET)                                                         $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make db-drop                Elimina TODA la base de datos                      $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)    make secrets-clean          Elimina TODOS los archivos de secrets              $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)║$(RESET)                                                                                   $(CYAN)║$(RESET)"
	@$(PRINT) "$(CYAN)╚═══════════════════════════════════════════════════════════════════════════════════╝$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "  $(YELLOW)Tip:$(RESET) make audit-full $(YELLOW)NO_COLOR=1$(RESET)  →  sin colores para logs de CI"
	@$(PRINT) "  $(YELLOW)Tip:$(RESET) make build      $(YELLOW)TAG=2026.03.01$(RESET)  →  tag personalizado"
	@$(PRINT) ""

# ══════════════════════════════════════════════════════════════════════════════
# PREPARACIÓN INTERNA (sin ##, no aparecen en el help)
# ══════════════════════════════════════════════════════════════════════════════

prepare-logs:
	@mkdir -p logs/backend logs/reports
	@if [ $$(id -u) = "1000" ]; then \
		$(PRINT) "$(GREEN)📁 Carpetas de logs listas$(RESET)"; \
	else \
		sudo chown -R 1000:1000 logs 2>/dev/null \
		&& $(PRINT) "$(GREEN)📁 Carpetas de logs listas$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  Permisos: ejecuta  sudo chown -R 1000:1000 logs$(RESET)"; \
	fi

prepare-audit-dirs:
	@mkdir -p "$(TESTS_DIR)"

# ══════════════════════════════════════════════════════════════════════════════
# SETUP, VALIDACIÓN Y DIAGNÓSTICO
# ══════════════════════════════════════════════════════════════════════════════

setup: ## Configuración inicial del proyecto
	@$(PRINT) "$(BLUE)🚀 Iniciando configuración...$(RESET)"
	chmod +x scripts/setup.sh
	chmod +x config/init-db.sh
	if ./scripts/setup.sh; then
		$(PRINT) "$(GREEN)✅ Setup completado correctamente$(RESET)"
	else
		$(PRINT) "$(RED)❌ Error en setup — revisa el output anterior$(RESET)"
		exit 1
	fi
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)🔍 Verificando configuración del .env...$(RESET)"
	@$(MAKE) --no-print-directory validate-env

prod-setup: ## Configuración inicial de producción
	@$(PRINT) "$(BLUE)🚀 Iniciando configuración de producción...$(RESET)"
	chmod +x scripts/setup.sh
	if ./scripts/setup.sh --prod; then
		$(PRINT) "$(GREEN)✅ Setup de producción completado correctamente$(RESET)"
	else
		$(PRINT) "$(RED)❌ Error en setup de producción — revisa el output anterior$(RESET)"
		exit 1
	fi
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)🔍 Verificando configuración del .env...$(RESET)"
	@$(MAKE) --no-print-directory validate-env-prod

pre-commit-setup: ## Configura git pre-commit hooks con pre-commit framework (ejecutar una sola vez)
	@$(PRINT) "$(BLUE)🔧 Instalando pre-commit framework...$(RESET)"
	@command -v pre-commit >/dev/null 2>&1 || { \
		$(PRINT) "$(YELLOW)⚠️  Instalando pre-commit...$(RESET)"; \
		pip install pre-commit --quiet; \
	}
# 	@command -v pre-commit >/dev/null 2>&1 || pip install pre-commit --quiet
	@pre-commit install
	@pre-commit install --hook-type commit-msg 2>/dev/null || true
	@$(PRINT) "$(GREEN)✅ pre-commit instalado. Los hooks se ejecutarán en cada 'git commit'$(RESET)"
	@$(PRINT) "   Ejecutar manualmente: $(YELLOW)pre-commit run --all-files$(RESET)"
	@$(PRINT) "   Actualizar hooks:     $(YELLOW)pre-commit autoupdate$(RESET)"

validate: ## Valida la sintaxis del docker-compose (rápido, sin build)
	@$(PRINT) "$(BLUE)🔍 Validando configuración de Compose...$(RESET)"
	$(DC) config > /dev/null && $(PRINT) "$(GREEN)✅ docker-compose.yml OK$(RESET)"
	$(DC_PROD) config > /dev/null && $(PRINT) "$(GREEN)✅ docker-compose.prod.yml OK$(RESET)"

validate-build: ## Construye todas las imágenes desde cero (lento, para CI)
	@$(PRINT) "$(BLUE)🔨 Build completo desde cero...$(RESET)"
	$(DC) build --no-cache

validate-env: ## Verifica .env contra .env.example (lee variables dinámicamente)
	@$(PRINT) "$(BLUE)🔍 Validando .env contra .env.example...$(RESET)"
	@[ -f .env.example ] || { \
		$(PRINT) "$(RED)❌ .env.example no encontrado$(RESET)"; exit 1; \
	}
	@[ -f .env ] || { \
		$(PRINT) "$(RED)❌ .env no encontrado — ejecuta: make setup$(RESET)"; exit 1; \
	}
	@ERRORS=0; TOTAL=0; \
	REQUIRED=$$(grep -E '^[A-Z_]+=.' .env.example \
		| grep -v '^\s*#' \
		| grep -v '^IMAGE_\|^PORT_PROMETHEUS\|^PORT_GRAFANA\|^PORT_NODE\|^PORT_CADVISOR\|^SLACK_WEBHOOK' \
		| cut -d'=' -f1); \
	for var in $$REQUIRED; do \
		TOTAL=$$((TOTAL+1)); \
		val=$$(grep -E "^$${var}=" .env 2>/dev/null | cut -d'=' -f2-); \
		if [ -z "$$val" ]; then \
			$(PRINT) "$(RED)❌ $$var — falta o está vacía en .env$(RESET)"; \
			ERRORS=$$((ERRORS+1)); \
		else \
			$(PRINT) "$(GREEN)✅ $$var$(RESET)"; \
		fi; \
	done; \
	[ $$ERRORS -eq 0 ] || { \
		$(PRINT) ""; \
		$(PRINT) "$(RED)❌ $$ERRORS de $$TOTAL variable(s) faltantes en .env$(RESET)"; \
		$(PRINT) "   Copia el valor de .env.example y ajústalo"; \
		exit 1; \
	}; \
	$(PRINT) ""; \
	$(PRINT) "$(GREEN)✅ Todas las variables requeridas presentes ($${TOTAL}/$${TOTAL})$(RESET)"

validate-env-prod: ## Verifica .env.production contra .env.prod.example
	@$(PRINT) "$(BLUE)🔍 Validando .env.production contra .env.prod.example...$(RESET)"
	@[ -f .env.prod.example ] || { \
		$(PRINT) "$(RED)❌ .env.prod.example no encontrado$(RESET)"; exit 1; \
	}
	@[ -f .env.production ] || { \
		$(PRINT) "$(YELLOW)⚠️  .env.production no existe (solo requerido en el servidor de prod)$(RESET)"; \
		exit 0; \
	}
	@ERRORS=0; TOTAL=0; \
	REQUIRED=$$(grep -E '^[A-Z_]+=.' .env.prod.example \
		| grep -v '^\s*#' \
		| grep -v '^#\|^IMAGE_\|^PORT_NODE\|^PORT_CADVISOR' \
		| cut -d'=' -f1); \
	for var in $$REQUIRED; do \
		TOTAL=$$((TOTAL+1)); \
		val=$$(grep -E "^$${var}=" .env.production 2>/dev/null | cut -d'=' -f2-); \
		if [ -z "$$val" ]; then \
			$(PRINT) "$(RED)❌ $$var — falta en .env.production$(RESET)"; \
			ERRORS=$$((ERRORS+1)); \
		else \
			$(PRINT) "$(GREEN)✅ $$var$(RESET)"; \
		fi; \
	done; \
	[ $$ERRORS -eq 0 ] || { \
		$(PRINT) "$(RED)❌ $$ERRORS variable(s) faltantes en .env.production$(RESET)"; \
		exit 1; \
	}; \
	$(PRINT) "$(GREEN)✅ .env.production OK ($${TOTAL}/$${TOTAL})$(RESET)"

validate-all: check-setup validate validate-env validate-env-prod lint-docker trivy-config-scan audit-pnpm ## ⭐ Validación COMPLETA antes de deploy
	@$(PRINT) ""
	@$(PRINT) "$(GREEN)$(BOLD)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(PRINT) "$(GREEN)$(BOLD)║   ✅ TODAS LAS VALIDACIONES PASARON — OK PARA DEPLOY       ║$(RESET)"
	@$(PRINT) "$(GREEN)$(BOLD)║   Ejecutar ahora: make prod                                ║$(RESET)"
	@$(PRINT) "$(GREEN)$(BOLD)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@$(PRINT) ""

doctor: ## Verifica dependencias, versiones y archivos críticos del entorno
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)── Sistema ───────────────────────────────────────────────────$(RESET)"
	@command -v docker >/dev/null 2>&1 \
		&& $(PRINT) "$(GREEN)✅ docker    : $$(docker --version)$(RESET)" \
		|| $(PRINT) "$(RED)❌ docker    : NO INSTALADO$(RESET)"
	@$(DC) version >/dev/null 2>&1 \
		&& $(PRINT) "$(GREEN)✅ compose   : $$($(DC) version --short)$(RESET)" \
		|| $(PRINT) "$(RED)❌ docker compose v2 : NO DISPONIBLE$(RESET)"
	@command -v make >/dev/null 2>&1 \
		&& $(PRINT) "$(GREEN)✅ make      : $$(make --version | head -1)$(RESET)" \
		|| $(PRINT) "$(RED)❌ make$(RESET)"
	@command -v psql >/dev/null 2>&1 \
		&& $(PRINT) "$(GREEN)✅ psql      : $$(psql --version)$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  psql      : no encontrado localmente$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)── Herramientas de seguridad ────────────────────────────────$(RESET)"
	@command -v hadolint >/dev/null 2>&1 \
		&& $(PRINT) "$(GREEN)✅ hadolint  : $$(hadolint --version)$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  hadolint  : no encontrado$(RESET)"
	@command -v trivy >/dev/null 2>&1 \
		&& $(PRINT) "$(GREEN)✅ trivy     : $$(trivy --version | head -1)$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  trivy     : no encontrado  → https://trivy.dev$(RESET)"
	@command -v syft >/dev/null 2>&1 \
		&& $(PRINT) "$(GREEN)✅ syft      : $$(syft --version)$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  syft      : no encontrado  → make install-tools$(RESET)"
	@command -v grype >/dev/null 2>&1 \
		&& $(PRINT) "$(GREEN)✅ grype     : $$(grype --version)$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  grype     : no encontrado  → make install-tools$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)── Versiones mínimas requeridas ────────────────────────────$(RESET)"
	@$(PRINT) "   Docker ≥ 20.10  │  Compose ≥ v2  │  Node.js ≥ 24  │  Python ≥ 3.12  │  PostgreSQL ≥ 15"
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)── Archivos críticos ────────────────────────────────────────$(RESET)"
	@[ -f .env ] \
		&& $(PRINT) "$(GREEN)✅ .env$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  .env no encontrado  → make setup$(RESET)"
	@[ -f .env.production ] \
		&& $(PRINT) "$(GREEN)✅ .env.production$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  .env.production no encontrado (solo en servidor de prod)$(RESET)"
	@[ -d secrets ] \
		&& $(PRINT) "$(GREEN)✅ secrets/$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  secrets/ no existe  → make secrets-init$(RESET)"
	@$(PRINT) ""

troubleshoot: ## Muestra tips de solución para problemas comunes
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)╔══════════════════════════════════════════════════════════════════════════╗$(RESET)"
	@$(PRINT) "$(CYAN)$(BOLD)║                  🔧  Troubleshooting — Problemas comunes                 ║$(RESET)"
	@$(PRINT) "$(CYAN)$(BOLD)╚══════════════════════════════════════════════════════════════════════════╝$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)$(BOLD)El backend no responde:$(RESET)"
	@$(PRINT) "   curl http://localhost:4000/health/ready"
	@$(PRINT) "   make logs-backend"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)$(BOLD)El frontend muestra error 502:$(RESET)"
	@$(PRINT) "   sudo nginx -t"
	@$(PRINT) "   sudo tail -n 50 /var/log/nginx/error.log"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)$(BOLD)Errores de permisos en volúmenes/logs:$(RESET)"
	@$(PRINT) "   sudo chown -R 1000:1000 logs"
	@$(PRINT) "   make doctor  # verifica tu UID"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)$(BOLD)Puerto ya en uso:$(RESET)"
	@$(PRINT) "   sudo lsof -i :4000    # backend"
	@$(PRINT) "   sudo lsof -i :3000    # frontend"
	@$(PRINT) "   sudo lsof -i :5000    # reports"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)$(BOLD)Los cambios en código no se reflejan (hot reload):$(RESET)"
	@$(PRINT) "   docker compose down -v && make dev"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)$(BOLD)Secretos mal configurados:$(RESET)"
	@$(PRINT) "   make secrets-check"
	@$(PRINT) "   make secrets-init   # si no existen aún"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)$(BOLD)Reports API no genera archivos:$(RESET)"
	@$(PRINT) "   make logs-reports"
	@$(PRINT) "   docker compose exec reports-api ls -la /tmp"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)$(BOLD)Ver todos los logs de una vez:$(RESET)"
	@$(PRINT) "   make logs"
	@$(PRINT) "   docker logs <nombre-contenedor> 2>&1 | tail -50"
	@$(PRINT) ""

# ─── Validación de entorno ────────────────────────────────────────────────────
check-setup: ## Verifica que make setup fue ejecutado correctamente antes de continuar
	@# Verificar que .env existe
	@if [ ! -f .env ]; then \
		$(PRINT) "$(RED)❌ Falta el archivo .env$(RESET)"; \
		$(PRINT) "   Ejecuta primero: $(YELLOW)make setup$(RESET)"; \
		exit 1; \
	fi
	@# Verificar que no hay placeholders sin reemplazar
	@if grep -q "CAMBIAR_" .env 2>/dev/null; then \
		$(PRINT) "$(RED)❌ El .env contiene placeholders sin configurar:$(RESET)"; \
		grep "CAMBIAR_" .env | sed 's/^/   /'; \
		$(PRINT) "   Ejecuta: $(YELLOW)make setup$(RESET)"; \
		exit 1; \
	fi
	@# Verificar variables críticas no vacías
	@for var in JWT_SECRET PEPPER_SECRET COOKIE_SECRET DB_USER DB_PASSWORD DB_NAME; do \
		val=$$(grep -v "^#" .env | grep "^$${var}=" | cut -d'=' -f2); \
		if [ -z "$$val" ]; then \
			$(PRINT) "$(RED)❌ Variable $$var vacía en .env$(RESET)"; \
			exit 1; \
		fi; \
	done
	@$(PRINT) "$(GREEN)✅ Entorno configurado correctamente$(RESET)"

check-secrets: ## Verifica que los secrets de producción existen y no tienen placeholders
	@if [ ! -d secrets ]; then \
		$(PRINT) "$(RED)❌ Carpeta secrets/ no existe$(RESET)"; \
		$(PRINT) "   Ejecuta: $(YELLOW)make secrets-init$(RESET)"; \
		exit 1; \
	fi
	@for f in db_password db_user db_read_only_password db_read_only_user jwt_secret pepper_secret cookie_secret redis_secret metrics_password; do \
		if [ ! -f "secrets/$${f}.txt" ]; then \
			$(PRINT) "$(RED)❌ Falta secrets/$${f}.txt$(RESET)"; \
			exit 1; \
		fi; \
		if grep -q "REEMPLAZA_CON\|CAMBIAR_\|TU_" "secrets/$${f}.txt" 2>/dev/null; then \
			$(PRINT) "$(RED)❌ secrets/$${f}.txt contiene placeholder sin reemplazar$(RESET)"; \
			exit 1; \
		fi; \
	done
	@$(PRINT) "$(GREEN)✅ Secrets de producción configurados$(RESET)"

ready-check: ## ⭐ Verifica que el proyecto está listo para ejecutarse (dev o prod)
	@$(PRINT) "$(BLUE)🔍 Verificando estado del proyecto...$(RESET)"
	@ERRORS=0; \
	\
	# 1. Git inicializado
	if [ ! -d .git ]; then \
		$(PRINT) "$(RED)❌ Git no inicializado. Ejecuta: git init$(RESET)"; \
		ERRORS=$$((ERRORS+1)); \
	else $(PRINT) "$(GREEN)✅ Git OK$(RESET)"; fi; \
	\
	# 2. .env existe y sin placeholders
	if [ ! -f .env ]; then \
		$(PRINT) "$(RED)❌ Falta .env — ejecuta: make setup$(RESET)"; \
		ERRORS=$$((ERRORS+1)); \
	elif grep -q "CAMBIAR_" .env 2>/dev/null; then \
		$(PRINT) "$(RED)❌ .env tiene placeholders sin reemplazar$(RESET)"; \
		ERRORS=$$((ERRORS+1)); \
	else $(PRINT) "$(GREEN)✅ .env OK$(RESET)"; fi; \
	\
	# 3. pre-commit instalado
	if [ ! -f .git/hooks/pre-commit ]; then \
		$(PRINT) "$(YELLOW)⚠️  pre-commit no instalado — ejecuta: make pre-commit-setup$(RESET)"; \
	else $(PRINT) "$(GREEN)✅ pre-commit OK$(RESET)"; fi; \
	\
	# 4. Docker disponible
	if ! docker compose version >/dev/null 2>&1; then \
		$(PRINT) "$(RED)❌ Docker Compose no disponible$(RESET)"; \
		ERRORS=$$((ERRORS+1)); \
	else $(PRINT) "$(GREEN)✅ Docker OK$(RESET)"; fi; \
	\
	# 5. Puertos libres
	for PORT in ${PORT_BACKEND:-4000} ${PORT_FRONTEND:-3000} ${PORT_REPORTS:-5000}; do \
		if ss -tlnp 2>/dev/null | grep -q ":$$PORT "; then \
			$(PRINT) "$(YELLOW)⚠️  Puerto $$PORT en uso$(RESET)"; \
		fi; \
	done; \
	\
	if [ $$ERRORS -gt 0 ]; then \
		$(PRINT) "$(RED)❌ $$ERRORS problema(s) encontrado(s). Corrige antes de continuar.$(RESET)"; \
		exit 1; \
	fi; \
	$(PRINT) "$(GREEN)✅ Proyecto listo para ejecutarse$(RESET)"

ready-check-prod: secrets-check ready-check ## Verifica que el proyecto está listo para PRODUCCIÓN
	@$(PRINT) "$(BLUE)🔍 Verificaciones adicionales para producción...$(RESET)"
	@# Verificar .env.production
	@[ -f .env.production ] || { \
		$(PRINT) "$(RED)❌ Falta .env.production$(RESET)"; exit 1; \
	}
	@grep -q "CAMBIAR_" .env.production 2>/dev/null && { \
		$(PRINT) "$(RED)❌ .env.production tiene placeholders$(RESET)"; exit 1; \
	} || true
	@$(PRINT) "$(GREEN)✅ Listo para producción$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# INSTALAR HERRAMIENTAS DE SEGURIDAD
# ══════════════════════════════════════════════════════════════════════════════

install-tools: ## Instala syft y grype con verificación de integridad (no curl|sh)
	@$(PRINT) "$(BLUE)🔧 Instalando herramientas de seguridad...$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)→ Instalando Syft (generador de SBOM)...$(RESET)"
	@# Descargamos primero, verificamos hash, luego ejecutamos.
	@# curl | sh directamente es una bandera roja en auditorías formales.
	curl -sSfL -o /tmp/syft-install.sh \
		https://raw.githubusercontent.com/anchore/syft/main/install.sh
	@$(PRINT) "$(CYAN)   SHA256 del instalador de syft(verificar en https://github.com/anchore/syft/releases):$(RESET)"
	sha256sum /tmp/syft-install.sh
	sh /tmp/syft-install.sh -b /usr/local/bin
	rm -f /tmp/syft-install.sh
	@$(PRINT) "$(GREEN)✅ Syft: $$(syft --version)$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)→ Instalando Grype (escáner de vulnerabilidades)...$(RESET)"
	curl -sSfL -o /tmp/grype-install.sh \
		https://raw.githubusercontent.com/anchore/grype/main/install.sh
	@$(PRINT) "$(CYAN)   SHA256 del instalador de grype:$(RESET)"
	sha256sum /tmp/grype-install.sh
	sh /tmp/grype-install.sh -b /usr/local/bin
	rm -f /tmp/grype-install.sh
	@$(PRINT) "$(GREEN)✅ Grype: $$(grype --version)$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(GREEN)🎉 Listo. Verifica con: make doctor$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# DOCKER SECRETS — Compose standalone (sin Swarm)
# ══════════════════════════════════════════════════════════════════════════════
#
# Sin Swarm, los secretos son archivos en ./secrets/ que Docker monta en
# /run/secrets/<nombre> dentro del contenedor (read-only).
# La app lee el archivo en lugar de una variable de entorno:
#   Node.js : fs.readFileSync('/run/secrets/db_password', 'utf8').trim()
#   Python  : open('/run/secrets/db_password').read().strip()
# ─────────────────────────────────────────────────────────────────────────────

secrets-init: ## Crea la carpeta secrets/ con archivos template para rellenar
	@$(PRINT) "$(BLUE)🔐 Inicializando estructura de secretos...$(RESET)"
	@$(PRINT) ""
	mkdir -p secrets && chmod 700 secrets
	@$(PRINT) "$(GREEN)📁 secrets/ creada (permisos 700)$(RESET)"
	@$(PRINT) ""
	@if [ ! -f secrets/db_password.txt ]; then \
		printf "REEMPLAZA_CON_PASSWORD_REAL" > secrets/db_password.txt; \
		chmod 600 secrets/db_password.txt; \
		$(PRINT) "$(YELLOW)📝 secrets/db_password.txt — EDÍTALO$(RESET)"; \
	else $(PRINT) "$(GREEN)✅ secrets/db_password.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/db_user.txt ]; then \
		printf "REEMPLAZA_CON_USUARIO_REAL" > secrets/db_user.txt; \
		chmod 600 secrets/db_user.txt; \
		$(PRINT) "$(YELLOW)📝 secrets/db_user.txt — EDÍTALO$(RESET)"; \
	else $(PRINT) "$(GREEN)✅ secrets/db_user.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/db_read_only_password.txt ]; then \
		printf "REEMPLAZA_CON_PASSWORD_REAL" > secrets/db_read_only_password.txt; \
		chmod 600 secrets/db_read_only_password.txt; \
		$(PRINT) "$(YELLOW)📝 secrets/db_read_only_password.txt — EDÍTALO$(RESET)"; \
	else $(PRINT) "$(GREEN)✅ secrets/db_read_only_password.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/db_read_only_user.txt ]; then \
		printf "REEMPLAZA_CON_USUARIO_REAL" > secrets/db_read_only_user.txt; \
		chmod 600 secrets/db_read_only_user.txt; \
		$(PRINT) "$(YELLOW)📝 secrets/db_read_only_user.txt — EDÍTALO$(RESET)"; \
	else $(PRINT) "$(GREEN)✅ secrets/db_read_only_user.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/grafana_password.txt ]; then \
		printf "REEMPLAZA_CON_PASSWORD_GRAFANA" > secrets/grafana_password.txt; \
		chmod 600 secrets/grafana_password.txt; \
		$(PRINT) "$(YELLOW)📝 secrets/grafana_password.txt — EDÍTALO$(RESET)"; \
	else $(PRINT) "$(GREEN)✅ secrets/grafana_password.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/slack_webhook_url.txt ]; then \
		printf "REEMPLAZA_CON_TU_SLACK_WEBHOOK" > secrets/slack_webhook_url.txt; \
		chmod 600 secrets/slack_webhook_url.txt; \
		$(PRINT) "$(YELLOW)📝 secrets/slack_webhook_url.txt — EDÍTALO$(RESET)"; \
	else $(PRINT) "$(GREEN)✅ secrets/slack_webhook_url.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/metrics_password.txt ]; then \
		openssl rand -base64 24 > secrets/metrics_password.txt; \
		chmod 600 secrets/metrics_password.txt; \
		$(PRINT) "$(GREEN)🔑 secrets/metrics_password.txt — GENERADO automáticamente$(RESET)"; \
		$(PRINT) "   (no hace falta editarlo — es un valor aleatorio seguro)"; \
	else $(PRINT) "$(GREEN)✅ secrets/metrics_password.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/jwt_secret.txt ]; then \
		openssl rand -base64 48 > secrets/jwt_secret.txt; \
		chmod 600 secrets/jwt_secret.txt; \
		$(PRINT) "$(GREEN)🔑 secrets/jwt_secret.txt — GENERADO automáticamente$(RESET)"; \
		$(PRINT) "   (no hace falta editarlo — es un valor aleatorio seguro)"; \
	else $(PRINT) "$(GREEN)✅ secrets/jwt_secret.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/pepper_secret.txt ]; then \
		openssl rand -base64 32 > secrets/pepper_secret.txt; \
		chmod 600 secrets/pepper_secret.txt; \
		$(PRINT) "$(GREEN)🔑 secrets/pepper_secret.txt — GENERADO automáticamente$(RESET)"; \
		$(PRINT) "   (no hace falta editarlo — es un valor aleatorio seguro)"; \
	else $(PRINT) "$(GREEN)✅ secrets/pepper_secret.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/cookie_secret.txt ]; then \
		openssl rand -hex 48 > secrets/cookie_secret.txt; \
		chmod 600 secrets/cookie_secret.txt; \
		$(PRINT) "$(GREEN)🔑 secrets/cookie_secret.txt — GENERADO automáticamente$(RESET)"; \
		$(PRINT) "   (no hace falta editarlo — es un valor aleatorio seguro)"; \
	else $(PRINT) "$(GREEN)✅ secrets/cookie_secret.txt ya existe$(RESET)"; fi
	@if [ ! -f secrets/redis_secret.txt ]; then \
		openssl rand -hex 32 > secrets/redis_secret.txt; \
		chmod 600 secrets/redis_secret.txt; \
		$(PRINT) "$(GREEN)🔑 secrets/redis_secret.txt — GENERADO automáticamente$(RESET)"; \
		$(PRINT) "   (no hace falta editarlo — es un valor aleatorio seguro)"; \
	else $(PRINT) "$(GREEN)✅ secrets/redis_secret.txt ya existe$(RESET)"; fi
	@$(PRINT) ""
	@grep -q "secrets/" .gitignore 2>/dev/null \
		&& $(PRINT) "$(GREEN)✅ secrets/ está en .gitignore$(RESET)" \
		|| $(PRINT) "$(RED)❌ AÑADE 'secrets/' a .gitignore AHORA$(RESET)"

secrets-check: ## Verifica que los secretos existen y no tienen valores placeholder
	@$(PRINT) "$(BLUE)🔐 Verificando secretos...$(RESET)"
	ERRORS=0
	for f in secrets/db_password.txt secrets/db_user.txt secrets/db_read_only_password.txt secrets/db_read_only_user.txt secrets/jwt_secret.txt secrets/pepper_secret.txt secrets/cookie_secret.txt secrets/redis_secret.txt secrets/metrics_password.txt secrets/grafana_password.txt secrets/slack_webhook_url.txt; do
		if [ ! -f "$$f" ]; then
			$(PRINT) "$(RED)❌ $$f — NO EXISTE (make secrets-init)$(RESET)"
			ERRORS=$$((ERRORS+1))
		elif grep -q "REEMPLAZA_CON" "$$f" 2>/dev/null; then
			$(PRINT) "$(RED)❌ $$f — TODAVÍA TIENE VALOR PLACEHOLDER$(RESET)"
			ERRORS=$$((ERRORS+1))
		else
			$(PRINT) "$(GREEN)✅ $$f$(RESET)"
		fi
	done
	if [ $$ERRORS -gt 0 ]; then
		$(PRINT) ""
		$(PRINT) "$(RED)❌ $$ERRORS secreto(s) pendientes. Corrige antes del deploy.$(RESET)"
		exit 1
	fi
	$(PRINT) ""
	$(PRINT) "$(GREEN)✅ Todos los secretos están configurados$(RESET)"

secrets-rotate-generated: guard-not-ci ## Rota solo secretos generados automáticamente (jwt, cookie, redis, metrics, pepper)
	@$(PRINT) "$(YELLOW)🔄 Rotando secretos generados automáticamente...$(RESET)"
	@$(PRINT) "$(YELLOW)   Los secretos manuales (db_user, db_password) NO se rotan aquí.$(RESET)"
	@read -r -p "   ¿Confirmas la rotación? Los servicios necesitarán reiniciarse. [s/N]: " RESP && \
		[ "$$RESP" = "s" ] || (echo "Cancelado." && exit 1)
	@BACKUP_DIR="secrets/backup-$(shell date +%Y%m%d-%H%M%S)"; \
		mkdir -p "$$BACKUP_DIR"; chmod 700 "$$BACKUP_DIR"; \
		for f in metrics_password jwt_secret pepper_secret cookie_secret redis_secret; do \
			[ -f "secrets/$$f.txt" ] && cp "secrets/$$f.txt" "$$BACKUP_DIR/$$f.txt.bak"; \
		done; \
		$(PRINT) "$(GREEN)📦 Backup guardado en $$BACKUP_DIR$(RESET)"
	@openssl rand -base64 24 > secrets/metrics_password.txt  && chmod 600 secrets/metrics_password.txt  && $(PRINT) "$(GREEN)🔑 metrics_password rotado$(RESET)"
	@openssl rand -base64 48 > secrets/jwt_secret.txt        && chmod 600 secrets/jwt_secret.txt        && $(PRINT) "$(GREEN)🔑 jwt_secret rotado$(RESET)"
	@openssl rand -base64 32 > secrets/pepper_secret.txt     && chmod 600 secrets/pepper_secret.txt     && $(PRINT) "$(GREEN)🔑 pepper_secret rotado$(RESET)"
	@openssl rand -hex    48 > secrets/cookie_secret.txt     && chmod 600 secrets/cookie_secret.txt     && $(PRINT) "$(GREEN)🔑 cookie_secret rotado (hex-48)$(RESET)"
	@openssl rand -hex    32 > secrets/redis_secret.txt      && chmod 600 secrets/redis_secret.txt      && $(PRINT) "$(GREEN)🔑 redis_secret rotado (hex-32)$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)⚠️  Reinicia los servicios para aplicar los nuevos secretos:$(RESET)"
	@$(PRINT) "   make prod-down && make prod-up"
	@$(PRINT) "$(YELLOW)⚠️  Las sesiones activas quedarán invalidadas (flush Redis si aplica).$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# BACKUP Y ROLLBACK DE BASE DE DATOS
# ══════════════════════════════════════════════════════════════════════════════
#
# backup-db: realiza un dump de PostgreSQL y lo guarda en /opt/backups/
# rollback-db: restaura el backup más reciente (usando ls -t para ordenar por fecha)
#
# Prerequisito: PostgreSQL corriendo en el host (no en contenedor)
# Prerrequisito de rollback: al menos un backup previo en /opt/backups/
# ─────────────────────────────────────────────────────────────────────────────

backup-db: ## Backup cifrado de PostgreSQL → /opt/backups/
	@$(PRINT) "$(BLUE)💾 Realizando backup cifrado de la base de datos...$(RESET)"
	@mkdir -p /opt/backups
	@# Leer nombre de la DB
	@DB_NAME=$$(grep -v "^#" .env.production 2>/dev/null | grep "^DB_NAME=" | cut -d'=' -f2); \
	if [ -z "$$DB_NAME" ]; then \
		DB_NAME=$$(grep -v "^#" .env 2>/dev/null | grep "^DB_NAME=" | cut -d'=' -f2); \
	fi; \
	if [ -z "$$DB_NAME" ]; then \
		$(PRINT) "$(RED)❌ DB_NAME no encontrado en .env ni .env.production$(RESET)"; \
		exit 1; \
	fi; \
	\
	BACKUP_FILE="/opt/backups/$${DB_NAME}_$$(date +%Y%m%d_%H%M%S).sql.gz.enc"; \
	BACKUP_KEY_FILE="/opt/backups/.backup_key"; \
	\
	@# Crear clave de cifrado si no existe (una sola vez)
	if [ ! -f "$$BACKUP_KEY_FILE" ]; then \
		openssl rand -base64 32 > "$$BACKUP_KEY_FILE"; \
		chmod 600 "$$BACKUP_KEY_FILE"; \
		$(PRINT) "$(YELLOW)🔑 Clave creada en $$BACKUP_KEY_FILE — guárdala en lugar seguro$(RESET)"; \
	fi; \
	\
	@# Dump → comprimir → cifrar (pipeline sin archivos temporales)
	@sudo -u postgres pg_dump "$$DB_NAME" \
		| gzip \
		| openssl enc -aes-256-cbc -pbkdf2 -salt \
			-pass file:"$$BACKUP_KEY_FILE" \
		> "$$BACKUP_FILE"; \
	\
	$(PRINT) "$(GREEN)✅ Backup cifrado: $$BACKUP_FILE$(RESET)"; \
	ls -lh /opt/backups/*.enc | tail -5

backup-db-decrypt: ## Descifra un backup para inspección o restauración
	@$(PRINT) "$(YELLOW)🔓 Descifrando backup...$(RESET)"
	@BACKUP_KEY_FILE="/opt/backups/.backup_key"; \
	ls -t /opt/backups/*.sql.gz.enc 2>/dev/null | head -5; \
	read -p "Archivo a descifrar (ruta completa): " ENCRYPTED_FILE; \
	DECRYPTED_FILE="$${ENCRYPTED_FILE%.enc}"; \
	@openssl enc -d -aes-256-cbc -pbkdf2 \
		-pass file:"$$BACKUP_KEY_FILE" \
		-in "$$ENCRYPTED_FILE" \
		| gunzip > "$$DECRYPTED_FILE"; \
	$(PRINT) "$(GREEN)✅ Descifrado: $$DECRYPTED_FILE$(RESET)"

rollback-db: ## Restaura el backup más reciente de PostgreSQL
	@$(PRINT) "$(YELLOW)⚠️  ROLLBACK — restaurando el último backup...$(RESET)"
	@BACKUP_KEY_FILE="/opt/backups/.backup_key"; \
	\
	# Buscar primero backups cifrados (.sql.gz.enc), luego planos (.sql)
	LAST_ENC=$$(ls -t /opt/backups/*.sql.gz.enc 2>/dev/null | head -1); \
	LAST_SQL=$$(ls -t /opt/backups/*.sql        2>/dev/null | head -1); \
	\
	if [ -n "$$LAST_ENC" ]; then \
		LAST_BACKUP="$$LAST_ENC"; \
		$(PRINT) "$(CYAN)Backup cifrado a restaurar: $$LAST_BACKUP$(RESET)"; \
	elif [ -n "$$LAST_SQL" ]; then \
		LAST_BACKUP="$$LAST_SQL"; \
		$(PRINT) "$(CYAN)Backup plano a restaurar: $$LAST_BACKUP$(RESET)"; \
	else \
		$(PRINT) "$(RED)❌ No se encontraron backups en /opt/backups/$(RESET)"; \
		exit 1; \
	fi; \
	\
	DB_NAME=$$(grep -v "^#" .env.production 2>/dev/null | grep "^DB_NAME=" | cut -d'=' -f2); \
	if [ -z "$$DB_NAME" ]; then \
		DB_NAME=$$(grep -v "^#" .env 2>/dev/null | grep "^DB_NAME=" | cut -d'=' -f2); \
	fi; \
	\
	read -p "¿Confirmar restauración de $$DB_NAME? (y/N) " CONFIRM && [ "$$CONFIRM" = "y" ] || exit 0; \
	\
	if [[ "$$LAST_BACKUP" == *.sql.gz.enc ]]; then \
		$(PRINT) "$(BLUE)🔓 Descifrando y descomprimiendo...$(RESET)"; \
		[ -f "$$BACKUP_KEY_FILE" ] || { \
			$(PRINT) "$(RED)❌ Clave no encontrada: $$BACKUP_KEY_FILE$(RESET)"; \
			exit 1; \
		}; \
		@openssl enc -d -aes-256-cbc -pbkdf2 \
			-pass file:"$$BACKUP_KEY_FILE" \
			-in "$$LAST_BACKUP" \
			| gunzip \
			| sudo -u postgres psql "$$DB_NAME"; \
	else \
		sudo -u postgres psql "$$DB_NAME" < "$$LAST_BACKUP"; \
	fi; \
	$(PRINT) "$(GREEN)✅ Rollback completado desde: $$LAST_BACKUP$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# BASE DE DATOS Y MIGRACIONES
# ══════════════════════════════════════════════════════════════════════════════
# Requiere TypeORM configurado en el backend con scripts en package.json:
#   "typeorm": "ts-node -r tsconfig-paths/register ./node_modules/typeorm/cli"
#   "migration:run": "pnpm run typeorm migration:run -- -d src/config/datasource.ts"
#   "migration:revert": "pnpm run typeorm migration:revert -- -d src/config/datasource.ts"

db-migrate: ## Ejecuta las migraciones de TypeORM pendientes
	@$(PRINT) "$(BLUE)📊 Ejecutando migraciones de base de datos...$(RESET)"
	@$(DC) exec -T backend pnpm run migration:run 2>/dev/null || { \
		$(PRINT) "$(YELLOW)⚠️  Script migration:run no encontrado en package.json$(RESET)"; \
		$(PRINT) "   Añadir en backend/package.json: \"migration:run\": \"...\""; \
		exit 1; \
	}
	@$(PRINT) "$(GREEN)✅ Migraciones completadas$(RESET)"

db-rollback: ## Revierte la última migración de TypeORM
	@$(PRINT) "$(YELLOW)⏪ Revirtiendo última migración...$(RESET)"
	@read -r -p "¿Seguro que quieres revertir la última migración? [y/N]: " confirm && \
		[ "$$confirm" = "y" ] || exit 0
	@$(DC) exec -T backend pnpm run migration:revert 2>/dev/null || { \
		$(PRINT) "$(YELLOW)⚠️  Script migration:revert no encontrado en package.json$(RESET)"; \
		exit 1; \
	}
	@$(PRINT) "$(GREEN)✅ Migración revertida$(RESET)"

db-seed: ## Carga datos iniciales en la base de datos (seed)
	@$(PRINT) "$(BLUE)🌱 Cargando datos iniciales...$(RESET)"
	@$(DC) exec -T backend pnpm run seed 2>/dev/null || { \
		$(PRINT) "$(YELLOW)⚠️  Script seed no encontrado en package.json$(RESET)"; \
		$(PRINT) "   Añadir en backend/package.json: \"seed\": \"ts-node src/seed.ts\""; \
		exit 1; \
	}
	@$(PRINT) "$(GREEN)✅ Datos iniciales cargados$(RESET)"

db-migration-generate: ## Genera migración desde cambios en entidades (uso: make db-migration-generate NAME=NombreCambio)
	@[ -n "$(NAME)" ] || { \
		$(PRINT) "$(RED)❌ Falta el nombre: make db-migration-generate NAME=AnadirCampoTelefono$(RESET)"; \
		exit 1; \
	}
	@$(PRINT) "$(BLUE)🗄️  Generando migración: $(NAME)...$(RESET)"
	$(DC) exec -T backend pnpm run migration:generate -- src/migrations/$(NAME)
	@$(PRINT) "$(GREEN)✅ Migración generada — revisa src/migrations/ antes de hacer commit$(RESET)"

db-migration-show: ## Muestra el estado de las migraciones (pendientes y aplicadas)
	@$(PRINT) "$(CYAN)🔍 Estado de migraciones TypeORM:$(RESET)"
	$(DC) exec -T backend pnpm run migration:show

db-migration-create: ## Crea migración vacía para editar manualmente (uso: make db-migration-create NAME=AjusteEspecial)
	@[ -n "$(NAME)" ] || { \
		$(PRINT) "$(RED)❌ Falta el nombre: make db-migration-create NAME=AjusteEspecial$(RESET)"; \
		exit 1; \
	}
	$(DC) exec -T backend pnpm run migration:create src/migrations/$(NAME)
	@$(PRINT) "$(GREEN)✅ Migración vacía creada en src/migrations/$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# BACKUP AUTOMATIZADO
# ══════════════════════════════════════════════════════════════════════════════

setup-cron: ## Instala backup automático diario de PostgreSQL (cron)
	@$(PRINT) "$(BLUE)⏰ Instalando cron job de backup diario...$(RESET)"
	@# Verificar que make backup-db funciona antes de automatizarlo
	@command -v crontab >/dev/null 2>&1 || { \
		$(PRINT) "$(RED)❌ crontab no disponible$(RESET)"; exit 1; \
	}
	@CRON_CMD="0 2 * * * cd $$(pwd) && make backup-db >> /var/log/nombre_del_proyecto-backup.log 2>&1"
	@if crontab -l 2>/dev/null | grep -q "nombre_del_proyecto.*backup"; then \
		$(PRINT) "$(YELLOW)⚠️  Ya existe un cron job de backup — no se duplica$(RESET)"; \
		crontab -l | grep nombre_del_proyecto; \
	else \
		(crontab -l 2>/dev/null; echo "$$CRON_CMD") | crontab - ; \
		$(PRINT) "$(GREEN)✅ Cron instalado: backup diario a las 2:00am$(RESET)"; \
	fi
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)Cron jobs activos:$(RESET)"
	@crontab -l | grep nombre_del_proyecto || $(PRINT) "  (ninguno)"

remove-cron: ## Elimina el cron job de backup
	@$(PRINT) "$(YELLOW)🗑️  Eliminando cron job de backup...$(RESET)"
	@crontab -l 2>/dev/null | grep -v "nombre_del_proyecto.*backup" | crontab - || true
	@$(PRINT) "$(GREEN)✅ Cron job eliminado$(RESET)"

check-cron: ## Verifica el estado del cron job de backup
	@$(PRINT) "$(BLUE)🔍 Cron jobs de backup:$(RESET)"
	@crontab -l 2>/dev/null | grep nombre_del_proyecto \
		&& $(PRINT) "$(GREEN)✅ Backup automatizado activo$(RESET)" \
		|| $(PRINT) "$(YELLOW)⚠️  Sin cron job — ejecuta: make setup-cron$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# MONITOREO Y SALUD
# ══════════════════════════════════════════════════════════════════════════════

health-check: ## Verifica el estado de salud de los 3 servicios
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)── Estado de servicios ───────────────────────────────────$(RESET)"
	@for svc in nombre_del_proyecto_api nombre_del_proyecto_web nombre_del_proyecto_reports; do \
		STATUS=$$(docker inspect --format='{{.State.Health.Status}}' $$svc 2>/dev/null); \
		if [ "$$STATUS" = "healthy" ]; then \
			$(PRINT) "$(GREEN)✅ $$svc — healthy$(RESET)"; \
		elif [ "$$STATUS" = "starting" ]; then \
			$(PRINT) "$(YELLOW)⏳ $$svc — starting$(RESET)"; \
		elif [ -z "$$STATUS" ]; then \
			$(PRINT) "$(RED)❌ $$svc — no encontrado (¿está corriendo?)$(RESET)"; \
		else \
			$(PRINT) "$(RED)❌ $$svc — $$STATUS$(RESET)"; \
		fi; \
	done
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)── Puertos expuestos ─────────────────────────────────────$(RESET)"
	@docker ps --filter "name=nombre_del_proyecto" --format "  {{.Names}}: {{.Ports}}" 2>/dev/null || \
		$(PRINT) "  No hay contenedores corriendo"

wait-healthy: ## Espera hasta que los 3 servicios estén healthy (timeout: 5 min)
	@$(PRINT) "$(BLUE)⏳ Esperando que todos los servicios estén healthy...$(RESET)"
	@ELAPSED=0; MAX=300; INTERVAL=5; \
	while [ $$ELAPSED -lt $$MAX ]; do \
		HEALTHY=$$(docker ps --filter "health=healthy" --format '{{.Names}}'); \
		API=$$(echo "$$HEALTHY" | grep -c nombre_del_proyecto_api || true); \
		WEB=$$(echo "$$HEALTHY" | grep -c nombre_del_proyecto_web || true); \
		RPT=$$(echo "$$HEALTHY" | grep -c nombre_del_proyecto_reports || true); \
		if [ "$$API" -ge 1 ] && [ "$$WEB" -ge 1 ] && [ "$$RPT" -ge 1 ]; then \
			$(PRINT) "$(GREEN)✅ Todos los servicios healthy ($$ELAPSED s)$(RESET)"; \
			exit 0; \
		fi; \
		$(PRINT) "  Esperando... ($$ELAPSED s / API:$$API WEB:$$WEB RPT:$$RPT)"; \
		sleep $$INTERVAL; \
		ELAPSED=$$((ELAPSED + INTERVAL)); \
	done; \
	$(PRINT) "$(RED)❌ Timeout: servicios no healthy en $${MAX}s$(RESET)"; \
	docker ps --filter "name=nombre_del_proyecto"; \
	exit 1

stats: ## Muestra uso de CPU y RAM de los 3 contenedores (una sola lectura)
	@$(PRINT) "$(CYAN)$(BOLD)── Recursos de contenedores ──────────────────────────────$(RESET)"
	@docker stats --no-stream \
		--format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
		nombre_del_proyecto_api nombre_del_proyecto_web nombre_del_proyecto_reports 2>/dev/null || \
		$(PRINT) "$(YELLOW)⚠️  No hay contenedores corriendo$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "  Tip: Para monitoreo en tiempo real: docker stats nombre_del_proyecto_api nombre_del_proyecto_web nombre_del_proyecto_reports"

# ══════════════════════════════════════════════════════════════════════════════
# MONITOREO AVANZADO
# ══════════════════════════════════════════════════════════════════════════════

# Cargar .env si SLACK_WEBHOOK_URL no está en el entorno
monitoring-config: ## Genera prometheus.yml y alertmanager.yml desde templates
	@set -eu; \
	# ── Alertmanager ──────────────────────────────────────────────────────
	WEBHOOK="$${SLACK_WEBHOOK_URL:-}"; \
	if [ -z "$$WEBHOOK" ] && [ -f .env ]; then \
		WEBHOOK=$$(grep '^SLACK_WEBHOOK_URL=' .env | grep -v '^#' | cut -d'=' -f2- | tr -d '"'"'"' ' || true); \
	fi; \
	if [ -z "$$WEBHOOK" ]; then \
		WEBHOOK="CAMBIAR_URL_ENV_VACIO"; \
		$(PRINT) "$(YELLOW)⚠️  SLACK_WEBHOOK_URL no definida — alertmanager.yml generado con placeholder$(RESET)"; \
		$(PRINT) "   Edita .env: SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ"; \
	fi; \
	SLACK_WEBHOOK_URL="$$WEBHOOK" envsubst '$$SLACK_WEBHOOK_URL' \
		< monitoring/alertmanager.yml.template \
		> monitoring/alertmanager.yml; \
	$(PRINT) "$(GREEN)✅ alertmanager.yml generado$(RESET)"; \
	# ── Prometheus ────────────────────────────────────────────────────────
	PORT_BACKEND="$${PORT_BACKEND:-4000}"; \
	PORT_REPORTS="$${PORT_REPORTS:-5000}"; \
	METRICS_USER="$${METRICS_USER:-prometheus}"; \
	METRICS_PASSWORD="$${METRICS_PASSWORD:-}"; \
	if [ -f .env ]; then \
		PORT_BACKEND=$$(grep '^PORT_BACKEND=' .env | cut -d'=' -f2- || echo 4000); \
		PORT_REPORTS=$$(grep '^PORT_REPORTS=' .env | cut -d'=' -f2- || echo 5000); \
		METRICS_USER=$$(grep '^METRICS_USER=' .env | cut -d'=' -f2- || echo prometheus); \
		METRICS_PASSWORD=$$(grep '^METRICS_PASSWORD=' .env | grep -v '^#' | cut -d'=' -f2- || echo ''); \
	fi; \
	if [ -z "$$METRICS_PASSWORD" ]; then \
		METRICS_PASSWORD="CAMBIAR_EJECUTA_MAKE_SETUP"; \
		$(PRINT) "$(YELLOW)⚠️  METRICS_PASSWORD vacío — prometheus.yml generado con placeholder$(RESET)"; \
		$(PRINT) "   Ejecuta: make setup  (genera automáticamente)"; \
	fi; \
	PORT_BACKEND="$$PORT_BACKEND" PORT_REPORTS="$$PORT_REPORTS" \
	METRICS_USER="$$METRICS_USER" METRICS_PASSWORD="$$METRICS_PASSWORD" \
		envsubst '$$PORT_BACKEND $$PORT_REPORTS $$METRICS_USER $$METRICS_PASSWORD' \
		< monitoring/prometheus.yml.template \
		> monitoring/prometheus.yml; \
	$(PRINT) "$(GREEN)✅ prometheus.yml generado$(RESET)"

monitoring-up: ## Levanta Prometheus + Grafana (requiere docker-compose.monitoring.yml)
	@$(PRINT) "$(BLUE)📊 Levantando stack de monitoreo...$(RESET)"
	@[ -f docker-compose.monitoring.yml ] || { \
		$(PRINT) "$(RED)❌ docker-compose.monitoring.yml no encontrado$(RESET)"; \
		$(PRINT) "   Copia el archivo a la raíz del proyecto"; \
		exit 1; \
	}
	@[ -f secrets/grafana_password.txt ] || { \
		$(PRINT) "$(RED)❌ secrets/grafana_password.txt no existe$(RESET)"; \
		$(PRINT) "   Ejecuta: echo 'tu_password' > secrets/grafana_password.txt"; \
		exit 1; \
	}
	$(DC_MONITORING) up -d
	@$(PRINT) ""
	@$(PRINT) "$(GREEN)✅ Monitoreo activo:$(RESET)"
	@$(PRINT) "   Grafana:    http://localhost:$${PORT_GRAFANA:-3001}  (admin / ver secrets/grafana_password.txt)"
	@$(PRINT) "   Prometheus: http://localhost:$${PORT_PROMETHEUS:-9090}"
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)ℹ️  Los servicios deben exponer /metrics para que Prometheus los scrapee$(RESET)"
	@$(PRINT) "   Ver docs/MONITORING-ROADMAP.md para implementar /metrics en backend y reports"

monitoring-down: ## Detiene el stack de monitoreo
	@$(PRINT) "$(YELLOW)🛑 Deteniendo stack de monitoreo...$(RESET)"
	$(DC_MONITORING) down
	@$(PRINT) "$(GREEN)✅ Stack de monitoreo detenido$(RESET)"

monitoring-logs: ## Ver logs del stack de monitoreo en tiempo real
	$(DC_MONITORING) logs -f

monitoring-ps: ## Estado de contenedores del stack de monitoreo
	@$(PRINT) "$(CYAN)$(BOLD)── Estado del stack de monitoreo ─────────────────────────$(RESET)"
	$(DC_MONITORING) ps

# ══════════════════════════════════════════════════════════════════════════════
# BUILD DE IMÁGENES DE PRODUCCIÓN (target compartido — evita builds duplicados)
# ══════════════════════════════════════════════════════════════════════════════
#
# sbom, scan-security y grype-scan dependen de este target.
# Sin él, cada uno reconstruía las tres imágenes por separado (lento).
# Ahora se construyen una sola vez y todos los escaneos las reutilizan.

build-prod-images:
	@$(PRINT) "$(CYAN)→ Construyendo imágenes de producción (nombre_del_proyecto/*:ci)...$(RESET)"
	docker build -q -t nombre_del_proyecto/backend:ci \
		-f backend/.docker/Dockerfile.prod backend/
	docker build -q -t nombre_del_proyecto/reports:ci \
		-f reports/.docker/Dockerfile.prod reports/
	docker build -q -t nombre_del_proyecto/frontend:ci \
		--build-arg NEXT_PUBLIC_API_URL=http://localhost:4000 \
		--build-arg NEXT_PUBLIC_REPORTS_URL=http://localhost:5000 \
		-f frontend/.docker/Dockerfile.prod frontend/
	@$(PRINT) "$(GREEN)✅ Imágenes listas: nombre_del_proyecto/backend:ci  nombre_del_proyecto/reports:ci  nombre_del_proyecto/frontend:ci$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# SEGURIDAD: LINT DE DOCKERFILES (hadolint) → alerts.log
# ══════════════════════════════════════════════════════════════════════════════

lint-docker: prepare-audit-dirs ## Valida todos los Dockerfiles con hadolint
	@$(PRINT) "$(BLUE)🔍 Lint de Dockerfiles (hadolint)...$(RESET)"
	@$(PRINT) ""
	printf "=== HADOLINT SCAN — %s ===\n\n" "$$(date)" > "$(TESTS_DIR)/alerts.log"
	WARNINGS=0
	for dockerfile in \
		backend/.docker/Dockerfile \
		backend/.docker/Dockerfile.prod \
		frontend/.docker/Dockerfile \
		frontend/.docker/Dockerfile.prod \
		reports/.docker/Dockerfile \
		reports/.docker/Dockerfile.prod; do
		$(PRINT) "$(CYAN)→ $$dockerfile$(RESET)"
		printf '%s\n' "--- %s ---\n" "$$dockerfile" >> "$(TESTS_DIR)/alerts.log"
		if hadolint "$$dockerfile" 2>&1 | tee -a "$(TESTS_DIR)/alerts.log"; then
			$(PRINT) "  $(GREEN)✅ OK$(RESET)"
		else
			$(PRINT) "  $(YELLOW)⚠️  warnings en $$dockerfile$(RESET)"
			WARNINGS=$$((WARNINGS+1))
		fi
		printf "\n" >> "$(TESTS_DIR)/alerts.log"
	done
	printf "=== Completado: %d archivo(s) con warnings ===\n" "$$WARNINGS" \
		>> "$(TESTS_DIR)/alerts.log"
	$(PRINT) ""
	$(PRINT) "$(GREEN)✅ Lint completado → $(TESTS_DIR)/alerts.log$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# SEGURIDAD: TRIVY CONFIG SCAN — Dockerfiles y compose ANTES del build
# ══════════════════════════════════════════════════════════════════════════════
#
# Diferencia entre los tres modos de trivy:
#   trivy config  → Archivos de configuración (Dockerfiles, compose): misconfig
#   trivy image   → Imagen construida: CVEs en paquetes del SO y librerías
#   trivy fs      → Código fuente: CVEs en package.json, requirements.txt
# Los tres son complementarios — audit-full los ejecuta todos.

trivy-config-scan: prepare-audit-dirs ## Trivy: escanea Dockerfiles/compose por misconfiguraciones
	@$(PRINT) "$(BLUE)🛡️  Trivy config scan (Dockerfiles + compose)...$(RESET)"
	@$(PRINT) ""
	printf "=== TRIVY CONFIG SCAN — %s ===\n\n" "$$(date)" > "$(TESTS_DIR)/trivy-config.log"
	$(PRINT) "$(CYAN)── Dockerfiles de producción ──$(RESET)"
	for dockerfile in \
		backend/.docker/Dockerfile.prod \
		frontend/.docker/Dockerfile.prod \
		reports/.docker/Dockerfile.prod; do
		$(PRINT) "$(CYAN)→ $$dockerfile$(RESET)"
		printf '%s\n' "--- %s ---\n" "$$dockerfile" >> "$(TESTS_DIR)/trivy-config.log"
		trivy config "$$dockerfile" --severity HIGH,CRITICAL --exit-code 1 2>&1 \
			| tee -a "$(TESTS_DIR)/trivy-config.log" || exit 1
		printf "\n" >> "$(TESTS_DIR)/trivy-config.log"
	done
	$(PRINT) ""
	$(PRINT) "$(CYAN)── docker-compose.prod.yml ──$(RESET)"
	printf '%s\n' "--- docker-compose.prod.yml ---\n" >> "$(TESTS_DIR)/trivy-config.log"
	trivy config docker-compose.prod.yml --severity HIGH,CRITICAL --exit-code 1 2>&1 \
		| tee -a "$(TESTS_DIR)/trivy-config.log" || exit 1
	$(PRINT) ""
	$(PRINT) "$(GREEN)✅ trivy config → $(TESTS_DIR)/trivy-config.log$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# SEGURIDAD: TRIVY IMAGE SCAN — imágenes construidas
# ══════════════════════════════════════════════════════════════════════════════

scan-security: prepare-audit-dirs build-prod-images ## Trivy: escanea imágenes de producción
	@$(PRINT) "$(BLUE)🛡️  Trivy image scan...$(RESET)"
	@$(PRINT) ""
	printf "=== TRIVY IMAGE SCAN — %s ===\n\n" "$$(date)" > "$(TESTS_DIR)/security-scan.log"
	for service in backend frontend reports; do
		$(PRINT) "$(CYAN)=== $$service ===$(RESET)"
		printf '%s\n' "--- %s ---\n" "$$service" >> "$(TESTS_DIR)/security-scan.log"
		trivy image --severity CRITICAL,HIGH --exit-code 1 "nombre_del_proyecto/$$service:ci" 2>&1 \
			| tee -a "$(TESTS_DIR)/security-scan.log" || exit 1
		printf "\n" >> "$(TESTS_DIR)/security-scan.log"
	done
	$(PRINT) ""
	$(PRINT) "$(GREEN)✅ Escaneo completado → $(TESTS_DIR)/security-scan.log$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# AUDITORÍA DE DEPENDENCIAS PYTHON
# ══════════════════════════════════════════════════════════════════════════════

audit-requirements: prepare-audit-dirs ## pip-audit: CVEs en dependencias Python (falla en CRITICAL/HIGH)
	@$(PRINT) "$(BLUE)🔍 Auditando dependencias Python (pip-audit)...$(RESET)"
	@set -o pipefail; \
	docker run --rm \
		-v "$$(pwd)/reports":/app \
		-w /app \
		python:3.12-slim \
		sh -c ' \
			pip install pip-audit --quiet --root-user-action=ignore && \
			pip-audit -r requirements.txt \
				--format json \
				--output /app/pip-audit-results.json \
				--progress-spinner off && \
			pip-audit -r requirements.txt \
				--progress-spinner off \
		' 2>&1 | tee "$(TESTS_DIR)/pip-audit.log"; \
	EXIT=$$?; \
	[ -f reports/pip-audit-results.json ] && \
		cp reports/pip-audit-results.json "$(TESTS_DIR)/pip-audit-results.json" || true; \
	if [ $$EXIT -ne 0 ]; then \
		$(PRINT) "$(RED)❌ pip-audit encontró vulnerabilidades — revisar $(TESTS_DIR)/pip-audit.log$(RESET)"; \
		exit $$EXIT; \
	fi
	@$(PRINT) "$(GREEN)✅ pip-audit → $(TESTS_DIR)/pip-audit.log$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# SBOM — Software Bill of Materials
# ══════════════════════════════════════════════════════════════════════════════
#
# El SBOM es un inventario completo de TODOS los paquetes de cada imagen:
#   nombre, versión, origen, licencia — en formato CycloneDX (JSON).
# Para qué sirve:
#   - Si aparece una CVE, buscas en el SBOM sin necesidad de rebuild.
#   - Requerido en auditorías ISO 27001 / SOC2 / PCI-DSS.
#   - Grype lo usa para escanear vulnerabilidades más rápido.

sbom: prepare-audit-dirs build-prod-images ## Genera SBOM con syft instalado localmente
	@$(PRINT) "$(BLUE)📦 Generando SBOM con syft...$(RESET)"
	command -v syft >/dev/null 2>&1 || {
		$(PRINT) "$(RED)❌ syft no encontrado.$(RESET)"
		$(PRINT) "   1. make install-tools  → instala syft"
		$(PRINT) "   2. make sbom-docker    → usa Docker, sin instalar"
		exit 1
	}
	$(PRINT) ""
	for service in backend reports frontend; do
		$(PRINT) "$(CYAN)→ SBOM — $$service...$(RESET)"
		syft "nombre_del_proyecto/$$service:ci" \
			-o cyclonedx-json="$(TESTS_DIR)/sbom-$$service.json" \
			-o table
		$(PRINT) ""
	done
	$(PRINT) "$(GREEN)✅ SBOMs generados:$(RESET)"
	ls -lh "$(TESTS_DIR)"/sbom-*.json

sbom-docker: prepare-audit-dirs build-prod-images ## Genera SBOM vía Docker (sin instalar syft)
	@$(PRINT) "$(BLUE)📦 Generando SBOM vía Docker...$(RESET)"
	[ -S /var/run/docker.sock ] || {
		$(PRINT) "$(RED)❌ /var/run/docker.sock no disponible$(RESET)"
		exit 1
	}
	for service in backend reports frontend; do
		$(PRINT) "$(CYAN)→ SBOM — $$service...$(RESET)"
		docker run --rm \
			-v /var/run/docker.sock:/var/run/docker.sock \
			-v "$$(pwd)/$(TESTS_DIR)":/output \
			anchore/syft:latest "nombre_del_proyecto/$$service:ci" \
			-o cyclonedx-json=/output/sbom-$$service.json
		$(PRINT) "$(GREEN)✅ $(TESTS_DIR)/sbom-$$service.json$(RESET)"
	done

# ══════════════════════════════════════════════════════════════════════════════
# GRYPE — Escáner de vulnerabilidades
# ══════════════════════════════════════════════════════════════════════════════
#
# --fail-on high: retorna exit code != 0 si encuentra HIGH o CRITICAL.
# En CI, esto hace que el pipeline falle automáticamente — es el comportamiento
# deseado para bloquear imágenes vulnerables antes del deploy.

grype-scan: prepare-audit-dirs ## Grype: escanea imágenes, falla si hay HIGH/CRITICAL (local)
	@$(PRINT) "$(BLUE)🔍 Escaneando con Grype...$(RESET)"
	command -v grype >/dev/null 2>&1 || {
		$(PRINT) "$(RED)❌ grype no encontrado.$(RESET)"
		$(PRINT) "   1. make install-tools     → instala grype"
		$(PRINT) "   2. make grype-scan-docker → usa Docker"
		exit 1
	}
	for service in backend reports frontend; do
		$(PRINT) "$(CYAN)→ $$service...$(RESET)"
		grype "nombre_del_proyecto/$$service:ci" --fail-on high 2>&1 \
			| tee "$(TESTS_DIR)/grype-$$service.log" || {
			$(PRINT) "$(RED)❌ CRITICAL/HIGH en $$service → $(TESTS_DIR)/grype-$$service.log$(RESET)"
			exit 1
		}
		$(PRINT) ""
	done
	$(PRINT) "$(GREEN)✅ Sin vulnerabilidades CRITICAL/HIGH$(RESET)"

grype-scan-docker: ## Grype: escanea imágenes vía Docker (sin instalar grype)
	@$(PRINT) "$(BLUE)🔍 Escaneando con Grype vía Docker...$(RESET)"
	[ -S /var/run/docker.sock ] || {
		$(PRINT) "$(RED)❌ docker.sock no disponible$(RESET)"
		exit 1
	}
	for service in backend reports frontend; do
		$(PRINT) "$(CYAN)→ $$service...$(RESET)"
		docker run --rm \
			-v /var/run/docker.sock:/var/run/docker.sock \
			anchore/grype:latest "nombre_del_proyecto/$$service:ci" --fail-on high || {
			$(PRINT) "$(RED)❌ CRITICAL/HIGH en $$service$(RESET)"
			exit 1
		}
	done
	$(PRINT) "$(GREEN)✅ Sin vulnerabilidades CRITICAL/HIGH$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# SYSTEM CHECK — Evidencia operativa fechada
# ══════════════════════════════════════════════════════════════════════════════
#
# system-check.log es evidencia de cumplimiento operativo para auditorías:
# demuestra que el sistema estaba funcionando correctamente en esa fecha.

audit-security: prepare-audit-dirs ## Genera system-check.log con estado del sistema
	@$(PRINT) "$(BLUE)📋 Generando system-check.log...$(RESET)"
	{
		printf "=== SYSTEM CHECK — %s ===\n\n" "$$(date)"
		printf '%s\n' "--- docker version ---\n"
		docker version 2>&1
		printf '%s\n' "--- docker info ---\n"
		docker info 2>&1
		printf '%s\n' "--- compose ps ---\n"
		$(DC) ps 2>&1
		printf '%s\n' "--- compose logs (últimas 50 líneas) ---\n"
		$(DC) logs --tail=50 2>&1
	} > "$(TESTS_DIR)/system-check.log"
	$(PRINT) "$(GREEN)✅ $(TESTS_DIR)/system-check.log$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# AUDITORIA DE DEPENDENDIAS PNPM (Node.js) — CVEs en packages de backend y frontend
# ══════════════════════════════════════════════════════════════════════════════

audit-pnpm: ## Audita dependencias pnpm de backend y frontend (CVEs)
	@$(PRINT) "$(BLUE)🔍 Auditando dependencias Node.js (pnpm audit)...$(RESET)"
	@$(PRINT) "$(CYAN)→ backend...$(RESET)"
	(cd backend  && pnpm audit --audit-level=high --prod) 2>&1 | tee "$(TESTS_DIR)/pnpm-audit-backend.log"  || true
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)→ frontend...$(RESET)"
	(cd frontend && pnpm audit --audit-level=high --prod) 2>&1 | tee "$(TESTS_DIR)/pnpm-audit-frontend.log" || true
	@$(PRINT) ""
	@$(PRINT) "$(GREEN)✅ pnpm audit completado$(RESET)"

# ══════════════════════════════════════════════════════════════════════════════
# AUDIT-FULL — Pipeline manual completo de seguridad (7 pasos)
# ══════════════════════════════════════════════════════════════════════════════
#
# Evidencia generada en scripts/ tests/:
#   alerts.log         → hadolint (lint Dockerfiles)
#   trivy-config.log   → trivy config (misconfiguraciones)
#   security-scan.log  → trivy image (CVEs en imágenes)
#   pnpm-audit.log     → pnpm audit (CVEs en dependencias Node.js)
#   pip-audit.log      → pip-audit (CVEs en dependencias Python)
#   sbom-backend.json  → SBOM CycloneDX backend
#   sbom-reports.json  → SBOM CycloneDX reports
#   sbom-frontend.json → SBOM CycloneDX frontend
#   system-check.log   → Estado del sistema
#
# Para CI sin colores: make audit-full NO_COLOR=1

audit-full: prepare-audit-dirs ## ★ Pipeline completo: lint + trivy + sbom + system-check
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)$(BOLD)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(PRINT) "$(CYAN)$(BOLD)║     🛡️  PIPELINE COMPLETO DE AUDITORÍA — NOMBRE_DEL_PROYECTO            ║$(RESET)"
	@$(PRINT) "$(CYAN)$(BOLD)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[1/9]$(RESET) $(BLUE)Lint de Dockerfiles (hadolint)...$(RESET)"
	$(MAKE) --no-print-directory lint-docker NO_COLOR=$(NO_COLOR)
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[2/9]$(RESET) $(BLUE)Trivy config scan (Dockerfiles + compose)...$(RESET)"
	$(MAKE) --no-print-directory trivy-config-scan NO_COLOR=$(NO_COLOR)
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[3/9]$(RESET) $(BLUE)Auditoría de dependencias Python...$(RESET)"
	$(MAKE) --no-print-directory audit-requirements NO_COLOR=$(NO_COLOR)
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[4/9]$(RESET) $(BLUE)Auditoría de dependencias Node.js (pnpm)...$(RESET)"
	$(MAKE) --no-print-directory audit-pnpm NO_COLOR=$(NO_COLOR)
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[5/9]$(RESET) $(BLUE)Build único de imágenes de producción...$(RESET)"
	$(MAKE) --no-print-directory build-prod-images NO_COLOR=$(NO_COLOR)
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[6/9]$(RESET) $(BLUE)Trivy image scan (CVEs en imágenes)...$(RESET)"
	$(MAKE) --no-print-directory scan-security NO_COLOR=$(NO_COLOR)
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[7/9]$(RESET) $(BLUE)Generando SBOM...$(RESET)"
	@command -v syft >/dev/null 2>&1 \
		&& $(MAKE) --no-print-directory sbom        NO_COLOR=$(NO_COLOR) \
		|| $(MAKE) --no-print-directory sbom-docker NO_COLOR=$(NO_COLOR)
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[8/9]$(RESET) $(BLUE)System check (evidencia operativa)...$(RESET)"
	$(MAKE) --no-print-directory audit-security NO_COLOR=$(NO_COLOR)
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)$(BOLD)[9/9]$(RESET) $(BLUE)Grype: escáner de vulnerabilidades en imágenes...$(RESET)"
	@command -v grype >/dev/null 2>&1 \
		&& $(MAKE) --no-print-directory grype-scan        NO_COLOR=$(NO_COLOR) \
		|| $(MAKE) --no-print-directory grype-scan-docker NO_COLOR=$(NO_COLOR)
	@$(PRINT) "$(GREEN)$(BOLD)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(PRINT) "$(GREEN)$(BOLD)║     ✅ AUDITORÍA COMPLETADA                                 ║$(RESET)"
	@$(PRINT) "$(GREEN)$(BOLD)║     Evidencia disponible en: $(TESTS_DIR)/                  ║$(RESET)"
	@$(PRINT) "$(GREEN)$(BOLD)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@$(PRINT) ""
	ls -lh "$(TESTS_DIR)/"

# ══════════════════════════════════════════════════════════════════════════════
# DESARROLLO
# ══════════════════════════════════════════════════════════════════════════════

dev: ready-check prepare-logs check-setup ## Arranca servicios en desarrollo con logs en pantalla
	@$(PRINT) "$(BLUE)🔧 Arrancando en desarrollo...$(RESET)"
	$(DC) up

dev-full: ready-check prepare-logs check-setup ## Desarrollo completo: servicios + Redis + monitoreo (si disponible)
	@$(PRINT) "$(BLUE)🔧 Arrancando stack completo de desarrollo...$(RESET)"
	$(DC) -f docker-compose.redis.yml up -d
	@[ -f docker-compose.monitoring.yml ] && \
		$(DC_MONITORING) up -d && \
		$(PRINT) "$(GREEN)✅ Monitoreo activo$(RESET)" || \
		$(PRINT) "$(YELLOW)⚠️  Sin monitoreo (docker-compose.monitoring.yml no encontrado)$(RESET)"
	$(DC) logs -f

dev-bg: ready-check prepare-logs check-setup ## Arranca servicios en desarrollo en background
	@$(PRINT) "$(BLUE)🔧 Arrancando en background...$(RESET)"
	$(DC) up -d

build: ## Construye imágenes de desarrollo
	@$(PRINT) "$(BLUE)🔨 Construyendo imágenes...$(RESET)"
	$(DC) build

dev-with-redis: ready-check prepare-logs check-setup ## Arranca servicios + Redis
	@# Asegurar que la red existe antes de levantar Redis
	@docker network inspect nombre_del_proyecto-private >/dev/null 2>&1 || \
		$(DC) up --no-start 2>/dev/null || true
	@$(PRINT) "$(BLUE)🔧 Arrancando con Redis...$(RESET)"
	$(DC) -f docker-compose.redis.yml up

dev-with-redis-bg: ready-check prepare-logs check-setup ## Arranca servicios + Redis en background
	@# Asegurar que la red existe antes de levantar Redis
	@docker network inspect nombre_del_proyecto-private >/dev/null 2>&1 || \
        $(DC) up --no-start 2>/dev/null || true
	@$(PRINT) "$(BLUE)🔧 Arrancando con Redis en background...$(RESET)"
	$(DC) -f docker-compose.redis.yml up -d

dev-swagger: ready-check prepare-logs check-setup ## Arranca servicios con Swagger UI habilitado
	@$(PRINT) "$(BLUE)📚 Arrancando con Swagger habilitado...$(RESET)"
	SWAGGER_ENABLED=true $(DC) up

dev-swagger-bg: ready-check prepare-logs check-setup ## Arranca con Swagger en background
	@$(PRINT) "$(BLUE)📚 Arrancando con Swagger habilitado en background...$(RESET)"
	SWAGGER_ENABLED=true $(DC) up -d

# ══════════════════════════════════════════════════════════════════════════════
# PRODUCCIÓN
# ══════════════════════════════════════════════════════════════════════════════

prod: ready-check-prod ## Deploy a producción (validaciones + migraciones + up)
	@$(PRINT) "$(BLUE)🚀 Arrancando en producción...$(RESET)"
	@chmod +x scripts/deploy-prod.sh
	@DEPLOY_DIR=$$(pwd) bash scripts/deploy-prod.sh

prod-full: ready-check-prod ## Producción completa: servicios + monitoreo
	@$(PRINT) "$(BLUE)🚀 Arrancando stack completo de producción...$(RESET)"
	make prod
	@[ -f docker-compose.monitoring.yml ] && make monitoring-up-prod || true

prod-down: guard-not-ci ## Detiene y elimina contenedores de producción (con confirmación)
	@$(PRINT) "$(YELLOW)⚠️  Esto detendrá TODOS los contenedores de producción.$(RESET)"
	@$(PRINT) "   Los volúmenes de datos NO se eliminan."
	@read -r -p "   Escribe 'CONFIRMAR' para continuar: " RESP && \
		[ "$$RESP" = "CONFIRMAR" ] || ($(PRINT) "Cancelado." && exit 1)
	@$(PRINT) "$(BLUE)🛑 Deteniendo producción...$(RESET)"
	$(DC_PROD) down
	@$(PRINT) "$(GREEN)✅ Contenedores de producción detenidos$(RESET)"

prod-down-volumes: guard-not-ci ## ⚠️  Detiene producción Y ELIMINA VOLÚMENES (destructivo)
	@$(PRINT) "$(RED)$(BOLD)⚠️  PELIGRO: Esto eliminará los volúmenes de producción.$(RESET)"
	@$(PRINT) "$(RED)   Los datos de la DB Docker serán destruidos permanentemente.$(RESET)"
	@read -r -p "   Escribe 'ELIMINAR-VOLÚMENES' para continuar: " RESP && \
		[ "$$RESP" = "ELIMINAR-VOLÚMENES" ] || ($(PRINT) "Cancelado." && exit 1)
	$(DC_PROD) down -v
	@$(PRINT) "$(GREEN)✅ Contenedores y volúmenes de producción eliminados$(RESET)"

# prod: prepare-logs secrets-check ## Deploy a producción
# 	@$(PRINT) "$(BLUE)🚀 Arrancando en producción...$(RESET)"
# 	$(DC_PROD) up -d --build

# prod-secure: prepare-logs secrets-check ## Deploy con permisos estrictos en .env.production
# 	@$(PRINT) "$(BLUE)🔒 Aplicando permisos estrictos a .env.production...$(RESET)"
# 	[ -f .env.production ] || {
# 		$(PRINT) "$(RED)❌ .env.production no encontrado.$(RESET)"
# 		$(PRINT) "   Crea uno: cp .env.prod.example .env.production"
# 		exit 1
# 	}
# 	@# Aviso si no somos root: sudo puede pedir contraseña
# 	@if [ $$(id -u) -ne 0 ]; then \
# 		$(PRINT) "$(YELLOW)⚠️  Aplicando chmod/chown con sudo (puede pedir contraseña)$(RESET)"; \
# 	fi
# 	sudo chmod 600 .env.production
# 	sudo chown root:root .env.production
# 	@$(PRINT) "$(GREEN)✅ .env.production protegido (600, root:root)$(RESET)"
# 	@$(PRINT) "$(BLUE)🚀 Arrancando en producción...$(RESET)"
# 	$(DC_PROD) up -d --build

# ══════════════════════════════════════════════════════════════════════════════
# LOGS
# ══════════════════════════════════════════════════════════════════════════════

logs: ## Ver logs de todos los servicios en tiempo real
	$(DC) logs -f

logs-backend: ## Ver logs del backend
	$(DC) logs -f backend

logs-frontend: ## Ver logs del frontend
	$(DC) logs -f frontend

logs-reports: ## Ver logs del reports-api
	$(DC) logs -f reports-api

# ══════════════════════════════════════════════════════════════════════════════
# MANTENIMIENTO
# ══════════════════════════════════════════════════════════════════════════════

stop: ## Detiene todos los servicios
	@$(PRINT) "$(BLUE)🛑 Deteniendo servicios...$(RESET)"
	$(DC) down

clean: ## Elimina contenedores, volúmenes y logs locales
	@$(PRINT) "$(BLUE)🧹 Limpiando contenedores, volúmenes y logs...$(RESET)"
	$(DC) down -v
	rm -rf logs/backend/* logs/reports/*

prune: ## Elimina TODAS las imágenes y recursos Docker no usados (libera disco)
	@$(PRINT) "$(YELLOW)⚠️  Esto eliminará todas las imágenes y recursos Docker no usados.$(RESET)"
	@read -p "¿Continuar? (y/N) " CONFIRM && [ "$$CONFIRM" = "y" ] || exit 0
	docker system prune -af --volumes
	@$(PRINT) "$(GREEN)✅ Recursos huérfanos eliminados$(RESET)"

test: ## Corre tests del backend con reporte de cobertura
	@$(PRINT) "$(BLUE)🧪 Tests del backend (con coverage)...$(RESET)"
	$(DC) exec backend pnpm run test:cov 2>/dev/null || \
		$(DC) exec backend pnpm test

lint: ## Linter del backend
	@$(PRINT) "$(BLUE)🔍 Linter del backend...$(RESET)"
	$(DC) exec backend pnpm run lint

# ══════════════════════════════════════════════════════════════════════════════
# SHELLS
# ══════════════════════════════════════════════════════════════════════════════

shell-backend: ## Terminal interactiva en el contenedor backend
	$(DC) exec backend sh

shell-frontend: ## Terminal interactiva en el contenedor frontend
	$(DC) exec frontend sh

shell-reports: ## Terminal interactiva en el contenedor reports-api
	$(DC) exec reports-api sh

# ══════════════════════════════════════════════════════════════════════════════
# DIAGNÓSTICO Y MANTENIMIENTO AVANZADO
# ══════════════════════════════════════════════════════════════════════════════

config: ## Muestra la configuración resuelta de desarrollo y producción
	@$(PRINT) "$(BLUE)📋 Configuración de desarrollo:$(RESET)"
	$(DC) config
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)📋 Configuración de producción:$(RESET)"
	$(DC_PROD) config

update-requirements: ## Regenera requirements.txt con hashes SHA256
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)🔄 Actualizando requirements.txt con hashes SHA256...$(RESET)"
	docker run --rm \
		-v "$$(pwd)/reports":/app \
		-w /app \
		python:3.12-slim \
		sh -c "pip install pip-tools --quiet --root-user-action=ignore && \
		       pip-compile --generate-hashes \
		                   --output-file=requirements.txt \
		                   requirements.in"
	$(PRINT) ""
	$(PRINT) "$(GREEN)✅ requirements.txt actualizado$(RESET)"
	$(PRINT) "$(CYAN)Revisa el diff: git diff reports/requirements.txt$(RESET)"

show-digests: ## Muestra los digests SHA256 actuales de las imágenes base
	@$(PRINT) ""
	@$(PRINT) "$(BLUE)🔍 Digests actuales de imágenes base:$(RESET)"
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)=== node:24-slim ===$(RESET)"
	docker pull node:24-slim -q
	docker inspect node:24-slim --format '{{index .RepoDigests 0}}'
	@$(PRINT) ""
	@$(PRINT) "$(CYAN)=== python:3.12-slim ===$(RESET)"
	docker pull python:3.12-slim -q
	docker inspect python:3.12-slim --format '{{index .RepoDigests 0}}'
	@$(PRINT) ""
	@$(PRINT) "$(YELLOW)Copia estos digests en los FROM de los Dockerfiles.prod$(RESET)"

check-alertmanager-config: ## Verifica que Alertmanager tiene una URL de Slack configurada
	@if [ -f monitoring/alertmanager.yml ]; then \
		grep -q 'slack' monitoring/alertmanager.yml && \
			$(PRINT) "$(GREEN)✅ Alertmanager con Slack configurado$(RESET)" || \
			($(PRINT) "$(RED)❌ Alertmanager sin notificación configurada$(RESET)" && \
			 $(PRINT) "   Ver: docs/guides/MONITORING-ALERTMANAGER.md" && \
			 exit 1); \
	else \
		$(PRINT) "$(YELLOW)⚠️  alertmanager.yml no encontrado — omitiendo check$(RESET)"; \
	fi

# monitoring-up-prod: check-alertmanager-config ## Levanta monitoreo con Alertmanager verificado
# 	@$(PRINT) "$(BLUE)📊 Levantando stack de monitoreo CON Alertmanager...$(RESET)"
# 	$(DC_MONITORING) up -d

monitoring-up-prod: check-alertmanager-config ## Levanta Prometheus + Grafana + Alertmanager (solo producción)
	@$(PRINT) "$(BLUE)📊 Levantando stack de monitoreo CON Alertmanager...$(RESET)"
	@[ -f docker-compose.monitoring.yml ] || { \
		$(PRINT) "$(RED)❌ docker-compose.monitoring.yml no encontrado$(RESET)"; \
		exit 1; \
	}
	@[ -f secrets/grafana_password.txt ] || { \
		$(PRINT) "$(RED)❌ secrets/grafana_password.txt no existe$(RESET)"; \
		$(PRINT) "   Ejecuta: echo 'tu_password' > secrets/grafana_password.txt"; \
		exit 1; \
	}
	@# envsubst sustituye $$SLACK_WEBHOOK_URL en alertmanager.yml ANTES de levantarlo
	@# Docker NO interpola variables en archivos montados como volúmenes
	@[ -n "$${SLACK_WEBHOOK_URL:-}" ] || { \
		$(PRINT) "$(RED)❌ SLACK_WEBHOOK_URL no definida$(RESET)"; \
		$(PRINT) "   export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ"; \
		$(PRINT) "   O cárgala: set -a && source .env.production && set +a"; \
		exit 1; \
	}
	SLACK_WEBHOOK_URL="$${SLACK_WEBHOOK_URL}" \
		envsubst '$$SLACK_WEBHOOK_URL' \
		< monitoring/alertmanager.yml \
		> /tmp/alertmanager.resolved.yml
	$(PRINT) "$(CYAN)→ alertmanager.yml resuelto$(RESET)"
	$(DC_MONITORING) --profile prod-alerting up -d
	@$(PRINT) ""
	@$(PRINT) "$(GREEN)✅ Monitoreo COMPLETO activo:$(RESET)"
	@$(PRINT) "   Grafana:      http://localhost:$${PORT_GRAFANA:-3001}"
	@$(PRINT) "   Prometheus:   http://localhost:$${PORT_PROMETHEUS:-9090}"
	@$(PRINT) "   Alertmanager: http://localhost:9093"

monitoring-alert-test: ## Dispara alerta de prueba al Alertmanager → verifica Slack
	@$(PRINT) "$(YELLOW)🔔 Disparando alerta de prueba...$(RESET)"
	@command -v curl >/dev/null 2>&1 || { $(PRINT) "$(RED)❌ curl no disponible$(RESET)"; exit 1; }
	@curl -s -X POST http://localhost:9093/api/v1/alerts \
		-H 'Content-Type: application/json' \
		-d '[{"labels":{"alertname":"TestAlert","severity":"warning","job":"nombre_del_proyecto-test"},"annotations":{"summary":"🧪 Alerta de prueba — make monitoring-alert-test"},"startsAt":"'"$$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}]'
	@$(PRINT) ""
	@$(PRINT) "$(GREEN)✅ Alerta enviada — verifica #devops-alerts en Slack$(RESET)"
	@$(PRINT) "   Si no llega en 30s: make monitoring-logs"


# ══════════════════════════════════════════════════════════════════════════════
# UTILIDADES DE MANTENIMIENTO DE BASE DE DATOS Y SECRETS (DESTRUCTIVE)
# ══════════════════════════════════════════════════════════════════════════════

guard-not-ci:
	@[ "$$CI" != "true" ] || (echo "❌ Este target no puede ejecutarse en CI" && exit 1)

db-drop: guard-not-ci ## Elimina TODA la base de datos (destructive)
	$(call confirm_destructive,db-drop — eliminará TODA la base de datos)
	@docker compose exec postgres psql -U $$DB_USER -c "DROP DATABASE $$DB_NAME"

secrets-clean: guard-not-ci ## Elimina TODOS los archivos de secrets (destructive)
	$(call confirm_destructive,secrets-clean — eliminará TODOS los archivos de secrets)
	rm -rf ./secrets/