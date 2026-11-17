<!-- source: workspace/tools/login-simulator/README.md sha256:bd07d92c8d77fa70665a1c6033b909ebe6d431c0a8001deadd61079979f4fcec -->

# login-simulator

- [Qué es](#qué-es)
- [Cómo ejecutarlo](#cómo-ejecutarlo)
- [Archivo de configuración](#archivo-de-configuración)
- [Cómo lo usa una aplicación](#cómo-lo-usa-una-aplicación)
- [Avatar generado](#avatar-generado)
- [Prueba automatizada con instancia propia](#prueba-automatizada-con-instancia-propia)
- [Endpoints](#endpoints)
- [Cómo probarlo](#cómo-probarlo)
- [Datos personales y límites](#datos-personales-y-límites)

## Qué es

Un sustituto local de Auth0 para cualquier aplicación del workspace que necesite login. La página de login lista usuarios ficticios fijos; un clic inicia sesión, sin contraseña y sin internet. Habla el OpenID Connect de Auth0 (login con PKCE, intercambio del código por tokens, claves de firma, datos del usuario y logout): una aplicación hecha para Auth0 empieza a usarlo cambiando solo la dirección y el client id. Solo Node y su biblioteca estándar, sin dependencias.

| Puerto | Uso |
| --- | --- |
| `28080` | navegador: <http://localhost:28080> |
| `login-simulator:8080` | contenedores de otros stacks, a través de la red Docker `login-simulator` |
| `172.31.250.10:8080` | avatares generados: la misma dirección en el navegador y en los contenedores de la red ([Avatar generado](#avatar-generado)) |

## Cómo ejecutarlo

Una vez, desde la raíz del workspace; después Docker inicia la herramienta junto consigo (`restart: unless-stopped`):

```bash
bash scripts/sync-env.sh --path tools/login-simulator   # once: custom/env/login-simulator.env from .env.example (or /local-env tools/login-simulator)
docker compose --env-file custom/env/login-simulator.env -f tools/login-simulator/compose.yaml up -d --build
```

Los ajustes viven en la capa custom, `custom/env/login-simulator.env`, nunca en esta carpeta; son opcionales, así que sin ese archivo `--env-file tools/login-simulator/.env.example` se ejecuta con los valores por defecto. Un cambio en `config/config.json` surte efecto al reiniciar:

```bash
docker compose --env-file custom/env/login-simulator.env -f tools/login-simulator/compose.yaml restart
```

Un archivo inválido o un `AVATAR_ORIGIN` inválido: el contenedor no arranca y el log (`docker logs login-simulator-login-simulator-1`) indica el campo y el problema. Un cambio de código: `up -d --build` de nuevo.

## Archivo de configuración

El archivo de configuración registra las aplicaciones y los usuarios. Un campo desconocido, una URL inválida, un tipo incorrecto o un id repetido hacen que se rechace el archivo.

- `config/config.json` es un ejemplo: dos aplicaciones ficticias y los usuarios de cada una, que cubren roles, permisos, MFA, login social y un email no verificado.
- El archivo real, con las aplicaciones de los proyectos, vive fuera de la herramienta. El archivo compose monta la ruta de `LOGIN_SIMULATOR_CONFIG`, relativa a esta carpeta, y usa el ejemplo cuando la variable no está definida. Para usar el de la capa custom, define `LOGIN_SIMULATOR_CONFIG=../../custom/config/login-simulator/config.json` en `custom/env/login-simulator.env` y ejecuta `up -d` de nuevo. `custom/config/<tool>/` guarda la configuración de las herramientas del propio workspace; `custom/tools/` es para herramientas tuyas.

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

| Campo | Obligatorio | Qué es |
| --- | --- | --- |
| `issuer` | sí | `iss` de los tokens, fijo. Usa la dirección que ve el navegador, con `/` final, como en Auth0 |
| `applications[].name` | sí | nombre que se muestra en la página de login |
| `applications[].clientId` | sí | client id de la aplicación |
| `applications[].callbackUrls` | sí | retornos de login permitidos (Allowed Callback URLs) |
| `applications[].logoutUrls` | no | retornos de logout permitidos (Allowed Logout URLs) |
| `applications[].clientSecret` | no | solo para una aplicación confidencial (backend); sin él, PKCE es obligatorio. Un valor ficticio: el archivo está versionado |
| `applications[].rolesClaim` | no | nombre del claim de roles, el mismo de la Action de Auth0 de la aplicación (p. ej. `https://app/roles`); predeterminado `roles` |
| `users[].id` | sí | `sub` de los tokens, en el formato de Auth0 (`<provider>\|<id>`, p. ej. `google-oauth2\|...` para login social) |
| `users[].givenName`, `familyName`, `email` | sí | nombre, apellido y email. Dos ids pueden tener el mismo email: la misma persona a través de dos proveedores |
| `users[].emailVerified` | no | `true` o `false`, va en `email_verified` del ID token y de `/userinfo`; predeterminado `true` |
| `users[].picture` | no | una URL `http(s)` o `data:image/...`, devuelta tal cual; sin ella, la herramienta genera una mascota SVG, siempre la misma para el mismo id ([Avatar generado](#avatar-generado)). El avatar generado de cualquier usuario sirve como imagen fija (p. ej. `http://172.31.250.10:8080/avatars/<id in base64url>.svg`), que se abre sin internet |
| `users[].roles`, `permissions` | no | tipos de acceso; van en el claim de roles y en `permissions` |
| `users[].amr` | no | una lista de textos (p. ej. `["mfa"]`), va en el claim `amr` del ID token y del access token, como la Action de MFA de Auth0. Sin él, ningún token lleva `amr`. El MFA no se pide en pantalla: viene del archivo |

Los usuarios valen para todas las aplicaciones, como los de un tenant de Auth0. La página de login muestra el `amr` y marca un email no verificado.

## Cómo lo usa una aplicación

1. Registra la aplicación en `config/config.json` y reinicia.
2. En su configuración, reemplaza el dominio de Auth0 por `http://localhost:28080` y el client id por el registrado. SDK de Auth0 en el navegador (`auth0-spa-js`, `auth0-angular`, `auth0-react`): `domain: "http://localhost:28080"`.
3. Backend en un contenedor: conecta el servicio a la red externa y llama a la herramienta en `http://login-simulator:8080`:

   ```yaml
   services:
     api:
       networks: [default, login-simulator]
   networks:
     login-simulator:
       external: true
   ```

El `iss` es siempre el `issuer` del archivo; las direcciones de discovery (`/.well-known/openid-configuration`) siguen el host por el que llegó la solicitud. Así, el navegador recibe `localhost:28080` y el backend recibe `login-simulator:8080`, y ambos validan el mismo `iss`. El avatar generado tiene una única dirección, que ambos abren: consulta la sección siguiente.

## Avatar generado

El avatar generado de un usuario sin `picture` está en `<AVATAR_ORIGIN>/avatars/<id in base64url>.svg`, la misma URL en el ID token, en `/userinfo` y en la página de login, venga la solicitud del navegador o de la red Docker. En la instancia siempre activa, `AVATAR_ORIGIN` es `http://172.31.250.10:8080` (`compose.yaml`): el simulador tiene esta dirección fija en la red `login-simulator`, y Docker Engine en Linux permite que el propio host abra direcciones de contenedores. Así:

- el navegador abre el avatar, sin configuración;
- un backend en un contenedor de la red `login-simulator` descarga la misma URL, sin otra configuración que estar en la red (paso 3 de arriba). Un contenedor fuera de la red no puede alcanzarla.

Sin `AVATAR_ORIGIN` (la instancia propia de una prueba e2e), el avatar generado usa el origen del `issuer`. Una `picture` del archivo nunca se reescribe.

Por qué no `localhost:28080` ni un nombre `*.localhost`: dentro de un contenedor, `localhost` es el propio contenedor, y curl (y otros clientes HTTP) resuelve cualquier `*.localhost` a loopback sin consultar al DNS de Docker. Solo la dirección del contenedor funciona para ambos lados.

Límites: en Docker Desktop (Mac, Windows) el host no alcanza las direcciones de los contenedores, y el avatar no se abre en el navegador. Otra máquina de la red no alcanza la dirección: Docker Engine 28 o posterior descarta, por defecto, el acceso directo a un contenedor que viene de fuera del host.

La red `login-simulator` tiene una subred fija (`172.31.250.0/24`). Si ya existe una red con ese nombre y otra subred, recréala. Los contenedores de otros stacks conectados a ella salen primero y vuelven después:

```bash
docker network inspect login-simulator --format '{{range .Containers}}{{.Name}} {{end}}'   # quién está en la red
docker network disconnect login-simulator <container>                                      # cada uno, salvo el simulador
docker compose --env-file custom/env/login-simulator.env -f tools/login-simulator/compose.yaml down
docker compose --env-file custom/env/login-simulator.env -f tools/login-simulator/compose.yaml up -d --build
docker network connect login-simulator <container>                                         # cada uno de vuelta
```

## Prueba automatizada con instancia propia

La prueba e2e de un proyecto inicia la imagen `login-simulator:0.1.0` (construida por el `up --build` de arriba) en su red interna, con su propio archivo de usuarios. Nada sale de la máquina y nada se comparte con la instancia siempre activa:

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

La prueba hace el papel del navegador: `GET /authorize?...` devuelve la página con `<input name="request" value="...">`; `POST /login` con `request` y `user` (el id del usuario) devuelve el `302` a la dirección de retorno con `code` y `state`.

## Endpoints

| Endpoint | Qué hace |
| --- | --- |
| `GET /authorize` | `response_type=code`, `client_id`, `redirect_uri`, `scope`, `state`, `nonce`, `audience`, `code_challenge` (`S256` o `plain`), `prompt` (`none` usa la sesión; cualquier otro muestra la lista), `response_mode` (`query`, `form_post`, `web_message`). Una aplicación no registrada o una dirección de retorno fuera de la lista: una página de error con el motivo, sin redirigir |
| `POST /login` | un clic en un usuario: abre la sesión (cookie) y devuelve el código a la aplicación |
| `POST /oauth/token` | `grant_type=authorization_code`, formulario o JSON; secreto por `client_secret_post` o `client_secret_basic`. Un código de un solo uso, válido por 5 minutos |
| `GET` o `POST /userinfo` | claims del usuario del access token |
| `GET /.well-known/openid-configuration`, `/.well-known/jwks.json` | discovery y la clave pública RS256 |
| `GET /v2/logout` | `client_id`, `returnTo` (logout de Auth0): termina la sesión y vuelve a la dirección de retorno registrada; sin `returnTo`, a la primera de la aplicación |
| `GET /oidc/logout` | `post_logout_redirect_uri`, `client_id` o `id_token_hint`, `state` (logout de OpenID) |

Tokens: ID token por 10 horas y access token JWT por 24 horas, los valores predeterminados de Auth0. Con `audience`, el access token tiene `aud` `[audience, <issuer>userinfo]`. El ID token lleva `sub`, `name`, `given_name`, `family_name`, `nickname`, `picture` y `updated_at` (scope `profile`), `email` y `email_verified` (scope `email`), `nonce`, `sid`, el claim de roles, `permissions` y, cuando el usuario lo tiene, `amr`. El access token lleva el claim de roles, `permissions` y `amr`; `/userinfo` no lleva `amr`. CORS permite los orígenes de las direcciones de retorno registradas.

## Cómo probarlo

```bash
docker run --rm --network none -v "$PWD/tools/login-simulator":/app:ro -w /app \
  node:24-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 node --test
```

Las pruebas inician el servidor en un puerto libre de `127.0.0.1` y cubren login, tokens, rechazos, logout, modos de respuesta y el archivo de configuración.

## Datos personales y límites

- Solo usuarios ficticios en el archivo: está versionado. Nunca datos de personas reales.
- Nada va a disco: sesiones, códigos y la clave de firma quedan en memoria. Un reinicio cambia la clave, y los tokens anteriores dejan de ser válidos, como en una rotación de claves de Auth0.
- El log contiene solo eventos y conteos, sin datos de usuarios.
- Solo HTTP, en `127.0.0.1` y en la dirección del contenedor, que solo alcanza el host; nunca va a producción.
- Fuera de alcance: contraseña, proveedores sociales, registro, refresh token y la Management API.
