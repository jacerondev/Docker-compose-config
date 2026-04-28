```markdown
⚠️ **NOTA:** Esta es documentación de PLANTILLA empresarial. Los endpoints marcados 
con [501] aún no están implementados. Ver [ROADMAP.md](../ROADMAP.md) Fase 1 para 
cronograma de implementación.
```

# API REFERENCE — NOMBRE_DEL_PROYECTO

**Base URL Desarrollo:** `http://localhost:4000/api`  
**Base URL Producción:** `https://api.tudominio.com/api`  
**Documentación interactiva (solo dev):** `http://localhost:4000/api/docs` (requiere `SWAGGER_ENABLED=true`)

---

## Autenticación

La API usa **httpOnly Cookies** para gestionar las sesiones JWT.
Las cookies se establecen automáticamente por el servidor al hacer login.

> ⚠️ El cliente **no** debe incluir `Authorization: Bearer` ni gestionar tokens manualmente.
> El navegador envía las cookies automáticamente en cada petición si usa `credentials: 'include'`.

**Para endpoints protegidos desde curl o testing:**
```bash
# Login — guarda la cookie
curl -c cookies.txt -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@test.com","password":"Test1234!"}'

# Petición autenticada — usa la cookie guardada
curl -b cookies.txt http://localhost:4000/api/auth/me
```

Los endpoints marcados con `🔓 Público` no requieren cookie.

---

## Formato de endpoints

### GET /health

**Auth:** Pública (@Public decorator)
**Response 200:**
{ "status": "ok", "db": "connected" }

### POST /api/auth/login (PENDIENTE)

**Auth:** Pública
**Body:** { email, password }
**Response 200:** { access_token, refresh_token, expires_in }
**Response 401:** { message: "Invalid credentials" }

---

## Endpoints de Auth (`/api/auth/*`)

### POST /api/auth/register 🔓 Público

Registra un nuevo usuario.

**Rate limit:** 3 intentos/hora por IP

**Request body:**

```json
{
  "email": "usuario@empresa.com",
  "password": "MiPassword123!",
  "firstName": "Juan",
  "lastName": "García"
}
```

**Respuestas:**

- `201 Created` — usuario registrado
- `400 Bad Request` — datos inválidos
- `409 Conflict` — email ya registrado
- `429 Too Many Requests` — rate limit superado
- `501 Not Implemented` — AuthService pendiente (estado actual de plantilla)

---

### POST /api/auth/login 🔓 Público

Autentica al usuario. Devuelve tokens JWT via cookies httpOnly.

**Rate limit:** 5 intentos/minuto por IP  
**Body:** `application/json`
```json
{
  "email": "usuario@empresa.com",
  "password": "MiPassword123!"
}
```

**Respuesta 200 — Login exitoso:**
```
HTTP/1.1 200 OK
Set-Cookie: access_token=eyJhbGci...; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=900
Set-Cookie: refresh_token=eyJhbGci...; HttpOnly; Secure; SameSite=Strict; Path=/api/auth/refresh; Max-Age=604800
Content-Type: application/json

{ "message": "Login exitoso" }
```

> Los tokens se envían en cookies httpOnly — el cliente **no puede** leerlos con JavaScript.  
> El navegador los reenvía automáticamente en cada petición.

**Respuesta 400 — Body inválido:**
```json
{
  "statusCode": 400,
  "message": ["email must be an email", "password must be longer than 8 characters"],
  "error": "Bad Request",
  "requestId": "a1b2c3d4"
}
```

**Respuesta 401 — Credenciales incorrectas:**
```json
{ "statusCode": 401, "message": "Credenciales inválidas", "requestId": "a1b2c3d4" }
```

**Respuesta 429 — Rate limit:**
```
HTTP/1.1 429 Too Many Requests
Retry-After: 60
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 0
```

---

### POST /api/auth/refresh 🔒 Requiere cookie `refresh_token`

Emite un nuevo access token usando el refresh token (httpOnly cookie).

**Rate limit:** 10/minuto por IP  
**Body:** vacío (el refresh token va en la cookie)

**Respuesta 200:**
```
Set-Cookie: access_token=eyJhbGci...; HttpOnly; Secure; ...
```

**Respuesta 401:** refresh token inválido o expirado.

---

### GET /api/auth/me 🔒 Requiere JWT

Devuelve el perfil del usuario autenticado.

**Respuesta 200:**

```json
{
  "userId": 1,
  "email": "usuario@empresa.com",
  "role": "USER"
}
```

---

### POST /api/auth/logout 🔒 Requiere JWT

Cierra la sesión (invalida el token en el cliente).

**Respuesta 200:**

```json
{ "message": "Sesión cerrada correctamente" }
```

---

## Endpoints de Salud

### GET /health 🔓 Público

Healthcheck del backend (sin prefijo /api).

**Respuesta 200:**

```json
{ "status": "ok", "info": { "database": { "status": "up" } } }
```

---

## Reports API (`http://localhost:5000`)

### GET /health 🔓 Público

Verifica que la app y la base de datos responden.

**Respuesta 200:**

```json
{ "status": "ok", "db": "connected" }
```

**Respuesta 503:** base de datos no disponible.

---

## Errores comunes

| Código | Significado                   | Qué hacer                       |
| ------ | ----------------------------- | ------------------------------- |
| 400    | Datos inválidos en el body    | Revisar el formato del JSON     |
| 401    | Token ausente o expirado      | Re-autenticarse con /auth/login |
| 403    | Sin permiso para ese recurso  | Verificar rol del usuario       |
| 429    | Demasiadas peticiones         | Esperar antes de reintentar     |
| 501    | Funcionalidad no implementada | Estado de plantilla — pendiente |
| 503    | Servicio no disponible        | Ver logs, verificar BD          |
