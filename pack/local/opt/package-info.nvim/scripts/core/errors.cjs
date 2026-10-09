/** @param {unknown} value @returns {{kind: import("../types").ErrorKind,error:string}} */
function classify(value) {
  const error =
    value && typeof value === "object"
      ? /** @type {{code?:string,name?:string}} */ (value)
      : {};
  const code = error.code || "";
  if (code === "E401" || code === "E403" || code === "EAUTH")
    return { kind: "auth", error: "Registry authentication failed" };
  if (code === "E404")
    return {
      kind: "not_found",
      error: "Package not found or access denied by the registry",
    };
  if (
    error.name === "AbortError" ||
    error.name === "TimeoutError" ||
    /TIMEOUT|TIMEDOUT/.test(code)
  )
    return { kind: "timeout", error: "Registry request timed out" };
  if (code === "EMETADATA")
    return { kind: "metadata", error: "Registry returned invalid metadata" };
  return {
    kind: "network",
    error: "Registry request failed; check network and manager configuration",
  };
}

module.exports = { classify };
