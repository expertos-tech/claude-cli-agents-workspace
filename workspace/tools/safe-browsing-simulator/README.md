# safe-browsing-simulator

- [What it is](#what-it-is)
- [How to run](#how-to-run)
- [How an application uses it](#how-an-application-uses-it)
- [Automated test with its own instance](#automated-test-with-its-own-instance)
- [Threats file](#threats-file)
- [How the URL is matched](#how-the-url-is-matched)
- [Endpoint](#endpoint)
- [How to test](#how-to-test)
- [Data and limits](#data-and-limits)

## What it is

A local stand-in for Google Safe Browsing for any workspace application that checks whether a URL is dangerous. It answers on the path and in the format of the Lookup API v4 (`POST /v4/threatMatches:find`): an application starts using it by changing only the base address. The API key is accepted with any value, or with no value, and is never checked. The dangerous URLs and the domains that simulate the service being down come from a file. It never calls Google or anything outside the machine. Node and its standard library only, no dependencies; same model as [`login-simulator`](../login-simulator/README.md).

| Address | Use |
| --- | --- |
| `http://localhost:28090` | host: browser, application running outside Docker |
| `http://safe-browsing-simulator:8080` | containers of other stacks, through the Docker network `safe-browsing-simulator` |

## How to run

Once, from the workspace root; after that Docker starts the tool along with itself (`restart: unless-stopped`):

```bash
bash scripts/sync-env.sh --path tools/safe-browsing-simulator   # once: custom/env/safe-browsing-simulator.env from .env.example (or /local-env tools/safe-browsing-simulator)
docker compose --env-file custom/env/safe-browsing-simulator.env -f tools/safe-browsing-simulator/compose.yaml up -d --build
```

The settings live in the custom layer, `custom/env/safe-browsing-simulator.env`, never in this folder; they are optional, so without that file `--env-file tools/safe-browsing-simulator/.env.example` runs with the defaults. A change to `config/threats.json` takes effect on restart:

```bash
docker compose --env-file custom/env/safe-browsing-simulator.env -f tools/safe-browsing-simulator/compose.yaml restart
```

Invalid file: the container does not start and the log (`docker logs safe-browsing-simulator-safe-browsing-simulator-1`) names the field and the problem. A code change: `up -d --build` again. Outside Docker, the server runs with `THREATS_PATH=config/threats.json PORT=28090 node src/main.js`.

## How an application uses it

1. In its configuration, replace the API base address (`https://safebrowsing.googleapis.com`) with the simulator's. Path, body and key stay as they are; the key can be any value.
2. Application on the host: `http://localhost:28090/v4/threatMatches:find`.
3. Backend in a container: put the service on the external network and call `http://safe-browsing-simulator:8080/v4/threatMatches:find`:

   ```yaml
   services:
     api:
       networks: [default, safe-browsing-simulator]
   networks:
     safe-browsing-simulator:
       external: true
   ```

Both get the same response: the tool never returns addresses of its own.

## Automated test with its own instance

A project's test starts the image `safe-browsing-simulator:0.1.0` (built by the `up --build` above) on its internal network, with its own threats file. Nothing leaves the machine and nothing is shared with the always-on instance:

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

The application under test calls `http://safe-browsing:8080/v4/threatMatches:find`.

## Threats file

`config/threats.json`. An unknown field, an invalid URL, a threat type outside the list or a repeated item rejects the file.

```json
{
  "threats": [
    { "url": "http://malware.testing.google.test/testing/malware/", "threatType": "MALWARE" }
  ],
  "unavailableDomains": ["pending.example.test"]
}
```

| Field | Required | What it is |
| --- | --- | --- |
| `threats` | yes, may be empty | Dangerous URLs. Any URL outside the list is safe |
| `threats[].url` | yes | Absolute `http(s)` URL; matched as in [How the URL is matched](#how-the-url-is-matched) |
| `threats[].threatType` | yes | `MALWARE`, `SOCIAL_ENGINEERING`, `UNWANTED_SOFTWARE` or `POTENTIALLY_HARMFUL_APPLICATION`. The same URL may appear with more than one type |
| `unavailableDomains` | no | Lowercase domains, with no scheme or port. A lookup with any URL of one of them, or of a subdomain, gets a `503` for the whole request |

The example file, `config/threats.json`, holds:

| URL | Type | Origin |
| --- | --- | --- |
| `http://malware.testing.google.test/testing/malware/` | `MALWARE` | Google test URL |
| `http://testsafebrowsing.appspot.com/s/malware.html` | `MALWARE` | Google test page, <https://testsafebrowsing.appspot.com/> |
| `http://testsafebrowsing.appspot.com/s/phishing.html` | `SOCIAL_ENGINEERING` | same |
| `http://testsafebrowsing.appspot.com/s/unwanted.html` | `UNWANTED_SOFTWARE` | same |
| `http://pha.safe-browsing-simulator.test/app.apk` | `POTENTIALLY_HARMFUL_APPLICATION` | fictitious: Google publishes no test URL of this type |

Domains that are down: `unavailable.safe-browsing-simulator.test` and `pending.example.test`.

The default file is an example. The real one, with the projects' domains, lives outside the tool: the compose file mounts the path in `SAFE_BROWSING_THREATS`, relative to this folder, and uses the example when the variable is not set. To use the one of the custom layer, set `SAFE_BROWSING_THREATS=../../custom/config/safe-browsing-simulator/threats.json` in `custom/env/safe-browsing-simulator.env` and run `up -d` again. `custom/config/<tool>/` holds the configuration of the workspace's own tools; `custom/tools/` is for tools of yours.

## How the URL is matched

A simplified version of the Safe Browsing host and path expressions:

- scheme, port, user, password and fragment are ignored; the host is lowercased, without the trailing dot. A URL without a scheme (`site.test/x`) counts as `http`;
- the host looked up must be the listed host or a subdomain of it (`evil.test` covers `a.evil.test`);
- a listed path ending in `/` covers itself and everything below it (`/testing/malware/` covers `/testing/malware/x`); without a trailing `/`, only the exact path;
- a listed URL with a query requires the same query; without a query, any query matches.

## Endpoint

| Endpoint | What it does |
| --- | --- |
| `POST /v4/threatMatches:find` | Lookup v4. `key` in the query or `X-Goog-Api-Key`, never checked |
| `OPTIONS /v4/threatMatches:find` | CORS preflight (`Access-Control-Allow-Origin: *`) |
| `GET /healthz` | `{"status":"ok"}` |

Request, like Google's: `{"client": {...}, "threatInfo": {"threatTypes": [...], "platformTypes": [...], "threatEntryTypes": ["URL"], "threatEntries": [{"url": "..."}]}}`.

Response:

- some dangerous URL: `200` with `{"matches": [...]}`, one item per dangerous URL, per threat type asked in `threatTypes` and per platform asked in `platformTypes`: `threatType`, `platformType`, `threatEntryType: "URL"`, `threat: {"url": <the URL as sent>}` and `cacheDuration: "300s"`. A threat type that is listed but not asked for is not returned, as with Google; without `URL` in `threatEntryTypes`, nothing is returned;
- none dangerous: `200` with `{}`, as with Google;
- some URL of a domain that is down: `503`, for the whole request;
- invalid request (invalid JSON, unknown field, an empty type list or one with a value outside the API, a `url` that is not text, more than 500 entries): `400`.

Errors follow the Google API format: `{"error": {"code": 503, "message": "...", "status": "UNAVAILABLE"}}`. Entries with `hash` or `digest` instead of `url` are accepted and never match.

## How to test

```bash
docker run --rm --network none -v "$PWD/tools/safe-browsing-simulator":/app:ro -w /app \
  node:24-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 node --test
```

The tests start the server on a free port of `127.0.0.1` and cover AC-1 to AC-3 (malware test URL, a mixed lookup and an all-safe one, service down), the URL matching, the request and file rejections and the log. AC-4 (same response on the host and in a container of the network) and AC-5 (own instance with another file on an internal network) are checked with the containers running.

## Data and limits

- The file is versioned: only public test URLs or fictitious ones (`.test`).
- The log holds only events and counts: never a URL looked up nor the key.
- Nothing goes to disk; nothing leaves the machine. The port listens only on `127.0.0.1`; it never goes to production.
- Out of scope: API v5, the Update API (local lists by hash prefix) and hash matching.
