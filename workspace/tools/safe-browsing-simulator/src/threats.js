import { readFileSync } from "node:fs";

/** Threat types of the Lookup API v4 that the file can list. */
export const THREAT_TYPES = ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"];

const ROOT_FIELDS = ["threats", "unavailableDomains"];
const THREAT_FIELDS = ["url", "threatType"];
const DOMAIN_FORMAT = /^(?=.{1,253}$)[a-z0-9-]+(\.[a-z0-9-]+)*$/;
const SCHEME_FORMAT = /^[a-z][a-z0-9+.-]*:(?!\d)/i; // "host.test:8443/x" is a host and a port, not a scheme

/** Error of an invalid threats file; the message names the field and what is wrong with it. */
export class ThreatsError extends Error {}

/** Reads and validates the JSON threats file at `path`; throws ThreatsError on the first problem. */
export function loadThreats(path) {
  let raw;
  try {
    raw = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new ThreatsError(`cannot read ${path}: ${error.message}`);
  }
  return parseThreats(raw);
}

/**
 * Validates a parsed threats file and returns the lookup over it: `find(url)` gives the threat types listed for `url`,
 * `isUnavailable(url)` tells whether `url` is on an out-of-service domain.
 */
export function parseThreats(raw) {
  requireObject(raw, "file", ROOT_FIELDS);
  const threats = requireArray(raw.threats, "threats").map(parseThreat);
  requireUnique(threats.map((threat) => `${threat.threatType} ${threat.url}`), "threats");
  const domains = requireArray(raw.unavailableDomains ?? [], "unavailableDomains").map(parseDomain);
  requireUnique(domains, "unavailableDomains");

  return {
    threatCount: threats.length,
    domainCount: domains.length,
    find(url) {
      const key = urlKey(url);
      if (key === null) return [];
      return [...new Set(threats.filter((threat) => matches(threat.key, key)).map((threat) => threat.threatType))];
    },
    isUnavailable(url) {
      const key = urlKey(url);
      return key !== null && domains.some((domain) => onDomain(key.host, domain));
    },
  };
}

/**
 * Splits a URL into the parts Safe Browsing compares: host, path and query, without scheme, port, credentials or
 * fragment. A URL with no scheme is read as http, as the API accepts it. Returns null for a non-http(s) or invalid URL.
 */
export function urlKey(text) {
  if (typeof text !== "string") return null;
  let value = text.trim();
  if (value.startsWith("//")) value = `http:${value}`;
  else if (!SCHEME_FORMAT.test(value)) value = `http://${value}`;
  let url;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if ((url.protocol !== "http:" && url.protocol !== "https:") || url.hostname === "") return null;
  return { host: url.hostname.replace(/\.+$/, ""), path: url.pathname, query: url.search };
}

/**
 * Whether the listed `entry` covers the asked `key`, like the host suffix and path prefix expressions of Safe
 * Browsing: the host or one of its parent domains, then the path itself, or any path below it when the listed path
 * ends in "/". A listed query must be equal; a listed URL with no query covers any query.
 */
function matches(entry, key) {
  if (!onDomain(key.host, entry.host)) return false;
  const pathMatches = entry.path.endsWith("/") ? key.path.startsWith(entry.path) : key.path === entry.path;
  return pathMatches && (entry.query === "" || entry.query === key.query);
}

/** Whether `host` is `domain` or a subdomain of it. */
function onDomain(host, domain) {
  return host === domain || host.endsWith(`.${domain}`);
}

/** Validates one entry of `threats`. */
function parseThreat(raw, index) {
  const where = `threats[${index}]`;
  requireObject(raw, where, THREAT_FIELDS);
  const key = typeof raw.url === "string" && SCHEME_FORMAT.test(raw.url) ? urlKey(raw.url) : null;
  if (key === null) throw new ThreatsError(`${where}.url must be an absolute http(s) URL`);
  if (!THREAT_TYPES.includes(raw.threatType)) {
    throw new ThreatsError(`${where}.threatType must be one of ${THREAT_TYPES.join(", ")}`);
  }
  return { url: `${key.host}${key.path}${key.query}`, key, threatType: raw.threatType };
}

/** Validates one entry of `unavailableDomains`: a lowercase host name with no scheme, port or path. */
function parseDomain(raw, index) {
  if (typeof raw !== "string" || !DOMAIN_FORMAT.test(raw)) {
    throw new ThreatsError(`unavailableDomains[${index}] must be a lowercase host name, like pending.app.test`);
  }
  return raw;
}

/** Requires a plain object holding only the `allowed` keys. */
function requireObject(value, where, allowed) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ThreatsError(`${where} must be an object`);
  }
  const unknown = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unknown.length > 0) throw new ThreatsError(`${where} has unknown fields: ${unknown.join(", ")}`);
}

/** Requires an array, possibly empty. */
function requireArray(value, where) {
  if (!Array.isArray(value)) throw new ThreatsError(`${where} must be a list`);
  return value;
}

/** Requires that `values` has no repeated item. */
function requireUnique(values, where) {
  const position = values.findIndex((value, index) => values.indexOf(value) !== index);
  if (position >= 0) throw new ThreatsError(`${where}: item ${position} repeats an earlier item`);
}
