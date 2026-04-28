// filepath: frontend/middleware.ts
// ══════════════════════════════════════════════════════════════════════════════
// Content Security Policy (CSP) via Next.js middleware
//
// Estrategia: nonce por request para scripts Y estilos.
//   - script-src: nonce evita ejecución de scripts no autorizados (XSS)
//   - style-src:  nonce evita inyección CSS (CSS injection attacks)
//   - Sin 'unsafe-inline' en ninguna directiva — máxima protección
//
// El nonce se genera por request (no reutilizable) y se pasa al layout via
// el header 'x-nonce' para que los componentes servidor lo usen en <style> y <script>.
//
// Uso en layout.tsx:
//   const nonce = headers().get('x-nonce') ?? '';
//   <Script nonce={nonce} ... />
//   <style nonce={nonce}>{`...`}</style>
// ══════════════════════════════════════════════════════════════════════════════

import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  // Nonce único por request — inválido si se reutiliza (el navegador lo verifica)
  const nonce = Buffer.from(crypto.randomUUID()).toString('base64');
  const isProduction = process.env.NODE_ENV === 'production';
  const apiURL = process.env.NEXT_PUBLIC_API_URL;

  if (isProduction) {
    if (!apiURL) {
      throw new Error('NEXT_PUBLIC_API_URL es obligatorio en producción');
    }
  }

  const connectSrcOrigins = [
    apiURL,
    process.env.NEXT_PUBLIC_REPORTS_URL,
  ]
  .filter(Boolean)
  .map(url => {
    try { return new URL(url!).origin; } catch { return null; }
  })
  .filter(Boolean);
  const connectSrc = ["'self'", ...connectSrcOrigins].join(' ');

  const csp = [
    "default-src 'self'",
    // Scripts: solo con nonce válido — sin 'unsafe-inline'
    `script-src 'self' 'nonce-${nonce}'`,
    `style-src 'self' 'nonce-${nonce}'`,
    // `font-src 'self' https://fonts.gstatic.com`,
    // `style-src 'self' 'nonce-${nonce}' https://fonts.googleapis.com`,
    // Estilos: solo con nonce válido — sin 'unsafe-inline'
    // CSS injection permite exfiltrar datos via selectores (ej: input[value^="a"])
    "img-src 'self' data: blob:",
    "font-src 'self'",
    // connect-src: dominios permitidos para fetch/XHR (API y Reports)
    `connect-src ${connectSrc}`.trim(),
    // `connect-src 'self' ${apiURL ?? ''} ${process.env.NEXT_PUBLIC_REPORTS_URL ?? ''}`.trim(),
    "frame-src 'none'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "report-uri /api/csp-report",
    "report-to csp-endpoint",
    // upgrade-insecure-requests solo en producción — en desarrollo HTTP es necesario
    // si el desarrollador prueba contra un staging sin HTTPS, las peticiones HTTP no se actualizarán automáticamente.
    ...(isProduction ? ["upgrade-insecure-requests"] : [])
  ].join('; ');

  const response = NextResponse.next({
    request: {
      headers: new Headers({
        ...Object.fromEntries(request.headers),
        'x-nonce': nonce,
      }),
    },
  });
  response.headers.set('Content-Security-Policy', csp);

  const baseUrl = isProduction
    ? (apiURL ?? '')
    : 'http://localhost:4000';
  response.headers.set('Reporting-Endpoints', `csp-endpoint="${baseUrl}/api/csp-report"`);

  return response;
}

export const config = {
  matcher: '/((?!_next/static|_next/image|favicon.ico).*)',
};
