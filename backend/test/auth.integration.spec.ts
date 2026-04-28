// filepath: backend/test/auth.integration.spec.ts
describe('Auth flow (integration)', () => {
  it('POST /api/auth/login → 200 + cookie httpOnly', ...)
  it('GET /api/auth/me con cookie válida → 200', ...)
  it('GET /api/auth/me sin cookie → 401', ...)
  it('POST /api/auth/refresh con refresh válido → nuevo access token', ...)
  it('POST /api/auth/logout → cookie eliminada', ...)
});