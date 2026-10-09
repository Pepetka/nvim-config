const http = require("node:http");
const server = http.createServer((request, response) => {
  const url = new URL(request.url || "/", "http://fixture");
  const name = decodeURIComponent(
    url.pathname.replace(/^\/(?:public|private)\//, ""),
  );
  if (
    url.pathname.startsWith("/private/") &&
    request.headers.authorization !== "Bearer FIXTURE_TOKEN"
  ) {
    response.writeHead(401);
    response.end(JSON.stringify({ error: "SYNTHETIC_SECRET" }));
    return;
  }
  if (name.includes("missing")) {
    response.writeHead(404);
    response.end(JSON.stringify({ error: "SYNTHETIC_SECRET" }));
    return;
  }
  if (name.includes("auth_error")) {
    response.writeHead(403);
    response.end(JSON.stringify({ error: "SYNTHETIC_SECRET" }));
    return;
  }
  const metadata = {
    name,
    versions: { "1.0.0": {}, "1.2.0": {}, "2.0.0": {} },
    "dist-tags": { latest: "2.0.0" },
  };
  setTimeout(
    () => {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify(metadata));
    },
    name.includes("slow") ? 300 : 30,
  );
});
server.listen(0, "127.0.0.1", () =>
  process.stdout.write(
    "http://127.0.0.1:" +
      (() => {
        const address = server.address();
        if (!address || typeof address === "string")
          throw new Error("Invalid fixture address");
        return address.port;
      })() +
      "\n",
  ),
);
process.on("SIGTERM", () => server.close(() => process.exit(0)));
