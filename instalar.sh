#!/usr/bin/env bash
# ==============================================================================
#  Instala (o actualiza) CI Seguro en un repo. Funciona con CUALQUIER proyecto.
#    git ci-seguro                 -> en el repo donde estás (atajo, tras activar-en-mi-pc.sh)
#    bash instalar.sh [carpeta]    -> en esa carpeta
#    añade --forzar                -> reemplaza workflows ci.yml / release.yml que no sean del kit
#                                     (se guarda una copia en ci/respaldo/)
#  No borra nada tuyo, no sube nada y no necesita internet.
# ==============================================================================
set -euo pipefail

KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLANTILLA="$KIT/plantilla"
FORZAR=0
DESTINO=""
for a in "$@"; do
    case "$a" in
        --forzar) FORZAR=1 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) DESTINO="$a" ;;
    esac
done
DESTINO="${DESTINO:-$PWD}"
[ -d "$DESTINO" ] || { echo "❌ No existe la carpeta: $DESTINO"; exit 1; }
DESTINO=$(cd "$DESTINO" && (git rev-parse --show-toplevel 2>/dev/null || pwd))
[ "$DESTINO" != "$PLANTILLA" ] || { echo "❌ Esa es la plantilla del kit"; exit 1; }

verde() { printf '\033[1;32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[2m%s\033[0m\n' "$*"; }
amar()  { printf '\033[1;33m%s\033[0m\n' "$*"; }

echo "🛡  Instalando CI Seguro en: $DESTINO"
cd "$DESTINO"
mkdir -p ci .github/workflows

# 1. Motor y ejemplos: siempre a la última versión del kit
install -m 755 "$PLANTILLA/ci/revisar.sh"         ci/revisar.sh
install -m 644 "$PLANTILLA/ci/pruebas.ejemplo.sh" ci/pruebas.ejemplo.sh
install -m 644 "$PLANTILLA/ci/ajustes.ejemplo.conf" ci/ajustes.ejemplo.conf
verde "✔ ci/revisar.sh (motor) y ejemplos"

# 2. Workflows: se actualizan si son del kit; si son tuyos, solo con --forzar
for wf in ci.yml release.yml; do
    origen="$PLANTILLA/.github/workflows/$wf"
    dest=".github/workflows/$wf"
    if [ ! -f "$dest" ] || cmp -s "$origen" "$dest" || grep -q 'CI Seguro' "$dest"; then
        install -m 644 "$origen" "$dest"
        verde "✔ $dest"
    elif [ "$FORZAR" = 1 ]; then
        mkdir -p ci/respaldo
        cp "$dest" "ci/respaldo/$wf.$(date +%Y%m%d-%H%M%S)"
        install -m 644 "$origen" "$dest"
        verde "✔ $dest (el tuyo quedó en ci/respaldo/)"
    else
        amar "⚠ $dest ya existe y no es del kit: lo dejo. Usa --forzar para reemplazarlo."
    fi
done

# 3. Dependabot: solo si no tienes uno. Detecta los ecosistemas del repo.
if [ ! -f .github/dependabot.yml ] && [ ! -f .github/dependabot.yaml ]; then
    existe() { git ls-files --error-unmatch "$@" >/dev/null 2>&1 || compgen -G "$1" >/dev/null; }
    ecos=(github-actions)
    existe Dockerfile                                      && ecos+=(docker)
    { existe 'requirements*.txt' || existe pyproject.toml || existe setup.py; } && ecos+=(pip)
    existe package.json                                    && ecos+=(npm)
    existe go.mod                                          && ecos+=(gomod)
    existe Cargo.toml                                      && ecos+=(cargo)
    existe composer.json                                   && ecos+=(composer)
    existe Gemfile                                         && ecos+=(bundler)
    existe pom.xml                                         && ecos+=(maven)
    { existe build.gradle || existe build.gradle.kts; }    && ecos+=(gradle)
    {
        echo "# Dependabot: abre un pull request cuando hay actualizaciones."
        echo "# Cada PR pasa por el CI completo antes de que lo aceptes."
        echo "version: 2"
        echo "updates:"
        for e in "${ecos[@]}"; do
            printf '  - package-ecosystem: %s\n    directory: /\n    schedule:\n      interval: weekly\n' "$e"
            printf '    groups:\n      %s:\n        patterns: ["*"]\n' "${e//-/_}"
        done
    } > .github/dependabot.yml
    verde "✔ .github/dependabot.yml (${ecos[*]})"
else
    gris "– .github/dependabot.yml ya existe: lo dejo"
fi

# 4. Política de seguridad: solo si no tienes una
if [ ! -f SECURITY.md ]; then
    install -m 644 "$PLANTILLA/SECURITY.md" SECURITY.md
    verde "✔ SECURITY.md"
else
    gris "– SECURITY.md ya existe: lo dejo"
fi

echo
bash ci/revisar.sh info | sed 's/^/   /'
echo
verde "Listo. Siguientes pasos:"
echo "  1. Prueba en tu PC:   bash ci/revisar.sh            (o solo lo rápido: bash ci/revisar.sh secretos lint)"
echo "  2. ¿Pruebas propias?  cp ci/pruebas.ejemplo.sh ci/pruebas.sh   y edítalo"
echo "  3. Sube:              git add ci .github SECURITY.md && git commit -m 'CI Seguro' && git push"
echo "  4. Una vez por repo en GitHub: ajustes de seguridad + entorno 'produccion' (ver README del kit)"
