const FIND_PATH = "/v4/threatMatches:find";
const MAX_BODY_BYTES = 1024 * 1024;
const MAX_ENTRIES = 500; // the Lookup API limit per request
const MAX_URL_LENGTH = 8192;
const CACHE_DURATION = "300s";
const REQUEST_FIELDS = ["client", "threatInfo"];
const THREAT_INFO_FIELDS = ["threatTypes", "platformTypes", "threatEntryTypes", "threatEntries"];
const ENTRY_FIELDS = ["url", "hash", "digest"];
const API_THREAT_TYPES = ["THREAT_TYPE_UNSPECIFIED", "MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE",
  "POTENTIALLY_HARMFUL_APPLICATION"];
const API_PLATFORM_TYPES = ["PLATFORM_TYPE_UNSPECIFIED", "WINDOWS", "LINUX", "ANDROID", "OSX", "IOS", "ANY_PLATFORM",
  "ALL_PLATFORMS", "CHROME"];
const API_ENTRY_TYPES = ["THREAT_ENTRY_TYPE_UNSPECIFIED", "URL", "EXECUTABLE", "IP_RANGE"];
const STATUS_NAMES = { 400: "INVALID_ARGUMENT", 404: "NOT_FOUND", 405: "METHOD_NOT_ALLOWED", 413: "INVALID_ARGUMENT",
  500: "INTERNAL", 503: "UNAVAILABLE" };
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Goog-Api-Key",
};

/** Answer of an invalid request; `handle` turns it into an error response with `status`. */
class RequestError extends Error {
  /** `status` is the HTTP status of the answer. */
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/**
 * Builds the HTTP handler of the simulator: `POST /v4/threatMatches:find` of the Lookup API v4 over the `threats`
 * lookup (see threats.js), and `GET /healthz`. The API key (`key` query or `X-Goog-Api-Key`) is never checked.
 * `log` receives one event object per lookup, with counts only: never a URL or a key.
 */
export function createApp({ threats, log = () => {} }) {
  /** Answers a lookup: 503 when an asked URL is on an out-of-service domain, else the matches. */
  function findThreatMatches(body) {
    const info = parseLookup(body);
    const urls = info.threatEntries.map((entry) => entry.url).filter((url) => url !== undefined);
    if (urls.some((url) => threats.isUnavailable(url))) {
      log({ event: "lookup", urls: urls.length, result: "unavailable" });
      return error(503, "The service is currently unavailable.");
    }
    const matches = info.threatEntryTypes.includes("URL") ? urls.flatMap((url) => matchesOf(url, info)) : [];
    log({ event: "lookup", urls: urls.length, result: matches.length > 0 ? "matches" : "safe", matches: matches.length });
    return json(200, matches.length > 0 ? { matches } : {});
  }

  /** Matches of one asked URL: one per listed threat type the request asks for, per asked platform. */
  function matchesOf(url, info) {
    return threats.find(url)
      .filter((threatType) => info.threatTypes.includes(threatType))
      .flatMap((threatType) => info.platformTypes.map((platformType) => ({
        threatType, platformType, threatEntryType: "URL", threat: { url }, cacheDuration: CACHE_DURATION,
      })));
  }

  return async function handle(request, response) {
    const path = new URL(request.url, "http://simulator").pathname;
    let answer;
    try {
      answer = await route(request, path);
    } catch (problem) {
      if (problem instanceof RequestError) {
        answer = error(problem.status, problem.message);
      } else {
        log({ event: "failed", error: problem?.name ?? "unknown" });
        answer = error(500, "Internal error of the simulator.");
      }
    }
    if (response.destroyed) return;
    response.writeHead(answer.status, { ...CORS_HEADERS, ...answer.headers });
    response.end(answer.body);
  };

  /** Picks the answer of `request` by method and path. */
  async function route(request, path) {
    if (path === "/healthz" && request.method === "GET") return json(200, { status: "ok" });
    if (path !== FIND_PATH) return error(404, `Path ${path.slice(0, 200)} is not served by this simulator.`);
    if (request.method === "OPTIONS") return { status: 204, headers: {}, body: "" };
    if (request.method !== "POST") return { ...error(405, "Only POST is allowed."), headers: jsonHeaders({ Allow: "POST" }) };
    return findThreatMatches(await readJson(request));
  }
}

/** Validates the body of a lookup and returns its `threatInfo`; throws a 400 RequestError on the first problem. */
export function parseLookup(body) {
  requireObject(body, "request", REQUEST_FIELDS);
  const info = body.threatInfo;
  requireObject(info, "threatInfo", THREAT_INFO_FIELDS);
  const entries = info.threatEntries ?? [];
  if (!Array.isArray(entries)) throw invalid("threatInfo.threatEntries must be a list.");
  if (entries.length > MAX_ENTRIES) throw invalid(`threatInfo.threatEntries holds more than ${MAX_ENTRIES} entries.`);
  entries.forEach(parseEntry);
  return {
    threatTypes: requireEnumList(info.threatTypes, "threatTypes", API_THREAT_TYPES),
    platformTypes: requireEnumList(info.platformTypes, "platformTypes", API_PLATFORM_TYPES),
    threatEntryTypes: requireEnumList(info.threatEntryTypes, "threatEntryTypes", API_ENTRY_TYPES),
    threatEntries: entries,
  };
}

/** Validates one threat entry: an object whose `url`, when present, is a text of bounded length. */
function parseEntry(entry, index) {
  requireObject(entry, `threatInfo.threatEntries[${index}]`, ENTRY_FIELDS);
  if (entry.url !== undefined && (typeof entry.url !== "string" || entry.url.length > MAX_URL_LENGTH)) {
    throw invalid(`threatInfo.threatEntries[${index}].url must be a text of at most ${MAX_URL_LENGTH} characters.`);
  }
}

/** Requires a non-empty list of values of the API enum `allowed`, as the API does for the three type lists. */
function requireEnumList(value, field, allowed) {
  if (!Array.isArray(value) || value.length === 0) throw invalid(`${field} not set in threat info section of request.`);
  const unknown = value.find((item) => !allowed.includes(item));
  if (unknown !== undefined) throw invalid(`Invalid value in threatInfo.${field}: ${String(unknown).slice(0, 50)}.`);
  return value;
}

/** Requires a plain object holding only the `allowed` keys. */
function requireObject(value, where, allowed) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw invalid(`${where} must be an object.`);
  const unknown = Object.keys(value).find((key) => !allowed.includes(key));
  if (unknown !== undefined) throw invalid(`Unknown name "${unknown.slice(0, 50)}" in ${where}.`);
}

/** Reads the request body as JSON, up to MAX_BODY_BYTES. */
async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new RequestError(413, `Request body larger than ${MAX_BODY_BYTES} bytes.`);
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw invalid("Invalid JSON payload received.");
  }
}

/** A 400 RequestError with `message`. */
function invalid(message) {
  return new RequestError(400, message);
}

/** Error answer in the format of Google APIs: `{"error": {"code", "message", "status"}}`. */
function error(status, message) {
  return json(status, { error: { code: status, message, status: STATUS_NAMES[status] } });
}

/** JSON answer with `status`. */
function json(status, value) {
  return { status, headers: jsonHeaders(), body: JSON.stringify(value) };
}

/** Headers of a JSON answer, plus `extra`. */
function jsonHeaders(extra = {}) {
  return { "Content-Type": "application/json; charset=UTF-8", "Cache-Control": "no-store", ...extra };
}
