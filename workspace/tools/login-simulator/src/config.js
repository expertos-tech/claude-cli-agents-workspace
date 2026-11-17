import { readFileSync } from "node:fs";

const MAX_TEXT = 200;
const ROOT_FIELDS = ["issuer", "applications", "users"];
const APP_FIELDS = ["name", "clientId", "clientSecret", "callbackUrls", "logoutUrls", "rolesClaim"];
const USER_FIELDS = ["id", "givenName", "familyName", "email", "emailVerified", "picture", "roles", "permissions", "amr"];
const DEFAULT_ROLES_CLAIM = "roles";

/** Error of an invalid configuration file; the message names the field and what is wrong with it. */
export class ConfigError extends Error {}

/** Reads and validates the JSON configuration file at `path`; throws ConfigError on the first problem. */
export function loadConfig(path) {
  let raw;
  try {
    raw = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new ConfigError(`cannot read ${path}: ${error.message}`);
  }
  return parseConfig(raw);
}

/** Validates a parsed configuration object and returns it normalized (URLs in canonical form, defaults filled). */
export function parseConfig(raw) {
  requireObject(raw, "config", ROOT_FIELDS);
  const issuer = requireUrl(raw.issuer, "issuer");
  const applications = requireList(raw.applications, "applications").map(parseApplication);
  const users = requireList(raw.users, "users").map(parseUser);
  requireUnique(applications.map((app) => app.clientId), "applications[].clientId");
  requireUnique(users.map((user) => user.id), "users[].id");
  return { issuer, applications, users };
}

/** Normalizes a URL so that equal addresses compare equal (e.g. a missing "/" path); returns null when invalid. */
export function normalizeUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (url.hash || url.username || url.password) return null;
    return url.href;
  } catch {
    return null;
  }
}

/**
 * Validates the origin of the generated avatars (the AVATAR_ORIGIN variable): an http(s) origin with no path, query,
 * fragment or credentials. Returns it without the trailing "/"; throws ConfigError naming `where` otherwise.
 */
export function parseOrigin(value, where) {
  const url = typeof value === "string" ? normalizeUrl(value) : null;
  if (url === null || url !== `${new URL(url).origin}/`) {
    throw new ConfigError(`${where} must be an http(s) origin with no path, like http://172.31.250.10:8080`);
  }
  return new URL(url).origin;
}

/** Validates one entry of `applications`. */
function parseApplication(raw, index) {
  const where = `applications[${index}]`;
  requireObject(raw, where, APP_FIELDS);
  return {
    name: requireText(raw.name, `${where}.name`),
    clientId: requireText(raw.clientId, `${where}.clientId`),
    clientSecret: raw.clientSecret === undefined ? null : requireText(raw.clientSecret, `${where}.clientSecret`),
    callbackUrls: requireUrlList(raw.callbackUrls, `${where}.callbackUrls`, 1),
    logoutUrls: requireUrlList(raw.logoutUrls ?? [], `${where}.logoutUrls`, 0),
    rolesClaim: raw.rolesClaim === undefined ? DEFAULT_ROLES_CLAIM : requireText(raw.rolesClaim, `${where}.rolesClaim`),
  };
}

/** Validates one entry of `users`. */
function parseUser(raw, index) {
  const where = `users[${index}]`;
  requireObject(raw, where, USER_FIELDS);
  const email = requireText(raw.email, `${where}.email`);
  if (!/^[^\s@]+@[^\s@]+$/.test(email)) throw new ConfigError(`${where}.email is not an e-mail address`);
  return {
    id: requireText(raw.id, `${where}.id`),
    givenName: requireText(raw.givenName, `${where}.givenName`),
    familyName: requireText(raw.familyName, `${where}.familyName`),
    email,
    emailVerified: raw.emailVerified === undefined ? true : requireBoolean(raw.emailVerified, `${where}.emailVerified`),
    picture: raw.picture === undefined ? null : requirePicture(raw.picture, `${where}.picture`),
    roles: requireTextList(raw.roles ?? [], `${where}.roles`),
    permissions: requireTextList(raw.permissions ?? [], `${where}.permissions`),
    amr: raw.amr === undefined ? null : requireTextList(raw.amr, `${where}.amr`),
  };
}

/** Requires a plain object holding only the `allowed` keys. */
function requireObject(value, where, allowed) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ConfigError(`${where} must be an object`);
  }
  const unknown = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unknown.length > 0) throw new ConfigError(`${where} has unknown fields: ${unknown.join(", ")}`);
}

/** Requires an array with at least one item. */
function requireList(value, where) {
  if (!Array.isArray(value) || value.length === 0) throw new ConfigError(`${where} must be a non-empty list`);
  return value;
}

/** Requires a non-empty string of at most MAX_TEXT characters, with no control characters. */
function requireText(value, where) {
  if (typeof value !== "string" || value.trim() === "" || value.length > MAX_TEXT || /\p{Cc}/u.test(value)) {
    throw new ConfigError(`${where} must be a text of 1 to ${MAX_TEXT} characters`);
  }
  return value;
}

/** Requires true or false. */
function requireBoolean(value, where) {
  if (typeof value !== "boolean") throw new ConfigError(`${where} must be true or false`);
  return value;
}

/** Requires a list of texts with no repeated item. */
function requireTextList(value, where) {
  if (!Array.isArray(value)) throw new ConfigError(`${where} must be a list`);
  const items = value.map((item, index) => requireText(item, `${where}[${index}]`));
  requireUnique(items, where);
  return items;
}

/** Requires an absolute http(s) URL with no fragment or credentials; returns it normalized. */
function requireUrl(value, where) {
  const url = typeof value === "string" ? normalizeUrl(value) : null;
  if (url === null) throw new ConfigError(`${where} must be an absolute http(s) URL with no fragment`);
  return url;
}

/** Requires a list of URLs with at least `min` items. */
function requireUrlList(value, where, min) {
  if (!Array.isArray(value) || value.length < min) {
    throw new ConfigError(`${where} must be a list of at least ${min} URL(s)`);
  }
  const urls = value.map((item, index) => requireUrl(item, `${where}[${index}]`));
  requireUnique(urls, where);
  return urls;
}

/** Requires a picture given as an absolute http(s) URL or an image data URL. */
function requirePicture(value, where) {
  if (typeof value === "string" && /^data:image\/[a-z+.-]+;base64,[A-Za-z0-9+/=]+$/.test(value)) return value;
  return requireUrl(value, where);
}

/** Requires that `values` has no repeated item. */
function requireUnique(values, where) {
  const position = values.findIndex((value, index) => values.indexOf(value) !== index);
  if (position >= 0) throw new ConfigError(`${where}: item ${position} repeats an earlier item`);
}
