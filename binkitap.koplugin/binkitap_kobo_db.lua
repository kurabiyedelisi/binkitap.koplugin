--[[--
Read-only access to the Kobo (Nickel) database, KoboReader.sqlite.

Tables used:
  content      - one row per book (ContentType 6): title, reading status, percent
  Bookmark     - highlights, notes and dog-ears made in the Kobo reader
  Shelf        - the user's collections ("listeler")
  ShelfContent - which book is in which collection

Nothing is ever written to the Kobo database.
--]]

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local KUtil = require("binkitap_kobo_util")

local unpack = rawget(_G, "unpack") or table.unpack

local KoboDB = {}

KoboDB.DEFAULT_PATH = "/mnt/onboard/.kobo/KoboReader.sqlite"

local function notDeleted(col)
    return string.format("lower(COALESCE(%s, 'false')) NOT IN ('true', '1')", col)
end

local function num(v)
    if v == nil then return nil end
    return tonumber(v)
end

local function str(v)
    if v == nil then return nil end
    if type(v) == "string" then return v end
    local n = tonumber(v)
    return n and tostring(n) or tostring(v)
end

--- SQL for books (sideloaded files only: Kobo store books can't be opened by KOReader).
KoboDB.SQL_BOOKS = [[
SELECT ContentID, Title, Attribution, ReadStatus, ___PercentRead, DateLastRead, ChapterIDBookmarked
FROM content
WHERE ContentType = 6 AND ContentID LIKE 'file://%']]

--- SQL for highlights/notes/dog-ears. Optional columns differ between firmware versions.
function KoboDB.bookmarkSql(cols, one_volume)
    local select_type = cols.Type and "Type" or "NULL"
    local where = { "VolumeID LIKE 'file://%'" }
    if cols.Hidden then
        table.insert(where, notDeleted("Hidden"))
    end
    if one_volume then
        table.insert(where, "VolumeID = ?")
    end
    return string.format([[
SELECT BookmarkID, VolumeID, ContentID, StartContainerPath, Text, Annotation, DateCreated, ChapterProgress, %s
FROM Bookmark
WHERE %s
ORDER BY VolumeID, ChapterProgress]], select_type, table.concat(where, " AND "))
end

function KoboDB.shelfSql(cols)
    local where = cols._IsDeleted and (" WHERE " .. notDeleted("_IsDeleted")) or ""
    return "SELECT Name, InternalName FROM Shelf" .. where
end

function KoboDB.shelfContentSql(cols)
    local where = { "ContentId LIKE 'file://%'" }
    if cols._IsDeleted then
        table.insert(where, notDeleted("_IsDeleted"))
    end
    return "SELECT ShelfName, ContentId FROM ShelfContent WHERE " .. table.concat(where, " AND ")
end

local function eachRow(conn, sql, binds, fn)
    local stmt = conn:prepare(sql)
    local ok, err = pcall(function()
        if binds and #binds > 0 then
            stmt:bind(unpack(binds))
        end
        while true do
            local row = stmt:step()
            if not row then break end
            fn(row)
        end
    end)
    stmt:close()
    if not ok then error(err, 0) end
end

local function columns(conn, tbl)
    local cols = {}
    local found = false
    pcall(eachRow, conn, "PRAGMA table_info(" .. tbl .. ")", nil, function(row)
        if row[2] then
            cols[row[2]] = true
            found = true
        end
    end)
    return found and cols or nil
end

function KoboDB.exists(path)
    return path and lfs.attributes(path, "mode") == "file"
end

--- A string that changes whenever Nickel has written to the database.
function KoboDB.signature(path)
    local a = path and lfs.attributes(path)
    if not a then return nil end
    local w = lfs.attributes(path .. "-wal")
    return string.format("%d:%d:%d:%d", a.modification or 0, a.size or 0,
        w and w.modification or 0, w and w.size or 0)
end

local function bookmarkKind(text, note, btype)
    btype = btype and btype:lower() or nil
    if btype == "markup" then
        return nil -- stylus drawings: nothing KOReader can show
    end
    if text ~= "" then
        return "highlight"
    end
    if btype == nil or btype == "" or btype == "dogear" or note ~= "" then
        return "dogear"
    end
    return nil
end

--- Reads what the plugin needs.
-- opts.file: only this book (path as KOReader sees it)
-- opts.books / opts.bookmarks / opts.shelves: which parts to read (all if none given)
-- Returns data = { books = {[file]=book}, annotations = {[file]={rec,...}},
--                  shelves = {[name]={file,...}}, errors = {} }, or nil, error
function KoboDB.read(path, opts)
    opts = opts or {}
    local want_all = not (opts.books or opts.bookmarks or opts.shelves)
    local data = { books = {}, annotations = {}, shelves = {}, errors = {} }

    if not KoboDB.exists(path) then
        return nil, "not_found"
    end
    -- "rw" (not "ro") so that SQLite can replay a write-ahead log left behind
    -- when Nickel was stopped to start KOReader. We only run SELECT statements.
    local SQ3 = require("lua-ljsqlite3/init")
    local ok_open, conn = pcall(SQ3.open, path, "rw")
    if not ok_open or not conn then
        logger.warn("KoboSync: cannot open Kobo database:", conn)
        return nil, tostring(conn)
    end

    local volume = opts.file and ("file://" .. opts.file) or nil

    if want_all or opts.books then
        local ok, err = pcall(function()
            local sql = KoboDB.SQL_BOOKS
            local binds
            if volume then
                sql = sql .. " AND ContentID = ?"
                binds = { volume }
            end
            eachRow(conn, sql, binds, function(row)
                local file = KUtil.fileFromContentId(row[1])
                if file then
                    data.books[file] = {
                        file = file,
                        content_id = row[1],
                        title = str(row[2]),
                        author = str(row[3]),
                        read_status = num(row[4]) or 0,
                        percent = num(row[5]) or 0,
                        date_last_read = str(row[6]),
                        chapter_bookmarked = str(row[7]),
                    }
                end
            end)
        end)
        if not ok then
            logger.warn("KoboSync: reading books failed:", err)
            table.insert(data.errors, "books: " .. tostring(err))
        end
    end

    if want_all or opts.bookmarks then
        local ok, err = pcall(function()
            local cols = columns(conn, "Bookmark")
            if not cols then return end
            local binds = volume and { volume } or nil
            eachRow(conn, KoboDB.bookmarkSql(cols, volume ~= nil), binds, function(row)
                local file = KUtil.fileFromContentId(row[2])
                if not file then return end
                local raw_text = str(row[5]) or ""
                local text = KUtil.normalize(raw_text)
                local note = KUtil.cleanupText(str(row[6]) or "") or ""
                local kind = bookmarkKind(text, note, str(row[9]))
                if not kind then return end
                local rec = {
                    id = str(row[1]),
                    file = file,
                    content_id = str(row[3]),
                    start_path = str(row[4]),
                    raw_text = raw_text,
                    text = text,
                    note = note ~= "" and note or nil,
                    created = str(row[7]),
                    progress = num(row[8]),
                    kind = kind,
                }
                rec.href = KUtil.hrefFromBookmark(rec.start_path, rec.content_id)
                if rec.id then
                    local list = data.annotations[file]
                    if not list then
                        list = {}
                        data.annotations[file] = list
                    end
                    table.insert(list, rec)
                end
            end)
        end)
        if not ok then
            logger.warn("KoboSync: reading bookmarks failed:", err)
            table.insert(data.errors, "bookmarks: " .. tostring(err))
        end
    end

    if (want_all or opts.shelves) and not volume then
        local ok, err = pcall(function()
            local shelf_cols = columns(conn, "Shelf")
            local content_cols = columns(conn, "ShelfContent")
            if not content_cols then return end
            local names -- InternalName -> display name
            if shelf_cols then
                names = {}
                eachRow(conn, KoboDB.shelfSql(shelf_cols), nil, function(row)
                    local name = str(row[1])
                    local internal = str(row[2]) or name
                    if internal then
                        names[internal] = (name and name ~= "") and name or internal
                    end
                end)
            end
            eachRow(conn, KoboDB.shelfContentSql(content_cols), nil, function(row)
                local shelf = str(row[1])
                local file = KUtil.fileFromContentId(str(row[2]))
                if not shelf or shelf == "" or not file then return end
                local display = names and names[shelf] or (not names and shelf) or nil
                if not display then return end -- shelf was deleted on the Kobo
                local list = data.shelves[display]
                if not list then
                    list = {}
                    data.shelves[display] = list
                end
                table.insert(list, file)
            end)
        end)
        if not ok then
            logger.warn("KoboSync: reading shelves failed:", err)
            table.insert(data.errors, "shelves: " .. tostring(err))
        end
    end

    pcall(function() conn:close() end)
    return data
end

return KoboDB
