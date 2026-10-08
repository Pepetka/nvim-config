const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { Network, prepare, modernOptions, digest } = require("../scripts/network.cjs");
const core = require("../scripts/core.cjs");
const metadata = (name) => ({
  name,
  versions: { "1.0.0": {}, "1.2.0": {}, "2.0.0": {} },
  "dist-tags": { latest: "2.0.0" },
});
const dependency = (name) => ({
  ...core.specification(name, "^1"),
  section: "dependencies",
  installed: { version: "1.0.0" },
});
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "package-info-network-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function client(json, key = "client") {
  return { key, enabled: true, options: () => ({ registry: "https://registry.example.test" }), fetch: { json } };
}
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
test("checks stream results, deduplicate aliases, and limit 32 global / 16 per project requests", async () => {
  const network = new Network();
  let active = 0,
    peak = 0,
    calls = 0;
  const projects = new Map();
  function mock(project) {
    return client(async (url) => {
      calls++;
      active++;
      peak = Math.max(peak, active);
      projects.set(project, (projects.get(project) || 0) + 1);
      assert.ok(active <= 32);
      assert.ok(projects.get(project) <= 16);
      await delay(10);
      active--;
      projects.set(project, projects.get(project) - 1);
      return metadata(url.split("/").at(-1));
    }, project);
  }
  const a = { root: "a", dependencies: Array.from({ length: 20 }, (_, i) => dependency("p" + i)) };
  a.dependencies.push({ ...dependency("alias"), target: "p0", section: "devDependencies" });
  const b = { root: "b", dependencies: Array.from({ length: 20 }, (_, i) => dependency("q" + i)) };
  const events = [];
  await Promise.all([
    network.check(mock("a"), a, new AbortController().signal, false, (event) => events.push(event)),
    network.check(mock("b"), b, new AbortController().signal, false, (event) => events.push(event)),
  ]);
  assert.equal(calls, 40);
  assert.equal(peak, 32);
  assert.equal(events.length, 40);
  assert.equal(
    events.reduce((sum, event) => sum + event.records.length, 0),
    41,
  );
  assert.equal(events[0].completed, 1);
  assert.ok(events.some((e) => e.records[0].result.wanted === "1.2.0"));
});
test("lower manager concurrency is respected by the shared HTTP queue", async () => {
  const network = new Network();
  let active = 0,
    peak = 0;
  const c = client(async (url) => {
    active++;
    peak = Math.max(peak, active);
    await delay(5);
    active--;
    return metadata(url.split("/").at(-1));
  });
  c.concurrency = 2;
  await network.check(
    c,
    { root: "p", dependencies: Array.from({ length: 10 }, (_, i) => dependency("p" + i)) },
    new AbortController().signal,
    false,
    () => {},
  );
  assert.equal(peak, 2);
});
test("persistent cache survives a new helper; forced refresh and credential/config changes bypass it", async (t) => {
  const dir = fixture(t);
  let calls = 0;
  const c = client(async (url) => {
    calls++;
    return metadata(url.split("/").at(-1));
  });
  const signal = new AbortController().signal;
  await new Network({ cacheDir: dir }).lookup(c, "p", "example", signal);
  const restarted = new Network({ cacheDir: dir });
  assert.equal((await restarted.lookup(c, "p", "example", signal)).cached, true);
  assert.equal(calls, 1);
  await restarted.lookup(c, "p", "example", signal, true);
  assert.equal(calls, 2);
  await restarted.lookup({ ...c, key: "changed-auth-context" }, "p", "example", signal);
  assert.equal(calls, 3);
  for (const file of fs.readdirSync(dir)) {
    const text = fs.readFileSync(path.join(dir, file), "utf8");
    assert.ok(!text.includes("registry.example.test"));
    assert.ok(!text.includes("authorization"));
  }
});
test("expired and corrupted cache entries do not invent version information", async (t) => {
  const dir = fixture(t);
  let calls = 0;
  const c = client(async () => {
    calls++;
    return metadata("example");
  });
  const key = digest(c.key + ":example");
  fs.writeFileSync(
    path.join(dir, key + ".json"),
    JSON.stringify({
      time: Date.now() - 16 * 60 * 1000,
      metadata: { versions: ["9.0.0"], "dist-tags": { latest: "9.0.0" } },
    }),
  );
  const signal = new AbortController().signal;
  await new Network({ cacheDir: dir }).lookup(c, "p", "example", signal);
  assert.equal(calls, 1);
  fs.writeFileSync(path.join(dir, key + ".json"), "{bad JSON");
  await new Network({ cacheDir: dir }).lookup(c, "p", "example", signal);
  assert.equal(calls, 2);
});
test("auth and not-found errors keep partial results, back off, and never disclose raw errors", async () => {
  let calls = 0;
  const network = new Network();
  const c = client(async (url) => {
    calls++;
    const name = url.split("/").at(-1);
    if (name === "private") throw Object.assign(new Error("SECRET bearer credentials"), { code: "E401" });
    if (name === "missing") throw Object.assign(new Error("SECRET private registry URL"), { code: "E404" });
    return metadata(name);
  });
  const context = { root: "p", dependencies: [dependency("good"), dependency("private"), dependency("missing")] };
  const events = [];
  await network.check(c, context, new AbortController().signal, false, (event) => events.push(event));
  assert.equal(events.length, 3);
  assert.ok(events.some((e) => e.records[0].result));
  assert.ok(events.some((e) => e.records[0].kind === "auth"));
  assert.ok(events.some((e) => e.records[0].kind === "not_found"));
  assert.ok(!JSON.stringify(events).includes("SECRET"));
  await network.check(c, context, new AbortController().signal, false, () => {});
  assert.equal(calls, 3);
  await network.check(c, context, new AbortController().signal, true, () => {});
  assert.equal(calls, 6);
});
test("timeouts and cancellation release slots and never cache cancelled responses", async () => {
  const network = new Network({ timeout: 20, globalLimit: 1, projectLimit: 1 });
  let calls = 0;
  const c = client(
    (url, options) =>
      new Promise((resolve, reject) => {
        calls++;
        if (url.endsWith("good")) {
          resolve(metadata("good"));
          return;
        }
        options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true });
      }),
  );
  const keepAlive = setInterval(() => {}, 1000);
  try {
    const result = await network.lookup(c, "p", "slow", new AbortController().signal);
    assert.equal(result.kind, "timeout");
    const controller = new AbortController();
    const events = [];
    const check = network.check(
      c,
      { root: "p", dependencies: [dependency("cancelled"), dependency("queued")] },
      controller.signal,
      false,
      (event) => events.push(event),
    );
    await delay(2);
    controller.abort();
    network.pump();
    await check;
    assert.equal(events.length, 0);
    assert.equal(network.cached(digest(c.key + ":cancelled")), null);
    await network.lookup(c, "p", "good", new AbortController().signal);
    assert.equal(calls, 3);
  } finally {
    clearInterval(keepAlive);
  }
});
test("cancelling one check cannot abort another buffer checking the same package", async () => {
  const network = new Network({ globalLimit: 1, projectLimit: 1 });
  const started = Promise.withResolvers();
  let calls = 0;
  const c = client((url, options) => {
    calls++;
    if (calls > 1) return Promise.resolve(metadata("example"));
    return new Promise((resolve, reject) => {
      options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true });
      started.resolve();
    });
  });
  const controller = new AbortController();
  const cancelled = [],
    kept = [];
  const context = { root: "shared-workspace", dependencies: [dependency("example")] };
  const first = network.check(c, context, controller.signal, false, (event) => cancelled.push(event));
  const second = network.check(c, context, new AbortController().signal, false, (event) => kept.push(event));
  await started.promise;
  controller.abort();
  network.pump();
  await Promise.all([first, second]);
  assert.equal(cancelled.length, 0);
  assert.equal(kept.length, 1);
  assert.equal(kept[0].records[0].result.wanted, "1.2.0");
  assert.equal(calls, 2);
  assert.equal((await network.lookup(c, context.root, "example", new AbortController().signal)).cached, true);
  assert.equal(calls, 2);
});
test("an unusable cache directory cannot prevent results or the in-memory cache", async (t) => {
  const dir = fixture(t);
  const cacheDir = path.join(dir, "regular-file");
  fs.writeFileSync(cacheDir, "not a directory");
  let calls = 0;
  const c = client(async () => {
    calls++;
    return metadata("example");
  });
  const network = new Network({ cacheDir });
  const signal = new AbortController().signal;
  const entry = await network.lookup(c, "p", "example", signal);
  assert.equal(core.compare(dependency("example"), entry.metadata).wanted, "1.2.0");
  assert.equal((await network.lookup(c, "p", "example", signal)).cached, true);
  assert.equal(calls, 1);
  assert.equal(fs.readFileSync(cacheDir, "utf8"), "not a directory");
});
test("disabled networking reads persistent metadata and never fetches uncached or forced requests", async (t) => {
  const cacheDir = fixture(t);
  let calls = 0;
  const c = client(async () => {
    calls++;
    return metadata("example");
  });
  const signal = new AbortController().signal;
  await new Network({ cacheDir }).lookup(c, "p", "example", signal);
  const offline = new Network({ cacheDir });
  const disabled = { ...c, enabled: false };
  assert.equal((await offline.lookup(disabled, "p", "example", signal)).cached, true);
  for (const [name, force] of [
    ["uncached", false],
    ["example", true],
  ]) {
    const entry = await offline.lookup(disabled, "p", name, signal, force);
    assert.equal(entry.metadata, undefined);
    assert.ok(entry.error);
  }
  assert.equal(calls, 1);
});
test("invalid registry metadata preserves valid packages and is never persisted as versions", async (t) => {
  const cacheDir = fixture(t);
  const network = new Network({ cacheDir });
  const c = client(async (url) => {
    const name = url.split("/").at(-1);
    if (name === "wrong-name") return metadata("unrelated");
    if (name === "wrong-tags") return { ...metadata(name), "dist-tags": [] };
    if (name === "wrong-versions") return { ...metadata(name), versions: "SECRET malformed metadata" };
    return metadata(name);
  });
  const names = ["good", "wrong-name", "wrong-tags", "wrong-versions"];
  const records = [];
  await network.check(
    c,
    { root: "p", dependencies: names.map(dependency) },
    new AbortController().signal,
    false,
    (event) => records.push(...event.records),
  );
  assert.equal(records.length, names.length);
  assert.equal(records.find((record) => record.name === "good").result.wanted, "1.2.0");
  for (const record of records.filter((record) => record.name !== "good")) {
    assert.equal(record.result, undefined);
    assert.equal(record.kind, "metadata");
  }
  assert.ok(!JSON.stringify(records).includes("SECRET"));
  assert.equal(fs.readdirSync(cacheDir).length, 1);
});
test("Yarn routing preserves scope registries, auth precedence, Basic auth and unscoped auth policy", () => {
  const config = {
    npmRegistryServer: "https://public.test",
    enableStrictSsl: true,
    npmAuthToken: "GLOBAL",
    npmScopes: {
      private: { npmRegistryServer: "https://private.test/npm/", npmAuthToken: "SCOPED" },
      basic: { npmRegistryServer: "https://basic.test", npmAuthIdent: "user:password" },
      registry: { npmRegistryServer: "https://private.test/npm" },
    },
    npmRegistries: { "//private.test/npm": { npmAuthToken: "REGISTRY" } },
  };
  assert.equal(modernOptions(config, "@private/package").registry, "https://private.test/npm");
  assert.equal(modernOptions(config, "@private/package").forceAuth.token, "SCOPED");
  assert.equal(modernOptions(config, "@registry/package").forceAuth.token, "REGISTRY");
  assert.equal(modernOptions(config, "@other/package").forceAuth.token, "GLOBAL");
  assert.deepEqual(modernOptions(config, "public").forceAuth, {});
  assert.equal(modernOptions(config, "@basic/package").forceAuth.auth, Buffer.from("user:password").toString("base64"));
  const insecure = { ...config, npmRegistryServer: "http://registry.example.test" };
  assert.throws(() => modernOptions(insecure, "public"), /HTTPS/);
  assert.equal(
    modernOptions({ ...insecure, unsafeHttpWhitelist: ["*.example.test"] }, "public").registry,
    "http://registry.example.test",
  );
});
test("native npm configuration reads project and scoped auth without touching manifests", async (t) => {
  const dir = fixture(t);
  const npm = spawnSync("which", ["npm"], { encoding: "utf8" }).stdout.trim();
  fs.writeFileSync(path.join(dir, "package.json"), '{"name":"fixture"}');
  fs.writeFileSync(
    path.join(dir, ".npmrc"),
    "registry=https://public.test/\n@private:registry=https://private.test/npm/\n//private.test/npm/:_authToken=SYNTHETIC_TOKEN\n",
  );
  const native = await prepare({
    npm_path: npm,
    context: { manager: "npm", dir, fingerprint: "fixture" },
    environment: {
      HOME: dir,
      NPM_CONFIG_GLOBALCONFIG: path.join(dir, "globalrc"),
      NPM_CONFIG_USERCONFIG: path.join(dir, "userrc"),
    },
  });
  const options = native.options("@private/package");
  assert.equal(options.registry, "https://private.test/npm/");
  assert.equal(options["//private.test/npm/:_authToken"], "SYNTHETIC_TOKEN");
  assert.equal(fs.readFileSync(path.join(dir, "package.json"), "utf8"), '{"name":"fixture"}');
});
test("native configuration export adapters preserve credentials and fall back for custom Yarn hooks", async () => {
  const npm = spawnSync("which", ["npm"], { encoding: "utf8" }).stdout.trim();
  const modern = {
    config: JSON.stringify({ key: "npmRegistryServer", effective: "https://public.test" }),
    npmScopes: JSON.stringify({ private: { npmRegistryServer: "https://private.test", npmAuthToken: "TOKEN" } }),
    npmRegistries: "undefined\n",
    npmAuthToken: "null",
    npmAuthIdent: "null",
    networkSettings: "undefined\n",
  };
  const c = await prepare({
    npm_path: npm,
    context: { manager: "yarn", major: 4, fingerprint: "context" },
    exports: modern,
  });
  assert.equal(c.options("@private/pkg").forceAuth.token, "TOKEN");
  assert.ok(!c.key.includes("TOKEN"));
  assert.deepEqual(
    await prepare({ npm_path: npm, context: { manager: "yarn", major: 4, custom_plugins: true }, exports: modern }),
    { fallback: true },
  );
  const classic = await prepare({
    npm_path: npm,
    context: { manager: "yarn", major: 1, fingerprint: "context" },
    exports: {
      config:
        JSON.stringify({ type: "inspect", data: { registry: "https://yarn.test" } }) +
        "\n" +
        JSON.stringify({
          type: "inspect",
          data: { "@private:registry": "https://private.test", "//private.test/:_authToken": "TOKEN" },
        }),
    },
  });
  assert.equal(classic.options("@private/pkg").registry, "https://private.test");
  assert.equal(classic.options("example").registry, "https://yarn.test");
  const pnpm = await prepare({
    npm_path: npm,
    context: { manager: "pnpm", fingerprint: "context" },
    exports: { config: JSON.stringify({ registry: "https://pnpm.test", "@private:registry": "https://private.test" }) },
  });
  assert.equal(pnpm.options("@private/pkg").registry, "https://private.test");
});
