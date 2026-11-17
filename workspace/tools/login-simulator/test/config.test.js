import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { ConfigError, loadConfig, parseConfig, parseOrigin } from "../src/config.js";

const VALID = {
  issuer: "http://localhost:28080/",
  applications: [{ name: "App", clientId: "app", callbackUrls: ["http://localhost:4200/auth"] }],
  users: [{ id: "local|ana", givenName: "Ana", familyName: "Test", email: "ana@app.test" }],
};

/** VALID with `change` applied to a deep copy. */
function variant(change) {
  const copy = structuredClone(VALID);
  change(copy);
  return copy;
}

test("the shipped config file loads", () => {
  const config = loadConfig(fileURLToPath(new URL("../config/config.json", import.meta.url)));
  assert.equal(config.issuer, "http://localhost:28080/");
  assert.ok(config.users.some((user) => user.id === "local|ana"));
});

test("the shipped example config has an admin client and its users: MFA, social login, unverified e-mail", () => {
  const config = loadConfig(fileURLToPath(new URL("../config/config.json", import.meta.url)));
  const hub = config.applications.find((app) => app.clientId === "example-admin-web");
  assert.deepEqual(hub.callbackUrls, ["http://localhost:4500/callback"]);
  assert.deepEqual(hub.logoutUrls, ["http://localhost:4500/"]);
  assert.equal(hub.clientSecret, null);

  const hubUsers = config.users.filter((user) => user.email.endsWith("@example-admin.local"));
  const admins = hubUsers.filter((user) => user.permissions.includes("hub:admin"));
  assert.deepEqual(admins.map((user) => user.amr), [["mfa"], null]);
  const social = hubUsers.find((user) => user.id.startsWith("google-oauth2|"));
  assert.match(social.picture, /^http:\/\/172\.31\.250\.10:8080\/avatars\//);
  const sameEmail = hubUsers.filter((user) => user.email === social.email);
  assert.deepEqual(sameEmail.map((user) => user.id.split("|")[0]).sort(), ["auth0", "google-oauth2"]);
  assert.equal(hubUsers.filter((user) => !user.emailVerified).length, 1);
  assert.equal(config.users.filter((user) => !user.email.endsWith("@example-admin.local"))
    .every((user) => user.emailVerified && user.amr === null), true);
});

test("defaults: no roles, no permissions, e-mail verified, no amr, no secret, roles claim 'roles', normalized URLs", () => {
  const config = parseConfig(variant((copy) => { copy.applications[0].logoutUrls = ["http://localhost:4200"]; }));
  assert.deepEqual(config.users[0].roles, []);
  assert.deepEqual(config.users[0].permissions, []);
  assert.equal(config.users[0].emailVerified, true);
  assert.equal(config.users[0].amr, null);
  assert.equal(config.applications[0].clientSecret, null);
  assert.equal(config.applications[0].rolesClaim, "roles");
  assert.deepEqual(config.applications[0].logoutUrls, ["http://localhost:4200/"]);
});

for (const [label, change] of [
  ["an unknown field", (copy) => { copy.users[0].password = "x"; }],
  ["no users", (copy) => { copy.users = []; }],
  ["a repeated client id", (copy) => { copy.applications.push({ ...copy.applications[0] }); }],
  ["a callback with a fragment", (copy) => { copy.applications[0].callbackUrls = ["http://localhost/a#b"]; }],
  ["a non-http callback", (copy) => { copy.applications[0].callbackUrls = ["javascript:alert(1)"]; }],
  ["no callback", (copy) => { copy.applications[0].callbackUrls = []; }],
  ["a bad e-mail", (copy) => { copy.users[0].email = "ana"; }],
  ["a picture that is no URL", (copy) => { copy.users[0].picture = "ana.svg"; }],
  ["an empty name", (copy) => { copy.users[0].givenName = " "; }],
  ["a role that is no text", (copy) => { copy.users[0].roles = [1]; }],
  ["an emailVerified that is no boolean (hub RN-5)", (copy) => { copy.users[0].emailVerified = "false"; }],
  ["an amr that is no list (hub RN-5)", (copy) => { copy.users[0].amr = "mfa"; }],
  ["an amr item that is no text (hub RN-5)", (copy) => { copy.users[0].amr = [true]; }],
]) {
  test(`refuses ${label}`, () => assert.throws(() => parseConfig(variant(change)), ConfigError));
}

test("a repeated value is reported by position, without the value", () => {
  const config = variant((copy) => { copy.users.push({ ...copy.users[0] }); });
  assert.throws(() => parseConfig(config), (error) => error.message.includes("users[].id: item 1")
    && !error.message.includes("local|ana"));
});

test("one e-mail under two ids is accepted: the same person through two providers (hub RN-4)", () => {
  const config = parseConfig(variant((copy) => {
    copy.users.push({ ...copy.users[0], id: "google-oauth2|1", emailVerified: false, amr: ["mfa"] });
  }));
  assert.deepEqual(config.users.map((user) => user.email), ["ana@app.test", "ana@app.test"]);
  assert.equal(config.users[1].emailVerified, false);
  assert.deepEqual(config.users[1].amr, ["mfa"]);
});

test("a data URL picture is accepted", () => {
  const config = parseConfig(variant((copy) => { copy.users[0].picture = "data:image/png;base64,iVBORw0KGgo="; }));
  assert.match(config.users[0].picture, /^data:image\/png/);
});

test("the avatar origin is an http(s) origin, returned without the trailing slash", () => {
  assert.equal(parseOrigin("http://172.31.250.10:8080", "AVATAR_ORIGIN"), "http://172.31.250.10:8080");
  assert.equal(parseOrigin("https://login.test/", "AVATAR_ORIGIN"), "https://login.test");
  for (const value of ["http://login.test/avatars", "http://login.test?x=1", "ftp://login.test", "login.test",
    "http://user:pw@login.test", "http://login.test/#x", 8080]) {
    assert.throws(() => parseOrigin(value, "AVATAR_ORIGIN"), /AVATAR_ORIGIN must be an http\(s\) origin/);
  }
});

test("an unreadable file is a ConfigError", () => {
  assert.throws(() => loadConfig("/nonexistent/config.json"), ConfigError);
});
