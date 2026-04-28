# docs/MONITORING-ROADMAP.md — Guía para añadir Prometheus + Grafana

**Estado:** ✅ Stack implementado — ver `docker-compose.monitoring.yml`
**Alertmanager:** ✅ Configurado con profile `prod-alerting` — solo en producción
**Loki/Promtail:** 🔲 Pendiente — documentado en `docs/guides/MONITORING-LOKI-PROMTAIL.md`
**Métricas de negocio:** 🔲 Pendiente — documentar en guide antes de implementar
**Impacto:** Alta visibilidad del sistema en tiempo real  

---

## Qué vas a tener al final

```
[Browser] → http://servidor:3001   →  Grafana (dashboards)
                                       ↑ lee
[Prometheus :9090] ← scrapea cada 30s → [Backend   :4000/metrics]
                                       → [Reports   :5000/metrics]
                                       → [Node Exporter (CPU/RAM host)]
                                       → [cAdvisor  (Docker containers)]
```

---

## Paso 1: Exponer métricas en NestJS

```bash
# En el directorio backend/
pnpm add @willsoto/nestjs-prometheus prom-client
```

```typescript
// src/app.module.ts
import { PrometheusModule } from '@willsoto/nestjs-prometheus';

@Module({
  imports: [
    PrometheusModule.register({
      defaultMetrics: { enabled: true },  // CPU, memoria, event loop
      path: '/metrics',                    // endpoint scrapeado por Prometheus
    }),
  ],
})
export class AppModule {}
```

Después de esto, `GET http://localhost:4000/metrics` devuelve métricas en formato Prometheus.

---

## Paso 2: Exponer métricas en Flask (Reports)

```python
# reports/main.py — añadir
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time

# Métricas personalizadas
REQUEST_COUNT = Counter('reports_requests_total', 'Total requests', ['method', 'endpoint'])
REQUEST_LATENCY = Histogram('reports_request_duration_seconds', 'Request duration', ['endpoint'])

@app.before_request
def before_request():
    request._start_time = time.time()

@app.after_request
def after_request(response):
    duration = time.time() - request._start_time
    REQUEST_COUNT.labels(request.method, request.path).inc()
    REQUEST_LATENCY.labels(request.path).observe(duration)
    return response

@app.route('/metrics')
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}
```

```
# Añadir a requirements.in:
prometheus-client>=0.19
```

---

## Paso 3: Configuración de Prometheus

```yaml
# monitoring/prometheus.yml
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'nombre_del_proyecto-backend'
    static_configs:
      - targets: ['host-gateway:4000']   # NestJS
    metrics_path: /metrics

  - job_name: 'nombre_del_proyecto-reports'
    static_configs:
      - targets: ['host-gateway:5000']   # Flask
    metrics_path: /metrics

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']  # CPU/RAM del servidor host

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']       # Métricas de contenedores Docker
```

---

## Paso 4: docker-compose.monitoring.yml

Crear este archivo en la raíz del proyecto. Se levanta **separado** del stack principal:

```yaml
# docker-compose.monitoring.yml
# ══════════════════════════════════════════════════════════════════════════════
# Stack de monitoreo: Prometheus + Grafana + exporters
# NO incluir en docker-compose.prod.yml — levantar por separado:
#   docker compose -f docker-compose.monitoring.yml up -d
# ══════════════════════════════════════════════════════════════════════════════

services:

  # ── Prometheus: recolecta métricas ────────────────────────────────────────
  prometheus:
    image: prom/prometheus:v2.50.1@sha256:e3bdd6a5f24fdf6e22ee7c8c3c7e97e7a5f57c1f24ded43b12c6b37f08f2bfad
    container_name: nombre_del_proyecto_prometheus
    restart: unless-stopped
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'    # Conservar 30 días de métricas
      - '--web.enable-lifecycle'
    ports:
      - "127.0.0.1:9090:9090"   # Solo accesible desde localhost (via Nginx si se quiere público)
    extra_hosts:
      - "host-gateway:host-gateway"
    networks:
      - monitoring

  # ── Grafana: dashboards ────────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:10.3.3@sha256:1ebb3d16e54b56a5f9be56cf6f5e81f27f3e9b69a4ed81af97cf99e394562c4e
    container_name: nombre_del_proyecto_grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD_FILE=/run/secrets/grafana_password
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=http://localhost:3001
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "127.0.0.1:3001:3000"   # Grafana en puerto 3001 (3000 es el frontend)
    secrets:
      - grafana_password
    networks:
      - monitoring
    depends_on:
      - prometheus

  # ── Node Exporter: métricas del servidor host ──────────────────────────────
  node-exporter:
    image: prom/node-exporter:v1.7.0@sha256:4cb2b9019f1757be8482419002cb7afe028fdba35d47958829e4cfeaf6246d80
    container_name: nombre_del_proyecto_node_exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring

  # ── cAdvisor: métricas de contenedores Docker ─────────────────────────────
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1@sha256:b3e8f6349e57e4cedc7e3f98f28a8de0f9b00e5427c9c8d50c7da42e3de3ab58
    container_name: nombre_del_proyecto_cadvisor
    restart: unless-stopped
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    networks:
      - monitoring

# ── Secretos ─────────────────────────────────────────────────────────────────
secrets:
  grafana_password:
    file: ./secrets/grafana_password.txt   # crear: echo "TU_PASSWORD" > secrets/grafana_password.txt

# ── Volúmenes ─────────────────────────────────────────────────────────────────
volumes:
  prometheus_data:
  grafana_data:

# ── Redes ─────────────────────────────────────────────────────────────────────
networks:
  monitoring:
    driver: bridge
```

---

## Paso 5: Configuración de Grafana (provisioning automático)

```
monitoring/
├── prometheus.yml
└── grafana/
    └── provisioning/
        ├── datasources/
        │   └── prometheus.yml   ← Conecta Grafana con Prometheus
        └── dashboards/
            └── dashboard.yml    ← Carga los dashboards automáticamente
```

```yaml
# monitoring/grafana/provisioning/datasources/prometheus.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

---

## Paso 6: Operación

```bash
# Crear password de Grafana
echo "tu_password_segura_aqui" > secrets/grafana_password.txt
chmod 600 secrets/grafana_password.txt

# Levantar el stack de monitoreo
docker compose -f docker-compose.monitoring.yml up -d

# Verificar que está corriendo
docker compose -f docker-compose.monitoring.yml ps

# Acceder:
# - Grafana:    http://tu-servidor:3001  (admin / tu_password)
# - Prometheus: http://tu-servidor:9090  (solo interno)

# Ver logs si algo falla
docker compose -f docker-compose.monitoring.yml logs -f
```

---

## Targets del Makefile para monitoreo (añadir)

```makefile
monitoring-up: ## Levanta el stack de Prometheus + Grafana
	@$(PRINT) "$(BLUE)📊 Levantando stack de monitoreo...$(RESET)"
	docker compose -f docker-compose.monitoring.yml up -d
	@$(PRINT) "$(GREEN)✅ Monitoreo activo:$(RESET)"
	@$(PRINT) "   Grafana:    http://localhost:3001"
	@$(PRINT) "   Prometheus: http://localhost:9090"

monitoring-down: ## Detiene el stack de monitoreo
	docker compose -f docker-compose.monitoring.yml down

monitoring-logs: ## Logs del stack de monitoreo
	docker compose -f docker-compose.monitoring.yml logs -f
```

---

## Dashboards recomendados en Grafana

Importar desde grafana.com (ID numérico):

| Dashboard | ID | Descripción |
|---|---|---|
| Node Exporter Full | 1860 | CPU, RAM, disco, red del servidor |
| Docker Container Metrics | 11600 | Métricas de contenedores via cAdvisor |
| NestJS + Node.js | 11956 | Event loop, memory heap, requests |

Para importar: Grafana → Dashboards → Import → pegar el ID.

---

## Notas importantes

- **No incluir** `docker-compose.monitoring.yml` en el CI/CD habitual — es opcional para producción
- **Costos de recursos:** Prometheus + Grafana usan ~200MB RAM adicionales
- **Retención:** 30 días de métricas en disco (~1-5GB según carga)
- **Seguridad:** Grafana expuesto en `127.0.0.1:3001`, acceder via Nginx con autenticación si se quiere público
