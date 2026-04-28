# CONTRIBUTING.md — Guía de contribución

Gracias por contribuir al proyecto NOMBRE_DEL_PROYECTO. Esta guía describe cómo trabajar con el repositorio de forma consistente.

---

## Índice

- [Requisitos previos](#requisitos-previos)
- [Configuración del entorno](#configuración-del-entorno)
- [Convención de ramas (branches)](#convención-de-ramas)
- [Convención de commits](#convención-de-commits)
- [Flujo de trabajo](#flujo-de-trabajo)
- [Cómo correr los tests](#cómo-correr-los-tests)
- [Política de cobertura de tests](#política-de-cobertura-de-tests)
- [Antes de hacer un PR](#antes-de-hacer-un-pr)
- [Qué va en cada archivo de configuración](#qué-va-en-cada-archivo-de-configuración)
- [Contacto](#contacto)

---

## Requisitos previos

```bash
docker --version          # >= 20.10
docker compose version    # >= 2.0
make --version            # GNU Make >= 4.0
psql --version            # PostgreSQL client (para backup-db/rollback-db)
```

Verificar todo de una vez:
```bash
make doctor
```

---

## Configuración del entorno

Para configurar tu entorno de desarrollo local, sigue la guía en [README.md](README.md#-inicio-rápido-desarrollo). Una vez configurado, vuelve aquí para las convenciones de contribución

---

## Convención de ramas

| Tipo | Formato | Ejemplo |
|---|---|---|
| Feature | `feature/descripcion-corta` | `feature/healthcheck-db` |
| Bugfix | `fix/descripcion-del-bug` | `fix/env-example-db-credentials` |
| Documentación | `docs/descripcion` | `docs/architecture-diagram` |
| Refactor | `refactor/descripcion` | `refactor/makefile-validate-env` |
| Hotfix (urgente) | `hotfix/descripcion` | `hotfix/security-yml-syntax` |

**Reglas:**
- Siempre partir de `develop` (no de `main`)
- Nombres en minúsculas con guiones
- No subir directamente a `main` — siempre PR

---

## Convención de commits

Usar [Conventional Commits](https://www.conventionalcommits.org/):

```
<tipo>(<alcance>): <descripción corta>

[cuerpo opcional]

[pie opcional]
```

**Tipos:**

| Tipo | Cuándo usarlo |
|---|---|
| `feat` | Nueva funcionalidad o target de Makefile |
| `fix` | Corrección de bug |
| `docs` | Cambio en documentación únicamente |
| `chore` | Mantenimiento: dependencias, CI, config |
| `security` | Corrección de vulnerabilidad |
| `refactor` | Refactor sin cambio de comportamiento |
| `test` | Añadir o mejorar tests |

**Ejemplos:**

```bash
feat(makefile): añadir target setup-cron para backup automático
fix(env): corregir formato IMAGE_ sin protocolo http://
docs(architecture): añadir diagrama Mermaid en docs/ARCHITECTURE.md
chore(ci): añadir make validate-env en job validate
security(deps): actualizar digest node:24-slim via Renovate
```

---

## Flujo de trabajo

```
develop
  └── feature/mi-cambio
        ├── commits locales
        └── PR → develop
              ├── CI pasa (validate + tests + scan)
              └── Code review
                    └── Merge to develop
                          └── (periódico) PR develop → main
                                └── tag v2026.03.01
                                      └── deploy automático
```

---

## Cómo correr los tests

### Tests unitarios por servicio

```bash
# Backend (NestJS)
cd backend && pnpm test
cd backend && pnpm run lint

# Frontend (Next.js)
cd frontend && pnpm run lint
cd frontend && pnpm test --if-present

# Reports (Python)
cd reports && python -m pytest --tb=short
cd reports && flake8 . --max-line-length=120
```

### Validación de infraestructura

```bash
make validate           # Valida docker-compose.yml y docker-compose.prod.yml
make validate-env       # Verifica que .env tiene todas las variables requeridas
make lint-docker        # Hadolint en todos los Dockerfiles
make doctor             # Estado del entorno local
```

### Pipeline de seguridad completo

```bash
make audit-full         # 7 pasos: lint → misconfig → pip-audit → build → trivy → sbom → system-check
make grype-scan         # Escaneo de vulnerabilidades en imágenes (requiere grype)
make grype-scan-docker  # Lo mismo pero via Docker (sin instalar grype)
```

---

## Política de cobertura de tests

El proyecto usa un plan progresivo de cobertura — **nunca bajamos el umbral actual**.

| Servicio | Umbral actual | Próximo objetivo |
|---|---|---|
| Backend (NestJS) | 30% | 50% (Q3 2026) |
| Frontend (Next.js) | lint solamente | 20% (Q4 2026) |
| Reports (Python) | 0% (en activación) | 20% (Q3 2026) |

**Regla para PRs:** si tu PR introduce lógica de negocio nueva, debe incluir al menos:
- Un test del caso exitoso (happy path)
- Un test del caso de error principal

Para subir el umbral de Python de 0% a 20%, editar `reports/setup.cfg`:
\```ini
[pytest]
addopts = --cov=src --cov-fail-under=20
\```

---

## Antes de hacer un PR

Checklist obligatorio antes de abrir el PR:

```bash
# 1. El compose es válido
make validate

# 2. Las variables de entorno están completas
make validate-env

# 3. Los Dockerfiles no tienen problemas
make lint-docker

# 4. Los tests pasan
cd backend && pnpm test
cd frontend && pnpm run lint
cd reports && python -m pytest 2>/dev/null || echo "sin tests"

# 5. El pipeline de seguridad pasa
make audit-full

# 6. CHANGELOG.md actualizado con tu cambio
nano CHANGELOG.md   # añadir bajo ## [Sin lanzar]
```

---

## Qué va en cada archivo de configuración

| ¿Qué cambiar? | ¿Dónde? |
|---|---|
| Variable de entorno nueva | `.env.example`, `.env.prod.example`, `docs/ENV-VARIABLES.md` |
| Secreto nuevo | `docker-compose.prod.yml` (declarar), `docs/ENV-VARIABLES.md` (documentar) |
| Límites de recursos (CPU/RAM) | `docker-compose.prod.yml` + `DECISIONS.md ADR-010` |
| Puerto de un servicio | `.env.example`, `docker-compose.yml`, `docker-compose.override.yml` |
| Decisión de arquitectura | `DECISIONS.md` (nuevo ADR) |
| Imagen base nueva | `Dockerfile.prod` + verificar digest SHA256 |
| Target nuevo del Makefile | `Makefile` + añadir al `.PHONY` + añadir al `help` dashboard |
| Cambio en el workflow de CI | `.github/workflows/ci.yml` o `security.yml` |

---

## Estructura de archivos relevante

```
docker-compose-config/
├── .env.example              ← Plantilla dev (SÍ versionado)
├── .env.prod.example         ← Plantilla prod (SÍ versionado)
├── .env                      ← Dev activo (NO versionado)
├── .env.production           ← Prod activo (NO versionado, solo en servidor)
├── secrets/                  ← Credenciales (NO versionado, solo en servidor)
├── docker-compose.yml        ← Base
├── docker-compose.override.yml ← Delta desarrollo (auto-aplicado en dev)
├── docker-compose.prod.yml   ← Delta producción
├── Makefile                  ← Interfaz de todas las operaciones
├── DECISIONS.md              ← ADRs de arquitectura
├── CHANGELOG.md              ← Historial de cambios
├── README.md                 ← Guía de despliegue
└── docs/
    ├── ARCHITECTURE.md       ← Diagrama de arquitectura
    ├── ENV-VARIABLES.md      ← Documentación de variables
    └── auditorias/           ← Informes de auditoría externos
```

---

## Contacto

Para preguntas sobre la infraestructura o el proceso de contribución, abrir un issue en GitHub o contactar al responsable del proyecto.
