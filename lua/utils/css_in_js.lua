local M = {}
local api = vim.api
local filetypes = { javascript = true, javascriptreact = true, typescript = true, typescriptreact = true }

function M.supports_buffer(buf)
  return filetypes[vim.bo[buf].filetype] and vim.bo[buf].buftype == "" and not vim.b[buf].bigfile
end

-- Use the host syntax tree so ${...} stays with the TypeScript server.
-- Injection ranges identify tagged templates, including generics and attrs().
function M.context(buf, row, col)
  if not M.supports_buffer(buf) then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return nil
  end
  parser:parse(true)
  local tree = parser:trees()[1]
  local styled = parser:children().styled
  if not tree or not styled then
    return nil
  end
  local node = tree:root():named_descendant_for_range(row, col, row, col)
  while node do
    if node:type() == "template_substitution" then
      return nil
    elseif node:type() == "template_string" then
      local sr, sc = node:range()
      for _, regions in pairs(styled:included_regions()) do
        for _, range in ipairs(regions) do
          local er, ec = range[4], range[5]
          if range[1] == sr and range[2] == sc + 1 then
            if (row > sr or col >= sc + 1) and (row < er or col <= ec) then
              return { node = node, start_row = sr, start_col = sc + 1, end_row = er, end_col = ec }
            end
          end
        end
      end
      return nil
    end
    node = node:parent()
  end
end

-- Extract only the active template. Mask substitutions from right to left so
-- byte offsets remain valid, preserving UTF-16 widths for CSS LSP positions.
function M.document(buf, region)
  local sr, sc = region.start_row, region.start_col
  local lines = api.nvim_buf_get_text(buf, sr, sc, region.end_row, region.end_col, {})
  for i = region.node:named_child_count() - 1, 0, -1 do
    local child = region.node:named_child(i)
    if child:type() == "template_substitution" then
      local fr, fc, tr, tc = child:range()
      local before = table.concat(api.nvim_buf_get_text(buf, sr, sc, fr, fc, {}), "\n")
      local declaration = before:match("[^;{}]*$") or ""
      local placeholder = declaration:find(":", 1, true) and "0" or ";"
      for row = fr, tr do
        local index = row - sr + 1
        local first = row == fr and fc - (row == sr and sc or 0) or 0
        local last = row == tr and tc - (row == sr and sc or 0) or #lines[index]
        local width = vim.str_utfindex(lines[index]:sub(first + 1, last), "utf-16")
        local replacement = string.rep(" ", width)
        if row == fr and width > 0 then
          replacement = placeholder .. replacement:sub(2)
        end
        lines[index] = lines[index]:sub(1, first) .. replacement .. lines[index]:sub(last + 1)
      end
    end
  end
  table.insert(lines, 1, "a{")
  lines[#lines + 1] = ";}"
  return lines
end

-- The wrapper adds one line; only the first content line has a column offset.
function M.host_range(range, region, column_offset)
  local mapped = vim.deepcopy(range)
  for _, position in ipairs({ mapped.start, mapped["end"] }) do
    if position.line < 1 or position.line > region.end_row - region.start_row + 1 then
      return nil
    end
    if position.line == 1 then
      position.character = position.character + column_offset
    end
    position.line = position.line + region.start_row - 1
  end
  return mapped
end

return M
