import { createHash } from "node:crypto";

/** Texts of the pages, in English. `{name}` marks a value filled in by `text`. */
const MESSAGES = {
  "login.title": "Login simulator",
  "login.heading": "Sign in to {app}",
  "login.lead": "Local environment, no password and no internet. Choose a fictitious user.",
  "login.roles": "Roles",
  "login.permissions": "Permissions",
  "login.amr": "amr",
  "login.unverified": "email not verified",
  "login.none": "none",
  "login.footer": "Users and applications come from the tool's configuration file.",
  "theme.label": "Theme",
  "theme.system": "System",
  "theme.light": "Light",
  "theme.dark": "Dark",
  "error.title": "Request refused",
  "error.hint": "Fix the request or the tool's configuration file and restart the tool.",
  "error.missingClient": "The request has no client_id.",
  "error.unknownClient": "The application with client_id \"{clientId}\" is not registered.",
  "error.missingRedirect": "The request has no redirect_uri.",
  "error.redirectNotAllowed": "The return address \"{url}\" is not in the login return list of {app}.",
  "error.expiredRequest": "The login request expired or was already used. Go back to the application and start the login again.",
  "error.unknownUser": "The chosen user is not in the configuration file.",
  "error.logoutNotAllowed": "The address \"{url}\" is not in the logout return list of {app}.",
  "error.logoutNotRegistered": "The address \"{url}\" is not in the logout return list of any application.",
  "error.notFound": "Unknown address.",
  "logout.title": "Signed out",
  "logout.text": "You signed out of the login simulator.",
  "formPost.title": "Returning to the application",
  "formPost.continue": "Continue",
};

const AVATAR_COLORS = ["#7ed957", "#ff8a3d", "#a06cf0", "#3dc6f0", "#f05c9a", "#f5c33b"];

const STYLE = `
@font-face { font-family: "Poppins"; font-style: normal; font-weight: 700; font-display: swap;
  src: url("/fonts/poppins-latin-700-normal.woff2") format("woff2"); }
@font-face { font-family: "Roboto"; font-style: normal; font-weight: 400; font-display: swap;
  src: url("/fonts/roboto-latin-400-normal.woff2") format("woff2"); }
@font-face { font-family: "Roboto"; font-style: normal; font-weight: 500; font-display: swap;
  src: url("/fonts/roboto-latin-500-normal.woff2") format("woff2"); }
@font-face { font-family: "Roboto"; font-style: normal; font-weight: 700; font-display: swap;
  src: url("/fonts/roboto-latin-700-normal.woff2") format("woff2"); }
:root { --brand-primary: #5b23bd; --brand-primary-hover: #4a1aa3; --brand-accent-dark: #00f0d0; --brand-ink: #1a0b4b;
  --brand-dark-background: #1b1040; --brand-dark-surface: #251a52; --brand-background: #f7f5fd; --brand-surface: #ffffff;
  --brand-surface-muted: #ece8f8; --brand-text-muted: #4f4670; --brand-text-muted-dark: #cbc4e6; --brand-line: #ddd8ee;
  --brand-line-dark: #6a5fa0; --status-critical: #da3746;
  --font-sans: "Roboto", system-ui, sans-serif; --font-heading: "Poppins", var(--font-sans); --font-mono: ui-monospace,
  "DejaVu Sans Mono", "Liberation Mono", monospace; --radius-control: 0.3125rem; --radius-card: 1.25rem;
  --color-primary: var(--brand-primary); --color-primary-foreground: var(--brand-surface);
  --color-background: var(--brand-background); --color-foreground: var(--brand-ink); --color-card: var(--brand-surface);
  --color-card-foreground: var(--brand-ink); --color-muted: var(--brand-surface-muted);
  --color-muted-foreground: var(--brand-text-muted); --color-border: var(--brand-line);
  --color-input-border: var(--brand-text-muted); --color-ring: var(--brand-primary);
  --color-status-critical: var(--status-critical); --color-shadow: color-mix(in srgb, var(--brand-ink) 8%, transparent);
  color-scheme: light; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --color-background: var(--brand-dark-background);
  --color-foreground: var(--brand-background); --color-card: var(--brand-dark-surface);
  --color-card-foreground: var(--brand-background);
  --color-muted: color-mix(in srgb, var(--brand-dark-surface), var(--brand-text-muted-dark) 10%);
  --color-muted-foreground: var(--brand-text-muted-dark); --color-border: var(--brand-line-dark);
  --color-input-border: var(--brand-text-muted-dark); --color-ring: var(--brand-accent-dark);
  --color-shadow: color-mix(in srgb, var(--brand-ink) 40%, transparent); color-scheme: dark; } }
:root[data-theme="dark"] { --color-background: var(--brand-dark-background); --color-foreground: var(--brand-background);
  --color-card: var(--brand-dark-surface); --color-card-foreground: var(--brand-background);
  --color-muted: color-mix(in srgb, var(--brand-dark-surface), var(--brand-text-muted-dark) 10%);
  --color-muted-foreground: var(--brand-text-muted-dark); --color-border: var(--brand-line-dark);
  --color-input-border: var(--brand-text-muted-dark); --color-ring: var(--brand-accent-dark);
  --color-shadow: color-mix(in srgb, var(--brand-ink) 40%, transparent); color-scheme: dark; }
/* The top bar stays on ink in both themes, as in the container console. */
[data-surface="ink"] { --color-foreground: var(--brand-background);
  --color-muted: color-mix(in srgb, var(--brand-ink), var(--brand-background) 12%);
  --color-muted-foreground: var(--brand-text-muted-dark); --color-border: var(--brand-line-dark);
  --color-input-border: var(--brand-text-muted-dark); --color-ring: var(--brand-accent-dark); }
* { box-sizing: border-box; }
body { margin: 0; background: var(--color-background); color: var(--color-foreground); font-family: var(--font-sans);
  font-size: 0.875rem; line-height: 1.5; }
h1, h2 { margin: 0; font-family: var(--font-heading); font-weight: 700; }
p { margin: 0; color: var(--color-muted-foreground); }
button { font: inherit; color: inherit; }
:focus-visible { outline: 2px solid var(--color-ring); outline-offset: 2px; }
.top-bar { display: flex; align-items: center; gap: 0.5rem; min-height: 3.5rem; padding: 0.5rem 0.75rem;
  border-bottom: 1px solid var(--color-border); background: var(--brand-ink); color: var(--color-foreground); }
.logo { display: inline-flex; flex: none; align-items: center; gap: 0.5rem; }
.logo img { display: block; width: 1.75rem; height: 1.75rem; }
.app-name { display: flex; flex-direction: column; font-family: var(--font-heading); font-weight: 700; font-size: 1rem;
  line-height: 1.2; }
.tool-name { font-family: var(--font-sans); font-weight: 400; font-size: 0.75rem; }
main { max-width: 34rem; margin: 0 auto; padding: 1rem 0.75rem; display: flex; flex-direction: column; gap: 1.5rem; }
@media (min-width: 48rem) { main { padding: 2rem; } }
h1 { font-size: 1.75rem; line-height: 1.15; overflow-wrap: break-word; }
@media (min-width: 48rem) { h1 { font-size: 2rem; } }
.card { background: var(--color-card); color: var(--color-card-foreground); border: 1px solid var(--color-border);
  border-radius: var(--radius-card); box-shadow: 0 1px 2px var(--color-shadow); padding: 1rem; display: flex;
  flex-direction: column; gap: 1rem; min-width: 0; }
@media (min-width: 48rem) { .card { padding: 1.5rem; } }
h2 { font-size: 1rem; line-height: 1.3; }
.users { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 0.5rem; }
.user { width: 100%; display: flex; gap: 0.75rem; align-items: flex-start; text-align: left; padding: 0.75rem;
  border: 1px solid var(--color-input-border); border-radius: var(--radius-control); background: transparent;
  cursor: pointer; min-height: 2.25rem; }
.user:hover { background: var(--color-muted); }
.user img { width: 2.5rem; height: 2.5rem; border-radius: 50%; flex: none; }
.who { display: flex; flex-direction: column; gap: 0.25rem; min-width: 0; }
.name { font-weight: 500; font-size: 1rem; }
h2.name { font-weight: 700; }
.mail, .id { color: var(--color-muted-foreground); font-size: 0.75rem; overflow-wrap: anywhere; }
.id { font-family: var(--font-mono); }
.access { display: flex; flex-wrap: wrap; gap: 0.25rem; align-items: center; font-size: 0.75rem;
  color: var(--color-muted-foreground); }
.chip { background: var(--color-muted); color: var(--color-foreground); border-radius: var(--radius-control);
  padding: 0 0.375rem; font-family: var(--font-mono); }
.user:hover .chip { background: var(--color-card); }
.theme { display: flex; flex-wrap: wrap; gap: 0.25rem; align-items: center; margin-inline-start: auto;
  font-size: 0.75rem; color: var(--color-muted-foreground); }
.theme button { color: var(--color-foreground); background: transparent; border: 1px solid var(--color-input-border);
  border-radius: var(--radius-control); padding: 0.25rem 0.75rem; min-height: 2rem; font-weight: 500; cursor: pointer; }
.theme button:hover { background: var(--color-muted); }
.theme button[aria-pressed="true"] { background: var(--brand-accent-dark); border-color: var(--brand-accent-dark);
  color: var(--brand-ink); }
.reason { border-left: 4px solid var(--color-status-critical); padding-left: 0.75rem; color: var(--color-card-foreground);
  overflow-wrap: anywhere; }
noscript button { min-height: 2.25rem; padding: 0.5rem 1rem; border: 1px solid transparent;
  border-radius: var(--radius-control); background: var(--color-primary); color: var(--color-primary-foreground);
  font-weight: 500; cursor: pointer; }
`;

/** Replaces `{name}` placeholders of the message `key` with the matching `params`, HTML-escaped. */
function text(key, params = {}) {
  return escapeHtml(MESSAGES[key]).replace(/\{(\w+)\}/g, (_, name) => escapeHtml(params[name] ?? ""));
}

/** Escapes a value for HTML text and attribute positions. */
export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);
}

/** Script that applies and stores the theme choice (system, light, dark); browser storage may be unavailable. */
const THEME_SCRIPT = `
const root = document.documentElement;
const read = () => { try { return localStorage.getItem("theme") || "system"; } catch { return "system"; } };
const apply = (theme) => {
  if (theme === "system") root.removeAttribute("data-theme"); else root.dataset.theme = theme;
  document.querySelectorAll("[data-theme-choice]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.themeChoice === theme)));
};
document.querySelectorAll("[data-theme-choice]").forEach((b) => b.addEventListener("click", () => {
  try { localStorage.setItem("theme", b.dataset.themeChoice); } catch {}
  apply(b.dataset.themeChoice);
}));
apply(read());`;

/**
 * Wraps `body` in the common page skeleton; `nonce` authorizes the page's own inline scripts and `header`, the top bar,
 * goes above the main content.
 */
function layout(title, body, nonce, script = THEME_SCRIPT, header = "") {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${escapeHtml(title)}</title>
<link rel="icon" type="image/png" href="/favicon.png">
<style nonce="${nonce}">${STYLE}</style>
</head>
<body>
${header}<main>${body}</main>
<script nonce="${nonce}">${script}</script>
</body>
</html>`;
}

/** Top bar on ink, as in the container console: project icon, workspace and tool names, and the theme switch. */
function topBar() {
  const choice = (theme) =>
    `<button type="button" data-theme-choice="${theme}" aria-pressed="false">${text(`theme.${theme}`)}</button>`;
  return `<header class="top-bar" data-surface="ink"><div class="logo"><img src="/favicon.png" alt="" width="28" height="28">
<span class="app-name">Claude CLI Agents Workspace<span class="tool-name">Login Simulator</span></span></div>
<div class="theme" role="group" aria-label="${text("theme.label")}">${choice("system")}${choice("light")}${choice("dark")}</div>
</header>`;
}

/** Title of the page, first thing of the main content. */
function pageHeader(heading) {
  return `<h1>${heading}</h1>`;
}

/** One line of access types (roles or permissions) of a user. */
function accessLine(labelKey, items) {
  const chips = items.length === 0 ? text("login.none")
    : items.map((item) => `<span class="chip">${escapeHtml(item)}</span>`).join("");
  return `<span class="access">${text(labelKey)}: ${chips}</span>`;
}

/**
 * Login page: one button per user; a click posts the pending request id and the user id to /login.
 * `users` items carry `pictureUrl`, the picture as the browser reaches it.
 */
export function loginPage({ appName, requestId, users, nonce }) {
  const items = users.map((user) => `<li><button class="user" type="submit" name="user" value="${escapeHtml(user.id)}">
<img src="${escapeHtml(user.pictureUrl)}" alt="">
<span class="who"><span class="name">${escapeHtml(`${user.givenName} ${user.familyName}`)}</span>
<span class="mail">${escapeHtml(user.email)}${user.emailVerified ? "" : ` (${text("login.unverified")})`}</span>
<span class="id">${escapeHtml(user.id)}</span>
${accessLine("login.roles", user.roles)}${accessLine("login.permissions", user.permissions)}${
  user.amr === null ? "" : accessLine("login.amr", user.amr)}</span>
</button></li>`).join("\n");
  const body = `${pageHeader(text("login.title"))}
<section class="card" aria-labelledby="login-heading">
<h2 id="login-heading" class="name">${text("login.heading", { app: appName })}</h2>
<p>${text("login.lead")}</p>
<form method="post" action="/login"><input type="hidden" name="request" value="${escapeHtml(requestId)}">
<ul class="users">${items}</ul></form>
</section>
<p>${text("login.footer")}</p>`;
  return layout(text("login.title"), body, nonce, THEME_SCRIPT, topBar());
}

/** Error page that states the reason; `reasonKey` and `params` pick and fill the message. */
export function errorPage({ reasonKey, params, nonce }) {
  const body = `${pageHeader(text("error.title"))}
<section class="card"><p class="reason" role="alert">${text(reasonKey, params)}</p><p>${text("error.hint")}</p></section>`;
  return layout(text("error.title"), body, nonce, THEME_SCRIPT, topBar());
}

/** Page shown after a logout with no address to return to. */
export function loggedOutPage({ nonce }) {
  const body = `${pageHeader(text("logout.title"))}<section class="card"><p>${text("logout.text")}</p></section>`;
  return layout(text("logout.title"), body, nonce, THEME_SCRIPT, topBar());
}

/** response_mode=form_post: a form that posts `fields` to `action` by itself, with a button when scripts are off. */
export function formPostPage({ action, fields, nonce }) {
  const inputs = Object.entries(fields)
    .map(([name, value]) => `<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(value)}">`).join("");
  const body = `<form method="post" action="${escapeHtml(action)}">${inputs}
<noscript><button type="submit">${text("formPost.continue")}</button></noscript></form>`;
  return layout(text("formPost.title"), body, nonce, "document.forms[0].submit();");
}

/**
 * response_mode=web_message (silent login of auth0-spa-js in an iframe): posts `response` to the parent window,
 * restricted to `origin`, the origin of the registered callback URL.
 */
export function webMessagePage({ origin, response, nonce }) {
  const message = JSON.stringify({ type: "authorization_response", response }).replace(/</g, "\\u003c");
  const target = JSON.stringify(origin).replace(/</g, "\\u003c");
  return layout(text("formPost.title"), "", nonce,
    `(window.opener || window.parent).postMessage(${message}, ${target});`);
}

/** Eyes of the mascot: one big eye, two eyes or three eyes. */
const MASCOT_EYES = [
  '<circle cx="48" cy="44" r="14" fill="#fff"/><circle cx="51" cy="46" r="7" fill="#222"/><circle cx="53" cy="43" r="2" fill="#fff"/>',
  '<circle cx="36" cy="44" r="9" fill="#fff"/><circle cx="60" cy="44" r="9" fill="#fff"/>'
    + '<circle cx="38" cy="46" r="4.5" fill="#222"/><circle cx="62" cy="46" r="4.5" fill="#222"/>',
  '<circle cx="32" cy="46" r="7" fill="#fff"/><circle cx="48" cy="38" r="7" fill="#fff"/><circle cx="64" cy="46" r="7" fill="#fff"/>'
    + '<circle cx="33" cy="47" r="3.5" fill="#222"/><circle cx="49" cy="39" r="3.5" fill="#222"/>'
    + '<circle cx="65" cy="47" r="3.5" fill="#222"/>',
];

/** Mouth of the mascot: a smile, an open mouth with one tooth, or a tongue out. */
const MASCOT_MOUTHS = [
  '<path d="M34 64 Q48 76 62 64" fill="none" stroke="#222" stroke-width="3.5" stroke-linecap="round"/>',
  '<path d="M36 62 Q48 80 60 62 Z" fill="#222"/><rect x="44" y="62" width="7" height="6" rx="1" fill="#fff"/>',
  '<path d="M36 64 Q48 72 60 64" fill="none" stroke="#222" stroke-width="3.5" stroke-linecap="round"/>'
    + '<path d="M50 67 Q55 78 59 66 Z" fill="#ff6b8a"/>',
];

/** Top of the mascot's head: two antennae, two horns, or a tuft of hair. */
const MASCOT_TOPS = [
  '<path d="M38 22 L32 8 M58 22 L64 8" stroke="#222" stroke-width="3" stroke-linecap="round"/>'
    + '<circle cx="32" cy="8" r="4" fill="#ffd54f"/><circle cx="64" cy="8" r="4" fill="#ffd54f"/>',
  '<path d="M28 26 L22 8 L38 20 Z M68 26 L74 8 L58 20 Z" fill="#fff3e0"/>',
  '<path d="M40 20 Q44 4 48 18 Q52 4 56 20" fill="none" stroke="#222" stroke-width="3" stroke-linecap="round"/>',
];

/**
 * Generated avatar, for a user with no picture in the configuration: a cartoon mascot whose color, eyes, mouth and
 * top come from the hash of the user id, so each user always gets the same one. No user data goes in the image.
 */
export function mascotAvatar(user) {
  const hash = createHash("sha256").update(user.id).digest();
  const pick = (list, byte) => list[hash[byte] % list.length];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
<circle cx="48" cy="48" r="48" fill="#f4f1ea"/>
${pick(MASCOT_TOPS, 3)}
<ellipse cx="48" cy="54" rx="32" ry="34" fill="${pick(AVATAR_COLORS, 0)}"/>
${pick(MASCOT_EYES, 1)}
${pick(MASCOT_MOUTHS, 2)}
</svg>`;
}
