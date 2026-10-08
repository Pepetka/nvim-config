const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const semver = require("semver");
const picomatch = require("picomatch");
const yaml = require("yaml");

const sections = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"];
function read(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return "";
  }
}
function json(file) {
  try {
    return JSON.parse(read(file));
  } catch {
    return {};
  }
}
function ancestors(dir) {
  const result = [];
  for (;;) {
    result.push(dir);
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return result;
}
function workspacePatterns(dir, manifest) {
  const ws = manifest.workspaces;
  let patterns = Array.isArray(ws) ? ws : ws?.packages || [];
  const file = read(path.join(dir, "pnpm-workspace.yaml"));
  if (file) {
    try {
      patterns = yaml.parse(file)?.packages || patterns;
    } catch {
      return [];
    }
  }
  return Array.isArray(patterns) ? patterns.filter((p) => typeof p === "string") : [];
}
function member(dir, child, manifest) {
  const relative = path.relative(dir, child).split(path.sep).join("/");
  const patterns = workspacePatterns(dir, manifest);
  const positive = patterns.filter((p) => !p.startsWith("!"));
  const negative = patterns.filter((p) => p.startsWith("!")).map((p) => p.slice(1));
  return !!relative && positive.some((p) => picomatch(p)(relative)) && !negative.some((p) => picomatch(p)(relative));
}
function specification(name, value) {
  let target = name,
    range = value;
  if (typeof value !== "string")
    return { name, spec: String(value), kind: "unsupported", reason: "Non-string declaration" };
  if (!/^(@[a-z0-9_.-]+\/)?[a-z0-9_.-]+$/i.test(name))
    return { name, spec: value, kind: "unsupported", reason: "Invalid declaration name" };
  if (/^(workspace|file|link|portal):/.test(value)) return { name, spec: value, kind: "local" };
  if (value.startsWith("npm:")) {
    const match = value.slice(4).match(/^(@[^/]+\/[^@]+|[^@]+)(?:@(.+))?$/);
    if (!match) return { name, spec: value, kind: "unsupported", reason: "Invalid npm alias" };
    target = match[1];
    range = match[2] || "*";
  }
  if (!/^(@[a-z0-9_.-]+\/)?[a-z0-9_.-]+$/i.test(target))
    return { name, spec: value, kind: "unsupported", reason: "Invalid package name" };
  range = range.trim();
  if (semver.validRange(range)) return { name, target, spec: value, range, kind: "range" };
  if (/^[a-zA-Z][a-zA-Z0-9_.-]*$/.test(range)) return { name, target, spec: value, range, kind: "tag" };
  return {
    name,
    spec: value,
    kind: "unsupported",
    reason: "Git, URL, catalog and patch specifications are not compared",
  };
}
function installed(dep, dir, root, pnp = false) {
  if (!dep.target) return { state: "not_applicable" };
  if (pnp) {
    try {
      const issuer = path.join(fs.realpathSync(dir), "package.json");
      const api = require("node:module").findPnpApi(issuer);
      const resolved = api.resolveToUnqualified(dep.name, issuer);
      const pkg = json(path.join(resolved, "package.json"));
      return pkg.name === dep.target && semver.valid(pkg.version)
        ? { state: "installed", version: pkg.version }
        : { state: "unknown", reason: "Resolved package identity mismatch" };
    } catch {
      return { state: "unknown", reason: "PnP cannot resolve this declaration" };
    }
  }
  for (const current of ancestors(dir)) {
    const file = path.join(current, "node_modules", dep.name, "package.json");
    if (fs.existsSync(file)) {
      const pkg = json(file);
      return pkg.name === dep.target && semver.valid(pkg.version)
        ? { state: "installed", version: pkg.version }
        : { state: "unknown", reason: "Installed package identity mismatch" };
    }
    if (current === root) break;
  }
  return { state: "unknown", reason: "No installed package found" };
}
function inspect(input) {
  const dir = path.dirname(path.resolve(input.path));
  const manifest = JSON.parse(input.manifest);
  const chain = ancestors(dir);
  let root = dir;
  for (const parent of chain.slice(1)) {
    const pkg = json(path.join(parent, "package.json"));
    if (member(parent, root, pkg)) root = parent;
    else if (fs.existsSync(path.join(parent, "package.json")) || fs.existsSync(path.join(parent, ".git"))) break;
  }
  const applicable = ancestors(dir).slice(0, ancestors(dir).indexOf(root) + 1);
  let marker;
  for (const current of applicable) {
    const pkg = current === dir ? manifest : json(path.join(current, "package.json"));
    if (pkg.packageManager) {
      marker = pkg.packageManager;
      break;
    }
  }
  const locks = new Set();
  for (const current of applicable) {
    if (fs.existsSync(path.join(current, "pnpm-workspace.yaml"))) locks.add("pnpm");
    for (const [file, manager] of [
      ["package-lock.json", "npm"],
      ["npm-shrinkwrap.json", "npm"],
      ["yarn.lock", "yarn"],
      ["pnpm-lock.yaml", "pnpm"],
    ]) {
      if (fs.existsSync(path.join(current, file))) locks.add(manager);
    }
  }
  const override = input.override || applicable.map((current) => input.managers?.[current]).find(Boolean);
  const selected = override || marker || (locks.size === 1 ? [...locks][0] : locks.size === 0 ? "npm" : null);
  const match = selected?.match(/^(npm|yarn|pnpm)(?:@(\d+)(?:\.[^ ]*)?)?$/);
  const context = {
    dir,
    root,
    manager: match?.[1],
    expected_major: match?.[2] && Number(match[2]),
    marker,
    error: !selected
      ? "Conflicting lockfiles: set a package manager override"
      : !match
        ? "Unsupported packageManager"
        : undefined,
  };
  const hash = crypto.createHash("sha256");
  hash.update(input.manifest);
  hash.update(String(selected));
  hash.update(input.environment_hash || "");
  const registryHash = crypto.createHash("sha256");
  registryHash.update(dir);
  registryHash.update(root);
  registryHash.update(String(selected));
  registryHash.update(input.environment_hash || "");
  const configFiles = [
    "package.json",
    "package-lock.json",
    "npm-shrinkwrap.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "pnpm-workspace.yaml",
    ".npmrc",
    ".yarnrc",
    ".yarnrc.yml",
    ".pnp.cjs",
    ".pnp.loader.mjs",
  ];
  // Include user rc contents in the fingerprint, never in responses or diagnostics.
  for (const current of new Set([...chain, process.env.HOME].filter(Boolean))) {
    for (const file of configFiles) {
      const filename = path.join(current, file);
      if (fs.existsSync(filename)) {
        hash.update(filename);
        const content = read(filename);
        hash.update(content);
        if ([".npmrc", ".yarnrc", ".yarnrc.yml", "pnpm-workspace.yaml"].includes(file)) {
          registryHash.update(filename);
          registryHash.update(content);
        }
      }
    }
  }
  if (input.user_config) {
    hash.update(input.user_config);
    hash.update(read(input.user_config));
    registryHash.update(input.user_config);
    registryHash.update(read(input.user_config));
  }
  context.fingerprint = hash.digest("hex");
  context.registry_fingerprint = registryHash.digest("hex");
  context.pnp = applicable.some((current) => fs.existsSync(path.join(current, ".pnp.cjs")));
  context.custom_plugins = [...new Set([...chain, process.env.HOME].filter(Boolean))].some((current) => {
    try {
      return Boolean(yaml.parse(read(path.join(current, ".yarnrc.yml")))?.plugins?.length);
    } catch {
      return false;
    }
  });
  context.overrides = Boolean(
    manifest.overrides ||
    manifest.resolutions ||
    json(path.join(root, "package.json")).overrides ||
    json(path.join(root, "package.json")).resolutions,
  );
  context.dependencies = sections.flatMap((section) =>
    Object.entries(manifest[section] || {}).map(([name, spec]) => {
      const dep = { ...specification(name, spec), section };
      dep.installed = context.pnp ? { state: "unknown", reason: "PnP lookup pending" } : installed(dep, dir, root);
      return dep;
    }),
  );
  return context;
}
function compare(dep, metadata) {
  const versions = (metadata.versions || []).filter((v) => semver.valid(v));
  const tags = metadata["dist-tags"] || {};
  const resolved =
    dep.kind === "tag"
      ? semver.valid(tags[dep.range])
        ? tags[dep.range]
        : undefined
      : semver.maxSatisfying(versions, dep.range);
  const wanted = resolved || undefined;
  const latest = semver.valid(tags.latest) ? tags.latest : undefined;
  const current = dep.installed?.version;
  let status = "unknown";
  if (!wanted) status = "unavailable";
  else if (current && semver.valid(current)) {
    status = "current";
    if (semver.gt(wanted, current)) status = "update";
    else if (
      dep.kind === "range" &&
      latest &&
      semver.gt(latest, current) &&
      !semver.prerelease(current) &&
      !semver.prerelease(wanted)
    )
      status = "major";
  }
  return { wanted, latest, status, checked_at: Date.now() };
}
function parseRegistry(text) {
  const valid = (value) =>
    value && Array.isArray(value.versions) && value["dist-tags"] && typeof value["dist-tags"] === "object";
  try {
    const value = JSON.parse(text);
    if (valid(value)) return value;
    if (valid(value.data)) return value.data;
  } catch {}
  for (const line of text.split("\n")) {
    try {
      const value = JSON.parse(line);
      if (value.type === "inspect" && valid(value.data)) return value.data;
      if (valid(value)) return value;
    } catch {}
  }
  throw new Error("Registry command returned no version metadata");
}
module.exports = { inspect, specification, installed, compare, parseRegistry, member };
