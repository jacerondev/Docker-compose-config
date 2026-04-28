// filepath: frontend/src/app/error.tsx
'use client';

import { useEffect } from 'react';

/**
 * error.tsx — Error boundary global del App Router de Next.js
 *
 * ¿Cuándo se activa?
 *   - Cuando un Server Component lanza un error no capturado durante el render
 *   - Cuando una acción de servidor falla
 *   - Cuando un Client Component dentro de este segmento de ruta lanza un error
 *
 * ¿Cuándo NO se activa?
 *   - Errores en layout.tsx (usar un error.tsx en el directorio padre)
 *   - Errores en loading.tsx o not-found.tsx
 *   - Para errores en el propio layout raíz: crear app/global-error.tsx
 *
 * Docs: https://nextjs.org/docs/app/api-reference/file-conventions/error
 */

interface ErrorProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function Error({ error, reset }: ErrorProps) {
  useEffect(() => {
    // Log del error — en producción enviar a un servicio de tracking (Sentry, etc.)
    // En desarrollo aparece en la consola del servidor
    console.error('[Error Boundary]', {
      message: error.message,
      digest: error.digest, // ID de correlación en los logs del servidor (Next.js lo genera)
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined,
    });
  }, [error]);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-6 bg-gray-50 px-4">
      <div className="w-full max-w-md rounded-lg border border-red-200 bg-white p-8 shadow-sm">
        {/* Icono de error */}
        <div className="mb-4 flex justify-center">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-red-100">
            <svg
              className="h-8 w-8 text-red-600"
              fill="none"
              viewBox="0 0 24 24"
              strokeWidth={1.5}
              stroke="currentColor"
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"
              />
            </svg>
          </div>
        </div>

        {/* Título */}
        <h1 className="mb-2 text-center text-xl font-semibold text-gray-900">
          Algo salió mal
        </h1>

        {/* Mensaje de error — solo detalle en desarrollo */}
        <p className="mb-6 text-center text-sm text-gray-500">
          {process.env.NODE_ENV === 'development'
            ? error.message
            : 'Ha ocurrido un error inesperado. Por favor intenta de nuevo.'}
        </p>

        {/* ID de correlación para soporte (digest de Next.js) */}
        {error.digest && (
          <p className="mb-4 text-center text-xs text-gray-400">
            ID de error: <code className="font-mono">{error.digest}</code>
          </p>
        )}

        {/* Acciones */}
        <div className="flex flex-col gap-2">
          <button
            onClick={reset}
            className="w-full rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
          >
            Intentar de nuevo
          </button>
          <a
            href="/"
            className="w-full rounded-md border border-gray-300 bg-white px-4 py-2 text-center text-sm font-medium text-gray-700 transition-colors hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
          >
            Volver al inicio
          </a>
        </div>
      </div>
    </div>
  );
}
