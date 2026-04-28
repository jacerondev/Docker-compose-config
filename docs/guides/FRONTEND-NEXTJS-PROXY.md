# Frontend: Server-Side API Routes como Proxy (Next.js)

## El problema con NEXT_PUBLIC_*

Las variables `NEXT_PUBLIC_API_URL` y `NEXT_PUBLIC_REPORTS_URL` se "bakean"
(incrustan) en el bundle de JavaScript durante el `next build`. Esto significa:

- Si la URL del backend cambia → hay que hacer rebuild + redeploy completo de la imagen frontend.
- Las URLs son visibles en el código fuente del bundle (inspeccionable en el navegador).

## Alternativa: Route Handlers de Next.js como proxy interno

En lugar de que el navegador llame directamente al backend, el frontend de Next.js
puede actuar como proxy: el navegador llama a `/api/*` del propio servidor Next.js,
y ese servidor (en Node.js) reenvía al backend usando variables de entorno de servidor
(que SÍ se pueden cambiar sin rebuild).

### Arquitectura actual (NEXT_PUBLIC_*)
```
Browser → http://tu-api.com/api/users        (URL bakeada en el bundle)
```

### Arquitectura con proxy server-side
```
Browser → /api/proxy/users (Next.js server)
              └──────────→ http://backend:4000/api/users  (variable de entorno, no bakeada)
```

## Implementación

### 1. Variables de entorno de servidor (no públicas)

En `.env`:
```bash
# Sin NEXT_PUBLIC_ — solo accesibles desde el servidor Next.js, no desde el browser
BACKEND_INTERNAL_URL=http://backend:4000     # URL interna Docker
REPORTS_INTERNAL_URL=http://reports-api:5000 # URL interna Docker
```

En `.env.prod.example`:
```bash
BACKEND_INTERNAL_URL=http://backend:4000     # Igual — resuelve por Docker DNS
REPORTS_INTERNAL_URL=http://reports-api:5000
```

### 2. Route Handler proxy en Next.js App Router

Crea `frontend/src/app/api/proxy/[...path]/route.ts`:
```typescript
// frontend/src/app/api/proxy/[...path]/route.ts
import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_INTERNAL_URL ?? 'http://backend:4000';

export async function GET(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path, 'GET');
}

export async function POST(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path, 'POST');
}

// Añadir PUT, PATCH, DELETE según necesidad

async function proxyRequest(
  request: NextRequest,
  pathSegments: string[],
  method: string
): Promise<NextResponse> {
  const targetUrl = `${BACKEND_URL}/api/${pathSegments.join('/')}`;

  // Propagar cookies de autenticación al backend
  const cookieHeader = request.headers.get('cookie') ?? '';
  const requestId = request.headers.get('x-request-id') ?? crypto.randomUUID();

  try {
    const body = method !== 'GET' ? await request.text() : undefined;

    const response = await fetch(targetUrl, {
      method,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': cookieHeader,          // Propagar cookies httpOnly
        'X-Request-Id': requestId,       // Trazabilidad
        'X-Forwarded-For': request.ip ?? '',
      },
      body,
      // Next.js 14+: no cachear por defecto las llamadas proxy
      cache: 'no-store',
    });

    const responseBody = await response.text();

    return new NextResponse(responseBody, {
      status: response.status,
      headers: {
        'Content-Type': response.headers.get('Content-Type') ?? 'application/json',
        // Propagar Set-Cookie del backend (para renovación de tokens)
        ...(response.headers.get('Set-Cookie')
          ? { 'Set-Cookie': response.headers.get('Set-Cookie')! }
          : {}),
      },
    });
  } catch (error) {
    return NextResponse.json(
      { error: 'Backend no disponible' },
      { status: 503 }
    );
  }
}
```

### 3. Cliente del frontend (sin NEXT_PUBLIC_*)
```typescript
// frontend/src/lib/api.ts — versión con proxy server-side
const API_BASE = '/api/proxy';  // Relativo — siempre al mismo dominio
```

### Cuándo usar este patrón

| Criterio | NEXT_PUBLIC_* | Proxy server-side |
|---|---|---|
| URLs cambian frecuentemente | ❌ Rebuild necesario | ✅ Solo reiniciar |
| Ocultar URL del backend al usuario | ❌ Visible en bundle | ✅ Opaco |
| Latencia | ✅ Directa | ⚠️ Un hop extra |
| Complejidad | ✅ Simple | ⚠️ Código de proxy |
| SSR con cookies | ⚠️ Complejo | ✅ Natural |

### Recomendación para este proyecto

Para la plantilla actual (single VPS, URLs estables), **NEXT_PUBLIC_* es aceptable**.
Migrar al proxy cuando:
- La URL del backend cambie más de una vez al mes, o
- Se requiera ocultar la URL interna del backend al usuario final.