const semver = require("semver");
/** @param {string} name @param {unknown} value @returns {import("../types").Declaration} */
function specification(name, value) {
  let target = name,
    range = typeof value === "string" ? value : "";
  if (typeof value !== "string")
    return {
      name,
      spec: String(value),
      kind: "unsupported",
      reason: "Non-string declaration",
    };
  if (!/^(@[a-z0-9_.-]+\/)?[a-z0-9_.-]+$/i.test(name))
    return {
      name,
      spec: value,
      kind: "unsupported",
      reason: "Invalid declaration name",
    };
  if (/^(workspace|file|link|portal):/.test(value))
    return { name, spec: value, kind: "local" };
  if (value.startsWith("npm:")) {
    const match = value.slice(4).match(/^(@[^/]+\/[^@]+|[^@]+)(?:@(.+))?$/);
    if (!match)
      return {
        name,
        spec: value,
        kind: "unsupported",
        reason: "Invalid npm alias",
      };
    target = match[1];
    range = match[2] || "*";
  }
  if (!/^(@[a-z0-9_.-]+\/)?[a-z0-9_.-]+$/i.test(target))
    return {
      name,
      spec: value,
      kind: "unsupported",
      reason: "Invalid package name",
    };
  range = range.trim();
  if (semver.validRange(range))
    return { name, target, spec: value, range, kind: "range" };
  if (/^[a-zA-Z][a-zA-Z0-9_.-]*$/.test(range))
    return { name, target, spec: value, range, kind: "tag" };
  return {
    name,
    spec: value,
    kind: "unsupported",
    reason: "Git, URL, catalog and patch specifications are not compared",
  };
}
/** @param {import("../types").Declaration} dep @param {import("../types").Metadata} metadata @param {string} [range] @param {string} [manager] @returns {string | undefined} */
function pick(dep, metadata, range, manager) {
  const tags = metadata["dist-tags"] || {};
  if (dep.kind === "tag")
    return semver.valid(tags[range || ""]) ? tags[range || ""] : undefined;
  const versions = (metadata.versions || []).filter((v) => semver.valid(v));
  const deprecated = new Set(metadata.deprecated || []);
  const latest = tags.latest;
  // npm and pnpm prefer the latest tag when it satisfies the range; Yarn takes the highest match.
  if (
    manager !== "yarn" &&
    semver.valid(latest) &&
    !deprecated.has(latest) &&
    semver.satisfies(latest, range || "*")
  )
    return latest;
  return (
    semver.maxSatisfying(
      versions.filter((v) => !deprecated.has(v)),
      range || "*",
    ) ||
    semver.maxSatisfying(versions, range || "*") ||
    undefined
  );
}
/** @param {import("../types").Declaration} dep @param {import("../types").Metadata} metadata @param {number} [checked_at] @param {string} [manager] @returns {import("../types").Comparison} */
function compare(dep, metadata, checked_at, manager) {
  const tags = metadata["dist-tags"] || {};
  const wanted = pick(dep, metadata, dep.range, manager);
  const latest = semver.valid(tags.latest) ? tags.latest : undefined;
  const current = dep.installed?.version;
  /** @type {import("../types").Comparison["status"]} */
  let status = "unknown";
  if (!wanted) status = "unavailable";
  else if (current && semver.valid(current)) {
    status = "current";
    if (dep.kind === "range" && !semver.satisfies(current, dep.range || "*"))
      status = "mismatch";
    else if (semver.gt(wanted, current)) status = "update";
    else if (
      dep.kind === "range" &&
      latest &&
      semver.gt(latest, current) &&
      !semver.prerelease(current) &&
      !semver.prerelease(wanted)
    )
      status = "major";
  } else if (
    dep.installed?.state === "missing" &&
    dep.section !== "optionalDependencies" &&
    dep.section !== "peerDependencies"
  )
    status = "missing";
  return { wanted, latest, status, checked_at };
}

module.exports = { specification, compare };
