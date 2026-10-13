const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const { object } = require("../core/metadata.cjs");
/** @param {string} value @returns {string} */
function digest(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
/** @param {string | undefined} text @param {unknown} [fallback] @returns {unknown} */
function decode(text, fallback = {}) {
  if (!text || text.trim() === "undefined") return fallback;
  return JSON.parse(text);
}
/** @type {Map<string,string>} */
const npmRoots = new Map();
/** @param {string} executable @returns {string} */
function npmRoot(executable) {
  const known = npmRoots.get(executable);
  if (known) return known;
  /** @param {string} root */
  const usable = (root) =>
    fs.existsSync(path.join(root, "node_modules", "npm-registry-fetch"));
  let root = "";
  try {
    root = path.dirname(path.dirname(fs.realpathSync(executable)));
  } catch {}
  if (!usable(root)) {
    // Version manager shims (Volta, mise, asdf) do not resolve to npm's installation directory.
    try {
      root = path.join(
        execFileSync(executable, ["root", "-g"], {
          encoding: "utf8",
          timeout: 5000,
          stdio: ["ignore", "pipe", "ignore"],
        }).trim(),
        "npm",
      );
    } catch {}
  }
  if (!usable(root)) throw new Error("npm libraries are unavailable");
  npmRoots.set(executable, root);
  return root;
}
/** @param {import("../types").FetchOptions} options @returns {string} */
function credentials(options) {
  /** @type {Record<string,unknown>} */
  const values = { registry: options.registry, forceAuth: options.forceAuth };
  for (const [key, value] of Object.entries(options)) {
    if (
      key.startsWith("//") ||
      [
        "_auth",
        "_authToken",
        "username",
        "_password",
        "ca",
        "cert",
        "key",
      ].includes(key)
    )
      values[key] = value;
  }
  return digest(JSON.stringify(Object.entries(values).sort()));
}
/** @param {string} executable @returns {import("../types").NpmLibraries} */
function npmLibraries(executable) {
  const root = npmRoot(executable);
  /** @param {string} name @returns {unknown} */
  const load = (name) => require(path.join(root, "node_modules", name));
  return {
    root,
    load,
    fetch: /** @type {import("../types").NpmLibraries["fetch"]} */ (
      load("npm-registry-fetch")
    ),
  };
}
const options = require("../core/options.cjs");
/** @param {import("../types").ManagerConfig} config @returns {import("../types").FetchOptions} */
function optionsFromNpm(config) {
  return options.optionsFromNpm(config, (file) =>
    fs.readFileSync(file, "utf8"),
  );
}
/** @param {import("../types").ManagerConfig} config @param {string} name */
function modernOptions(config, name) {
  return options.modernOptions(config, name, (file) =>
    fs.readFileSync(file, "utf8"),
  );
}
/** @param {import("../types").ConfigureInput} input @param {AbortSignal} [signal] @returns {Promise<import("../types").Client | {fallback:true}>} */
async function prepare(input, signal) {
  signal?.throwIfAborted();
  const libs = npmLibraries(input.npm_path);
  const context = input.context;
  const exports = input.exports || {};
  /** @type {import("../types").ManagerConfig} */
  let config;
  if (context.manager === "npm") {
    const Config =
      /** @type {new(options:Record<string,unknown>)=>import("../types").NativeConfig} */ (
        libs.load("@npmcli/config")
      );
    const definitions = /** @type {Record<string,unknown>} */ (
      libs.load("@npmcli/config/lib/definitions")
    );
    const native = new Config({
      ...definitions,
      npmPath: libs.root,
      cwd: context.dir,
      env: input.environment || process.env,
      argv: [process.execPath, input.npm_path],
      warn: false,
    });
    await native.load();
    signal?.throwIfAborted();
    config = {
      ...Object.assign({}, ...native.list.slice().reverse()),
      ...native.flat,
    };
  } else if (context.manager === "yarn" && context.major === 1) {
    const inspections = (exports.config || "").split("\n").flatMap((line) => {
      try {
        /** @type {unknown} */
        const value = JSON.parse(line);
        return object(value) && value.type === "inspect" && object(value.data)
          ? [value.data]
          : [];
      } catch {
        return [];
      }
    });
    if (inspections.length !== 2)
      throw new Error("Incomplete Yarn configuration");
    config = { ...inspections[1], ...inspections[0] };
    // A scoped npm registry takes precedence over the Yarn default registry.
  } else if (context.manager === "pnpm") {
    config = options.configuration(decode(exports.config));
    if (!config.registry) throw new Error("Incomplete pnpm configuration");
  } else {
    config = {};
    for (const line of (exports.config || "").split("\n")) {
      try {
        /** @type {unknown} */
        const value = JSON.parse(line);
        if (
          object(value) &&
          typeof value.key === "string" &&
          value.effective !== undefined
        )
          config[value.key] = value.effective;
      } catch {}
    }
    for (const name of [
      "npmAuthToken",
      "npmAuthIdent",
      "npmScopes",
      "npmRegistries",
      "networkSettings",
    ]) {
      config[name] = decode(
        exports[name],
        name.endsWith("Token") || name.endsWith("Ident") ? null : {},
      );
    }
    if (!config.npmRegistryServer)
      throw new Error("Incomplete Yarn configuration");
    if (
      Object.keys(config.networkSettings || {}).length ||
      config.enableOfflineMode ||
      context.custom_plugins
    )
      return { fallback: true };
  }
  config = options.configuration(config);
  if (context.custom_plugins) return { fallback: true };
  // A range/lockfile edit changes the comparison, not the package metadata or credentials.
  const fingerprint = digest(
    (context.registry_fingerprint || "") + JSON.stringify(config),
  );
  /** @param {string} name @returns {import("../types").FetchOptions} */
  const fetchOptions = (name) => {
    if (context.manager === "yarn" && (context.major || 0) > 1)
      return modernOptions(config, name);
    const options = optionsFromNpm(config);
    const scope = name.startsWith("@") ? name.split("/")[0] : "";
    const registry = config[scope + ":registry"] || config.registry;
    options.registry = typeof registry === "string" ? registry : "";
    if (!options.registry) throw new Error("Registry is unavailable");
    return options;
  };
  /** @type {Map<string,string>} */
  const identities = new Map();
  return {
    fetch: libs.fetch,
    key: fingerprint,
    options: fetchOptions,
    identity: (/** @type {string} */ name) => {
      const scope = name.startsWith("@") ? name.split("/")[0] : "";
      let value = identities.get(scope);
      if (value === undefined) {
        value = credentials(fetchOptions(name));
        identities.set(scope, value);
      }
      return value;
    },
    enabled: config.enableNetwork !== false && config.offline !== true,
    concurrency:
      context.manager === "yarn" && (context.major || 0) > 1
        ? config.networkConcurrency
        : config["network-concurrency"],
  };
}

module.exports = { prepare, modernOptions, optionsFromNpm, digest };
