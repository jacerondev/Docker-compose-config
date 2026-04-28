# MONITORING-ALERTMANAGER.md — Guía de Alertmanager para NOMBRE_DEL_PROYECTO

> **Referencia técnica viva.** Actualizar al añadir nuevos canales de notificación o reglas de alerta.
>
> Stack: Alertmanager v0.27.0 · Prometheus · Slack (canal principal)

---

## Índice

1. [¿Qué es Alertmanager y por qué existe separado de Prometheus?](#1-qué-es-alertmanager-y-por-qué-existe-separado-de-prometheus)
2. [Arquitectura: cómo encaja en el stack de monitoreo](#2-arquitectura-cómo-encaja-en-el-stack-de-monitoreo)
3. [Configuración actual — alertmanager.yml](#3-configuración-actual--alertmanageryml)
4. [¿Activar en desarrollo o solo en producción?](#4-activar-en-desarrollo-o-solo-en-producción)
5. [Desactivar Alertmanager en desarrollo](#5-desactivar-alertmanager-en-desarrollo)
6. [Variables de entorno requeridas](#6-variables-de-entorno-requeridas)
7. [Alertas configuradas — alerts.yml](#7-alertas-configuradas--alertsyml)
8. [Añadir un canal de notificación nuevo](#8-añadir-un-canal-de-notificación-nuevo)
9. [Probando que las alertas funcionan](#9-probando-que-las-alertas-funcionan)
10. [Silenciar una alerta temporalmente](#10-silenciar-una-alerta-temporalmente)
11. [Referencia rápida de comandos](#11-referencia-rápida-de-comandos)

---

## 1. ¿Qué es Alertmanager y por qué existe separado de Prometheus?

**Prometheus** recoge métricas y evalúa reglas. Cuando una regla se cumple (ej: CPU > 80%), Prometheus genera una alerta en estado `firing`. Pero Prometheus no sabe cómo notificar a nadie.

**Alertmanager** recibe esas alertas de Prometheus y se encarga de:

- Agrupar alertas relacionadas (evitar 200 notificaciones en cascada)
- Deduplicar la misma alerta si llega varias veces
- Silenciar alertas planificadas (mantenimientos)
- Enrutar alertas al canal correcto (Slack, email, PagerDuty, etc.)
- Controlar la frecuencia de repetición (`repeat_interval`)

```
Prometheus → evalúa rules → alerta "firing"
    ↓ HTTP POST /api/v2/alerts
Alertmanager → agrupa → deduplica → enruta
    ↓
Canal de notificación (Slack #devops-alerts)
```

**Sin Alertmanager:** Prometheus puede enviar alertas directamente a webhooks, pero sin agrupación ni deduplicación ni silenciado. Útil solo para pruebas.

---

## 2. Arquitectura: cómo encaja en el stack de monitoreo

```
monitoring/
├── prometheus.yml          ← Define jobs de scraping y apunta a alerts.yml
├── alerts.yml              ← Reglas: cuándo y cómo se genera una alerta
├── alertmanager.yml        ← A dónde van las alertas y con qué frecuencia
└── grafana/
    └── provisioning/
        └── datasources/
            └── prometheus.yml  ← Grafana conecta a Prometheus
```

En `prometheus.yml` se debe referenciar `alerts.yml` y apuntar a Alertmanager:

```yaml
# monitoring/prometheus.yml — añadir estas secciones
rule_files:
  - /etc/prometheus/alerts.yml # Prometheus evalúa estas reglas

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"] # Donde Alertmanager escucha
```

> **⚠️ Verificar:** El `prometheus.yml` actual del proyecto no tiene `rule_files` ni `alerting` configurados. Añadir esas secciones para que Alertmanager reciba alertas.

---

## 3. Configuración actual — alertmanager.yml

```yaml
# monitoring/alertmanager.yml
route:
  receiver: "slack-devops"
  group_wait: 30s # Espera 30s para agrupar alertas antes de notificar
  group_interval: 5m # Cada 5m notifica el resumen del grupo
  repeat_interval: 4h # Si la alerta sigue firing, repite cada 4 horas

receivers:
  - name: "slack-devops"
    slack_configs:
      - api_url: "${SLACK_WEBHOOK_URL}"
        channel: "#devops-alerts"
        title: "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}"
        send_resolved: true # Notifica también cuando la alerta se resuelve
```

**Parámetros clave:**

| Parámetro         | Qué hace                                                                         | Valor actual |
| ----------------- | -------------------------------------------------------------------------------- | ------------ |
| `group_wait`      | Tiempo que espera antes de enviar el primer mensaje (agrupa alertas simultáneas) | 30s          |
| `group_interval`  | Tiempo entre actualizaciones del grupo si hay alertas nuevas                     | 5m           |
| `repeat_interval` | Frecuencia de recordatorio si la alerta no se resuelve                           | 4h           |
| `send_resolved`   | Envía mensaje cuando el problema se soluciona                                    | `true`       |

---

## 4. ¿Activar en desarrollo o solo en producción?

**Decisión del proyecto:** Alertmanager está **desactivado por defecto en desarrollo** y **activo en producción**.

### Razones para desactivarlo en desarrollo

| Factor                | Desarrollo                                                | Producción                                     |
| --------------------- | --------------------------------------------------------- | ---------------------------------------------- |
| **Propósito**         | Probar código, levantar/bajar contenedores frecuentemente | Monitorear un sistema real con usuarios        |
| **Alertas esperadas** | Servicios que caen constantemente durante pruebas         | Solo alertas reales que requieren acción       |
| **Ruido**             | Cada `make dev` + `make stop` dispararía `ServiceDown`    | Solo alertas que merecen interrumpir al equipo |
| **Webhook**           | No tiene sentido tener Slack de producción activo en dev  | Canal dedicado `#devops-alerts` monitoreado    |
| **Recursos**          | Alertmanager usa ~20-50MB RAM extra                       | En VPS de producción es justificable           |

### Cuándo SÍ tiene sentido en desarrollo

- Cuando estás desarrollando la propia configuración de alertas y necesitas verificar que llegan correctamente
- Para testing de integración de la cadena completa: reglas → Alertmanager → Slack

---

## 5. Desactivar Alertmanager en desarrollo

El proyecto usa `docker-compose.monitoring.yml` para todo el stack de monitoreo. Para desactivar Alertmanager solo en desarrollo, se usan **Docker Compose profiles**:

### Modificar docker-compose.monitoring.yml

```yaml
# docker-compose.monitoring.yml — Alertmanager con profile "prod-alerting"
alertmanager:
  image: prom/alertmanager:v0.27.0@sha256:e13b6ed5cb929eeaee733479dce55e10eb3bc2e9c4586c705a4e8da41e5eacf5
  container_name: nombre_del_proyecto_alertmanager
  restart: unless-stopped
  profiles:
    - prod-alerting # ← Solo se levanta si se activa este profile
  volumes:
    - ./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    - alertmanager_data:/alertmanager # Persistir silenciados y estado
  command:
    - "--config.file=/etc/alertmanager/alertmanager.yml"
    - "--storage.path=/alertmanager"
  ports:
    - "127.0.0.1:9093:9093"
  networks:
    - monitoring
  healthcheck:
    test:
      [
        "CMD",
        "wget",
        "--quiet",
        "--tries=1",
        "--spider",
        "http://localhost:9093/-/healthy",
      ]
    interval: 30s
    timeout: 10s
    retries: 3
```

### Uso según entorno

```bash
# DESARROLLO — Prometheus + Grafana + exporters, SIN Alertmanager
make monitoring-up
# equivalente a:
docker compose -f docker-compose.monitoring.yml up -d

# PRODUCCIÓN — Stack completo CON Alertmanager
make monitoring-up-prod
# equivalente a:
docker compose -f docker-compose.monitoring.yml --profile prod-alerting up -d
```

### Añadir al Makefile

```makefile
monitoring-up: ## Levanta el stack de monitoreo (sin Alertmanager)
	@$(PRINT) "$(BLUE)📊 Levantando stack de monitoreo (desarrollo)...$(RESET)"
	docker compose -f docker-compose.monitoring.yml up -d
	@$(PRINT) "$(GREEN)✅ Monitoreo activo:$(RESET)"
	@$(PRINT) "   Grafana:    http://localhost:$(PORT_GRAFANA:-3001)"
	@$(PRINT) "   Prometheus: http://localhost:$(PORT_PROMETHEUS:-9090)"
	@$(PRINT) "   Nota: Alertmanager desactivado en dev (usar monitoring-up-prod para producción)"

monitoring-up-prod: ## Levanta el stack completo CON Alertmanager (producción)
	@$(PRINT) "$(BLUE)📊 Levantando stack de monitoreo con Alertmanager...$(RESET)"
	@test -n "$$SLACK_WEBHOOK_URL" || (echo "❌ SLACK_WEBHOOK_URL no está configurada" && exit 1)
	docker compose -f docker-compose.monitoring.yml --profile prod-alerting up -d
	@$(PRINT) "$(GREEN)✅ Monitoreo completo activo con Alertmanager$(RESET)"
```

---

## 6. Variables de entorno requeridas

Añadir al `.env.example` y `.env.prod.example`:

```bash
# --- ALERTMANAGER (solo si usas docker-compose.monitoring.yml con --profile prod-alerting) ---
# Webhook de Slack para notificaciones de alertas
# Obtener en: https://api.slack.com/apps → Incoming Webhooks
# SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ
```

> **⚠️ Importante:** La variable `${SLACK_WEBHOOK_URL}` en `alertmanager.yml` no se interpola automáticamente por Docker. Hay dos opciones:

**Opción A — Usar `envsubst` antes de levantar (recomendado en CI/CD):**

```bash
# En el servidor antes de levantar el stack de monitoreo:
envsubst < monitoring/alertmanager.yml > monitoring/alertmanager.resolved.yml
# Y montar el archivo resuelto en docker-compose.monitoring.yml
```

**Opción B — Usar Docker secret para el webhook:**

```yaml
# docker-compose.monitoring.yml
alertmanager:
  environment:
    - SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}
  # En alertmanager.yml usar directamente el valor expandido por Docker
```

**Opción C (más simple) — Escribir el valor directamente en alertmanager.yml** (solo en servidor, no en repo):

```yaml
# monitoring/alertmanager.yml — EN EL SERVIDOR (no committear)
receivers:
  - name: "slack-devops"
    slack_configs:
      - api_url: "https://hooks.slack.com/services/TU/WEBHOOK/REAL"
```

---

## 7. Alertas configuradas — alerts.yml

El archivo `monitoring/alerts.yml` define las condiciones. Falta conectarlo en `prometheus.yml`:

```yaml
# monitoring/prometheus.yml — AÑADIR estas líneas
rule_files:
  - /etc/prometheus/alerts.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]
```

```yaml
# monitoring/docker-compose.monitoring.yml — prometheus debe montar alerts.yml
prometheus:
  volumes:
    - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - ./monitoring/alerts.yml:/etc/prometheus/alerts.yml:ro # ← AÑADIR
    - prometheus_data:/prometheus
```

**Alertas actuales en `alerts.yml`:**

| Alerta               | Condición                         | Severidad | Tiempo |
| -------------------- | --------------------------------- | --------- | ------ |
| `ServiceDown`        | `up == 0`                         | critical  | 1 min  |
| `HealthCheckFailing` | `nestjs_health_check_status == 0` | critical  | 2 min  |
| `HighCPU`            | CPU > 80%                         | warning   | 5 min  |
| `LowDiskSpace`       | Disco libre < 15%                 | warning   | 5 min  |
| `HighErrorRate`      | Errores 5xx > 5%                  | critical  | 3 min  |
| `SlowResponses`      | P95 > 2 segundos                  | warning   | 5 min  |

> **Nota sobre `alerts.yml`:** Faltan las etiquetas `labels:` en la mayoría de reglas. Añadirlas para que Alertmanager pueda enrutar correctamente:

```yaml
# monitoring/alerts.yml — corregido con labels
groups:
  - name: nombre_del_proyecto-infrastructure
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical # ← labels es requerido por Alertmanager
          team: devops
        annotations:
          summary: "Servicio {{ $labels.job }} caído"
          description: "El servicio {{ $labels.job }} lleva 1 minuto sin responder."
```

---

## 8. Añadir un canal de notificación nuevo

### Email (SMTP)

```yaml
# monitoring/alertmanager.yml
global:
  smtp_smarthost: "smtp.gmail.com:587"
  smtp_from: "alertas@tudominio.com"
  smtp_auth_username: "alertas@tudominio.com"
  smtp_auth_password: "${SMTP_PASSWORD}"

receivers:
  - name: "email-equipo"
    email_configs:
      - to: "devops@tudominio.com"
        subject: "[ALERTA] {{ .GroupLabels.alertname }}"
        body: "{{ range .Alerts }}{{ .Annotations.description }}{{ end }}"

  - name: "slack-devops"
    slack_configs:
      - api_url: "${SLACK_WEBHOOK_URL}"
        channel: "#devops-alerts"
        send_resolved: true
```

### Múltiples receptores con rutas

```yaml
# monitoring/alertmanager.yml — rutas por severidad
route:
  receiver: "slack-devops" # Default
  group_wait: 30s
  routes:
    - match:
        severity: critical
      receiver: "pagerduty-oncall" # Críticas van a PagerDuty (si aplica)
      continue: true # También notifica a slack-devops
    - match:
        severity: warning
      receiver: "slack-devops"
      repeat_interval: 8h
```

---

## 9. Probando que las alertas funcionan

```bash
# 1. Verificar que Alertmanager está corriendo y configurado
curl http://localhost:9093/-/healthy
# Respuesta: Alertmanager is Healthy.

# 2. Ver alertas activas en este momento
curl http://localhost:9093/api/v2/alerts | python3 -m json.tool

# 3. Forzar una alerta de prueba (requiere curl)
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": { "alertname": "TestAlert", "severity": "warning", "job": "test" },
    "annotations": { "summary": "Alerta de prueba — puedes ignorar" },
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }]'

# 4. Verificar en Slack que llegó la notificación
# 5. Marcar la alerta como resuelta (enviar endsAt)
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": { "alertname": "TestAlert", "severity": "warning", "job": "test" },
    "annotations": { "summary": "Alerta de prueba — resuelta" },
    "endsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }]'
```

---

## 10. Silenciar una alerta temporalmente

Útil durante mantenimientos planificados para evitar falsos positivos.

```bash
# Silenciar todas las alertas por 2 horas (via API)
curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "alertname", "value": ".*", "isRegex": true}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d "+2 hours" +%Y-%m-%dT%H:%M:%SZ)'",
    "createdBy": "devops",
    "comment": "Mantenimiento programado"
  }'

# O usar la UI de Alertmanager: http://localhost:9093
```

---

## 11. Referencia rápida de comandos

```bash
# Levantar monitoreo completo en producción (con Alertmanager)
make monitoring-up-prod

# Levantar solo monitoreo básico en desarrollo (sin Alertmanager)
make monitoring-up

# Ver logs de Alertmanager
docker compose -f docker-compose.monitoring.yml logs alertmanager -f

# Recargar configuración sin reiniciar (requiere '--web.enable-lifecycle')
curl -X POST http://localhost:9093/-/reload

# Ver estado de todos los receptores
curl http://localhost:9093/api/v2/receivers | python3 -m json.tool

# Listar silenciados activos
curl http://localhost:9093/api/v2/silences | python3 -m json.tool
```
