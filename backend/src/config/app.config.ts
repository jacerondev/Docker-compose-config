// filepath: backend/src/config/app.config.ts
import { IsIn, IsNotEmpty, IsNumberString, IsOptional } from 'class-validator';
import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';

class AppConfig {
  @IsIn(['development', 'production', 'test'])
  NODE_ENV: string;

  @IsIn(['development', 'real'])
  AUTH_MODE: string;

  @IsNotEmpty({ message: 'ALLOWED_ORIGINS es obligatorio. Ej: http://localhost:3000' })
  ALLOWED_ORIGINS: string;

  // DB_HOST y DB_NAME se validan aquí para fail-fast antes del bootstrap de TypeORM
  @IsNotEmpty({ message: 'DB_HOST es obligatorio. Revisa tu .env' })
  DB_HOST: string;

  @IsNotEmpty({ message: 'DB_NAME es obligatorio. Revisa tu .env' })
  DB_NAME: string;

  // PORT es opcional con default — solo validar formato si está definido
  @IsOptional()
  @IsNumberString({}, { message: 'PORT debe ser un número. Ej: 4000' })
  PORT?: string;
}

export function validateAppConfig(): void {
  const config = plainToInstance(AppConfig, process.env as Record<string, unknown>);
  const errors = validateSync(config, { skipMissingProperties: false });
  if (errors.length > 0) {
    const messages: string[] = errors.flatMap(
      (e) => Object.values(e.constraints ?? {}) as string[]
    );
    throw new Error(
      `[AppConfig] Configuración inválida:\n${messages.map((m) => `  - ${m}`).join('\n')}`
    );
  }
}