// filepath: backend/src/config/database.config.spec.ts
import * as fs from 'fs';
import { getDatabaseConfig } from './database.config';

// Variables de entorno base válidas para todos los tests
const BASE_ENV = {
  DB_HOST: 'localhost',
  DB_PORT: '5432',
  DB_NAME: 'test_db',
  NODE_ENV: 'test',
};

describe('getDatabaseConfig()', () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    // Guardar el entorno original y limpiarlo antes de cada test
    originalEnv = { ...process.env };
    // Limpiar todas las variables relevantes
    delete process.env.DB_HOST;
    delete process.env.DB_PORT;
    delete process.env.DB_NAME;
    delete process.env.DB_USER;
    delete process.env.DB_PASSWORD;
    delete process.env.DB_USER_FILE;
    delete process.env.DB_PASSWORD_FILE;
    delete process.env.NODE_ENV;
  });

  afterEach(() => {
    // Restaurar entorno original
    process.env = originalEnv;
  });

  // ── readSecret: lee de variable de entorno directa ───────────────────────
  describe('credenciales desde variables de entorno (desarrollo)', () => {
    it('devuelve configuración válida con DB_USER y DB_PASSWORD en env', () => {
      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER: 'dev_user',
        DB_PASSWORD: 'dev_password',
      });

      const config = getDatabaseConfig();

      expect(config.type).toBe('postgres');
      expect(config.host).toBe('localhost');
      expect(config.port).toBe(5432);
      expect(config.database).toBe('test_db');
      expect(config.username).toBe('dev_user');
      expect(config.password).toBe('dev_password');
    });

    it('parsea DB_PORT como número', () => {
      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER: 'u',
        DB_PASSWORD: 'p',
        DB_PORT: '5433',
      });

      const config = getDatabaseConfig();
      expect(config.port).toBe(5433);
    });

    it('usa 5432 como puerto por defecto si DB_PORT no está definido', () => {
      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER: 'u',
        DB_PASSWORD: 'p',
      });
      delete process.env.DB_PORT;

      const config = getDatabaseConfig();
      expect(config.port).toBe(5432);
    });
  });

  // ── readSecret: lee de archivo Docker Secret ─────────────────────────────
  describe('credenciales desde Docker Secrets (producción)', () => {
    it('lee usuario y contraseña desde archivos cuando *_FILE está definido', () => {
      // Mockear fs.readFileSync para no necesitar archivos reales
      const readFileSpy = jest
        .spyOn(fs, 'readFileSync')
        .mockImplementation((path: any) => {
          if (String(path).includes('db_user'))     return 'prod_user\n';
          if (String(path).includes('db_password')) return 'prod_password\n';
          return '';
        });

      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER_FILE:     '/run/secrets/db_user',
        DB_PASSWORD_FILE: '/run/secrets/db_password',
      });

      const config = getDatabaseConfig();

      expect(config.username).toBe('prod_user');     // trim() aplicado
      expect(config.password).toBe('prod_password');
      readFileSpy.mockRestore();
    });

    it('prefiere *_FILE sobre la variable directa cuando ambas están definidas', () => {
      const readFileSpy = jest
        .spyOn(fs, 'readFileSync')
        .mockReturnValue('file_user\n' as any);

      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER:      'env_user',       // debería ignorarse
        DB_USER_FILE: '/run/secrets/db_user',
        DB_PASSWORD:  'env_password',
      });

      const config = getDatabaseConfig();
      expect(config.username).toBe('file_user');   // gana el archivo
      readFileSpy.mockRestore();
    });

    it('lanza error si el archivo *_FILE no existe', () => {
      jest.spyOn(fs, 'readFileSync').mockImplementation(() => {
        throw new Error('ENOENT');
      });

      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER_FILE:     '/run/secrets/db_user',
        DB_PASSWORD_FILE: '/run/secrets/db_password',
      });

      expect(() => getDatabaseConfig()).toThrow();
    });
  });

  // ── Casos de error ────────────────────────────────────────────────────────
  describe('errores de configuración incompleta', () => {
    it('lanza error si DB_USER y DB_USER_FILE están ausentes', () => {
      Object.assign(process.env, {
        ...BASE_ENV,
        DB_PASSWORD: 'p',
        // DB_USER no definida
      });

      expect(() => getDatabaseConfig()).toThrow(/DB_USER/);
    });

    it('lanza error si DB_PASSWORD y DB_PASSWORD_FILE están ausentes', () => {
      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER: 'u',
        // DB_PASSWORD no definida
      });

      expect(() => getDatabaseConfig()).toThrow(/DB_PASSWORD/);
    });

    it('lanza error si DB_HOST no está definido', () => {
      Object.assign(process.env, {
        DB_PORT:     '5432',
        DB_NAME:     'test_db',
        DB_USER:     'u',
        DB_PASSWORD: 'p',
        // DB_HOST ausente
      });

      expect(() => getDatabaseConfig()).toThrow(/DB_HOST/);
    });

    it('lanza error si DB_NAME no está definido', () => {
      Object.assign(process.env, {
        DB_HOST:     'localhost',
        DB_PORT:     '5432',
        DB_USER:     'u',
        DB_PASSWORD: 'p',
        // DB_NAME ausente
      });

      expect(() => getDatabaseConfig()).toThrow(/DB_NAME/);
    });
  });

  // ── Configuración según entorno ───────────────────────────────────────────
  describe('logging según NODE_ENV', () => {
    it('habilita logging de queries en desarrollo', () => {
      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER: 'u', DB_PASSWORD: 'p',
        NODE_ENV: 'development',
      });

      const config = getDatabaseConfig() as any;
      expect(config.logging).toContain('query');
    });

    it('solo loguea errores en producción', () => {
      Object.assign(process.env, {
        ...BASE_ENV,
        DB_USER: 'u', DB_PASSWORD: 'p',
        NODE_ENV: 'production',
      });

      const config = getDatabaseConfig() as any;
      expect(config.logging).toEqual(['error']);
      expect(config.logging).not.toContain('query');
    });
  });
});