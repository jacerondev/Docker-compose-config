// filepath: frontend/src/components/ui/StatusBadge.spec.tsx
import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { StatusBadge } from './StatusBadge';

describe('StatusBadge', () => {
  it('muestra label personalizado cuando se proporciona', () => {
    render(<StatusBadge status="ok" label="Sistema operativo" />);
    expect(screen.getByText('Sistema operativo')).toBeInTheDocument();
  });

  it('muestra el status por defecto cuando no hay label', () => {
    render(<StatusBadge status="error" />);
    expect(screen.getByText('error')).toBeInTheDocument();
  });

  it('aplica clase verde para status ok', () => {
    const { container } = render(<StatusBadge status="ok" />);
    expect(container.firstChild).toHaveClass('bg-green-100');
  });

  it('aplica clase roja para status error', () => {
    const { container } = render(<StatusBadge status="error" />);
    expect(container.firstChild).toHaveClass('bg-red-100');
  });
});