<!-- source: workspace/docker/README.md sha256:54ae8f3ba9b93c21ff75f52a849e6024370d241358fb2baaddc32c6a550caf25 -->

# docker/

Caja de herramientas de soporte y validación en contenedores. Nada que instalar en el host aparte de Docker. Punto de entrada: `scripts/validate.sh`.
Reglas para agregar o actualizar herramientas: `rules/rules.md` "Tooling".

## Herramientas (`compose.yaml`)

| Servicio | Herramienta | Verificación en validate.sh | Propósito |
| --- | --- | --- | --- |
| terraform | Terraform 1.17.1 | terraform | fmt, init sin backend, validate |
| tflint | TFLint v0.65.0 | terraform | lint de Terraform (preset recommended de `config/tflint.hcl`; un `.tflint.hcl` de módulo con rulesets de provider tiene prioridad) |
| trivy | Trivy 0.76.1 | vuln, iac | CVEs de dependencias, secretos, errores de configuración de IaC (también `trivy image`) |
| gitleaks | Gitleaks v8.30.1 | secrets | secretos en archivos, config `config/gitleaks.toml`; `gitleaks git` para el historial corre solo con las reglas por defecto, nunca con esa config (`rules/security.md` "Secrets") |
| shellcheck | ShellCheck v0.11.0 | shell | lint de bash |
| hadolint | Hadolint v2.15.1 | dockerfile | lint de Dockerfile |
| markdownlint | markdownlint-cli2 v0.24.0 | markdown | lint de Markdown |
| mermaid | mermaid-cli 12.0.1 | mermaid | renderiza los diagramas para demostrar que se parsean |
| infracost | Infracost 0.10.47 | cost | costo mensual a partir de Terraform; necesita `INFRACOST_API_KEY` en `custom/env/docker.env` |
| ruff | Ruff 0.17.3 | python | lint y verificación de formato de Python, config `config/ruff.toml` |
| biome | Biome 2.6.4, binario estático de la imagen oficial en una imagen `scratch` (construida desde `biome/`) | typescript | `biome ci` sobre `*.ts` y `*.tsx`, config `config/biome.json` |
| python-coverage | coverage.py 7.17.0 sobre `python:3.14.10-alpine` (construida desde `python-coverage/`) | coverage | ejecuta las pruebas de cada objetivo de cobertura y aplica el gate por módulo de `rules/quality.md` |

- Imágenes fijadas por tag@digest. Trivy: nunca uses 0.69.4–0.69.6 (GHSA-69fq-xp46-6x23).
- `ruff`, `biome` y `python-coverage` se aplican solo al código que es del workspace: `validate.sh` ignora `projects/` para ellas, y también `tools/` para `python-coverage` (`rules/rules.md` "Workspace layout"), e imprime `SKIP <check> (no targets)` cuando no queda nada.
- Ejecución ad hoc: `WORKSPACE_DIR="$PWD" docker compose -f docker/compose.yaml run --rm -T <service> <args>`; el workspace se monta en `/work`.
- Variables y secretos: el archivo rellenado vive en la capa custom, `custom/env/docker.env` (ignorado por git allí), creado a partir de `.env.example` con `/local-env docker` en una sesión o `bash scripts/sync-env.sh --path docker`. `scripts/validate.sh` se lo pasa a compose con `--env-file`; sin él, valen los valores por defecto de `.env.example` (solo `cost` necesita una clave). Nunca se escribe un `.env` en `docker/`.
- El workspace se monta de solo lectura en cada contenedor, que corre como root y de otro modo pasaría por encima del core de solo lectura de un workspace instalado. Solo `terraform` e `infracost` escriben, y solo en la carpeta del módulo que `validate.sh` monta con escritura encima, cuando está en `projects/`, `tmp/` o `custom/`.

## Verificación de cobertura (`python-coverage/`)

- Opt-in: cada carpeta que tiene un `.coveragerc`, fuera de `projects/` y `tools/`, es un objetivo; si no encuentra ninguno imprime `SKIP coverage (no targets)` y sale con 0, porque no se midió nada.
- En cada objetivo el contenedor ejecuta `coverage run -m unittest discover -s tests`. Una prueba que falla hace fallar la verificación, y también cualquier módulo medido por debajo del 85% de líneas o del 85% de ramas. Un módulo sin ramas pasa la parte de ramas.
- Cada etapa (pruebas, informe) debe terminar dentro de `COVERAGE_TIMEOUT_SECONDS`, segundos enteros desde el shell de `validate.sh`, 600 por defecto. Una etapa colgada se mata y hace fallar la verificación, indicando el plazo; un valor inválido falla antes de que corra nada.
- El contenedor corre sin root, con el workspace montado en solo lectura y sin red; los datos y el informe quedan bajo `/tmp`. `validate.sh` reconstruye la imagen cuando cambia (el primer build necesita red).
- `run_coverage.py` es el punto de entrada del contenedor y `check_coverage.py` el gate; sus pruebas se someten a esta misma verificación. El archivo de lock `requirements.txt` se instala con `pip --require-hashes`; pip se quita de la imagen después.
- La base es Alpine: musl libc, `/bin/sh` de BusyBox y sin bash, así que las pruebas de un objetivo solo pueden ejecutar lo que tiene la imagen. `pty.fork` más exec funciona sin root y sin red; el hijo hace exec antes de que coverage guarde sus datos, así que marca esa rama con `# pragma: no cover`.
- `.coveragerc` de un objetivo (`include_namespace_packages` también mide carpetas sin `__init__.py` que ninguna prueba importa):

```ini
[run]
branch = True
source = .
omit = tests/*

[report]
include_namespace_packages = True
```

- Las pruebas viven en `<target>/tests/test_*.py` y ponen ellas mismas el objetivo en `sys.path`, así que también corren con `python3 -I -B -m unittest discover -s tests` en el host (`-B`: sin `__pycache__` en una carpeta de solo lectura), sin `PYTHONPATH`:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import my_module
```

## Sonar (`sonar/compose.yaml`, opcional)

- SonarQube Community Build 26.10 + PostgreSQL 17.11 + sonar-scanner-cli 12.3. Interfaz en `http://127.0.0.1:29000`.
- Configuración: `/local-env docker/sonar` en una sesión (o `bash scripts/sync-env.sh --path docker/sonar`) crea `custom/env/docker-sonar.env`; define `SONAR_DB_PASSWORD` en él; `bash scripts/sonar.sh up`; crea un token en la interfaz; define `SONAR_TOKEN`. `sonar.sh` pasa el archivo con `--env-file` y se detiene, nombrando `/local-env`, cuando falta.
- El scanner monta el workspace de solo lectura; su carpeta de trabajo (`.scannerwork`) queda en el `/tmp` del contenedor, nunca en la carpeta escaneada.
- SonarQube necesita `vm.max_map_count >= 524288`; en este host Linux configúralo con `sysctl` en el host.
- Informes de cobertura y exclusiones: `sonar-project.properties` en la carpeta escaneada.
