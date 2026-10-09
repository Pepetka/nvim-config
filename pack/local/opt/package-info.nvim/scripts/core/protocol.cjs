const { object } = require("./metadata.cjs");
/** @param {unknown} value @returns {boolean} */
function strings(value) {
  // Neovim encodes an empty Lua table as []; preserve the existing wire format for empty maps.
  return (
    (Array.isArray(value) && value.length === 0) ||
    (object(value) &&
      Object.values(value).every(
        (item) => typeof item === "string" || item === undefined,
      ))
  );
}
/** @param {unknown} value @returns {boolean} */
function installed(value) {
  return (
    object(value) &&
    (value.state === undefined ||
      (typeof value.state === "string" &&
        ["installed", "unknown", "not_applicable"].includes(value.state))) &&
    ["version", "reason"].every(
      (key) => value[key] === undefined || typeof value[key] === "string",
    )
  );
}
/** @param {unknown} value @returns {boolean} */
function declaration(value) {
  return (
    object(value) &&
    typeof value.name === "string" &&
    typeof value.spec === "string" &&
    typeof value.kind === "string" &&
    ["range", "tag", "local", "unsupported"].includes(value.kind) &&
    ["target", "range", "reason", "section"].every(
      (key) => value[key] === undefined || typeof value[key] === "string",
    ) &&
    (value.installed === undefined || installed(value.installed)) &&
    (!["range", "tag"].includes(value.kind) ||
      (typeof value.target === "string" && typeof value.range === "string"))
  );
}
/** @param {unknown} value @returns {boolean} */
function context(value) {
  return (
    object(value) &&
    ["dir", "root", "fingerprint", "registry_fingerprint"].every(
      (key) => typeof value[key] === "string",
    ) &&
    ["pnp", "custom_plugins", "overrides"].every(
      (key) => typeof value[key] === "boolean",
    ) &&
    (value.manager === undefined ||
      (typeof value.manager === "string" &&
        ["npm", "yarn", "pnpm"].includes(value.manager))) &&
    Array.isArray(value.dependencies) &&
    value.dependencies.every(
      (dep) => declaration(dep) && installed(dep.installed),
    )
  );
}
/** @param {string} line @returns {import("../types").HelperRequest} */
function request(line) {
  /** @type {unknown} */
  const value = JSON.parse(line);
  if (
    !object(value) ||
    !object(value.input) ||
    typeof value.method !== "string"
  )
    throw new Error("Invalid request");
  if (
    value.method !== "cancel" &&
    (!Number.isSafeInteger(value.id) || Number(value.id) <= 0)
  )
    throw new Error("Invalid id");
  const input = value.input;
  if (
    (value.method === "inspect" &&
      typeof input.path === "string" &&
      typeof input.manifest === "string" &&
      (input.managers === undefined || strings(input.managers)) &&
      ["override", "environment_hash", "user_config"].every(
        (key) => input[key] === undefined || typeof input[key] === "string",
      )) ||
    (value.method === "compare" &&
      declaration(input.dep) &&
      typeof input.stdout === "string") ||
    (value.method === "configure" &&
      object(input.context) &&
      strings(input.exports) &&
      typeof input.npm_path === "string" &&
      (input.environment === undefined || strings(input.environment))) ||
    (value.method === "check" &&
      typeof input.client === "string" &&
      context(input.context) &&
      (input.force === undefined || typeof input.force === "boolean")) ||
    (value.method === "cancel" &&
      Number.isSafeInteger(input.id) &&
      Number(input.id) > 0)
  ) {
    return /** @type {import("../types").HelperRequest} */ (
      /** @type {unknown} */ (value)
    );
  }
  throw new Error("Invalid method input");
}
/** @param {string} text @returns {{dir:string,root:string,dependencies:Pick<import("../types").Declaration,"name"|"target">[]}} */
function pnp(text) {
  /** @type {unknown} */
  const value = JSON.parse(text);
  if (
    !object(value) ||
    typeof value.dir !== "string" ||
    typeof value.root !== "string" ||
    !Array.isArray(value.dependencies) ||
    !value.dependencies.every(
      (dep) =>
        object(dep) &&
        typeof dep.name === "string" &&
        (dep.target === undefined || typeof dep.target === "string"),
    )
  )
    throw new Error("Invalid PnP request");
  return /** @type {{dir:string,root:string,dependencies:Pick<import("../types").Declaration,"name"|"target">[]}} */ (
    value
  );
}
module.exports = { request, pnp };
