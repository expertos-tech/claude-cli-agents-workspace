import assert from "node:assert/strict";
import { createHash, createPublicKey, verify } from "node:crypto";
import { once } from "node:events";
import { createServer, get } from "node:http";
import { after, before, describe, test } from "node:test";
import { createApp } from "../src/app.js";
import { parseConfig } from "../src/config.js";
import { createSigner } from "../src/tokens.js";

const VERIFIER = "v".repeat(43) + "-verifier_ok";
const CHALLENGE = createHash("sha256").update(VERIFIER).digest("base64url");
const CALLBACK = "http://localhost:4200/auth";

const CONFIG = parseConfig({
  issuer: "http://localhost:28080/",
  applications: [
    { name: "Spa Test", clientId: "spa", callbackUrls: [CALLBACK], logoutUrls: ["http://localhost:4200/"],
      rolesClaim: "https://spa.test/roles" },
    { name: "Server Test", clientId: "server", clientSecret: "not-a-real-secret",
      callbackUrls: ["http://localhost:5000/callback"], logoutUrls: [] },
  ],
  users: [
    { id: "local|ana", givenName: "Ana", familyName: "Test", email: "ana@app.test", roles: ["admin"],
      permissions: ["links:read", "links:write"] },
    { id: "local|beto", givenName: "Beto", familyName: "Silva", email: "beto@app.test",
      picture: "https://pictures.test/beto.png" },
    { id: "local|dora", givenName: "Dora", familyName: "Admin", email: "dora@app.test", permissions: ["hub:admin"],
      amr: ["mfa"] },
    { id: "local|edu", givenName: "Edu", familyName: "Pending", email: "edu@app.test", emailVerified: false },
  ],
});

let server;
let origin;
let clock = Date.parse("2026-11-15T12:00:00Z");
const signer = createSigner();

before(async () => {
  server = createServer(createApp({ config: CONFIG, signer, now: () => clock }));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  origin = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

/** Request to the simulator with no automatic redirect. */
function call(path, options = {}) {
  return fetch(`${origin}${path}`, { redirect: "manual", ...options });
}

/** /authorize query of the SPA with PKCE S256. */
function authorizePath(overrides = {}) {
  const params = { client_id: "spa", redirect_uri: CALLBACK, response_type: "code", scope: "openid profile email",
    state: "state-123", nonce: "nonce-456", code_challenge: CHALLENGE, code_challenge_method: "S256", ...overrides };
  return `/authorize?${new URLSearchParams(Object.entries(params).filter(([, value]) => value !== null))}`;
}

/** Opens the login page and clicks `userId`; returns the redirect location and the session cookie. */
async function clickLogin(userId, overrides = {}) {
  const page = await (await call(authorizePath(overrides))).text();
  const requestId = page.match(/name="request" value="([^"]+)"/)[1];
  const response = await call("/login", { method: "POST", body: new URLSearchParams({ request: requestId, user: userId }) });
  return { response, cookie: response.headers.get("set-cookie")?.split(";")[0] };
}

/** Logs `userId` in and returns the code of the redirect. */
async function codeFor(userId, overrides = {}) {
  const { response } = await clickLogin(userId, overrides);
  return new URL(response.headers.get("location")).searchParams.get("code");
}

/** Exchanges a code at /oauth/token. */
function exchange(fields, headers = {}) {
  return call("/oauth/token", { method: "POST", headers,
    body: new URLSearchParams({ grant_type: "authorization_code", client_id: "spa", redirect_uri: CALLBACK,
      code_verifier: VERIFIER, ...fields }) });
}

/** Verifies a JWT against the published JWKS and returns its payload. */
async function verifiedPayload(token) {
  const { keys } = await (await call("/.well-known/jwks.json")).json();
  const [header, payload, signature] = token.split(".");
  const key = createPublicKey({ key: keys[0], format: "jwk" });
  assert.ok(verify("sha256", Buffer.from(`${header}.${payload}`), key, Buffer.from(signature, "base64url")));
  return JSON.parse(Buffer.from(payload, "base64url").toString());
}

describe("login (AC-1)", () => {
  test("AC-1: the login page lists every user with name, e-mail, picture and access types", async () => {
    const response = await call(authorizePath());
    const page = await response.text();
    assert.equal(response.status, 200);
    for (const text of ["Sign in to Spa Test", "Ana Test", "ana@app.test", "local|ana", "admin", "links:write",
      "Beto Silva", "https://pictures.test/beto.png", "/avatars/"]) {
      assert.ok(page.includes(text), `page without ${text}`);
    }
    assert.match(response.headers.get("content-security-policy"), /frame-ancestors 'none'/);
  });

  test("AC-1: a click returns a code and the tokens carry id, name, e-mail, picture and access types", async () => {
    const { response, cookie } = await clickLogin("local|ana");
    assert.equal(response.status, 302);
    const location = new URL(response.headers.get("location"));
    assert.equal(`${location.origin}${location.pathname}`, CALLBACK);
    assert.equal(location.searchParams.get("state"), "state-123");
    assert.match(cookie, /^login_simulator_session=/);

    const tokens = await exchange({ code: location.searchParams.get("code") });
    assert.equal(tokens.status, 200);
    const body = await tokens.json();
    assert.equal(body.token_type, "Bearer");
    const id = await verifiedPayload(body.id_token);
    assert.equal(id.iss, "http://localhost:28080/");
    assert.equal(id.aud, "spa");
    assert.equal(id.sub, "local|ana");
    assert.equal(id.nonce, "nonce-456");
    assert.equal(id.name, "Ana Test");
    assert.equal(id.given_name, "Ana");
    assert.equal(id.family_name, "Test");
    assert.equal(id.email, "ana@app.test");
    assert.equal(id.email_verified, true);
    assert.equal(id.picture, `http://localhost:28080/avatars/${Buffer.from("local|ana").toString("base64url")}.svg`);
    assert.deepEqual(id["https://spa.test/roles"], ["admin"]);
    assert.deepEqual(id.permissions, ["links:read", "links:write"]);
    assert.equal(id.exp - id.iat, 36000);

    const access = await verifiedPayload(body.access_token);
    assert.equal(access.aud, "http://localhost:28080/userinfo");
    assert.deepEqual(access.permissions, ["links:read", "links:write"]);

    const info = await call("/userinfo", { headers: { Authorization: `Bearer ${body.access_token}` } });
    assert.equal(info.status, 200);
    const claims = await info.json();
    assert.equal(claims.sub, "local|ana");
    assert.equal(claims.email, "ana@app.test");
    assert.deepEqual(claims["https://spa.test/roles"], ["admin"]);
  });

  test("AC-1: the generated avatar is served for any user of the file, and only for them", async () => {
    const response = await call(`/avatars/${Buffer.from("local|ana").toString("base64url")}.svg`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "image/svg+xml");
    const svg = await response.text();
    assert.match(svg, /^<svg [^>]*viewBox="0 0 96 96"/);
    assert.doesNotMatch(svg, /Ana|Test|<text/);
    assert.equal(svg, await (await call(`/avatars/${Buffer.from("local|ana").toString("base64url")}.svg`)).text());
    assert.equal((await call(`/avatars/${Buffer.from("local|beto").toString("base64url")}.svg`)).status, 200);
    assert.equal((await call(`/avatars/${Buffer.from("local|ghost").toString("base64url")}.svg`)).status, 404);
  });

  test("the generated picture is at the issuer's origin, not at the host the caller used", async () => {
    const body = await (await exchange({ code: await codeFor("local|ana") })).json();
    const info = await call("/userinfo", { headers: { Authorization: `Bearer ${body.access_token}` } });
    assert.equal((await info.json()).picture,
      `http://localhost:28080/avatars/${Buffer.from("local|ana").toString("base64url")}.svg`);
  });

  test("with an avatar origin, the generated picture is there in both tokens and /userinfo; a file picture is as is",
    async () => {
      const other = createServer(createApp({ config: CONFIG, signer, avatarOrigin: "http://172.31.250.10:8080" }));
      other.listen(0, "127.0.0.1");
      await once(other, "listening");
      const saved = origin;
      origin = `http://127.0.0.1:${other.address().port}`;
      try {
        const ana = await (await exchange({ code: await codeFor("local|ana") })).json();
        const avatar = `http://172.31.250.10:8080/avatars/${Buffer.from("local|ana").toString("base64url")}.svg`;
        assert.equal((await verifiedPayload(ana.id_token)).picture, avatar);
        const info = await call("/userinfo", { headers: { Authorization: `Bearer ${ana.access_token}` } });
        assert.equal((await info.json()).picture, avatar);
        const beto = await (await exchange({ code: await codeFor("local|beto") })).json();
        assert.equal((await verifiedPayload(beto.id_token)).picture, "https://pictures.test/beto.png");
        assert.match(await (await call(authorizePath())).text(), /http:\/\/172\.31\.250\.10:8080\/avatars\//);
      } finally {
        origin = saved;
        other.close();
      }
    });

  test("an audience adds itself to the access token, and the scope limits the claims", async () => {
    const code = await codeFor("local|beto", { audience: "https://api.test", scope: "openid" });
    const body = await (await exchange({ code })).json();
    const access = await verifiedPayload(body.access_token);
    assert.deepEqual(access.aud, ["https://api.test", "http://localhost:28080/userinfo"]);
    const id = await verifiedPayload(body.id_token);
    assert.equal(id.email, undefined);
    assert.equal(id.name, undefined);
    assert.deepEqual(id.permissions, []);
  });
});

describe("hub claims: e-mail verification and amr", () => {
  /** Logs `userId` in with the hub's audience and returns the verified ID token, access token and /userinfo. */
  async function hubLogin(userId) {
    const code = await codeFor(userId, { audience: "example-admin-api" });
    const body = await (await exchange({ code })).json();
    const info = await call("/userinfo", { headers: { Authorization: `Bearer ${body.access_token}` } });
    return { id: await verifiedPayload(body.id_token), access: await verifiedPayload(body.access_token),
      info: await info.json() };
  }

  test("hub AC-2: a user with emailVerified false gets email_verified false in the ID token and /userinfo", async () => {
    const { id, info } = await hubLogin("local|edu");
    assert.equal(id.email_verified, false);
    assert.equal(info.email_verified, false);
  });

  test("hub AC-3: the admin with MFA gets hub:admin and amr mfa in the access token of the hub API", async () => {
    const { id, access, info } = await hubLogin("local|dora");
    assert.ok(access.aud.includes("example-admin-api"));
    assert.deepEqual(access.permissions, ["hub:admin"]);
    assert.deepEqual(access.amr, ["mfa"]);
    assert.deepEqual(id.amr, ["mfa"]);
    assert.equal(info.amr, undefined);
    assert.equal(id.email_verified, true);
  });

  test("hub AC-4: a user with no amr in the file gets no amr claim in any token", async () => {
    const { id, access } = await hubLogin("local|ana");
    assert.equal("amr" in id, false);
    assert.equal("amr" in access, false);
  });

  test("the login page shows the amr and an unverified e-mail", async () => {
    const page = await (await call(authorizePath())).text();
    assert.match(page, /edu@app\.test \(email not verified\)/);
    assert.match(page, /amr: <span class="chip">mfa<\/span>/);
    assert.equal(page.match(/amr: /g).length, 1);
  });
});

describe("refused requests (AC-2)", () => {
  for (const [label, overrides, reason] of [
    ["unregistered client id", { client_id: "ghost" }, "client_id &#34;ghost&#34; is not registered"],
    ["missing client id", { client_id: null }, "has no client_id"],
    ["return address off the list", { redirect_uri: "http://evil.test/auth" }, "is not in the login return list"],
    ["missing return address", { redirect_uri: null }, "has no redirect_uri"],
  ]) {
    test(`AC-2: ${label} gets an error page with the reason and no redirect`, async () => {
      const response = await call(authorizePath(overrides));
      assert.equal(response.status, 400);
      assert.equal(response.headers.get("location"), null);
      assert.ok((await response.text()).includes(reason));
    });
  }

  test("a valid client with a bad response type is answered at its callback", async () => {
    const response = await call(authorizePath({ response_type: "token" }));
    const location = new URL(response.headers.get("location"));
    assert.equal(location.searchParams.get("error"), "unsupported_response_type");
    assert.equal(location.searchParams.get("state"), "state-123");
  });

  test("a public application must send a PKCE challenge", async () => {
    const response = await call(authorizePath({ code_challenge: null, code_challenge_method: null }));
    assert.equal(new URL(response.headers.get("location")).searchParams.get("error"), "invalid_request");
  });

  test("a stale login request or an unknown user is refused", async () => {
    const stale = await call("/login", { method: "POST", body: new URLSearchParams({ request: "x", user: "local|ana" }) });
    assert.equal(stale.status, 400);
    assert.ok((await stale.text()).includes("expired"));
    const page = await (await call(authorizePath())).text();
    const requestId = page.match(/name="request" value="([^"]+)"/)[1];
    const unknown = await call("/login", { method: "POST", body: new URLSearchParams({ request: requestId, user: "nobody" }) });
    assert.equal(unknown.status, 400);
  });
});

describe("code exchange", () => {
  test("a code works once", async () => {
    const code = await codeFor("local|ana");
    assert.equal((await exchange({ code })).status, 200);
    const again = await exchange({ code });
    assert.equal(again.status, 403);
    assert.equal((await again.json()).error, "invalid_grant");
  });

  test("a wrong verifier, another redirect or another client is refused", async () => {
    assert.equal((await exchange({ code: await codeFor("local|ana"), code_verifier: "w".repeat(43) })).status, 403);
    assert.equal((await exchange({ code: await codeFor("local|ana"), redirect_uri: "http://localhost:4200/other" })).status, 403);
    const otherClient = await exchange({ code: await codeFor("local|ana"), client_id: "server", client_secret: "not-a-real-secret" });
    assert.equal(otherClient.status, 403);
  });

  test("an expired code is refused", async () => {
    const code = await codeFor("local|ana");
    clock += 6 * 60 * 1000;
    try {
      assert.equal((await exchange({ code })).status, 403);
    } finally {
      clock -= 6 * 60 * 1000;
    }
  });

  test("a JSON body and a plain challenge work", async () => {
    const code = await codeFor("local|ana", { code_challenge: VERIFIER, code_challenge_method: "plain" });
    const response = await call("/oauth/token", { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ grant_type: "authorization_code", client_id: "spa", redirect_uri: CALLBACK,
        code_verifier: VERIFIER, code }) });
    assert.equal(response.status, 200);
  });

  test("a confidential application authenticates with its secret, in the body or by Basic", async () => {
    const serverPath = { client_id: "server", redirect_uri: "http://localhost:5000/callback", code_challenge: null,
      code_challenge_method: null };
    const fields = { client_id: "server", redirect_uri: "http://localhost:5000/callback", code_verifier: "" };
    const wrong = await exchange({ ...fields, code: await codeFor("local|ana", serverPath), client_secret: "wrong" });
    assert.equal(wrong.status, 401);
    const post = await exchange({ ...fields, code: await codeFor("local|ana", serverPath), client_secret: "not-a-real-secret" });
    assert.equal(post.status, 200);
    const basic = Buffer.from("server:not-a-real-secret").toString("base64");
    const viaBasic = await exchange({ ...fields, code: await codeFor("local|ana", serverPath) },
      { Authorization: `Basic ${basic}` });
    assert.equal(viaBasic.status, 200);
  });

  test("another grant type is refused", async () => {
    const response = await exchange({ grant_type: "refresh_token" });
    assert.equal((await response.json()).error, "unsupported_grant_type");
  });

  test("the browser of a registered origin may read the token answer", async () => {
    const preflight = await call("/oauth/token", { method: "OPTIONS", headers: { Origin: "http://localhost:4200" } });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get("access-control-allow-origin"), "http://localhost:4200");
    const stranger = await call("/oauth/token", { method: "OPTIONS", headers: { Origin: "http://evil.test" } });
    assert.equal(stranger.headers.get("access-control-allow-origin"), null);
  });

  test("an expired or foreign access token is refused at /userinfo", async () => {
    const body = await (await exchange({ code: await codeFor("local|ana") })).json();
    clock += 86_401_000;
    try {
      const expired = await call("/userinfo", { headers: { Authorization: `Bearer ${body.access_token}` } });
      assert.equal(expired.status, 401);
    } finally {
      clock -= 86_401_000;
    }
    const foreign = createSigner().sign({ iss: "http://localhost:28080/", sub: "local|ana", exp: 9e9, azp: "spa" });
    assert.equal((await call("/userinfo", { headers: { Authorization: `Bearer ${foreign}` } })).status, 401);
  });
});

describe("session and logout (AC-3)", () => {
  test("AC-3: logout returns to the registered address and the next login shows the list again", async () => {
    const { cookie } = await clickLogin("local|ana");
    const silent = await call(authorizePath({ prompt: "none" }), { headers: { Cookie: cookie } });
    assert.ok(new URL(silent.headers.get("location")).searchParams.has("code"), "prompt=none with a session gives a code");

    const out = await call("/v2/logout?client_id=spa&returnTo=http%3A%2F%2Flocalhost%3A4200", { headers: { Cookie: cookie } });
    assert.equal(out.status, 302);
    assert.equal(out.headers.get("location"), "http://localhost:4200/");
    assert.match(out.headers.get("set-cookie"), /Max-Age=0/);

    const afterOut = await call(authorizePath({ prompt: "none" }), { headers: { Cookie: cookie } });
    assert.equal(new URL(afterOut.headers.get("location")).searchParams.get("error"), "login_required");
    const page = await call(authorizePath(), { headers: { Cookie: cookie } });
    assert.ok((await page.text()).includes("Ana Test"));
  });

  test("AC-3: logout with no returnTo goes to the first registered logout address", async () => {
    const out = await call("/v2/logout?client_id=spa");
    assert.equal(out.headers.get("location"), "http://localhost:4200/");
  });

  test("a logout address off the list, or an unknown client, gets an error page", async () => {
    const offList = await call("/v2/logout?client_id=spa&returnTo=http%3A%2F%2Fevil.test%2F");
    assert.equal(offList.status, 400);
    assert.equal(offList.headers.get("location"), null);
    assert.equal((await call("/v2/logout?client_id=ghost")).status, 400);
    assert.equal((await call("/v2/logout?returnTo=http%3A%2F%2Fevil.test%2F")).status, 400);
    const noTarget = await call("/v2/logout?client_id=server");
    assert.equal(noTarget.status, 200);
    assert.ok((await noTarget.text()).includes("You signed out"));
  });

  test("OpenID logout takes the client from the ID token hint and echoes the state", async () => {
    const body = await (await exchange({ code: await codeFor("local|ana") })).json();
    const params = new URLSearchParams({ id_token_hint: body.id_token, post_logout_redirect_uri: "http://localhost:4200/",
      state: "bye" });
    const out = await call(`/oidc/logout?${params}`);
    assert.equal(out.headers.get("location"), "http://localhost:4200/?state=bye");
  });
});

describe("response modes and discovery", () => {
  test("form_post posts the code to the callback", async () => {
    const { response } = await clickLogin("local|ana", { response_mode: "form_post" });
    const page = await response.text();
    assert.equal(response.status, 200);
    assert.ok(page.includes(`action="${CALLBACK}"`));
    assert.match(page, /name="code" value="[A-Za-z0-9_-]{43}"/);
  });

  test("web_message posts the answer to the callback origin only, inside a frame of that origin", async () => {
    const { cookie } = await clickLogin("local|ana");
    const response = await call(authorizePath({ prompt: "none", response_mode: "web_message" }), { headers: { Cookie: cookie } });
    const page = await response.text();
    assert.match(page, /"type":"authorization_response"/);
    assert.ok(page.includes(`, "http://localhost:4200");`));
    assert.match(response.headers.get("content-security-policy"), /frame-ancestors http:\/\/localhost:4200$/);
  });

  test("discovery keeps the issuer and points the endpoints to the address the caller used", async () => {
    // fetch drops a custom Host header, so this request goes through node:http.
    const doc = await new Promise((resolve, reject) => {
      get(`${origin}/.well-known/openid-configuration`, { headers: { Host: "login-simulator:8080" } }, (response) => {
        let raw = "";
        response.on("data", (chunk) => { raw += chunk; });
        response.on("end", () => resolve(JSON.parse(raw)));
      }).on("error", reject);
    });
    assert.equal(doc.issuer, "http://localhost:28080/");
    assert.equal(doc.token_endpoint, "http://login-simulator:8080/oauth/token");
    assert.equal(doc.jwks_uri, "http://login-simulator:8080/.well-known/jwks.json");
    assert.equal(doc.authorization_endpoint, "http://login-simulator:8080/authorize");
  });

  test("the embedded fonts are served as woff2, and only the known names", async () => {
    const response = await call("/fonts/roboto-latin-400-normal.woff2");
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "font/woff2");
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.match(response.headers.get("cache-control"), /max-age=31536000/);
    assert.equal(Buffer.from(await response.arrayBuffer()).subarray(0, 4).toString("latin1"), "wOF2");
    assert.equal((await call("/fonts/arial-latin-400-normal.woff2")).status, 404);
    for (const path of ["/fonts/..%2Fapp.js%00.woff2", "/fonts/..%2F..%2Fpackage.json.woff2",
      "/fonts/%2E%2E%2Ficon.png.woff2", "/fonts/../fonts/LICENSE-OFL.txt.woff2"]) {
      assert.equal((await call(path)).status, 404, path);
    }
  });

  test("the pages allow fonts from the simulator itself and declare the embedded faces", async () => {
    const response = await call("/v2/logout");
    assert.match(response.headers.get("content-security-policy"), /(^|; )font-src 'self'(;|$)/);
    const page = await response.text();
    assert.ok(page.includes('url("/fonts/poppins-latin-700-normal.woff2")'));
    assert.ok(page.includes('url("/fonts/roboto-latin-500-normal.woff2")'));
  });

  test("an unknown path is 404 and a too large body is 400", async () => {
    assert.equal((await call("/nothing")).status, 404);
    const big = await call("/oauth/token", { method: "POST", body: "x=".padEnd(20_000, "y") });
    assert.equal(big.status, 400);
  });
});
