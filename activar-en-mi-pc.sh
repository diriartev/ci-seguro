#!/usr/bin/env bash
# ==============================================================================
#  Activa CI Seguro en TU PC para TODOS tus repos (una sola vez; repítelo para actualizar).
#    bash activar-en-mi-pc.sh
#  Qué hace:
#   - copia el kit a ~/.config/git/ci-seguro (ruta fija, independiente de dónde lo bajaste)
#   - instala el hook global pre-push: antes de CADA push, en CUALQUIER repo, busca
#     secretos en el historial (y revisa el código si el repo tiene el kit)
#   - crea los atajos:  git ci-seguro  (instalar en un repo)   git revisar  (revisar ya)
#  No lee ni toca tus llaves, tu correo ni tus repos.
# ==============================================================================
set -euo pipefail

KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEST="$HOME/.config/git/ci-seguro"
HOOKS="$HOME/.config/git/hooks"

verde() { printf '\033[1;32m%s\033[0m\n' "$*"; }
amar()  { printf '\033[1;33m%s\033[0m\n' "$*"; }

# 1. Copia del kit en una ruta estable
if [ "$KIT" != "$DEST" ]; then
    rm -rf "$DEST.nuevo"
    mkdir -p "$DEST.nuevo"
    cp -r "$KIT/plantilla" "$KIT/instalar.sh" "$KIT/activar-en-mi-pc.sh" "$DEST.nuevo/"
    rm -rf "$DEST"
    mv "$DEST.nuevo" "$DEST"
fi
verde "✔ Kit en $DEST (versión $(grep -m1 '^VERSION_KIT=' "$DEST/plantilla/ci/revisar.sh" | cut -d'"' -f2))"

# 2. Hook global pre-push
ACTUAL=$(git config --global core.hooksPath || true)
if [ -n "$ACTUAL" ] && [ "${ACTUAL/#\~/$HOME}" != "$HOOKS" ]; then
    amar "⚠ core.hooksPath apunta a $ACTUAL (no a $HOOKS). No lo cambio: copia allí el pre-push si quieres."
fi
mkdir -p "$HOOKS"
cat > "$HOOKS/pre-push" <<'EOF'
#!/usr/bin/env bash
# CI Seguro · antes de CADA push, en CUALQUIER repo:
#   - siempre: busca secretos en todo el historial (gitleaks)
#   - si el repo tiene el kit (ci/revisar.sh): también revisa el código
# Usa SIEMPRE el motor de ~/.config/git/ci-seguro (no ejecuta código del repo).
# Saltar (si estás seguro; GitHub lo revisará igual): git push --no-verify
MOTOR="$HOME/.config/git/ci-seguro/plantilla/ci/revisar.sh"
RAIZ=$(git rev-parse --show-toplevel)
if [ -f "$MOTOR" ] && command -v docker >/dev/null 2>&1; then
    ETAPAS=(secretos)
    [ -f "$RAIZ/ci/revisar.sh" ] && ETAPAS+=(lint)
    echo "🔎 CI Seguro: revisando (${ETAPAS[*]}) antes de subir..."
    LOG=$(mktemp)
    if ! (cd "$RAIZ" && bash "$MOTOR" "${ETAPAS[@]}") >"$LOG" 2>&1; then
        tail -30 "$LOG"; rm -f "$LOG"
        echo "⛔ Push cancelado: arregla lo de arriba (o, si estás seguro: git push --no-verify)"
        exit 1
    fi
    rm -f "$LOG"
    echo "✔ Todo limpio, subiendo..."
else
    echo "⚠️  CI Seguro: sin Docker no puedo revisar aquí. GitHub lo revisará al subir."
fi
# Si el repo tiene su propio pre-push, también se ejecuta
if [ -x "$(git rev-parse --git-dir)/hooks/pre-push" ]; then
    "$(git rev-parse --git-dir)/hooks/pre-push" "$@" || exit 1
fi
exit 0
EOF
chmod +x "$HOOKS/pre-push"
[ -n "$ACTUAL" ] || git config --global core.hooksPath "$HOOKS"
verde "✔ Hook global pre-push (secretos en cada push de cualquier repo)"
[ -x "$HOOKS/pre-commit" ] || amar "  (no tienes el pre-commit global: ejecuta configurar-git.sh de tu Git-Guia)"

# 3. Atajos
git config --global alias.ci-seguro '!bash "$HOME/.config/git/ci-seguro/instalar.sh"'
git config --global alias.revisar   '!bash "$HOME/.config/git/ci-seguro/plantilla/ci/revisar.sh"'
verde "✔ Atajos:  git ci-seguro   (instala/actualiza el kit en el repo actual)"
verde "           git revisar     (revisa el repo actual ya, tenga o no el kit)"
echo
verde "🎉 CI Seguro activado para todos tus repos."
