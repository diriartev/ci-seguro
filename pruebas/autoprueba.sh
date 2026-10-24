#!/usr/bin/env bash
# ==============================================================================
#  Autoprueba del kit: crea repos de mentira de distintos tipos y comprueba que
#  revisar.sh deja pasar lo bueno y BLOQUEA lo malo. Se ejecuta en el CI del kit.
#    bash pruebas/autoprueba.sh
# ==============================================================================
set -euo pipefail
KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MOTOR="$KIT/plantilla/ci/revisar.sh"
BASE=$(mktemp -d -p "${TMPDIR:-/tmp}" autoprueba-XXXX)
trap 'rm -rf "$BASE"; docker rmi -f rep-docker-bien:ci rep-docker-root:ci >/dev/null 2>&1 || true' EXIT
OK=0; MAL=0

# git aislado: sin tus hooks globales, sin firma, identidad de prueba
G=(git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false
   -c user.name=prueba -c user.email=prueba@example.invalid -c init.defaultBranch=main)

nuevo_repo() {   # nuevo_repo nombre  -> crea y entra
    mkdir -p "$BASE/$1"; cd "$BASE/$1"; "${G[@]}" init -q
}
commit() { "${G[@]}" add -A; "${G[@]}" commit -qm "$1"; }

espera() {       # espera pasa|falla "descripción" "motivo esperado (regex)" etapas...
    local esperado=$1 desc=$2 motivo=$3; shift 3
    if bash "$MOTOR" "$@" >"$BASE/log" 2>&1; then r=pasa; else r=falla; fi
    if [ "$r" = falla ] && [ -n "$motivo" ] && ! grep -qE "$motivo" "$BASE/log"; then
        printf '\033[1;31m  ✘ %s: falló, pero NO por "%s"\033[0m\n' "$desc" "$motivo"; tail -20 "$BASE/log"; MAL=$((MAL+1))
    elif [ "$r" = "$esperado" ]; then
        printf '\033[1;32m  ✔ %s (%s, como debe)\033[0m\n' "$desc" "$r"; OK=$((OK+1))
    else
        printf '\033[1;31m  ✘ %s: esperaba %s y dio %s\033[0m\n' "$desc" "$esperado" "$r"; tail -20 "$BASE/log"; MAL=$((MAL+1))
    fi
}

echo "▶ 1. Repo Python + Bash limpio"
nuevo_repo rep-limpio
printf 'def hola(nombre: str) -> str:\n    return f"hola {nombre}"\n' > app.py
printf '#!/usr/bin/env bash\nset -euo pipefail\necho "hola"\n' > run.sh
commit "inicio"
espera pasa "repo limpio" "" secretos lint config deps

echo "▶ 2. Secreto en un commit ANTIGUO (ya borrado del código)"
nuevo_repo rep-secreto
echo "x = 1" > a.py; commit "inicio"
printf 'AWS_KEY = "%s%s"\n' "AKIA" "$(LC_ALL=C tr -dc 'A-Z2-7' </dev/urandom | head -c16)" > config.py; commit "ups"
rm config.py; commit "borrado"
espera falla "secreto escondido en el historial" "leaks found" secretos
grep -q 'AKIA[A-Z2-7]\{16\}' "$BASE/log" && { echo "  ✘ el log muestra el secreto"; MAL=$((MAL+1)); } \
    || { echo "  ✔ el log no muestra el secreto (REDACTED)"; OK=$((OK+1)); }

echo "▶ 3. Código Python peligroso"
nuevo_repo rep-python-malo
printf 'import os\n\ndef run(cmd):\n    os.system("ls " + cmd)\n    return eval(cmd)\n' > app.py; commit "inicio"
espera falla "os.system / eval (bandit)" "S605|S307" lint

echo "▶ 4. Script Bash con error"
nuevo_repo rep-bash-malo
printf '#!/usr/bin/env bash\nrm -rf $CARPETA/*\n' > borrar.sh; commit "inicio"
espera falla "variable sin comillas en rm -rf (shellcheck)" "SC2115|SC2086" lint

echo "▶ 5. Workflow con acción sin fijar por hash"
nuevo_repo rep-wf-malo
mkdir -p .github/workflows
printf 'name: x\non: push\npermissions: {}\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout@v4\n' \
    > .github/workflows/x.yml; commit "inicio"
espera falla "actions/checkout@v4 sin hash" "sin fijar por hash" lint

echo "▶ 6. Docker corriendo como root"
nuevo_repo rep-docker-root
printf 'FROM alpine:3.22\nCMD ["sleep", "300"]\n' > Dockerfile; commit "inicio"
espera falla "imagen sin USER (trivy config)" "DS-?0*02" config
espera falla "imagen sin USER (prueba de arranque)" "corre como root" build pruebas

echo "▶ 7. Docker bien hecho (usuario sin privilegios)"
nuevo_repo rep-docker-bien
printf 'FROM alpine:3.22\nUSER 65534:65534\nHEALTHCHECK CMD ["true"]\nCMD ["sleep", "300"]\n' > Dockerfile; commit "inicio"
espera pasa "imagen endurecida: build + arranque + vulnerabilidades" "" lint config build pruebas vulnerabilidades

echo "▶ 8. Dependencia con vulnerabilidad CRÍTICA conocida"
nuevo_repo rep-deps-malo
echo "PyYAML==5.3" > requirements.txt; commit "inicio"
espera falla "PyYAML 5.3 (CVE-2020-14343, crítica)" "CVE-2020-14343" deps

echo "▶ 9. ci/ajustes.conf no ejecuta código"
nuevo_repo rep-ajustes
mkdir ci
# shellcheck disable=SC2016  # el $(...) es literal a propósito: no debe ejecutarse
printf 'OMITIR=$(touch %s/pwned)\nOTRA=1\nSEVERIDAD_FALLO=CRITICAL\n' "$BASE" > ci/ajustes.conf
echo "x = 1" > a.py; commit "inicio"
bash "$MOTOR" info >/dev/null 2>&1 || true
if [ -e "$BASE/pwned" ]; then echo "  ✘ ajustes.conf ejecutó código"; MAL=$((MAL+1))
else echo "  ✔ ajustes.conf se lee como texto, no se ejecuta"; OK=$((OK+1)); fi

echo "▶ 10. Instalador en un repo sin nada"
nuevo_repo rep-instalar
echo '{"name":"x"}' > package.json; echo "flask==3.1.1" > requirements.txt; commit "inicio"
bash "$KIT/instalar.sh" . >/dev/null
for f in ci/revisar.sh .github/workflows/ci.yml .github/workflows/release.yml .github/dependabot.yml SECURITY.md; do
    [ -f "$f" ] || { echo "  ✘ falta $f"; MAL=$((MAL+1)); continue; }
done
if grep -q 'npm' .github/dependabot.yml && grep -q 'pip' .github/dependabot.yml; then
    echo "  ✔ instala todo y detecta npm + pip para Dependabot"; OK=$((OK+1))
else echo "  ✘ dependabot.yml incompleto"; MAL=$((MAL+1)); fi
commit "ci"
espera pasa "repo recién instalado pasa sus propios workflows" "" lint

echo
echo "Resultado: $OK bien, $MAL mal"
[ "$MAL" -eq 0 ]
