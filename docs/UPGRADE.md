# UPGRADE.md — Guía de Actualización y Versionado

> **Última actualización:** Marzo 2026  
> Ver ADR-017 en DECISIONS.md para la política de actualización de imágenes base.

---

## Política de Versionado

Este proyecto usa **CalVer** (Calendar Versioning): `YYYY.MM.DD`

```bash
# Crear un release
git tag v$(date +%Y.%m.%d)
git push origin v$(date +%Y.%m.%d)

# Si hay dos releases el mismo día
git tag v2026.03.15.1   # sufijo numérico
```

**¿Cuándo crear un tag?**
- Después de un deploy exitoso a producción
- Después de cambios significativos en infraestructura
- Siempre antes de actualizar `.env.production` en el servidor

---

## Actualizar la aplicación (código)

```bash
# En el servidor de producción
cd /opt/nombre_del_proyecto
git pull origin main

# Hacer backup de BD antes de cualquier deploy
make backup-db

# Redesplegar
make prod

# Verificar que todo está healthy
docker ps --filter "health=healthy"
make health-check
```

---

## Actualizar imágenes base Docker

Las imágenes base están fijadas con **digest SHA256** para builds reproducibles.
Renovate abre PRs automáticos semanalmente con los nuevos digests.

### Flujo automático (Renovate)

1. Renovate detecta un nuevo digest para `node:24-slim` o `python:3.12-slim`
2. Abre un PR con el diff en los `FROM` de los Dockerfiles
3. CI corre automáticamente (build + tests + trivy)
4. Tú revisas y apruebas el PR con los resultados del CI
5. El merge actualiza las imágenes base

### Actualización manual de digests

```bash
# Ver los digests actuales
make show-digests

# Obtener el nuevo digest de una imagen
docker pull node:24-slim
docker inspect node:24-slim --format '{{index .RepoDigests 0}}'
# Output: node@sha256:abc123...

# Actualizar en los Dockerfiles:
# - backend/.docker/Dockerfile.prod  (2 referencias FROM)
# - frontend/.docker/Dockerfile.prod  (3 referencias FROM)
# - reports/.docker/Dockerfile.prod   (2 referencias FROM)
```

---

## Actualizar dependencias Node.js (backend y frontend)

```bash
# Ver dependencias desactualizadas
cd backend && pnpm outdated
cd frontend && pnpm outdated

# Auditar vulnerabilidades (pnpm audit se ejecuta en CI automáticamente)
pnpm audit

# Actualizar una dependencia específica
pnpm update @nestjs/core@latest

# Actualizar todas las dependencias (con cuidado — puede haber breaking changes)
pnpm update
```

---

## Actualizar dependencias Python (reports-api)

```bash
# Ver CVEs en dependencias actuales
make audit-requirements   # pip-audit

# El proyecto usa requirements.txt con hashes SHA256 para reproducibilidad
# Para actualizar a nuevas versiones:

# 1. Editar reports/requirements.in con la nueva versión deseada
nano reports/requirements.in

# 2. Regenerar requirements.txt con hashes
make update-requirements

# 3. Revisar el diff
git diff reports/requirements.txt

# 4. Rebuild y test
make build
```

---

## Actualizar PostgreSQL

> PostgreSQL corre en el host (fuera de Docker). La actualización es del SO.

```bash
# Ver versión actual
psql --version
sudo -u postgres psql -c "SELECT version();"

# Actualización menor (ej: 15.3 → 15.5) — sin cambio de schema
sudo apt update && sudo apt upgrade postgresql-15

# Actualización mayor (ej: 15 → 16) — requiere pg_upgrade
# Ver: https://www.postgresql.org/docs/current/pgupgrade.html
# PREREQUISITO: make backup-db antes de cualquier actualización mayor
```

---

## Rollback

```bash
# Ver commits recientes
git log --oneline -10

# Volver al commit anterior
make stop
make backup-db   # Siempre hacer backup antes
git checkout <COMMIT_ANTERIOR>
make prod

# O volver al tag anterior
git checkout v2026.03.01
make prod

# Verificar
docker ps --filter "health=healthy"
```

---

## Checklist de actualización

```
Pre-actualización:
- [ ] make backup-db  (siempre, sin excepción)
- [ ] git log --oneline -5  (anotar el commit actual para rollback)
- [ ] docker ps --filter "health=healthy"  (estado base)

Durante:
- [ ] git pull origin main
- [ ] make prod

Post-actualización:
- [ ] docker ps --filter "health=healthy"  (3 servicios healthy)
- [ ] curl https://api.tudominio.com/health
- [ ] make logs  (revisar errores en primeros 2 minutos)
- [ ] git tag v$(date +%Y.%m.%d)

Si algo falla:
- [ ] make stop && git checkout <tag-anterior> && make prod
```

---

## Deprecaciones y breaking changes a vigilar

| Versión | Cambio | Acción requerida |
|---|---|---|
| Node.js 24 LTS | Próxima versión LTS | Renovate abrirá PR automático |
| Python 3.13 | Nueva versión estable | Actualizar `FROM python:3.12-slim` |
| NestJS v11 | Cambios en decoradores | Revisar CHANGELOG de @nestjs/core |
| Next.js 15+ | App Router como default | Revisar guía de migración oficial |
| TypeORM 0.4 | API de migraciones cambia | Pendiente — seguir releases |
