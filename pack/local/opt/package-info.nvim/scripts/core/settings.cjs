const { object } = require("./metadata.cjs");
/** @param {unknown} [value] @returns {import("../types").RuntimeSettings} */
function settings(value = {}) {
  if (!object(value)) throw new Error("Invalid runtime options");
  const defaults = {
    globalLimit: 32,
    projectLimit: 16,
    timeout: 15000,
    ttl: 900000,
    retry: 30000,
    memoryLimit: 2000,
    disk: true,
    diskLimit: 2000,
    cleanupInterval: 60000,
    clientTTL: 900000,
    clientLimit: 128,
  };
  for (const key of Object.keys(defaults)) {
    const option = value[key];
    if (option === undefined) continue;
    if (key === "disk") {
      if (typeof option !== "boolean") throw new Error("Invalid disk option");
    } else {
      const zero = [
        "ttl",
        "retry",
        "memoryLimit",
        "diskLimit",
        "cleanupInterval",
      ].includes(key);
      if (
        typeof option !== "number" ||
        !Number.isSafeInteger(option) ||
        option < (zero ? 0 : 1) ||
        option > 2147483647
      )
        throw new Error("Invalid runtime limit");
    }
  }
  return /** @type {import("../types").RuntimeSettings} */ ({
    ...defaults,
    ...Object.fromEntries(
      Object.keys(defaults)
        .filter((key) => value[key] !== undefined)
        .map((key) => [key, value[key]]),
    ),
  });
}
module.exports = { settings };
