import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { after, before, test } from "node:test";
import { createApp } from "../src/app.js";
import { loadThreats } from "../src/threats.js";

const GOOGLE_MALWARE = "https://malware.testing.google.test/testing/malware/";
const SAFE = "https://example.test/page";

let server;
let origin;
const events = [];

before(async () => {
  const threats = loadThreats(fileURLToPath(new URL("../config/threats.json", import.meta.url)));
  server = createServer(createApp({ threats, log: (event) => events.push(event) }));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  origin = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

/** Lookup body as an application sends it, for `urls`. */
function lookupBody(urls, overrides = {}) {
  return {
    client: { clientId: "test", clientVersion: "1.0" },
    threatInfo: {
      threatTypes: ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE"],
      platformTypes: ["ANY_PLATFORM"],
      threatEntryTypes: ["URL"],
      threatEntries: urls.map((url) => ({ url })),
      ...overrides,
    },
  };
}

/** POSTs `body` (an object, or a raw text) to the find path with any API key. */
async function find(body, key = "any-value") {
  const response = await fetch(`${origin}/v4/threatMatches:find?key=${key}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  return { status: response.status, body: await response.json(), headers: response.headers };
}

test("AC-1: the Google malware test URL comes back as MALWARE in the v4 format", async () => {
  const { status, body, headers } = await find(lookupBody([GOOGLE_MALWARE]));
  assert.equal(status, 200);
  assert.match(headers.get("content-type"), /^application\/json/);
  assert.deepEqual(body, { matches: [{ threatType: "MALWARE", platformType: "ANY_PLATFORM", threatEntryType: "URL",
    threat: { url: GOOGLE_MALWARE }, cacheDuration: "300s" }] });
});

test("AC-1: each listed threat type of the shipped file is found", async () => {
  const urls = ["http://testsafebrowsing.appspot.com/s/phishing.html", "testsafebrowsing.appspot.com/s/unwanted.html",
    "https://pha.safe-browsing-simulator.test/app.apk"];
  const { body } = await find(lookupBody(urls, { threatTypes: ["SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE",
    "POTENTIALLY_HARMFUL_APPLICATION"] }));
  assert.deepEqual(body.matches.map((match) => [match.threat.url, match.threatType]), [
    [urls[0], "SOCIAL_ENGINEERING"], [urls[1], "UNWANTED_SOFTWARE"], [urls[2], "POTENTIALLY_HARMFUL_APPLICATION"]]);
});

test("AC-2: a mixed lookup returns only the dangerous URL; an all-safe lookup returns {}", async () => {
  const mixed = await find(lookupBody([SAFE, GOOGLE_MALWARE, "http://another.test/"]));
  assert.deepEqual(mixed.body.matches.map((match) => match.threat.url), [GOOGLE_MALWARE]);

  const safe = await find(lookupBody([SAFE, "http://another.test/"]));
  assert.equal(safe.status, 200);
  assert.deepEqual(safe.body, {});
});

test("AC-3: a URL of an out-of-service domain makes the whole lookup 503", async () => {
  for (const url of ["https://pending.example.test/x", "http://a.unavailable.safe-browsing-simulator.test/"]) {
    const { status, body } = await find(lookupBody([GOOGLE_MALWARE, url]));
    assert.equal(status, 503, url);
    assert.equal(body.error.status, "UNAVAILABLE");
  }
  const parent = await find(lookupBody(["https://example.test/"]));
  assert.equal(parent.status, 200, "the parent domain of an out-of-service domain stays up");
});

test("RN-1: the key is never checked, missing or not", async () => {
  assert.equal((await find(lookupBody([GOOGLE_MALWARE]), "")).status, 200);
  const response = await fetch(`${origin}/v4/threatMatches:find`, { method: "POST",
    body: JSON.stringify(lookupBody([GOOGLE_MALWARE])) });
  assert.equal(response.status, 200);
});

test("a match comes back only for the asked threat types, entry type and per asked platform", async () => {
  const otherType = await find(lookupBody([GOOGLE_MALWARE], { threatTypes: ["SOCIAL_ENGINEERING"] }));
  assert.deepEqual(otherType.body, {});

  const executable = await find(lookupBody([GOOGLE_MALWARE], { threatEntryTypes: ["EXECUTABLE"] }));
  assert.deepEqual(executable.body, {});

  const platforms = await find(lookupBody([GOOGLE_MALWARE], { platformTypes: ["WINDOWS", "LINUX"] }));
  assert.deepEqual(platforms.body.matches.map((match) => match.platformType), ["WINDOWS", "LINUX"]);
});

test("an invalid lookup gets 400 in the Google error format", async () => {
  const cases = [
    "not json",
    { threatInfo: [] },
    { extra: 1, threatInfo: lookupBody([]).threatInfo },
    lookupBody([GOOGLE_MALWARE], { threatEntryTypes: [] }),
    lookupBody([GOOGLE_MALWARE], { threatTypes: ["VIRUS"] }),
    lookupBody([GOOGLE_MALWARE], { threatEntries: [{ url: 42 }] }),
    lookupBody(Array.from({ length: 501 }, (_, index) => `http://site${index}.test/`)),
  ];
  for (const body of cases) {
    const response = await find(body);
    assert.equal(response.status, 400, JSON.stringify(body).slice(0, 80));
    assert.equal(response.body.error.status, "INVALID_ARGUMENT");
  }
});

test("other paths and methods, preflight and health", async () => {
  assert.equal((await fetch(`${origin}/v5/urls:search`)).status, 404);
  const get = await fetch(`${origin}/v4/threatMatches:find`);
  assert.equal(get.status, 405);
  assert.equal(get.headers.get("allow"), "POST");
  const preflight = await fetch(`${origin}/v4/threatMatches:find`, { method: "OPTIONS" });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get("access-control-allow-origin"), "*");
  assert.deepEqual(await (await fetch(`${origin}/healthz`)).json(), { status: "ok" });
});

test("the log carries counts only, never a URL or the key", async () => {
  events.length = 0;
  await find(lookupBody([GOOGLE_MALWARE, SAFE]), "secret-looking-key");
  assert.deepEqual(events, [{ event: "lookup", urls: 2, result: "matches", matches: 1 }]);
});
