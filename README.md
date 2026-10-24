# 🛡 CI Seguro

Pipeline CI/CD **universal** para publicar cualquier repo sin filtrar secretos, con pruebas antes de publicar y con publicación firmada y aprobada a mano.
Sirve para Python, Bash, Node, Go, Rust, Docker… porque **detecta qué hay en cada repo** y solo aplica lo que corresponde.

```
 TU PC                                             GITHUB
 git commit ─► 🛡 pre-commit (global)  .env, llaves, tokens, archivos enormes
 git push ───► 🛡 pre-push   (global)  secretos en TODO el historial, en cualquier repo
                       │
                       ▼
        CI (cada push y pull request) ─ bash ci/revisar.sh
          1 secretos     gitleaks, todo el historial
          2 lint         ruff+bandit · shellcheck · hadolint · actionlint + acciones fijadas por hash
          3 config       trivy config (Dockerfile, compose, Kubernetes, Terraform…)
          4 deps         trivy fs (requirements, package-lock, go.sum, Cargo.lock…)
          5 build        imagen Docker (si hay Dockerfile)
          6 pruebas      ci/pruebas.sh del repo, o prueba genérica de arranque endurecido
          7 vulnerab.    trivy image
                       │ ✅
 git tag v1.0.0 ───────┤
                       ▼
        Release ─ CI completo → ⏸ tu aprobación → publica firmado
          con Docker:  imagen en ghcr.io + firma Sigstore + SBOM + procedencia
          sin Docker:  .tar.gz/.zip del código + SHA256SUMS + procedencia
```

## Instalación (una vez en tu PC)

```bash
git clone https://github.com/diriartev/ci-seguro.git
bash ci-seguro/activar-en-mi-pc.sh
```

Esto deja el kit en `~/.config/git/ci-seguro` y crea:

| Qué | Para qué |
| --- | --- |
| hook global `pre-push` | antes de **cada** push, en **cualquier** repo: busca secretos en todo el historial. Si el repo tiene el kit, también revisa el código |
| `git ci-seguro` | instala o actualiza el kit en el repo donde estás |
| `git revisar` | revisa el repo actual ya mismo, tenga o no el kit (`git revisar secretos lint`) |

Requisitos: `git` y `docker`. Las herramientas corren en contenedores fijados por digest; no hay que instalarlas.

## Añadir el pipeline a un repo (cualquiera)

```bash
cd mi-proyecto
git ci-seguro                 # añade ci/, .github/workflows/, dependabot.yml, SECURITY.md
bash ci/revisar.sh            # pruébalo en tu PC: es EXACTAMENTE lo mismo que corre GitHub
git add ci .github SECURITY.md && git commit -m "CI Seguro" && git push
```

- Si el repo ya tenía `ci.yml` o `release.yml` propios, no se tocan. Con `git ci-seguro --forzar` se reemplazan y se guarda una copia en `ci/respaldo/`.
- Para actualizar el kit en un repo, vuelve a ejecutar `git ci-seguro`.

### Pruebas propias

Si no hay `ci/pruebas.sh`, el kit hace una **prueba genérica**: si hay Dockerfile, comprueba que la imagen no corra como root y que arranque sin privilegios ni red (y que el HEALTHCHECK diga *healthy*).
Para pruebas reales:

```bash
cp ci/pruebas.ejemplo.sh ci/pruebas.sh     # trae ejemplos para pytest, npm y servicios Docker
```

`ci/pruebas.sh` recibe la variable `$IMAGEN` con la imagen recién construida. Si termina con error, no se publica nada.

### Ajustes opcionales (`ci/ajustes.conf`)

```bash
cp ci/ajustes.ejemplo.conf ci/ajustes.conf
```

| Clave | Por defecto | Para qué |
| --- | --- | --- |
| `DOCKERFILE` / `CONTEXTO` | `Dockerfile` / `.` | si tu Dockerfile no está en la raíz |
| `SEVERIDAD_FALLO` | `CRITICAL` | `HIGH,CRITICAL` para ser más estricto |
| `OMITIR` | vacío | etapas a saltar, p. ej. `deps` |
| `LIBERAR_ESPACIO` | `0` | `1` si la imagen pesa varios GB (libera disco en GitHub) |

El archivo se **lee como texto**, nunca se ejecuta: solo acepta estas claves.

Más ajustes, con los archivos estándar de cada herramienta: `ruff.toml`, `.hadolint.yaml`, `.gitleaks.toml` / `.gitleaksignore` y `.trivyignore`.

## Una vez por repo en GitHub

1. **Settings → Advanced Security**: Dependabot alerts y security updates, Secret Protection + **Push protection**, Private vulnerability reporting y CodeQL (Default).
2. **Settings → Actions → General**: ✅ *Require actions to be pinned to a full-length commit SHA* · *Workflow permissions*: **Read**.
3. **Settings → Environments → New environment** `produccion`: **Required reviewers** = tú · *Deployment branches and tags* → regla de tipo **Tag** `v*.*.*`.
4. **Settings → Rules → Rulesets**: proteger `main` (sin borrar ni force push) y las etiquetas `v*` (sin mover ni borrar).
5. **Settings → General → Releases**: ✅ *Enable release immutability*.

## Publicar una versión

```bash
git tag -s v1.0.0 -m "Versión 1.0.0" && git push origin v1.0.0
```

GitHub repite todo el CI, te pide la aprobación (**Actions → Review deployments → Approve**) y publica.
La primera vez que publiques una imagen: **Packages → el paquete → Package settings → Change visibility → Public**.

## Por qué es seguro

- **Cero secretos guardados.** Se publica con el token temporal de cada ejecución y se firma con Sigstore (identidad OIDC, sin llave privada).
- **Mínimo privilegio.** El CI solo lee. Solo el job de publicar, y solo tras tu aprobación, puede escribir.
- **Nada cambia por detrás.** Acciones fijadas por hash de commit (el propio CI lo exige) y herramientas por digest.
- **Logs sin fugas.** gitleaks usa `--redact`.
- **El mismo motor en local y en GitHub.** Si pasa en tu PC, pasa en GitHub.
- **Los ajustes no ejecutan código.** El hook global usa siempre el motor de `~/.config/git/ci-seguro`, no el del repo.

## Probar el propio kit

```bash
bash ci/revisar.sh          # el kit se revisa a sí mismo; incluye pruebas/autoprueba.sh
```

La autoprueba crea repos de mentira y comprueba que el motor **bloquea**: un secreto escondido en un commit antiguo, `eval`/`os.system`, `rm -rf $VAR`, acciones sin fijar, imágenes que corren como root y dependencias con CVE crítico. También comprueba que deja pasar los repos limpios y que `ajustes.conf` no ejecuta código.
