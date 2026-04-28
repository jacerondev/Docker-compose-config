// filepath: backend/src/auth/dto/login.dto.ts
import { IsEmail, IsString, MinLength, MaxLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class LoginDto {
  @ApiProperty({ example: 'usuario@empresa.com' })
  @IsEmail({}, { message: 'Formato de email inválido' })
  email!: string;

  @ApiProperty({ example: 'MiPassword123!', minLength: 8 })
  @IsString()
  @MinLength(8, { message: 'La contraseña debe tener al menos 8 caracteres' })
  @MaxLength(64, { message: 'La contraseña no puede superar 64 caracteres' })
  password!: string;
}
