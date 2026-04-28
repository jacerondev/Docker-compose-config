// filepath: backend/ormconfig.ts
// CLI de TypeORM únicamente — la app usa database.config.ts
// Compatible con producción (Docker Secrets) y desarrollo (.env)
import { DataSource } from 'typeorm';
import * as dotenv from 'dotenv';
import * as fs from 'fs';
import * as path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../.env') });

function readSecret(fileVar: string, plainVar: string): string | undefined {
  const filePath = process.env[fileVar];
  if (filePath) {
    try { return fs.readFileSync(filePath, 'utf8').trim(); } catch {}
  }
  return process.env[plainVar];
}

export default new DataSource({
  type: 'postgres',
  host:     process.env.DB_HOST     ?? 'localhost',
  port:     parseInt(process.env.DB_PORT ?? '5432'),
  username: readSecret('DB_USER_FILE', 'DB_USER'),
  password: readSecret('DB_PASSWORD_FILE', 'DB_PASSWORD'),
  database: process.env.DB_NAME,
  entities:   ['src/**/*.entity.ts'],
  migrations: ['src/migrations/*.ts'],
  synchronize: false,
});