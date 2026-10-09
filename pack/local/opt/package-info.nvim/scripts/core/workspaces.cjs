const path = require("node:path");
const picomatch = require("picomatch");
const yaml = require("yaml");
const { object } = require("./metadata.cjs");
/** @param {import("../types").Manifest} manifest @param {string} [file] @returns {string[]} */
function workspacePatterns(manifest, file = "") {
  const ws = manifest.workspaces;
  let patterns = Array.isArray(ws) ? ws : ws?.packages || [];
  if (file) {
    try {
      /** @type {unknown} */
      const value = yaml.parse(file);
      if (object(value) && Array.isArray(value.packages))
        patterns = value.packages.filter((item) => typeof item === "string");
    } catch {
      return [];
    }
  }
  return Array.isArray(patterns)
    ? patterns.filter((p) => typeof p === "string")
    : [];
}
/** @param {string} dir @param {string} child @param {import("../types").Manifest} manifest @param {string} [file] @returns {boolean} */
function member(dir, child, manifest, file = "") {
  const relative = path.relative(dir, child).split(path.sep).join("/");
  const patterns = workspacePatterns(manifest, file);
  const positive = patterns.filter((p) => !p.startsWith("!"));
  const negative = patterns
    .filter((p) => p.startsWith("!"))
    .map((p) => p.slice(1));
  return (
    !!relative &&
    positive.some((p) => picomatch(p)(relative)) &&
    !negative.some((p) => picomatch(p)(relative))
  );
}

module.exports = { workspacePatterns, member };
