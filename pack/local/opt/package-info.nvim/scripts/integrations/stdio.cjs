const readline = require("node:readline");
const { request } = require("../core/protocol.cjs");
/** @param {ReturnType<typeof import("../controller.cjs").createDispatcher>} dispatcher */
function serve(dispatcher) {
  readline
    .createInterface({ input: process.stdin })
    .on("line", async (line) => {
      let id;
      try {
        const message = request(line);
        id = message.id;
        await dispatcher.handle(message);
      } catch {
        send({ id, error: "Helper could not process the request" });
      }
    });
}
/** @param {import("../types").Response} value */
function send(value) {
  process.stdout.write(JSON.stringify(value) + "\n");
}
module.exports = { serve, send };
