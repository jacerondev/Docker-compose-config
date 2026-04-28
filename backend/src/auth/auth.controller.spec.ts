// filepath: backend/src/auth/auth.controller.ts
import { Test, TestingModule } from '@nestjs/testing';
import { AuthController } from './auth.controller';
import { ThrottlerModule } from '@nestjs/throttler';

describe('AuthController (plantilla)', () => {
  let controller: AuthController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [
        ThrottlerModule.forRoot([
          { name: 'short', ttl: 1000, limit: 10 },
        ]),
      ],
      controllers: [AuthController],
    }).compile();

    controller = module.get<AuthController>(AuthController);
  });

  it('debería estar definido', () => {
    expect(controller).toBeDefined();
  });

  it('logout devuelve mensaje OK (no necesita AuthService)', async () => {
    const result = await controller.logout();
    expect(result).toEqual({ message: 'Sesión cerrada correctamente' });
  });

  it('health devuelve status ok (endpoint público)', () => {
    const result = controller.health();
    expect(result).toEqual({ status: 'ok' });
  });
});