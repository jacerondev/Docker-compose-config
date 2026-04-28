// filepath: backend/src/auth/dto/register.dto.ts
// ══════════════════════════════════════════════════════════════════════════════
// DTO de registro — valida los datos del body antes de llegar al controller
// ══════════════════════════════════════════════════════════════════════════════

import {
  IsEmail,
  IsString,
  MinLength,
  MaxLength,
  Matches,
  IsOptional,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class RegisterDto {
  /** Nombre del usuario (opcional — ajustar según requisitos del negocio) */
  @ApiPropertyOptional({ example: 'Juan Pérez' })
  @IsOptional()
  @IsString()
  @MinLength(2, { message: 'El nombre debe tener al menos 2 caracteres' })
  @MaxLength(100, { message: 'El nombre no puede superar 100 caracteres' })
  name?: string;

  /** Email único — identificador de login */
  @ApiProperty({ example: 'usuario@empresa.com' })
  @IsEmail({}, { message: 'Formato de email inválido' })
  email!: string;

  /**
   * Contraseña: mín. 8 caracteres, máx. 64.
   * Debe incluir mayúscula, minúscula y número.
   * Límite de 64 para prevenir ataques DoS en argon2.
   */
  @ApiProperty({ example: 'MiPassword123!', minLength: 8 })
  @IsString()
  @MinLength(8, { message: 'La contraseña debe tener al menos 8 caracteres' })
  @MaxLength(64, { message: 'La contraseña no puede superar 64 caracteres' })
  @Matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$/, {
    message: 'La contraseña debe incluir mayúscula, minúscula y número',
  })
  password!: string;
}

// ══════════════════════════════════════════════════════════════════════════════
// NOTAS DE IMPLEMENTACIÓN
// ══════════════════════════════════════════════════════════════════════════════
//
// HASH — en AuthService, NUNCA en el DTO:
//   const hashed = await hashPassword(dto.password); // password.service.ts
//   await this.userRepository.save({ ...dto, password: hashed });
//
// EMAIL NORMALIZADO — para evitar duplicados por mayúsculas/espacios:
//   Añadir en AuthService antes de guardar:
//   const normalizedEmail = dto.email.toLowerCase().trim();
//
// CONFIRMACIÓN DE PASSWORD — si el negocio lo requiere:
//   Validar en AuthService (no en el DTO):
//   if (dto.password !== dto.confirmPassword) throw new BadRequestException(...);
//
// ⚠️  NUNCA loggear el DTO completo — contiene la contraseña en texto plano.
// ══════════════════════════════════════════════════════════════════════════════
