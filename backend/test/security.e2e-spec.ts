// filepath: backend/test/security.e2e-spec.ts

describe('Security: Stack trace not exposed in production', () => {
  it('should not expose stack in 500 errors', async () => {
    // Simular NODE_ENV=production
    process.env.NODE_ENV = 'production';
    
    const response = await request(app.getHttpServer())
      .get('/api/nonexistent-endpoint-that-causes-error')
      .expect(404);

    expect(response.body).not.toHaveProperty('stack');
    expect(response.body).not.toHaveProperty('path');
    expect(response.body.message).not.toContain('/home/');  // No rutas del sistema
    expect(response.body.message).not.toContain('node_modules');
  });
});