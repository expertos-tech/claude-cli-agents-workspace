import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { normalizeUrl } from "./config.js";
import { errorPage, formPostPage, mascotAvatar, loggedOutPage, loginPage, webMessagePage } from "./pages.js";
import { safeEqual, verifyPkce } from "./tokens.js";

const LOGIN_REQUEST_TTL_MS = 10 * 60 * 1000;
const CODE_TTL_MS = 5 * 60 * 1000;
const ID_TOKEN_TTL_S = 36000; // Auth0 default
const ACCESS_TOKEN_TTL_S = 86400; // Auth0 default
const MAX_BODY_BYTES = 16 * 1024;
const SESSION_COOKIE = "login_simulator_session";
const RESPONSE_MODES = ["query", "form_post", "web_message"];
const CHALLENGE_FORMAT = /^[A-Za-z0-9._~-]{43,128}$/;
const HOST_FORMAT = /^[A-Za-z0-9.-]{1,253}(:\d{1,5})?$/;
/** Project icon of the workspace (assets/icon.png at 64 px), shown in the top bar and as the favicon. */
const ICON = readFileSync(new URL("./icon.png", import.meta.url));
/** Fonts of the container console (latin woff2, see fonts/LICENSE-OFL.txt), by name; only these are served. */
const FONTS = new Map(["poppins-latin-700-normal", "roboto-latin-400-normal", "roboto-latin-500-normal",
  "roboto-latin-700-normal"].map((name) => [name, readFileSync(new URL(`./fonts/${name}.woff2`, import.meta.url))]));

/** Answer of an invalid request body; `handle` turns it into a 400 invalid_request. */
class BadRequest extends Error {}

/** Short-lived single-use records (login requests, authorization codes), dropped when expired or taken. */
class TtlStore {
  /** `now` returns milliseconds; `ttlMs` is the life of each record. */
  constructor(now, ttlMs) {
    this.now = now;
    this.ttlMs = ttlMs;
    this.items = new Map();
  }

  /** Stores `value` under `key` and drops the expired records. */
  put(key, value) {
    const now = this.now();
    for (const [oldKey, item] of this.items) if (item.expiresAt <= now) this.items.delete(oldKey);
    this.items.set(key, { value, expiresAt: now + this.ttlMs });
  }

  /** Removes and returns the value of `key`, or null when it is missing or expired. */
  take(key) {
    const item = typeof key === "string" ? this.items.get(key) : undefined;
    if (item === undefined) return null;
    this.items.delete(key);
    return item.expiresAt > this.now() ? item.value : null;
  }
}

/**
 * Builds the HTTP handler of the simulator: the Auth0 endpoints (/authorize, /oauth/token, /userinfo, discovery,
 * JWKS, /v2/logout, /oidc/logout), the login page and the generated avatars. All state is in memory.
 * `avatarOrigin` is where the generated avatars are linked (default: the issuer's origin); `now` returns milliseconds;
 * `random` returns a base64url secret of the given byte count.
 */
export function createApp({ config, signer, avatarOrigin, now = () => Date.now(), random = defaultRandom }) {
  const loginRequests = new TtlStore(now, LOGIN_REQUEST_TTL_MS);
  const codes = new TtlStore(now, CODE_TTL_MS);
  const sessions = new Map();
  const updatedAt = new Date(now()).toISOString();
  const allowedOrigins = new Set(config.applications
    .flatMap((app) => [...app.callbackUrls, ...app.logoutUrls]).map((url) => new URL(url).origin));
  const userinfoAudience = new URL("userinfo", config.issuer).href;
  const pictureOrigin = avatarOrigin ?? new URL(config.issuer).origin;

  const findApp = (clientId) => config.applications.find((app) => app.clientId === clientId) ?? null;
  const findUser = (id) => config.users.find((user) => user.id === id) ?? null;
  const seconds = () => Math.floor(now() / 1000);

  /**
   * Picture of `user`: the configured URL as it is, or the generated avatar at `pictureOrigin`. Never the caller's
   * host: the same URL goes to the browser and to a backend that reads /userinfo through the Docker network, so the
   * origin must be one both reach (README, "Foto gerada").
   */
  function pictureUrl(user) {
    return user.picture ?? `${pictureOrigin}/avatars/${Buffer.from(user.id).toString("base64url")}.svg`;
  }

  /** Claims of `user` that `scopes` release, plus the access types, as Auth0 fills them. */
  function userClaims(user, scopes, app) {
    const claims = { sub: user.id };
    if (scopes.has("profile")) {
      Object.assign(claims, {
        name: `${user.givenName} ${user.familyName}`, given_name: user.givenName, family_name: user.familyName,
        nickname: user.email.split("@")[0], picture: pictureUrl(user), updated_at: updatedAt,
      });
    }
    if (scopes.has("email")) Object.assign(claims, { email: user.email, email_verified: user.emailVerified });
    claims[app.rolesClaim] = user.roles;
    claims.permissions = user.permissions;
    return claims;
  }

  /** Sends the answer of /authorize back to the application, in the response mode it asked for. */
  function replyToClient(res, grant, fields) {
    const values = grant.state === undefined ? fields : { ...fields, state: grant.state };
    const nonce = random(16);
    if (grant.mode === "form_post") {
      return sendHtml(res, 200, formPostPage({ action: grant.redirectUri, fields: values, nonce }), nonce);
    }
    if (grant.mode === "web_message") {
      const origin = new URL(grant.redirectUri).origin;
      return sendHtml(res, 200, webMessagePage({ origin, response: values, nonce }), nonce, origin);
    }
    const target = new URL(grant.redirectUri);
    for (const [name, value] of Object.entries(values)) target.searchParams.set(name, value);
    return redirect(res, target.href);
  }

  /** Issues the authorization code of `grant` for the user of session `sid` and sends it to the application. */
  function issueCode(res, grant, userId, sid) {
    const code = random(32);
    codes.put(code, { ...grant, userId, sid });
    replyToClient(res, grant, { code });
  }

  /** Shows the error page with the reason (no redirect: the application or its return address is not trusted). */
  function refuse(res, reasonKey, params = {}) {
    const nonce = random(16);
    sendHtml(res, 400, errorPage({ reasonKey, params, nonce }), nonce);
  }

  /** Returns the [sid, userId] of the browser's login session, or null. */
  function sessionOf(req) {
    const sid = readCookie(req, SESSION_COOKIE);
    return sid && sessions.has(sid) ? [sid, sessions.get(sid)] : null;
  }

  /** GET /authorize: validates the application and its return address, then shows the users or answers prompt=none. */
  function authorize(req, res, params) {
    if (!params.client_id) return refuse(res, "error.missingClient");
    const app = findApp(params.client_id);
    if (app === null) return refuse(res, "error.unknownClient", { clientId: params.client_id });
    if (!params.redirect_uri) return refuse(res, "error.missingRedirect");
    const redirectUri = normalizeUrl(params.redirect_uri);
    if (!app.callbackUrls.includes(redirectUri)) {
      return refuse(res, "error.redirectNotAllowed", { url: params.redirect_uri, app: app.name });
    }

    const grant = {
      clientId: app.clientId, redirectUri, state: params.state, nonce: params.nonce, audience: params.audience,
      scope: params.scope || "openid", challenge: params.code_challenge,
      method: params.code_challenge ? params.code_challenge_method || "plain" : null,
      mode: RESPONSE_MODES.includes(params.response_mode) ? params.response_mode : "query",
    };
    const problem = authorizeProblem(params, app, grant);
    if (problem) return replyToClient(res, grant, { error: problem[0], error_description: problem[1] });

    if (params.prompt === "none") {
      const session = sessionOf(req);
      if (session === null) return replyToClient(res, grant, { error: "login_required", error_description: "Login required" });
      return issueCode(res, grant, session[1], session[0]);
    }

    const requestId = random(32);
    loginRequests.put(requestId, grant);
    const users = config.users.map((user) => ({ ...user, pictureUrl: pictureUrl(user) }));
    const nonce = random(16);
    return sendHtml(res, 200, loginPage({ appName: app.name, requestId, users, nonce }), nonce);
  }

  /** POST /login: the click on a user; opens the login session and returns the code to the application. */
  async function login(req, res) {
    const body = await readBody(req);
    const grant = loginRequests.take(body.request);
    if (grant === null) return refuse(res, "error.expiredRequest");
    const user = findUser(body.user);
    if (user === null) return refuse(res, "error.unknownUser");

    const sid = random(32);
    sessions.set(sid, user.id);
    res.setHeader("Set-Cookie", `${SESSION_COOKIE}=${sid}; Path=/; HttpOnly; SameSite=Lax`);
    return issueCode(res, grant, user.id, sid);
  }

  /** POST /oauth/token: exchanges an authorization code (with its PKCE verifier or client secret) for tokens. */
  async function token(req, res) {
    const body = await readBody(req);
    const credentials = { ...body, ...basicCredentials(req) };
    if (body.grant_type !== "authorization_code") {
      return oauthError(req, res, 400, "unsupported_grant_type", "Only authorization_code is supported");
    }
    const app = findApp(credentials.client_id);
    if (app === null || (app.clientSecret !== null && !safeEqual(credentials.client_secret ?? "", app.clientSecret))) {
      return oauthError(req, res, 401, "invalid_client", "Unknown client or wrong client secret");
    }
    const code = codes.take(body.code);
    if (code === null || code.clientId !== app.clientId || normalizeUrl(body.redirect_uri ?? "") !== code.redirectUri
      || (code.challenge && !verifyPkce(body.code_verifier, code.challenge, code.method))) {
      return oauthError(req, res, 403, "invalid_grant", "Invalid authorization code or code verifier");
    }
    return sendJson(req, res, 200, issueTokens(code, app, findUser(code.userId)));
  }

  /**
   * Signs the ID token (when the scope has openid) and the access token of an exchanged code. The user's `amr`, when
   * the file has it, goes in both, as the hub's Auth0 MFA Action puts it; it is not a /userinfo claim.
   */
  function issueTokens(code, app, user) {
    const iat = seconds();
    const scopes = new Set(code.scope.split(" "));
    const amr = user.amr === null ? {} : { amr: user.amr };
    const claims = { ...userClaims(user, scopes, app), ...amr };
    const access = {
      iss: config.issuer, sub: user.id, aud: code.audience ? [code.audience, userinfoAudience] : userinfoAudience,
      iat, exp: iat + ACCESS_TOKEN_TTL_S, scope: code.scope, azp: app.clientId,
      [app.rolesClaim]: user.roles, permissions: user.permissions, ...amr,
    };
    const answer = { access_token: signer.sign(access), scope: code.scope, expires_in: ACCESS_TOKEN_TTL_S, token_type: "Bearer" };
    if (scopes.has("openid")) {
      const id = { ...claims, iss: config.issuer, aud: app.clientId, iat, exp: iat + ID_TOKEN_TTL_S, sid: code.sid };
      if (code.nonce) id.nonce = code.nonce;
      answer.id_token = signer.sign(id);
    }
    return answer;
  }

  /** GET or POST /userinfo: the claims of the access token's user. */
  function userinfo(req, res) {
    const header = req.headers.authorization ?? "";
    const payload = header.startsWith("Bearer ") ? signer.verify(header.slice(7)) : null;
    const user = payload && payload.iss === config.issuer && payload.exp > seconds() ? findUser(payload.sub) : null;
    const app = payload ? findApp(payload.azp) : null;
    if (user === null || app === null) {
      res.setHeader("WWW-Authenticate", 'Bearer error="invalid_token"');
      return oauthError(req, res, 401, "invalid_token", "Invalid or expired access token");
    }
    return sendJson(req, res, 200, userClaims(user, new Set(String(payload.scope).split(" ")), app));
  }

  /**
   * Ends the login session and returns to `returnTo` when it is a registered logout address (of `clientId` when
   * given, else of any application). With no `returnTo`: the application's first logout address, or a page.
   */
  function logout(req, res, { clientId, returnTo, state }) {
    const session = sessionOf(req);
    if (session !== null) sessions.delete(session[0]);
    res.setHeader("Set-Cookie", `${SESSION_COOKIE}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax`);

    const app = clientId ? findApp(clientId) : null;
    if (clientId && app === null) return refuse(res, "error.unknownClient", { clientId });
    const allowed = app ? app.logoutUrls : config.applications.flatMap((item) => item.logoutUrls);
    const target = returnTo ? normalizeUrl(returnTo) : app?.logoutUrls[0];
    if (returnTo && !allowed.includes(target)) {
      return app ? refuse(res, "error.logoutNotAllowed", { url: returnTo, app: app.name })
        : refuse(res, "error.logoutNotRegistered", { url: returnTo });
    }
    if (!target) {
      const nonce = random(16);
      return sendHtml(res, 200, loggedOutPage({ nonce }), nonce);
    }
    const url = new URL(target);
    if (state) url.searchParams.set("state", state);
    return redirect(res, url.href);
  }

  /** GET /oidc/logout (OpenID RP-initiated logout): the application comes from client_id or the ID token hint. */
  function oidcLogout(req, res, params) {
    const hint = params.id_token_hint ? signer.verify(params.id_token_hint) : null;
    const clientId = params.client_id || (typeof hint?.aud === "string" ? hint.aud : undefined);
    return logout(req, res, { clientId, returnTo: params.post_logout_redirect_uri, state: params.state });
  }

  /** OpenID discovery document; the endpoints use `base`, the address this request came through. */
  function discovery(req, res, base) {
    return sendJson(req, res, 200, {
      issuer: config.issuer,
      authorization_endpoint: `${base}/authorize`,
      token_endpoint: `${base}/oauth/token`,
      userinfo_endpoint: `${base}/userinfo`,
      jwks_uri: `${base}/.well-known/jwks.json`,
      end_session_endpoint: `${base}/oidc/logout`,
      scopes_supported: ["openid", "profile", "email"],
      response_types_supported: ["code"],
      response_modes_supported: RESPONSE_MODES,
      grant_types_supported: ["authorization_code"],
      code_challenge_methods_supported: ["S256", "plain"],
      subject_types_supported: ["public"],
      id_token_signing_alg_values_supported: ["RS256"],
      token_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"],
      claims_supported: ["sub", "iss", "aud", "exp", "iat", "nonce", "sid", "name", "given_name", "family_name",
        "nickname", "picture", "updated_at", "email", "email_verified", "permissions", "amr"],
    });
  }

  /** GET /avatars/<base64url user id>.svg: the generated mascot avatar of any user of the file. */
  function avatar(res, key) {
    const user = config.users.find((item) => Buffer.from(item.id).toString("base64url") === key);
    if (!user) return notFound(res);
    res.writeHead(200, { "Content-Type": "image/svg+xml", "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'", "X-Content-Type-Options": "nosniff" });
    return res.end(mascotAvatar(user));
  }

  /** Sends the project icon. */
  function icon(res) {
    res.writeHead(200, { "Content-Type": "image/png", "Cache-Control": "public, max-age=86400",
      "Content-Security-Policy": "default-src 'none'", "X-Content-Type-Options": "nosniff" });
    return res.end(ICON);
  }

  /** GET /fonts/<name>.woff2: one of the embedded fonts; any other name is 404. */
  function font(res, name) {
    const file = FONTS.get(name);
    if (!file) return notFound(res);
    res.writeHead(200, { "Content-Type": "font/woff2", "Cache-Control": "public, max-age=31536000, immutable",
      "Content-Security-Policy": "default-src 'none'", "X-Content-Type-Options": "nosniff" });
    return res.end(file);
  }

  /** Answers a CORS preflight from a registered application origin. */
  function preflight(req, res) {
    corsHeaders(req, res);
    res.writeHead(204, { "Access-Control-Allow-Methods": "GET, POST", "Access-Control-Max-Age": "600",
      "Access-Control-Allow-Headers": "Authorization, Content-Type, Auth0-Client" });
    res.end();
  }

  /** Lets a registered application origin read the answer (the SPA calls /oauth/token and /userinfo). */
  function corsHeaders(req, res) {
    const origin = req.headers.origin;
    if (origin && allowedOrigins.has(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
    }
  }

  /** Sends JSON with no caching, plus CORS for registered origins. */
  function sendJson(req, res, status, body) {
    corsHeaders(req, res);
    res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff" });
    res.end(JSON.stringify(body));
  }

  /** Sends an OAuth error answer. */
  function oauthError(req, res, status, error, description) {
    return sendJson(req, res, status, { error, error_description: description });
  }

  /** Routes one request. */
  async function route(req, res) {
    const url = new URL(req.url, "http://placeholder");
    const params = Object.fromEntries(url.searchParams);
    const base = baseUrl(req, config.issuer);
    const key = `${req.method} ${url.pathname}`;
    if (req.method === "OPTIONS" && ["/oauth/token", "/userinfo"].includes(url.pathname)) return preflight(req, res);
    if (req.method === "GET" && url.pathname.startsWith("/avatars/") && url.pathname.endsWith(".svg")) {
      return avatar(res, url.pathname.slice("/avatars/".length, -".svg".length));
    }
    if (req.method === "GET" && url.pathname.startsWith("/fonts/") && url.pathname.endsWith(".woff2")) {
      return font(res, url.pathname.slice("/fonts/".length, -".woff2".length));
    }
    switch (key) {
      case "GET /healthz": return sendJson(req, res, 200, { status: "ok" });
      case "GET /favicon.png": return icon(res);
      case "GET /.well-known/openid-configuration": return discovery(req, res, base);
      case "GET /.well-known/jwks.json": return sendJson(req, res, 200, signer.jwks);
      case "GET /authorize": return authorize(req, res, params);
      case "POST /login": return login(req, res);
      case "POST /oauth/token": return token(req, res);
      case "GET /userinfo": case "POST /userinfo": return userinfo(req, res);
      case "GET /v2/logout": return logout(req, res, { clientId: params.client_id, returnTo: params.returnTo });
      case "GET /oidc/logout": return oidcLogout(req, res, params);
      default: return notFound(res);
    }
  }

  /** The request handler: routes, and turns a bad body into 400 and any other failure into 500. */
  return async function handle(req, res) {
    try {
      await route(req, res);
    } catch (error) {
      if (res.headersSent) return res.destroy();
      if (error instanceof BadRequest) return oauthError(req, res, 400, "invalid_request", error.message);
      console.error(JSON.stringify({ event: "request_failed", path: new URL(req.url, "http://x").pathname,
        error: error.name }));
      return oauthError(req, res, 500, "server_error", "Internal error");
    }
  };

  /** Plain 404 answer. */
  function notFound(res) {
    const nonce = random(16);
    return sendHtml(res, 404, errorPage({ reasonKey: "error.notFound", params: {}, nonce }), nonce);
  }
}

/** Returns the [error, description] of an /authorize request that cannot get a code, or null when it can. */
function authorizeProblem(params, app, grant) {
  if (params.response_type !== "code") return ["unsupported_response_type", "Only response_type=code is supported"];
  if (params.response_mode && !RESPONSE_MODES.includes(params.response_mode)) {
    return ["invalid_request", "Unsupported response_mode"];
  }
  if (grant.challenge) {
    if (!["S256", "plain"].includes(grant.method)) return ["invalid_request", "Unsupported code_challenge_method"];
    if (!CHALLENGE_FORMAT.test(grant.challenge)) return ["invalid_request", "Invalid code_challenge"];
  } else if (app.clientSecret === null) {
    return ["invalid_request", "code_challenge is required for an application with no client secret"];
  }
  return null;
}

/** Base URL of the request, from its Host header; the issuer's origin when the header is missing or malformed. */
function baseUrl(req, issuer) {
  const host = req.headers.host;
  return host && HOST_FORMAT.test(host) ? `http://${host}` : new URL(issuer).origin;
}

/** Reads a form or JSON body of at most MAX_BODY_BYTES into a flat object of strings. */
async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new BadRequest("Body too large");
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  const type = (req.headers["content-type"] ?? "").split(";")[0].trim();
  if (type === "application/json") {
    let value;
    try {
      value = JSON.parse(raw);
    } catch {
      throw new BadRequest("Invalid JSON body");
    }
    if (value === null || typeof value !== "object" || Array.isArray(value)) throw new BadRequest("Invalid JSON body");
    return Object.fromEntries(Object.entries(value).filter(([, item]) => typeof item === "string"));
  }
  return Object.fromEntries(new URLSearchParams(raw));
}

/** client_id and client_secret of an HTTP Basic Authorization header, or nothing. */
function basicCredentials(req) {
  const header = req.headers.authorization ?? "";
  if (!header.startsWith("Basic ")) return {};
  const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
  const separator = decoded.indexOf(":");
  if (separator < 0) return {};
  try {
    return { client_id: decodeURIComponent(decoded.slice(0, separator)),
      client_secret: decodeURIComponent(decoded.slice(separator + 1)) };
  } catch {
    throw new BadRequest("Invalid Basic credentials");
  }
}

/** Value of cookie `name` in the request, or null. */
function readCookie(req, name) {
  for (const part of (req.headers.cookie ?? "").split(";")) {
    const [key, ...value] = part.trim().split("=");
    if (key === name) return value.join("=");
  }
  return null;
}

/** Sends an HTML page with a CSP that runs only the page's own nonce; `frameOrigin` may embed it (web_message). */
function sendHtml(res, status, html, nonce, frameOrigin = "'none'") {
  res.writeHead(status, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": `default-src 'none'; img-src 'self' data: http: https:; font-src 'self'; style-src 'nonce-${nonce}'; `
      + `script-src 'nonce-${nonce}'; base-uri 'none'; frame-ancestors ${frameOrigin}`,
  });
  res.end(html);
}

/** Sends a 302 to `location`. */
function redirect(res, location) {
  res.writeHead(302, { Location: location, "Cache-Control": "no-store" });
  res.end();
}

/** A random secret of `bytes` bytes in base64url. */
function defaultRandom(bytes) {
  return randomBytes(bytes).toString("base64url");
}
