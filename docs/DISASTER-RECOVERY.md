# DISASTER-RECOVERY.md — Plan de Recuperación ante Desastres

**Proyecto:** NOMBRE_DEL_PROYECTO  
**Última actualización:** Febrero 2026  
**Propietario:** DevOps / Tech Lead  

> Revisar y actualizar cada 3 meses o después de cualquier incidente.

---

## Objetivos de Recuperación

| Métrica | Definición | Objetivo actual |
|---|---|---|
| **RTO** (Recovery Time Objective) | Tiempo máximo para restaurar el servicio | 2 horas |
| **RPO** (Recovery Point Objective) | Máxima pérdida de datos aceptable | 24 horas (último backup) |

---

## Escenarios y Runbooks

### Escenario 1: Contenedor caído (más común)

**Síntomas:** Un servicio no responde, `docker ps` muestra `(unhealthy)` o el contenedor no existe.

**Tiempo estimado de recuperación:** 2-5 minutos

```bash
# 1. Verificar estado
docker ps -a
make health-check

# 2. Ver los últimos logs del servicio caído
docker logs nombre_del_proyecto_api --tail=100   # o nombre_del_proyecto_web, nombre_del_proyecto_reports

# 3. Reiniciar el servicio específico
docker compose restart backend       # o frontend, reports-api

# 4. Si el contenedor no levanta, rebuild
docker compose up -d --build backend

# 5. Verificar que levantó correctamente
make wait-healthy
make health-check
```

---

### Escenario 2: Servidor reiniciado inesperadamente

**Síntomas:** Todos los contenedores caídos después de un reinicio del servidor.

**Tiempo estimado de recuperación:** 5-10 minutos

```bash
# Los contenedores tienen restart: unless-stopped — deben reiniciar solos
# Si no reiniciaron automáticamente:

# 1. Verificar estado
docker ps -a

# 2. Levantar todos los servicios
cd /opt/nombre_del_proyecto
make prod

# 3. Verificar
make wait-healthy
```

---

### Escenario 3: Error de deployment — rollback

**Síntomas:** El nuevo código rompe algo, los servicios están unhealthy.

**Tiempo estimado de recuperación:** 10-15 minutos

```bash
# 1. Identificar el tag anterior (el que funcionaba)
git tag --sort=-version:refname | head -5
# Ejemplo: v2026.02.20

# 2. Hacer rollback al tag anterior
cd /opt/nombre_del_proyecto
git checkout v2026.02.20

# 3. Redeploy
make prod

# 4. Verificar
make wait-healthy
make health-check

# 5. Documentar el incidente en CHANGELOG.md
```

---

### Escenario 4: Corrupción de datos / DELETE accidental

**Síntomas:** Datos faltantes o incorrectos en la aplicación.

**Tiempo estimado de recuperación:** 1-4 horas

```bash
# 1. PARAR los servicios para evitar más escrituras
docker compose -f docker-compose.yml -f docker-compose.prod.yml stop backend reports-api
# (frontend puede seguir sirviendo páginas estáticas)

# 2. Ver backups disponibles
ls -lht /opt/backups/

# 3. Hacer backup del estado actual ANTES de restaurar (por si necesitas comparar)
make backup-db  # guarda en /opt/backups/

# 4. Restaurar el backup del día anterior
make rollback-db
# O restaurar uno específico:
# pg_restore -U $DB_USER -d $DB_NAME /opt/backups/nombre_del_proyecto_2026-02-26_02-00.sql.gz

# 5. Verificar integridad de datos
docker exec nombre_del_proyecto_api psql -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM users;"
docker exec nombre_del_proyecto_api psql -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM reports;"

# 6. Reiniciar servicios
docker compose -f docker-compose.yml -f docker-compose.prod.yml start backend reports-api
make wait-healthy

# 7. Documentar: qué datos se perdieron, causa raíz, acción correctiva
```

---

### Escenario 5: Disco lleno

**Síntomas:** Servicios se cuelgan, logs dejan de escribirse, errores de disco.

**Tiempo estimado de recuperación:** 30 minutos

```bash
# 1. Verificar espacio
df -h
du -sh /var/lib/docker/
du -sh /opt/backups/
du -sh /var/log/

# 2. Limpiar recursos Docker no usados
docker system prune -f        # elimina contenedores parados, imágenes dangling, redes
docker volume prune -f        # elimina volúmenes no usados (¡cuidado!)
docker image prune -a -f      # elimina TODAS las imágenes no usadas (rebuild necesario)

# 3. Limpiar logs viejos de backup (conservar últimos 7 días)
find /opt/backups/ -name "*.sql.gz" -mtime +7 -delete
find /var/log/ -name "nombre_del_proyecto-backup.log*" -mtime +30 -delete

# 4. Verificar logs de Docker (pueden crecer mucho)
find /var/lib/docker/containers/ -name "*.log" | xargs ls -lh | sort -k5 -rh | head -10

# 5. Reiniciar servicios si se colgaron
make prod
```

---

### Escenario 6: Compromiso de secretos / credenciales expuestas

**Síntomas:** Actividad sospechosa en DB, secretos visibles en logs o código.

**Tiempo estimado de recuperación:** 1-2 horas

```bash
# 1. INMEDIATO: cambiar todas las credenciales
# Acceder al servidor de PostgreSQL y cambiar contraseñas:
psql -U postgres -c "ALTER ROLE db_user WITH PASSWORD 'NUEVA_CONTRASEÑA_FUERTE';"

# 2. Actualizar secretos en el servidor
echo "NUEVA_CONTRASEÑA_FUERTE" > /opt/nombre_del_proyecto/secrets/db_password.txt
chmod 400 /opt/nombre_del_proyecto/secrets/db_password.txt
chown root:root /opt/nombre_del_proyecto/secrets/db_password.txt

# 3. Actualizar JWT_SECRET si se expuso
# En GitHub Settings → Secrets → Actualizar JWT_SECRET
# En el servidor: reiniciar backend para forzar nuevos tokens

# 4. Reiniciar todos los servicios (invalida conexiones DB existentes)
make prod

# 5. Auditar: revisar logs de los últimos 7 días
docker compose logs backend --since 168h | grep -E "error|unauthorized|forbidden"

# 6. Si el servidor SSH se comprometió: cambiar SSH keys
# En GitHub Settings → Deploy keys → Revocar y añadir nueva
```

---

## Verificación del Plan (Drill Trimestral)

Ejecutar este checklist cada 3 meses para verificar que los runbooks funcionan:

```bash
# [ ] 1. Backup funciona
make backup-db
ls -lh /opt/backups/ | head -3

# [ ] 2. Restore funciona (en entorno de staging, nunca en producción directamente)
# Clonar la DB en un servidor de prueba y ejecutar rollback

# [ ] 3. Restart de contenedores funciona
docker compose restart backend
make wait-healthy

# [ ] 4. Rollback de código funciona
git log --oneline | head -5
# (no ejecutar en producción, solo verificar que el proceso es claro)

# [ ] 5. Secretos están configurados correctamente
make secrets-check

# [ ] 6. Cron job de backup está activo
make check-cron

# [ ] 7. Logs son accesibles
make logs-backend | head -20
```

---

## Contactos de Emergencia

| Rol | Responsabilidad en incidente |
|---|---|
| Tech Lead / DevOps | Escalado técnico, acceso SSH al servidor |
| Product Manager | Comunicación a usuarios, decisiones de negocio |
| DBA / Backend Dev | Consultas de restauración de datos específicos |

---

## Prevención: controles activos

| Control | Estado | Verificar |
|---|---|---|
| Backups automáticos diarios (cron 2am) | ⚠️ Pendiente `make setup-cron` | `make check-cron` |
| Backups guardados en `/opt/backups/` | ✅ `make backup-db` | `ls /opt/backups/` |
| restart: unless-stopped en todos los servicios | ✅ docker-compose.prod.yml | `docker ps` post-reboot |
| Alertas de disco lleno | ❌ Pendiente | Configurar con cron + df |
| Healthchecks Nivel 2 (DB check) | ⚠️ Pendiente | docs/IMPORTANTE-NESTJS |

---

### Escenario 5: Alertmanager no envía notificaciones a Slack

**Síntomas:** Hay alertas en Prometheus (rojo en la UI) pero no llegan mensajes a Slack.

**Tiempo estimado de recuperación:** 5-15 minutos

```bash
# 1. Verificar que Alertmanager está corriendo
make monitoring-ps
docker logs nombre_del_proyecto_alertmanager --tail=50

# 2. Verificar que Prometheus conecta con Alertmanager
# Ir a http://localhost:9090/status → sección "Alertmanagers"
# Debe mostrar: http://alertmanager:9093/api/v2/alerts — State: UP

# 3. Verificar que alertmanager.yml tiene la URL real (no la variable sin resolver)
docker exec nombre_del_proyecto_alertmanager cat /etc/alertmanager/alertmanager.yml
# Si muestra "${SLACK_WEBHOOK_URL}" sin resolver → problema de envsubst

# 4. Solución: volver a levantar con la URL resuelta
export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ
make monitoring-up-prod

# 5. Probar que llega la alerta
make monitoring-alert-test
```

**Causa más común:** `make monitoring-up` (sin `-prod`) levanta sin Alertmanager,
o `SLACK_WEBHOOK_URL` no estaba exportada cuando se ejecutó `make monitoring-up-prod`.

---

### Escenario 6: Token JWT inválido — usuarios no pueden iniciar sesión

**Síntomas:** Todos los usuarios reciben 401 tras un deploy o reinicio del backend.

**Tiempo estimado de recuperación:** 2-5 minutos

```bash
# Esto ocurre si JWT_SECRET cambió entre reinicios (cada deploy usa una nueva clave)

# 1. Verificar que JWT_SECRET está fijo en .env.production (no generado dinámicamente)
grep JWT_SECRET .env.production

# 2. Si usas Docker Secrets, verificar que el archivo existe y no está vacío
cat secrets/jwt_secret.txt

# 3. Reiniciar backend con la clave correcta
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart backend

# Los usuarios tendrán que volver a iniciar sesión — los tokens anteriores
# firmados con la clave anterior ya no son válidos.
```
