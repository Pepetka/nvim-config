const { object, metadata } = require("./metadata.cjs");
/** @param {unknown} value @param {number} now @param {Pick<import("../types").RuntimeSettings,"ttl"|"retry">} [options] @returns {import("../types").CacheEntry|null} */
function entry(value, now, options = { ttl: 900000, retry: 30000 }) {
  if (
    !object(value) ||
    typeof value.time !== "number" ||
    !Number.isFinite(value.time) ||
    value.time > now ||
    now - value.time >= (value.error ? options.retry : options.ttl)
  )
    return null;
  if (value.error !== undefined) {
    if (
      typeof value.error !== "string" ||
      !["auth", "not_found", "timeout", "metadata", "network"].includes(
        String(value.kind),
      )
    )
      return null;
    return {
      time: value.time,
      error: value.error,
      kind: /** @type {import("../types").ErrorKind} */ (value.kind),
    };
  }
  try {
    return { time: value.time, metadata: metadata(value.metadata) };
  } catch {
    return null;
  }
}
module.exports = { entry };
