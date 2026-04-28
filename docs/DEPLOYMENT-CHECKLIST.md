# DEPLOYMENT CHECKLIST — NOMBRE_DEL_PROYECTO

Usar antes de cada deploy a producción. Copiar como issue de GitHub o ticket.

---

## PRE-DEPLOY (en local / CI)

### Código
- [ ] Tests pasando: `make test`
- [ ] Linting sin errores: `make lint`
- [ ] Type checking: `tsc --noEmit` en backend y frontend
- [ ] SBOM generado en CI (automático en push a main)
- [ ] Trivy sin CRITICAL/HIGH (automático en CI)
- [ ] PR aprobado por al menos 1 reviewer

### Variables de entorno
- [ ] `.env.production` actualizado con las URLs correctas
- [ ] `NEXT_PUBLIC_API_URL` apunta al dominio real (no localhost)
- [ ] `ALLOWED_ORIGINS` incluye el dominio de producción
- [ ] `NODE_ENV=production` y `APP_ENV=production`
- [ ] `SWAGGER_ENABLED` NO está en `.env.production` (o es `false`)

---

## EN EL SERVIDOR VPS

### Secrets
- [ ] `make secrets-init` ejecutado (primera vez)
- [ ] `secrets/db_password.txt` — contraseña PostgreSQL usuario principal
- [ ] `secrets/db_user.txt` — nombre del usuario PostgreSQL principal
- [ ] `secrets/db_read_only_password.txt` — contraseña PostgreSQL usuario solo lectura
- [ ] `secrets/db_read_only_user.txt` — nombre del usuario PostgreSQL solo lectura
- [ ] `secrets/jwt_secret.txt` — generado automáticamente con `openssl rand -base64 48`
- [ ] `secrets/cookie_secret.txt` — generado automáticamente con `openssl rand -hex 48`
- [ ] `secrets/pepper_secret.txt` — generado automáticamente con `openssl rand -base64 32` ⚠️ no rotar sin plan de migración de contraseñas
- [ ] `secrets/metrics_password.txt` — contraseña para endpoint /metrics (Prometheus)
- [ ] `make secrets-check` sin errores ni placeholders
- [ ] Permisos correctos: `chmod 700 secrets/ && chmod 600 secrets/*.txt`
- [ ] `ls -la secrets/` — verificar que permisos son 600 (no 644 ni 777)

### Base de datos
- [ ] PostgreSQL corriendo en el host: `pg_isready -h localhost`
- [ ] Usuario y base de datos creados
- [ ] `pg_hba.conf` tiene entrada para la red Docker (`172.17.0.0/16`)
- [ ] Migraciones ejecutadas: `make db-migrate` (o equivalente)
- [ ] **Backup pre-deploy realizado:** `make backup-db` (OBLIGATORIO)
- [ ] Crontab de backup configurado: `sudo crontab -l | grep backup` (primer deploy)

### Nginx y red
- [ ] Configuración de Nginx actualizada (si cambió): `sudo nginx -t`
- [ ] SSL/TLS válido: `sudo certbot renew --dry-run`
- [ ] Nginx corriendo: `systemctl status nginx`
- [ ] Firewall activo con solo puertos 22, 80, 443: `sudo ufw status`

### Recursos del servidor
- [ ] Verificar cores disponibles: `nproc` (mínimo 4 para la config actual)
- [ ] Verificar RAM disponible: `free -h` (mínimo 6 GB libres)
- [ ] Verificar espacio en disco: `df -h /var/lib/docker` (mínimo 20 GB libres)

---

## DEPLOY

- [ ] `make prod` (validaciones + migraciones + up)
- [ ] Esperar: `watch -n 5 'docker ps --filter "health=healthy"'`
- [ ] Health check: `curl http://localhost:4000/health`
- [ ] Verificar en navegador que la app carga desde el dominio real

---

## POST-DEPLOY

- [ ] `docker stats --no-stream` — verificar que los 3 servicios tienen mem_limit aplicado
- [ ] Monitoreo activo (Grafana, si configurado): `make monitoring-up`
- [ ] Primera alerta de prueba funcionando en Slack/email
- [ ] CHANGELOG.md actualizado con la versión y cambios
- [ ] Tag de git creado: `git tag v$(date +%Y.%m.%d) && git push --tags`
- [ ] Comunicar al equipo que el deploy fue exitoso

---

## ROLLBACK (si algo falla)

- [ ] Ver `docs/guides/RUNBOOK-OPERACIONAL.md`
- [ ] `make stop`
- [ ] `make rollback-db` (restaurar la BD al backup pre-deploy)
- [ ] `git checkout <tag-anterior>` → `make prod`
- [ ] Documentar el incidente en CHANGELOG.md

---

## Referencias

- Gestión de secretos: [docs/SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md)
- Guía de actualización: [docs/UPGRADE.md](UPGRADE.md)
- Runbook operacional: [docs/guides/RUNBOOK-OPERACIONAL.md](guides/RUNBOOK-OPERACIONAL.md)
- Troubleshooting: [docs/guides/TROUBLESHOOTING.md](guides/TROUBLESHOOTING.md)