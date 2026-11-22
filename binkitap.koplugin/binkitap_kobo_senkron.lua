--[[--
Kobo Senkron (1000Kitap eklentisinin Kobo bölümü; önceden ayrı kobosync.koplugin eklentisiydi).
Kobo Senkron: brings what was done in the Kobo's own reader (Nickel) into KOReader.

  * highlights, notes and dog-ears -> KOReader highlights, notes and bookmarks
  * reading progress and finished status -> KOReader (the newer side wins)
  * Kobo collections ("listeler") -> KOReader collections
  * a "Kobo vurgu ve notları" collection with every book that has highlights

Everything is one-way (Kobo -> KOReader); the Kobo database is only read.

Ayarlar eski eklentiyle aynı dosyada (kobosync.lua) ve kitapların yan dosyalarındaki
kobosync_* kayıtları da aynı: aktarılmış notlar tekrar eklenmez.
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = ffiutil.template

local eklenti_dizini = (debug.getinfo(1, "S").source or ""):match("^@(.+)/[^/]+$") or "."
local function yukle(ad)
    local ok, m = pcall(require, ad)
    if ok then return m end
    return dofile(eklenti_dizini .. "/" .. ad .. ".lua")
end
local KoboDB = yukle("binkitap_kobo_db")
local KUtil = yukle("binkitap_kobo_util")
local Locate = yukle("binkitap_kobo_bul")


local NOTES_COLLECTION = "Kobo vurgu ve notları"
local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/kobosync.lua"
local OLDEST_DOM_VERSION = 20171225 -- CreDocument:getOldestDomVersion()

local DEFAULTS = {
    auto_scan = true,        -- scan when the file browser opens and the Kobo database changed
    import_notes = true,     -- highlights and notes
    import_dogears = true,   -- Kobo bookmarks (dog-ears)
    sync_progress = true,    -- reading position and status
    sync_shelves = true,     -- Kobo collections -> KOReader collections
    notes_collection = true, -- collection of books with Kobo highlights
}

local scan_running = false

local function realpath(p)
    return (p and ffiutil.realpath(p)) or p
end

local function basename(p)
    return (p and p:gsub(".*/", "")) or "?"
end

local function fileExists(p)
    return p and lfs.attributes(p, "mode") == "file"
end

local function isReflowable(file)
    local ok, provider = pcall(DocumentRegistry.getProvider, DocumentRegistry, file)
    return (ok and provider and provider.provider == "crengine") and true or false
end

local function resetBookInfoCache(file)
    local ok, BookList = pcall(require, "ui/widget/booklist")
    if ok and type(BookList) == "table" and BookList.resetBookInfoCache then
        pcall(BookList.resetBookInfoCache, file)
    end
end

local function defaultDrawer()
    return G_reader_settings:readSetting("highlight_drawing_style") or "lighten"
end

local function defaultColor()
    local color = G_reader_settings:readSetting("highlight_color")
    if color then return color end
    local is_color = false
    pcall(function() is_color = Device.screen:isColorEnabled() end)
    return is_color and "yellow" or "gray"
end

local function inChapterText(chapter)
    if chapter and chapter ~= "" then
        return T(_("in %1"), chapter)
    end
end

local function hasSameAnnotation(annotations, item)
    for _, a in ipairs(annotations) do
        if item.pos0 then
            if a.pos0 == item.pos0 and a.pos1 == item.pos1 then return true end
        elseif not a.drawer and not a.pos0 and a.page == item.page then
            return true
        end
    end
    return false
end

-- KOReader 2024.04 and later keep highlights in a single "annotations" list.
local function hasAnnotationSupport()
    if package.loaded["apps/reader/modules/readerannotation"] then return true end
    local ok = pcall(require, "apps/reader/modules/readerannotation")
    return ok
end

local function percentString(p)
    return "%" .. tostring(math.floor((tonumber(p) or 0) + 0.5))
end

local Kobo = {}
Kobo.__index = Kobo

--- o: { ui, view, dialog, sahip (1000Kitap eklentisi) }
function Kobo.yeni(o)
    setmetatable(o, Kobo)
    o:init()
    return o
end

function Kobo:init()
    self.settings = LuaSettings:open(SETTINGS_FILE)
    self.is_reader = self.ui.document ~= nil
    if not self.is_reader and self:getSetting("auto_scan") then
        UIManager:scheduleIn(1.5, function() self:autoScan() end)
    end
end

--- Eski, ayrı Kobo Senkron eklentisi hâlâ açıksa iş onundur: ikisi aynı anda aktarmasın.
function Kobo:eskiAcik()
    return self.sahip ~= nil and self.sahip:eskiKoboEklentisi() ~= nil
end

-- settings

function Kobo:getSetting(key)
    local v = self.settings:readSetting(key)
    if v == nil then return DEFAULTS[key] end
    return v
end

function Kobo:toggleSetting(key)
    self.settings:saveSetting(key, not self:getSetting(key))
    self.settings:flush()
end

function Kobo:dbPath()
    return self.settings:readSetting("db_path") or KoboDB.DEFAULT_PATH
end

function Kobo:showMessage(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

function Kobo:checkDatabase()
    if KoboDB.exists(self:dbPath()) then return true end
    self:showMessage(T("Kobo veritabanı bulunamadı:\n%1\n\nBu eklenti Kobo cihazında çalışır.", self:dbPath()))
    return false
end

function Kobo:showQuickDialog()
    local dialog
    local function close() UIManager:close(dialog) end
    local buttons = {
        {{ text = "Şimdi senkronize et", callback = function() close(); self:runScan(true) end }},
        {{ text = "Kobo'da notlu kitaplar", callback = function() close(); self:showReport() end }},
        {{ text = "Koleksiyonlar", callback = function() close(); self:showCollections() end }},
    }
    if self.sahip and self.sahip.koboVurgulariniGonder then
        table.insert(buttons, 2, {{
            text = (self.is_reader and "Bu kitabın Kobo vurgularını 1000Kitap'a gönder" or "Kobo vurgularını 1000Kitap'a gönder"),
            callback = function() close(); self.sahip:koboVurgulariniGonder() end,
        }})
    end
    if self.is_reader and self.ui.rolling then
        table.insert(buttons, 2, {{
            text = "Bu kitabın Kobo notlarını aktar",
            callback = function() close(); self:importCurrentBook(true) end,
        }})
    end
    dialog = ButtonDialog:new{
        title = "Kobo Senkron",
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function Kobo:showCollections()
    local coll = self.ui.collections
    if coll and coll.onShowCollList then
        coll:onShowCollList()
    else
        self:showMessage("Koleksiyonlar bu KOReader sürümünde açılamadı.")
    end
end

function Kobo:getMenuItems()
    local function setting(key, text)
        return {
            text = text,
            checked_func = function() return self:getSetting(key) end,
            callback = function() self:toggleSetting(key) end,
        }
    end
    local items = {
        {
            text = "Şimdi senkronize et",
            callback = function(touchmenu_instance)
                if touchmenu_instance then touchmenu_instance:closeMenu() end
                self:runScan(true)
            end,
        },
    }
    if self.is_reader then
        table.insert(items, {
            text = "Bu kitabın Kobo notlarını aktar",
            enabled_func = function() return self.ui.rolling ~= nil end,
            callback = function(touchmenu_instance)
                if touchmenu_instance then touchmenu_instance:closeMenu() end
                self:importCurrentBook(true)
            end,
        })
    end
    items[#items].separator = true
    table.insert(items, {
        text = "Kobo'da notlu kitaplar",
        callback = function(touchmenu_instance)
            if touchmenu_instance then touchmenu_instance:closeMenu() end
            self:showReport()
        end,
    })
    table.insert(items, {
        text = "Koleksiyonlar",
        callback = function(touchmenu_instance)
            if touchmenu_instance then touchmenu_instance:closeMenu() end
            self:showCollections()
        end,
        separator = true,
    })
    table.insert(items, {
        text = "Ayarlar",
        sub_item_table = {
            setting("auto_scan", "Kobo'da değişiklik olunca otomatik tara"),
            setting("import_notes", "Vurgu ve notları aktar"),
            setting("import_dogears", "Kobo yer imlerini de aktar"),
            setting("sync_progress", "Okuma ilerlemesini eşleştir"),
            setting("sync_shelves", "Kobo listelerini koleksiyonlara aktar"),
            setting("notes_collection", "\"" .. NOTES_COLLECTION .. "\" koleksiyonunu tut"),
        },
    })
    table.insert(items, {
        text = "Hakkında",
        keep_menu_open = true,
        callback = function() self:showAbout() end,
    })
    return items
end

function Kobo:showAbout()
    local path = self:dbPath()
    local last = self.settings:readSetting("last_scan")
    UIManager:show(TextViewer:new{
        title = "Kobo Senkron",
        text = table.concat({
            "Kobo'nun kendi okuyucusunda yaptıklarını KOReader'a aktarır:",
            "",
            "• Vurgular ve notlar KOReader'da vurgu/not olur. Kitapta aynı metin aranarak yerleştirilir.",
            "• Kobo yer imleri, KOReader'da yer imi olur (bölüm içindeki yaklaşık sayfa).",
            "• Okuma ilerlemesi ve \"bitti\" durumu aktarılır; hangi tarafta daha yeni okuduysan o geçerli olur.",
            "• Kobo listelerin KOReader koleksiyonu olur; Kobo'da listeden çıkardığın kitap burada da çıkar.",
            "• Kobo'da vurgu yaptığın bütün kitaplar \"" .. NOTES_COLLECTION .. "\" koleksiyonunda toplanır.",
            "",
            "Aktarım tek yönlüdür: Kobo veritabanına hiçbir şey yazılmaz. Bir kez aktarılan not, KOReader'da silsen de tekrar eklenmez.",
            "",
            "Veritabanı: " .. path .. (KoboDB.exists(path) and " (bulundu)" or " (bulunamadı)"),
            "Son tarama: " .. (last and os.date("%Y-%m-%d %H:%M", last) or "henüz yok"),
        }, "\n"),
    })
end

-- scanning

function Kobo:autoScan()
    if self:eskiAcik() then return end
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    if not FileManager or FileManager.instance ~= self.ui then return end
    local path = self:dbPath()
    if not KoboDB.exists(path) then return end
    local sig = KoboDB.signature(path)
    if sig == self.settings:readSetting("last_signature") and not self.settings:isTrue("batch_pending") then
        return
    end
    self:runScan(false)
end

function Kobo:runScan(interactive)
    if scan_running then
        if interactive then self:showMessage("Kobo senkronu zaten çalışıyor.", 3) end
        return
    end
    if interactive then
        if not self:checkDatabase() then return end
    elseif not KoboDB.exists(self:dbPath()) then
        return
    end
    scan_running = true
    Trapper:wrap(function()
        local ok, err = pcall(self.doScan, self, interactive)
        scan_running = false
        if not ok then
            logger.err("Kobo: scan failed:", err)
            pcall(Trapper.clear, Trapper)
            self:showMessage("Kobo senkronunda hata oluştu:\n" .. tostring(err))
        end
    end)
end

function Kobo:doScan(interactive)
    local path = self:dbPath()
    Trapper:info("Kobo ile eşleştiriliyor…\n\nKobo veritabanı okunuyor.")
    local db, err = KoboDB.read(path)
    if not db then
        Trapper:clear()
        self:showMessage("Kobo veritabanı okunamadı: " .. tostring(err))
        return
    end
    -- taken after reading: SQLite may have folded Nickel's write-ahead log in
    local sig = KoboDB.signature(path)
    local current = self.is_reader and self.ui.document and self.ui.document.file or nil
    local summary = {}

    if self:getSetting("sync_shelves") or self:getSetting("notes_collection") then
        local ok, res = pcall(self.syncCollections, self, db)
        if ok then summary.shelves = res else logger.warn("Kobo: collections:", res) end
    end
    if self:getSetting("sync_progress") then
        local ok, res = pcall(self.syncProgress, self, db, current)
        if ok then summary.progress = res else logger.warn("Kobo: progress:", res) end
    end

    local batch_done = true
    if self:getSetting("import_notes") and hasAnnotationSupport() then
        if current then
            batch_done = false -- other books are done from the file browser
        else
            local stats, complete = self:batchImport(db)
            summary.notes = stats
            batch_done = complete
        end
    end

    self.settings:saveSetting("last_signature", sig)
    self.settings:saveSetting("batch_pending", not batch_done)
    self.settings:saveSetting("last_scan", os.time())
    self.settings:flush()
    Trapper:clear()

    if not self.is_reader and self.ui.file_chooser then
        pcall(function() self.ui.file_chooser:refreshPath() end)
    end

    local text = self:summaryText(summary)
    if current and self:getSetting("import_notes") then
        -- The open book is handled right away, with the book itself.
        self:importCurrentBook(interactive, text)
        return
    end
    if text ~= "" then
        self:showMessage("Kobo senkron\n\n" .. text, interactive and nil or 8)
    elseif interactive then
        self:showMessage("Kobo senkron: her şey güncel.", 4)
    end
end

function Kobo:summaryText(s)
    local lines = {}
    local n = s.notes
    if n then
        if n.highlights + n.notes > 0 then
            table.insert(lines, T("%1 kitaba %2 vurgu ve %3 not eklendi.", n.books, n.highlights, n.notes))
        end
        if n.bookmarks > 0 then
            table.insert(lines, T("%1 Kobo yer imi eklendi.", n.bookmarks))
        end
        if n.approx > 0 then
            table.insert(lines, T("%1 vurgunun kitapta tam yeri bulunamadı; yaklaşık konumuna not içeren yer imi olarak eklendi.", n.approx))
        end
        if n.failed > 0 then
            table.insert(lines, T("%1 not/vurgu eşleşmedi (\"Kobo'da notlu kitaplar\" listesinden görebilirsin).", n.failed))
        end
        if n.deferred > 0 then
            table.insert(lines, T("%1 kitabın notları, kitabı açtığında eklenecek.", n.deferred))
        end
        if n.stopped then
            table.insert(lines, "Aktarımı durdurdun; kalanlar kitabı açınca ya da bir sonraki taramada eklenecek.")
        end
    end
    if s.progress and s.progress > 0 then
        table.insert(lines, T("%1 kitabın okuma ilerlemesi Kobo'dan güncellendi.", s.progress))
    end
    local sh = s.shelves
    if sh and (sh.added > 0 or sh.removed > 0) then
        table.insert(lines, T("Kobo listeleri: %1 kitap eklendi, %2 kitap çıkarıldı.", sh.added, sh.removed))
    end
    return table.concat(lines, "\n")
end

-- collections

function Kobo:syncCollections(db)
    local ok, ReadCollection = pcall(require, "readcollection")
    if not ok or type(ReadCollection) ~= "table" or not ReadCollection.addCollection then
        return nil -- KOReader too old for multiple collections
    end
    pcall(ReadCollection._read, ReadCollection)

    local pairs_done = self.settings:readSetting("shelf_pairs") or {}
    local created = self.settings:readSetting("created_collections") or {}
    local desired = {}
    local wanted_colls = {}

    if self:getSetting("sync_shelves") then
        for shelf, files in pairs(db.shelves) do
            wanted_colls[shelf] = true
            for _, file in ipairs(files) do
                desired[shelf .. "\t" .. file] = { shelf, file }
            end
        end
    end
    if self:getSetting("notes_collection") then
        wanted_colls[NOTES_COLLECTION] = true
        for file, recs in pairs(db.annotations) do
            for _, rec in ipairs(recs) do
                if rec.kind == "highlight" then
                    desired[NOTES_COLLECTION .. "\t" .. file] = { NOTES_COLLECTION, file }
                    break
                end
            end
        end
    end

    local stats = { added = 0, removed = 0 }
    local changed = false
    local updated = {}

    for key, p in pairs(desired) do
        if not pairs_done[key] then
            local coll_name, file = p[1], p[2]
            if fileExists(file) then
                if not ReadCollection.coll[coll_name] then
                    ReadCollection:addCollection(coll_name)
                    created[coll_name] = true
                end
                if not ReadCollection:isFileInCollection(file, coll_name) then
                    ReadCollection:addItem(file, coll_name)
                    stats.added = stats.added + 1
                end
                updated[coll_name] = true
                changed = true
                pairs_done[key] = true
            end
        end
    end

    -- Removed from a list on the Kobo (or the list was deleted): remove here too.
    for key in pairs(pairs_done) do
        if not desired[key] then
            local coll_name, file = key:match("^(.-)\t(.*)$")
            local coll = coll_name and ReadCollection.coll[coll_name]
            if coll then
                local real = realpath(file)
                if coll[real] or coll[file] then
                    coll[real] = nil
                    coll[file] = nil
                    stats.removed = stats.removed + 1
                    updated[coll_name] = true
                    changed = true
                end
            end
            pairs_done[key] = nil
        end
    end

    -- Collections this plugin made, that no longer exist on the Kobo and are empty now.
    for coll_name in pairs(created) do
        if not wanted_colls[coll_name] then
            local coll = ReadCollection.coll[coll_name]
            if coll and next(coll) == nil then
                ReadCollection:removeCollection(coll_name)
                changed = true
            end
            created[coll_name] = nil
        end
    end

    if changed then
        ReadCollection:write(updated)
    end
    self.settings:saveSetting("shelf_pairs", pairs_done)
    self.settings:saveSetting("created_collections", created)
    return stats
end

-- reading progress

function Kobo:koreaderLastRead(file)
    local ok, ReadHistory = pcall(require, "readhistory")
    if ok and ReadHistory and ReadHistory.getIndexByFile then
        local idx = ReadHistory:getIndexByFile(realpath(file))
        if idx and ReadHistory.hist[idx] and ReadHistory.hist[idx].time then
            return ReadHistory.hist[idx].time
        end
    end
    local sidecar = DocSettings:findSidecarFile(file)
    if sidecar then
        return lfs.attributes(sidecar, "modification")
    end
end

function Kobo:applyProgress(ds, book, file)
    local frac = math.max(0, math.min(1, (tonumber(book.percent) or 0) / 100))
    local finished = book.read_status == 2
    local summary = ds:readSetting("summary") or {}
    summary.status = finished and "complete" or "reading"
    summary.modified = os.date("%Y-%m-%d")
    ds:saveSetting("summary", summary)
    if finished then
        ds:saveSetting("percent_finished", 1)
        return
    end
    local current = tonumber(ds:readSetting("percent_finished"))
    if current and math.abs(current - frac) < 0.01 then return end -- already there
    ds:saveSetting("percent_finished", frac)
    if frac > 0 and isReflowable(file) then
        -- KOReader opens at last_percent when there is no last_xpointer.
        if ds:has("last_xpointer") then
            if ds:hasNot("cre_dom_version") then
                -- keep the DOM version KOReader would have used for this book
                ds:saveSetting("cre_dom_version", OLDEST_DOM_VERSION)
            end
            ds:delSetting("last_xpointer")
        end
        ds:saveSetting("last_percent", frac)
    end
end

function Kobo:syncProgress(db, current_file)
    local count = 0
    for file, book in pairs(db.books) do
        if file ~= current_file and (book.read_status or 0) > 0
                and book.date_last_read and book.date_last_read ~= "" and fileExists(file) then
            local ds = DocSettings:open(file)
            if ds:readSetting("kobosync_progress_seen") ~= book.date_last_read then
                local kobo_ts = KUtil.parseIso(book.date_last_read) or 0
                local kr_ts = self:koreaderLastRead(file)
                local kr_has_progress = ds:has("last_xpointer") or ds:has("last_percent")
                    or ds:has("last_page") or ds:has("percent_finished")
                if not kr_has_progress or not kr_ts or kobo_ts > kr_ts then
                    self:applyProgress(ds, book, file)
                    count = count + 1
                end
                ds:saveSetting("kobosync_progress_seen", book.date_last_read)
                ds:flush()
                resetBookInfoCache(file)
            end
        end
    end
    return count
end

-- highlights and notes

function Kobo:pendingRecords(recs, imported, failed)
    local pending = {}
    local want_dogears = self:getSetting("import_dogears")
    for _, rec in ipairs(recs or {}) do
        if not imported[rec.id] and not failed[rec.id]
                and (rec.kind == "highlight" or want_dogears) then
            table.insert(pending, rec)
        end
    end
    return pending
end

local function kreaderDate(rec)
    return KUtil.toKoreaderDateTime(rec.created) or os.date("%Y-%m-%d %H:%M:%S")
end

local function benzerMetin(a, b)
    a, b = KUtil.normalize(a), KUtil.normalize(b)
    if a == "" or b == "" then return true end
    local n = math.min(15, #a, #b)
    return a:find(b:sub(1, n), 1, true) ~= nil or b:find(a:sub(1, n), 1, true) ~= nil
end

--- Kobo'dan gelmiş ama işaretsiz vurguları (eski Kobo Senkron eklentisinin ya da
--- 1.3.0'dan önce aktarılanlar) Kobo kaydının tarihinden tanıyıp kobo_id ekler.
--- Aktarılırken vurgunun tarihi Kobo'daki oluşturma anı yapılır; saniyesine kadar
--- aynı tarihli başka vurgu pek olmaz, yine de metin de karşılaştırılır.
--- Yeni işaretlenen sayısını döner.
function Kobo.kimlikleriTamamla(annotations, recs)
    if type(annotations) ~= "table" or type(recs) ~= "table" then return 0 end
    local tarihli = {}
    for _i, rec in ipairs(recs) do
        if rec.kind == "highlight" and rec.created then
            local d = KUtil.toKoreaderDateTime(rec.created)
            if d then tarihli[d] = rec end
        end
    end
    local n = 0
    for _i, a in ipairs(annotations) do
        local rec = a.drawer and not a.kobo_id and a.datetime and tarihli[a.datetime]
        if rec and benzerMetin(a.text, rec.text) then
            a.kobo_id = rec.id
            n = n + 1
        end
    end
    return n
end

function Kobo:makeHighlightItem(rec, r, drawer, color, chapter)
    return {
        datetime = kreaderDate(rec),
        drawer = drawer,
        color = color,
        text = r.text,
        note = rec.note,
        chapter = chapter,
        page = r.pos0,
        pos0 = r.pos0,
        pos1 = r.pos1,
        epubcfi = r.epubcfi,
        kobo_id = rec.id, -- 1000Kitap renk kuralıyla kendiliğinden göndermesin
        kobo_oran = r.oran, -- kitabın neresinde (0..1): kitap açılmadan sayfa tahmini
    }
end

function Kobo:makeBookmarkItem(rec, r, chapter)
    local note = rec.note
    if not r.dogear then
        note = "Kobo vurgusu (kitapta tam yeri bulunamadı, yaklaşık konumuna eklendi):\n«"
            .. (KUtil.cleanupText(rec.raw_text) or rec.text or "") .. "»"
        if rec.note then
            note = note .. "\n\nNot: " .. rec.note
        end
    end
    return {
        datetime = kreaderDate(rec),
        page = r.page,
        text = inChapterText(chapter),
        note = note,
        chapter = chapter,
    }
end

local function newStats()
    return { books = 0, highlights = 0, notes = 0, bookmarks = 0, approx = 0, failed = 0, deferred = 0, stopped = false }
end

local function domVersionFor(ds, cre)
    local v = ds:readSetting("cre_dom_version")
    if not v then
        v = ds:has("last_xpointer") and OLDEST_DOM_VERSION or cre.getLatestDomVersion()
    end
    return v
end

--- Imports pending Kobo highlights of every book (except the open one),
-- opening each book in a subprocess. Returns stats, completed.
function Kobo:batchImport(db)
    local stats = newStats()
    local todo = {}
    local cre

    for file, recs in pairs(db.annotations) do
        if fileExists(file) and isReflowable(file) then
            local ds = DocSettings:open(file)
            local pending = self:pendingRecords(recs,
                ds:readSetting("kobosync_imported") or {}, ds:readSetting("kobosync_failed") or {})
            if #pending > 0 then
                if ds:hasNot("annotations") and (ds:has("bookmarks") or ds:has("highlight")) then
                    -- very old KOReader sidecar: let the reader convert it first
                    stats.deferred = stats.deferred + 1
                else
                    if not cre then
                        -- Start crengine here once, so that subprocesses inherit it.
                        cre = require("document/credocument"):engineInit()
                    end
                    local dom = domVersionFor(ds, cre)
                    if dom < cre.getDomVersionWithNormalizedXPointers() then
                        stats.deferred = stats.deferred + 1 -- old positions: do it with the book open
                    else
                        local book = db.books[file]
                        table.insert(todo, {
                            file = file,
                            pending = pending,
                            dom = dom,
                            title = book and book.title or basename(file),
                        })
                    end
                end
            end
        end
    end
    if #todo == 0 then return stats, true end
    table.sort(todo, function(a, b) return a.title < b.title end)

    for i, job in ipairs(todo) do
        -- yüzde: bitmiş kitaplar; her kitap açılıp taranırken ekran değişmez, donmadığını söyle
        local label = T("Kobo notları aktarılıyor · %1\n\n%2 / %3 kitap: %4\n%5 vurgu/not aranıyor\n\nKitap açılıp taranıyor; büyük kitaplarda bir dakikayı bulabilir.\nDurdurmak için dokun.",
            "%" .. math.floor((i - 1) / #todo * 100), i, #todo, job.title, #job.pending)
        local completed, out = Trapper:dismissableRunInSubprocess(function()
            return Locate.openAndLocate(job.file, job.dom, job.pending, { chapters = true, cfi = true })
        end, label)
        if not completed then
            stats.stopped = true
            return stats, false
        end
        if type(out) == "table" and type(out.results) == "table" then
            local ok, err = pcall(self.applyToSidecar, self, job, out.results, stats)
            if not ok then logger.warn("Kobo: could not save", job.file, err) end
        else
            logger.warn("Kobo: could not open", job.file, out and out.error)
            stats.deferred = stats.deferred + 1
        end
    end
    return stats, true
end

function Kobo:applyToSidecar(job, results, stats)
    local ds = DocSettings:open(job.file)
    local annotations = ds:readSetting("annotations") or {}
    if #annotations > 0 and type(annotations[1].page) ~= "string" then
        stats.deferred = stats.deferred + 1 -- opened with a non-crengine engine before
        return
    end
    local imported = ds:readSetting("kobosync_imported") or {}
    local failed = ds:readSetting("kobosync_failed") or {}
    local by_id = {}
    for _, rec in ipairs(job.pending) do by_id[rec.id] = rec end
    local drawer, color = defaultDrawer(), defaultColor()
    local added = 0

    for _, r in ipairs(results) do
        local rec = by_id[r.id]
        if rec then
            if r.status == "ok" then
                local item = self:makeHighlightItem(rec, r, drawer, color, r.chapter)
                if not hasSameAnnotation(annotations, item) then
                    table.insert(annotations, item)
                    added = added + 1
                    if item.note then stats.notes = stats.notes + 1 else stats.highlights = stats.highlights + 1 end
                end
                imported[rec.id] = true
            elseif r.status == "approx" then
                local item = self:makeBookmarkItem(rec, r, r.chapter)
                if not hasSameAnnotation(annotations, item) or not r.dogear then
                    table.insert(annotations, item)
                    added = added + 1
                    if r.dogear then stats.bookmarks = stats.bookmarks + 1 else stats.approx = stats.approx + 1 end
                end
                imported[rec.id] = true
            else
                failed[rec.id] = { text = rec.raw_text, note = rec.note, kind = rec.kind }
                stats.failed = stats.failed + 1
            end
        end
    end

    if added > 0 then
        ds:saveSetting("annotations", annotations)
        -- KOReader recomputes page numbers and sorts them when the book is opened.
        ds:makeTrue("annotations_externally_modified")
        stats.books = stats.books + 1
    end
    if ds:hasNot("cre_dom_version") then
        ds:saveSetting("cre_dom_version", job.dom)
    end
    ds:saveSetting("kobosync_imported", imported)
    ds:saveSetting("kobosync_failed", failed)
    ds:flush()
    resetBookInfoCache(job.file)
end

-- the book open in the reader

function Kobo:onReaderReady()
    if not self.is_reader or not self.ui.rolling or self:eskiAcik() then return end
    local file = self.ui.document and self.ui.document.file
    if not file then return end
    UIManager:scheduleIn(1, function()
        local ReaderUI = package.loaded["apps/reader/readerui"]
        if not ReaderUI or ReaderUI.instance ~= self.ui then return end
        if not (self.ui.document and self.ui.document.file == file) then return end
        if not KoboDB.exists(self:dbPath()) then return end
        self:importCurrentBook(false)
    end)
end

--- Imports the open book's Kobo highlights, then offers Kobo's reading position.
function Kobo:importCurrentBook(interactive, prefix_text)
    if not (self.is_reader and self.ui.document and self.ui.rolling) then
        if interactive then self:showMessage("Bunun için bir EPUB kitap açık olmalı.") end
        return
    end
    if interactive and not self:checkDatabase() then return end
    if self.importing then return end
    self.importing = true
    local file = self.ui.document.file
    Trapper:wrap(function()
        local ok, err = pcall(self.doImportCurrentBook, self, file, interactive, prefix_text)
        self.importing = false
        if not ok then
            logger.err("Kobo: import failed:", err)
            self:showMessage("Kobo notları aktarılamadı:\n" .. tostring(err))
        end
    end)
end

function Kobo:doImportCurrentBook(file, interactive, prefix_text)
    local db = KoboDB.read(self:dbPath(), { file = file, books = true, bookmarks = true })
    if not db then
        if interactive then self:showMessage("Kobo veritabanı okunamadı.") end
        return
    end
    local lines = {}
    if prefix_text and prefix_text ~= "" then table.insert(lines, prefix_text) end

    if self:getSetting("import_notes") or interactive then
        local text = self:liveImport(file, db.annotations[file] or {}, interactive)
        if text then table.insert(lines, text) end
    end

    if #lines > 0 then
        self:showMessage("Kobo senkron\n\n" .. table.concat(lines, "\n"), interactive and nil or 6)
    elseif interactive then
        if prefix_text then -- came from a full sync
            self:showMessage("Kobo senkron: her şey güncel.", 4)
        else
            self:showMessage("Bu kitap için Kobo'da aktarılacak yeni not yok.", 4)
        end
    end

    if self:getSetting("sync_progress") then
        self:checkLiveProgress(db.books[file])
    end
end

function Kobo:liveImport(file, recs, interactive)
    if not (self.ui.annotation and self.ui.annotation.addItem) then
        return interactive and "Vurgu aktarımı için KOReader'ın 2024.04 veya daha yeni bir sürümü gerekiyor." or nil
    end
    local ds = self.ui.doc_settings
    -- önceden aktarılmış ama işaretsiz Kobo vurguları: 1000Kitap renk kuralıyla göndermesin
    pcall(Kobo.kimlikleriTamamla, self.ui.annotation.annotations, recs)
    local imported = ds:readSetting("kobosync_imported") or {}
    local failed = ds:readSetting("kobosync_failed") or {}
    if interactive then
        failed = {} -- try the ones that failed before again
    end
    local pending = self:pendingRecords(recs, imported, failed)
    if #pending == 0 then return nil end

    local doc = self.ui.document
    local completed, results = Trapper:dismissableRunInSubprocess(function()
        return Locate.locateAll(doc, pending, { cfi = true })
    end, T("Kobo'dan %1 vurgu/not ekleniyor…\n\nKitapta aranıyor; uzun kitaplarda biraz sürebilir.\nDurdurmak için dokun.", #pending))
    if not completed or type(results) ~= "table" then
        return "Aktarımı durdurdun; kalanlar kitabı bir sonraki açışında eklenecek."
    end

    local stats = newStats()
    local by_id = {}
    for _, rec in ipairs(pending) do by_id[rec.id] = rec end
    local drawer = self.view and self.view.highlight and self.view.highlight.saved_drawer or defaultDrawer()
    local color = self.view and self.view.highlight and self.view.highlight.saved_color or defaultColor()
    local annotations = self.ui.annotation.annotations

    local function chapterFor(xp, fallback)
        local ok, title = pcall(function()
            if self.ui.highlight and self.ui.highlight.getHighlightChapter then
                return self.ui.highlight:getHighlightChapter(xp)
            end
            return self.ui.toc:getTocTitleByPage(xp)
        end)
        if ok and title and title ~= "" then return title end
        return fallback
    end

    for _, r in ipairs(results) do
        local rec = by_id[r.id]
        if rec then
            if r.status == "ok" then
                local item = self:makeHighlightItem(rec, r, drawer, color, chapterFor(r.pos0, r.chapter))
                if not hasSameAnnotation(annotations, item) then
                    local index = self.ui.annotation:addItem(item)
                    if item.note then
                        stats.notes = stats.notes + 1
                        self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_notes_added = 1, index_modified = index }))
                    else
                        stats.highlights = stats.highlights + 1
                        self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = 1, index_modified = index }))
                    end
                end
                imported[rec.id] = true
                failed[rec.id] = nil
            elseif r.status == "approx" then
                local item = self:makeBookmarkItem(rec, r, chapterFor(r.page, r.chapter))
                if not hasSameAnnotation(annotations, item) or not r.dogear then
                    local index = self.ui.annotation:addItem(item)
                    self.ui:handleEvent(Event:new("AnnotationsModified", { item, index_modified = index }))
                    if r.dogear then stats.bookmarks = stats.bookmarks + 1 else stats.approx = stats.approx + 1 end
                end
                imported[rec.id] = true
                failed[rec.id] = nil
            else
                failed[rec.id] = { text = rec.raw_text, note = rec.note, kind = rec.kind }
                stats.failed = stats.failed + 1
            end
        end
    end

    -- keep the earlier failures we did not retry
    local old_failed = ds:readSetting("kobosync_failed") or {}
    for id, v in pairs(old_failed) do
        if failed[id] == nil and not imported[id] then failed[id] = v end
    end
    ds:saveSetting("kobosync_imported", imported)
    ds:saveSetting("kobosync_failed", failed)
    pcall(function() self.view.footer:maybeUpdateFooter() end)
    pcall(function() self.ui:saveSettings() end)
    UIManager:setDirty(self.dialog or self.ui, "ui")

    local lines = {}
    if stats.highlights + stats.notes > 0 then
        table.insert(lines, T("Bu kitaba Kobo'dan %1 vurgu ve %2 not eklendi.", stats.highlights, stats.notes))
    end
    if stats.bookmarks > 0 then
        table.insert(lines, T("%1 Kobo yer imi eklendi.", stats.bookmarks))
    end
    if stats.approx > 0 then
        table.insert(lines, T("%1 vurgunun tam yeri bulunamadı; yaklaşık konumuna not içeren yer imi olarak eklendi.", stats.approx))
    end
    if stats.failed > 0 then
        table.insert(lines, T("%1 not/vurgu kitapta bulunamadı.", stats.failed))
    end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

function Kobo:currentPercent()
    local ok, pct = pcall(function()
        local doc = self.ui.document
        local total = doc:getPageCount()
        if not total or total == 0 then return nil end
        return doc:getCurrentPage() / total * 100
    end)
    return ok and pct or nil
end

--- If the book was read on the Kobo since we last looked, offer to jump there.
function Kobo:checkLiveProgress(book)
    if not book or (book.read_status or 0) == 0 or not book.date_last_read or book.date_last_read == "" then
        return
    end
    local ds = self.ui.doc_settings
    if ds:readSetting("kobosync_progress_seen") == book.date_last_read then return end
    ds:saveSetting("kobosync_progress_seen", book.date_last_read)
    if book.read_status == 2 then return end -- finished: nothing to jump to
    local kobo_pct = tonumber(book.percent) or 0
    local cur = self:currentPercent()
    if kobo_pct <= 0 or not cur or math.abs(cur - kobo_pct) < 2 then return end
    local epoch = KUtil.parseIso(book.date_last_read)
    local when = epoch and os.date("%d.%m.%Y %H:%M", epoch) or book.date_last_read
    UIManager:show(ConfirmBox:new{
        text = T("Bu kitabı Kobo okuyucusunda en son %1 civarında bırakmışsın (%2).\nKOReader'da şu an %3 civarındasın.\n\nKobo'da kaldığın yere gideyim mi?",
            percentString(kobo_pct), when, percentString(cur)),
        ok_text = "Git",
        cancel_text = "Burada kal",
        ok_callback = function()
            pcall(function() self.ui.link:addCurrentLocationToStack() end)
            self.ui:handleEvent(Event:new("GotoPercent", kobo_pct))
        end,
    })
end

-- report: which books have Kobo highlights and notes

function Kobo:collectReport()
    local db, err = KoboDB.read(self:dbPath(), { books = true, bookmarks = true })
    if not db then return nil, err end
    local entries = {}
    local totals = { books = 0, highlights = 0, notes = 0, dogears = 0 }
    for file, recs in pairs(db.annotations) do
        local e = { file = file, recs = recs, highlights = 0, notes = 0, dogears = 0, imported = 0, failed = 0 }
        local book = db.books[file]
        e.title = (book and book.title and book.title ~= "") and book.title or basename(file)
        e.author = book and book.author
        for _, r in ipairs(recs) do
            if r.kind == "highlight" then
                if r.note then e.notes = e.notes + 1 else e.highlights = e.highlights + 1 end
            else
                e.dogears = e.dogears + 1
            end
        end
        e.exists = fileExists(file)
        if e.exists and DocSettings:hasSidecarFile(file) then
            local ds = DocSettings:open(file)
            local imported = ds:readSetting("kobosync_imported") or {}
            local failed = ds:readSetting("kobosync_failed") or {}
            for _, r in ipairs(recs) do
                if imported[r.id] then e.imported = e.imported + 1 end
                if failed[r.id] then e.failed = e.failed + 1 end
            end
            e.failed_map = failed
        end
        table.insert(entries, e)
        totals.books = totals.books + 1
        totals.highlights = totals.highlights + e.highlights
        totals.notes = totals.notes + e.notes
        totals.dogears = totals.dogears + e.dogears
    end
    table.sort(entries, function(a, b) return a.title:lower() < b.title:lower() end)
    return entries, totals
end

function Kobo:showReport()
    if not self:checkDatabase() then return end
    local entries, totals = self:collectReport()
    if not entries then
        self:showMessage("Kobo veritabanı okunamadı: " .. tostring(totals))
        return
    end
    if #entries == 0 then
        self:showMessage("Kobo'da vurgu ya da not yapılmış kitap bulunamadı.")
        return
    end
    local item_table = {
        {
            text = T("%1 kitap · %2 vurgu · %3 not · %4 yer imi", totals.books, totals.highlights, totals.notes, totals.dogears),
            select_enabled = false,
            separator = true,
        },
    }
    for _, e in ipairs(entries) do
        local parts = {}
        if e.highlights > 0 then table.insert(parts, T("%1 vurgu", e.highlights)) end
        if e.notes > 0 then table.insert(parts, T("%1 not", e.notes)) end
        if e.highlights + e.notes == 0 and e.dogears > 0 then table.insert(parts, T("%1 yer imi", e.dogears)) end
        local mark = ""
        if e.imported > 0 and e.imported + e.failed >= #e.recs then
            mark = e.failed > 0 and " !" or " ✓"
        end
        table.insert(item_table, {
            text = e.title,
            mandatory = table.concat(parts, " · ") .. mark,
            dim = not e.exists,
            entry = e,
            callback = function()
                if e.exists then
                    UIManager:nextTick(function()
                        require("apps/reader/readerui"):showReader(e.file)
                    end)
                else
                    self:showMessage("Bu kitabın dosyası artık cihazda yok:\n" .. e.file)
                end
            end,
        })
    end
    local menu
    menu = Menu:new{
        title = "Kobo'da notlu kitaplar",
        subtitle = "Dokun: kitabı aç · Basılı tut: vurgu ve notları gör",
        item_table = item_table,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuHold = function(_, item)
            if item.entry then self:showBookDetails(item.entry) end
            return true
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function Kobo:showBookDetails(e)
    local lines = {}
    if e.author and e.author ~= "" then
        table.insert(lines, e.author)
        table.insert(lines, "")
    end
    local status = {}
    if e.imported > 0 then table.insert(status, T("%1 tanesi KOReader'a aktarıldı", e.imported)) end
    if e.failed > 0 then table.insert(status, T("%1 tanesi kitapta bulunamadı (!)", e.failed)) end
    if #status > 0 then
        table.insert(lines, table.concat(status, ", ") .. ".")
        table.insert(lines, "")
    end
    for _, r in ipairs(e.recs) do
        local flag = (e.failed_map and e.failed_map[r.id]) and "(!) " or ""
        if r.kind == "highlight" then
            table.insert(lines, "• " .. flag .. "«" .. (KUtil.cleanupText(r.raw_text) or r.text) .. "»")
            if r.note then
                table.insert(lines, "   Not: " .. r.note)
            end
        else
            table.insert(lines, "• " .. flag .. "[yer imi]" .. (r.note and (" " .. r.note) or ""))
        end
        table.insert(lines, "")
    end
    UIManager:show(TextViewer:new{
        title = e.title,
        text = table.concat(lines, "\n"),
    })
end


return Kobo
