/** @template T @param {T} value @returns {NonNullable<T>} */
function required(value) {
  assert.ok(value !== undefined && value !== null);
  return value;
}
const { test } = require("node:test");
test("runtime policy validates startup options and keeps omitted defaults", () => {
  const { settings } = require("../scripts/core/settings.cjs");
  assert.equal(
    settings({ timeout: 42, disk: false, memoryLimit: 0 }).timeout,
    42,
  );
  assert.equal(settings({ timeout: 42 }).globalLimit, 32);
  for (const value of [
    null,
    [],
    { globalLimit: 0 },
    { timeout: NaN },
    { ttl: -1 },
    { disk: "false" },
    { clientTTL: 0 },
  ])
    assert.throws(() => settings(value));
});
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const core = {
  ...require("../scripts/integrations/filesystem.cjs"),
  ...require("../scripts/core/versions.cjs"),
  ...require("../scripts/core/metadata.cjs"),
};
const metadata = {
  versions: ["1.0.0", "1.2.0", "1.3.0-beta.1", "2.0.0", "3.0.0-beta.1"],
  "dist-tags": { latest: "2.0.0", next: "3.0.0-beta.1" },
};
/** @param {string} spec @param {string} [version] @returns {import("../scripts/types").Declaration} */
function dep(spec, version) {
  return {
    ...core.specification("example", spec),
    installed: version ? { version, state: "installed" } : { state: "unknown" },
  };
}
/** @param {import("node:test").TestContext} t */
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "package-info-test-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  /** @param {string} file @param {unknown} value */
  function write(file, value) {
    fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
    fs.writeFileSync(
      path.join(root, file),
      typeof value === "string" ? value : JSON.stringify(value),
    );
  }
  /** @param {string} file @param {string} [override] */
  function inspect(file, override) {
    return core.inspect({
      path: path.join(root, file),
      manifest: fs.readFileSync(path.join(root, file), "utf8"),
      override,
    });
  }
  return { root, write, inspect };
}
test("wanted respects ranges, tags, prereleases; latest is a tag, not the largest version", () => {
  assert.equal(core.compare(dep("^1.0.0", "1.0.0"), metadata).wanted, "1.2.0");
  assert.equal(core.compare(dep("^1.0.0", "1.0.0"), metadata).status, "update");
  assert.equal(core.compare(dep("^1.0.0", "1.2.0"), metadata).status, "major");
  assert.equal(
    core.compare(dep("next", "2.0.0"), metadata).wanted,
    "3.0.0-beta.1",
  );
  assert.equal(
    core.compare(dep("^1.3.0-beta.0", "1.3.0-beta.1"), metadata).status,
    "current",
  );
  assert.equal(core.compare(dep("*", "3.0.0"), metadata).status, "current");
  assert.equal(
    core.compare(dep("next", "3.0.0-beta.1"), metadata).status,
    "current",
  );
  assert.equal(core.compare(dep("^1.0.0"), metadata).status, "unknown");
  assert.equal(core.compare(dep("^9"), metadata).status, "unavailable");
});
test("aliases, local protocols and unsupported specs are classified explicitly", () => {
  const alias = core.specification("compat", "npm:@scope/pkg@^1");
  assert.equal(alias.target, "@scope/pkg");
  assert.equal(alias.range, "^1");
  assert.equal(core.specification("compat", "npm:example").range, "*");
  for (const spec of [
    "workspace:*",
    "file:../lib",
    "link:../lib",
    "portal:../lib",
  ])
    assert.equal(core.specification("x", spec).kind, "local");
  for (const spec of [
    "catalog:",
    "patch:example@npm:1#x",
    "https://example.com/x.tgz",
    "user/repo",
    "git+ssh://x",
  ])
    assert.equal(core.specification("x", spec).kind, "unsupported");
});
test("registry adapters decode JSON and NDJSON without interpreting warnings as metadata", () => {
  assert.deepEqual(core.parseRegistry(JSON.stringify(metadata)), metadata);
  assert.deepEqual(
    core.parseRegistry(
      JSON.stringify({ type: "warning", data: "fallback" }) +
        "\n" +
        JSON.stringify({ type: "inspect", data: metadata }) +
        "\n" +
        JSON.stringify({ type: "finished", data: 12 }),
    ),
    metadata,
  );
  assert.deepEqual(
    core.parseRegistry("warning\n" + JSON.stringify(metadata)),
    metadata,
  );
  assert.throws(() =>
    core.parseRegistry('{"type":"warning","data":"no match"}'),
  );
});
test("workspace membership, exclusions, hoisting, aliases and section identities", (t) => {
  const f = fixture(t);
  f.write("package.json", {
    packageManager: "yarn@4.18.0",
    workspaces: { packages: ["packages/*", "!packages/excluded"] },
  });
  f.write("yarn.lock", "lock");
  f.write("node_modules/example/package.json", {
    name: "example",
    version: "1.2.0",
  });
  f.write("node_modules/compat/package.json", {
    name: "@scope/pkg",
    version: "2.0.0",
  });
  f.write("packages/a/package.json", {
    dependencies: { example: "^1", compat: "npm:@scope/pkg@^2" },
    devDependencies: { example: "^2" },
    peerDependencies: { missing: "*" },
  });
  f.write("packages/b/package.json", { dependencies: { example: "^2" } });
  f.write("packages/b/node_modules/example/package.json", {
    name: "example",
    version: "2.0.0",
  });
  let c = f.inspect("packages/a/package.json");
  assert.equal(c.root, f.root);
  assert.equal(c.manager, "yarn");
  assert.equal(c.expected_major, 4);
  assert.equal(c.dependencies[0].installed.version, "1.2.0");
  assert.equal(c.dependencies[1].installed.version, "2.0.0");
  assert.equal(c.dependencies[2].section, "devDependencies");
  assert.equal(c.dependencies[3].installed.state, "unknown");
  assert.equal(
    f.inspect("packages/b/package.json").dependencies[0].installed.version,
    "2.0.0",
  );
  f.write("packages/excluded/package.json", { dependencies: { example: "*" } });
  c = f.inspect("packages/excluded/package.json");
  assert.equal(c.root, path.join(f.root, "packages/excluded"));
  assert.equal(c.manager, "npm");
  assert.equal(c.dependencies[0].installed.state, "unknown");
});
test("pnpm yaml workspaces and conflicting locks require explicit choice", (t) => {
  const f = fixture(t);
  f.write("package.json", {});
  f.write("pnpm-workspace.yaml", 'packages:\n  - "packages/*"\n');
  f.write("packages/a/package.json", {});
  assert.equal(f.inspect("packages/a/package.json").manager, "pnpm");
  f.write("yarn.lock", "lock");
  assert.match(
    required(f.inspect("packages/a/package.json").error),
    /Conflicting/,
  );
  assert.equal(f.inspect("packages/a/package.json", "yarn@4").manager, "yarn");
  f.write("packages/a/package.json", { packageManager: "npm@11.19.0" });
  assert.equal(f.inspect("packages/a/package.json").manager, "npm");
});
test("independent nested projects do not inherit an unrelated parent manager or install", (t) => {
  const f = fixture(t);
  f.write("package.json", { packageManager: "yarn@4.0.0" });
  f.write("nested/package.json", { dependencies: { example: "*" } });
  f.write("node_modules/example/package.json", {
    name: "example",
    version: "2.0.0",
  });
  const c = f.inspect("nested/package.json");
  assert.equal(c.manager, "npm");
  assert.equal(c.root, path.join(f.root, "nested"));
  assert.equal(c.dependencies[0].installed.state, "unknown");
});
test("installed symlinks are followed and unrelated names rejected", (t) => {
  const f = fixture(t);
  f.write("package.json", { dependencies: { compat: "npm:example@*" } });
  f.write("store/package.json", { name: "example", version: "2.0.0" });
  fs.mkdirSync(path.join(f.root, "node_modules"));
  fs.symlinkSync("../store", path.join(f.root, "node_modules/compat"));
  assert.equal(
    f.inspect("package.json").dependencies[0].installed.version,
    "2.0.0",
  );
  f.write("store/package.json", { name: "other", version: "2.0.0" });
  assert.equal(
    f.inspect("package.json").dependencies[0].installed.state,
    "unknown",
  );
});
test("config and lock changes invalidate fingerprints without revealing credentials", (t) => {
  const f = fixture(t);
  f.write("package.json", {});
  f.write(".npmrc", "//registry.example/:_authToken=SECRET");
  const first = f.inspect("package.json");
  assert.ok(!JSON.stringify(first).includes("SECRET"));
  f.write(".npmrc", "//registry.example/:_authToken=OTHER");
  assert.notEqual(f.inspect("package.json").fingerprint, first.fingerprint);
  const second = f.inspect("package.json");
  assert.notEqual(second.registry_fingerprint, first.registry_fingerprint);
  f.write("package-lock.json", "{}");
  assert.notEqual(f.inspect("package.json").fingerprint, second.fingerprint);
  assert.equal(
    f.inspect("package.json").registry_fingerprint,
    second.registry_fingerprint,
  );
  f.write("package.json", { dependencies: { example: "^2" } });
  assert.equal(
    f.inspect("package.json").registry_fingerprint,
    second.registry_fingerprint,
  );
});
test("PnP uses the issuer package API and reports actual versions", (t) => {
  const f = fixture(t);
  f.write("package.json", { dependencies: { example: "^1" } });
  f.write("store/example/package.json", { name: "example", version: "1.2.0" });
  f.write(
    ".pnp.cjs",
    `require('node:module').findPnpApi = issuer => ({ resolveToUnqualified: name => { if(name !== 'example') throw new Error('missing'); return ${JSON.stringify(path.join(f.root, "store/example"))}; } });`,
  );
  const input = f.inspect("package.json");
  assert.equal(input.pnp, true);
  assert.equal(input.dependencies[0].installed.state, "unknown");
  const result = spawnSync(
    process.execPath,
    [
      "--require",
      path.join(f.root, ".pnp.cjs"),
      path.resolve(__dirname, "../scripts/index.cjs"),
      "--pnp",
      JSON.stringify(input),
    ],
    { env: process.env, encoding: "utf8" },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout)[0].version, "1.2.0");
  const symbolic = path.join(f.root, "linked");
  fs.symlinkSync(f.root, symbolic);
  const nativeModule =
    /** @type {{findPnpApi?:(issuer:string)=>{resolveToUnqualified(name:string):string}}} */ (
      /** @type {unknown} */ (require("node:module"))
    );
  const original_api = nativeModule.findPnpApi;
  nativeModule.findPnpApi = (issuer) => {
    assert.equal(issuer, path.join(fs.realpathSync(f.root), "package.json"));
    return { resolveToUnqualified: () => path.join(f.root, "store/example") };
  };
  t.after(() => {
    nativeModule.findPnpApi = original_api;
  });
  assert.equal(
    core.installed(input.dependencies[0], symbolic, symbolic, true).version,
    "1.2.0",
  );
});
test("NDJSON helper handles several requests and malformed messages without crashing", () => {
  const input =
    [
      {
        id: 1,
        method: "compare",
        input: { dep: dep("^1", "1.0.0"), stdout: JSON.stringify(metadata) },
      },
      { id: 2, method: "bad" },
      {
        id: 3,
        method: "compare",
        input: { dep: dep("next"), stdout: JSON.stringify(metadata) },
      },
    ]
      .map((value) => JSON.stringify(value))
      .join("\n") + "\n";
  const result = spawnSync(
    process.execPath,
    [path.resolve(__dirname, "../scripts/index.cjs")],
    {
      input,
      encoding: "utf8",
    },
  );
  assert.equal(result.status, 0);
  const responses = result.stdout
    .trim()
    .split("\n")
    .map((value) => JSON.parse(value));
  assert.equal(responses.length, 3);
  assert.equal(responses[0].result.status, "update");
  assert.ok(responses[1].error);
  assert.equal(responses[2].id, 3);
});
test("CLI metadata rejects malformed tag maps and version types consistently", () => {
  for (const metadata of [
    { versions: ["1.0.0"], "dist-tags": [] },
    { versions: [null], "dist-tags": {} },
    { versions: ["1.0.0"], "dist-tags": { latest: 1 } },
  ]) {
    assert.throws(() => core.parseRegistry(JSON.stringify(metadata)));
  }
});
test("manager selection and cache validation are pure and reject stale malformed records", () => {
  const { selectManager } = require("../scripts/core/context.cjs");
  const { entry } = require("../scripts/core/cache.cjs");
  assert.equal(
    selectManager("yarn@4", "npm@11", ["npm", "pnpm"]).manager,
    "yarn",
  );
  assert.equal(
    selectManager(undefined, undefined, ["npm", "pnpm"]).error,
    "Conflicting lockfiles: set a package manager override",
  );
  assert.equal(entry({ time: 100, metadata }, 99), null);
  assert.equal(entry({ time: 0, error: 42, kind: "auth" }, 1), null);
  assert.equal(
    entry({ time: 0, metadata: { versions: ["1"], "dist-tags": [] } }, 1),
    null,
  );
  assert.deepEqual(entry({ time: 0, metadata }, 1)?.metadata, metadata);
});
test("protocol rejects malformed inputs before dispatch", () => {
  const { request } = require("../scripts/core/protocol.cjs");
  for (const input of [
    null,
    [],
    { id: 0, method: "inspect", input: {} },
    { id: 1, method: "check", input: { client: "x", context: {} } },
  ]) {
    assert.throws(() => request(JSON.stringify(input)));
  }
  assert.equal(
    request(
      JSON.stringify({
        id: 1,
        method: "inspect",
        input: { path: "/tmp/package.json", manifest: "{}" },
      }),
    ).method,
    "inspect",
  );
  assert.equal(
    request(
      JSON.stringify({
        id: 2,
        method: "inspect",
        input: { path: "/tmp/package.json", manifest: "{}", managers: [] },
      }),
    ).method,
    "inspect",
  );
  assert.equal(
    request(
      JSON.stringify({
        id: 3,
        method: "configure",
        input: { npm_path: "/npm", context: {}, exports: [] },
      }),
    ).method,
    "configure",
  );
  assert.throws(() =>
    request(
      JSON.stringify({
        id: 4,
        method: "inspect",
        input: { path: "/tmp/package.json", manifest: "{}", managers: ["npm"] },
      }),
    ),
  );
  assert.throws(() =>
    request(
      JSON.stringify({
        id: 5,
        method: "compare",
        input: {
          dep: { name: "a", spec: "^1", kind: "range", target: 42 },
          stdout: "{}",
        },
      }),
    ),
  );
});
test("manifest and PnP boundaries validate unknown fields without assuming JSON shape", () => {
  const { manifest } = require("../scripts/core/manifest.cjs");
  const { pnp } = require("../scripts/core/protocol.cjs");
  for (const value of [
    null,
    [],
    { packageManager: 4 },
    { dependencies: [] },
    { workspaces: [1] },
  ]) {
    assert.throws(() => manifest(value));
  }
  assert.deepEqual(
    manifest({
      dependencies: { a: 42 },
      workspaces: { packages: ["packages/*"] },
    }).dependencies,
    { a: 42 },
  );
  assert.throws(() =>
    pnp('{"dir":"/tmp","root":"/tmp","dependencies":[null]}'),
  );
  assert.deepEqual(
    pnp(
      '{"dir":"/tmp","root":"/tmp","dependencies":[{"name":"a","target":"a"}]}',
    ).dependencies,
    [{ name: "a", target: "a" }],
  );
});
