# Frontend — Dockerfiles

## Archivos

- `Dockerfile`      — Desarrollo con Next.js dev server y hot reload
- `Dockerfile.prod` — Producción optimizada (multi-stage, standalone output)

---

## Dockerfile (Desarrollo)

### Características
- Node.js 24 slim
- Usuario no-root `node` (UID 1000)
- Hot reload mediante volumen montado desde el host
- DevDependencies incluidas (`pnpm ci --include=dev`)

### Variables
- `PORT_FRONTEND` — Puerto interno que Next.js escucha (por defecto: 3000)

### Build manual (solo para pruebas, normalmente usa docker-compose)
```bash
docker build -f .docker/Dockerfile \
  --build-arg PORT_FRONTEND=3000 \
  -t nombre_del_proyecto_frontend_dev .
```

---

## Dockerfile.prod (Producción)

### Características
- **3 etapas:** `deps` → `builder` → `runner`
- Variables `NEXT_PUBLIC_*` compiladas en tiempo de build (baked-in)
- Output standalone de Next.js — mínima huella, sin node_modules en runner
- Usuario no-root `node` (UID 1000)
- `curl` instalado para los healthchecks de Docker

### Etapas

| Etapa    | Base          | Propósito                                              |
|----------|---------------|--------------------------------------------------------|
| `deps`   | node:24-slim  | Instala solo dependencias (`pnpm ci`)                  |
| `builder`| node:24-slim  | Copia deps, recibe ARGs públicos y ejecuta `pnpm run build` |
| `runner` | node:24-slim  | Copia solo el output standalone y archivos estáticos   |

### Variables de build (pasadas desde docker-compose.prod.yml)

| Variable                  | Cuándo se usa         | Ejemplo                        |
|---------------------------|-----------------------|--------------------------------|
| `PORT_FRONTEND`           | Runtime               | `3000`                         |
| `NEXT_PUBLIC_API_URL`     | Build (baked-in)      | `https://api.tudominio.com`    |
| `NEXT_PUBLIC_REPORTS_URL` | Build (baked-in)      | `https://reports.tudominio.com`|

> **Importante:** las variables `NEXT_PUBLIC_*` se incrustan en el bundle de JavaScript
> durante el build. Si cambias las URLs en `.env` debes hacer un nuevo build
> (`make prod` lo hace automáticamente).

### Requisito en next.config.js

Para que el output standalone funcione, el proyecto Next.js debe tener:

```js
// next.config.js
module.exports = {
  output: 'standalone',
}
```

Sin esta línea, el COPY de `.next/standalone` fallará con un error de directorio
no encontrado.

### Build manual (solo para pruebas)
```bash
docker build -f .docker/Dockerfile.prod \
  --build-arg PORT_FRONTEND=3000 \
  --build-arg NEXT_PUBLIC_API_URL=https://api.tudominio.com \
  --build-arg NEXT_PUBLIC_REPORTS_URL=https://reports.tudominio.com \
  -t nombre_del_proyecto_frontend_prod .
```