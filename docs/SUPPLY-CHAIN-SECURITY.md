# Supply Chain Security

## Controles activos

| Control | Dónde | Qué detecta |
|---------|-------|-------------|
| `--ignore-scripts` en .npmrc | CI + Docker | Lifecycle scripts en npm |
| Semgrep p/secrets | security.yml | Secretos hardcodeados |
| Trivy filesystem scan | security.yml | CVEs en dependencias |
| Bandit | security.yml | Vulnerabilidades Python |
| pip-audit | audit.yml | CVEs en Python |
| pnpm audit | audit.yml | CVEs en Node |
| lifecycle-scripts check | security.yml | postinstall maliciosos |

## Procedimiento ante un lifecycle script nuevo

1. Revisar el propósito del script
2. Si es legítimo, documentarlo en este archivo con justificación
3. Añadir su hash a `.github/allowed-scripts.txt`
4. El CI lo marcará como excepción aprobada