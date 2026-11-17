import { createServer } from "node:http";
import { createApp } from "./app.js";
import { loadThreats, ThreatsError } from "./threats.js";

/** Starts the simulator: reads THREATS_PATH (default /config/threats.json) and listens on PORT (default 8080). */
function main() {
  const threatsPath = process.env.THREATS_PATH || "/config/threats.json";
  const port = Number(process.env.PORT || "8080");
  if (!Number.isInteger(port) || port < 1 || port > 65535) fail(`PORT must be a TCP port, got "${process.env.PORT}"`);

  let threats;
  try {
    threats = loadThreats(threatsPath);
  } catch (error) {
    if (error instanceof ThreatsError) fail(`invalid threats file: ${error.message}`);
    throw error;
  }

  const log = (event) => console.log(JSON.stringify(event));
  const server = createServer(createApp({ threats, log }));
  server.requestTimeout = 10_000;
  server.headersTimeout = 5_000;
  server.listen(port, () => {
    log({ event: "started", port, threats: threats.threatCount, unavailableDomains: threats.domainCount });
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
