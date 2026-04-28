# PERFORMANCE.md — Guía de Rendimiento

> **Última actualización:** Marzo 2026  
> Para configuración de recursos Docker, ver ADR-010 en DECISIONS.md.

---

## Configuración actual de recursos (single VPS)

| Servicio | CPU | RAM | Swap | Justificación |
|---|---|---|---|---|
| backend (NestJS) | 1.0 core | 1 GB | Sin swap (intencional) | NestJS estable en carga normal |
| frontend (Next.js) | 0.5 core | 512 MB | Sin swap | Standalone es liviano |
| reports-api (Flask) | 2.0 cores | 2 GB | Sin swap | Pandas puede usar varios GB |
| PostgreSQL (host) | ~0.5 | ~512 MB | Sistema | Gestión directa del OS |

**Servidor mínimo recomendado:** 4 vCPU / 8 GB RAM  
**Servidor recomendado actual:** 6 vCPU / 8 GB RAM (margen para próximos 6 meses)

> `memswap_limit == mem_limit` → Swap = 0. Si el contenedor alcanza el límite, el proceso se mata
> (OOM kill) en lugar de hacer swap. Es intencional: evita degradación lenta que es difícil de detectar.

---

## Monitorear uso real

```bash
# Ver uso en tiempo real
docker stats

# Ver uso puntual (sin actualización continua)
docker stats --no-stream

# Ver límites configurados
docker inspect nombre_del_proyecto_api | grep -A8 Memory
docker inspect nombre_del_proyecto_web | grep -A8 Memory
docker inspect nombre_del_proyecto_reports | grep -A8 Memory

# Ver OOM kills (contenedor matado por falta de memoria)
dmesg | grep -i "oom\|killed"
docker inspect nombre_del_proyecto_reports | grep OOMKillDisable
```

---

## Ajustar límites según el servidor

### VPS pequeño (2 cores / 4 GB)

```yaml
# docker-compose.prod.yml
backend:
  mem_limit: 512m
  memswap_limit: 512m
  cpus: "0.5"

frontend:
  mem_limit: 256m
  memswap_limit: 256m
  cpus: "0.3"

reports-api:
  mem_limit: 1g
  memswap_limit: 1g
  cpus: "0.9"
```

### VPS grande (8 cores / 16 GB)

```yaml
backend:
  mem_limit: 2g
  memswap_limit: 2g
  cpus: "2.0"

frontend:
  mem_limit: 1g
  memswap_limit: 1g
  cpus: "1.0"

reports-api:
  mem_limit: 4g
  memswap_limit: 4g
  cpus: "4.0"
```

---

## Rendimiento del pool de conexiones DB

### TypeORM / NestJS (backend)

```typescript
// backend/src/config/database.config.ts — valores actuales
extra: {
  max: 10,                      // conexiones simultáneas máximas
  idleTimeoutMillis: 30_000,    // cerrar conexión inactiva tras 30s
  connectionTimeoutMillis: 3_000, // fallar si no conecta en 3s
}
```

**Cuándo ajustar `max`:**
- Con tráfico bajo (< 50 usuarios concurrentes): `max: 5` es suficiente
- Con tráfico medio (50-200): `max: 10` (valor actual)
- Con tráfico alto (200+): `max: 20` + revisar PostgreSQL `max_connections`

> PostgreSQL tiene un límite de `max_connections` (por defecto 100). La suma de
> `max` de todos los servicios no debe superar ese límite.

### SQLAlchemy / Flask (reports-api)

```python
# reports/main.py — valores actuales
engine = create_engine(
    DATABASE_URL,
    pool_size=5,         # conexiones base por worker de Gunicorn
    max_overflow=10,     # conexiones extra en pico
    pool_timeout=10,     # esperar 10s antes de fallar
    pool_recycle=1800,   # reciclar conexiones cada 30 min (evita conexiones muertas)
    pool_pre_ping=True   # verifica que la conexión está viva antes de usarla
)
```

**Nota Gunicorn:** Con `--threads 4` (4 threads en 1 worker), el pool de cada proceso
tiene `pool_size=5` conexiones disponibles. Total máximo: `5 + 10 = 15` conexiones desde reports.

---

## Rendimiento de Gunicorn (reports-api)

```
--worker-class gthread  # Hilos dentro de un proceso (I/O concurrente)
--threads 4             # 4 hilos simultáneos
--timeout 300           # Máximo 5 min por request (reportes grandes)
--max-requests 200      # Reiniciar worker después de 200 requests (previene memory leaks)
--worker-tmp-dir /dev/shm  # Heartbeats en RAM (más rápido que disco)
```

**Señales de que necesitas más threads:**
```bash
# Ver si hay timeouts de Gunicorn (CRITIC WORKER TIMEOUT)
docker logs nombre_del_proyecto_reports | grep -i "timeout\|worker"

# Ver tiempo promedio de respuesta
docker logs nombre_del_proyecto_reports | grep "GET\|POST" | awk '{print $NF}'
```

---

## Caché de Next.js

Next.js en modo standalone genera caché en memoria por defecto. Si los arranques son lentos:

```yaml
# docker-compose.override.yml — ya configurado
volumes:
  - frontend_next:/usr/src/app/.next  # Caché persistente entre reinicios
```

En producción, la caché de Next.js vive en la imagen construida — no hay caché de disco en runtime
(salvo que lo configures explícitamente). El `start_period: 90s` en el healthcheck da tiempo
para el primer arranque.

---

## Nginx como proxy de alto rendimiento

```nginx
# Añadir a cada bloque server en /etc/nginx/sites-available/nombre_del_proyecto
# Compresión gzip para archivos estáticos del frontend
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

# Cache de archivos estáticos de Next.js
location /_next/static/ {
    proxy_pass http://127.0.0.1:3000;
    proxy_cache_valid 200 365d;
    add_header Cache-Control "public, max-age=31536000, immutable";
}
```

---

## Señales de alerta (cuando revisar recursos)

| Señal | Causa probable | Acción |
|---|---|---|
| OOM kill en reports | Dataset > 2 GB en RAM | Aumentar `mem_limit` a 4g |
| CPU 100% sostenido | Pandas en reportes grandes | Implementar queue de tareas |
| Response time > 2s en backend | Pool de DB lleno | Aumentar `max` en extra pool |
| Health check timeout | Servicio bajo memoria | Ver `docker stats` |
| Nginx 502 Bad Gateway | Contenedor no healthy aún | Ver `start_period` del healthcheck |

---

## Benchmarking básico

```bash
# Probar throughput del backend (instalar wrk o ab)
wrk -t2 -c10 -d30s http://localhost:4000/health

# Apache Bench
ab -n 1000 -c 10 http://localhost:4000/health

# Ver latencia de PostgreSQL desde el contenedor
docker compose exec backend sh -c "time psql \$DATABASE_URL -c 'SELECT 1'"
```
