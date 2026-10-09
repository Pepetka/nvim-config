local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local t = require("support")
local config = require("css_in_js.core.config")
local regions = require("css_in_js.core.regions")
local coordinates = require("css_in_js.core.coordinates")
local document = require("css_in_js.core.document")
local completion = require("css_in_js.core.completion")
local requests = require("css_in_js.core.requests")
local host_vim = rawget(_G, "vim")
_G.vim = nil

---@param first integer
---@param last integer
---@return CssInJsRegion
local function region(first, last)
  return { start_row = 0, start_col = first, end_row = 0, end_col = last, substitutions = {} }
end
---@param first integer
---@param last integer
---@param row? integer
---@return lsp.Range
local function range(first, last, row)
  return { start = { line = row or 1, character = first }, ["end"] = { line = row or 1, character = last } }
end
---@type CssInJsClient
local client = {
  id = 1,
  name = "css_in_js",
  initialized = true,
  stopped = false,
  encoding = "utf-16",
  completion = true,
  hover = true,
}
local snapshot = document.build({ "prefix`color: red;`suffix" }, region(7, 18))

t.test("defaults and inputs are independent", function()
  local input = { styled_parser = { url = "parser", files = { "p.c" } } }
  local options, messages = config.normalize(input)
  assert(options.filter(0))
  t.equal(messages, {})
  assert(options.styled_parser).files[1] = "changed"
  t.equal(input.styled_parser.files, { "p.c" })
end)
for _, value in ipairs({
  false,
  1,
  "bad",
  { filter = false },
  { styled_parser = false },
  { styled_parser = { url = "" } },
  { styled_parser = { url = "p", files = { [2] = "x" } } },
  { styled_parser = { url = "p", revision = 2 } },
  { styled_parser = { url = "p", generate = "yes" } },
}) do
  t.test("invalid configuration " .. tostring(value), function()
    local options, messages = config.normalize(value)
    assert(#messages > 0 and options.filter(0))
    t.equal(options.styled_parser, nil)
  end)
end
for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
  t.test("supported filetype " .. ft, function()
    assert(regions.supports(ft, ""))
    assert(not regions.supports(ft, "nofile"))
  end)
end
t.test("unknown filetypes return false", function()
  t.equal(regions.supports("css", ""), false)
end)
t.test("region boundaries exclude substitutions and allow insertion at content end", function()
  local value = region(4, 20)
  value.substitutions = { region(8, 12) }
  assert(regions.active(value, 0, 4))
  assert(regions.active(value, 0, 20))
  assert(not regions.active(value, 0, 3))
  assert(not regions.active(value, 0, 21))
  assert(not regions.active(value, 0, 8))
  assert(not regions.active(value, 0, 11))
  assert(regions.active(value, 0, 12))
  assert(not regions.active(value, -1, 4))
end)
for _, encoding in ipairs({ "utf-8", "utf-16", "utf-32" }) do
  t.test("Unicode position round trips " .. encoding, function()
    ---@cast encoding CssInJsEncoding
    local text = "aé界😀é"
    for _, byte in ipairs({ 0, 1, 3, 6, 10, 11, 13 }) do
      local character = assert(coordinates.character(text, byte, encoding))
      t.equal(coordinates.byte(text, character, encoding), byte)
    end
    t.equal(coordinates.character(text, 2, encoding), nil)
    t.equal(coordinates.byte(text, 999, encoding), nil)
  end)
end
for _, text in ipairs({ "\128", "\192\128", "\237\160\128", "\244\144\128\128", "\240\159" }) do
  t.test("reject invalid UTF-8 " .. #text .. text:byte(), function()
    t.equal(coordinates.decode(text, 1), nil)
  end)
end
t.test("reject surrogate split and invalid positions", function()
  t.equal(coordinates.byte("😀", 1, "utf-16"), nil)
  t.equal(coordinates.character("abc", -1, "utf-16"), nil)
  t.equal(coordinates.byte("abc", 1.5, "utf-8"), nil)
end)
t.test("placeholder selection", function()
  t.equal(document.placeholder("color: "), "0")
  t.equal(document.placeholder("; "), ";")
end)
t.test("document wrapper and extraction", function()
  t.equal(snapshot.lines, { "a{", "color: red;", ";}" })
  local host = { "before`", "color: red;", "`after" }
  t.equal(
    document.extract(host, { start_row = 0, start_col = 7, end_row = 2, end_col = 0, substitutions = {} }),
    { "", "color: red;", "" }
  )
end)
t.test("empty document insertion translates to the host", function()
  local empty = document.build({ "css``" }, region(4, 4))
  t.equal(document.host_range(empty, range(0, 0), "utf-16"), range(4, 4, 0))
end)
t.test("valid range translated without mutating input", function()
  local input = range(0, 5)
  local before = t.copy(input)
  t.equal(document.host_range(snapshot, input, "utf-16"), range(7, 12, 0))
  t.equal(input, before)
end)
for _, input in ipairs({
  range(-1, 2),
  range(0, 999),
  range(5, 2),
  range(0, 2, 0),
  range(0, 1, 2),
  range(0.5, 2),
  {},
  { start = {}, ["end"] = {} },
}) do
  t.test("reject invalid range " .. tostring(input), function()
    t.equal(document.host_range(snapshot, input, "utf-16"), nil)
  end)
end
for _, encoding in ipairs({ "utf-8", "utf-16", "utf-32" }) do
  t.test("masked emoji preserves host coordinates " .. encoding, function()
    ---@cast encoding CssInJsEncoding
    local text = "css`color: ${😀}; padding: 1px;`"
    local first = assert(text:find("${", 1, true)) - 1
    local last = assert(text:find("}", 1, true))
    local value = region(4, #text - 1)
    value.substitutions = { region(first, last) }
    local snap = document.build({ text }, value)
    assert(not snap.lines[2]:find("😀", 1, true))
    local host_byte = assert(text:find("padding", 1, true)) - 1
    local position = assert(document.position(snap, 0, host_byte, encoding))
    local mapped = assert(document.host_range(snap, { start = position, ["end"] = position }, encoding))
    t.equal(mapped.start.character, coordinates.character(text, host_byte, encoding))
    t.equal(document.host_range(snap, range(0, #snap.lines[2]), encoding), nil)
    t.equal(document.position(snap, 0, first + 2, encoding), nil)
  end)
end
t.test("multiline substitutions and immutable host input", function()
  local host = { "css`color: ${", "  fn('😀')", "}; padding: 1px;`" }
  local before = t.copy(host)
  local value = {
    start_row = 0,
    start_col = 4,
    end_row = 2,
    end_col = #host[3] - 1,
    substitutions = { { start_row = 0, start_col = 11, end_row = 2, end_col = 1, substitutions = {} } },
  }
  local snap = document.build(host, value)
  t.equal(host, before)
  assert(not table.concat(snap.lines):find("fn", 1, true))
  local position = assert(document.position(snap, 2, 3, "utf-16"))
  t.equal(
    assert(document.host_range(snap, { start = position, ["end"] = position }, "utf-16")).start,
    { line = 2, character = 3 }
  )
end)
t.test("completion defaults and response are immutable", function()
  local result = {
    itemDefaults = {
      editRange = range(0, 5),
      insertTextFormat = 2,
      insertTextMode = 1,
      commitCharacters = { ";" },
      data = { key = 1 },
    },
    items = { { label = "color", textEditText = "color: $0" } },
  }
  local before = t.copy(result)
  local response = completion.response(result, snapshot, client, 7)
  t.equal(result, before)
  t.equal(#response.items, 1)
  local item = response.items[1]
  t.equal(item.client_id, 1)
  t.equal(item.cursor_column, 7)
  t.equal(item.textEdit.range, range(7, 12, 0))
  t.equal(item.insertTextFormat, 2)
  t.equal(item.data, { key = 1 })
end)
t.test("explicit defaults and insert replace edits", function()
  local item = assert(
    completion.item(
      { label = "color", insertTextFormat = 1, data = false },
      { insertTextFormat = 2, data = true },
      snapshot,
      client,
      7
    )
  )
  t.equal(item.insertTextFormat, 1)
  t.equal(item.data, false)
  local edit =
    assert(completion.edit({ newText = "color", insert = range(0, 2), replace = range(0, 5) }, snapshot, "utf-16"))
  t.equal(edit.insert, range(7, 9, 0))
end)
for _, value in ipairs({
  false,
  {},
  { label = "x", textEdit = { newText = "x", range = range(0, 999) } },
  { label = "x", additionalTextEdits = { { newText = "x", range = range(0, 1, 0) } } },
  { label = "x", textEdit = { newText = "x", insert = range(0, 8), replace = range(0, 5) } },
  { label = "x", additionalTextEdits = false },
}) do
  t.test("invalid completion " .. tostring(value), function()
    t.equal(completion.item(value, {}, snapshot, client, 0), nil)
  end)
end
t.test("array completion and nil replies", function()
  t.equal(#completion.response({ { label = "red" } }, snapshot, client, 0).items, 1)
  t.equal(completion.response(nil, snapshot, client, 0).items, {})
end)
t.test("request state transitions", function()
  local job = { done = false, deadline = 5000, version = 1, tick = 2, cancel = function() end }
  t.equal(requests.state(job, 0, 2, 1, client), "ready")
  local pending = t.copy(client)
  pending.initialized = false
  t.equal(requests.state(job, 0, 2, 1, pending), "wait")
  t.equal(requests.state(job, 5000, 2, 1, client), "timeout")
  t.equal(requests.state(job, 0, 3, 1, client), "stale")
  t.equal(requests.state(job, 0, 2, 2, client), "stale")
  t.equal(requests.state(job, 0, 2, 1, nil), "stale")
  job.done = true
  t.equal(requests.state(job, 5000, 2, 1, client), "done")
end)
t.test("multiple substitutions preserve coordinates and source input", function()
  local text = "css`color: ${😀}; width: ${x}; padding: 1px;`"
  local value = region(4, #text - 1)
  for _, needle in ipairs({ "${😀}", "${x}" }) do
    local first, last = assert(text:find(needle, 1, true))
    value.substitutions[#value.substitutions + 1] = region(first - 1, last)
  end
  local before = t.copy(value)
  local snap = document.build({ text }, value)
  t.equal(value, before)
  local byte = assert(text:find("padding", 1, true)) - 1
  local position = assert(document.position(snap, 0, byte, "utf-16"))
  t.equal(
    assert(document.host_range(snap, { start = position, ["end"] = position }, "utf-16")).start.character,
    coordinates.character(text, byte, "utf-16")
  )
end)
t.test("defaults with insert replace ranges and valid additional edits", function()
  local item = assert(
    completion.item(
      { label = "color", additionalTextEdits = { { newText = "blue", range = range(7, 10) } } },
      { editRange = { insert = range(0, 2), replace = range(0, 5) } },
      snapshot,
      client,
      7
    )
  )
  t.equal(item.textEdit.insert, range(7, 9, 0))
  t.equal(item.additionalTextEdits[1].range, range(14, 17, 0))
end)
for _, item in ipairs({
  { label = "x", insertTextFormat = 3 },
  { label = "x", insertTextMode = false },
  { label = "x", insertText = 1 },
  { label = "x", commitCharacters = { true } },
  { label = "x", additionalTextEdits = { [2] = {} } },
}) do
  t.test("malformed completion metadata " .. tostring(item), function()
    t.equal(completion.item(item, {}, snapshot, client, 0), nil)
  end)
end
t.test("sparse result lists are rejected", function()
  t.equal(completion.response({ items = { [2] = { label = "red" } } }, snapshot, client, 0).items, {})
end)
t.test("overlapping main and additional edits are rejected atomically", function()
  t.equal(
    completion.item({
      label = "color",
      textEdit = { newText = "color", range = range(0, 5) },
      additionalTextEdits = { { newText = "blue", range = range(3, 8) } },
    }, {}, snapshot, client, 7),
    nil
  )
  assert(completion.disjoint({ range(0, 5), range(5, 8) }))
  assert(not completion.disjoint({ range(2, 2), range(2, 2) }))
end)
t.test("completion envelope validation distinguishes empty success from malformed replies", function()
  assert(completion.valid_response({}))
  assert(completion.valid_response({ items = {}, isIncomplete = false }))
  assert(completion.valid_response({ { label = "red" } }))
  for _, value in ipairs({
    true,
    "invalid",
    { items = false },
    { items = { [2] = { label = "red" } } },
    { items = {}, isIncomplete = "invalid" },
    { items = {}, itemDefaults = false },
  }) do
    assert(not completion.valid_response(value))
    t.equal(completion.response(value, snapshot, client, 7).items, {})
  end
end)
t.test("custom configuration is normalized without sharing caller data or defaults", function()
  local input = {
    filetypes = { "typescript" },
    server_name = "custom_css",
    request_timeout_ms = 800,
    poll_interval_ms = 75,
    trigger_characters = { ":" },
    suppressed_lsp_clients = { "custom_ts" },
    hover = { border = "single", max_width = 80, max_height = 12 },
  }
  local configured, messages = config.normalize(input)
  t.equal(messages, {})
  for key, value in pairs(input) do
    t.equal(configured[key], value)
  end
  input.filetypes[1] = "changed"
  input.hover.max_width = 1
  t.equal(configured.filetypes, { "typescript" })
  t.equal(configured.hover.max_width, 80)
  configured.trigger_characters[1] = "changed"
  configured.suppressed_lsp_clients[1] = "changed"
  t.equal(config.normalize().trigger_characters, { ":", "-", " " })
  t.equal(config.normalize().suppressed_lsp_clients, { "vtsls", "tsgo" })
end)
for _, value in ipairs({
  { filetypes = false },
  { filetypes = { [2] = "typescript" } },
  { trigger_characters = { "" } },
  { trigger_characters = { 1 } },
  { suppressed_lsp_clients = "vtsls" },
  { server_name = "" },
  { server_name = false },
  { request_timeout_ms = 0 },
  { request_timeout_ms = -1 },
  { request_timeout_ms = 0 / 0 },
  { request_timeout_ms = math.huge },
  { request_timeout_ms = "5000" },
  { poll_interval_ms = 0 },
  { poll_interval_ms = 1.5 },
  { hover = false },
  { hover = { border = "invalid" } },
  { hover = { max_width = 0 } },
  { hover = { max_height = "12" } },
}) do
  t.test("invalid new configuration falls back independently " .. tostring(value), function()
    local configured, messages = config.normalize(value)
    assert(#messages > 0)
    t.equal(configured.filetypes, config.normalize().filetypes)
    t.equal(configured.server_name, "cssls")
    t.equal(configured.request_timeout_ms, 5000)
    t.equal(configured.poll_interval_ms, 20)
    t.equal(configured.trigger_characters, { ":", "-", " " })
    t.equal(configured.suppressed_lsp_clients, { "vtsls", "tsgo" })
    t.equal(configured.hover, { border = "rounded" })
  end)
end
t.test("empty configured lists disable their respective features", function()
  local configured, messages =
    config.normalize({ filetypes = {}, trigger_characters = {}, suppressed_lsp_clients = {} })
  t.equal(messages, {})
  t.equal(configured.filetypes, {})
  t.equal(configured.trigger_characters, {})
  t.equal(configured.suppressed_lsp_clients, {})
  assert(not regions.supports("typescript", "", configured.filetypes))
  assert(regions.supports("custom_ts", "", { "custom_ts" }))
  assert(not regions.supports("custom_ts", "nofile", { "custom_ts" }))
end)
t.test("invalid hover fields preserve valid sibling settings", function()
  local configured, messages = config.normalize({ hover = { border = "single", max_width = -1, max_height = 12 } })
  t.equal(#messages, 1)
  t.equal(configured.hover, { border = "single", max_height = 12 })
end)
t.test("cropped host snapshots preserve absolute Unicode mappings and multiline substitutions", function()
  local prefix = "const 😀 = css`"
  local host = { "header", prefix .. "color: ${", " fn('😀')", "}; padding: 1px;`;", "footer" }
  local value = {
    start_row = 1,
    start_col = #prefix,
    end_row = 3,
    end_col = #host[4] - 2,
    substitutions = { { start_row = 1, start_col = #prefix + 7, end_row = 3, end_col = 1, substitutions = {} } },
  }
  local full = document.build(host, value)
  local input = { host[2], host[3], host[4] }
  local cropped = document.build(input, value, 1)
  t.equal(cropped.lines, full.lines)
  t.equal(cropped.maps, full.maps)
  t.equal(cropped.host_start_row, 1)
  t.equal(#cropped.host_lines, 3)
  input[1] = "mutated"
  t.equal(cropped.host_lines[1], host[2])
  for _, encoding in ipairs({ "utf-8", "utf-16", "utf-32" }) do
    ---@cast encoding CssInJsEncoding
    for _, point in ipairs({ { 1, #prefix }, { 3, 3 } }) do
      local position = assert(document.position(cropped, point[1], point[2], encoding))
      t.equal(position, document.position(full, point[1], point[2], encoding))
      local edit_range = { start = position, ["end"] = position }
      t.equal(document.host_range(cropped, edit_range, encoding), document.host_range(full, edit_range, encoding))
      t.equal(assert(document.host_range(cropped, edit_range, encoding)).start, {
        line = point[1],
        character = coordinates.character(host[point[1] + 1], point[2], encoding),
      })
    end
  end
end)
local ok, err = pcall(t.run, "css-in-js core (without vim)")
_G.vim = host_vim
assert(ok, err)
