#!/usr/bin/env bash
# Pruebas propias del kit
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "▶ La copia instalada en este repo es idéntica a la plantilla"
for f in ci/revisar.sh .github/workflows/ci.yml .github/workflows/release.yml; do
    cmp -s "$f" "plantilla/$f" || { echo "❌ $f difiere de plantilla/$f (vuelve a ejecutar: bash instalar.sh .)"; exit 1; }
done
echo "✔ Sincronizada"

echo "▶ Repos de mentira buenos y malos"
bash pruebas/autoprueba.sh
