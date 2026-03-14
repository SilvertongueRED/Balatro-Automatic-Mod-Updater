local json = {}

local function decode_error(str, idx, msg)
  error(("JSON decode error at position %d: %s"):format(idx, msg))
end

local function skip_ws(str, idx)
  while true do
    local c = str:sub(idx, idx)
    if c == '' then return idx end
    if c == ' ' or c == '\t' or c == '\r' or c == '\n' then
      idx = idx + 1
    else
      return idx
    end
  end
end

local function decode_string(str, idx)
  idx = idx + 1
  local out = {}
  while true do
    local c = str:sub(idx, idx)
    if c == '' then decode_error(str, idx, "unterminated string") end
    if c == '"' then return table.concat(out), idx + 1 end
    if c == '\\' then
      local esc = str:sub(idx + 1, idx + 1)
      if esc == '' then decode_error(str, idx, "bad escape") end
      if esc == '"' or esc == '\\' or esc == '/' then table.insert(out, esc)
      elseif esc == 'b' then table.insert(out, '\b')
      elseif esc == 'f' then table.insert(out, '\f')
      elseif esc == 'n' then table.insert(out, '\n')
      elseif esc == 'r' then table.insert(out, '\r')
      elseif esc == 't' then table.insert(out, '\t')
      elseif esc == 'u' then
        local hex = str:sub(idx+2, idx+5)
        if #hex < 4 or not hex:match("^[0-9a-fA-F]+$") then decode_error(str, idx, "bad unicode escape") end
        local code = tonumber(hex, 16)
        if code <= 0x7F then
          table.insert(out, string.char(code))
        elseif code <= 0x7FF then
          table.insert(out, string.char(0xC0 + math.floor(code/0x40)))
          table.insert(out, string.char(0x80 + (code % 0x40)))
        elseif code <= 0xFFFF then
          table.insert(out, string.char(0xE0 + math.floor(code/0x1000)))
          table.insert(out, string.char(0x80 + (math.floor(code/0x40) % 0x40)))
          table.insert(out, string.char(0x80 + (code % 0x40)))
        else
          table.insert(out, '?')
        end
        idx = idx + 6
        goto continue
      else
        decode_error(str, idx, "invalid escape: \\" .. esc)
      end
      idx = idx + 2
    else
      table.insert(out, c)
      idx = idx + 1
    end
    ::continue::
  end
end

local function decode_number(str, idx)
  local s, e = str:find("^-?%d+%.?%d*[eE]?[+-]?%d*", idx)
  if not s then decode_error(str, idx, "invalid number") end
  local num = tonumber(str:sub(s, e))
  if num == nil then decode_error(str, idx, "invalid number") end
  return num, e + 1
end

local decode_value

local function decode_array(str, idx)
  idx = idx + 1
  local out = {}
  idx = skip_ws(str, idx)
  if str:sub(idx, idx) == ']' then return out, idx + 1 end
  local i = 1
  while true do
    local val; val, idx = decode_value(str, idx)
    out[i] = val; i = i + 1
    idx = skip_ws(str, idx)
    local c = str:sub(idx, idx)
    if c == ',' then idx = skip_ws(str, idx + 1)
    elseif c == ']' then return out, idx + 1
    else decode_error(str, idx, "expected , or ]") end
  end
end

local function decode_object(str, idx)
  idx = idx + 1
  local out = {}
  idx = skip_ws(str, idx)
  if str:sub(idx, idx) == '}' then return out, idx + 1 end
  while true do
    if str:sub(idx, idx) ~= '"' then decode_error(str, idx, "expected string key") end
    local key; key, idx = decode_string(str, idx)
    idx = skip_ws(str, idx)
    if str:sub(idx, idx) ~= ':' then decode_error(str, idx, "expected :") end
    idx = skip_ws(str, idx + 1)
    local val; val, idx = decode_value(str, idx)
    out[key] = val
    idx = skip_ws(str, idx)
    local c = str:sub(idx, idx)
    if c == ',' then idx = skip_ws(str, idx + 1)
    elseif c == '}' then return out, idx + 1
    else decode_error(str, idx, "expected , or }") end
  end
end

decode_value = function(str, idx)
  idx = skip_ws(str, idx)
  local c = str:sub(idx, idx)
  if c == '' then decode_error(str, idx, "unexpected end") end
  if c == '"' then return decode_string(str, idx) end
  if c == '{' then return decode_object(str, idx) end
  if c == '[' then return decode_array(str, idx) end
  if c == '-' or c:match("%d") then return decode_number(str, idx) end
  if str:sub(idx, idx+3) == "true" then return true, idx + 4 end
  if str:sub(idx, idx+4) == "false" then return false, idx + 5 end
  if str:sub(idx, idx+3) == "null" then return nil, idx + 4 end
  decode_error(str, idx, "unexpected token")
end

function json.decode(str)
  if type(str) ~= "string" then error("json.decode expects string") end
  local val, idx = decode_value(str, 1)
  idx = skip_ws(str, idx)
  if idx <= #str then decode_error(str, idx, "trailing garbage") end
  return val
end

return json