local M = {}
local snapshot

---Publish the palette used by TokyoNight before its highlight consumers run.
---@param palette table<string, any>
function M.update(palette)
  snapshot = {
    palette = palette,
    fg = palette.fg,
    bg = palette.bg,
    bg_visual = palette.bg_visual,
    error = palette.error,
    warning = palette.warning,
    info = palette.info,
    success = palette.green,
    muted = palette.comment,
    subtle = palette.dark3,
    surface = palette.bg_highlight,
    gutter = palette.fg_gutter,
    accent = palette.cyan,
    focus = palette.blue,
    alert = palette.orange,
    special = palette.magenta,
    test = palette.magenta2,
  }
end

function M.ready()
  return snapshot ~= nil
end

---Read the current snapshot; retained snapshots belong to their original theme.
---@return table<string, any>
function M.get()
  assert(snapshot, "Theme palette is not initialized; load configs.theme before color consumers")
  return snapshot
end

-- Keep semantic access such as colors.fg dynamic without rebuilding the palette.
return setmetatable(M, {
  __index = function(_, key)
    return M.get()[key]
  end,
})
