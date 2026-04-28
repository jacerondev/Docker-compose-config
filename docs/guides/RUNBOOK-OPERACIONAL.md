# RUNBOOK OPERACIONAL — NOMBRE_DEL_PROYECTO
**Propósito:** Procedimientos step-by-step para responder a alertas y resolver incidentes en producción.  
**Acceso rápido:** `ssh -i /path/key admin@TU_VPS_IP` → `cd /opt/nombre_del_proyecto`

---

## ACCESO RÁPIDO

| Tarea | Comando |
|---|---|
| Ver todos los servicios | `docker ps -a` |
| Ver logs en vivo | `make logs` |
| Estado de salud | `make health-check` |
| Reiniciar todo | `make prod` |
| Ver uso de recursos | `docker stats --no-stream` |

---

## ALERTA 1: Servicio Caído (backend / frontend / reports-api)

**Síntomas:**
- Prometheus: `up{job="nombre_del_proyecto-backend"} == 0`
- Grafana: panel rojo
- Nginx: 502 Bad Gateway a usuarios

**Diagnóstico (< 2 minutos):**
```bash
# 1. Ver qué está pasando
docker ps -a | grep nombre_del_proyecto

# 2. Ver los últimos 50 logs del servicio caído
docker logs nombre_del_proyecto_api --tail=50        # backend
docker logs nombre_del_proyecto_web --tail=50        # frontend
docker logs nombre_del_proyecto_reports --tail=50    # reports

# 3. Verificar healthcheck
curl -f http://127.0.0.1:4000/health && echo "OK" || echo "DOWN"
curl -f http://127.0.0.1:3000         && echo "OK" || echo "DOWN"
curl -f http://127.0.0.1:5000/health  && echo "OK" || echo "DOWN"
```

**Resolución rápida:**
```bash
# Reiniciar solo el servicio afectado
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart backend
# O con make:
make restart-backend   # si existe el target
```

**Si persiste (> 5 minutos):**
```bash
# Ver si hay error de memoria o disco
docker stats --no-stream
df -h

# Rebuild del servicio específico
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build backend

# Último recurso: rollback a tag anterior
git tag --sort=-version:refname | head -5
# Elegir el tag anterior y hacer deploy
```

**Escalación:** Si la BD está caída → contactar DBA. Si es disco lleno → contactar infra.

---

## ALERTA 2: Alto Uso de CPU (> 80% sostenido)

**Síntomas:** Prometheus: `cpu_usage_percent > 80`
```bash
# Identificar qué contenedor consume
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Si reports-api está al 100% (normal durante generación de reporte grande):
#   Esperar a que termine. Si lleva > 5 min, es un reporte bloqueado.
docker exec nombre_del_proyecto_reports ps aux

# Si backend está al 100%: posible loop infinito o query sin índice
docker logs nombre_del_proyecto_api --tail=100 | grep -i "error\|warn"
```

---

## ALERTA 3: Alto Uso de Memoria (> 85%)
```bash
# Ver uso por contenedor
docker stats --no-stream

# Si reports-api usa > 1.5G: reporte con dataset muy grande
# Reiniciar el worker de Gunicorn (el proceso reiniciará al completar max-requests=200):
docker exec nombre_del_proyecto_reports kill -SIGTERM 1

# Si backend usa > 800MB: posible memory leak
# Reiniciar contenedor (NestJS reinicia limpiamente):
docker compose restart backend
```

---

## ALERTA 4: Disco Lleno (> 85%)
```bash
# Ver uso de disco
df -h

# Limpieza de imágenes Docker antiguas (NO afecta contenedores activos)
docker image prune -f

# Rotar logs manualmente si está lleno de logs Docker
# Los logs están en /var/lib/docker/containers/*/
# El max-size: 10m debería evitar esto, pero verificar:
docker system df
docker system prune --volumes  # ⚠️ PELIGROSO: elimina volúmenes no usados
```

---

## ALERTA 5: Error Rate Elevado (> 5%)
```bash
# Ver logs de errores del backend
docker logs nombre_del_proyecto_api --tail=200 | grep -E "ERROR|500|502"

# Ver métricas de Prometheus
curl http://127.0.0.1:9090/metrics | grep http_requests_total

# Identificar endpoint con más errores en Grafana
# Dashboard → HTTP Errors → Top endpoints
```

---

## PROCEDIMIENTO: Rollback
```bash
# 1. Ver tags disponibles
git tag --sort=-version:refname | head -10

# 2. Hacer checkout del tag anterior
git checkout v2026.02.XX

# 3. Rebuild y deploy
make prod

# 4. Verificar
make wait-healthy
make health-check
```

---

## PROCEDIMIENTO: Backup Manual
```bash
# Backup inmediato (antes de cambios importantes)
make backup-db   # si el target existe
# O manualmente:
pg_dump -h host-gateway -U $(cat secrets/db_user.txt) \
        -d $(grep DB_NAME .env.production | cut -d= -f2) \
        | gzip > backup-manual-$(date +%Y%m%d-%H%M%S).sql.gz
```

---

## PROCEDIMIENTO: Restore de Backup
```bash
# 1. Verificar el backup
gunzip -t backup-FECHA.sql.gz && echo "Backup OK"

# 2. Detener la app para evitar writes durante restore
docker compose -f docker-compose.yml -f docker-compose.prod.yml stop backend reports-api

# 3. Restore
gunzip -c backup-FECHA.sql.gz | \
  psql -h host-gateway -U $(cat secrets/db_user.txt) \
       -d $(grep DB_NAME .env.production | cut -d= -f2)

# 4. Levantar de nuevo
make prod
make health-check
```