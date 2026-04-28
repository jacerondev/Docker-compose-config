# GIT-WORKFLOW.md — Flujo de trabajo Git

## Protección de rama main

La rama `main` está protegida en GitHub. Configurar en:
GitHub → Settings → Branches → Add protection rule → main

Reglas requeridas:
- Require a pull request before merging
- Require status checks: validate, typecheck, test-backend, test-reports, scan-prod-images
- Require branches to be up to date before merging
- Do not allow bypassing the above settings

## Flujo de trabajo diario
```bash
# Crear rama desde develop
git checkout develop
git checkout -b feature/nombre-descriptivo

# Trabajar y hacer commits
git add .
git commit -m "feat: descripción del cambio"

# Push y PR
git push origin feature/nombre-descriptivo
# → Abrir PR en GitHub hacia main
# → Esperar que CI pase (todos los jobs verdes)
# → Merge
```

## Releases con tags firmados

Los releases de producción usan tags Git firmados con GPG.
```bash
# Prerequisito: tener una clave GPG configurada en Git
# git config user.signingkey TU_KEY_ID

# Crear tag firmado
git tag -s v2026.03.27 -m "Release v2026.03.27 — descripción del release"
git push origin v2026.03.27
```

## Configuración futura — build en CI y registry

[Ver ci.yml job build-and-push — comentado para activar cuando el registry esté configurado]
