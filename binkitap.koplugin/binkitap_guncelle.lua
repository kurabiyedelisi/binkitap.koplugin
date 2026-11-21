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
local API_URL = "https://api.github.com/repos/" .. DEPO
local REF_URL = API_URL .. "/git/ref/heads/" .. DAL

--- ref: commit kimliği (yoksa dal adı). GitHub'ın ham dosya önbelleği yeni bir
--- yayından sonra birkaç dakika eski dosyaları verebiliyor; commit'e sabitlenmiş
--- adresler ise her zaman o commit'in dosyalarını verir.
local function adresler(ref)
    ref = ref or DAL
    local ham = "https://raw.githubusercontent.com/" .. DEPO .. "/" .. ref .. "/" .. KLASOR .. "/"
    return {
        liste = API_URL .. "/contents/" .. KLASOR .. "?ref=" .. ref,
        ham = ham,
        meta = ham .. "_meta.lua",
        yenilik = ham .. "binkitap_yenilikler.lua",
    }
end
local YENILIK_DOSYASI = "binkitap_yenilikler.lua"
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

--- Dalın şu anki commit'i; bulunamazsa nil (o zaman dal adresleri kullanılır).
local function sonCommit()
    local metin = indir(REF_URL)
    local veri = metin and jsonCoz(metin)
    local sha = type(veri) == "table" and type(veri.object) == "table" and veri.object.sha
    if type(sha) == "string" and #sha >= 7 and sha:match("^%x+$") then return sha end
    logger.info("1000Kitap güncelleme: commit bulunamadı, dal adresleri kullanılacak")
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

--- Sürüm notları dosyasını boş bir ortamda okur (kod çalıştırmaz, yalnızca veri döner).
local function yenilikleriCoz(icerik)
    if type(icerik) ~= "string" or icerik == "" then return nil end
    local fn
    local sabitle = rawget(_G, "setfenv")
    if sabitle then -- LuaJIT / Lua 5.1 (KOReader)
        fn = (rawget(_G, "loadstring") or load)(icerik, "=yenilikler")
        if fn then sabitle(fn, {}) end
    else
        fn = load(icerik, "=yenilikler", "t", {})
    end
    if not fn then return nil end
    local ok, veri = pcall(fn)
    if not ok or type(veri) ~= "table" then return nil end
    local liste = {}
    for _i, g in ipairs(veri) do
        if type(g) == "table" and type(g.surum) == "string" and type(g.maddeler) == "table" then
            local m = {}
            for _j, x in ipairs(g.maddeler) do
                if type(x) == "string" then m[#m + 1] = x end
            end
            liste[#liste + 1] = { surum = g.surum, maddeler = m }
        end
    end
    return liste
end

--- eski < sürüm <= yeni aralığındaki notlar. eski yoksa yalnızca "yeni" sürümünkiler.
local function yeniliklerMetni(liste, eski, yeni, kisa)
    local parcalar = {}
    for _i, g in ipairs(liste or {}) do
        local alt_sinir = eski and dahaYeni(g.surum, eski) or (not eski and g.surum == yeni)
        if alt_sinir and not dahaYeni(g.surum, yeni) then
            local satirlar = {}
            if not kisa then satirlar[1] = T(_("Sürüm %1"), g.surum) end
            for _j, m in ipairs(g.maddeler) do
                if kisa and #m > 110 then m = m:sub(1, 107):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "…" end
                satirlar[#satirlar + 1] = "• " .. m
            end
            parcalar[#parcalar + 1] = table.concat(satirlar, "\n")
        end
    end
    if kisa then
        local hepsi = table.concat(parcalar, "\n")
        local satir_say, kes = 0, nil
        for i = 1, #hepsi do
            if hepsi:sub(i, i) == "\n" then
                satir_say = satir_say + 1
                if satir_say == 6 then kes = i; break end
            end
        end
        if kes then hepsi = hepsi:sub(1, kes - 1) .. "\n…" end
        return hepsi ~= "" and hepsi or nil
    end
    return #parcalar > 0 and table.concat(parcalar, "\n\n") or nil
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
    function BinKitap:guncellemeKur(yeni, sha)
        local bekle = self:bekle(T(_("1000Kitap %1 indiriliyor…"), yeni))
        local function bitir(hata)
            UIManager:close(bekle)
            if hata then
                BinKitap.hataKaydet("guncelleme", "Güncelleme", hata)
                self:hataGoster(T(_("Güncelleme kurulamadı: %1\n\nEklentinin şu anki sürümü olduğu gibi duruyor."), hata))
            end
        end
        local adres = adresler(sha or sonCommit())
        local liste_metni, err = indir(adres.liste)
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
                local icerik, ierr = indir(adres.ham .. ad)
                if not icerik then return bitir(ierr) end
                if oge.size and tonumber(oge.size) ~= #icerik then
                    return bitir(T(_("%1 tam inmedi. Bağlantı kesilmiş ya da GitHub dosyaları henüz yenilememiş olabilir; birkaç dakika sonra tekrar dene."), ad))
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
        if not dahaYeni(meta_surumu, BinKitap.SURUM) then
            -- dal adreslerine düşüldüyse önbellek eski dosyaları vermiş olabilir: karışık sürüm kurma
            return bitir(_("GitHub henüz yeni sürümün dosyalarını vermiyor; birkaç dakika sonra tekrar dene."))
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
            local sha = sonCommit()
            local adres = adresler(sha)
            local meta, err = indir(adres.meta)
            if bekle then UIManager:close(bekle) end
            self.settings:saveSetting("guncelleme_son_denetim", os.time())
            self.settings:flush()
            if not meta then
                BinKitap.hataKaydet("ag", "Güncelleme denetimi", err)
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
            -- Sürüm notlarının kısa bir özeti (indirilemezse olmadan sor)
            local notlar = yeniliklerMetni(yenilikleriCoz(indir(adres.yenilik)), BinKitap.SURUM, yeni, true)
            UIManager:show(ConfirmBox:new{
                text = T(_("1000Kitap eklentisinin yeni sürümü var: %1 (sendeki %2).\n\nŞimdi indirip kurayım mı? Ayarların, hesap bilgilerin ve bekleyen gönderilerin korunur."),
                    yeni, BinKitap.SURUM) .. (notlar and ("\n\n" .. _("Yenilikler:") .. "\n" .. notlar) or ""),
                ok_text = _("Kur"),
                cancel_text = _("Sonra"),
                ok_callback = function() self:guncellemeKur(yeni, sha) end,
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

    --- Kurulu sürümün notları
    function BinKitap:yenilikListesi()
        local dizin = self:eklentiDizini()
        if not dizin then return nil end
        local h = io.open(dizin .. "/" .. YENILIK_DOSYASI, "rb")
        if not h then return nil end
        local icerik = h:read("*a")
        h:close()
        return yenilikleriCoz(icerik)
    end

    --- eski verilirse ondan sonraki tüm sürümlerin, yoksa kurulu sürümün notları.
    function BinKitap:yenilikleriGoster(eski)
        local metin = yeniliklerMetni(self:yenilikListesi(), eski, BinKitap.SURUM)
        if not metin then
            return self:bildir(T(_("Sürüm %1 için not bulunamadı."), BinKitap.SURUM))
        end
        local ok, TextViewer = pcall(require, "ui/widget/textviewer")
        local baslik = T(_("1000Kitap %1: neler var"), BinKitap.SURUM)
        if ok and TextViewer then
            UIManager:show(TextViewer:new{ title = baslik, text = metin })
        else
            self:bildir(baslik .. "\n\n" .. metin)
        end
    end

    --- Açılışta: güncellemeden sonra yenilikleri bir kez gösterir.
    function BinKitap:yenilikKontrol()
        local onceki = self.settings:readSetting("son_gorulen_surum")
        if onceki == BinKitap.SURUM then return end
        self.settings:saveSetting("son_gorulen_surum", BinKitap.SURUM)
        self.settings:flush()
        if onceki and not dahaYeni(BinKitap.SURUM, onceki) then return end -- geri dönüş
        -- Bu kaydı tutmayan eski sürümden mi geldi, yoksa ilk kurulum mu?
        if not onceki and not (self.settings:readSetting("guncelleme_kurulan")
                or self.settings:readSetting("eslesmeler") or BinKitap.Api:kimlikVar()) then
            return
        end
        UIManager:scheduleIn(2, function() self:yenilikleriGoster(onceki) end)
    end

    function BinKitap:guncellemeMenuOgeleri()
        return {
            {
                text = _("Bu sürümde neler var"),
                keep_menu_open = true,
                callback = function() self:yenilikleriGoster() end,
            },
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

    BinKitap._guncelleme = { dahaYeni = dahaYeni, surumBul = surumBul, DEPO = DEPO,
        yenilikleriCoz = yenilikleriCoz, yeniliklerMetni = yeniliklerMetni }
end
