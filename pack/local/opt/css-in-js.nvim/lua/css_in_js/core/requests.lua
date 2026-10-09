local M = {}

---@param ctx CssInJsContext
---@return CssInJsContext
function M.context(ctx)
  return { bufnr = ctx.bufnr, cursor = { ctx.cursor[1], ctx.cursor[2] }, line = ctx.line }
end

---@param job CssInJsJob
---@param now integer
---@param tick integer?
---@param version integer
---@param client CssInJsClient?
---@return "done" | "stale" | "timeout" | "wait" | "ready"
function M.state(job, now, tick, version, client)
  if job.done then
    return "done"
  end
  if tick ~= job.tick or version ~= job.version or not client or client.stopped then
    return "stale"
  end
  if now >= job.deadline then
    return "timeout"
  end
  return client.initialized and "ready" or "wait"
end

return M
