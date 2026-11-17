<!-- source: workspace/tools/safe-browsing-simulator/README.md sha256:088492a196bfff34760580ab80a9555249dc3c1ba04771f7f2e09d9d24c67432 -->

# safe-browsing-simulator

- [O que é](#o-que-é)
- [Como rodar](#como-rodar)
- [Como uma aplicação usa](#como-uma-aplicação-usa)
- [Teste automatizado com instância própria](#teste-automatizado-com-instância-própria)
- [Arquivo de ameaças](#arquivo-de-ameaças)
- [Como a URL é comparada](#como-a-url-é-comparada)
- [Endpoint](#endpoint)
- [Como testar](#como-testar)
- [Dados e limites](#dados-e-limites)

## O que é

Substituto local do Google Safe Browsing para qualquer aplicação do workspace que verifica se uma URL é perigosa. Responde no caminho e no formato da API Lookup v4 (`POST /v4/threatMatches:find`): uma aplicação passa a usá-lo trocando só o endereço base. A chave de API é aceita com qualquer valor, ou sem valor, e nunca é conferida. As URLs perigosas e os domínios que simulam o serviço fora do ar vêm de um arquivo. Nunca chama o Google nem nada fora da máquina. Só Node e a biblioteca padrão, sem dependências; mesmo modelo do [`login-simulator`](../login-simulator/README.md).

| Endereço | Uso |
| --- | --- |
| `http://localhost:28090` | host: navegador, aplicação rodando fora do Docker |
| `http://safe-browsing-simulator:8080` | contêineres de outras stacks, pela rede Docker `safe-browsing-simulator` |

## Como rodar

Uma vez, da raiz do workspace; depois o Docker sobe a ferramenta junto com ele (`restart: unless-stopped`):

```bash
bash scripts/sync-env.sh --path tools/safe-browsing-simulator   # once: custom/env/safe-browsing-simulator.env from .env.example (or /local-env tools/safe-browsing-simulator)
docker compose --env-file custom/env/safe-browsing-simulator.env -f tools/safe-browsing-simulator/compose.yaml up -d --build
```

As configurações ficam na camada custom, `custom/env/safe-browsing-simulator.env`, nunca nesta pasta; são opcionais, então sem esse arquivo `--env-file tools/safe-browsing-simulator/.env.example` roda com os padrões. Uma mudança em `config/threats.json` vale ao reiniciar:

```bash
docker compose --env-file custom/env/safe-browsing-simulator.env -f tools/safe-browsing-simulator/compose.yaml restart
```

Arquivo inválido: o contêiner não sobe e o log (`docker logs safe-browsing-simulator-safe-browsing-simulator-1`) diz o campo e o problema. Mudança no código: `up -d --build` de novo. Fora do Docker, o servidor roda com `THREATS_PATH=config/threats.json PORT=28090 node src/main.js`.

## Como uma aplicação usa

1. Troque na configuração dela o endereço base da API (`https://safebrowsing.googleapis.com`) pelo do simulador. Caminho, corpo e chave ficam como estão; a chave pode ser qualquer valor.
2. Aplicação no host: `http://localhost:28090/v4/threatMatches:find`.
3. Backend em contêiner: ponha o serviço na rede externa e chame `http://safe-browsing-simulator:8080/v4/threatMatches:find`:

   ```yaml
   services:
     api:
       networks: [default, safe-browsing-simulator]
   networks:
     safe-browsing-simulator:
       external: true
   ```

As duas recebem a mesma resposta: a ferramenta nunca devolve endereços dela mesma.

## Teste automatizado com instância própria

O teste de um projeto sobe a imagem `safe-browsing-simulator:0.1.0` (gerada pelo `up --build` acima) na rede interna dele, com o próprio arquivo de ameaças. Nada sai da máquina e nada é compartilhado com a instância sempre ativa:

```yaml
services:
  safe-browsing:
    image: safe-browsing-simulator:0.1.0
    read_only: true
    volumes:
      - ./e2e/threats.json:/config/threats.json:ro
networks:
  default:
    internal: true
```

A aplicação sob teste chama `http://safe-browsing:8080/v4/threatMatches:find`.

## Arquivo de ameaças

`config/threats.json`. Campo desconhecido, URL inválida, tipo de ameaça fora da lista ou item repetido recusam o arquivo.

```json
{
  "threats": [
    { "url": "http://malware.testing.google.test/testing/malware/", "threatType": "MALWARE" }
  ],
  "unavailableDomains": ["pending.example.test"]
}
```

| Campo | Obrigatório | O que é |
| --- | --- | --- |
| `threats` | sim, pode ser vazia | URLs perigosas. Qualquer URL fora da lista é segura |
| `threats[].url` | sim | URL absoluta `http(s)`; comparada como em [Como a URL é comparada](#como-a-url-é-comparada) |
| `threats[].threatType` | sim | `MALWARE`, `SOCIAL_ENGINEERING`, `UNWANTED_SOFTWARE` ou `POTENTIALLY_HARMFUL_APPLICATION`. A mesma URL pode aparecer com mais de um tipo |
| `unavailableDomains` | não | Domínios em minúsculas, sem esquema nem porta. Uma consulta com qualquer URL de um deles, ou de um subdomínio, recebe `503` para o pedido inteiro |

O arquivo de exemplo, `config/threats.json`, traz:

| URL | Tipo | Origem |
| --- | --- | --- |
| `http://malware.testing.google.test/testing/malware/` | `MALWARE` | URL de teste do Google |
| `http://testsafebrowsing.appspot.com/s/malware.html` | `MALWARE` | Página de teste do Google, <https://testsafebrowsing.appspot.com/> |
| `http://testsafebrowsing.appspot.com/s/phishing.html` | `SOCIAL_ENGINEERING` | idem |
| `http://testsafebrowsing.appspot.com/s/unwanted.html` | `UNWANTED_SOFTWARE` | idem |
| `http://pha.safe-browsing-simulator.test/app.apk` | `POTENTIALLY_HARMFUL_APPLICATION` | fictícia: o Google não publica URL de teste desse tipo |

Domínios fora do ar: `unavailable.safe-browsing-simulator.test` e `pending.example.test`.

O arquivo padrão é um exemplo. O de verdade, com os domínios dos projetos, fica fora da ferramenta: o compose monta o caminho de `SAFE_BROWSING_THREATS`, relativo a esta pasta, e usa o exemplo quando a variável não existe. Para usar o da camada custom, defina `SAFE_BROWSING_THREATS=../../custom/config/safe-browsing-simulator/threats.json` em `custom/env/safe-browsing-simulator.env` e rode o `up -d` de novo. `custom/config/<tool>/` guarda a configuração das ferramentas do próprio workspace; `custom/tools/` é para ferramentas suas.

## Como a URL é comparada

Uma versão simplificada das expressões de host e caminho do Safe Browsing:

- esquema, porta, usuário, senha e fragmento são ignorados; o host fica em minúsculas, sem o ponto final. URL sem esquema (`site.test/x`) vale como `http`;
- o host consultado tem de ser o host listado ou um subdomínio dele (`evil.test` cobre `a.evil.test`);
- caminho listado terminado em `/` cobre ele mesmo e tudo abaixo (`/testing/malware/` cobre `/testing/malware/x`); sem `/` no fim, só o caminho exato;
- URL listada com query exige a mesma query; sem query, vale qualquer query.

## Endpoint

| Endpoint | O que faz |
| --- | --- |
| `POST /v4/threatMatches:find` | Lookup v4. `key` na query ou `X-Goog-Api-Key`, nunca conferida |
| `OPTIONS /v4/threatMatches:find` | Preflight do CORS (`Access-Control-Allow-Origin: *`) |
| `GET /healthz` | `{"status":"ok"}` |

Pedido, como o do Google: `{"client": {...}, "threatInfo": {"threatTypes": [...], "platformTypes": [...], "threatEntryTypes": ["URL"], "threatEntries": [{"url": "..."}]}}`.

Resposta:

- alguma URL perigosa: `200` com `{"matches": [...]}`, um item por URL perigosa, por tipo de ameaça pedido em `threatTypes` e por plataforma pedida em `platformTypes`: `threatType`, `platformType`, `threatEntryType: "URL"`, `threat: {"url": <the URL as sent>}` e `cacheDuration: "300s"`. Tipo de ameaça listado mas não pedido não volta, como no Google; sem `URL` em `threatEntryTypes`, nada volta;
- nenhuma perigosa: `200` com `{}`, como no Google;
- alguma URL de domínio fora do ar: `503`, para o pedido inteiro;
- pedido inválido (JSON inválido, campo desconhecido, lista de tipos vazia ou com valor fora da API, `url` que não é texto, mais de 500 entradas): `400`.

Os erros seguem o formato das APIs do Google: `{"error": {"code": 503, "message": "...", "status": "UNAVAILABLE"}}`. Entradas com `hash` ou `digest` em vez de `url` são aceitas e nunca casam.

## Como testar

```bash
docker run --rm --network none -v "$PWD/tools/safe-browsing-simulator":/app:ro -w /app \
  node:24-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 node --test
```

Os testes sobem o servidor numa porta livre de `127.0.0.1` e cobrem AC-1 a AC-3 (URL de teste de malware, consulta mista e toda segura, serviço fora do ar), a comparação de URLs, as recusas do pedido e do arquivo e o log. AC-4 (mesma resposta no host e num contêiner da rede) e AC-5 (instância própria com outro arquivo numa rede interna) são conferidos com os contêineres rodando.

## Dados e limites

- O arquivo é versionado: só URLs de teste públicas ou fictícias (`.test`).
- O log traz só eventos e contagens: nunca uma URL consultada nem a chave.
- Nada vai para disco; nada sai da máquina. A porta só escuta em `127.0.0.1`; nunca vai para produção.
- Fora do escopo: API v5, Update API (listas locais por prefixo de hash) e a comparação por hash.
