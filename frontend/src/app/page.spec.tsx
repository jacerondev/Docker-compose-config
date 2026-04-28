// filepath: frontend/src/app/page.spec.tsx
import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import Page from './page';

describe('Home Page', () => {
  it('renderiza sin errores', () => {
    const { container } = render(<Page />);
    expect(container).toBeDefined();
  });

  it('muestra el título principal de la aplicación', () => {
    render(<Page />);
    // Ajusta 'NOMBRE_DEL_PROYECTO' al texto real de tu page.tsx
    const heading = screen.getByRole('heading', { level: 1 });
    expect(heading).toBeInTheDocument();
  });
});