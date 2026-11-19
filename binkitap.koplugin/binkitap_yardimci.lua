--[[
1000Kitap eklentisi: metin, dosya ve kitap bilgisi yardımcıları.
]]

local Y = {}

function Y.kirp(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- UTF-8 karakterini bölmeden kısaltır.
function Y.kisalt(s, max)
    s = s or ""
    if #s <= max then return s end
    local i = max
    while i > 1 do
        local b = s:byte(i + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        i = i - 1
    end
    return s:sub(1, i) .. "…"
end

local TR = {
    ["ç"] = "c", ["Ç"] = "c", ["ğ"] = "g", ["Ğ"] = "g", ["ı"] = "i", ["İ"] = "i",
    ["ö"] = "o", ["Ö"] = "o", ["ş"] = "s", ["Ş"] = "s", ["ü"] = "u", ["Ü"] = "u",
    ["â"] = "a", ["Â"] = "a", ["î"] = "i", ["Î"] = "i", ["û"] = "u", ["Û"] = "u",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["á"] = "a", ["à"] = "a", ["ó"] = "o",
    ["ñ"] = "n", ["ä"] = "a", ["ë"] = "e", ["ï"] = "i",
}

--- Karşılaştırma için sadeleştirir: Türkçe harfleri ASCII'ye çevirir,
-- küçük harfe indirir, harf ve rakam dışındaki her şeyi atar.
function Y.normal(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("[\195\196\197][\128-\191]", function(c) return TR[c] or "" end)
    s = s:lower()
    return (s:gsub("[^%w]", ""))
end

--- Dosya adından okunabilir bir başlık çıkarır.
function Y.dosyaAdindanBaslik(yol)
    local ad = (yol or ""):match("([^/]+)$") or ""
    ad = ad:gsub("%.kepub%.epub$", ""):gsub("%.[%w]+$", "")
    ad = ad:gsub("[_]+", " "):gsub("%s+", " ")
    return Y.kirp(ad)
end

--- Kitap bilgilerinden ISBN çıkarır (978/979'la başlayan 13 hane ya da 10 hane).
function Y.isbnBul(props)
    if type(props) ~= "table" then return nil end
    local kaynaklar = { props.identifiers, props.isbn, props.keywords }
    for _i, k in ipairs(kaynaklar) do
        if type(k) == "string" and k ~= "" then
            local temiz = k:gsub("[%-%s]", "")
            local isbn = temiz:match("97[89]%d%d%d%d%d%d%d%d%d%d")
            if isbn then return isbn end
            local isbn10 = temiz:lower():match("isbn:?(%d%d%d%d%d%d%d%d%d[%dx])")
            if isbn10 then return isbn10:upper() end
        end
    end
    return nil
end

--- Calibre'de eklenebilen "1000kitap:24319" tanımlayıcısını bulur.
function Y.binkitapIdBul(props)
    if type(props) ~= "table" then return nil end
    for _i, k in ipairs({ props.identifiers, props.keywords }) do
        if type(k) == "string" then
            local id = k:lower():match("1000kitap[%s:=]*(%d+)")
            if id then return id end
        end
    end
    return nil
end

--- Başlık eşleşmesi: 1000Kitap'taki ad ile dosyadaki başlık aynı kitap mı?
function Y.baslikAyni(a, b)
    local na, nb = Y.normal(a), Y.normal(b)
    if na == "" or nb == "" then return false end
    return na == nb
end

--- Yazar eşleşmesi: soyadı (son kelime) diğerinin içinde geçiyor mu?
function Y.yazarUyuyor(a, b)
    if Y.kirp(a) == "" or Y.kirp(b) == "" then return true end
    local soyad = (a:match("([^%s]+)%s*$") or a)
    local ns, nb = Y.normal(soyad), Y.normal(b)
    if #ns < 3 then return true end
    return nb:find(ns, 1, true) ~= nil
end

local UZANTILAR = {
    epub = true, pdf = true, mobi = true, azw = true, azw3 = true, fb2 = true, fb3 = true,
    djvu = true, cbz = true, cbr = true, txt = true, docx = true, rtf = true, htm = true,
    html = true, chm = true, doc = true, pdb = true, prc = true, md = true, xps = true,
}

function Y.kitapDosyasiMi(yol)
    local ok, DocumentRegistry = pcall(require, "document/documentregistry")
    if ok and DocumentRegistry and DocumentRegistry.hasProvider then
        local ok2, var = pcall(DocumentRegistry.hasProvider, DocumentRegistry, yol)
        if ok2 then return var and true or false end
    end
    local uzanti = (yol:match("%.([%w]+)$") or ""):lower()
    return UZANTILAR[uzanti] == true
end

--- Bir klasördeki (isteğe bağlı alt klasörlerle) kitap dosyalarını listeler.
function Y.kitapDosyalari(dizin, alt_klasorler, en_fazla)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then return {} end
    local sonuc = {}
    en_fazla = en_fazla or 5000
    local function tara(d, derinlik)
        if #sonuc >= en_fazla or derinlik > 8 then return end
        local ok_dir, iter, obj = pcall(lfs.dir, d)
        if not ok_dir then return end
        local adlar = {}
        for ad in iter, obj do adlar[#adlar + 1] = ad end
        table.sort(adlar)
        for _i, ad in ipairs(adlar) do
            if ad:sub(1, 1) ~= "." then
                local yol = d .. "/" .. ad
                local tip = lfs.attributes(yol, "mode")
                if tip == "directory" then
                    if alt_klasorler and not ad:match("%.sdr$") then tara(yol, derinlik + 1) end
                elseif tip == "file" and Y.kitapDosyasiMi(yol) then
                    sonuc[#sonuc + 1] = yol
                    if #sonuc >= en_fazla then return end
                end
            end
        end
    end
    tara(dizin, 0)
    return sonuc
end

--- Açık olmayan bir dosyanın başlık/yazar/ISBN bilgisi.
-- Önce verilen book_props, sonra yan dosyadaki doc_props, sonra KOReader'ın
-- kitap bilgisi modülü, en son dosya adı kullanılır.
function Y.dosyaBilgisi(ui, yol, book_props)
    local props
    if type(book_props) == "table" and (book_props.title or book_props.display_title) then
        props = book_props
    end
    if not props then
        local ok, DocSettings = pcall(require, "docsettings")
        if ok and DocSettings then
            local ok2, var = pcall(function() return DocSettings:hasSidecarFile(yol) end)
            if ok2 and var then
                local ok3, ds = pcall(function() return DocSettings:open(yol) end)
                if ok3 and ds then
                    local p = ds:readSetting("doc_props")
                    if type(p) == "table" then props = p end
                end
            end
        end
    end
    if not props and ui and ui.bookinfo and ui.bookinfo.getDocProps then
        local ok, p = pcall(ui.bookinfo.getDocProps, ui.bookinfo, yol, nil, true)
        if ok and type(p) == "table" then props = p end
    end
    props = props or {}
    local baslik = Y.kirp(props.display_title or props.title)
    if baslik == "" then baslik = Y.dosyaAdindanBaslik(yol) end
    local yazar = Y.kirp((props.authors or ""):gsub("\n.*", ""))
    return {
        baslik = baslik,
        yazar = yazar,
        isbn = Y.isbnBul(props),
        kitap_id = Y.binkitapIdBul(props),
    }
end

--- Dosya adlarıyla 1000Kitap kitaplarını eşleştirmek için dizin.
function Y.dosyaDizini(yollar)
    local dizin = {}
    for _i, yol in ipairs(yollar) do
        dizin[#dizin + 1] = { yol = yol, ad = Y.normal(Y.dosyaAdindanBaslik(yol)) }
    end
    return dizin
end

--- 1000Kitap kitabını yerel dosya dizininde arar (başlık dosya adında geçiyorsa).
function Y.dosyadaBul(dizin, baslik)
    local nb = Y.normal(baslik)
    if #nb < 3 then return nil end
    local en_iyi, en_iyi_fark
    for _i, d in ipairs(dizin) do
        if d.ad == nb then return d.yol end
        if d.ad:find(nb, 1, true) then
            local fark = #d.ad - #nb
            if not en_iyi_fark or fark < en_iyi_fark then
                en_iyi, en_iyi_fark = d.yol, fark
            end
        end
    end
    return en_iyi
end

return Y
