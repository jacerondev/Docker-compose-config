# Security Testing Guide

Esta guía cubre las herramientas y procesos de seguridad del proyecto,
organizados por cuándo y cómo ejecutarlos.

---

## Análisis de dependencias (SCA) — Alternativas gratuitas a Snyk

El proyecto no usa Snyk por no contemplar licencia. Las herramientas
equivalentes de código abierto cubren el mismo surface de vulnerabilidades.

### Herramientas activas en CI (automáticas)

**`pnpm audit`** — dependencias Node.js contra el advisory DB de npm:
```bash
# Corre automáticamente en audit.yml
# Para correr manualmente:
cd backend && pnpm audit --audit-level=high
cd frontend && pnpm audit --audit-level=high
```

**`pip-audit`** — dependencias Python contra PyPA advisory DB y OSV:
```bash
# Instalar (si no está):
pip install pip-audit

# Escanear el proyecto
pip-audit -r reports/requirements.txt --format=json -o scripts/tests/pip-audit.log
cat scripts/tests/pip-audit.log
```

### Herramientas manuales (ejecutar antes de cada release)

**OSV Scanner** (Google) — escaneo multi-ecosistema, incluye Node y Python:
```bash
# Instalar (una vez):
curl -fsSL https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_linux_amd64 \
  -o /usr/local/bin/osv-scanner && chmod +x /usr/local/bin/osv-scanner

# Escanear todo el proyecto:
osv-scanner --recursive .

# Solo lockfiles específicos:
osv-scanner --lockfile backend/pnpm-lock.yaml
osv-scanner --lockfile reports/requirements.txt
```

**Grype** (Anchore) — análisis de SBOMs e imágenes locales:
```bash
# Instalar:
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# Escanear el filesystem del proyecto:
grype dir:. --fail-on high

# Escanear una imagen Docker local:
grype nombre_del_proyecto_api:latest --fail-on critical
```

### Cuándo migrar a Snyk

Si en el futuro el proyecto:
- Tiene múltiples desarrolladores que necesitan ver vulnerabilidades en un dashboard compartido
- Requiere Pull Request checks automáticas con sugerencias de fix
- Necesita monitoreo continuo (no solo en CI)

El tier gratuito de Snyk cubre proyectos open source ilimitados y hasta
3 proyectos privados. Para proyectos personales privados, OSV Scanner + Grype
es equivalente sin costo.


---

## Blackbox & Greybox Testing

El testing de seguridad dinámico complementa el análisis estático (Semgrep, Bandit, Trivy)
probando la aplicación en ejecución desde la perspectiva de un atacante.

**Cuándo ejecutar:**
- Antes del primer deploy a producción (obligatorio)
- Antes de cada release que modifique auth, CORS, Nginx o endpoints públicos
- Trimestralmente como verificación de mantenimiento

**Entorno requerido:** Un entorno de staging activo con el stack completo levantado.
Nunca ejecutar estos tests contra producción real.

```bash
# Variable de entorno para todos los comandos de esta sección
export TARGET=https://staging.tu-dominio.com
export VPS_IP=<ip-publica-del-vps>
```

---

### 1. Blackbox — superficie expuesta externamente

Simula un atacante externo que solo conoce la IP pública del VPS y el dominio.
No requiere credenciales.

#### 1.1 Verificar que los puertos internos no son accesibles desde internet

Los puertos de aplicación están bound a `127.0.0.1` en producción (ver `docker-compose.prod.yml`).
Solo deben ser accesibles los puertos 80 y 443 desde el exterior.

```bash
# Resultado esperado: puertos 3000, 4000, 5000, 5432, 9090, 3001 → filtrados o cerrados
# Solo 80 y 443 deben aparecer como open
nmap -p 80,443,3000,4000,5000,5432,9090,3001 $VPS_IP

# Verificación rápida de los servicios internos (deben rechazar conexión):
curl -s --max-time 3 http://$VPS_IP:4000/health || echo "OK — backend no accesible directamente"
curl -s --max-time 3 http://$VPS_IP:5000/health || echo "OK — reports no accesible directamente"
curl -s --max-time 3 http://$VPS_IP:5432      || echo "OK — postgres no accesible directamente"
```

#### 1.2 Verificar headers de seguridad HTTP

```bash
# Verificar que todos los headers críticos están presentes
curl -sI $TARGET | grep -E \
  "Strict-Transport-Security|Content-Security-Policy|X-Frame-Options|\
Referrer-Policy|X-Content-Type-Options"

# Resultado esperado:
#   Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
#   Content-Security-Policy: default-src 'self'; ...
#   Referrer-Policy: strict-origin-when-cross-origin
#   X-Content-Type-Options: nosniff
```

#### 1.3 Verificar que endpoints sensibles no están expuestos

```bash
# Todos deben devolver 404, 401 o rechazo de conexión — nunca 200
echo "Swagger UI (solo dev):"
curl -s -o /dev/null -w "%{http_code}" $TARGET/api/docs

echo "Prometheus:"
curl -s -o /dev/null -w "%{http_code}" $TARGET/metrics

echo "Grafana:"
curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://$VPS_IP:3001 \
  || echo "cerrado correctamente"

echo "Health interno (no debe estar en Nginx):"
curl -s -o /dev/null -w "%{http_code}" $TARGET/health/ready
# Esperado: 404 si Nginx no expone /health/ready; 200 si sí (revisar config Nginx)
```

#### 1.4 ZAP Baseline Scan — escaneo pasivo automático

No ataca activamente, solo observa y detecta misconfiguraciones. Aproximadamente 10–15 minutos.

```bash
# Instalar ZAP CLI (si no está):
docker pull owasp/zap2docker-stable

# Ejecutar baseline scan
docker run --rm -t \
  -v $(pwd)/.zap:/zap/wrk:rw \
  owasp/zap2docker-stable zap-baseline.py \
  -t $TARGET \
  -r /zap/wrk/zap-baseline-$(date +%Y%m%d).html \
  -I   # -I: no falla aunque encuentre issues, solo reporta

# Abrir el reporte:
open .zap/zap-baseline-$(date +%Y%m%d).html
```

El archivo `.zap/rules.tsv` ya contiene los falsos positivos conocidos de este proyecto:
```
10015   IGNORE  (Incomplete or No Cache-control Header Set)
10096   IGNORE  (Timestamp Disclosure)
```
Añadir nuevas entradas si ZAP reporta falsos positivos adicionales.

#### 1.5 Nikto — configuraciones inseguras conocidas

```bash
# Nikto detecta versiones de software expuestas, directorios listables, etc.
docker run --rm \
  sullo/nikto -h $TARGET -ssl \
  -o /tmp/nikto-$(date +%Y%m%d).txt

# Ver solo findings de severidad alta:
grep -E "OSVDB|CVE|\+.*interesting" /tmp/nikto-$(date +%Y%m%d).txt
```

---

### 2. Greybox — con sesión autenticada

Simula un pentester con acceso a una cuenta legítima (no admin). Requiere que la
autenticación esté implementada (`AUTH_MODE=real`).

> **Nota sobre el estado actual:** Con `AUTH_MODE=development`, el guard inyecta
> un usuario simulado y estos tests no son aplicables. Ejecutar solo cuando la
> autenticación real esté activa en staging.

#### 2.1 Verificar cookies de autenticación

Cuando el login esté implementado, verificar que las cookies tienen los flags correctos:

```bash
# Hacer login y capturar las cookies
curl -c /tmp/cookies-$(date +%Y%m%d).txt \
  -s -o /dev/null -w "%{http_code}" \
  -X POST $TARGET/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"password_correcto"}'
echo ""

# Inspeccionar los flags de seguridad de las cookies
cat /tmp/cookies-$(date +%Y%m%d).txt

# Resultado esperado para access_token y refresh_token:
#   HttpOnly  → presente (inaccesible desde JavaScript)
#   Secure    → presente (solo HTTPS)
#   SameSite=Strict → presente (protección CSRF)
#   Path      → /api/auth/refresh para refresh_token (scope limitado)
```

#### 2.2 Verificar rate limiting en endpoints de autenticación

```bash
# Login: máximo 5 intentos por minuto desde la misma IP
# Los primeros 5 deben devolver 401, el 6.º debe devolver 429
for i in $(seq 1 7); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST $TARGET/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"test@test.com","password":"incorrecta"}')
  echo "Intento $i: HTTP $STATUS"
  sleep 0.5
done
# Esperado: 401 401 401 401 401 429 429

# Registro: máximo 3 intentos por hora desde la misma IP
for i in $(seq 1 4); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST $TARGET/api/auth/register \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"test${i}@test.com\",\"password\":\"Test1234!\"}")
  echo "Registro $i: HTTP $STATUS"
done
# Esperado: 201 201 201 429
```

#### 2.3 Verificar X-Request-Id en respuestas

```bash
# Cada respuesta debe devolver el mismo ID que se envió (o generar uno nuevo)
REQUEST_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)

curl -sI $TARGET/api/auth/health \
  -H "X-Request-Id: $REQUEST_ID" | grep -i "x-request-id"
# Esperado: X-Request-Id: <mismo UUID que enviamos>
```

#### 2.4 ZAP Full Scan — con sesión activa

Para ejecutar este scan, ZAP necesita una sesión autenticada. Configurar
el contexto de autenticación en `.zap/auth.yaml` antes de ejecutar.

```bash
# Full scan autenticado (~30-60 min, más exhaustivo)
docker run --rm -t \
  -v $(pwd)/.zap:/zap/wrk:rw \
  owasp/zap2docker-stable zap-full-scan.py \
  -t $TARGET \
  -r /zap/wrk/zap-full-$(date +%Y%m%d).html \
  -z "-config scanner.attackStrength=MEDIUM" \
  -I
```

---

### 3. Guardar evidencia

```bash
# Crear directorio de evidencia si no existe
mkdir -p scripts/tests/

# Copiar reportes al directorio de evidencia
cp .zap/zap-baseline-$(date +%Y%m%d).html scripts/tests/
cp .zap/zap-full-$(date +%Y%m%d).html     scripts/tests/ 2>/dev/null || true
cp /tmp/nikto-$(date +%Y%m%d).txt         scripts/tests/
```

El `.gitignore` excluye `scripts/tests/*.log` pero no `.html` ni `.txt`.
Los reportes ZAP y Nikto en esos formatos sí se versionan como evidencia de auditoría.

---

### 4. Frecuencia recomendada

| Prueba | Cuándo ejecutar | Tiempo estimado |
|--------|----------------|-----------------|
| nmap + headers (`§1.1`, `§1.2`) | Antes de cada release | 2 min |
| Endpoints sensibles (`§1.3`) | Antes de cada release | 1 min |
| ZAP Baseline (`§1.4`) | Antes de cada release | 15 min |
| Nikto (`§1.5`) | Trimestralmente | 30 min |
| Cookies + rate limiting (`§2.1`, `§2.2`) | Al implementar auth real | 10 min |
| ZAP Full autenticado (`§2.4`) | Trimestralmente | 60 min |

---

### 5. Interpretar resultados

Los escáneres generan falsos positivos. Clasificar hallazgos así:

| Nivel ZAP/Nikto | Criterio de acción |
|-----------------|-------------------|
| High / Critical con PoC | Bloquea el release — corregir antes del deploy |
| Medium | Corregir en el siguiente sprint |
| Low | Evaluar caso por caso — muchos son ruido |
| Informational | Revisar, sin acción obligatoria |

**Falsos positivos frecuentes en este proyecto:**
- `Cache-Control header missing` en `/api/docs` → ignorado (Swagger solo en dev)
- `X-Frame-Options missing` → ya gestionado por Helmet en el backend
- `Timestamp Disclosure` en headers de respuesta → ya en `.zap/rules.tsv`


---


## CIS Docker Benchmark — Hardening del daemon Docker

Verifica que la configuración del daemon Docker en el VPS sigue las mejores prácticas
del Center for Internet Security (CIS Docker Benchmark).

### Cuándo ejecutar

- Después de instalar Docker en el VPS por primera vez
- Después de actualizar Docker Engine a una versión mayor
- Trimestralmente como verificación de mantenimiento

### Ejecución
```bash
# En el VPS — requiere acceso root
docker run --rm --net host --pid host --userns host \
  --cap-add audit_control \
  -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
  -v /etc:/etc:ro \
  -v /lib/systemd/system:/lib/systemd/system:ro \
  -v /usr/bin/containerd:/usr/bin/containerd:ro \
  -v /usr/bin/runc:/usr/bin/runc:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --label docker_bench_security \
  docker/docker-bench-security 2>&1 | tee /tmp/docker-bench-$(date +%Y%m%d).txt
```

### Interpretar resultados

El reporte usa tres niveles:

| Nivel | Significado | Acción |
|-------|-------------|--------|
| `[PASS]` | Control cumplido | Ninguna |
| `[WARN]` | Control no cumplido | Evaluar y corregir si aplica |
| `[INFO]` | Informativo | Leer, sin acción obligatoria |
| `[NOTE]` | Requiere revisión manual | Evaluar según el contexto |

### Controles WARN comunes y cómo resolverlos

**`[WARN] 1.1.1 — Ensure a separate partition for containers`**
En un VPS de propósito único esto es impractical. Documentar como excepción aceptada.

**`[WARN] 2.1 — Ensure the container host has been Hardened`**
Resolución: instalar y correr Lynis (ver sección siguiente).

**`[WARN] 2.2 — Ensure Docker is up to date`**
```bash
# Actualizar Docker Engine
sudo apt update && sudo apt upgrade docker-ce docker-ce-cli containerd.io
```

**`[WARN] 3.x — Docker daemon configuration files`**
Verificar permisos del socket:
```bash
ls -la /var/run/docker.sock
# Esperado: srw-rw---- root docker
# Si dice srw-rw-rw- → corregir: sudo chmod 660 /var/run/docker.sock
```

**`[WARN] 4.x — Container images`**
La mayoría ya están resueltos en este proyecto:
- ✅ Imágenes con usuario no-root
- ✅ Imágenes con digest SHA256
- ✅ `read_only: true` en producción
- ✅ `no-new-privileges: true`

### Guardar evidencia de auditoría
```bash
# Mover el reporte al directorio de evidencia del proyecto
mkdir -p scripts/tests/
mv /tmp/docker-bench-$(date +%Y%m%d).txt scripts/tests/
```

El `.gitignore` ya incluye `scripts/tests/*.log` — para versionar los reportes,
renombrarlos con extensión `.txt` o añadirlos explícitamente.

---

## Lynis — Hardening del sistema operativo (Ubuntu/Debian)

Lynis audita el sistema operativo del VPS contra una base de datos de ~600 controles
de seguridad (CIS, HIPAA, PCI-DSS). Complementa docker-bench que solo analiza Docker.

### Instalación en el VPS
```bash
# Instalar desde repositorio oficial (más actualizado que apt)
curl -fsSL https://packages.cisofy.com/keys/cisofy-software-public.key | sudo gpg --dearmor -o /usr/share/keyrings/cisofy-software.gpg
echo "deb [signed-by=/usr/share/keyrings/cisofy-software.gpg] https://packages.cisofy.com/community/lynis/deb/ stable main" | sudo tee /etc/apt/sources.list.d/cisofy-lynis.list
sudo apt update && sudo apt install lynis
```

### Ejecución
```bash
# Auditoría completa del sistema (10-15 min)
sudo lynis audit system 2>&1 | tee /tmp/lynis-$(date +%Y%m%d).txt

# Ver solo los warnings (más rápido para revisiones periódicas)
sudo lynis audit system --quick 2>&1 | grep -E "Warning|Suggestion" | head -30

# El reporte detallado queda en:
cat /var/log/lynis-report.dat
```

### Secciones clave del reporte para un VPS con Docker

El reporte muestra un `Hardening index` de 0-100. Para un servidor de producción
apuntar a **>70**. Los controles más relevantes para este proyecto:

| Sección | Qué revisa | Acción típica |
|---------|-----------|---------------|
| `Authentication` | SSH config, PAM, sudo | Desactivar SSH con contraseña, usar solo keys |
| `Networking` | Firewall (ufw/iptables), puertos abiertos | Activar ufw, abrir solo 22/80/443 |
| `File permissions` | Permisos de archivos críticos | Seguir sugerencias de Lynis |
| `Software` | Actualizaciones pendientes | `sudo apt upgrade` |
| `Containers` | Configuración básica de Docker | Ver docker-bench para detalle |

### Correcciones comunes sugeridas por Lynis

**SSH hardening** (`/etc/ssh/sshd_config`):
```bash
# Añadir o verificar estas líneas:
PasswordAuthentication no      # Solo SSH keys
PermitRootLogin no             # No login directo como root
MaxAuthTries 3                 # Máximo 3 intentos por sesión
Protocol 2                     # Solo SSH v2
```

**Firewall básico con ufw**:
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 80/tcp     # HTTP (Nginx)
sudo ufw allow 443/tcp    # HTTPS (Nginx)
sudo ufw enable
sudo ufw status verbose
```

**Desactivar servicios innecesarios**:
```bash
# Ver servicios activos
sudo systemctl list-units --type=service --state=running

# Deshabilitar los que no uses (ejemplos comunes en VPS):
sudo systemctl disable --now cups avahi-daemon bluetooth 2>/dev/null || true
```

### Frecuencia recomendada

| Cuándo | Qué ejecutar |
|--------|-------------|
| Después de provisionar el VPS | `lynis audit system` completo + aplicar sugerencias HIGH |
| Mensualmente | `lynis audit system --quick` — revisar nuevas sugerencias |
| Antes de un release a producción | Confirmar que el Hardening index no bajó |

### Guardar evidencia
```bash
sudo cp /var/log/lynis-report.dat scripts/tests/lynis-report-$(date +%Y%m%d).dat
```

---

## Supply Chain: pnpm --ignore-scripts

Todos los `pnpm install` deben ejecutarse con `--ignore-scripts` para prevenir
ejecución de código arbitrario en postinstall scripts. Esta restricción es:
- Obligatoria en CI (verificada automáticamente)
- Obligatoria en Dockerfiles (ya configurado)
- Recomendada en desarrollo local (configurada en .npmrc)

El CI fallará si .npmrc no contiene `ignore-scripts=true`.