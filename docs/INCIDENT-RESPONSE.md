# Plan de Respuesta a Incidentes de Seguridad
## NOMBRE_DEL_PROYECTO — CONFIDENCIAL

**Versión:** 1.0.0  
**Última actualización:** [FECHA]  
**Propietario:** [NOMBRE/EQUIPO]  
**Clasificación:** INTERNO — No compartir externamente  

---

## 1. CLASIFICACIÓN DE INCIDENTES

| Severidad | Descripción | Tiempo de Respuesta | Ejemplo |
|---|---|---|---|
| P0 — CRÍTICO | Compromiso confirmado, datos expuestos | 15 minutos | DB dump filtrado |
| P1 — ALTO | Posible compromiso, servicio caído | 1 hora | Acceso no autorizado a admin |
| P2 — MEDIO | Vulnerabilidad explotable no confirmada | 4 horas | Secreto expuesto en logs |
| P3 — BAJO | Vulnerabilidad de baja probabilidad | 24 horas | Dependencia con CVE bajo |

---

## 2. CONTACTOS DE EMERGENCIA

| Rol | Nombre | Email | Teléfono |
|---|---|---|---|
| Responsable Principal | [NOMBRE] | [EMAIL] | [TELÉFONO] |
| Backup | [NOMBRE] | [EMAIL] | [TELÉFONO] |
| Hosting/VPS Provider | [PROVEEDOR] | [SOPORTE] | — |

---

## 3. PROCESO DE RESPUESTA

### 3.1 Detección y Triage (0-15 minutos)

```bash
# Comandos inmediatos de diagnóstico
# Estado de contenedores
docker ps -a
docker stats --no-stream

# Logs recientes (últimas 2 horas)
docker logs nombre_del_proyecto_api --since 2h 2>&1 | tail -500
docker logs nombre_del_proyecto_web --since 2h 2>&1 | tail -500
docker logs nombre_del_proyecto_reports --since 2h 2>&1 | tail -500

# Conexiones de red activas (desde el host)
ss -tulnp | grep -E '443|80|4000|3000|5000'
netstat -anp | grep ESTABLISHED

# Procesos sospechosos
ps aux | grep -v grep | grep -E 'nc|ncat|curl|wget|bash'
```

### 3.2 Contención (15-60 minutos)

```bash
# OPCIÓN 1: Bloquear acceso externo manteniendo el sistema activo
sudo ufw deny in 443
sudo ufw deny in 80
# Esto bloquea usuarios pero permite diagnóstico interno

# OPCIÓN 2: Parar todos los contenedores (último recurso)
make prod-down

# OPCIÓN 3: Aislar solo el servicio comprometido
docker stop nombre_del_proyecto_api  # Solo backend
docker network disconnect nombre_del_proyecto-private nombre_del_proyecto_api
```

### 3.3 Preservación de Evidencia (Durante contención)

```bash
# Capturar estado del sistema ANTES de cualquier cambio
# Ejecutar esto PRIMERO, antes de reiniciar nada

INCIDENT_DIR="/tmp/incident-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$INCIDENT_DIR"

# Logs de todos los contenedores
docker logs nombre_del_proyecto_api > "$INCIDENT_DIR/api.log" 2>&1
docker logs nombre_del_proyecto_web > "$INCIDENT_DIR/web.log" 2>&1
docker logs nombre_del_proyecto_reports > "$INCIDENT_DIR/reports.log" 2>&1

# Inspección de contenedores
docker inspect nombre_del_proyecto_api > "$INCIDENT_DIR/api-inspect.json"
docker inspect nombre_del_proyecto_web > "$INCIDENT_DIR/web-inspect.json"

# Conexiones de red
ss -tulnp > "$INCIDENT_DIR/network-connections.txt"
netstat -anp >> "$INCIDENT_DIR/network-connections.txt"

# Procesos
ps auxf > "$INCIDENT_DIR/processes.txt"

# Auth logs del sistema
sudo cat /var/log/auth.log > "$INCIDENT_DIR/auth.log" 2>/dev/null || true
sudo cat /var/log/secure > "$INCIDENT_DIR/secure.log" 2>/dev/null || true

# Comprimir y firmar
tar -czf "$INCIDENT_DIR.tar.gz" "$INCIDENT_DIR/"
sha256sum "$INCIDENT_DIR.tar.gz" > "$INCIDENT_DIR.tar.gz.sha256"

echo "Evidencia guardada en: $INCIDENT_DIR.tar.gz"
```

### 3.4 Rotación de Secretos Post-Incidente

```bash
# Rotar TODOS los secretos si hay sospecha de compromiso
# 1. Generar nuevos secretos
make secrets-rotate

# 2. Verificar nuevo estado
make secrets-check

# 3. Rearrancar servicios con nuevos secretos
make prod-down
make prod-up

# 4. Invalidar TODAS las sesiones activas (si Redis está disponible)
docker exec nombre_del_proyecto_redis redis-cli FLUSHDB

# 5. Si la DB fue comprometida: cambiar contraseñas en PostgreSQL
# psql -h localhost -U postgres
# ALTER USER app_user WITH PASSWORD 'NUEVA_CONTRASEÑA_FUERTE';
# ALTER USER app_readonly WITH PASSWORD 'NUEVA_CONTRASEÑA_FUERTE';
```

---

## 4. ESCENARIOS ESPECÍFICOS

### Escenario A: Secreto expuesto en logs o repositorio

1. Rotar el secreto comprometido inmediatamente.
2. Auditar logs para ver si fue usado.
3. Si es JWT_SECRET: invalidar todas las sesiones (flush Redis).
4. Si es DB_PASSWORD: auditar accesos a PostgreSQL.

```bash
# Auditar accesos a PostgreSQL por período sospechoso
psql -h localhost -U postgres -c "
SELECT client_addr, usename, datname, application_name, state, query_start, query
FROM pg_stat_activity
WHERE query_start > NOW() - INTERVAL '24 hours'
ORDER BY query_start DESC;
"
```

### Escenario B: Contenedor comprometido

1. Capturar evidencia (ver §3.3).
2. `docker stop [contenedor]`.
3. NO reiniciar el contenedor comprometido — hacer forensic primero.
4. Reconstruir imagen desde cero: `make prod-build`.

### Escenario C: Acceso no autorizado a la API

1. Verificar logs de Nginx para identificar IPs atacantes.
2. Bloquear IPs con UFW: `sudo ufw deny from [IP]`.
3. Revisar audit_trail table para acciones realizadas.
4. Revocar tokens comprometidos.

---

## 5. COMUNICACIÓN

### 5.1 Notificaciones internas

- **P0/P1:** Notificar inmediatamente por teléfono + Slack.
- **P2:** Notificar en ≤ 4h vía Slack.
- **P3:** Documentar en ticket, comunicar en daily.

### 5.2 Notificaciones externas (si hay datos de usuarios afectados)

- **GDPR:** Notificar a la autoridad de protección de datos en ≤ 72h.
- **Usuarios:** Comunicar si hay evidencia de acceso a datos personales.

---

## 6. POST-INCIDENTE

### Checklist de cierre

- [ ] Incidente contenido y sistema restaurado
- [ ] Evidencia forense preservada
- [ ] Todos los secretos rotados si hubo compromiso
- [ ] Sistemas auditados y limpios
- [ ] Vulnerabilidad raíz identificada y parchada
- [ ] Retrospectiva realizada (≤ 5 días post-incidente)
- [ ] Lecciones aprendidas documentadas
- [ ] Controles adicionales implementados

### Plantilla de informe post-incidente

INFORME DE INCIDENTE DE SEGURIDAD
ID: INC-YYYYMMDD-001
Fecha: YYYY-MM-DD
Severidad: P[0-3]
Estado: [En progreso / Cerrado]
RESUMEN EJECUTIVO:
[2-3 líneas describiendo qué ocurrió y el impacto]
LÍNEA DE TIEMPO:

HH:MM — Detección
HH:MM — Primera respuesta
HH:MM — Contención
HH:MM — Resolución

CAUSA RAÍZ:
[Descripción técnica]
IMPACTO:

Sistemas afectados:
Datos comprometidos: [Sí/No/Desconocido]
Tiempo de inactividad:
Usuarios afectados:

ACCIONES TOMADAS:

[Acción]
[Acción]

ACCIONES PREVENTIVAS:

[Control a implementar]

LECCIONES APRENDIDAS:
[Qué mejorar en el proceso]