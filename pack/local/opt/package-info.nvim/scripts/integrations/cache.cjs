const fs = require("node:fs");
const path = require("node:path");
const { entry: validate } = require("../core/cache.cjs");
/** @param {string|undefined} directory @param {()=>number} [now] @param {import("../types").NetworkOptions} [options] */
function storage(directory, now = Date.now, options = {}) {
  const policy = require("../core/settings.cjs").settings(options);
  if (!policy.disk || policy.diskLimit === 0) directory = undefined;
  let lastCleanup = -Infinity;
  /** @param {string} file */
  function remove(file) {
    try {
      fs.unlinkSync(file);
    } catch {}
  }
  function prune() {
    if (
      !directory ||
      (now() - lastCleanup >= 0 && now() - lastCleanup < policy.cleanupInterval)
    )
      return;
    lastCleanup = now();
    try {
      /** @type {{file:string,time:number}[]} */
      const retained = [];
      for (const name of fs.readdirSync(directory)) {
        if (!/^[a-f0-9]{64}\.json$/.test(name)) continue;
        const file = path.join(directory, name);
        try {
          if (!fs.lstatSync(file).isFile()) continue;
          const entry = validate(
            JSON.parse(fs.readFileSync(file, "utf8")),
            now(),
            policy,
          );
          if (entry && entry.metadata)
            retained.push({ file, time: entry.time });
          else remove(file);
        } catch {
          remove(file);
        }
      }
      retained.sort((a, b) => b.time - a.time);
      for (const entry of retained.slice(policy.diskLimit)) remove(entry.file);
    } catch {}
  }
  return {
    prune,
    /** @param {string} key @returns {unknown} */
    read(key) {
      if (!directory) return undefined;
      prune();
      const file = path.join(directory, key + ".json");
      try {
        const entry = validate(
          JSON.parse(fs.readFileSync(file, "utf8")),
          now(),
          policy,
        );
        if (entry && entry.metadata) return entry;
        remove(file);
        return undefined;
      } catch {
        remove(file);
        return undefined;
      }
    },
    /** @param {string} key @param {import("../types").CacheEntry} entry */
    write(key, entry) {
      if (!directory || !entry.metadata) return;
      const file = path.join(directory, key + ".json");
      const temp = file + "." + process.pid + ".tmp";
      try {
        fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
        fs.writeFileSync(temp, JSON.stringify(entry), { mode: 0o600 });
        fs.renameSync(temp, file);
        prune();
      } catch {
        try {
          fs.unlinkSync(temp);
        } catch {}
      }
    },
  };
}
module.exports = { storage };
