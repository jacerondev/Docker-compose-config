// filepath: backend/src/auth/dto/register.dto.spec.ts
import { validate } from 'class-validator';
import { plainToInstance } from 'class-transformer';
import { RegisterDto } from './register.dto';

describe('RegisterDto', () => {
  it('debería aceptar datos válidos', async () => {
    const dto = plainToInstance(RegisterDto, {
      email: 'test@nombre_del_proyecto.com',
      password: 'Password123!',
      firstName: 'Juan',
      lastName: 'García',
    });
    const errors = await validate(dto);
    expect(errors.length).toBe(0);
  });

  it('debería rechazar email inválido', async () => {
    const dto = plainToInstance(RegisterDto, {
      email: 'no-es-email',
      password: 'Password123!',
    });
    const errors = await validate(dto);
    expect(errors.some(e => e.property === 'email')).toBe(true);
  });
});