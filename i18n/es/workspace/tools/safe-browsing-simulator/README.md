<!-- source: workspace/tools/safe-browsing-simulator/README.md sha256:088492a196bfff34760580ab80a9555249dc3c1ba04771f7f2e09d9d24c67432 -->

# safe-browsing-simulator

- [Qué es](#qué-es)
- [Cómo ejecutarlo](#cómo-ejecutarlo)
- [Cómo lo usa una aplicación](#cómo-lo-usa-una-aplicación)
- [Prueba automatizada con instancia propia](#prueba-automatizada-con-instancia-propia)
- [Archivo de amenazas](#archivo-de-amenazas)
- [Cómo se compara la URL](#cómo-se-compara-la-url)
- [Endpoint](#endpoint)
- [Cómo probarlo](#cómo-probarlo)
- [Datos y límites](#datos-y-límites)

## Qué es

Un sustituto local de Google Safe Browsing para cualquier aplicación del workspace que verifique si una URL es peligrosa. Responde en la ruta y en el formato de la Lookup API v4 (`POST /v4/threatMatches:find`): una aplicación empieza a usarlo cambiando solo la dirección base. La clave de API se acepta con cualquier valor, o sin valor, y nunca se verifica. Las URL peligrosas y los dominios que simulan el servicio caído vienen de un archivo. Nunca llama a Google ni a nada fuera de la máquina. Solo Node y su biblioteca estándar, sin dependencias; el mismo modelo que [`login-simulator`](../login-simulator/README.md).

| Dirección | Uso |
| --- | --- |
| `http://localhost:28090` | host: navegador, aplicación que se ejecuta fuera de Docker |
| `http://safe-browsing-simulator:8080` | contenedores de otros stacks, a través de la red Docker `safe-browsing-simulator` |

## Cómo ejecutarlo

Una vez, desde la raíz del workspace; después Docker inicia la herramienta junto consigo (`restart: unless-stopped`):

```bash
bash scripts/sync-env.sh --path tools/safe-browsing-simulator   # once: custom/env/safe-browsing-simulator.env from .env.example (or /local-env tools/safe-browsing-simulator)
docker compose --env-file custom/env/safe-browsing-simulator.env -f tools/safe-browsing-simulator/compose.yaml up -d --build
```

Los ajustes viven en la capa custom, `custom/env/safe-browsing-simulator.env`, nunca en esta carpeta; son opcionales, así que sin ese archivo `--env-file tools/safe-browsing-simulator/.env.example` se ejecuta con los valores por defecto. Un cambio en `config/threats.json` surte efecto al reiniciar:

```bash
docker compose --env-file custom/env/safe-browsing-simulator.env -f tools/safe-browsing-simulator/compose.yaml restart
```

Archivo inválido: el contenedor no arranca y el log (`docker logs safe-browsing-simulator-safe-browsing-simulator-1`) indica el campo y el problema. Un cambio de código: `up -d --build` de nuevo. Fuera de Docker, el servidor se ejecuta con `THREATS_PATH=config/threats.json PORT=28090 node src/main.js`.

## Cómo lo usa una aplicación

1. En su configuración, reemplaza la dirección base de la API (`https://safebrowsing.googleapis.com`) por la del simulador. Ruta, cuerpo y clave se mantienen; la clave puede tener cualquier valor.
2. Aplicación en el host: `http://localhost:28090/v4/threatMatches:find`.
3. Backend en un contenedor: conecta el servicio a la red externa y llama a `http://safe-browsing-simulator:8080/v4/threatMatches:find`:

   ```yaml
   services:
     api:
       networks: [default, safe-browsing-simulator]
   networks:
     safe-browsing-simulator:
       external: true
   ```

Ambos reciben la misma respuesta: la herramienta nunca devuelve direcciones propias.

## Prueba automatizada con instancia propia

La prueba de un proyecto inicia la imagen `safe-browsing-simulator:0.1.0` (construida por el `up --build` de arriba) en su red interna, con su propio archivo de amenazas. Nada sale de la máquina y nada se comparte con la instancia siempre activa:

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

La aplicación bajo prueba llama a `http://safe-browsing:8080/v4/threatMatches:find`.

## Archivo de amenazas

`config/threats.json`. Un campo desconocido, una URL inválida, un tipo de amenaza fuera de la lista o un elemento repetido hacen que se rechace el archivo.

```json
{
  "threats": [
    { "url": "http://malware.testing.google.test/testing/malware/", "threatType": "MALWARE" }
  ],
  "unavailableDomains": ["pending.example.test"]
}
```

| Campo | Obligatorio | Qué es |
| --- | --- | --- |
| `threats` | sí, puede estar vacío | URL peligrosas. Cualquier URL fuera de la lista es segura |
| `threats[].url` | sí | URL `http(s)` absoluta; se compara como en [Cómo se compara la URL](#cómo-se-compara-la-url) |
| `threats[].threatType` | sí | `MALWARE`, `SOCIAL_ENGINEERING`, `UNWANTED_SOFTWARE` o `POTENTIALLY_HARMFUL_APPLICATION`. La misma URL puede aparecer con más de un tipo |
| `unavailableDomains` | no | Dominios en minúsculas, sin esquema ni puerto. Una consulta con cualquier URL de uno de ellos, o de un subdominio, recibe un `503` para toda la solicitud |

El archivo de ejemplo, `config/threats.json`, contiene:

| URL | Tipo | Origen |
| --- | --- | --- |
| `http://malware.testing.google.test/testing/malware/` | `MALWARE` | URL de prueba de Google |
| `http://testsafebrowsing.appspot.com/s/malware.html` | `MALWARE` | Página de prueba de Google, <https://testsafebrowsing.appspot.com/> |
| `http://testsafebrowsing.appspot.com/s/phishing.html` | `SOCIAL_ENGINEERING` | ídem |
| `http://testsafebrowsing.appspot.com/s/unwanted.html` | `UNWANTED_SOFTWARE` | ídem |
| `http://pha.safe-browsing-simulator.test/app.apk` | `POTENTIALLY_HARMFUL_APPLICATION` | ficticia: Google no publica ninguna URL de prueba de este tipo |

Dominios caídos: `unavailable.safe-browsing-simulator.test` y `pending.example.test`.

El archivo predeterminado es un ejemplo. El real, con los dominios de los proyectos, vive fuera de la herramienta: el archivo compose monta la ruta de `SAFE_BROWSING_THREATS`, relativa a esta carpeta, y usa el ejemplo cuando la variable no está definida. Para usar el de la capa custom, define `SAFE_BROWSING_THREATS=../../custom/config/safe-browsing-simulator/threats.json` en `custom/env/safe-browsing-simulator.env` y ejecuta `up -d` de nuevo. `custom/config/<tool>/` guarda la configuración de las herramientas del propio workspace; `custom/tools/` es para herramientas tuyas.

## Cómo se compara la URL

Una versión simplificada de las expresiones de host y ruta de Safe Browsing:

- se ignoran el esquema, el puerto, el usuario, la contraseña y el fragmento; el host se pasa a minúsculas, sin el punto final. Una URL sin esquema (`site.test/x`) cuenta como `http`;
- el host consultado debe ser el host listado o un subdominio de él (`evil.test` cubre `a.evil.test`);
- una ruta listada que termina en `/` se cubre a sí misma y a todo lo que está debajo (`/testing/malware/` cubre `/testing/malware/x`); sin `/` final, solo la ruta exacta;
- una URL listada con query exige la misma query; sin query, cualquier query coincide.

## Endpoint

| Endpoint | Qué hace |
| --- | --- |
| `POST /v4/threatMatches:find` | Lookup v4. `key` en la query o `X-Goog-Api-Key`, nunca se verifica |
| `OPTIONS /v4/threatMatches:find` | Preflight de CORS (`Access-Control-Allow-Origin: *`) |
| `GET /healthz` | `{"status":"ok"}` |

Solicitud, igual que la de Google: `{"client": {...}, "threatInfo": {"threatTypes": [...], "platformTypes": [...], "threatEntryTypes": ["URL"], "threatEntries": [{"url": "..."}]}}`.

Respuesta:

- alguna URL peligrosa: `200` con `{"matches": [...]}`, un elemento por URL peligrosa, por tipo de amenaza pedido en `threatTypes` y por plataforma pedida en `platformTypes`: `threatType`, `platformType`, `threatEntryType: "URL"`, `threat: {"url": <the URL as sent>}` y `cacheDuration: "300s"`. Un tipo de amenaza listado pero no pedido no se devuelve, como en Google; sin `URL` en `threatEntryTypes`, no se devuelve nada;
- ninguna peligrosa: `200` con `{}`, como en Google;
- alguna URL de un dominio caído: `503`, para toda la solicitud;
- solicitud inválida (JSON inválido, campo desconocido, una lista de tipos vacía o con un valor fuera de la API, un `url` que no es texto, más de 500 entradas): `400`.

Los errores siguen el formato de la API de Google: `{"error": {"code": 503, "message": "...", "status": "UNAVAILABLE"}}`. Las entradas con `hash` o `digest` en lugar de `url` se aceptan y nunca coinciden.

## Cómo probarlo

```bash
docker run --rm --network none -v "$PWD/tools/safe-browsing-simulator":/app:ro -w /app \
  node:24-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 node --test
```

Las pruebas inician el servidor en un puerto libre de `127.0.0.1` y cubren de AC-1 a AC-3 (URL de prueba de malware, una consulta mixta y una totalmente segura, servicio caído), la comparación de URL, los rechazos de solicitud y de archivo y el log. AC-4 (la misma respuesta en el host y en un contenedor de la red) y AC-5 (instancia propia con otro archivo en una red interna) se verifican con los contenedores en ejecución.

## Datos y límites

- El archivo está versionado: solo URL de prueba públicas o ficticias (`.test`).
- El log contiene solo eventos y conteos: nunca una URL consultada ni la clave.
- Nada va a disco; nada sale de la máquina. El puerto escucha solo en `127.0.0.1`; nunca va a producción.
- Fuera de alcance: la API v5, la Update API (listas locales por prefijo de hash) y la comparación por hash.
