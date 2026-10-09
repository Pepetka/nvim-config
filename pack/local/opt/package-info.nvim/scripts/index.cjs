const filesystem = require("./integrations/filesystem.cjs");
if (process.argv[2] === "--pnp") {
  const input = require("./core/protocol.cjs").pnp(process.argv[3]);
  process.stdout.write(
    JSON.stringify(
      input.dependencies.map((dep) =>
        filesystem.installed(dep, input.dir, input.root, true),
      ),
    ),
  );
} else {
  const settings = require("./core/settings.cjs").settings(
    process.argv[2] === "--options" ? JSON.parse(process.argv[3]) : {},
  );
  const { createDispatcher } = require("./controller.cjs");
  const stdio = require("./integrations/stdio.cjs");
  stdio.serve(
    createDispatcher({
      inspect: filesystem.inspect,
      compare: require("./core/versions.cjs").compare,
      prepare: require("./integrations/managers.cjs").prepare,
      network: new (require("./integrations/network.cjs").Network)({
        ...settings,
        cacheDir: require("node:path").join(__dirname, "metadata"),
      }),
      now: Date.now,
      send: stdio.send,
    }),
  );
}
