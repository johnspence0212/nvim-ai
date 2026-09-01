local M = {}

local function push_seg(segs, text, hl)
  if text == "" then
    return
  end
  local last = segs[#segs]
  if last and last.hl == hl then
    last.text = last.text .. text
    return
  end
  segs[#segs + 1] = { text = text, hl = hl }
end

local function find_next(s, i)
  local n = #s
  local best
  local function consider(pos)
    if pos and (not best or pos < best) then
      best = pos
    end
  end
  consider(s:find("`", i, true))
  consider(s:find("**", i, true))
  local star = s:find("*", i, true)
  if star and s:sub(star, star + 1) ~= "**" then
    consider(star)
  end
  return best or (n + 1)
end

local function parse_inlines(s)
  local segs = {}
  local i = 1
  local n = #s
  while i <= n do
    local ch = s:sub(i, i)
    if ch == "`" then
      local j = s:find("`", i + 1, true)
      if j then
        push_seg(segs, s:sub(i + 1, j - 1), "NaiMdCode")
        i = j + 1
      else
        push_seg(segs, "`", nil)
        i = i + 1
      end
    elseif s:sub(i, i + 1) == "**" then
      local j = s:find("**", i + 2, true)
      if j then
        push_seg(segs, s:sub(i + 2, j - 1), "NaiMdBold")
        i = j + 2
      else
        push_seg(segs, "**", nil)
        i = i + 2
      end
    elseif ch == "*" then
      local prev = i > 1 and s:sub(i - 1, i - 1) or ""
      if prev:match("[%w]") then
        push_seg(segs, "*", nil)
        i = i + 1
      else
        local j = s:find("*", i + 1, true)
        if j and j > i + 1 then
          push_seg(segs, s:sub(i + 1, j - 1), "NaiMdItalic")
          i = j + 1
        else
          push_seg(segs, "*", nil)
          i = i + 1
        end
      end
    else
      local stop = find_next(s, i)
      push_seg(segs, s:sub(i, stop - 1), nil)
      i = stop
    end
  end
  return segs
end

local function emit_line(out, marks, segs, line_hl)
  local col = 0
  local parts = {}
  local row = #out
  for _, seg in ipairs(segs) do
    parts[#parts + 1] = seg.text
    local start = col
    col = col + #seg.text
    local hl = seg.hl or line_hl
    if hl and start < col then
      marks[#marks + 1] = { row = row, col = start, end_col = col, hl = hl }
    end
  end
  local text = table.concat(parts)
  if line_hl and text ~= "" then
    marks[#marks + 1] = { row = row, col = 0, end_col = #text, hl = line_hl }
  end
  out[#out + 1] = text
end

function M.render(src)
  local raw = vim.split(src, "\n", { plain = true })
  local out = {}
  local marks = {}
  local i = 1
  while i <= #raw do
    local line = raw[i]
    if line:match("^```") then
      local body = {}
      i = i + 1
      while i <= #raw and not raw[i]:match("^```") do
        body[#body + 1] = raw[i]
        i = i + 1
      end
      if i <= #raw then
        i = i + 1
      end
      local function fence_line(text)
        local row = #out
        out[#out + 1] = "  " .. text
        marks[#marks + 1] = { row = row, line = true, hl = "NaiMdFence" }
      end
      fence_line("")
      for _, body_line in ipairs(body) do
        fence_line(body_line)
      end
      fence_line("")
    elseif line:match("^|") or line:match("^!%[") then
      out[#out + 1] = line
      i = i + 1
    else
      local hashes, heading = line:match("^(#+)%s+(.*)$")
      local list_indent, list_rest = line:match("^(%s*)[-*+]%s+(.*)$")
      local num_indent, numbered, numbered_rest = line:match("^(%s*)(%d+%. )(.*)$")
      if hashes and #hashes >= 1 and #hashes <= 6 then
        emit_line(out, marks, parse_inlines(heading), "NaiMdHeading")
      elseif list_rest then
        local segs = { { text = list_indent .. "• ", hl = "NaiMdList" } }
        for _, seg in ipairs(parse_inlines(list_rest)) do
          segs[#segs + 1] = seg
        end
        emit_line(out, marks, segs)
      elseif numbered then
        local segs = { { text = (num_indent or "") .. numbered, hl = "NaiMdList" } }
        for _, seg in ipairs(parse_inlines(numbered_rest)) do
          segs[#segs + 1] = seg
        end
        emit_line(out, marks, segs)
      else
        emit_line(out, marks, parse_inlines(line))
      end
      i = i + 1
    end
  end
  if #out == 0 then
    out[1] = ""
  end
  return out, marks
end

return M
