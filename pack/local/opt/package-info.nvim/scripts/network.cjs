const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const picomatch = require("picomatch");
const core = require("./core.cjs");
const TTL = 15 * 60 * 1000;
const BACKOFF = 30000;
function digest(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
function decode(text, fallback = {}) {
  if (!text || text.trim() === "undefined") return fallback;
  return JSON.parse(text);
}
function npmLibraries(executable) {
  const root = path.dirname(path.dirname(fs.realpathSync(executable)));
  const load = (name) => require(path.join(root, "node_modules", name));
  return { root, load, fetch: load("npm-registry-fetch") };
}
function optionsFromNpm(config) {
  const options = { ...config };
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
    if (config[key]) options[field] = fs.readFileSync(config[key], "utf8");
  }
  if (config["network-concurrency"] !== undefined) options.maxSockets = config["network-concurrency"];
  return options;
}
function modernOptions(config, name) {
  const scope = name.startsWith("@") ? name.slice(1).split("/")[0] : null;
  const scoped = config.npmScopes?.[scope] || (scope === "jsr" ? { npmRegistryServer: "https://npm.jsr.io" } : {});
  const registry = (scoped.npmRegistryServer || config.npmRegistryServer).replace(/\/$/, "");
  const destination = new URL(registry);
  if (
    destination.protocol === "http:" &&
    !(config.unsafeHttpWhitelist || []).some((pattern) => picomatch(pattern)(destination.hostname))
  ) {
    throw new Error("Yarn requires HTTPS for this registry");
  }
  const registryConfig = config.npmRegistries?.[registry] || config.npmRegistries?.[registry.replace(/^[a-z]+:/, "")];
  const auth = scoped.npmAuthToken || scoped.npmAuthIdent ? scoped : registryConfig || config;
  const mustAuth = Boolean(scope || auth.npmAlwaysAuth);
  const options = {
    registry,
    strictSSL: config.enableStrictSsl,
    proxy: config.httpProxy,
    httpsProxy: config.httpsProxy,
    forceAuth: {},
    maxSockets: Math.min(config.networkConcurrency ?? 50, 16),
  };
  if (mustAuth && auth.npmAuthToken) options.forceAuth.token = auth.npmAuthToken;
  else if (mustAuth && auth.npmAuthIdent)
    options.forceAuth.auth = auth.npmAuthIdent.includes(":")
      ? Buffer.from(auth.npmAuthIdent).toString("base64")
      : auth.npmAuthIdent;
  else if (mustAuth && auth.npmAlwaysAuth && !scope)
    throw Object.assign(new Error("Authentication required"), { code: "EAUTH" });
  for (const [key, field] of [
    ["httpsCaFilePath", "ca"],
    ["httpsCertFilePath", "cert"],
    ["httpsKeyFilePath", "key"],
  ]) {
    if (config[key]) options[field] = fs.readFileSync(config[key], "utf8");
  }
  return options;
}
async function prepare(input) {
  const libs = npmLibraries(input.npm_path);
  const context = input.context;
  let config;
  if (context.manager === "npm") {
    const Config = libs.load("@npmcli/config");
    const definitions = libs.load("@npmcli/config/lib/definitions");
    const native = new Config({
      ...definitions,
      npmPath: libs.root,
      cwd: context.dir,
      env: input.environment || process.env,
      argv: [process.execPath, input.npm_path],
      warn: false,
    });
    await native.load();
    config = { ...Object.assign({}, ...native.list.slice().reverse()), ...native.flat };
  } else if (context.manager === "yarn" && context.major === 1) {
    const inspections = (input.exports.config || "").split("\n").flatMap((line) => {
      try {
        const value = JSON.parse(line);
        return value.type === "inspect" ? [value.data] : [];
      } catch {
        return [];
      }
    });
    if (inspections.length !== 2) throw new Error("Incomplete Yarn configuration");
    config = { ...inspections[1], ...inspections[0] };
    // A scoped npm registry takes precedence over the Yarn default registry.
  } else if (context.manager === "pnpm") {
    config = decode(input.exports.config);
    if (!config.registry) throw new Error("Incomplete pnpm configuration");
  } else {
    config = {};
    for (const line of (input.exports.config || "").split("\n")) {
      try {
        const value = JSON.parse(line);
        if (value.key && value.effective !== undefined) config[value.key] = value.effective;
      } catch {}
    }
    for (const name of ["npmAuthToken", "npmAuthIdent", "npmScopes", "npmRegistries", "networkSettings"]) {
      config[name] = decode(input.exports[name], name.endsWith("Token") || name.endsWith("Ident") ? null : {});
    }
    if (!config.npmRegistryServer) throw new Error("Incomplete Yarn configuration");
    if (Object.keys(config.networkSettings || {}).length || config.enableOfflineMode || context.custom_plugins)
      return { fallback: true };
  }
  if (context.custom_plugins) return { fallback: true };
  // A range/lockfile edit changes the comparison, not the package metadata or credentials.
  const fingerprint = digest((context.registry_fingerprint || context.fingerprint) + JSON.stringify(config));
  return {
    fetch: libs.fetch,
    key: fingerprint,
    options: (name) => {
      if (context.manager === "yarn" && context.major > 1) return modernOptions(config, name);
      const options = optionsFromNpm(config);
      const scope = name.startsWith("@") ? name.split("/")[0] : "";
      options.registry = config[scope + ":registry"] || config.registry;
      if (!options.registry) throw new Error("Registry is unavailable");
      return options;
    },
    enabled: config.enableNetwork !== false && config.offline !== true,
    concurrency:
      context.manager === "yarn" && context.major > 1 ? config.networkConcurrency : config["network-concurrency"],
  };
}
function classify(error) {
  const code = error.code || "";
  if (code === "E401" || code === "E403" || code === "EAUTH")
    return { kind: "auth", error: "Registry authentication failed" };
  if (code === "E404") return { kind: "not_found", error: "Package not found or access denied by the registry" };
  if (error.name === "AbortError" || error.name === "TimeoutError" || /TIMEOUT|TIMEDOUT/.test(code))
    return { kind: "timeout", error: "Registry request timed out" };
  if (code === "EMETADATA") return { kind: "metadata", error: "Registry returned invalid metadata" };
  return { kind: "network", error: "Registry request failed; check network and manager configuration" };
}
class Network {
  constructor({ cacheDir, globalLimit = 32, projectLimit = 16, timeout = 15000 } = {}) {
    this.cacheDir = cacheDir;
    this.globalLimit = globalLimit;
    this.projectLimit = projectLimit;
    this.timeout = timeout;
    this.cache = new Map();
    this.active = 0;
    this.projects = new Map();
    this.waiting = [];
  }
  pump() {
    for (let index = 0; this.active < this.globalLimit && index < this.waiting.length;) {
      const task = this.waiting[index];
      if (task.signal.aborted) {
        this.waiting.splice(index, 1);
        task.reject(task.signal.reason);
        continue;
      }
      if ((this.projects.get(task.project) || 0) >= task.limit) {
        index++;
        continue;
      }
      this.waiting.splice(index, 1);
      this.active++;
      this.projects.set(task.project, (this.projects.get(task.project) || 0) + 1);
      task
        .run()
        .then(task.resolve, task.reject)
        .finally(() => {
          this.active--;
          this.projects.set(task.project, this.projects.get(task.project) - 1);
          this.pump();
        });
    }
  }
  enqueue(project, signal, run, limit = this.projectLimit) {
    return new Promise((resolve, reject) => {
      this.waiting.push({ project, signal, run, resolve, reject, limit });
      this.pump();
    });
  }
  cached(key) {
    let entry = this.cache.get(key);
    if (!entry && this.cacheDir) {
      try {
        entry = JSON.parse(fs.readFileSync(path.join(this.cacheDir, key + ".json"), "utf8"));
      } catch {}
    }
    if (
      !entry ||
      !Number.isFinite(entry.time) ||
      Date.now() - entry.time >= (entry.error ? BACKOFF : TTL) ||
      entry.time > Date.now()
    )
      return null;
    if (
      !entry.error &&
      (!Array.isArray(entry.metadata?.versions) ||
        !entry.metadata["dist-tags"] ||
        typeof entry.metadata["dist-tags"] !== "object" ||
        Array.isArray(entry.metadata["dist-tags"]))
    )
      return null;
    this.cache.set(key, entry);
    return entry;
  }
  store(key, entry) {
    this.cache.set(key, entry);
    if (this.cache.size > 2000) this.cache.delete(this.cache.keys().next().value);
    if (!this.cacheDir || !entry.metadata) return;
    try {
      fs.mkdirSync(this.cacheDir, { recursive: true, mode: 0o700 });
      const file = path.join(this.cacheDir, key + ".json");
      const temp = file + "." + process.pid + ".tmp";
      fs.writeFileSync(temp, JSON.stringify(entry), { mode: 0o600 });
      fs.renameSync(temp, file);
    } catch {
      /* A read-only cache must not prevent registry checks. */
    }
  }
  async lookup(client, project, name, signal, force = false) {
    const key = digest(client.key + ":" + name);
    const cached = !force && this.cached(key);
    if (cached) return { ...cached, cached: true };
    // Share only within one check; cancellation of one buffer cannot abort another check's request.
    const entry = await this.enqueue(
      project,
      signal,
      async () => {
        try {
          if (!client.enabled) throw new Error("Networking disabled");
          const options = client.options(name);
          const registry = options.registry.replace(/\/$/, "");
          const url = registry + "/" + name.replace("/", "%2f");
          const deadline = AbortSignal.timeout(this.timeout);
          const response = await client.fetch.json(url, {
            ...options,
            signal: AbortSignal.any([signal, deadline]),
            timeout: this.timeout,
            cache: null,
            retry: { retries: 0 },
            fetchRetries: 0,
            headers: { accept: "application/vnd.npm.install-v1+json" },
          });
          if (
            !response ||
            response.name !== name ||
            !response.versions ||
            typeof response.versions !== "object" ||
            !response["dist-tags"] ||
            typeof response["dist-tags"] !== "object" ||
            Array.isArray(response["dist-tags"])
          )
            throw Object.assign(new Error("Invalid metadata"), { code: "EMETADATA" });
          const versions = Array.isArray(response.versions) ? response.versions : Object.keys(response.versions);
          return { time: Date.now(), metadata: { versions, "dist-tags": response["dist-tags"] } };
        } catch (error) {
          if (signal.aborted) throw error;
          return { time: Date.now(), ...classify(error) };
        }
      },
      Math.max(1, Math.min(this.projectLimit, Number(client.concurrency) || this.projectLimit)),
    );
    if (!signal.aborted) this.store(key, entry);
    return entry;
  }
  async check(client, context, signal, force, emit) {
    const groups = new Map();
    for (const dep of context.dependencies) {
      if (dep.target) {
        if (!groups.has(dep.target)) groups.set(dep.target, []);
        groups.get(dep.target).push(dep);
      }
    }
    let completed = 0;
    await Promise.all(
      [...groups].map(async ([name, declarations]) => {
        try {
          const entry = await this.lookup(client, context.root, name, signal, force);
          if (signal.aborted) return;
          emit({
            records: declarations.map((dep) => ({
              name: dep.name,
              section: dep.section,
              result: entry.metadata ? core.compare(dep, entry.metadata) : undefined,
              error: entry.error,
              kind: entry.kind,
              age_ms: Date.now() - entry.time,
              cached: Boolean(entry.cached),
            })),
            completed: ++completed,
            total: groups.size,
          });
        } catch (error) {
          if (!signal.aborted) throw error;
        }
      }),
    );
  }
}
module.exports = { prepare, Network, classify, modernOptions, optionsFromNpm, digest };
