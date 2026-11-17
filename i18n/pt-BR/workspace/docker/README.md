<!-- source: workspace/docker/README.md sha256:54ae8f3ba9b93c21ff75f52a849e6024370d241358fb2baaddc32c6a550caf25 -->

# docker/

Caixa de ferramentas de apoio e validação em contêiner. Nada a instalar no host além do Docker. Ponto de entrada: `scripts/validate.sh`.
Regras para acrescentar ou atualizar ferramentas: `rules/rules.md` "Tooling".

## Ferramentas (`compose.yaml`)

| Serviço | Ferramenta | Check no validate.sh | Para quê |
| --- | --- | --- | --- |
| terraform | Terraform 1.17.1 | terraform | fmt, init sem backend, validate |
| tflint | TFLint v0.65.0 | terraform | lint de Terraform (preset recomendado em `config/tflint.hcl`; um `.tflint.hcl` do módulo com rulesets de provider tem precedência) |
| trivy | Trivy 0.76.1 | vuln, iac | CVEs de dependências, segredos, erros de configuração de IaC (também `trivy image`) |
| gitleaks | Gitleaks v8.30.1 | secrets | segredos em arquivos, config `config/gitleaks.toml`; `gitleaks git` para o histórico roda só com as regras padrão, nunca com essa config (`rules/security.md` "Secrets") |
| shellcheck | ShellCheck v0.11.0 | shell | lint de bash |
| hadolint | Hadolint v2.15.1 | dockerfile | lint de Dockerfile |
| markdownlint | markdownlint-cli2 v0.24.0 | markdown | lint de Markdown |
| mermaid | mermaid-cli 12.0.1 | mermaid | renderiza os diagramas para provar que fazem parse |
| infracost | Infracost 0.10.47 | cost | custo mensal a partir do Terraform; precisa de `INFRACOST_API_KEY` em `custom/env/docker.env` |
| ruff | Ruff 0.17.3 | python | lint e checagem de formatação de Python, config `config/ruff.toml` |
| biome | Biome 2.6.4, binário estático da imagem oficial numa imagem `scratch` (construída a partir de `biome/`) | typescript | `biome ci` em `*.ts` e `*.tsx`, config `config/biome.json` |
| python-coverage | coverage.py 7.17.0 sobre `python:3.14.10-alpine` (construída a partir de `python-coverage/`) | coverage | roda os testes de cada alvo de cobertura e aplica o gate por módulo de `rules/quality.md` |

- Imagens fixadas por tag@digest. Trivy: nunca use 0.69.4–0.69.6 (GHSA-69fq-xp46-6x23).
- `ruff`, `biome` e `python-coverage` valem só para código que é do workspace: o `validate.sh` ignora `projects/` para eles, e também `tools/` para o `python-coverage` (`rules/rules.md` "Workspace layout"), e mostra `SKIP <check> (no targets)` quando não sobra nada.
- Execução avulsa: `WORKSPACE_DIR="$PWD" docker compose -f docker/compose.yaml run --rm -T <service> <args>`; o workspace é montado em `/work`.
- Variáveis e segredos: o arquivo preenchido fica na camada custom, `custom/env/docker.env` (ignorado pelo git lá), criado a partir do `.env.example` com `/local-env docker` numa sessão ou `bash scripts/sync-env.sh --path docker`. O `scripts/validate.sh` o passa ao compose com `--env-file`; sem ele, valem os padrões do `.env.example` (só o `cost` precisa de uma chave). Nenhum `.env` é escrito em `docker/`.
- O workspace é montado só leitura em todo contêiner, que roda como root e, de outro modo, passaria por cima do core só leitura de um workspace instalado. Só `terraform` e `infracost` escrevem, e só na pasta do módulo que o `validate.sh` monta com escrita por cima, quando ela está em `projects/`, `tmp/` ou `custom/`.

## Check de cobertura (`python-coverage/`)

- Opt-in: toda pasta com um `.coveragerc`, fora de `projects/` e `tools/`, é um alvo; sem nenhum, mostra `SKIP coverage (no targets)` e sai com 0, porque nada foi medido.
- Em cada alvo o contêiner roda `coverage run -m unittest discover -s tests`. Um teste falhando derruba o check, e também qualquer módulo medido abaixo de 85% de linhas ou 85% de ramos. Um módulo sem ramos passa na parte de ramos.
- Cada passo (testes, relatório) precisa terminar dentro de `COVERAGE_TIMEOUT_SECONDS`, em segundos inteiros, vindo do shell do `validate.sh`, padrão 600. Um passo travado é morto e derruba o check, dizendo o prazo; um valor inválido falha antes de qualquer coisa rodar.
- O contêiner roda sem root, com o workspace montado só para leitura e sem rede; dados e relatório ficam em `/tmp`. O `validate.sh` reconstrói a imagem quando ela muda (o primeiro build precisa de rede).
- `run_coverage.py` é o ponto de entrada do contêiner e `check_coverage.py` o gate; os testes deles usam o próprio check (dogfood). O arquivo de lock `requirements.txt` é instalado com `pip --require-hashes`; o pip é removido da imagem depois.
- A base é Alpine: musl libc, `/bin/sh` do BusyBox e sem bash, então os testes de um alvo só podem executar o que a imagem tem. `pty.fork` mais exec funciona sem root e sem rede; o filho faz exec antes de o coverage salvar os dados, então marque esse ramo com `# pragma: no cover`.
- `.coveragerc` de um alvo (`include_namespace_packages` também mede pastas sem `__init__.py` que nenhum teste importa):

```ini
[run]
branch = True
source = .
omit = tests/*

[report]
include_namespace_packages = True
```

- Os testes ficam em `<target>/tests/test_*.py` e colocam o alvo no `sys.path` eles mesmos, então também rodam com `python3 -I -B -m unittest discover -s tests` no host (`-B`: sem `__pycache__` numa pasta só leitura), sem `PYTHONPATH`:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import my_module
```

## Sonar (`sonar/compose.yaml`, opcional)

- SonarQube Community Build 26.10 + PostgreSQL 17.11 + sonar-scanner-cli 12.3. Interface em `http://127.0.0.1:29000`.
- Setup: `/local-env docker/sonar` numa sessão (ou `bash scripts/sync-env.sh --path docker/sonar`) cria `custom/env/docker-sonar.env`; defina `SONAR_DB_PASSWORD` nele; `bash scripts/sonar.sh up`; crie um token na interface; defina `SONAR_TOKEN`. O `sonar.sh` passa o arquivo com `--env-file` e para, citando `/local-env`, quando ele não existe.
- O scanner monta o workspace só leitura; a pasta de trabalho dele (`.scannerwork`) fica no `/tmp` do contêiner, nunca na pasta escaneada.
- O SonarQube precisa de `vm.max_map_count >= 524288`; neste host Linux, defina com `sysctl` no host.
- Relatórios de cobertura e exclusões: `sonar-project.properties` na pasta analisada.
