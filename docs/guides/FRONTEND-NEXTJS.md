# FRONTEND-NEXTJS.md — Guía de Desarrollo del Frontend

> **Referencia técnica viva.** Actualizar al añadir patrones, componentes o decisiones.
>
> Stack: Next.js 15 · TypeScript · App Router · Tailwind CSS

---

## Índice

1. [Estructura de carpetas](#1-estructura-de-carpetas)
2. [Capa API — lib/api.ts](#2-capa-api--libapits)
3. [Security headers — next.config.ts](#3-security-headers--nextconfigts)
4. [Manejo de errores global](#4-manejo-de-errores-global)
5. [Estado global — cuándo y qué usar](#5-estado-global--cuándo-y-qué-usar)
6. [Tipos compartidos](#6-tipos-compartidos)
7. [Tests con Jest + Testing Library](#7-tests-con-jest--testing-library)
7. [Variables de entorno — qué requiere rebuild y qué no](#8-variables-de-entorno--qué-requiere-rebuild-y-qué-no)

---

## 1. Estructura de carpetas

```
frontend/src/
├── app/                        ← App Router (Next.js 13+)
│   ├── layout.tsx              ← Layout raíz (providers, metadata)
│   ├── page.tsx                ← Home /
│   ├── page.spec.tsx           ← Test de la home page
│   ├── error.tsx               ← Error boundary global (pendiente)
│   ├── loading.tsx             ← Skeleton de carga global (pendiente)
│   ├── (auth)/                 ← Route group sin prefijo en URL
│   │   ├── login/page.tsx
│   │   └── register/page.tsx
│   └── dashboard/
│       ├── layout.tsx          ← Layout protegido (requiere JWT)
│       └── page.tsx
│
├── components/
│   ├── ui/                     ← Componentes base reutilizables
│   └── [feature]/              ← Componentes específicos de feature
│
├── lib/
│   └── api.ts                  ← Capa de comunicación con el backend
│
└── types/
    └── index.ts                ← Interfaces TypeScript compartidas
```

---

## 2. Capa API — lib/api.ts

`lib/api.ts` ya implementa la capa base de comunicación. Extender aquí al añadir features:

```typescript
// lib/api.ts — ya implementado
const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000';

// Uso:
const users = await api.get<User[]>('/api/users', { token });
const user  = await api.post<User>('/api/users', { name, email }, { token });
```

**Extender para autenticación automática:**
```typescript
// lib/auth-api.ts — crear cuando se implemente auth
import { api } from './api';

// Leer el token del cookie o localStorage
function getToken(): string | undefined {
  if (typeof window === 'undefined') return undefined;
  return localStorage.getItem('access_token') ?? undefined;
}

// Wrapper que añade el token automáticamente
export const authApi = {
  get: <T>(endpoint: string) =>
    api.get<T>(endpoint, { token: getToken() }),
  post: <T>(endpoint: string, body: unknown) =>
    api.post<T>(endpoint, body, { token: getToken() }),
};
```

---

## 3. Security headers — next.config.ts

Ya configurado con 5 headers de seguridad:

```typescript
// next.config.ts — ya implementado
const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },         // evita MIME sniffing
  { key: 'X-Frame-Options',        value: 'DENY' },             // evita clickjacking
  { key: 'X-XSS-Protection',       value: '1; mode=block' },    // bloquea XSS inline
  { key: 'Referrer-Policy',        value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy',     value: 'camera=(), microphone=(), geolocation=()' },
];
```

**Añadir CSP cuando la app esté en producción real:**
```typescript
// Añadir a securityHeaders (ajustar dominios según CDNs usados):
{
  key: 'Content-Security-Policy',
  value: [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",   // unsafe-inline necesario para Next.js
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    "connect-src 'self' https://api.tudominio.com",
  ].join('; ')
}
```

---

## 4. Manejo de errores global

> **Estado:** Pendiente de crear — archivos estándar de Next.js App Router.

```typescript
// src/app/error.tsx — crear este archivo
'use client';
import { useEffect } from 'react';

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error('Error capturado por error.tsx:', error);
  }, [error]);

  return (
    <div className="flex flex-col items-center justify-center min-h-screen gap-4">
      <h2 className="text-2xl font-bold text-red-600">Algo salió mal</h2>
      <p className="text-gray-600">{error.message}</p>
      <button
        onClick={reset}
        className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
      >
        Intentar de nuevo
      </button>
    </div>
  );
}
```

```typescript
// src/app/loading.tsx — crear este archivo
export default function Loading() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600" />
    </div>
  );
}
```

---

## 5. Estado global — cuándo y qué usar

> **Estado actual:** Sin estado global — correcto para el tamaño actual.

**Guía de decisión:**

| Situación | Solución | Cuándo |
|---|---|---|
| Datos del servidor (listas, detalles) | `fetch` en Server Components | Ahora |
| Estado local del componente | `useState` | Ahora |
| Caché de API + loading/error automático | TanStack Query | Cuando haya >3 endpoints |
| Estado UI compartido (modal, sidebar) | Zustand | Cuando >3 componentes compartan estado |
| Estado muy complejo, múltiples actores | Redux Toolkit | Raramente necesario |

**TanStack Query (cuando aplique):**
```bash
pnpm add @tanstack/react-query
```
```typescript
// Reemplaza fetch manual + useState(loading) + useState(error) con:
const { data: users, isLoading, error } = useQuery({
  queryKey: ['users'],
  queryFn: () => api.get<User[]>('/api/users'),
});
```

---

## 6. Tipos compartidos

```typescript
// src/types/index.ts — centralizar interfaces
export interface User {
  id: number;
  email: string;
  name: string;
  role: 'admin' | 'user' | 'viewer';
  isActive: boolean;
  createdAt: string;
}

export interface ApiError {
  statusCode: number;
  message: string;
  timestamp: string;
  path: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
}

// Para el estado de requests:
export type RequestStatus = 'idle' | 'loading' | 'success' | 'error';
```

---

## 7. Tests con Jest + Testing Library

```bash
cd frontend
pnpm test           # todos los tests
pnpm test:cov       # con reporte de cobertura
```

**Template de test para un componente:**
```typescript
// src/components/ui/Button.spec.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { Button } from './Button';

describe('Button', () => {
  it('renders with text', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByText('Click me')).toBeInTheDocument();
  });

  it('calls onClick when clicked', () => {
    const handleClick = jest.fn();
    render(<Button onClick={handleClick}>Click</Button>);
    fireEvent.click(screen.getByText('Click'));
    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  it('is disabled when disabled prop is true', () => {
    render(<Button disabled>Click</Button>);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
```

**Test de página con fetch mock:**
```typescript
// src/app/page.spec.tsx — ya existe, extender así:
import { render, screen } from '@testing-library/react';

// Mock de fetch para tests
global.fetch = jest.fn(() =>
  Promise.resolve({
    ok: true,
    json: () => Promise.resolve([]),
  })
) as jest.Mock;

describe('Home Page', () => {
  it('renders without crashing', () => {
    render(<Page />);
    expect(document.body).toBeDefined();
  });
});
```

## 8. Variables de entorno — qué requiere rebuild y qué no

### Variables que se bakean en el bundle (requieren `docker build`)

Las variables `NEXT_PUBLIC_*` se incrustan en el código JavaScript durante `next build`.
**Cambiarlas sin rebuild no tiene efecto.**

| Variable | Dónde se usa | Consecuencia si cambia sin rebuild |
|----------|-------------|-----------------------------------|
| `NEXT_PUBLIC_API_URL` | `lib/api.ts`, `middleware.ts` | Las peticiones al backend irán a la URL antigua |
| `NEXT_PUBLIC_REPORTS_URL` | `lib/reports.ts`, `middleware.ts` | Las peticiones a reports irán a la URL antigua |

**Para cambiarlas en producción:**
```bash
# 1. Actualizar .env.production
# 2. Rebuild de la imagen
make build-prod-images
# 3. Redeploy
make prod
```

### Variables configurables en runtime (sin rebuild)

Las variables sin prefijo `NEXT_PUBLIC_` solo están disponibles en el servidor
(Server Components, Route Handlers, middleware Node.js).
El proceso de Next.js las lee de `process.env` al arrancar, no al buildear.

| Variable | Dónde se usa | Se puede cambiar sin rebuild |
|----------|-------------|------------------------------|
| `NODE_ENV` | Condicionales server-side | No (afecta optimizaciones del build) |
| `PORT_FRONTEND` | Puerto de escucha | Sí, reiniciando el contenedor |

### ¿Por qué `middleware.ts` puede leer `NEXT_PUBLIC_*`?

El edge middleware (`middleware.ts`) se ejecuta en el runtime de Next.js, no en un
worker V8 aislado. Durante el build, Next.js reemplaza estáticamente las referencias
a `process.env.NEXT_PUBLIC_*` con sus valores literales en el bundle del middleware.
```typescript
// Esto en middleware.ts:
process.env.NEXT_PUBLIC_API_URL
// Se convierte en el bundle en:
"https://api.tudominio.com"   // valor bakeado en build-time
```

Por eso el middleware funciona aunque no tenga acceso al `process.env` del servidor
Node.js en runtime. **El valor es el del momento del build, no del arranque.**