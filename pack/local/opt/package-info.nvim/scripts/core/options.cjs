const picomatch = require("picomatch");
const { object } = require("./metadata.cjs");
/** @param {unknown} value @returns {import("../types").ManagerConfig} */
function configuration(value) {
  if (!object(value)) throw new Error("Invalid manager configuration");
  const result = { ...value };
  for (const key of [
    "registry",
    "npmRegistryServer",
    "npmAuthToken",
    "npmAuthIdent",
    "httpProxy",
    "httpsProxy",
  ]) {
    if (result[key] === null) delete result[key];
    if (result[key] !== undefined && typeof result[key] !== "string")
      throw new Error("Invalid manager configuration");
  }
  for (const key of [
    "npmAlwaysAuth",
    "enableStrictSsl",
    "enableOfflineMode",
    "enableNetwork",
    "offline",
  ]) {
    if (result[key] !== undefined && typeof result[key] !== "boolean")
      throw new Error("Invalid manager configuration");
  }
  for (const key of ["npmScopes", "npmRegistries"]) {
    if (result[key] === undefined) continue;
    if (!object(result[key])) throw new Error("Invalid registry configuration");
    result[key] = Object.fromEntries(
      Object.entries(result[key]).map(([name, auth]) => [
        name,
        configuration(auth),
      ]),
    );
  }
  if (result.networkSettings !== undefined && !object(result.networkSettings))
    throw new Error("Invalid network configuration");
  if (
    result.unsafeHttpWhitelist !== undefined &&
    (!Array.isArray(result.unsafeHttpWhitelist) ||
      !result.unsafeHttpWhitelist.every((item) => typeof item === "string"))
  )
    throw new Error("Invalid HTTP whitelist");
  if (
    result.networkConcurrency !== undefined &&
    (typeof result.networkConcurrency !== "number" ||
      !Number.isFinite(result.networkConcurrency) ||
      result.networkConcurrency < 1)
  )
    throw new Error("Invalid connection limit");
  return /** @type {import("../types").ManagerConfig} */ (result);
}
/** @param {import("../types").ManagerConfig} config @param {(file:string)=>string} read @returns {import("../types").FetchOptions} */
function optionsFromNpm(config, read) {
  /** @type {import("../types").FetchOptions} */
  const options = { ...config, registry: config.registry || "" };
  for (const [key, field] of Object.entries({
    "strict-ssl": "strictSSL",
    "https-proxy": "httpsProxy",
    "user-agent": "userAgent",
    "local-address": "localAddress",
    noproxy: "noProxy",
    maxsockets: "maxSockets",
  })) {
    if (config[key] !== undefined) options[field] = config[key];
  }
  for (const [key, field] of [
    ["cafile", "ca"],
    ["certfile", "cert"],
    ["keyfile", "key"],
  ]) {
    const file = config[key];
    if (typeof file === "string" && file) options[field] = read(file);
  }
  if (config["network-concurrency"] !== undefined)
    options.maxSockets = Number(config["network-concurrency"]);
  return options;
}
/** @param {import("../types").ManagerConfig} config @param {string} name @param {(file:string)=>string} read @returns {import("../types").FetchOptions & {forceAuth:{token?:string,auth?:string}}} */
function modernOptions(config, name, read) {
  const scope = name.startsWith("@") ? name.slice(1).split("/")[0] : "";
  const scoped =
    config.npmScopes?.[scope] ||
    (scope === "jsr" ? { npmRegistryServer: "https://npm.jsr.io" } : {});
  const registry = (
    scoped.npmRegistryServer ||
    config.npmRegistryServer ||
    ""
  ).replace(/\/$/, "");
  const destination = new URL(registry);
  if (
    destination.protocol === "http:" &&
    !(config.unsafeHttpWhitelist || []).some((pattern) =>
      picomatch(pattern)(destination.hostname),
    )
  ) {
    throw new Error("Yarn requires HTTPS for this registry");
  }
  const registryConfig =
    config.npmRegistries?.[registry] ||
    config.npmRegistries?.[registry.replace(/^[a-z]+:/, "")];
  const auth =
    scoped.npmAuthToken || scoped.npmAuthIdent
      ? scoped
      : registryConfig || config;
  const mustAuth = Boolean(scope || auth.npmAlwaysAuth);
  /** @type {import("../types").FetchOptions & {forceAuth:{token?:string,auth?:string}}} */
  const options = {
    registry,
    strictSSL: config.enableStrictSsl,
    proxy: config.httpProxy,
    httpsProxy: config.httpsProxy,
    forceAuth: {},
    maxSockets: Math.min(config.networkConcurrency ?? 50, 16),
  };
  if (mustAuth && auth.npmAuthToken)
    (options.forceAuth ||= {}).token = auth.npmAuthToken;
  else if (mustAuth && auth.npmAuthIdent)
    (options.forceAuth ||= {}).auth = auth.npmAuthIdent.includes(":")
      ? Buffer.from(auth.npmAuthIdent).toString("base64")
      : auth.npmAuthIdent;
  else if (mustAuth && auth.npmAlwaysAuth && !scope)
    throw Object.assign(new Error("Authentication required"), {
      code: "EAUTH",
    });
  for (const [key, field] of [
    ["httpsCaFilePath", "ca"],
    ["httpsCertFilePath", "cert"],
    ["httpsKeyFilePath", "key"],
  ]) {
    const file = config[key];
    if (typeof file === "string" && file) options[field] = read(file);
  }
  return options;
}
module.exports = { optionsFromNpm, modernOptions, configuration };
