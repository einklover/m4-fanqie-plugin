-- Durable chapter-cache guard. Formal chapter files are readable only after
-- an explicit .ok marker, so interrupted progressive writes are never mistaken
-- for a complete chapter on the next launch.
CacheGuard = CacheGuard or {}
function CacheGuard.install(Storage, opts)
  if type(Storage) ~= "table" or Storage.__cache_guard_v2 then return end
  opts = opts or {}
  Storage.__cache_guard_v2 = true
  local legacy_atomic = opts.legacy_atomic and true or false
  if type(Storage.chapter_ok_path) ~= "function" then
    function Storage.chapter_ok_path(bookId, chapterUid)
      return Storage.chapter_path(bookId, chapterUid) .. ".ok"
    end
  end
  if type(Storage.mark_chapter_complete) ~= "function" then
    function Storage.mark_chapter_complete(bookId, chapterUid)
      if type(fs) ~= "table" or type(fs.writeFile) ~= "function" then return false end
      return fs.writeFile(Storage.chapter_ok_path(bookId, chapterUid), "1") and true or false
    end
  end
  if type(Storage.clear_chapter_complete) ~= "function" then
    function Storage.clear_chapter_complete(bookId, chapterUid)
      local p = Storage.chapter_ok_path(bookId, chapterUid)
      if type(fs) == "table" and type(fs.remove) == "function" then pcall(fs.remove, p)
      elseif type(fs) == "table" and type(fs.writeFile) == "function" then pcall(fs.writeFile, p, "") end
    end
  end
  if type(Storage.chapter_complete) ~= "function" then
    function Storage.chapter_complete(bookId, chapterUid)
      if not bookId or tostring(bookId) == "" or not chapterUid or tostring(chapterUid) == "" then return false end
      local n = Storage.chapter_file_size and tonumber(Storage.chapter_file_size(bookId, chapterUid) or 0) or 0
      if n < 1 then return false end
      local okn = 0
      if type(fs) == "table" and type(fs.fileSize) == "function" then
        okn = tonumber(fs.fileSize(Storage.chapter_ok_path(bookId, chapterUid)) or 0) or 0
      end
      if okn > 0 then return true end
      if legacy_atomic then Storage.mark_chapter_complete(bookId, chapterUid); return true end
      return false
    end
  end
  if type(Storage.clear_chapter_cache) ~= "function" then
    function Storage.clear_chapter_cache(bookId, chapterUid)
      local p, okp = Storage.chapter_path(bookId, chapterUid), Storage.chapter_ok_path(bookId, chapterUid)
      if type(fs) == "table" and type(fs.remove) == "function" then pcall(fs.remove, p); pcall(fs.remove, okp)
      elseif type(fs) == "table" and type(fs.writeFile) == "function" then pcall(fs.writeFile, p, ""); pcall(fs.writeFile, okp, "") end
    end
  end
  if type(Storage.save_chapter_text) == "function" and not Storage.__cache_guard_save then
    Storage.__cache_guard_save = Storage.save_chapter_text
    Storage.save_chapter_text = function(bookId, chapterUid, text)
      Storage.clear_chapter_complete(bookId, chapterUid)
      local ok = Storage.__cache_guard_save(bookId, chapterUid, text)
      if ok then Storage.mark_chapter_complete(bookId, chapterUid) end
      return ok
    end
  end
  Storage.chapter_body_ready = function(bookId, chapterUid) return Storage.chapter_complete(bookId, chapterUid) end
  Storage.chapter_ready = Storage.chapter_body_ready
end
return CacheGuard
