// filepath: backend/jest.config.ts
export default {
  coverageThreshold: {
    global: {
      lines: 60,       // Subir a 80 cuando auth esté completo
      functions: 60,
      branches: 50,
      statements: 60,
    },
  },
};