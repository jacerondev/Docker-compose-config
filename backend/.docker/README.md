# Backend Dockerfiles

## Archivos

- `Dockerfile` - Desarrollo con hot reload
- `Dockerfile.prod` - Producción optimizado (multi-stage)

## Dockerfile (Desarrollo)

### Características:
- Node.js 24 slim
- Usuario no-root (UID 1000)
- Hot reload con volúmenes
- DevDependencies incluidas

### Build:
\`\`\`bash
docker build -f .docker/Dockerfile -t nombre_del_proyecto_backend_dev .
\`\`\`

### Variables:
- `PORT_BACKEND` - Puerto interno (default: 4000)

---

## Dockerfile.prod (Producción)

### Características:
- Multi-stage build (builder + runner)
- Solo production dependencies
- Optimizado para tamaño
- Usuario no-root

### Build:
\`\`\`bash
docker build -f .docker/Dockerfile.prod \
  --build-arg PORT_BACKEND=4000 \
  -t nombre_del_proyecto_backend_prod .
\`\`\`

### Etapas:
1. **Builder** - Compila TypeScript
2. **Runner** - Ejecuta código compilado

### Optimizaciones:
- pnpm ci --only=production
- pnpm cache clean --force
- Copia solo dist/ y package.json