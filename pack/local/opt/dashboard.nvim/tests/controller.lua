local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local t = require("support")
local fixtures = require("fixtures")
local host_vim = rawget(_G, "vim")
_G.vim = nil

---@return DashboardOptions
local function options()
  return {
    blocks = {
      {
        id = "menu",
        type = "actions",
        items = {
          { id = "one", label = "One", key = "f", run = "echo 1" },
          { id = "two", label = "Two", key = "s", run = "echo 2" },
        },
      },
    },
  }
end

t.test("setup required; repeated setup does not install twice", function()
  local f = fixtures.new()
  f.api.show()
  t.equal(#f.errors, 1)
  f.api.setup(options())
  f.api.setup(options())
  t.equal(f.installs, 1)
  f.api.hide()
  f.api.teardown()
  f.api.teardown()
end)

t.test("windows and controller instances have independent sessions", function()
  local f, other = fixtures.new(), fixtures.new()
  f.api.setup(options())
  other.api.setup(options())
  f.api.show(1)
  f.api.show(2)
  other.api.show(1)
  local first = f.live[1]
  f.api.show(1)
  assert(f.live[1] == first)
  f.api.move(2, 1)
  t.equal(f.live[1].selected.id, "one")
  t.equal(f.live[2].selected.id, "two")
  t.equal(other.live[1].selected.id, "one")
  f.api.hide(2)
  assert(f.live[1] and not f.live[2])
  t.equal(#f.errors, 0)
end)

t.test("refresh retains selection by identity and source context", function()
  local f = fixtures.new()
  f.api.setup(options())
  f.api.show()
  f.api.move(1, 1)
  f.contexts[1].height = 20
  f.api.refresh()
  t.equal(f.live[1].selected.id, "two")
  local selected_source
  f.api.setup({
    blocks = {
      {
        id = "menu",
        type = "actions",
        items = {
          {
            id = "two",
            label = "Changed",
            run = function(ctx)
              selected_source = ctx.source_buf
            end,
          },
        },
      },
    },
  })
  f.api.activate(1)
  t.equal(selected_source, 1001)
  t.equal(f.live[1].selected.id, "two")
end)

t.test("theme updates never call content providers or rewrite documents", function()
  local f = fixtures.new()
  local calls, color = 0, "#123456"
  f.api.setup({
    blocks = {
      {
        id = "title",
        type = "text",
        lines = function()
          calls = calls + 1
          return { "hello" }
        end,
      },
    },
    highlights = function()
      return { Header = { fg = color } }
    end,
  })
  f.api.show()
  local writes = f.writes
  color = "#abcdef"
  f.api.theme()
  t.equal(calls, 1)
  t.equal(f.writes, writes)
  t.equal(f.styles.Header.fg, color)
end)

t.test("custom block adds styles and actions using the common document contract", function()
  local f = fixtures.new()
  local count = 0
  f.api.setup({
    blocks = {
      {
        id = "project",
        type = "custom",
        render = function(ctx)
          assert(ctx.source_buf == 1001)
          return {
            lines = { "Project" },
            spans = { { row = 0, start_col = 0, end_col = 7, style = "Project" } },
            targets = {
              {
                id = "open",
                row = 0,
                col = 0,
                key = "p",
                run = function()
                  count = count + 1
                end,
              },
            },
          }
        end,
      },
    },
  })
  f.api.show()
  f.api.activate(1, "project", "open")
  t.equal(count, 1)
  f.api.hide()
  f.api.show()
  f.api.activate(1)
  t.equal(count, 2)
end)

t.test("provider and validation failures preserve the current document", function()
  local f = fixtures.new()
  f.api.setup(options())
  f.api.show()
  local doc = f.live[1].document
  f.api.setup({
    blocks = {
      {
        id = "bad",
        type = "text",
        lines = function()
          error("provider failed")
        end,
      },
    },
  })
  assert(f.live[1].document == doc)
  f.api.refresh()
  t.equal(f.live[1].document, doc)
  t.equal(#f.errors, 1)
end)

t.test("render and creation failures do not leak a session", function()
  for _, operation in ipairs({ "create", "apply" }) do
    local f = fixtures.new()
    f.api.setup(options())
    ---@cast operation "create" | "apply"
    f.fail = operation
    f.api.show()
    assert(not f.live[1])
    t.equal(#f.errors, 1)
    f.api.show()
    assert(f.live[1])
  end
end)

t.test("failed setup application rolls back options, styles and documents", function()
  local f = fixtures.new()
  f.api.setup(options())
  f.api.show()
  local previous = f.configured
  f.fail = "apply"
  f.api.setup({ blocks = { { id = "new", type = "text", lines = { "different" } } } })
  assert(f.configured == previous)
  t.equal(f.live[1].selected.id, "one")
  t.equal(#f.errors, 1)
end)

t.test("invalid targeted activation does not execute a different action", function()
  local f = fixtures.new()
  f.api.setup(options())
  f.api.show()
  f.api.activate(1, "menu", "missing")
  t.equal(f.commands, {})
  f.api.activate(1, "menu", "two")
  t.equal(f.commands, { "echo 2" })
end)

t.test("actions may call the public API and their errors are contained", function()
  local f = fixtures.new()
  f.api.setup({
    blocks = {
      {
        id = "menu",
        type = "actions",
        items = {
          {
            id = "close",
            label = "Close",
            run = function()
              f.api.hide()
            end,
          },
        },
      },
    },
  })
  f.api.show()
  f.api.activate(1)
  assert(not f.live[1])
  f.api.setup({
    blocks = {
      {
        id = "menu",
        type = "actions",
        items = {
          {
            id = "fail",
            label = "Fail",
            run = function()
              error("action failed")
            end,
          },
        },
      },
    },
  })
  f.api.show()
  f.api.activate(1)
  assert(f.live[1])
  t.equal(#f.errors, 1)
end)

t.test("queued events coalesce and are cancelled by teardown", function()
  local f = fixtures.new()
  f.api.setup(options())
  f.api.show()
  f.api.changed()
  f.api.changed()
  t.equal(#f.queue, 1)
  f.api.teardown()
  f.aliases = { 2 }
  fixtures.flush(f)
  assert(not f.live[2])
  t.equal(#f.errors, 0)
end)

t.test("failed first render keeps ownership when cleanup fails and hide or teardown can retry", function()
  for _, cleanup in ipairs({ "hide", "teardown" }) do
    local f = fixtures.new()
    f.api.setup({
      blocks = {
        {
          id = "bad",
          type = "text",
          lines = function()
            error("provider failed")
          end,
        },
      },
    })
    f.fail = "close"
    f.api.show()
    assert(f.live[1])
    assert(f.errors[1]:find("provider failed", 1, true))
    assert(f.errors[1]:find("cleanup failed", 1, true))
    f.api[cleanup]()
    assert(not f.live[1])
  end
end)

t.test("failure after creation is tracked before returning from the adapter", function()
  local f = fixtures.new()
  f.api.setup(options())
  local create = f.adapter.create
  f.adapter.create = function(ctx, track)
    create(ctx, track)
    error("creation failed after allocation")
  end
  f.fail = "close"
  f.api.show()
  assert(f.live[1])
  f.api.teardown()
  assert(not f.live[1])
end)

t.test("refresh isolates both provider and application failures by window", function()
  for _, failure in ipairs({ "provider", "apply" }) do
    local f = fixtures.new()
    local word, failing = "Before", false
    f.api.setup({
      blocks = {
        {
          id = "title",
          type = "text",
          lines = function(ctx)
            if failing and failure == "provider" and ctx.win == 1 then
              error("provider failed")
            end
            return { word }
          end,
        },
      },
    })
    f.api.show(1)
    f.api.show(2)
    local original = f.live[1].document
    local apply = f.adapter.apply
    f.adapter.apply = function(session, document, selected)
      if failing and failure == "apply" and session.win == 1 then
        error("application failed")
      end
      apply(session, document, selected)
    end
    word, failing = "After!", true
    f.api.refresh()
    assert(f.live[1].document == original)
    assert(table.concat(f.live[2].document.lines):find("After!", 1, true))
    t.equal(#f.errors, 1)
    assert(f.errors[1]:find("window 1", 1, true))
  end
end)

t.test("cleanup failure keeps resources tracked for retry", function()
  local f = fixtures.new()
  f.api.setup(options())
  f.api.show()
  f.fail = "close"
  f.api.hide()
  assert(f.live[1])
  f.api.hide()
  assert(not f.live[1])
  t.equal(#f.errors, 1)
end)

t.test("conditional blocks skip providers and margins and can return on resize", function()
  local f = fixtures.new()
  local calls = 0
  f.contexts[1] = { win = 1, source_buf = 1001, width = 10, height = 5 }
  f.api.setup({
    layout = { horizontal = "left", vertical = "top", gap = 1 },
    blocks = {
      {
        id = "header",
        type = "text",
        enabled = function(ctx)
          return ctx.width >= 20
        end,
        layout = { gap_before = 2, gap_after = 2 },
        lines = function()
          calls = calls + 1
          return { "Header" }
        end,
      },
      {
        id = "hidden",
        type = "custom",
        enabled = false,
        render = function()
          error("must not render")
        end,
      },
      { id = "menu", type = "actions", items = { { id = "a", label = "A", run = "" } } },
    },
  })
  f.api.show()
  t.equal(f.live[1].document.lines, { "A" })
  t.equal(calls, 0)
  f.contexts[1].width = 20
  f.api.refresh()
  t.equal(calls, 1)
  t.equal(f.live[1].document.lines, { "", "", "Header", "", "", "", "A" })
  t.equal(f.live[1].selected.id, "a")
end)

t.test("invalid visibility result preserves the document during refresh", function()
  local f = fixtures.new()
  local invalid = false
  f.api.setup({
    blocks = {
      {
        id = "title",
        type = "text",
        lines = { "Hello" },
        enabled = function()
          if invalid then
            error("visibility failed")
          end
          return true
        end,
      },
    },
  })
  f.api.show()
  local previous = f.live[1].document
  invalid = true
  f.api.refresh()
  assert(f.live[1].document == previous)
  t.equal(#f.errors, 1)
  f.api.setup({
    blocks = {
      {
        id = "bad",
        type = "text",
        lines = {},
        enabled = function()
          ---@diagnostic disable-next-line: return-type-mismatch
          return nil
        end,
      },
    },
  })
  assert(f.live[1].document == previous)
  t.equal(#f.errors, 2)
end)

t.test("each build measures distinct strings once without caching providers or display settings", function()
  local f = fixtures.new()
  local widths, calls, providers = {}, 0, 0
  local scale = 1
  f.adapter.measure = function(text)
    widths[text] = (widths[text] or 0) + 1
    calls = calls + 1
    return #text * scale
  end
  f.api.setup({
    layout = { vertical = "top" },
    blocks = {
      { id = "title", type = "text", lines = { "Same", "Same", "" } },
      {
        id = "menu",
        type = "actions",
        spacing = 0,
        items = function()
          providers = providers + 1
          return { { id = "a", label = "Same", run = "" }, { id = "b", label = "Same", run = "" } }
        end,
      },
    },
  })
  f.api.show()
  t.equal(widths, { Same = 1, [""] = 1 })
  t.equal(calls, 2)
  local original = f.live[1].document.lines[1]
  widths = {}
  scale = 2
  f.api.refresh()
  t.equal(widths, { Same = 1, [""] = 1 })
  t.equal(providers, 2)
  assert(original ~= f.live[1].document.lines[1], "new display widths must change centering")
  widths = {}
  f.api.show(2)
  t.equal(widths, { Same = 1, [""] = 1 })
  t.equal(providers, 3)
  t.equal(#f.errors, 0)
end)

t.test("misplaced options and invalid custom Unicode offsets preserve the live document", function()
  local f = fixtures.new()
  f.api.setup(options())
  f.api.show()
  local previous = f.live[1].document
  local invalid = options()
  ---@diagnostic disable-next-line: inject-field
  invalid.blocks[1].offset_x = 100
  f.api.setup(invalid)
  assert(f.live[1].document == previous)
  t.equal(#f.errors, 1)
  assert(f.errors[1]:find("unknown block option: offset_x", 1, true))
  f.api.setup({
    blocks = {
      {
        id = "bad",
        type = "custom",
        render = function()
          return { lines = { "界" }, spans = {}, targets = { { id = "a", row = 0, col = 1, run = "" } } }
        end,
      },
    },
  })
  assert(f.live[1].document == previous)
  t.equal(#f.errors, 2)
end)

t.run("Dashboard controller")
_G.vim = host_vim
