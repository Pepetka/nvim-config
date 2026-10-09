/** @param {string|undefined} override @param {string|undefined} marker @param {string[]} locks */
function selectManager(override, marker, locks) {
  const selected =
    override ||
    marker ||
    (locks.length === 1 ? locks[0] : locks.length === 0 ? "npm" : null);
  const match = selected?.match(/^(npm|yarn|pnpm)(?:@(\d+)(?:\.[^ ]*)?)?$/);
  return {
    selected,
    manager: match?.[1],
    expected_major: match?.[2] ? Number(match[2]) : undefined,
    error: !selected
      ? "Conflicting lockfiles: set a package manager override"
      : !match
        ? "Unsupported packageManager"
        : undefined,
  };
}
module.exports = { selectManager };
