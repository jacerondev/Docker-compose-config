# MONITORING-LOKI-PROMTAIL.md — Logs con Grafana Loki y Promtail

> **Referencia técnica viva.** Implementar cuando se quiera centralizar logs de todos los contenedores.
>
> Stack: Grafana Loki v2.9 · Promtail v2.9 · Grafana (ya en el stack)

---

## Índice

1. [Qué es Grafana Loki y por qué no es Elasticsearch](#1-qué-es-grafana-loki-y-por-qué-no-es-elasticsearch)
2. [Arquitectura completa: Promtail → Loki → Grafana](#2-arquitectura-completa-promtail--loki--grafana)
3. [Qué es Promtail y por qué es necesario](#3-qué-es-promtail-y-por-qué-es-necesario)
4. [Añadir Loki y Promtail al docker-compose.monitoring.yml](#4-añadir-loki-y-promtail-al-docker-composemonitoringyml)
5. [Configuración de Promtail — promtail.yml](#5-configuración-de-promtail--promtailyml)
6. [Configuración de Loki — loki.yml](#6-configuración-de-loki--lokiyml)
7. [Conectar Grafana con Loki (datasource)](#7-conectar-grafana-con-loki-datasource)
8. [Prerequisito: logs en formato JSON en los servicios](#8-prerequisito-logs-en-formato-json-en-los-servicios)
9. [Consultas LogQL en Grafana](#9-consultas-logql-en-grafana)
10. [ELK Stack como alternativa — cuándo y por qué](#10-elk-stack-como-alternativa--cuándo-y-por-qué)
11. [Decisión del proyecto: Loki vs ELK](#11-decisión-del-proyecto-loki-vs-elk)

---

## 1. Qué es Grafana Loki y por qué no es Elasticsearch

**Loki** es un sistema de agregación de logs diseñado por Grafana Labs con una premisa diferente:
- **Elasticsearch** indexa el contenido completo de cada log → búsquedas potentes pero muy costosas en CPU y RAM
- **Loki** solo indexa las *etiquetas* (labels) del log, no su contenido → mucho más eficiente, menor coste

```
Log de ejemplo:
{"level":"error","time":"2026-03-10T10:30:15Z","service":"backend","userId":"u42","msg":"DB timeout"}

Loki indexa SOLO:
  service=backend   ← etiqueta
  level=error       ← etiqueta extraída

El contenido ("DB timeout", "userId") se comprime y almacena sin indexar.
Para buscarlo, Loki usa full-scan en el tiempo seleccionado (rápido con ventanas pequeñas).
```

**Resultado en recursos para este proyecto (3 servicios, VPS único):**

| Sistema | RAM necesaria | CPU | Cuándo usarlo |
|---|---|---|---|
| **Loki** | ~100-200 MB | Bajo | 1-50 servicios, VPS único, equipo pequeño |
| **Elasticsearch** | 1-4 GB mínimo | Alto | 50+ servicios, búsquedas full-text avanzadas |

Loki es la elección correcta para esta arquitectura.

---

## 2. Arquitectura completa: Promtail → Loki → Grafana

```
Contenedores Docker
  ↓ escriben a stdout/stderr
Docker daemon
  ↓ almacena en /var/lib/docker/containers/<id>/<id>-json.log
Promtail (agente)
  ↓ lee esos archivos de log continuamente
  ↓ añade etiquetas (container_name, service, etc.)
  ↓ envía a Loki via HTTP
Loki (almacenamiento)
  ↓ comprime + indexa etiquetas
  ↓ expone API de consultas LogQL
Grafana
  ↓ consulta Loki con LogQL
  ↓ muestra logs en dashboards y Explore
```

**Flujo concreto para el proyecto:**

```
nombre_del_proyecto_api (backend)    → /var/lib/docker/containers/... → Promtail → Loki → Grafana
nombre_del_proyecto_web (frontend)   → /var/lib/docker/containers/... → Promtail → Loki → Grafana
nombre_del_proyecto_reports          → /var/lib/docker/containers/... → Promtail → Loki → Grafana
```

---

## 3. Qué es Promtail y por qué es necesario

**Promtail** es el agente recolector de logs de Loki. Corre como sidecar o como contenedor separado y:

1. Descubre automáticamente los archivos de log de los contenedores Docker
2. Lee los logs línea a línea en tiempo real
3. Enriquece cada línea con etiquetas (nombre del contenedor, nombre del servicio, etc.)
4. Los envía a Loki

Sin Promtail, los logs quedarían en los archivos de Docker sin ser recogidos.

**Alternativas a Promtail:**

| Agente | Cuándo usarlo |
|---|---|
| **Promtail** | Configuración más simple, integración nativa con Loki |
| **Alloy** (sucesor de Promtail) | Proyectos nuevos — Grafana lo recomienda como reemplazo futuro |
| **Fluentd/Fluent Bit** | Cuando ya tienes Fluentd en el stack, o necesitas enviar a múltiples destinos |
| **Vector** | Alternativa de alto rendimiento, soporte multi-destino |

Para este proyecto, **Promtail** es la elección correcta: simple, bien documentado, integración directa con el stack de Grafana ya existente.

---

## 4. Añadir Loki y Promtail al docker-compose.monitoring.yml

```yaml
# docker-compose.monitoring.yml — añadir estos servicios

  # ── Loki: almacenamiento y consultas de logs ───────────────────────────────
  loki:
    image: grafana/loki:2.9.4
    container_name: nombre_del_proyecto_loki
    restart: unless-stopped
    volumes:
      - ./monitoring/loki.yml:/etc/loki/local-config.yaml:ro
      - loki_data:/loki
    command: -config.file=/etc/loki/local-config.yaml
    ports:
      - "127.0.0.1:3100:3100"   # Solo localhost — Promtail y Grafana lo usan internamente
    networks:
      - monitoring
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3100/ready"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ── Promtail: agente recolector de logs ───────────────────────────────────
  # Lee logs de todos los contenedores Docker y los envía a Loki
  promtail:
    image: grafana/promtail:2.9.4
    container_name: nombre_del_proyecto_promtail
    restart: unless-stopped
    volumes:
      - ./monitoring/promtail.yml:/etc/promtail/config.yml:ro
      # Promtail necesita leer los archivos de log de Docker del HOST
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    command: -config.file=/etc/promtail/config.yml
    networks:
      - monitoring
    depends_on:
      loki:
        condition: service_healthy

# Añadir a la sección volumes:
volumes:
  prometheus_data:
  grafana_data:
  loki_data:       # ← añadir
  alertmanager_data:  # ← añadir si usas Alertmanager
```

**Grafana debe estar configurado como dependencia de Loki:**
```yaml
# docker-compose.monitoring.yml — actualizar grafana
grafana:
  depends_on:
    prometheus:
      condition: service_healthy
    loki:                          # ← añadir
      condition: service_healthy
```

---

## 5. Configuración de Promtail — promtail.yml

```yaml
# monitoring/promtail.yml — crear este archivo
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml   # Guarda dónde quedó leyendo cada archivo

clients:
  - url: http://loki:3100/loki/api/push

scrape_configs:
  # ── Logs de todos los contenedores Docker ────────────────────────────────
  - job_name: docker-containers
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 15s
        filters:
          - name: status
            values: ["running"]   # Solo contenedores que están corriendo
    relabel_configs:
      # Usar el nombre del contenedor como etiqueta "container"
      - source_labels: ['__meta_docker_container_name']
        target_label: container
        regex: '/(.*)'
        replacement: '$1'

      # Extraer el nombre del servicio (nombre_del_proyecto_api → backend)
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: service

      # Añadir el nombre del proyecto de compose como etiqueta
      - source_labels: ['__meta_docker_container_label_com_docker_compose_project']
        target_label: project

    # Pipeline para parsear JSON si los logs están en formato JSON
    pipeline_stages:
      - json:
          expressions:
            level: level          # Extraer campo "level" del JSON
            msg: msg
            timestamp: time
      - labels:
          level:                  # Añadir "level" como etiqueta Loki para filtrar
      - timestamp:
          source: timestamp
          format: RFC3339Nano
          fallback_formats:
            - RFC3339
            - "2006-01-02T15:04:05Z"
```

> **Nota sobre el socket Docker:** Para que Promtail pueda descubrir contenedores automáticamente, necesita acceso al socket `/var/run/docker.sock`. Añadir al `docker-compose.monitoring.yml`:
>
> ```yaml
> promtail:
>   volumes:
>     - ./monitoring/promtail.yml:/etc/promtail/config.yml:ro
>     - /var/log:/var/log:ro
>     - /var/lib/docker/containers:/var/lib/docker/containers:ro
>     - /var/run/docker.sock:/var/run/docker.sock:ro  # ← para auto-discovery
> ```

---

## 6. Configuración de Loki — loki.yml

```yaml
# monitoring/loki.yml — crear este archivo
auth_enabled: false   # Sin autenticación — Loki solo accesible desde la red monitoring

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://alertmanager:9093   # Conectar con Alertmanager

limits_config:
  retention_period: 744h   # 31 días de retención de logs
```

---

## 7. Conectar Grafana con Loki (datasource)

Añadir el datasource de Loki en el provisioning automático de Grafana:

```yaml
# monitoring/grafana/provisioning/datasources/loki.yml — crear este archivo
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false      # Prometheus sigue siendo el datasource principal
    editable: false
    jsonData:
      maxLines: 1000      # Máximo de líneas por consulta
      derivedFields:
        # Crear link desde un log de error al trace correspondiente (si usas tracing)
        # - name: TraceID
        #   matcherRegex: '"traceId":"(\w+)"'
        #   url: 'http://localhost:16686/trace/$${__value.raw}'
```

Grafana cargará este datasource automáticamente al levantar el stack.

---

## 8. Prerequisito: logs en formato JSON en los servicios

Para que Loki y Grafana puedan filtrar logs por campos (nivel, userId, etc.), los logs deben ser JSON.

**Backend NestJS:** Ver `docs/guides/BACKEND-NESTJS.md` §14 (nestjs-pino).

**Reports Flask:** Ver `docs/guides/REPORTS-PYTHON.md` §14 (structlog).

**Frontend Next.js:** Por defecto Next.js no tiene logs JSON en el servidor. Para producción, las excepciones de SSR irán al stderr del contenedor. Son suficientes para diagnóstico sin configuración extra.

**Verificar que los logs son JSON:**
```bash
# Ver los últimos logs del backend
docker logs nombre_del_proyecto_api --tail 5

# Salida esperada en producción (JSON):
# {"level":"info","time":1710062400,"msg":"Application running","port":4000}
# {"level":"info","time":1710062410,"msg":"request completed","req":{"url":"/health"},"res":{"statusCode":200}}

# Salida en desarrollo (pretty-print con pino-pretty):
# [Nest] LOG  [NestApplication] Application running on port 4000
```

---

## 9. Consultas LogQL en Grafana

Una vez Loki está activo y recibiendo logs, acceder en Grafana → Explore → Seleccionar datasource "Loki".

**Consultas básicas:**

```logql
# Todos los logs del backend
{service="backend"}

# Solo errores del backend
{service="backend"} | json | level="error"

# Logs de todos los servicios NOMBRE_DEL_PROYECTO
{project="docker-compose-config"}

# Errores en todos los servicios en los últimos 5 minutos
{project="docker-compose-config"} | json | level="error"

# Buscar un error específico
{service="backend"} |= "DB timeout"

# Logs de un usuario específico (solo si los logs incluyen userId)
{service="backend"} | json | userId="u42"

# Requests lentos (responseTime > 1000ms en formato JSON)
{service="backend"} | json | responseTime > 1000

# Tasa de errores por servicio (métrica derivada de logs)
rate({project="docker-compose-config"} | json | level="error" [5m])
```

**Dashboard recomendado:**
Importar "Grafana Loki Dashboard Quick Search" (ID: 12019) desde grafana.com.

---

## 10. ELK Stack como alternativa — cuándo y por qué

**ELK** = Elasticsearch + Logstash + Kibana. Es la alternativa más conocida a Loki.

### Diferencias fundamentales

| Aspecto | Grafana Loki | ELK Stack |
|---|---|---|
| **Índice** | Solo etiquetas (labels) | Contenido completo de cada log |
| **Búsqueda** | LogQL — eficiente en ventanas de tiempo | Query DSL — full-text search en cualquier campo |
| **RAM mínima** | ~100-300 MB | 2-4 GB solo para Elasticsearch |
| **CPU** | Bajo | Alto (indexación continua) |
| **Curva de aprendizaje** | Media (LogQL similar a PromQL) | Alta (Elasticsearch DSL, mappings, índices) |
| **Integración** | Nativa con Grafana (mismo stack) | Kibana separado (interfaz propia) |
| **Coste en VPS** | Viable en servidores de 4-8 GB RAM | Requiere servidores de 8-16 GB RAM dedicados |
| **Escalabilidad** | Escala bien con almacenamiento S3/GCS | Escala bien con cluster multi-nodo |
| **Análisis avanzado** | Básico (conteos, tasas, filtros) | Muy avanzado (ML, anomaly detection, APM) |

### Cuándo ELK tiene sentido

- **Volumen de logs muy alto:** 10+ GB/día de logs que necesitan búsqueda en cualquier campo
- **Búsquedas full-text complejas:** "encuentra todos los logs que contengan exactamente este error en cualquier campo"
- **Análisis de negocio en logs:** el equipo de BI usa Kibana para analizar patrones en logs
- **Equipo con experiencia en Elasticsearch:** la curva de aprendizaje ya está superada
- **Compliance y auditoría:** Elasticsearch tiene características de auditoría muy maduras
- **Más de 20-30 servicios** con logs de alta densidad

### Por qué NO usar ELK en este proyecto

```
VPS con 4-8 GB RAM:
├── Backend + Frontend + Reports:          ~3.5 GB RAM (configurado en prod)
├── Prometheus + Grafana + Loki + Promtail: ~500 MB
└── Sistema operativo + Nginx + PostgreSQL: ~1 GB
Total Loki: ~5 GB → viable en VPS de 8 GB

Con ELK:
├── Backend + Frontend + Reports:          ~3.5 GB RAM
├── Elasticsearch solo:                    ~2-4 GB RAM (mínimo recomendado)
├── Logstash:                              ~500 MB
├── Kibana:                                ~500 MB
└── Sistema operativo + Nginx + PostgreSQL: ~1 GB
Total ELK: ~8-10 GB → requiere VPS de 16 GB mínimo
```

### Configuración de referencia para ELK (si en el futuro aplica)

```yaml
# docker-compose.elk.yml — SOLO REFERENCIA, no implementado
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms1g -Xmx2g"
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
    mem_limit: 3g
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    ports:
      - "127.0.0.1:9200:9200"

  logstash:
    image: docker.elastic.co/logstash/logstash:8.12.0
    volumes:
      - ./monitoring/logstash/pipeline:/usr/share/logstash/pipeline:ro
    mem_limit: 1g
    depends_on: [elasticsearch]

  kibana:
    image: docker.elastic.co/kibana/kibana:8.12.0
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    ports:
      - "127.0.0.1:5601:5601"
    mem_limit: 1g
    depends_on: [elasticsearch]

  filebeat:  # Alternativa a Logstash para proyectos simples
    image: docker.elastic.co/beats/filebeat:8.12.0
    user: root
    volumes:
      - ./monitoring/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

---

## 11. Decisión del proyecto: Loki vs ELK

**Decisión: Grafana Loki.**

Esta decisión está alineada con el resto del stack de monitoreo (Prometheus, Grafana) y es la correcta para:

- VPS único con recursos limitados
- 3 servicios con logs de densidad moderada
- Equipo pequeño sin experiencia dedicada en Elasticsearch
- Integración directa con Grafana que ya está en el stack

**Cuándo reconsiderar a ELK:**
- El proyecto crece a 15+ servicios
- El VPS se actualiza a 32+ GB RAM con presupuesto para hardware dedicado de logs
- Se necesita APM (Application Performance Monitoring) completo con distributed tracing
- El equipo tiene un DevOps dedicado con experiencia en Elasticsearch

> **Referencia:** Ver `DECISIONS.md` para añadir un ADR-018 documentando esta decisión cuando se implemente el stack de logs.
