import { createServer } from "node:http";
import { createApp } from "./app.js";
import { ConfigError, loadConfig, parseOrigin } from "./config.js";
import { createSigner } from "./tokens.js";

/**
 * Starts the simulator: reads CONFIG_PATH (default /config/config.json) and listens on PORT (default 8080).
 * AVATAR_ORIGIN, when set, is the origin of the generated avatars; unset, the issuer's origin.
 */
function main() {
  const configPath = process.env.CONFIG_PATH || "/config/config.json";
  const port = Number(process.env.PORT || "8080");
  if (!Number.isInteger(port) || port < 1 || port > 65535) fail(`PORT must be a TCP port, got "${process.env.PORT}"`);

  let config;
  let avatarOrigin;
  try {
    config = loadConfig(configPath);
    avatarOrigin = process.env.AVATAR_ORIGIN ? parseOrigin(process.env.AVATAR_ORIGIN, "AVATAR_ORIGIN") : undefined;
  } catch (error) {
    if (error instanceof ConfigError) fail(`invalid configuration: ${error.message}`);
    throw error;
  }

  const server = createServer(createApp({ config, signer: createSigner(), avatarOrigin }));
  server.requestTimeout = 10_000;
  server.headersTimeout = 5_000;
  server.listen(port, () => {
    console.log(JSON.stringify({ event: "started", port, issuer: config.issuer, avatarOrigin: avatarOrigin ?? null,
      applications: config.applications.length, users: config.users.length }));
  });
  const stop = () => server.close(() => process.exit(0));
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
}

/** Prints the startup problem and exits with status 1. */
function fail(message) {
  console.error(JSON.stringify({ event: "startup_failed", message }));
  process.exit(1);
}

main();
