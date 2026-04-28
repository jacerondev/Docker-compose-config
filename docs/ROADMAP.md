# ROADMAP.md — Hoja de Ruta del Proyecto

> **Última actualización:** Marzo 2026  
> Este roadmap es orientativo. Las prioridades pueden cambiar según el negocio.

---

## Estado Actual — Plantilla Empresarial Base

```
✅ Listo para producción:
  - Infraestructura Docker (3 servicios)
  - CI/CD con GitHub Actions
  - Hardening de contenedores (enterprise grade)
  - Stack de monitoreo (Prometheus + Grafana)
  - Pipeline de auditoría de seguridad (trivy, hadolint, SBOM)
  - Gestión de secretos con Docker Secrets
  - Backup cifrado con AES-256

🔶 Esqueleto implementado (lógica pendiente):
  - Auth endpoints (guard activo, devuelve usuario mock)
  - Reports API (estructura Flask lista)
  - Frontend (página de ejemplo)

❌ Pendiente de implementar:
  - AuthService con JWT real
  - Lógica de negocio del Backend
  - Lógica de negocio del Frontend
  - Lógica de reportes (Pandas)
```

---

## Fase 1 — Autenticación Real (Prioridad Alta)

**Objetivo:** Implementar JWT real con base de datos.

- [ ] Implementar `AuthService` en `backend/src/auth/auth.service.ts`
  - `register()` — hashear contraseña con argon2, guardar en User entity
  - `login()` — validar credenciales, emitir access + refresh token
  - `refreshTokens()` — validar refresh token, emitir nuevo access token
- [ ] Crear entity `User` con TypeORM
- [ ] Crear `JwtStrategy` (passport-jwt) en `backend/src/auth/strategies/`
- [ ] Activar JWT real en `JwtAuthGuard` (descomentar `AuthGuard('jwt')`)
- [ ] Implementar revocación de refresh tokens (Redis o tabla DB)
- [ ] Exponer `/metrics` de Prometheus solo con autenticación básica HTTP

**Tiempo estimado:** 2-3 sprints

---

## Fase 2 — Lógica de Negocio (Prioridad Media)

**Objetivo:** Implementar la lógica específica del negocio.

- [ ] Definir entidades de dominio (según el negocio)
- [ ] Implementar módulos NestJS de negocio
- [ ] Implementar rutas Flask para reportes Excel/PDF
- [ ] Construir UI en Next.js
- [ ] Implementar tests de integración

---

## Fase 3 — Observabilidad (Prioridad Media)

**Objetivo:** Visibilidad completa del sistema en producción.

- [ ] Activar stack de monitoreo: `make monitoring-up`
- [ ] Configurar `monitoring/alerts.yml` con reglas de alerta
- [ ] Configurar Alertmanager con Slack webhook
- [ ] Implementar métricas de negocio en NestJS (`@willsoto/nestjs-prometheus`)
- [ ] Crear dashboards en Grafana para métricas de negocio
- [ ] Implementar Loki + Promtail para logs centralizados (ver `guides/MONITORING-LOKI-PROMTAIL.md`)
- [ ] Activar Healthcheck Nivel 2 (`/health` con `SELECT 1` a PostgreSQL)

---

## Fase 4 — Seguridad Avanzada (Prioridad Media)

**Objetivo:** Reducir superficie de ataque.

- [ ] Implementar CSP con nonces en Next.js (eliminar `unsafe-inline`)
- [ ] Proteger `/metrics` con JWT guard específico
- [ ] Añadir rate limiting por usuario autenticado (además de por IP)
- [ ] Implementar rotación automática de secretos con crontab
- [ ] SBOM como parte del proceso de release
- [ ] Implementar multi-stage builds para desarrollo (hot reload en contenedor)

---

## Fase 5 — Escala y Madurez (Prioridad Baja)

**Objetivo:** Preparar para mayor tráfico.

- [ ] Migrar backend a Fastify si se supera 10k req/seg
- [ ] Evaluar Redis para caché y session store
- [ ] Implementar queue de tareas para reportes largos (Bull/Celery)
- [ ] Configurar PostgreSQL con réplica de lectura
- [ ] CDN para assets estáticos del frontend

---

## Cuándo reconsiderar la arquitectura

| Señal | Acción recomendada |
|---|---|
| > 10 servicios | Evaluar K3s/Kubernetes (ver ADR-012) |
| > 1000 usuarios concurrentes | Escalar horizontalmente, balanceador de carga |
| Equipo DevOps dedicado | Adoptar Terraform + Kubernetes |
| Múltiples regiones | Arquitectura multi-región con CDN |
| > 50 req/s en reports | Implementar queue de tareas (Celery + Redis) |

---

## Decisiones técnicas futuras a evaluar

| Tema | Estado | ADR |
|---|---|---|
| PostgreSQL → servicio cloud (RDS, Supabase) | Evaluación futura | (pendiente ADR-019) |
| Nginx → Caddy (auto-SSL, más simple) | Evaluación futura | (pendiente ADR-020) |
| Flask → FastAPI (async, mejor rendimiento) | Evaluación futura | Ver ADR-001 |
| Redis para invalidación de tokens | Necesario con Auth real | Ver `guides/BACKEND-NESTJS.md §15` |
