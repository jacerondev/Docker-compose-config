# Reports API — Dockerfiles

## Archivos

- `Dockerfile`      — Desarrollo con Flask dev server y hot reload
- `Dockerfile.prod` — Producción con Gunicorn (multi-stage)

---

## Dockerfile (Desarrollo)

### Características
- Python 3.12 slim
- Usuario no-root `nombre_del_proyecto` (UID 1000)
- Hot reload con volumen montado y flag `--debug`
- Todas las dependencias del sistema necesarias para compilar psycopg2, reportlab y pandas

### Variables
- `PORT_REPORTS` — Puerto interno que Flask escucha (por defecto: 5000)

### Build manual (solo para pruebas)
```bash
docker build -f .docker/Dockerfile \
  --build-arg PORT_REPORTS=5000 \
  -t nombre_del_proyecto_reports_dev .
```

---

## Dockerfile.prod (Producción)

### Características
- **2 etapas:** `builder` → `runner`
- Gunicorn con `worker-class gthread` — óptimo para carga mixta CPU+I/O
- Timeout de 300s para reportes con cientos de miles de filas
- Usuario no-root `nombre_del_proyectouser` (UID 1000)
- `curl` instalado para healthchecks de Docker

### Etapas

| Etapa     | Base             | Propósito                                         |
|-----------|------------------|---------------------------------------------------|
| `builder` | python:3.12-slim | Compila dependencias con headers de sistema       |
| `runner`  | python:3.12-slim | Solo runtime mínimo, copia libs del builder       |

### Configuración de Gunicorn

| Parámetro            | Valor          | Motivo                                                   |
|----------------------|----------------|----------------------------------------------------------|
| `--workers`          | `$(nproc)`     | 1 worker por CPU; evita context switching innecesario    |
| `--worker-class`     | `gthread`      | Threads por worker; mejor que sync para I/O + CPU mixto  |
| `--threads`          | `4`            | 4 requests concurrentes por worker                       |
| `--timeout`          | `300`          | 5 minutos; suficiente para reportes Excel grandes        |
| `--max-requests`     | `200`          | Reinicia el worker cada 200 requests (previene memory leaks con Pandas) |
| `--max-requests-jitter` | `40`        | Desfasa los reinicios para evitar que todos coincidan    |
| `--worker-tmp-dir`   | `/dev/shm`     | Archivos temporales en RAM; más rápido que disco         |
| `--preload -`        | `on`           | Carga la app antes del fork; reduce uso de memoria (Copy-On-Write) y mejora el arranque, pero requiere que no haya conexiones a BD abiertas ni side-effects al importar               |
| `--access-logfile -` | stdout         | Logs visibles con `docker compose logs`                  |
| `--error-logfile -`  | stdout         | Errores visibles con `docker compose logs`               |

**Capacidad total:** `$(nproc)` workers × 4 threads.  
En un servidor de 4 CPUs: 16 requests simultáneas.

### Monitoreo
```bash
# Uso de CPU y RAM en tiempo real
docker stats nombre_del_proyecto_reports

# Logs de Gunicorn
docker compose logs -f reports-api

# Workers activos dentro del contenedor
docker exec nombre_del_proyecto_reports ps aux | grep gunicorn
```

---

## Dependencias del sistema instaladas en runner

| Paquete  | Motivo                                     |
|----------|--------------------------------------------|
| `libpq5` | Librería cliente de PostgreSQL (psycopg2)  |
| `curl`   | Healthcheck de Docker                      |