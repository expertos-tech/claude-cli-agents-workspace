# login-simulator

- [What it is](#what-it-is)
- [How to run](#how-to-run)
- [Configuration file](#configuration-file)
- [How an application uses it](#how-an-application-uses-it)
- [Generated avatar](#generated-avatar)
- [Automated test with its own instance](#automated-test-with-its-own-instance)
- [Endpoints](#endpoints)
- [How to test](#how-to-test)
- [Personal data and limits](#personal-data-and-limits)

## What it is

A local stand-in for Auth0 for any workspace application that needs a login. The login page lists fixed fictitious users; one click signs in, with no password and no internet. It speaks Auth0's OpenID Connect (login with PKCE, exchange of the code for tokens, signing keys, user data and logout): an application built for Auth0 starts using it by changing only the address and the client id. Node and its standard library only, no dependencies.

| Port | Use |
| --- | --- |
| `28080` | browser: <http://localhost:28080> |
| `login-simulator:8080` | containers of other stacks, through the Docker network `login-simulator` |
| `172.31.250.10:8080` | generated avatars: the same address in the browser and in the containers of the network ([Generated avatar](#generated-avatar)) |

## How to run

Put the configuration file in the custom layer, `custom/config/login-simulator/config.json` ([Configuration file](#configuration-file); start from `config/config.json`), then run `/run-tools` in a session and tick it, or, from the workspace root:

```bash
bash scripts/run-tools.sh up login-simulator
```

It runs in `claude-cli-agents-tools`, the compose project of every tool (`tools/compose.yaml`), and Docker starts it again along with itself (`restart: unless-stopped`). Without the configuration file it is listed as "configuration missing" and does not start. The settings are optional and live in `custom/env/login-simulator.env` (`/local-env tools/login-simulator`), never in this folder. A change to the configuration file takes effect on restart:

```bash
docker compose -f tools/compose.yaml restart login-simulator
```

The tool's own `compose.yaml` still starts it alone, for development: `LOGIN_SIMULATOR_CONFIG=./config/config.json docker compose -f tools/login-simulator/compose.yaml up -d --build` runs the example (project `login-simulator`, not the group; stop it before `/run-tools`).

An invalid file or an invalid `AVATAR_ORIGIN`: the container does not start and the log (`docker compose -f tools/compose.yaml logs login-simulator`) names the field and the problem. A code change: `bash scripts/run-tools.sh up login-simulator` again.

## Configuration file

The configuration file registers the applications and the users. An unknown field, an invalid URL, a wrong type or a repeated id rejects the file.

- `config/config.json` is an example: two fictitious applications and the users of each, covering roles, permissions, MFA, social login and an unverified email.
- The real file, with the projects' applications, lives outside the tool, in the custom layer: `custom/config/login-simulator/config.json`, the path the compose file mounts by default. `LOGIN_SIMULATOR_CONFIG` in `custom/env/login-simulator.env`, relative to this folder, points to another file. The compose file never creates a missing file: the container is not created and `/run-tools` says what is missing. `custom/config/<tool>/` holds the configuration of the workspace's own tools; `custom/tools/` is for tools of yours.

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

| Field | Required | What it is |
| --- | --- | --- |
| `issuer` | yes | `iss` of the tokens, fixed. Use the address the browser sees, with a trailing `/`, as in Auth0 |
| `applications[].name` | yes | name shown on the login page |
| `applications[].clientId` | yes | client id of the application |
| `applications[].callbackUrls` | yes | allowed login returns (Allowed Callback URLs) |
| `applications[].logoutUrls` | no | allowed logout returns (Allowed Logout URLs) |
| `applications[].clientSecret` | no | only for a confidential application (backend); without it, PKCE is mandatory. A fictitious value: the file is versioned |
| `applications[].rolesClaim` | no | name of the roles claim, the same as the application's Auth0 Action (e.g. `https://app/roles`); default `roles` |
| `users[].id` | yes | `sub` of the tokens, in the Auth0 format (`<provider>\|<id>`, e.g. `google-oauth2\|...` for social login) |
| `users[].givenName`, `familyName`, `email` | yes | first name, last name and email. Two ids may have the same email: the same person through two providers |
| `users[].emailVerified` | no | `true` or `false`, goes in `email_verified` in the ID token and in `/userinfo`; default `true` |
| `users[].picture` | no | an `http(s)` or `data:image/...` URL, returned as it is; without it, the tool generates an SVG mascot, always the same for the same id ([Generated avatar](#generated-avatar)). The generated avatar of any user works as a fixed picture (e.g. `http://172.31.250.10:8080/avatars/<id in base64url>.svg`), which opens with no internet |
| `users[].roles`, `permissions` | no | access types; they go in the roles claim and in `permissions` |
| `users[].amr` | no | a list of texts (e.g. `["mfa"]`), goes in the `amr` claim of the ID token and of the access token, like Auth0's MFA Action. Without it, no token carries `amr`. MFA is not asked on screen: it comes from the file |

The users are valid for every application, like the ones of an Auth0 tenant. The login page shows the `amr` and marks an unverified email.

## How an application uses it

1. Register the application in the configuration file (`custom/config/login-simulator/config.json`) and restart.
2. In its configuration, replace the Auth0 domain with `http://localhost:28080` and the client id with the registered one. Auth0 SDK in the browser (`auth0-spa-js`, `auth0-angular`, `auth0-react`): `domain: "http://localhost:28080"`.
3. Backend in a container: put the service on the external network and call the tool at `http://login-simulator:8080`:

   ```yaml
   services:
     api:
       networks: [default, login-simulator]
   networks:
     login-simulator:
       external: true
   ```

The `iss` is always the `issuer` of the file; the discovery addresses (`/.well-known/openid-configuration`) follow the host the request came through. So the browser gets `localhost:28080` and the backend gets `login-simulator:8080`, and both validate the same `iss`. The generated avatar has a single address, which both open: see below.

## Generated avatar

The generated avatar of a user without `picture` is at `<AVATAR_ORIGIN>/avatars/<id in base64url>.svg`, the same URL in the ID token, in `/userinfo` and on the login page, whether the request comes from the browser or from the Docker network. On the always-on instance, `AVATAR_ORIGIN` is `http://172.31.250.10:8080` (`compose.yaml`): the simulator has this fixed address on the `login-simulator` network, and Docker Engine on Linux lets the host itself open container addresses. So:

- the browser opens the avatar, with no configuration;
- a backend in a container on the `login-simulator` network downloads the same URL, with no configuration besides being on the network (step 3 above). A container outside the network cannot reach it.

Without `AVATAR_ORIGIN` (the own instance of an e2e test), the generated avatar uses the origin of the `issuer`. A `picture` from the file is never rewritten.

Why not `localhost:28080` or a `*.localhost` name: inside a container, `localhost` is the container itself, and curl (and other HTTP clients) resolves any `*.localhost` to loopback without asking Docker's DNS. Only the container's address works for both sides.

Limits: on Docker Desktop (Mac, Windows) the host does not reach container addresses, and the avatar does not open in the browser. Another machine on the network does not reach the address: Docker Engine 28 or newer drops, by default, direct access to a container coming from outside the host.

The `login-simulator` network has a fixed subnet (`172.31.250.0/24`). If a network with that name already exists with another subnet, recreate it. Containers of other stacks attached to it leave first and come back afterwards:

```bash
docker network inspect login-simulator --format '{{range .Containers}}{{.Name}} {{end}}'   # who is on the network
docker network disconnect login-simulator <container>                                      # each one, except the simulator
docker compose -f tools/compose.yaml rm --stop --force login-simulator && docker network rm login-simulator
bash scripts/run-tools.sh up login-simulator
docker network connect login-simulator <container>                                         # each one back
```

## Automated test with its own instance

A project's e2e test starts the image `login-simulator:0.1.0` (built by the `up --build` above) on its internal network, with its own users file. Nothing leaves the machine and nothing is shared with the always-on instance:

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

The test plays the browser's part: `GET /authorize?...` returns the page with `<input name="request" value="...">`; `POST /login` with `request` and `user` (the user id) returns the `302` to the return address with `code` and `state`.

## Endpoints

| Endpoint | What it does |
| --- | --- |
| `GET /authorize` | `response_type=code`, `client_id`, `redirect_uri`, `scope`, `state`, `nonce`, `audience`, `code_challenge` (`S256` or `plain`), `prompt` (`none` uses the session; any other shows the list), `response_mode` (`query`, `form_post`, `web_message`). An unregistered application or a return address off the list: an error page with the reason, without redirecting |
| `POST /login` | a click on a user: opens the session (cookie) and returns the code to the application |
| `POST /oauth/token` | `grant_type=authorization_code`, form or JSON; secret by `client_secret_post` or `client_secret_basic`. A single-use code, valid for 5 minutes |
| `GET` or `POST /userinfo` | claims of the access token's user |
| `GET /.well-known/openid-configuration`, `/.well-known/jwks.json` | discovery and the RS256 public key |
| `GET /v2/logout` | `client_id`, `returnTo` (Auth0 logout): ends the session and goes back to the registered return address; without `returnTo`, to the application's first one |
| `GET /oidc/logout` | `post_logout_redirect_uri`, `client_id` or `id_token_hint`, `state` (OpenID logout) |

Tokens: ID token for 10 hours and JWT access token for 24 hours, the Auth0 defaults. With `audience`, the access token has `aud` `[audience, <issuer>userinfo]`. The ID token carries `sub`, `name`, `given_name`, `family_name`, `nickname`, `picture` and `updated_at` (scope `profile`), `email` and `email_verified` (scope `email`), `nonce`, `sid`, the roles claim, `permissions` and, when the user has it, `amr`. The access token carries the roles claim, `permissions` and `amr`; `/userinfo` does not carry `amr`. CORS allows the origins of the registered return addresses.

## How to test

```bash
docker run --rm --network none -v "$PWD/tools/login-simulator":/app:ro -w /app \
  node:24-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 node --test
```

The tests start the server on a free port of `127.0.0.1` and cover login, tokens, refusals, logout, response modes and the configuration file.

## Personal data and limits

- Only fictitious users in the file: it is versioned. Never data of real people.
- Nothing goes to disk: sessions, codes and the signing key stay in memory. A restart changes the key, and the earlier tokens stop being valid, as in an Auth0 key rotation.
- The log holds only events and counts, no user data.
- HTTP only, on `127.0.0.1` and on the container's address, which only the host reaches; it never goes to production.
- Out of scope: password, social providers, sign-up, refresh token and the Management API.
