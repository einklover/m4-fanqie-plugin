-- Shared low-memory guard for Murphy M4 Lua plugins.
-- The sandbox budget is ~512 KiB. Large network bodies, decoded chapter text
-- and JSON tables must never overlap longer than one cooperative step.
LowMem = LowMem or {}
LowMem.LUA_LIMIT_KB = 512
LowMem.BACKGROUND_MIN_FREE_KB = 160
LowMem.FOREGROUND_MIN_FREE_KB = 96
LowMem._foreground = false
function LowMem.used_kb()
  if type(collectgarbage) ~= "function" then return 0 end
  local ok, n = pcall(collectgarbage, "count")
  if ok and type(n) == "number" then return n end
  return 0
end
function LowMem.free_kb()
  local used = LowMem.used_kb()
  if used <= 0 then return LowMem.LUA_LIMIT_KB end
  return math.max(0, LowMem.LUA_LIMIT_KB - used)
end
function LowMem.soft_gc()
  if type(collectgarbage) == "function" then pcall(collectgarbage, "step", 96) end
end
function LowMem.hard_gc()
  if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
end
function LowMem.before_heavy() LowMem.hard_gc(); return LowMem.free_kb() end
function LowMem.after_heavy() LowMem.soft_gc(); return LowMem.free_kb() end
function LowMem.can_background(min_free_kb)
  local need = tonumber(min_free_kb) or LowMem.BACKGROUND_MIN_FREE_KB
  local free = LowMem.free_kb()
  if free < need + 24 then LowMem.soft_gc(); free = LowMem.free_kb() end
  return free >= need, free
end
function LowMem.can_foreground(min_free_kb)
  local need = tonumber(min_free_kb) or LowMem.FOREGROUND_MIN_FREE_KB
  local free = LowMem.free_kb()
  if free < need then LowMem.hard_gc(); free = LowMem.free_kb() end
  return free >= need, free
end
function LowMem.set_foreground(v) LowMem._foreground = v and true or false end
function LowMem.drop(obj, fields, hard)
  if type(obj) == "table" and type(fields) == "table" then
    for i = 1, #fields do obj[fields[i]] = nil end
  end
  if hard then LowMem.hard_gc() else LowMem.soft_gc() end
end
function LowMem.install_api(Api)
  if type(Api) ~= "table" or Api.__lowmem_wrapped then return end
  Api.__lowmem_wrapped = true
  local function wrap(name)
    local raw = Api[name]
    if type(raw) ~= "function" then return end
    Api[name] = function(...)
      if not LowMem._foreground then
        local ok = LowMem.can_background()
        if not ok then return nil, "lowmem_defer" end
      else
        LowMem.can_foreground()
      end
      local results = table.pack(pcall(raw, ...))
      LowMem.after_heavy()
      if not results[1] then return nil, "api_exception:" .. tostring(results[2]) end
      return table.unpack(results, 2, results.n)
    end
  end
  wrap("fetch_chapter_text")
  wrap("fetch_chapter_to_file")
end
return LowMem
