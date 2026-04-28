// filepath: frontend/src/components/ui/StatusBadge.tsx
interface StatusBadgeProps {
  status: 'ok' | 'error' | 'loading';
  label?: string;
}

export function StatusBadge({ status, label }: StatusBadgeProps) {
  const colors = {
    ok: 'bg-green-100 text-green-800',
    error: 'bg-red-100 text-red-800',
    loading: 'bg-yellow-100 text-yellow-800',
  };
  return (
    <span className={`px-2 py-1 rounded text-sm font-medium ${colors[status]}`}>
      {label ?? status}
    </span>
  );
}