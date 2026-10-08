const readline = require("node:readline");
const core = require("./core.cjs");
const network = require("./network.cjs");

if (process.argv[2] === "--pnp") {
  const input = JSON.parse(process.argv[3]);
  const result = input.dependencies.map((dep) => core.installed(dep, input.dir, input.root, true));
  process.stdout.write(JSON.stringify(result));
} else {
  const clients = new Map();
  const requests = new Map();
  const checks = new network.Network({ cacheDir: require("node:path").join(__dirname, "metadata") });
  const send = (value) => process.stdout.write(JSON.stringify(value) + "\n");
  readline.createInterface({ input: process.stdin }).on("line", async (line) => {
    let request;
    try {
      request = JSON.parse(line);
      let result;
      if (request.method === "cancel") {
        requests.get(request.input.id)?.abort();
        checks.pump();
        return;
      }
      if (request.method === "configure") {
        const client = await network.prepare(request.input);
        if (client.fallback) result = { fallback: true };
        else {
          clients.set(client.key, client);
          result = { client: client.key };
        }
      } else if (request.method === "check") {
        const client = clients.get(request.input.client);
        if (!client) throw new Error("Registry client is unavailable");
        const controller = new AbortController();
        requests.set(request.id, controller);
        try {
          await checks.check(client, request.input.context, controller.signal, request.input.force, (value) =>
            send({ id: request.id, result: value, done: false }),
          );
        } finally {
          requests.delete(request.id);
        }
        result = { complete: true };
      } else if (request.method === "inspect") result = core.inspect(request.input);
      else if (request.method === "compare")
        result = core.compare(request.input.dep, core.parseRegistry(request.input.stdout));
      else throw new Error("Unknown helper method");
      send({ id: request.id, result });
    } catch {
      process.stdout.write(JSON.stringify({ id: request?.id, error: "Helper could not process the request" }) + "\n");
    }
  });
}
