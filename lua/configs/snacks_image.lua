-- Fixes private snacks.image lifecycle bugs; remove once upstream merges #2918 and #2964.
-- A terminal placement exists only while its buffer is visible. Run tests/image.lua after updating snacks.
local image = require("snacks").image
local Image = image.image
local Placement = image.placement
local offscreen = setmetatable({}, { __mode = "v" }) ---@type table<number, snacks.image.Placement>

---@param pid? number
---@diagnostic disable-next-line: duplicate-set-field
function Image:del(pid)
  for _, id in ipairs(pid and { pid } or vim.tbl_keys(self.placements)) do
    if self.placements[id] then
      image.terminal.request({ a = "d", d = "i", i = self.id, p = id })
      self.placements[id] = nil
    end
  end
  if self.sent and not next(self.placements) then
    image.terminal.request({ a = "d", d = "I", i = self.id })
    self.sent = false
  end
end

local update = Placement.update
---@diagnostic disable-next-line: duplicate-set-field
function Placement:update()
  -- opts is unset while Placement.new sends the image, and inline images manage their own visibility.
  local managed = self:ready() and not self.opts.inline
  local visible = managed and #self:wins() > 0
  if visible then
    self.hidden = false
  end
  update(self)
  if managed and not visible then
    self.img:del(self.id)
    offscreen[self.buf] = self
  end
end

-- fzf-lua restores preview buffers without autocommands, so only their redraw reveals them.
vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace("configs.snacks_image"), {
  on_win = function(_, _, buf)
    local placement = offscreen[buf]
    if placement then
      offscreen[buf] = nil
      vim.schedule(function()
        placement:update()
      end)
    end
    return false
  end,
})

for _, name in ipairs({ "progress", "error" }) do
  local method = Placement[name]
  Placement[name] = function(self)
    method(self)
    if not self.opts.inline and vim.api.nvim_buf_is_valid(self.buf) then
      vim.bo[self.buf].modified = false
    end
  end
end
