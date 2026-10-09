const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const semver = require("semver");
const workspaces = require("../core/workspaces.cjs");
const { specification } = require("../core/versions.cjs");
const { selectManager } = require("../core/context.cjs");
const yaml = require("yaml");
const { manifest: validateManifest } = require("../core/manifest.cjs");
const { object } = require("../core/metadata.cjs");

/** @type {(keyof Pick<import("../types").Manifest,"dependencies"|"devDependencies"|"optionalDependencies"|"peerDependencies">)[]} */
const sections = [
  "dependencies",
  "devDependencies",
  "optionalDependencies",
  "peerDependencies",
];
/** @param {string} file @returns {string} */
function read(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return "";
  }
}
/** @param {string} file @returns {import("../types").Manifest} */
function json(file) {
  try {
    return validateManifest(JSON.parse(read(file)));
  } catch {
    return {};
  }
}
/** @param {string} dir @returns {string[]} */
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
/** @param {string} dir @param {string} child @param {import("../types").Manifest} manifest @returns {boolean} */
function member(dir, child, manifest) {
  return workspaces.member(
    dir,
    child,
    manifest,
    read(path.join(dir, "pnpm-workspace.yaml")),
  );
}
/** @param {Pick<import("../types").Declaration,"name"|"target">} dep @param {string} dir @param {string} root @param {boolean} [pnp] @returns {import("../types").Installed} */
function installed(dep, dir, root, pnp = false) {
  if (!dep.target) return { state: "not_applicable" };
  if (pnp) {
    try {
      const issuer = path.join(fs.realpathSync(dir), "package.json");
      const api =
        /** @type {{resolveToUnqualified(name:string,issuer:string):string}} */ (
          /** @type {{findPnpApi(issuer:string):{resolveToUnqualified(name:string,issuer:string):string}}} */ (
            /** @type {unknown} */ (require("node:module"))
          ).findPnpApi(issuer)
        );
      const resolved = api.resolveToUnqualified(dep.name, issuer);
      const pkg = json(path.join(resolved, "package.json"));
      return pkg.name === dep.target && semver.valid(pkg.version)
        ? { state: "installed", version: pkg.version }
        : { state: "unknown", reason: "Resolved package identity mismatch" };
    } catch {
      return {
        state: "unknown",
        reason: "PnP cannot resolve this declaration",
      };
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
/** @param {import("../types").InspectInput} input @returns {import("../types").Context} */
function inspect(input) {
  const dir = path.dirname(path.resolve(input.path));
  const manifest = validateManifest(JSON.parse(input.manifest));
  const chain = ancestors(dir);
  let root = dir;
  for (const parent of chain.slice(1)) {
    const pkg = json(path.join(parent, "package.json"));
    if (member(parent, root, pkg)) root = parent;
    else if (
      fs.existsSync(path.join(parent, "package.json")) ||
      fs.existsSync(path.join(parent, ".git"))
    )
      break;
  }
  const applicable = ancestors(dir).slice(0, ancestors(dir).indexOf(root) + 1);
  let marker;
  for (const current of applicable) {
    const pkg =
      current === dir ? manifest : json(path.join(current, "package.json"));
    if (pkg.packageManager) {
      marker = pkg.packageManager;
      break;
    }
  }
  const locks = new Set();
  for (const current of applicable) {
    if (fs.existsSync(path.join(current, "pnpm-workspace.yaml")))
      locks.add("pnpm");
    for (const [file, manager] of [
      ["package-lock.json", "npm"],
      ["npm-shrinkwrap.json", "npm"],
      ["yarn.lock", "yarn"],
      ["pnpm-lock.yaml", "pnpm"],
    ]) {
      if (fs.existsSync(path.join(current, file))) locks.add(manager);
    }
  }
  const override =
    input.override ||
    applicable.map((current) => input.managers?.[current]).find(Boolean);
  const selection = selectManager(override, marker, [...locks]);
  const selected = selection.selected;
  /** @type {import("../types").Context} */
  const context = {
    dir,
    root,
    manager: selection.manager,
    expected_major: selection.expected_major,
    marker,
    error: selection.error,
    fingerprint: "",
    registry_fingerprint: "",
    pnp: false,
    custom_plugins: false,
    overrides: false,
    dependencies: [],
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
  for (const current of new Set(
    [...chain, process.env.HOME].filter((value) => typeof value === "string"),
  )) {
    for (const file of configFiles) {
      const filename = path.join(current, file);
      if (fs.existsSync(filename)) {
        hash.update(filename);
        const content = read(filename);
        hash.update(content);
        if (
          [".npmrc", ".yarnrc", ".yarnrc.yml", "pnpm-workspace.yaml"].includes(
            file,
          )
        ) {
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
  context.pnp = applicable.some((current) =>
    fs.existsSync(path.join(current, ".pnp.cjs")),
  );
  context.custom_plugins = [
    ...new Set(
      [...chain, process.env.HOME].filter((value) => typeof value === "string"),
    ),
  ].some((current) => {
    try {
      /** @type {unknown} */
      const config = yaml.parse(read(path.join(current, ".yarnrc.yml")));
      return (
        object(config) &&
        Array.isArray(config.plugins) &&
        config.plugins.length > 0
      );
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
      const declaration = specification(name, spec);
      return {
        ...declaration,
        section,
        installed: context.pnp
          ? { state: "unknown", reason: "PnP lookup pending" }
          : installed(declaration, dir, root),
      };
    }),
  );
  return context;
}

module.exports = { inspect, installed, member };
