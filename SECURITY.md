# Política de seguridad

## Cómo reportar una vulnerabilidad

**No abras un issue público.** Usa el reporte privado de GitHub:
pestaña **Security → Report a vulnerability** de este repositorio.

Respondo lo antes posible y publico el arreglo junto con el aviso.

## Cómo se protege este repositorio

Cada cambio pasa por [CI Seguro](https://github.com/diriartev/ci-seguro):

- búsqueda de secretos en todo el historial (gitleaks);
- análisis de código, Dockerfile y workflows (ruff + bandit, shellcheck, hadolint, actionlint);
- configuración insegura y dependencias vulnerables (trivy);
- construcción, pruebas y escaneo de la imagen antes de publicar;
- publicación solo con aprobación manual, firmada con Sigstore y con certificado de procedencia.
