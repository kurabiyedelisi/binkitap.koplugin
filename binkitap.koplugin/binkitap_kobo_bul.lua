--[[--
Finds where Kobo highlights are in a book opened with crengine.

Kobo and KOReader store positions differently (Adobe "point" paths vs
crengine XPointers), so the highlighted text itself is searched for in the
book. Kobo's chapter file (from StartContainerPath) and its position inside
the chapter (ChapterProgress) are used to pick the right hit when the same
words appear more than once.

This module only calls document methods: it is run in a subprocess, either
on the book open in the reader, or on a book opened just for this.
--]]

local KUtil = require("binkitap_kobo_util")

local Locate = {
    -- MATCH_ACROSS_TEXT_NODES | COLLAPSE_CONSECUTIVE_SPACES | NORMALIZE_CANONICAL
    -- | NORMALIZE_COMPATIBILITY | IGNORE_FORMAT_CONTROL_CHARS | FOLD_SPACES
    -- | FOLD_APOSTROPHES | FOLD_HYPHENS (same as KOReader's default search)
    SEARCH_FLAGS = 0x00FF,
    MAX_HITS = 60,
    FULL_SEARCH_MAX_WORDS = 40,
    EDGE_WORDS = 8,
}

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

local Ctx = {}
Ctx.__index = Ctx

function Locate.newContext(doc, opts)
    local ctx = setmetatable({
        doc = doc,
        opts = opts or {},
        page_cache = {},
        frag_start = {},
    }, Ctx)
    ctx.page_count = safe(doc.getPageCount, doc) or 0
    ctx:initSpine()
    return ctx
end

function Ctx:fragXPointer(k)
    return "/body/DocFragment[" .. k .. "]"
end

function Ctx:fragExists(k)
    return safe(self.doc.isXPointerInDocument, self.doc, self:fragXPointer(k)) and true or false
end

--- Maps chapter files to crengine's DocFragment numbers (spine order).
function Ctx:initSpine()
    local doc = self.doc
    if type(doc.getDocumentFileContent) ~= "function" then return end
    local read = function(p) return safe(doc.getDocumentFileContent, doc, p) end
    local ok, map, count = pcall(KUtil.parseSpine, read("META-INF/container.xml"), read)
    if not ok or not map then return end
    -- crengine makes one DocFragment per spine item; if the numbers don't
    -- line up (missing files in the book), don't trust the mapping.
    if not self:fragExists(count) or self:fragExists(count + 1) then return end
    self.spine = map
end

function Ctx:pageOf(xp)
    if not xp then return nil end
    local p = self.page_cache[xp]
    if p == nil then
        p = safe(self.doc.getPageFromXPointer, self.doc, xp) or false
        self.page_cache[xp] = p
    end
    return p or nil
end

function Ctx:fragStartPage(k)
    if self.frag_start[k] == nil then
        local p = false
        if self:fragExists(k) then
            p = safe(self.doc.getPageFromXPointer, self.doc, self:fragXPointer(k)) or false
        end
        self.frag_start[k] = p
    end
    return self.frag_start[k] or nil
end

--- First page of a chapter file and first page after it.
function Ctx:fragPageRange(k)
    local s = self:fragStartPage(k)
    if not s then return nil end
    local e = self:fragStartPage(k + 1) or (self.page_count + 1)
    if e <= s then e = s + 1 end
    return s, e
end

--- XPointer of the page at `progress` (0..1) inside chapter file k.
function Ctx:approxXPointer(k, progress)
    local s, e = self:fragPageRange(k)
    if not s then return nil end
    progress = tonumber(progress) or 0
    if progress < 0 then progress = 0 elseif progress > 1 then progress = 1 end
    local p = s + math.floor(progress * (e - 1 - s) + 0.5)
    if p >= e then p = e - 1 end
    if p < s then p = s end
    if p == s then
        return self:fragXPointer(k)
    end
    return safe(self.doc.getPageXPointer, self.doc, p) or self:fragXPointer(k)
end

function Ctx:chapterOf(xp)
    if not self.opts.chapters or not xp then return nil end
    if self.toc == nil then
        local toc = safe(self.doc.getToc, self.doc)
        self.toc = type(toc) == "table" and toc or false
    end
    if not self.toc then return nil end
    local page = self:pageOf(xp)
    if not page then return nil end
    local title
    for _, entry in ipairs(self.toc) do
        if type(entry) == "table" and entry.page and entry.page <= page then
            title = entry.title
        end
    end
    if type(title) == "string" then
        title = KUtil.normalize(title)
        if title ~= "" then return title end
    end
    return nil
end

function Ctx:search(pattern)
    if not pattern or pattern == "" then return {} end
    local res = safe(self.doc.findAllText, self.doc, pattern, true, 0, Locate.MAX_HITS, false, Locate.SEARCH_FLAGS)
    local hits = {}
    if type(res) == "table" then
        for _, r in ipairs(res) do
            if type(r) == "table" and r.start and r["end"] then
                hits[#hits + 1] = { start = r.start, ["end"] = r["end"] }
            end
        end
    end
    return hits
end

function Ctx:inFrag(hits, frag)
    if not frag then return hits end
    local same = {}
    for _, h in ipairs(hits) do
        if KUtil.fragOfXPointer(h.start) == frag then
            same[#same + 1] = h
        end
    end
    return same
end

--- Pairs start hits with end hits whose text length matches the highlight.
function Ctx:pairEdges(heads, tails, target_len, frag)
    if frag then
        local h2, t2 = self:inFrag(heads, frag), self:inFrag(tails, frag)
        if #h2 > 0 and #t2 > 0 then heads, tails = h2, t2 end
    end
    local out, checks = {}, 0
    for _, h in ipairs(heads) do
        local best, best_score
        for _, t in ipairs(tails) do
            if checks >= 300 then break end
            if safe(self.doc.compareXPointers, self.doc, h.start, t["end"]) == 1 then
                checks = checks + 1
                local txt = safe(self.doc.getTextFromXPointers, self.doc, h.start, t["end"])
                if type(txt) == "string" then
                    local ratio = #KUtil.normalize(txt) / math.max(1, target_len)
                    if ratio >= 0.7 and ratio <= 1.4 then
                        local score = math.abs(1 - ratio)
                        if not best_score or score < best_score then
                            best, best_score = t, score
                        end
                    end
                end
            end
        end
        if best then
            out[#out + 1] = { start = h.start, ["end"] = best["end"] }
        end
    end
    return out
end

--- Long or multi-paragraph highlights: search the first and the last words
-- (taken from the first and last paragraph Kobo stored), with fewer words
-- if needed, and keep the pair that spans the right amount of text.
function Ctx:headTail(rec, words, target_len, frag)
    local segs = {}
    for line in ((rec.raw_text or "") .. "\n"):gmatch("([^\n]*)\n") do
        local w = KUtil.splitWords(KUtil.normalize(line))
        if #w > 0 then segs[#segs + 1] = w end
    end
    local first, last = words, words
    local single = #segs < 2
    if not single then
        first, last = segs[1], segs[#segs]
    end
    local tried = {}
    local k = Locate.EDGE_WORDS
    while k >= 2 do
        local kh, kt
        if single then
            kh = math.min(k, math.max(1, math.floor(#words / 2)))
            kt = kh
        else
            kh, kt = math.min(k, #first), math.min(k, #last)
        end
        local head = KUtil.joinWords(first, 1, kh)
        local tail = KUtil.joinWords(last, #last - kt + 1, #last)
        local key = head .. "\0" .. tail
        if not tried[key] then
            tried[key] = true
            local heads = self:search(head)
            if #heads > 0 then
                local tails = self:search(tail)
                if #tails > 0 then
                    local out = self:pairEdges(heads, tails, target_len, frag)
                    if #out > 0 then return out end
                end
            end
        end
        k = math.floor(k / 2)
    end
    return {}
end

--- Chooses among several hits: same chapter file first, then the one
-- closest to where Kobo says it is inside that chapter.
function Ctx:pick(cands, frag, progress)
    if #cands == 0 then return nil end
    if #cands == 1 then return cands[1] end
    local pool = cands
    if frag then
        local same = self:inFrag(cands, frag)
        if #same > 0 then pool = same end
        if #pool == 1 then return pool[1] end
        progress = tonumber(progress)
        if progress then
            local s, e = self:fragPageRange(frag)
            if s then
                local target = s + progress * (e - 1 - s)
                local best, best_d
                for _, c in ipairs(pool) do
                    local p = self:pageOf(c.start)
                    if p then
                        local d = math.abs(p - target)
                        if not best_d or d < best_d then
                            best, best_d = c, d
                        end
                    end
                end
                if best then return best end
            end
        end
    end
    return pool[1]
end

function Ctx:fragOf(rec)
    if not self.spine or not rec.href then return nil end
    return KUtil.spineLookup(self.spine, rec.href)
end

function Ctx:locate(rec)
    local frag = self:fragOf(rec)

    if rec.kind == "dogear" then
        local xp = frag and self:approxXPointer(frag, rec.progress)
        if xp then
            return { id = rec.id, status = "approx", dogear = true, page = xp, chapter = self:chapterOf(xp) }
        end
        return { id = rec.id, status = "fail" }
    end

    local text = rec.text or ""
    local words = KUtil.splitWords(text)
    local cands = {}
    if #words > 0 and #words <= Locate.FULL_SEARCH_MAX_WORDS then
        cands = self:search(text)
    end
    if #cands == 0 and #words >= 4 then
        cands = self:headTail(rec, words, #text, frag)
    end
    local best = self:pick(cands, frag, rec.progress)
    if best then
        local doc_text = safe(self.doc.getTextFromXPointers, self.doc, best.start, best["end"])
        local res = {
            id = rec.id,
            status = "ok",
            pos0 = best.start,
            pos1 = best["end"],
            text = KUtil.cleanupText(doc_text) or KUtil.cleanupText(rec.raw_text) or text,
            chapter = self:chapterOf(best.start),
        }
        if self.opts.cfi then
            res.epubcfi = safe(self.doc.getEPubCFIRangeFromXPointers, self.doc, best.start, best["end"])
        end
        return res
    end

    -- Not found (text changed, or an unusual book): keep it as a page
    -- bookmark near where it was, with the highlighted text as its note.
    local xp = frag and self:approxXPointer(frag, rec.progress)
    if xp then
        return { id = rec.id, status = "approx", page = xp, chapter = self:chapterOf(xp) }
    end
    return { id = rec.id, status = "fail" }
end

--- Locates every record; never raises.
function Locate.locateAll(doc, records, opts)
    local results = {}
    local ok_ctx, ctx = pcall(Locate.newContext, doc, opts)
    for i, rec in ipairs(records) do
        local ok, res
        if ok_ctx then
            ok, res = pcall(ctx.locate, ctx, rec)
        end
        if ok and type(res) == "table" then
            results[i] = res
        else
            results[i] = { id = rec.id, status = "fail", error = tostring(res or ctx) }
        end
    end
    return results
end

--- Opens a book on its own (no reader), then locates the records in it.
-- Meant to run in a subprocess. dom_version must match the book's sidecar,
-- so that XPointers are the ones the reader will use.
function Locate.openAndLocate(path, dom_version, records, opts)
    local DocumentRegistry = require("document/documentregistry")
    local doc = DocumentRegistry:openDocument(path)
    if not doc then
        return { error = "open" }
    end
    local ok, res = pcall(function()
        if type(doc.findAllText) ~= "function" or type(doc.loadDocument) ~= "function" then
            return { error = "unsupported" }
        end
        if doc.setupDefaultView then doc:setupDefaultView() end
        if dom_version and doc.requestDomVersion then doc:requestDomVersion(dom_version) end
        if not doc:loadDocument() then
            return { error = "load" }
        end
        doc:render()
        return { results = Locate.locateAll(doc, records, opts) }
    end)
    pcall(doc.close, doc)
    if not ok then
        return { error = tostring(res) }
    end
    return res
end

return Locate
