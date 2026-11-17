import { createHash, generateKeyPairSync, sign, timingSafeEqual, verify } from "node:crypto";

const VERIFIER_FORMAT = /^[A-Za-z0-9._~-]{43,128}$/;

/**
 * Creates the RS256 signing key of this run. It lives only in memory: a restart rotates it, so tokens of the previous
 * run stop validating, as after a key rotation at Auth0.
 */
export function createSigner() {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const jwk = publicKey.export({ format: "jwk" });
  const kid = createHash("sha256").update(JSON.stringify({ e: jwk.e, kty: jwk.kty, n: jwk.n })).digest("base64url");
  const header = encodeJson({ alg: "RS256", typ: "JWT", kid });

  return {
    jwks: { keys: [{ kty: jwk.kty, use: "sig", alg: "RS256", kid, n: jwk.n, e: jwk.e }] },

    /** Returns `payload` as a signed compact JWT. */
    sign(payload) {
      const data = `${header}.${encodeJson(payload)}`;
      return `${data}.${sign("sha256", Buffer.from(data), privateKey).toString("base64url")}`;
    },

    /** Returns the payload of a JWT signed by this key, or null when the format, key or signature is wrong. */
    verify(token) {
      const parts = typeof token === "string" ? token.split(".") : [];
      if (parts.length !== 3) return null;
      const [headerPart, payloadPart, signature] = parts;
      const tokenHeader = decodeJson(headerPart);
      if (tokenHeader?.alg !== "RS256" || tokenHeader.kid !== kid) return null;
      const valid = verify("sha256", Buffer.from(`${headerPart}.${payloadPart}`), publicKey,
        Buffer.from(signature, "base64url"));
      return valid ? decodeJson(payloadPart) : null;
    },
  };
}

/** Checks an RFC 7636 code verifier against the challenge and method stored with the authorization code. */
export function verifyPkce(verifier, challenge, method) {
  if (typeof verifier !== "string" || !VERIFIER_FORMAT.test(verifier)) return false;
  const computed = method === "S256" ? createHash("sha256").update(verifier).digest("base64url") : verifier;
  return safeEqual(computed, challenge);
}

/** Compares two texts in constant time. */
export function safeEqual(left, right) {
  const a = Buffer.from(String(left));
  const b = Buffer.from(String(right));
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Encodes an object as base64url JSON. */
function encodeJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

/** Decodes base64url JSON; returns null when it is not a JSON object. */
function decodeJson(part) {
  try {
    const value = JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
    return value !== null && typeof value === "object" ? value : null;
  } catch {
    return null;
  }
}
