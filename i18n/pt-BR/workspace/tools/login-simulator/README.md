<!-- source: workspace/tools/login-simulator/README.md sha256:bd07d92c8d77fa70665a1c6033b909ebe6d431c0a8001deadd61079979f4fcec -->

# login-simulator

- [O que é](#o-que-é)
- [Como rodar](#como-rodar)
- [Arquivo de configuração](#arquivo-de-configuração)
- [Como uma aplicação usa](#como-uma-aplicação-usa)
- [Avatar gerado](#avatar-gerado)
- [Teste automatizado com instância própria](#teste-automatizado-com-instância-própria)
- [Endpoints](#endpoints)
- [Como testar](#como-testar)
- [Dados pessoais e limites](#dados-pessoais-e-limites)

## O que é

Substituto local do Auth0 para qualquer aplicação do workspace que precise de login. A página de login lista usuários fictícios fixos; um clique entra, sem senha e sem internet. Fala o OpenID Connect do Auth0 (login com PKCE, troca do código por tokens, chaves de assinatura, dados do usuário e logout): uma aplicação feita para o Auth0 passa a usá-lo trocando só o endereço e o client id. Só Node e a biblioteca padrão, sem dependências.

| Porta | Uso |
| --- | --- |
| `28080` | navegador: <http://localhost:28080> |
| `login-simulator:8080` | contêineres de outras stacks, pela rede Docker `login-simulator` |
| `172.31.250.10:8080` | avatares gerados: o mesmo endereço no navegador e nos contêineres da rede ([Avatar gerado](#avatar-gerado)) |

## Como rodar

Uma vez, da raiz do workspace; depois o Docker sobe a ferramenta junto com ele (`restart: unless-stopped`):

```bash
bash scripts/sync-env.sh --path tools/login-simulator   # once: custom/env/login-simulator.env from .env.example (or /local-env tools/login-simulator)
docker compose --env-file custom/env/login-simulator.env -f tools/login-simulator/compose.yaml up -d --build
```

As configurações ficam na camada custom, `custom/env/login-simulator.env`, nunca nesta pasta; são opcionais, então sem esse arquivo `--env-file tools/login-simulator/.env.example` roda com os padrões. Uma mudança em `config/config.json` vale ao reiniciar:

```bash
docker compose --env-file custom/env/login-simulator.env -f tools/login-simulator/compose.yaml restart
```

Arquivo inválido ou `AVATAR_ORIGIN` inválido: o contêiner não sobe e o log (`docker logs login-simulator-login-simulator-1`) diz o campo e o problema. Mudança no código: `up -d --build` de novo.

## Arquivo de configuração

O arquivo de configuração registra as aplicações e os usuários. Campo desconhecido, URL inválida, tipo errado ou id repetido recusam o arquivo.

- `config/config.json` é um exemplo: duas aplicações fictícias e os usuários de cada uma, cobrindo papéis, permissões, MFA, login social e e-mail não verificado.
- O arquivo de verdade, com as aplicações dos projetos, fica fora da ferramenta. O compose monta o caminho de `LOGIN_SIMULATOR_CONFIG`, relativo a esta pasta, e usa o exemplo quando a variável não existe. Para usar o da camada custom, defina `LOGIN_SIMULATOR_CONFIG=../../custom/config/login-simulator/config.json` em `custom/env/login-simulator.env` e rode o `up -d` de novo. `custom/config/<tool>/` guarda a configuração das ferramentas do próprio workspace; `custom/tools/` é para ferramentas suas.

```json
{
  "issuer": "http://localhost:28080/",
  "applications": [
    { "name": "Example (local)", "clientId": "example-local",
      "callbackUrls": ["http://localhost:4200/auth"], "logoutUrls": ["http://localhost:4200/"] }
  ],
  "users": [
    { "id": "local|ana", "givenName": "Ana", "familyName": "Test", "email": "ana@example.local",
      "roles": ["admin"], "permissions": ["links:read", "links:write"] }
  ]
}
```

| Campo | Obrigatório | O que é |
| --- | --- | --- |
| `issuer` | sim | `iss` dos tokens, fixo. Use o endereço que o navegador vê, com `/` no fim, como no Auth0 |
| `applications[].name` | sim | nome mostrado na página de login |
| `applications[].clientId` | sim | client id da aplicação |
| `applications[].callbackUrls` | sim | retornos de login permitidos (Allowed Callback URLs) |
| `applications[].logoutUrls` | não | retornos de logout permitidos (Allowed Logout URLs) |
| `applications[].clientSecret` | não | só para aplicação confidencial (backend); sem ele, o PKCE é obrigatório. Valor fictício: o arquivo é versionado |
| `applications[].rolesClaim` | não | nome do claim dos papéis, o mesmo da Action do Auth0 da aplicação (ex.: `https://app/roles`); padrão `roles` |
| `users[].id` | sim | `sub` dos tokens, no formato do Auth0 (`<provider>\|<id>`, ex.: `google-oauth2\|...` para login social) |
| `users[].givenName`, `familyName`, `email` | sim | nome, sobrenome e e-mail. Dois ids podem ter o mesmo e-mail: a mesma pessoa por dois provedores |
| `users[].emailVerified` | não | `true` ou `false`, vai em `email_verified` no ID token e no `/userinfo`; padrão `true` |
| `users[].picture` | não | URL `http(s)` ou `data:image/...`, que sai como está; sem ela, a ferramenta gera um mascote em SVG, sempre o mesmo para o mesmo id ([Avatar gerado](#avatar-gerado)). O avatar gerado de qualquer usuário serve como foto fixa (ex.: `http://172.31.250.10:8080/avatars/<id in base64url>.svg`), que abre sem internet |
| `users[].roles`, `permissions` | não | tipos de acesso; vão no claim de papéis e em `permissions` |
| `users[].amr` | não | lista de textos (ex.: `["mfa"]`), vai no claim `amr` do ID token e do access token, como a Action de MFA do Auth0. Sem ele, nenhum token traz `amr`. O MFA não é pedido na tela: vem do arquivo |

Os usuários valem para todas as aplicações, como os de um tenant do Auth0. A página de login mostra o `amr` e marca o e-mail não verificado.

## Como uma aplicação usa

1. Registre a aplicação em `config/config.json` e reinicie.
2. Troque na configuração dela o domínio do Auth0 por `http://localhost:28080` e o client id pelo registrado. SDK do Auth0 no navegador (`auth0-spa-js`, `auth0-angular`, `auth0-react`): `domain: "http://localhost:28080"`.
3. Backend em contêiner: ponha o serviço na rede externa e chame a ferramenta por `http://login-simulator:8080`:

   ```yaml
   services:
     api:
       networks: [default, login-simulator]
   networks:
     login-simulator:
       external: true
   ```

O `iss` é sempre o `issuer` do arquivo; os endereços do discovery (`/.well-known/openid-configuration`) seguem o host por onde o pedido chegou. Assim o navegador recebe `localhost:28080` e o backend recebe `login-simulator:8080`, e os dois validam o mesmo `iss`. O avatar gerado tem um endereço só, que os dois abrem: veja abaixo.

## Avatar gerado

O avatar gerado de um usuário sem `picture` fica em `<AVATAR_ORIGIN>/avatars/<id in base64url>.svg`, a mesma URL no ID token, no `/userinfo` e na página de login, venha o pedido do navegador ou da rede Docker. Na instância sempre ativa, `AVATAR_ORIGIN` é `http://172.31.250.10:8080` (`compose.yaml`): o simulador tem esse endereço fixo na rede `login-simulator`, e o Docker Engine no Linux deixa o próprio host abrir endereços de contêiner. Assim:

- o navegador abre o avatar, sem configuração;
- um backend em contêiner na rede `login-simulator` baixa a mesma URL, sem configuração além de estar na rede (passo 3 acima). Um contêiner fora da rede não alcança.

Sem `AVATAR_ORIGIN` (a instância própria de um teste e2e), o avatar gerado usa a origem do `issuer`. Uma `picture` do arquivo nunca é reescrita.

Por que não `localhost:28080` ou um nome `*.localhost`: dentro de um contêiner, `localhost` é o próprio contêiner, e o curl (e outros clientes HTTP) resolve qualquer `*.localhost` para o loopback sem perguntar ao DNS do Docker. Só o endereço do contêiner serve aos dois lados.

Limites: no Docker Desktop (Mac, Windows) o host não alcança endereços de contêiner, e o avatar não abre no navegador. Outra máquina da rede não alcança o endereço: o Docker Engine 28 ou mais novo descarta, por padrão, acesso direto a contêiner vindo de fora do host.

A rede `login-simulator` tem sub-rede fixa (`172.31.250.0/24`). Se já existir uma rede com esse nome e outra sub-rede, recrie-a. Os contêineres de outras stacks ligados a ela saem antes e voltam depois:

```bash
docker network inspect login-simulator --format '{{range .Containers}}{{.Name}} {{end}}'   # quem está na rede
docker network disconnect login-simulator <container>                                      # cada um, menos o simulador
docker compose --env-file custom/env/login-simulator.env -f tools/login-simulator/compose.yaml down
docker compose --env-file custom/env/login-simulator.env -f tools/login-simulator/compose.yaml up -d --build
docker network connect login-simulator <container>                                         # cada um de volta
```

## Teste automatizado com instância própria

O teste e2e de um projeto sobe a imagem `login-simulator:0.1.0` (gerada pelo `up --build` acima) na rede interna dele, com o próprio arquivo de usuários. Nada sai da máquina e nada é compartilhado com a instância sempre ativa:

```yaml
services:
  login:
    image: login-simulator:0.1.0
    read_only: true
    volumes:
      - ./e2e/login-simulator.json:/config/config.json:ro
networks:
  default:
    internal: true
```

O teste faz o papel do navegador: `GET /authorize?...` devolve a página com `<input name="request" value="...">`; `POST /login` com `request` e `user` (o id do usuário) devolve o `302` para o endereço de retorno com `code` e `state`.

## Endpoints

| Endpoint | O que faz |
| --- | --- |
| `GET /authorize` | `response_type=code`, `client_id`, `redirect_uri`, `scope`, `state`, `nonce`, `audience`, `code_challenge` (`S256` ou `plain`), `prompt` (`none` usa a sessão; qualquer outro mostra a lista), `response_mode` (`query`, `form_post`, `web_message`). Aplicação não registrada ou endereço de retorno fora da lista: página de erro com o motivo, sem redirecionar |
| `POST /login` | clique num usuário: abre a sessão (cookie) e devolve o código à aplicação |
| `POST /oauth/token` | `grant_type=authorization_code`, formulário ou JSON; segredo por `client_secret_post` ou `client_secret_basic`. Código de uso único, válido por 5 minutos |
| `GET` ou `POST /userinfo` | claims do usuário do access token |
| `GET /.well-known/openid-configuration`, `/.well-known/jwks.json` | discovery e chave pública RS256 |
| `GET /v2/logout` | `client_id`, `returnTo` (logout do Auth0): encerra a sessão e volta ao endereço de retorno registrado; sem `returnTo`, ao primeiro da aplicação |
| `GET /oidc/logout` | `post_logout_redirect_uri`, `client_id` ou `id_token_hint`, `state` (logout do OpenID) |

Tokens: ID token por 10 horas e access token JWT por 24 horas, os padrões do Auth0. Com `audience`, o access token tem `aud` `[audience, <issuer>userinfo]`. O ID token traz `sub`, `name`, `given_name`, `family_name`, `nickname`, `picture` e `updated_at` (escopo `profile`), `email` e `email_verified` (escopo `email`), `nonce`, `sid`, o claim de papéis, `permissions` e, quando o usuário tem, `amr`. O access token traz o claim de papéis, `permissions` e `amr`; o `/userinfo` não traz `amr`. O CORS libera as origens dos endereços de retorno registrados.

## Como testar

```bash
docker run --rm --network none -v "$PWD/tools/login-simulator":/app:ro -w /app \
  node:24-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 node --test
```

Os testes sobem o servidor numa porta livre de `127.0.0.1` e cobrem login, tokens, recusas, logout, modos de resposta e o arquivo de configuração.

## Dados pessoais e limites

- Só usuários fictícios no arquivo: ele é versionado. Nunca dados de pessoas reais.
- Nada vai para disco: sessões, códigos e a chave de assinatura ficam em memória. Reiniciar troca a chave, e os tokens anteriores deixam de valer, como numa rotação de chave do Auth0.
- O log traz só eventos e contagens, sem dado de usuário.
- Só HTTP, em `127.0.0.1` e no endereço do contêiner, que só o host alcança; nunca vai para produção.
- Fora do escopo: senha, provedores sociais, cadastro, refresh token e Management API.
