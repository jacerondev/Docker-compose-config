# TESTING.md — Estrategia de Testing — NOMBRE_DEL_PROYECTO

> **Estado actual:** Cobertura mínima funcional. Plan de incremento progresivo activo.

---

## Índice

- [Filosofía](#filosofía)
- [Estado actual de cobertura](#estado-actual-de-cobertura)
- [Cómo correr los tests](#cómo-correr-los-tests)
- [Estructura de tests por servicio](#estructura-de-tests-por-servicio)
- [Plan de incremento progresivo](#plan-de-incremento-progresivo)
- [Qué testear y qué no](#qué-testear-y-qué-no)
- [Guía rápida para escribir tests nuevos](#guía-rápida-para-escribir-tests-nuevos)
- [CI/CD y cobertura obligatoria](#cicd-y-cobertura-obligatoria)
- [Greybox Testing (con credenciales — como un pentester autorizado)](#greybox-testing-con-credenciales--como-un-pentester-autorizado)

---

## Filosofía

El testing en NOMBRE_DEL_PROYECTO sigue la **pirámide clásica**:

```
           ╱────────╲
          ╱  E2E (5%) ╲       Pocos, lentos, costosos
         ╱──────────────╲
        ╱  Integración   ╲    Validan módulos juntos
       ╱   (25%)          ╲
      ╱────────────────────╲
     ╱   Unitarios (70%)    ╲  Muchos, rápidos, aislados
    ╱────────────────────────╲
```

**Principio guía:** un test que no falla cuando el código está roto no aporta valor. Preferimos pocos tests con `--cov-fail-under` real antes que muchos tests que no detectan nada.

---

## Estado actual de cobertura

| Servicio | Framework | Umbral actual | Umbral objetivo |
|---|---|---|---|
| Backend (NestJS) | Jest | 30% | 60% (Q3 2026) |
| Frontend (Next.js) | Jest + RTL | 0% (lint solo) | 40% (Q4 2026) |
| Reports (Python) | pytest | 0% | 40% (Q3 2026) |

> ⚠️ El umbral de Python está en `--cov-fail-under=0` (nunca falla). Esto es temporal mientras se escriben los primeros tests de integración.

---

## Cómo correr los tests

### Backend (NestJS)

```bash
# Unitarios con cobertura
cd backend && pnpm test:cov

# Watch mode (desarrollo)
cd backend && pnpm test:watch

# E2E (requiere servicios corriendo)
cd backend && pnpm test:e2e

# Solo lint
cd backend && pnpm lint
```

### Frontend (Next.js)

```bash
# Lint (obligatorio en CI)
cd frontend && pnpm lint

# Tests si existen
cd frontend && pnpm test --if-present

# Type-check
cd frontend && pnpm build  # falla si hay errores de tipos
```

### Reports (Python)

```bash
# Tests con cobertura
cd reports && python -m pytest --cov=src --cov-report=term-missing -v

# Solo un archivo
cd reports && python -m pytest tests/test_health.py -v

# Con cobertura mínima (activar cuando se alcance umbral)
cd reports && python -m pytest --cov=src --cov-fail-under=20

# Lint
cd reports && flake8 . --max-line-length=120
cd reports && black . --check
```

### Todos los servicios (via Make)

```bash
make test              # Backend con cobertura
make validate          # Validación de compose
make lint-docker       # Hadolint en todos los Dockerfiles
make audit-full        # Pipeline completo (lint + trivy + sbom + system-check)
```

---

## Estructura de tests por servicio

### Backend — `backend/src/**/*.spec.ts`

```
backend/
├── src/
│   ├── app.controller.spec.ts         ← Tests del controller raíz
│   ├── health/
│   │   └── health.controller.spec.ts  ← Tests del healthcheck
│   └── auth/
│       └── auth.controller.spec.ts    ← (pendiente)
└── test/
    └── app.e2e-spec.ts                ← E2E con supertest
```

**Convención de nombres:** `[nombre].controller.spec.ts`, `[nombre].service.spec.ts`, `[nombre].module.spec.ts`

### Frontend — `frontend/src/**/*.spec.tsx`

```
frontend/src/
└── app/
    └── page.spec.tsx   ← Render test de la página raíz
```

**Convención:** `[nombre].spec.tsx` para componentes, `[nombre].test.ts` para utils.

### Reports — `reports/tests/`

```
reports/
└── tests/
    ├── conftest.py        ← Fixtures compartidas (cliente Flask, BD test)
    ├── test_health.py     ← Tests del endpoint /health
    └── test_[modulo].py   ← Un archivo por módulo/blueprint
```

---

## Plan de incremento progresivo

El objetivo es llegar a umbrales reales de forma sostenible, **sin escribir tests vacíos**.

### Fase 1 — Q2 2026 (estado inicial)

| Servicio | Umbral | Acción |
|---|---|---|
| Backend | 30% | Mantener. Tests existentes de health + app controller. |
| Frontend | 0% | Solo lint en CI. |
| Python | 0% | Solo `test_health.py` funcional. |

### Fase 2 — Q3 2026

| Servicio | Umbral | Qué escribir |
|---|---|---|
| Backend | 50% | Tests de DTOs (validaciones), guards, filtros de excepción |
| Frontend | 20% | Tests de render de componentes críticos |
| Python | 20% | Tests de rutas de reports, mocking de BD |

Para activar el umbral en Python, modificar `pyproject.toml` o `setup.cfg`:
```ini
[tool:pytest]
addopts = --cov=src --cov-fail-under=20
```

### Fase 3 — Q4 2026

| Servicio | Umbral | Qué escribir |
|---|---|---|
| Backend | 60% | Tests de servicios, integración con TypeORM (sqlite en memoria) |
| Frontend | 40% | Tests de formularios, integración con API mock |
| Python | 40% | Tests de generación de reportes, validaciones de schema |

---

## Qué testear y qué no

### ✅ Sí testear

- Lógica de negocio en servicios (`auth.service`, `reports.service`)
- Validaciones de DTOs y schemas (errores 400 con datos inválidos)
- Guards de autenticación (rutas protegidas)
- Transformaciones de datos (mappers, serializers)
- Casos borde: valores nulos, listas vacías, strings vacíos
- Endpoints de health

### ❌ No testear (bajo retorno)

- Getters/setters triviales sin lógica
- Módulos de NestJS (solo registran providers)
- Código generado automáticamente
- Infraestructura Docker/compose (eso lo cubre Trivy + hadolint)
- Estilos CSS (testing visual → Storybook si se necesita)

---

## Guía rápida para escribir tests nuevos

### Backend (NestJS) — test unitario mínimo

```typescript
// src/auth/auth.service.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  let service: AuthService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [AuthService],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('debería estar definido', () => {
    expect(service).toBeDefined();
  });

  it('debería rechazar credenciales inválidas', async () => {
    await expect(service.login({ email: 'x', password: 'y' }))
      .rejects.toThrow();
  });
});
```

### Python (Flask) — test con conftest

```python
# tests/test_reports.py
def test_lista_reportes_requiere_auth(client):
    """Sin token → 401"""
    response = client.get('/api/reports')
    assert response.status_code == 401

def test_lista_reportes_con_token(client, auth_headers):
    """Con token válido → 200"""
    response = client.get('/api/reports', headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json, list)
```

---

## CI/CD y cobertura obligatoria

El pipeline de CI (`.github/workflows/ci.yml`) ejecuta:

1. **Lint** (siempre) — fallo bloquea el merge
2. **Tests unitarios** con cobertura mínima — fallo bloquea el merge
3. **Seguridad** (`make audit-full`) — fallo bloquea el merge

Para actualizar el umbral de cobertura en CI:

```yaml
# .github/workflows/ci.yml — sección backend
- name: Tests con cobertura
  run: |
    cd backend
    pnpm test:cov -- --coverageThreshold='{"global":{"lines":50}}'
```

Para Python, editar `reports/setup.cfg` o crear `reports/pytest.ini`:
```ini
[pytest]
addopts = --cov=src --cov-report=term-missing --cov-fail-under=20
```

> **Regla de equipo:** al añadir una feature nueva, añadir al menos un test que cubra el happy path y un test que cubra el caso de error. No se fusionan PRs que bajen la cobertura actual.

# Security Testing Guide — Blackbox & Greybox

## ¿Cuándo ejecutar estas pruebas?

- **Antes del primer deploy a producción** — prueba baseline obligatoria
- **Antes de cada release mayor** — cuando se añaden nuevos módulos o endpoints
- **Después de cambios en Nginx, CORS o autenticación**

---

## Blackbox Testing (sin acceso al código — como un atacante externo)

Simula un atacante que solo conoce la URL pública. No requiere credenciales.

### Prerequisitos

Necesitas un entorno de staging activo (no correr contra producción real).
```bash
# Variables de entorno para los scripts
export TARGET=https://staging.tu-dominio.com
```

### 1. Verificar superficie de ataque visible externamente
```bash
# Confirmar que los puertos internos NO son accesibles desde internet
# Resultado esperado: todos los puertos filtrados excepto 80 y 443
nmap -p 80,443,3000,4000,5000,5432,9090,3001 <IP_PUBLICA_DEL_VPS>

# Verificar headers de seguridad HTTP
curl -sI $TARGET | grep -E "Strict-Transport|Content-Security|X-Frame|Referrer-Policy"
```

### 2. OWASP ZAP — Baseline Scan
```bash
# Escaneo rápido (~10 min): solo pasivo, sin atacar activamente
docker run --rm -t owasp/zap2docker-stable \
  zap-baseline.py \
  -t $TARGET \
  -r /tmp/zap-baseline.html \
  -I   # No bloquear aunque encuentre issues — modo informativo

# Ver el reporte
open /tmp/zap-baseline.html
```

### 3. Nikto — Configuraciones conocidas inseguras
```bash
# Escanea configuraciones comunes mal hechas (15-30 min)
docker run --rm sullo/nikto -h $TARGET -ssl -o /tmp/nikto.txt
```

### 4. Verificar endpoints sensibles no expuestos
```bash
# Ninguno de estos debe ser accesible externamente (debe devolver 404 o conexión rechazada)
curl -s -o /dev/null -w "%{http_code}" $TARGET/api/docs         # Swagger
curl -s -o /dev/null -w "%{http_code}" $TARGET:9090             # Prometheus
curl -s -o /dev/null -w "%{http_code}" $TARGET:3001             # Grafana
curl -s -o /dev/null -w "%{http_code}" $TARGET/metrics          # Métricas internas
```

---

## Greybox Testing (con credenciales — como un pentester autorizado)

Simula un atacante con acceso a una cuenta legítima (pero no admin).

### 1. ZAP Authenticated Scan
```bash
# Con sesión activa: ZAP puede explorar endpoints protegidos
docker run --rm -v $(pwd)/.zap:/zap/wrk:rw \
  owasp/zap2docker-stable \
  zap-full-scan.py \
  -t $TARGET \
  -r /zap/wrk/full-scan.html \
  -z "-config scanner.attackStrength=MEDIUM"
```

### 2. Checklist manual de autenticación

Cuando la autenticación esté implementada, verificar:
```bash
# Rate limiting en login (debe bloquear después de 5 intentos)
for i in {1..7}; do
  curl -s -o /dev/null -w "Intento $i: %{http_code}\n" \
    -X POST $TARGET/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"test@test.com","password":"wrong"}'
done
# Esperado: primeros 5 → 401, 6 y 7 → 429

# Verificar que cookies tienen los flags correctos
curl -c /tmp/cookies.txt -X POST $TARGET/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@test.com","password":"correcto"}'
grep -E "HttpOnly|Secure|SameSite" /tmp/cookies.txt
```

---

## Frecuencia recomendada para proyecto personal

| Prueba | Cuándo | Tiempo estimado |
|--------|--------|-----------------|
| Nmap + headers | Antes de cada release | 5 min |
| ZAP Baseline | Antes de cada release | 15 min |
| ZAP Full (greybox) | Trimestralmente | 1-2 horas |
| Nikto | Trimestralmente | 30 min |

---

## Interpretar los resultados

Los escáneres generan muchos falsos positivos. Prioriza así:

1. **CRITICAL/HIGH con PoC (proof of concept)** — corregir antes del deploy
2. **MEDIUM** — corregir en el siguiente sprint
3. **LOW/INFORMATIONAL** — evaluar caso por caso; muchos son falsos positivos
4. **Falsos positivos comunes:** Swagger endpoints (ya están protegidos), headers de Nginx con defaults, cookies de sesión sin `Path` explícito