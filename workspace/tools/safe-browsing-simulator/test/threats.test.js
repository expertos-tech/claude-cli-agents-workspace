import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { loadThreats, parseThreats, ThreatsError, urlKey } from "../src/threats.js";

const SHIPPED = fileURLToPath(new URL("../config/threats.json", import.meta.url));

test("RN-2: the shipped file lists the Google test URLs, one or more per threat type", () => {
  const threats = loadThreats(SHIPPED);
  assert.deepEqual(threats.find("http://malware.testing.google.test/testing/malware/"), ["MALWARE"]);
  assert.deepEqual(threats.find("https://testsafebrowsing.appspot.com/s/malware.html"), ["MALWARE"]);
  assert.deepEqual(threats.find("https://testsafebrowsing.appspot.com/s/phishing.html"), ["SOCIAL_ENGINEERING"]);
  assert.deepEqual(threats.find("https://testsafebrowsing.appspot.com/s/unwanted.html"), ["UNWANTED_SOFTWARE"]);
  assert.deepEqual(threats.find("https://pha.safe-browsing-simulator.test/app.apk"),
    ["POTENTIALLY_HARMFUL_APPLICATION"]);
  assert.deepEqual(threats.find("https://testsafebrowsing.appspot.com/"), []);
});

test("a listed URL ending in / covers the paths below it, on the host and its subdomains", () => {
  const threats = parseThreats({ threats: [{ url: "http://evil.test/bad/", threatType: "MALWARE" }] });
  for (const url of ["https://evil.test/bad/", "EVIL.TEST:8443/bad/deeper/page?x=1#top", "http://a.b.evil.test/bad/",
    "//evil.test./bad/x"]) {
    assert.deepEqual(threats.find(url), ["MALWARE"], url);
  }
  for (const url of ["http://evil.test/bad", "http://evil.test/other/", "http://notevil.test/bad/", "http://test/bad/",
    "ftp://evil.test/bad/", "http://", 42]) {
    assert.deepEqual(threats.find(url), [], String(url));
  }
});

test("a listed URL with no trailing / is exact on the path; a listed query must be equal", () => {
  const threats = parseThreats({ threats: [
    { url: "http://site.test/page.html", threatType: "SOCIAL_ENGINEERING" },
    { url: "http://site.test/download?id=7", threatType: "UNWANTED_SOFTWARE" },
  ] });
  assert.deepEqual(threats.find("https://site.test/page.html?any=1"), ["SOCIAL_ENGINEERING"]);
  assert.deepEqual(threats.find("https://site.test/page.html/more"), []);
  assert.deepEqual(threats.find("https://site.test/download?id=7"), ["UNWANTED_SOFTWARE"]);
  assert.deepEqual(threats.find("https://site.test/download?id=8"), []);
});

test("one URL can carry more than one threat type", () => {
  const threats = parseThreats({ threats: [
    { url: "http://both.test/", threatType: "MALWARE" },
    { url: "http://both.test/", threatType: "UNWANTED_SOFTWARE" },
  ] });
  assert.deepEqual(threats.find("http://both.test/x"), ["MALWARE", "UNWANTED_SOFTWARE"]);
});

test("RN-3: out-of-service domains cover their subdomains, not their parents", () => {
  const threats = parseThreats({ threats: [], unavailableDomains: ["down.app.test"] });
  assert.equal(threats.isUnavailable("https://down.app.test/x"), true);
  assert.equal(threats.isUnavailable("api.down.app.test"), true);
  assert.equal(threats.isUnavailable("https://app.test/"), false);
  assert.equal(threats.isUnavailable("https://notdown.app.test/"), false);
  assert.equal(parseThreats({ threats: [] }).isUnavailable("https://down.app.test/"), false);
});

test("urlKey drops scheme, port, credentials and fragment", () => {
  assert.deepEqual(urlKey("https://user:pw@Host.Test:8080/a/b?q=1#f"), { host: "host.test", path: "/a/b", query: "?q=1" });
  assert.deepEqual(urlKey("host.test"), { host: "host.test", path: "/", query: "" });
  assert.equal(urlKey("mailto:a@b.test"), null);
});

test("an invalid file is refused with the field and the problem", () => {
  const cases = [
    [[], /file must be an object/],
    [{ threats: [], extra: 1 }, /unknown fields: extra/],
    [{}, /threats must be a list/],
    [{ threats: [{ url: "evil.test/", threatType: "MALWARE" }] }, /threats\[0\]\.url/],
    [{ threats: [{ url: "ftp://evil.test/", threatType: "MALWARE" }] }, /threats\[0\]\.url/],
    [{ threats: [{ url: "http://evil.test/", threatType: "VIRUS" }] }, /threats\[0\]\.threatType/],
    [{ threats: [{ url: "http://evil.test/", threatType: "MALWARE", note: "x" }] }, /unknown fields: note/],
    [{ threats: [{ url: "http://evil.test/", threatType: "MALWARE" }, { url: "HTTPS://EVIL.TEST/",
      threatType: "MALWARE" }] }, /threats: item 1 repeats/],
    [{ threats: [], unavailableDomains: ["https://down.test"] }, /unavailableDomains\[0\]/],
    [{ threats: [], unavailableDomains: ["Down.test"] }, /unavailableDomains\[0\]/],
    [{ threats: [], unavailableDomains: ["down.test", "down.test"] }, /unavailableDomains: item 1 repeats/],
  ];
  for (const [raw, message] of cases) {
    assert.throws(() => parseThreats(raw), (error) => error instanceof ThreatsError && message.test(error.message),
      JSON.stringify(raw));
  }
  assert.throws(() => loadThreats("/nonexistent/threats.json"), ThreatsError);
});
