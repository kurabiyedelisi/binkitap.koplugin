--[[--
Kobo Senkron (1000Kitap eklentisinin Kobo bölümü): saf Lua yardımcıları.
Small pure-Lua helpers shared by the Kobo Senkron part of the plugin.
Nothing here touches KOReader's UI, so it can run in a subprocess and in tests.
--]]

local Util = {}

-- Characters that never appear in search hits the way Kobo stores them.
local INVISIBLE = {
    "\194\173",     -- U+00AD soft hyphen
    "\226\128\139", -- U+200B zero width space
    "\226\128\140", -- U+200C zero width non-joiner
    "\226\128\141", -- U+200D zero width joiner
    "\239\187\191", -- U+FEFF zero width no-break space / BOM
}

--- Collapses whitespace and strips invisible characters, so that Kobo's
-- highlight text can be searched for in the book.
function Util.normalize(s)
    if type(s) ~= "string" then return "" end
    for _, c in ipairs(INVISIBLE) do
        s = s:gsub(c, "")
    end
    s = s:gsub("\194\160", " ") -- no-break space
    s = s:gsub("%s+", " ")
    s = s:gsub("^ ", "")
    s = s:gsub(" $", "")
    return s
end

--- Same cleanup KOReader applies to selected text (util.cleanupSelectedText).
function Util.cleanupText(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^[\n%s]*", "")
    text = text:gsub("[\n%s]*$", "")
    text = text:gsub("%s*\n%s*", "\n")
    text = text:gsub("%s%s+", " ")
    return text
end

function Util.splitWords(s)
    local words = {}
    for w in s:gmatch("%S+") do
        words[#words + 1] = w
    end
    return words
end

function Util.joinWords(words, i, j)
    local t = {}
    for k = i, j do
        t[#t + 1] = words[k]
    end
    return table.concat(t, " ")
end

-- Seconds to add to os.time() of a local-time table to get the UTC epoch.
local function localUtcOffset(ts)
    local l = os.date("*t", ts)
    local u = os.date("!*t", ts)
    l.isdst = false
    u.isdst = false
    return os.difftime(os.time(l), os.time(u))
end

--- Parses an ISO 8601 date as Kobo stores it ("2026-11-20T21:14:03Z",
-- "2026-11-20T21:14:03.000", "2026-11-20 21:14:03+00:00").
-- Kobo writes UTC, so a date without a zone is read as UTC too.
-- Returns the Unix epoch, or nil.
function Util.parseIso(s)
    if type(s) ~= "string" then return nil end
    local y, mo, d, h, mi, sec, rest = s:match("^%s*(%d%d%d%d)-(%d%d)-(%d%d)[T ](%d%d):(%d%d):?(%d*)(.*)$")
    if not y then
        y, mo, d = s:match("^%s*(%d%d%d%d)-(%d%d)-(%d%d)%s*$")
        if not y then return nil end
        h, mi, sec, rest = "0", "0", "0", ""
    end
    local guess = os.time{
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) or 0,
        isdst = false,
    }
    if not guess then return nil end
    local epoch = guess + localUtcOffset(guess)
    rest = (rest or ""):gsub("^%.%d+", "")
    local sign, oh, om = rest:match("^([+-])(%d%d):?(%d%d)")
    if sign then
        local off = tonumber(oh) * 3600 + tonumber(om) * 60
        if sign == "+" then
            epoch = epoch - off
        else
            epoch = epoch + off
        end
    end
    return epoch
end

--- Kobo date -> "YYYY-MM-DD HH:MM:SS" in local time, as KOReader stores
-- annotation dates. Returns nil if the date can't be read.
function Util.toKoreaderDateTime(s)
    local epoch = Util.parseIso(s)
    if not epoch then return nil end
    return os.date("%Y-%m-%d %H:%M:%S", epoch)
end

function Util.urlDecode(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

--- Joins a relative href to a base directory ("OEBPS/") and resolves "." and "..".
function Util.resolvePath(base_dir, href)
    local path = (base_dir or "") .. (href or "")
    path = path:gsub("#.*$", "")
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 then table.remove(parts) end
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "/")
end

--- "file:///mnt/onboard/Kitaplar/x.epub" -> "/mnt/onboard/Kitaplar/x.epub"
function Util.fileFromContentId(cid)
    if type(cid) ~= "string" then return nil end
    local p = cid:match("^file://(/.*)$")
    if not p then return nil end
    -- Strip any chapter part ("...epub#(6)OEBPS/ch.xhtml")
    p = p:gsub("#%(%d+%).*$", "")
    return p
end

--- Chapter file of a Kobo highlight, relative to the EPUB root.
-- StartContainerPath looks like "OEBPS/cha01.xhtml#point(/1/4/2/26/1:223)",
-- ContentID like "file:///mnt/onboard/x.epub#(6)OEBPS/cha01.xhtml".
function Util.hrefFromBookmark(start_path, content_id)
    local href
    if type(start_path) == "string" and start_path ~= "" then
        href = start_path:match("^([^#]+)")
        -- kepub style "span#kobo.12.3" has no file part
        if href and (href:find("^span") or not href:find("%.")) then href = nil end
    end
    if not href and type(content_id) == "string" then
        href = content_id:match("#%(%d+%)([^#]+)")
        if not href then
            -- kepub chapters: "/mnt/onboard/x.kepub.epub!OEBPS!Text/ch.xhtml"
            href = content_id:match("![^!]*!(.*)$")
        end
    end
    if href then
        href = Util.resolvePath("", Util.urlDecode(href))
        if href == "" then href = nil end
    end
    return href
end

--- DocFragment index of a crengine XPointer ("/body/DocFragment[12]/body/p[3]/text().5").
function Util.fragOfXPointer(xp)
    if type(xp) ~= "string" then return nil end
    xp = xp:gsub("^/body%[1%]", "/body")
    local n = xp:match("^/body/DocFragment%[(%d+)%]")
    if n then return tonumber(n) end
    if xp:match("^/body/DocFragment/") or xp == "/body/DocFragment" then return 1 end
    return nil
end

--- Extracts attribute `name` from an XML tag string.
function Util.xmlAttr(tag, name)
    local v = tag:match("[%s:]" .. name .. "%s*=%s*\"([^\"]*)\"")
    if v == nil then
        v = tag:match("[%s:]" .. name .. "%s*=%s*'([^']*)'")
    end
    return v
end

--- Builds { [href from EPUB root] = spine position (1-based) } from the
-- container.xml and OPF texts. Returns map, count (or nil).
function Util.parseSpine(container_xml, read_file)
    if type(container_xml) ~= "string" then return nil end
    local opf_path
    for tag in container_xml:gmatch("<[%w_]*:?rootfile%s[^>]*>") do
        opf_path = Util.xmlAttr(" " .. tag, "full%-path")
        if opf_path then break end
    end
    if not opf_path then return nil end
    opf_path = Util.urlDecode(opf_path)
    local opf = read_file(opf_path)
    if type(opf) ~= "string" then return nil end
    local opf_dir = opf_path:match("^(.*/)") or ""
    local manifest = {}
    for tag in opf:gmatch("<[%w_]*:?item%s[^>]*>") do
        local id = Util.xmlAttr(" " .. tag, "id")
        local href = Util.xmlAttr(" " .. tag, "href")
        if id and href then
            manifest[id] = Util.resolvePath(opf_dir, Util.urlDecode(href))
        end
    end
    local map, count = {}, 0
    for tag in opf:gmatch("<[%w_]*:?itemref%s[^>]*>") do
        local idref = Util.xmlAttr(" " .. tag, "idref")
        count = count + 1
        local href = idref and manifest[idref]
        if href and not map[href] then
            map[href] = count
        end
    end
    if count == 0 then return nil end
    return map, count
end

--- Looks up an href in a spine map, tolerating case differences.
function Util.spineLookup(map, href)
    if not map or not href then return nil end
    local k = map[href]
    if k then return k end
    local lower = href:lower()
    for h, idx in pairs(map) do
        if h:lower() == lower then return idx end
    end
    -- Kobo sometimes stores the href relative to the OPF folder
    for h, idx in pairs(map) do
        if h:sub(-#href - 1) == "/" .. href then return idx end
    end
    return nil
end

return Util
