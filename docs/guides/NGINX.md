# docs/guides/NGINX.md — Guía de configuración de Nginx

**Proyecto:** NOMBRE_DEL_PROYECTO
**Audiencia:** Desarrollador principal — primer deploy en VPS
**Última actualización:** Marzo 2026

> Nginx actúa como proxy inverso entre internet y los 3 contenedores Docker.
> Es el único componente del stack que escucha en los puertos 80 y 443.
> Los contenedores solo escuchan en `127.0.0.1` (nunca accesibles directamente desde internet).
>
> Ver `DECISIONS.md ADR-006` para la justificación de Nginx en el host (fuera de Docker).

---

## Índice

- [Requisitos previos](#requisitos-previos)
- [Instalación](#instalación)
- [Estructura de archivos](#estructura-de-archivos)
- [Observabilidad y trazabilidad](#observabilidad-y-trazabilidad)
- [Configuración base del servidor](#configuración-base-del-servidor)
- [SSL con Certbot](#ssl-con-certbot)
- [Configuración global de Nginx (nginx.conf)](#configuración-global-de-nginx-nginxconf)
- [Configuración completa con SSL](#configuración-completa-con-ssl)
- [Rutas protegidas y bloqueadas](#rutas-protegidas-y-bloqueadas)
- [Headers de seguridad](#headers-de-seguridad)
- [Rate limiting en Nginx](#rate-limiting-en-nginx)
- [Comandos útiles](#comandos-útiles)
- [Troubleshooting](#troubleshooting)

---

## Requisitos previos

- Ubuntu 22.04 LTS o 24.04 LTS
- Dominio apuntando a la IP del servidor (registros DNS propagados)
- Docker y los 3 contenedores corriendo y sanos (`make prod && make wait-healthy`)
- Puertos 80 y 443 abiertos en el firewall del VPS

```bash
# Verificar que los contenedores están healthy antes de configurar Nginx
make health-check

# Verificar que los puertos están abiertos
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp   # ¡No cerrar SSH!
sudo ufw enable
```

---

## Instalación

```bash
sudo apt update
sudo apt install -y nginx

# Verificar que arranca correctamente
sudo systemctl status nginx
sudo systemctl enable nginx    # Arranque automático al reiniciar el servidor
```

---

## Estructura de archivos

```
/etc/nginx/
├── nginx.conf                          # Configuración global (no editar)
├── sites-available/
│   └── nombre_del_proyecto             # ← Tu configuración (crear aquí)
├── sites-enabled/
│   └── nombre_del_proyecto -> ../sites-available/nombre_del_proyecto
└── snippets/
    └── security-headers.conf           # ← Headers de seguridad reutilizables
```

---

## Observabilidad y trazabilidad

Se implementa un `X-Request-Id` para correlacionar logs entre Nginx, API y servicios internos.

> `X-Request-Id` añade trazabilidad de requests entre servicios.
> Si el cliente no lo envía, Nginx genera uno automáticamente usando `$request_id`.

---

## Configuración base del servidor

Crear `/etc/nginx/sites-available/nombre_del_proyecto` con el siguiente contenido.
Reemplaza `tudominio.com` con tu dominio real.

```nginx
# /etc/nginx/sites-available/nombre_del_proyecto
# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURACIÓN HTTP (puerto 80) — redirige todo a HTTPS
# Esta sección se genera automáticamente por Certbot.
# Si instalas Certbot antes de crear este archivo, él la gestiona solo.
# ─────────────────────────────────────────────────────────────────────────────
server {
    listen 80;
    listen [::]:80;
    server_name tudominio.com www.tudominio.com api.tudominio.com reports.tudominio.com;

    # Certbot añade aquí el bloque de validación ACME automáticamente
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Todo lo demás → HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}
```

Activar y probar:

```bash
sudo ln -s /etc/nginx/sites-available/nombre_del_proyecto /etc/nginx/sites-enabled/
sudo nginx -t                    # Verificar sintaxis sin reiniciar
sudo systemctl reload nginx      # Aplicar sin cortar conexiones activas
```

---

## SSL con Certbot

```bash
## 🔒 CONFIGURAR SSL (HTTPS)

# Instalar Certbot con el plugin de Nginx
sudo apt install -y certbot python3-certbot-nginx

# Obtener certificados para todos los subdominios
# (el -d admite múltiples dominios en el mismo certificado)
sudo certbot --nginx \
  -d tudominio.com \
  -d www.tudominio.com \
  -d api.tudominio.com \
  -d reports.tudominio.com \
  --email tu@email.com \
  --agree-tos \
  --non-interactive

# Verificar renovación automática (cron ya configurado por certbot)
sudo certbot renew --dry-run
```

Certbot modifica automáticamente el archivo de configuración para añadir los bloques SSL.

---

## Configuración global de Nginx (nginx.conf)

Algunas directivas deben configurarse en el contexto global `http {}` del archivo `/etc/nginx/nginx.conf`.

Editar:

```bash
sudo nano /etc/nginx/nginx.conf
```

Dentro del bloque http {} añadir:
http {
    # Ocultar la versión de Nginx (no informar atacantes)
    server_tokens off;

    limit_req_zone $binary_remote_addr zone=csp_report:1m rate=5r/m;

    map $http_x_request_id $request_id_new {
        default $http_x_request_id;
        ""      $request_id;
    }
}

---

## Configuración completa con SSL

| Servicio    | connect | send | read | Motivo                           |
| ----------- | ------- | ---- | ---- | -------------------------------- |
| Backend API | 60s     | 60s  | 60s  | Operaciones normales             |
| Frontend    | 30s     | 30s  | 30s  | Solo HTML/JS estático            |
| Reports     | 300s    | 300s | 300s | Generación de Excel puede tardar |

Una vez que Certbot ha generado los certificados, reemplazar el contenido de
`/etc/nginx/sites-available/nombre_del_proyecto` con esta configuración completa:

```nginx
# /etc/nginx/sites-available/nombre_del_proyecto — Configuración completa con SSL
# ══════════════════════════════════════════════════════════════════════════════
# RUTAS BLOQUEADAS (resumen):
#   /health/ready     → interno Docker, nunca público
#   /metrics          → Prometheus interno, bloqueado al exterior (deny all)
#   /api/docs         → Swagger, protegido con Basic Auth
#   /api/docs-json    → JSON del schema de Swagger, mismo tratamiento
#   /api/docs-yaml    → YAML del schema de Swagger, mismo tratamiento
# ══════════════════════════════════════════════════════════════════════════════

# ── Rate limiting global ──────────────────────────────────────────────────────
# Define zonas de rate limiting (declarar fuera de los bloques server)
# $binary_remote_addr: IP del cliente en formato binario (más eficiente que $remote_addr)
limit_req_zone $binary_remote_addr zone=api_limit:10m    rate=30r/s;
limit_req_zone $binary_remote_addr zone=login_limit:10m  rate=5r/m;
limit_req_zone $binary_remote_addr zone=reports_limit:10m  rate=5r/m;

# ── Redirección HTTP → HTTPS ──────────────────────────────────────────────────
server {
    listen 80;
    listen [::]:80;
    server_name tudominio.com www.tudominio.com api.tudominio.com reports.tudominio.com;
    return 301 https://$host$request_uri;
}

# ── Frontend (Next.js) — tudominio.com ───────────────────────────────────────
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name tudominio.com www.tudominio.com;

    # Certificados SSL (gestionados por Certbot — no editar estas líneas)
    ssl_certificate     /etc/letsencrypt/live/tudominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tudominio.com/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Headers de seguridad (ver sección completa más abajo)
    include /etc/nginx/snippets/security-headers.conf;

    # Proxy al frontend Next.js
    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   X-Request-Id $request_id_new;
        proxy_cache_bypass $http_upgrade;

        # Timeout generoso para SSR (Server-Side Rendering)
        proxy_connect_timeout 5s;   # Falla rápido si el contenedor no responde
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }
}

# ── Backend API (NestJS) — api.tudominio.com ─────────────────────────────────
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name api.tudominio.com;

    ssl_certificate     /etc/letsencrypt/live/tudominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tudominio.com/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    include /etc/nginx/snippets/security-headers.conf;

    # /health (ping público, sin detalle de BD) — sí se puede exponer
    location = /health {
        proxy_pass http://127.0.0.1:4000;
    }

    # ── BLOQUEOS DE SEGURIDAD ─────────────────────────────────────────────────
    # IMPORTANTE: Los bloques location exactos (=) y por prefijo (~) tienen
    # mayor prioridad que location / en Nginx. Deben ir ANTES de location /.

    # /health/ready — endpoint interno para Docker healthcheck.
    # Verifica conectividad con PostgreSQL. NUNCA exponer al exterior.
    # El healthcheck de Docker lo llama desde dentro del contenedor (curl localhost).
    location = /health/ready {
        deny all;
        return 404;
    }

    # /metrics — endpoint de Prometheus. Solo accesible desde la red interna.
    # Expone contadores de requests, memoria, GC y métricas de negocio.
    # Bloqueado al exterior para evitar reconocimiento de la infraestructura.
    location = /metrics {
        deny all;
        return 403;
    }

    # /api/docs — Swagger UI. Solo accesible con usuario y contraseña.
    # Expone todos los endpoints de la API con posibilidad de ejecutarlos.
    # Con AUTH_MODE=development, ejecuciones en Swagger actúan como ADMIN.
    # Ver sección "Protección de Swagger" más abajo para setup de htpasswd.
    location /api/docs {
        auth_basic "Dev Docs — NOMBRE_DEL_PROYECTO";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass         http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    # /api/docs-json y /api/docs-yaml — schemas de Swagger en formato máquina.
    # Misma protección que Swagger UI para evitar reconocimiento de la API.
    location ~ ^/api/docs-(json|yaml)$ {
        auth_basic "Dev Docs — NOMBRE_DEL_PROYECTO";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass         http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    # ── ENDPOINTS DE AUTENTICACIÓN (rate limiting estricto) ───────────────────
    # Rate limiting más restrictivo para login, register y refresh.
    # NestJS también aplica ThrottlerModule, esta es la capa previa (Nginx).
    location ~ ^/api/auth/(login|register|refresh) {
        limit_req zone=login_limit burst=3 nodelay;
        limit_req_status 429;

        proxy_pass         http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    # ── RESTO DE LA API ───────────────────────────────────────────────────────
    location / {
        limit_req zone=api_limit burst=50 nodelay;
        # limit_req zone=reports_limit burst=2 nodelay;
        limit_req_status 429;

        proxy_pass         http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   X-Request-Id $request_id_new;

        # Timeout generoso para SSR (Server-Side Rendering)
        proxy_connect_timeout 5s;   # Falla rápido si el contenedor no responde
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }

    location = /api/csp-report {
        limit_req zone=csp_report burst=10 nodelay;
        proxy_pass http://127.0.0.1:4000;
        # proxy_set_header Content-Type "application/json";  # normalizar para NestJS
    }
}

# ── Reports API (Flask/Gunicorn) — reports.tudominio.com ─────────────────────
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name reports.tudominio.com;

    ssl_certificate     /etc/letsencrypt/live/tudominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tudominio.com/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    include /etc/nginx/snippets/security-headers.conf;

    # /health (ping público, sin detalle de BD) — sí se puede exponer
    location = /health {
        proxy_pass http://127.0.0.1:5000;
    }

    # /health/ready — interno para Docker, bloqueado al exterior
    location = /health/ready {
        deny all;
        return 404;
    }

    location / {
        limit_req zone=api_limit burst=20 nodelay;
        limit_req zone=reports_limit burst=2 nodelay;

        proxy_pass         http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   X-Request-Id $request_id_new;

        # Timeout largo: los reportes pesados (Pandas + miles de filas) pueden tardar minutos
        # Timeout generoso para SSR (Server-Side Rendering)
        proxy_connect_timeout 5s;   # Falla rápido si el contenedor no responde
        proxy_send_timeout    300s;
        proxy_read_timeout    300s;

        # Para endpoints JSON puros
        client_max_body_size 64k;  # Más que suficiente para cualquier payload JSON razonable
        # Aumentar límite de body para uploads (ajustar según necesidad)
        # client_max_body_size 20M;
        # client_max_body_size 50M;
    }
}
```

---

## Rutas protegidas y bloqueadas

Resumen de la estrategia de control de acceso en Nginx:

| Ruta              | Acción              | Motivo                                                   |
| ----------------- | ------------------- | -------------------------------------------------------- |
| `/health`         | ✅ Proxy libre      | Endpoint público — responde `{status:'ok'}` sin detalles |
| `/health/ready`   | 🚫 `deny all` → 404 | Interno Docker — verifica BD, no exponer al exterior     |
| `/metrics`        | 🚫 `deny all` → 403 | Prometheus interno — expone métricas de infraestructura  |
| `/api/docs`       | 🔐 Basic Auth       | Swagger UI — ejecuta endpoints como ADMIN en dev         |
| `/api/docs-json`  | 🔐 Basic Auth       | Schema JSON de Swagger — mapa completo de la API         |
| `/api/docs-yaml`  | 🔐 Basic Auth       | Schema YAML de Swagger — mapa completo de la API         |
| `/api/auth/login` | ⏱ Rate limit 5/min  | Anti fuerza bruta                                        |
| `/api/*`          | ⏱ Rate limit 30/s   | Anti DDoS de aplicación                                  |

### Configurar htpasswd para Swagger

```bash
# Instalar htpasswd (incluido en apache2-utils)
sudo apt install -y apache2-utils

# Crear archivo con tu usuario (solicita contraseña interactivamente)
# Usa tu nombre real o un alias — es el usuario para acceder a Swagger
sudo htpasswd -c /etc/nginx/.htpasswd tu_usuario

# Verificar que se creó correctamente
sudo cat /etc/nginx/.htpasswd
# Salida esperada: tu_usuario:$apr1$...hash...

# Aplicar cambios
sudo nginx -t && sudo systemctl reload nginx
```

> **¿Por qué proteger Swagger?**
> Con `AUTH_MODE=development`, el guard de NestJS inyecta automáticamente
> un usuario `ADMIN` sin verificar tokens. Cualquier persona que llegue a
> `/api/docs` puede ejecutar cualquier endpoint de la API con privilegios
> de administrador sin credenciales. Basic Auth en Nginx es la barrera
> que protege esto antes de que el request llegue a NestJS.
>
> En producción, `SWAGGER_ENABLED=false` en `.env.production` desactiva
> Swagger completamente. Este bloque de Nginx queda inactivo pero inofensivo.

---

## Headers de seguridad

Crear el snippet reutilizable `/etc/nginx/snippets/security-headers.conf`:

```nginx
# /etc/nginx/snippets/security-headers.conf
# Headers de seguridad HTTP — incluir en cada bloque server

# Expect-CT: INTENCIONALMENTE OMITIDO
# Deprecado en 2022 (RFC 9163). Chrome 107+ y Firefox no lo procesan.
# Certificate Transparency es ahora obligatorio a nivel de CA — Let's Encrypt
# incluye SCT logs en cada certificado automáticamente. No añadir.

# HSTS: fuerza HTTPS durante 1 año (incluye subdominios y preload)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

# Evita que el navegador detecte el tipo MIME (protege contra ataques MIME sniffing)
add_header X-Content-Type-Options "nosniff" always;

# DENY es más restrictivo y correcto. SAMEORIGIN tiene sentido en aplicaciones que muestran contenido propio en iframes (e.g., dashboards con widgets embebidos del mismo dominio)
# Protección contra clickjacking
# add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Frame-Options "DENY" always;

# Política de recursos: qué puede cargar la página
# Ajustar si el frontend usa CDNs o fuentes externas
# Next.js middleware ya la maneja con nonces
# add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;" always;

# Referrer Policy: no enviar el URL completo al hacer requests a terceros
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# el navegador bloquea acceso a APIs sensibles (cámara, micrófono, geolocalización, USB, etc.) a scripts de terceros si alguno se inyecta en el futuro.
add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=()" always;

# Ocultar la versión de Nginx (no informar atacantes)
# ⚠️  server_tokens off DEBE ir en /etc/nginx/nginx.conf → bloque http {}
# No añadir aquí — este snippet se incluye en el contexto server {}, 
# donde server_tokens no tiene efecto. Ver sección "Configuración global de Nginx".
# server_tokens off;
```

Crear el directorio y verificar:

```bash
sudo mkdir -p /etc/nginx/snippets
sudo nano /etc/nginx/snippets/security-headers.conf
sudo nginx -t && sudo systemctl reload nginx
```

---

## Rate limiting en Nginx

El rate limiting de Nginx complementa (no reemplaza) el ThrottlerModule de NestJS:

| Capa   | Herramienta                      | Límite                | Propósito                                              |
| ------ | -------------------------------- | --------------------- | ------------------------------------------------------ |
| Nginx  | `limit_req_zone` (api_limit)     | 30 req/s por IP       | Protección DDoS básica para backend                    |
| Nginx  | `limit_req_zone` (reports_limit) | 5 req/min por IP      | Reportes pesados — protege CPU y RAM                   |
| NestJS | `ThrottlerModule`                | 10 req/s, 100 req/min | Lógica de aplicación, mensajes de error personalizados |

Si una IP excede el límite de Nginx, recibe HTTP 429 directamente sin que el proceso Node se entere.

---

## Comandos útiles

```bash
# Verificar sintaxis antes de aplicar cambios
sudo nginx -t

# Recargar configuración sin cortar conexiones activas
sudo systemctl reload nginx

# Reinicio completo (corta conexiones — solo si reload no funciona)
sudo systemctl restart nginx

# Ver logs en tiempo real
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Verificar que los certificados se renuevan correctamente
sudo certbot renew --dry-run

# Ver fechas de expiración de los certificados
sudo certbot certificates

# Verificar configuración SSL desde fuera del servidor
curl -I https://tudominio.com
openssl s_client -connect tudominio.com:443 -servername tudominio.com 2>/dev/null | openssl x509 -noout -dates

# Probar que /health/ready está correctamente bloqueado
curl -I https://api.tudominio.com/health/ready
# Respuesta esperada: 404 Not Found

# Probar que /metrics está bloqueado
curl -I https://api.tudominio.com/metrics
# Respuesta esperada: 403 Forbidden

# Probar que /api/docs requiere auth
curl -I https://api.tudominio.com/api/docs
# Respuesta esperada: 401 Unauthorized

# Probar que /api/docs es accesible con credenciales correctas
curl -u tu_usuario:tu_password https://api.tudominio.com/api/docs
# Respuesta esperada: 200 OK con HTML de Swagger
```

---

## Troubleshooting

### Error: `502 Bad Gateway`

El contenedor Docker no está respondiendo. Verificar:

```bash
make health-check
docker ps -a
# Si algún servicio está unhealthy:
docker logs nombre_del_proyecto_api --tail=50
make prod   # Reintentar deploy
```

### Error: `upstream timed out (110: Connection timed out)`

El timeout de Nginx es menor que el tiempo de respuesta del servicio.
Para reports con Pandas: aumentar `proxy_read_timeout 300s` en el bloque de reports.

### Error: `401 Unauthorized` en todas las rutas de la API

Verifica que el archivo `.htpasswd` solo aplica al bloque `/api/docs` y no al `location /` general.
El `auth_basic` solo debe estar en el bloque específico de Swagger, nunca en el bloque raíz.

### Error: `nginx: [emerg] unknown directive "<!--"` o similar

El archivo de configuración contiene comentarios HTML (`<!-- -->`).
Nginx solo acepta comentarios con `#`. Revisar el archivo y eliminar cualquier `<!--` o `-->`.

### Certbot falla: `Challenge failed for domain`

- Verificar que el DNS apunta a la IP correcta: `dig tudominio.com`
- Verificar que el puerto 80 está abierto: `sudo ufw status`
- Verificar que Nginx está corriendo: `sudo systemctl status nginx`

### Error: `Permission denied` al leer certificados

```bash
sudo chmod 755 /etc/letsencrypt/live/
sudo chmod 755 /etc/letsencrypt/archive/
```

### Verificar que los bloqueos funcionan correctamente

```bash
# Script de verificación rápida (ejecutar desde tu máquina local)
DOMAIN="api.tudominio.com"

echo "--- Rutas que deben estar BLOQUEADAS ---"
curl -s -o /dev/null -w "/health/ready → %{http_code}\n" https://$DOMAIN/health/ready
curl -s -o /dev/null -w "/metrics → %{http_code}\n"      https://$DOMAIN/metrics
curl -s -o /dev/null -w "/api/docs (sin auth) → %{http_code}\n" https://$DOMAIN/api/docs

echo "--- Rutas que deben estar ACCESIBLES ---"
curl -s -o /dev/null -w "/health (público) → %{http_code}\n" https://$DOMAIN/health

# Resultados esperados:
# /health/ready → 404
# /metrics → 403
# /api/docs (sin auth) → 401
# /health (público) → 200
```
