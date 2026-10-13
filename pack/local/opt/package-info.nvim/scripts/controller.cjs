const { packument } = require("./core/metadata.cjs");
const { compare } = require("./core/versions.cjs");
const { classify } = require("./core/errors.cjs");
/** @template T @param {Promise<T>} promise @param {AbortSignal} signal @returns {Promise<T>} */
function abortable(promise, signal) {
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener("abort", abort, { once: true });
    promise.then(
      (value) => {
        signal.removeEventListener("abort", abort);
        resolve(value);
      },
      (error) => {
        signal.removeEventListener("abort", abort);
        reject(error);
      },
    );
    if (signal.aborted) {
      signal.removeEventListener("abort", abort);
      abort();
    }
  });
}
class Network {
  /** @param {import("./types").NetworkDependencies} options */
  constructor(options) {
    const { storage, now, digest } = options;
    this.policy = require("./core/settings.cjs").settings(options);
    this.storage = storage;
    this.now = now;
    this.digest = digest;
    this.globalLimit = this.policy.globalLimit;
    this.projectLimit = this.policy.projectLimit;
    this.timeout = this.policy.timeout;
    /** @type {Map<string,import("./types").CacheEntry>} */
    this.cache = new Map();
    this.active = 0;
    /** @type {Map<string,number>} */
    this.projects = new Map();
    /** @type {import("./types").NetworkTask[]} */
    this.waiting = [];
    /** @type {Map<string,import("./types").Flight>} */
    this.flights = new Map();
  }
  pump() {
    for (
      let index = 0;
      this.active < this.globalLimit && index < this.waiting.length;
    ) {
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
      this.projects.set(
        task.project,
        (this.projects.get(task.project) || 0) + 1,
      );
      task
        .run()
        .then(task.resolve, task.reject)
        .finally(() => {
          this.active--;
          this.projects.set(
            task.project,
            (this.projects.get(task.project) || 0) - 1,
          );
          this.pump();
        });
    }
  }
  /** @param {string} project @param {AbortSignal} signal @param {()=>Promise<import("./types").CacheEntry>} run @param {number} [limit] @returns {Promise<import("./types").CacheEntry>} */
  enqueue(project, signal, run, limit = this.projectLimit) {
    return new Promise((resolve, reject) => {
      this.waiting.push({ project, signal, run, resolve, reject, limit });
      this.pump();
    });
  }
  /** @param {string} key @returns {import("./types").CacheEntry | null} */
  cached(key) {
    const validate = require("./core/cache.cjs").entry;
    const entry =
      validate(this.cache.get(key), this.now(), this.policy) ||
      validate(this.storage.read(key), this.now(), this.policy);
    if (!entry) {
      this.cache.delete(key);
      return null;
    }
    this.remember(key, entry);
    return entry;
  }
  /** @param {string} key @param {import("./types").CacheEntry} entry */
  remember(key, entry) {
    this.cache.delete(key);
    this.cache.set(key, entry);
    while (this.cache.size > this.policy.memoryLimit) {
      const oldest = this.cache.keys().next().value;
      if (oldest !== undefined) this.cache.delete(oldest);
    }
  }
  /** @param {string} key @param {import("./types").CacheEntry} entry */
  store(key, entry) {
    this.remember(key, entry);
    this.storage.write(key, entry);
  }

  /** @param {import("./types").Client} client @param {string} project @param {string} name @param {AbortSignal} signal @param {boolean} [force] @returns {Promise<import("./types").CacheEntry>} */
  async lookup(client, project, name, signal, force = false) {
    let identity = client.key;
    try {
      if (client.identity) identity = client.identity(name);
    } catch {}
    // Metadata depends on the registry and credentials, not on the package directory or session.
    const key = this.digest(identity + ":" + name);
    const cached = !force && this.cached(key);
    if (cached) return { ...cached, cached: true };
    // Concurrent checks share one request; it is cancelled only when every waiting check is cancelled.
    let flight = this.flights.get(key);
    if (!flight) {
      const controller = new AbortController();
      const shared = controller.signal;
      const promise = this.enqueue(
        project,
        shared,
        async () => {
          try {
            if (!client.enabled) throw new Error("Networking disabled");
            const options = client.options(name);
            const registry = options.registry.replace(/\/$/, "");
            const url = registry + "/" + name.replace("/", "%2f");
            const deadline = AbortSignal.timeout(this.timeout);
            const response = await client.fetch.json(url, {
              ...options,
              signal: AbortSignal.any([shared, deadline]),
              timeout: this.timeout,
              cache: null,
              retry: { retries: 0 },
              fetchRetries: 0,
              headers: { accept: "application/vnd.npm.install-v1+json" },
            });
            return { time: this.now(), metadata: packument(response, name) };
          } catch (error) {
            if (shared.aborted) throw error;
            return { time: this.now(), ...classify(error) };
          }
        },
        Math.max(
          1,
          Math.min(
            this.projectLimit,
            Number(client.concurrency) || this.projectLimit,
          ),
        ),
      );
      const current = { controller, promise, users: 0 };
      flight = current;
      this.flights.set(key, current);
      promise
        .then((entry) => {
          if (!shared.aborted) this.store(key, entry);
        })
        .catch(() => {})
        .finally(() => {
          if (this.flights.get(key) === current) this.flights.delete(key);
        });
    }
    const joined = flight;
    joined.users++;
    try {
      return await abortable(joined.promise, signal);
    } finally {
      if (--joined.users === 0 && signal.aborted) {
        if (this.flights.get(key) === joined) this.flights.delete(key);
        joined.controller.abort(signal.reason);
      }
    }
  }
  /** @param {import("./types").Client} client @param {import("./types").NetworkContext} context @param {AbortSignal} signal @param {boolean} force @param {(event:import("./types").Progress)=>void} emit @returns {Promise<void>} */
  async check(client, context, signal, force, emit) {
    /** @type {Map<string,import("./types").Declaration[]>} */
    const groups = new Map();
    for (const dep of context.dependencies) {
      if (dep.target) {
        if (!groups.has(dep.target)) groups.set(dep.target, []);
        groups.get(dep.target)?.push(dep);
      }
    }
    let completed = 0;
    await Promise.all(
      [...groups].map(async ([name, declarations]) => {
        try {
          const entry = await this.lookup(
            client,
            context.root,
            name,
            signal,
            force,
          );
          if (signal.aborted) return;
          emit({
            records: declarations.map((dep) => ({
              name: dep.name,
              section: dep.section,
              result: entry.metadata
                ? compare(dep, entry.metadata, this.now(), context.manager)
                : undefined,
              error: entry.error,
              kind: entry.kind,
              age_ms: this.now() - entry.time,
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

module.exports = { Network };
/**
 * @param {{inspect:(input:import("./types").InspectInput)=>import("./types").Context,
 * compare:(dep:import("./types").Declaration,metadata:import("./types").Metadata,now:number,manager?:string)=>import("./types").Comparison,
 * prepare:(input:import("./types").ConfigureInput,signal?:AbortSignal)=>Promise<import("./types").Client|{fallback:true}>,
 * network:Network,now:()=>number,send:(response:import("./types").Response)=>void}} adapters
 */
function createDispatcher(adapters) {
  let stopped = false;
  /** @type {Map<string,{client:import("./types").Client,time:number,project:string}>} */
  const clients = new Map();
  const clientTTL = adapters.network.policy.clientTTL;
  function pruneClients() {
    for (const [key, entry] of clients) {
      if (
        adapters.now() - entry.time >= clientTTL ||
        entry.time > adapters.now()
      )
        clients.delete(key);
    }
    while (clients.size > adapters.network.policy.clientLimit) {
      const oldest = clients.keys().next().value;
      if (oldest !== undefined) clients.delete(oldest);
    }
  }
  /** @type {Map<number,AbortController>} */
  const requests = new Map();
  /** @param {import("./types").HelperRequest} request */
  async function handle(request) {
    if (stopped) return;
    if (request.method === "cancel") {
      requests.get(request.input.id)?.abort();
      adapters.network.pump();
      return;
    }
    const id = request.id;
    let result;
    if (request.method === "configure") {
      const controller = new AbortController();
      requests.set(id, controller);
      try {
        const client = await abortable(
          adapters.prepare(request.input, controller.signal),
          controller.signal,
        );
        if (stopped || controller.signal.aborted) return;
        if ("fallback" in client) result = { fallback: true };
        else {
          const project =
            request.input.context.dir ||
            request.input.context.root ||
            client.key;
          for (const [key, entry] of clients) {
            if (entry.project === project && key !== client.key)
              clients.delete(key);
          }
          clients.delete(client.key);
          clients.set(client.key, { client, time: adapters.now(), project });
          pruneClients();
          result = { client: client.key };
        }
      } catch (error) {
        if (!stopped && !controller.signal.aborted) throw error;
        return;
      } finally {
        requests.delete(id);
      }
    } else if (request.method === "check") {
      pruneClients();
      const entry = clients.get(request.input.client);
      if (!entry) {
        adapters.send({ id, result: { reconfigure: true } });
        return;
      }
      clients.delete(request.input.client);
      entry.time = adapters.now();
      clients.set(request.input.client, entry);
      const controller = new AbortController();
      requests.set(id, controller);
      try {
        await adapters.network.check(
          entry.client,
          request.input.context,
          controller.signal,
          request.input.force === true,
          (value) => {
            if (!stopped && !controller.signal.aborted)
              adapters.send({ id, result: value, done: false });
          },
        );
        if (stopped || controller.signal.aborted) return;
      } catch (error) {
        if (!stopped && !controller.signal.aborted) throw error;
        return;
      } finally {
        requests.delete(id);
      }
      result = { complete: true };
    } else if (request.method === "inspect")
      result = adapters.inspect(request.input);
    else {
      let metadata;
      try {
        metadata = require("./core/metadata.cjs").parseRegistry(
          request.input.stdout,
        );
      } catch {
        // Distinguishes invalid registry output from helper transport failures.
        if (!stopped) adapters.send({ id, result: { invalid: true } });
        return;
      }
      result = adapters.compare(
        request.input.dep,
        metadata,
        adapters.now(),
        request.input.manager,
      );
    }
    if (!stopped) adapters.send({ id, result });
  }
  function teardown() {
    stopped = true;
    for (const request of requests.values()) request.abort();
    requests.clear();
    clients.clear();
    adapters.network.pump();
  }
  return { handle, teardown };
}
module.exports.createDispatcher = createDispatcher;
