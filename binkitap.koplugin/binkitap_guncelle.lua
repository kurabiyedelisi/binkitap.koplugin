--[[
1000Kitap eklentisi: GitHub'dan güncelleme.

- Depodaki _meta.lua'nın sürümüne bakar; daha yeniyse sorar.
- Dosyaları önce eklenti klasöründeki .guncelleme klasörüne indirir ve denetler
  (boyut, Lua sözdizimi), sonra eskilerini .yedek klasörüne taşıyıp yenilerini koyar.
  Bir adım bile başarısız olursa eski dosyalar geri konur.
- ayar.lua'ya ve KOReader ayarlarına hiç dokunmaz.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local DEPO = "kurabiyedelisi/binkitap.koplugin"
local DAL = "main"
local KLASOR = "binkitap.koplugin"
local LISTE_URL = "https://api.github.com/repos/" .. DEPO .. "/contents/" .. KLASOR .. "?ref=" .. DAL
local META_URL = "https://raw.githubusercontent.com/" .. DEPO .. "/" .. DAL .. "/" .. KLASOR .. "/_meta.lua"
local DENETIM_ARALIGI = 7 * 24 * 3600
local KORUNAN = { ["ayar.lua"] = true }
local planlandi = false   -- dosya tarayıcısı ve okuyucu aynı anda denetlemesin

local function indir(url)
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local http = require("socket.http")
    local ok_https, https = pcall(require, "ssl.https")
    local parcalar = {}
    local reqt = {
        url = url,
        method = "GET",
        headers = { ["user-agent"] = "binkitap.koplugin", ["accept"] = "*/*" },
        sink = ltn12.sink.table(parcalar),
    }
    local requester = (ok_https and url:sub(1, 6) == "https:") and https or http
    socketutil:set_timeout(15, 60)
    local ok, code, basliklar = pcall(function()
        return socket.skip(1, requester.request(reqt))
    end)
    socketutil:reset_timeout()
    if not ok or basliklar == nil or type(code) ~= "number" then
        logger.warn("1000Kitap güncelleme: ağ hatası", url, code)
        return nil, T(_("Bağlantı hatası: %1"), tostring(code))
    end
    if code == 403 or code == 429 then
        return nil, _("GitHub şu an çok fazla istek aldığını söylüyor. Bir saat sonra tekrar dene.")
    end
    if code ~= 200 then
        logger.warn("1000Kitap güncelleme: HTTP", url, code)
        return nil, T(_("GitHub beklenmeyen bir yanıt verdi (HTTP %1)."), code)
    end
    return table.concat(parcalar)
end

local function jsonCoz(metin)
    local ok, json = pcall(require, "json")
    if not ok then json = require("rapidjson") end
    local ok_dec, veri = pcall(json.decode, metin)
    if ok_dec then return veri end
end

local function surumBul(meta)
    return meta and meta:match('version%s*=%s*"([%d%.]+)"')
end

local function parcala(s)
    local t = {}
    for n in tostring(s or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

--- a, b'den yeni mi?
local function dahaYeni(a, b)
    local x, y = parcala(a), parcala(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

local function klasorHazirla(lfs, yol)
    if lfs.attributes(yol, "mode") == "directory" then
        for ad in lfs.dir(yol) do
            if ad ~= "." and ad ~= ".." then os.remove(yol .. "/" .. ad) end
        end
        return true
    end
    return lfs.mkdir(yol)
end

--- Dosyaları önce geçici klasöre yazar, sonra eskileri yedekleyip yerine koyar.
local function yerlestir(dizin, dosyalar)
    local lfs = require("libs/libkoreader-lfs")
    local gecici, yedek = dizin .. "/.guncelleme", dizin .. "/.yedek"
    for _i, k in ipairs({ gecici, yedek }) do
        local ok, err = klasorHazirla(lfs, k)
        if not ok then return nil, T(_("%1 klasörü hazırlanamadı (%2)."), k, tostring(err)) end
    end
    for _i, f in ipairs(dosyalar) do
        local h, err = io.open(gecici .. "/" .. f.ad, "wb")
        if not h then return nil, tostring(err) end
        h:write(f.icerik)
        h:close()
    end
    local tasinan = {}
    local function geriAl()
        for i = #tasinan, 1, -1 do
            local t = tasinan[i]
            os.remove(dizin .. "/" .. t.ad)
            if t.vardi then os.rename(yedek .. "/" .. t.ad, dizin .. "/" .. t.ad) end
        end
    end
    for _i, f in ipairs(dosyalar) do
        local hedef = dizin .. "/" .. f.ad
        local vardi = lfs.attributes(hedef, "mode") == "file"
        if vardi then
            local ok, err = os.rename(hedef, yedek .. "/" .. f.ad)
            if not ok then geriAl(); return nil, tostring(err) end
        end
        tasinan[#tasinan + 1] = { ad = f.ad, vardi = vardi }
        local ok, err = os.rename(gecici .. "/" .. f.ad, hedef)
        if not ok then geriAl(); return nil, tostring(err) end
    end
    return true
end

return function(BinKitap)

    function BinKitap:eklentiDizini()
        return self.path or BinKitap.DIZIN
    end

    --- Depodaki dosya listesini indirir ve denetler; hepsi sağlamsa yerleştirir.
    function BinKitap:guncellemeKur(yeni)
        local bekle = self:bekle(T(_("1000Kitap %1 indiriliyor…"), yeni))
        local function bitir(hata)
            UIManager:close(bekle)
            if hata then
                self:hataGoster(T(_("Güncelleme kurulamadı: %1\n\nEklentinin şu anki sürümü olduğu gibi duruyor."), hata))
            end
        end
        local liste_metni, err = indir(LISTE_URL)
        if not liste_metni then return bitir(err) end
        local liste = jsonCoz(liste_metni)
        if type(liste) ~= "table" or #liste == 0 then return bitir(_("Depodaki dosya listesi okunamadı.")) end

        local dosyalar, meta_surumu = {}, nil
        for _i, oge in ipairs(liste) do
            if oge.type ~= "file" then
                return bitir(_("Bu sürüm elle kurulmalı (yeni bir klasör içeriyor)."))
            end
            local ad = tostring(oge.name or "")
            if not ad:match("^[%w_%-][%w_%.%-]*$") then
                return bitir(T(_("Beklenmeyen dosya adı: %1"), ad))
            end
            if not KORUNAN[ad] then
                local icerik, ierr = indir(oge.download_url)
                if not icerik then return bitir(ierr) end
                if oge.size and tonumber(oge.size) ~= #icerik then
                    return bitir(T(_("%1 eksik indi."), ad))
                end
                if ad:match("%.lua$") then
                    local derle = loadstring or load
                    local fn, serr = derle(icerik, "=" .. ad)
                    if not fn then return bitir(T(_("%1 bozuk: %2"), ad, tostring(serr))) end
                end
                if ad == "_meta.lua" then meta_surumu = surumBul(icerik) end
                dosyalar[#dosyalar + 1] = { ad = ad, icerik = icerik }
            end
        end
        if not meta_surumu or not dosyalar[1] then
            return bitir(_("İndirilen dosyalarda sürüm bilgisi yok."))
        end
        local dizin = self:eklentiDizini()
        if not dizin then return bitir(_("Eklenti klasörü bulunamadı.")) end
        local ok, yerr = yerlestir(dizin, dosyalar)
        if not ok then return bitir(yerr) end
        bitir()
        logger.info("1000Kitap: güncellendi", BinKitap.SURUM, "->", meta_surumu)
        self.settings:saveSetting("guncelleme_kurulan", meta_surumu)
        self.settings:flush()
        local mesaj = T(_("1000Kitap %1 sürümüne güncellendi. Yeni sürüm KOReader yeniden başlatılınca çalışır."), meta_surumu)
        if UIManager.askForRestart then
            UIManager:askForRestart(mesaj)
        else
            self:bildir(mesaj, 8)
        end
    end

    --- Depodaki sürüme bakar. sessiz: sadece yeni sürüm varsa konuşur, hata göstermez.
    function BinKitap:guncellemeDenetle(sessiz)
        local function denetle()
            local bekle = (not sessiz) and self:bekle(_("Güncelleme denetleniyor…")) or nil
            local meta, err = indir(META_URL)
            if bekle then UIManager:close(bekle) end
            self.settings:saveSetting("guncelleme_son_denetim", os.time())
            self.settings:flush()
            if not meta then
                if not sessiz then self:hataGoster(err) end
                return
            end
            local yeni = surumBul(meta)
            if not yeni then
                if not sessiz then self:hataGoster(_("Depodaki sürüm bilgisi okunamadı.")) end
                return
            end
            if not dahaYeni(yeni, BinKitap.SURUM) then
                if not sessiz then self:bildir(T(_("En son sürümü kullanıyorsun (%1)."), BinKitap.SURUM)) end
                return
            end
            local kurulan = self.settings:readSetting("guncelleme_kurulan")
            if kurulan and not dahaYeni(yeni, kurulan) then
                -- indirildi ama KOReader henüz yeniden başlatılmadı
                if not sessiz then
                    self:bildir(T(_("%1 zaten indirildi. Geçerli olması için KOReader'ı yeniden başlat."), kurulan), 6)
                end
                return
            end
            UIManager:show(ConfirmBox:new{
                text = T(_("1000Kitap eklentisinin yeni sürümü var: %1 (sendeki %2).\n\nŞimdi indirip kurayım mı? Ayarların, hesap bilgilerin ve bekleyen gönderilerin korunur."),
                    yeni, BinKitap.SURUM),
                ok_text = _("Kur"),
                cancel_text = _("Sonra"),
                ok_callback = function() self:guncellemeKur(yeni) end,
            })
        end
        if sessiz then
            if NetworkMgr:isOnline() then denetle() end
        else
            NetworkMgr:runWhenOnline(denetle)
        end
    end

    --- Wi-Fi bağlanınca çağrılır: haftada bir sessizce denetler.
    function BinKitap:guncellemeKendiliginden()
        if self.settings:readSetting("guncelleme_oto") == false then return end
        if planlandi then return end
        local son = self.settings:readSetting("guncelleme_son_denetim") or 0
        if os.time() - son < DENETIM_ARALIGI then return end
        planlandi = true
        UIManager:scheduleIn(15, function()
            planlandi = false
            self:guncellemeDenetle(true)
        end)
    end

    function BinKitap:guncellemeMenuOgeleri()
        return {
            {
                text = T(_("Güncellemeleri denetle (sürüm %1)"), BinKitap.SURUM),
                keep_menu_open = true,
                callback = function() self:guncellemeDenetle(false) end,
            },
            {
                text = _("Haftada bir kendiliğinden denetle"),
                checked_func = function() return self.settings:readSetting("guncelleme_oto") ~= false end,
                callback = function()
                    local acik = self.settings:readSetting("guncelleme_oto") ~= false
                    self.settings:saveSetting("guncelleme_oto", not acik)
                    self.settings:flush()
                end,
                help_text = _("Wi-Fi bağlandığında haftada bir GitHub'daki sürüme bakar. Yeni sürüm varsa sorar; sormadan hiçbir şey kurmaz."),
            },
        }
    end

    BinKitap._guncelleme = { dahaYeni = dahaYeni, surumBul = surumBul, DEPO = DEPO }
end
