const { object } = require("./metadata.cjs");
/** @param {unknown} value @returns {import("../types").Manifest} */
function manifest(value) {
  if (!object(value)) throw new Error("Invalid manifest");
  for (const key of ["name", "version", "packageManager"]) {
    if (value[key] !== undefined && typeof value[key] !== "string")
      throw new Error("Invalid manifest field");
  }
  for (const key of [
    "dependencies",
    "devDependencies",
    "optionalDependencies",
    "peerDependencies",
  ]) {
    if (value[key] !== undefined && !object(value[key]))
      throw new Error("Invalid dependency section");
  }
  const workspaces = value.workspaces;
  const packages = object(workspaces) ? workspaces.packages : workspaces;
  if (
    packages !== undefined &&
    (!Array.isArray(packages) ||
      !packages.every((item) => typeof item === "string"))
  ) {
    throw new Error("Invalid workspaces");
  }
  if (
    workspaces !== undefined &&
    !Array.isArray(workspaces) &&
    !object(workspaces)
  )
    throw new Error("Invalid workspaces");
  return /** @type {import("../types").Manifest} */ (value);
}
module.exports = { manifest };
