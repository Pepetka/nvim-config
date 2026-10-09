/** @param {unknown} value @returns {value is Record<string, unknown>} */
function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
/** @param {unknown} value @returns {import("../types").Metadata} */
function metadata(value) {
  if (
    !object(value) ||
    !Array.isArray(value.versions) ||
    !value.versions.every((v) => typeof v === "string") ||
    !object(value["dist-tags"]) ||
    !Object.values(value["dist-tags"]).every((v) => typeof v === "string")
  )
    throw Object.assign(new Error("Invalid metadata"), { code: "EMETADATA" });
  return {
    versions: value.versions,
    "dist-tags": /** @type {Record<string,string>} */ (value["dist-tags"]),
  };
}
/** @param {unknown} value @param {string} name @returns {import("../types").Metadata} */
function packument(value, name) {
  if (
    !object(value) ||
    value.name !== name ||
    (!object(value.versions) && !Array.isArray(value.versions))
  )
    throw Object.assign(new Error("Invalid metadata"), { code: "EMETADATA" });
  return metadata({
    versions: Array.isArray(value.versions)
      ? value.versions
      : Object.keys(value.versions),
    "dist-tags": value["dist-tags"],
  });
}
/** @param {string} text @returns {import("../types").Metadata} */
function parseRegistry(text) {
  for (const line of [text, ...text.split("\n")]) {
    try {
      /** @type {unknown} */
      const value = JSON.parse(line);
      if (object(value)) {
        try {
          return metadata(value);
        } catch {}
        if (object(value.data)) {
          try {
            return metadata(value.data);
          } catch {}
        }
      }
    } catch {}
  }
  throw Object.assign(
    new Error("Registry command returned no version metadata"),
    { code: "EMETADATA" },
  );
}
module.exports = { object, metadata, packument, parseRegistry };
