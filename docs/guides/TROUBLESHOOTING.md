# TROUBLESHOOTING — NOMBRE_DEL_PROYECTO

Problemas comunes y sus soluciones.

> Para diagnóstico interactivo: `make troubleshoot`

---

## Error: "Read-only file system" en contenedor

**Síntoma:** La app crashea con `EROFS: read-only file system` o similar.

**Causa:** `read_only: true` en `docker-compose.prod.yml`. El contenedor no puede escribir en rutas no declaradas en `tmpfs`.

**Solución:** Identificar la ruta y añadirla a `tmpfs`:

```bash
# Verificar qué ruta intenta escribir
docker logs nombre_del_proyecto_api --tail=50 | grep "read-only"

# Añadir la ruta en docker-compose.prod.yml:
tmpfs:
  - /tmp:size=64m,mode=1777
  - /run:size=10m,mode=755
  - /app/.cache:size=32m,mode=1777   # ← añadir la ruta que falla
```

---

## Error: "host-gateway" no funciona (DB no conecta)

**Síntoma:** `psycopg2.OperationalError: could not connect to server` o similar.

**Causa:** `host-gateway` requiere Docker 20.10+. En versiones anteriores o en algunas configuraciones de Linux, no resuelve correctamente.

**Solución:**

```bash
# 1. Verificar versión de Docker
docker version --format '{{.Server.Version}}'   # necesita 20+

# 2. Si la versión es OK pero falla, usar IP directa:
# En .env y .env.production cambiar:
DB_HOST=host-gateway
# Por:
DB_HOST=172.17.0.1   # IP del host en la red bridge de Docker
# O verificar la IP real:
ip route | grep docker | awk '{print $9}'
```

---

## Error: JWT_SECRET no encontrado al arrancar

**Síntoma:** Backend crashea con `JWT_SECRET_FILE no encontrado` o `JWT_SECRET no definida`.

**Solución:**

```bash
# En desarrollo: añadir al .env
JWT_SECRET=genera_con_openssl_rand_base64_48

# En producción: crear el archivo de secret
make secrets-init   # ya genera jwt_secret.txt con openssl
make secrets-check  # verificar que existe y no es placeholder

# Verificar que docker-compose.prod.yml tiene jwt_secret descomentado
grep -n "jwt_secret" docker-compose.prod.yml
```

---

## Error: Gunicorn timeout en reportes grandes

**Síntoma:** `CRITICAL WORKER TIMEOUT` en logs de reports-api. El reporte no se genera.

**Causa:** El timeout de Gunicorn (300s por defecto) se superó con un dataset muy grande.

**Solución:**

```bash
# Verificar el timeout actual en Dockerfile.prod de reports
grep "timeout" reports/.docker/Dockerfile.prod

# Si el reporte tarda más de 5 min, aumentar timeout:
CMD ["gunicorn", "--timeout", "600", ...]  # 10 minutos

# Alternativa: añadir paginación en el endpoint de reportes
# En lugar de generar todo de una vez, generar en chunks
```

---

## Error: internal:true impide que el contenedor descargue dependencias

**Síntoma:** `pnpm install` o `pip install` falla en el build porque no hay internet.

**Causa:** La red `nombre_del_proyecto-private` tiene `internal: true`, que bloquea salida a internet. Pero el build de Docker NO usa esa red — usa la red del host por defecto.

**Explicación:** `internal: true` solo aplica a contenedores en runtime (cuando están corriendo), no durante el `docker build`. Los builds siempre tienen acceso a internet a menos que uses `--network=none`.

**Si el problema persiste:**

```bash
# Verificar que el problema es de red, no de proxy
docker build --no-cache ./backend  # si funciona: era cache corrupto

# Si el servidor VPS tiene restricciones de red saliente, configurar proxy:
# En Dockerfile añadir:
ARG HTTP_PROXY
ARG HTTPS_PROXY
```

---

## Error: Contenedor no arranca - "unhealthy" inmediatamente

**Causa:** Falta `start_period` en el healthcheck. Docker empieza a contar reintentos antes de que el servicio esté listo.

**Solución:** Ver Punto 3 de esta guía — añadir `start_period: 60s` a los healthchecks en `docker-compose.prod.yml`.

---

## Error: Swagger muestra todos los endpoints aunque SWAGGER_ENABLED no está

**Causa:** `SWAGGER_ENABLED=true` está en el `.env` de desarrollo. En producción, verificar que no esté en `.env.production`.

```bash
grep SWAGGER_ENABLED .env.production  # no debe aparecer o debe ser false
```

### Nginx no levanta tras el deploy

```bash
sudo nginx -t                              # Verificar configuración — muestra el error exacto
sudo systemctl status nginx               # Estado del servicio
sudo tail -n 50 /var/log/nginx/error.log  # Log detallado de errores
# Errores frecuentes:
#   - "bind() failed (98: Address in use)" → otro proceso usa el puerto 80/443
#   - "No such file or directory" → ruta del proxy_pass incorrecta
#   - "SSL certificate" → problema con certbot
sudo lsof -i :80    # Ver qué proceso usa el puerto 80
sudo lsof -i :443   # Ver qué proceso usa el puerto 443
```

---

### SSL no funciona / certbot falla

```bash
# Probar renovación en modo dry-run:
sudo certbot renew --dry-run

# Verificar que el dominio resuelve correctamente:
dig api.tudominio.com
curl -v https://api.tudominio.com/health

# Si certbot falla con "Connection refused":
#   1. Temporalmente detener Nginx (certbot necesita el puerto 80 libre en modo standalone)
#   2. O usar el plugin nginx: certbot --nginx (recomendado)
sudo certbot --nginx -d api.tudominio.com --force-renewal
```

---

### Fail2ban no banea IPs / comportamiento inesperado

```bash
sudo fail2ban-client status sshd          # Ver IPs actualmente baneadas
sudo fail2ban-client status               # Ver todas las jails activas
sudo tail -n 50 /var/log/fail2ban.log     # Log de actividad

# Desbanear una IP manualmente (si te bloqueaste a ti mismo):
sudo fail2ban-client set sshd unbanip <TU_IP>

# Reiniciar fail2ban si no responde:
sudo systemctl restart fail2ban
sudo fail2ban-client ping                 # Debe responder "pong"
```

---

### Servicios no están healthy tras el deploy

```bash
# Ver estado de healthchecks:
docker ps --filter "health=healthy"
docker inspect nombre_del_proyecto_api | grep -A5 Health

# Ver logs del servicio con problema:
make logs-backend
make logs-frontend
make logs-reports

# El frontend puede tardar hasta 60s en ser healthy (start_period):
watch -n 5 'docker ps --filter "health=healthy"'

# Si un contenedor no llega nunca a healthy:
docker inspect nombre_del_proyecto_api | grep -A20 '"Health"'
```

---

### Recursos insuficientes — el servidor se queda sin RAM/CPU

```bash
# Ver uso actual de recursos:
docker stats --no-stream

# Ver límites configurados:
docker inspect nombre_del_proyecto_api | grep -A5 Memory
docker inspect nombre_del_proyecto_reports | grep -A5 Memory

# El servidor necesita al menos 4 cores y 4GB RAM para los límites actuales.
# Ver cores disponibles:
nproc

# Si el servidor tiene menos recursos, ajustar en docker-compose.prod.yml:
# backend:   mem_limit: 512m, cpus: "0.5"
# frontend:  mem_limit: 256m, cpus: "0.3"
# reports:   mem_limit: 1g,   cpus: "0.9"
```

---

### PostgreSQL — el backend no puede conectarse desde Docker

```bash
# En el servidor, verificar que PostgreSQL está corriendo:
sudo systemctl status postgresql

# Obtener la IP del gateway Docker (la IP que ven los contenedores para llegar al host):
docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
# Resultado típico: 172.17.0.1

# Verificar que pg_hba.conf permite conexiones desde esa IP:
sudo grep -n "172.17" /etc/postgresql/*/main/pg_hba.conf
# Si no hay línea, añadir:
# host  nombre_del_proyecto_db  user_prod  172.17.0.0/16  md5

# Verificar que postgresql.conf escucha en todas las interfaces:
sudo grep "^listen_addresses" /etc/postgresql/*/main/postgresql.conf
# Debe ser: listen_addresses = 'localhost'

# Después de cambios:
sudo systemctl restart postgresql

# Probar conectividad manualmente desde el contenedor:
docker compose exec backend sh -c "nc -zv 172.17.0.1 5432"
```

---

### Secretos — los contenedores no leen los secretos correctamente

```bash
# Verificar que los archivos de secretos existen:
make secrets-check

# Verificar que los secretos están montados dentro del contenedor:
docker compose exec backend ls -la /run/secrets/
# Debe mostrar: db_password, db_user, jwt_secret, cookie_secret, pepper_secret, metrics_password

# Verificar el contenido (solo en emergencia — no hacer en logs):
docker compose exec backend cat /run/secrets/db_password

# Si los secretos cambiaron, reiniciar para que los contenedores los relean:
make stop && make prod
```

---

### El backend no responde

```bash
curl http://localhost:4000/health
make logs-backend
# Si el contenedor no existe:
docker ps -a | grep nombre_del_proyecto_api
# Si el puerto está ocupado:
sudo lsof -i :4000
```

**Causas frecuentes:**

- El contenedor falló al arrancar — revisar `make logs-backend` para ver el error
- Puerto 4000 ya en uso por otro proceso
- `.env` sin `DB_HOST` definido — `make doctor` lo detecta

---

### El frontend muestra error 502 Bad Gateway

```bash
sudo nginx -t                              # Verificar configuración Nginx
sudo tail -n 50 /var/log/nginx/error.log  # Ver el error exacto
curl http://localhost:3000                 # Verificar que Next.js responde directamente
make logs-frontend
```

**Causa frecuente:** Nginx está corriendo pero el contenedor frontend no está healthy aún (puede tardar hasta 60s en el start_period del healthcheck).

---

### Errores de permisos en volúmenes o logs

```bash
make doctor    # Verifica tu UID (debe ser 1000)
id -u          # Tu UID actual
sudo chown -R 1000:1000 logs   # Corrección manual
```

> ℹ️ El proyecto asume UID 1000. Si tu usuario tiene otro UID, los volúmenes de Docker generarán errores de permisos.

---

### Los cambios en el código no se reflejan (hot reload no funciona)

```bash
# Opción 1: reiniciar el servicio específico
docker compose restart backend

# Opción 2: limpieza completa y restart
docker compose down -v && make dev

# Para reports (Python), verificar que Flask está en modo debug:
make logs-reports
```

---

### Secretos mal configurados en producción

```bash
make secrets-check    # Verifica que los 8 secretos esenciales existen y no son placeholder
make secrets-init     # Si no existen — crea los archivos template
ls -la secrets/       # Verificar permisos (deben ser 600)
```

---

### Puerto ya en uso

```bash
sudo lsof -i :4000    # Ver qué proceso usa el puerto del backend
sudo lsof -i :3000    # Frontend
sudo lsof -i :5000    # Reports
# Matar el proceso si es necesario:
sudo kill -9 <PID>
```

---

### El contenedor de reports no genera archivos

```bash
make logs-reports
docker compose exec reports-api ls -la /tmp   # Ver archivos temporales
# En dev, verificar que Flask está en modo debug con autoreload:
make logs-reports | grep "Restarting with"
```

---

### Build falla con error de permisos en Docker

```bash
# Asegurarse de que tu usuario está en el grupo docker:
groups | grep docker
sudo usermod -aG docker $USER
newgrp docker   # Aplicar sin reiniciar sesión
```

---

### Rollback rápido ante un deploy fallido

```bash
make stop                    # Detener los servicios con problema
make rollback-db             # Restaurar la BD al último backup
git checkout HEAD~1          # Volver al commit anterior
make prod                    # Redesplegar la versión anterior
```
