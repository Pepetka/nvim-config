local M = {}
local levels = require("stable_folds.core.levels")

---@param context StableFoldsContext
---@return StableFoldsSignature
function M.signature(context)
  return { tick = context.tick, filetype = context.filetype, lang = context.lang }
end

---@param entry? StableFoldsSignature
---@param context StableFoldsContext
---@return boolean
function M.matches(entry, context)
  return entry ~= nil
    and entry.tick == context.tick
    and entry.filetype == context.filetype
    and entry.lang == context.lang
end

---@param view? StableFoldsView
---@param snapshot StableFoldsSnapshot
---@param context StableFoldsContext
---@return boolean
function M.view_matches(view, snapshot, context)
  return view ~= nil
    and view.buf == context.buf
    and view.snapshot == snapshot
    and view.minlines == context.minlines
    and view.nestmax == context.nestmax
end

---@param snapshot StableFoldsSnapshot
---@param context StableFoldsContext
---@param candidates table<integer, StableFoldsView>
---@return StableFoldsView
function M.view(snapshot, context, candidates)
  local previous = candidates[context.win]
  if M.view_matches(previous, snapshot, context) then
    return assert(previous)
  end
  local computed
  for _, candidate in pairs(candidates) do
    if M.view_matches(candidate, snapshot, context) then
      computed = candidate.levels
      break
    end
  end
  return {
    buf = context.buf,
    snapshot = snapshot,
    minlines = context.minlines,
    nestmax = context.nestmax,
    levels = computed or levels.build(snapshot.ranges, snapshot.line_count, context.minlines, context.nestmax),
  }
end

return M
