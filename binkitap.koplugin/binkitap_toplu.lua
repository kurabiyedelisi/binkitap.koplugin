--[[
1000Kitap eklentisi: dosya tarayıcısı ve toplu işler.

- Dosyaya uzun basınca "1000Kitap" menüsü (eşleştir, durum)
- Seçili / klasördeki kitapları topluca "Okuyacağım" yap
- Kütüphaneyi eşleştir: tüm kitapları tarar, emin olduklarını kendisi eşleştirir
- Bir kitabın vurgularını hepsini ya da seçerek gönder
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ARAMA_ARALIGI = 1.5  -- saniye; kitaplar arası: hem 1000Kitap'ı yormamak hem dokunuşlara yer açmak için
local PARCA = 20           -- bu kadar kitapta bir: ayarları yaz, belleği topla, cihazı dinlendir
local DINLENME = 10        -- saniye

return function(BinKitap)
    local Api, Y = BinKitap.Api, BinKitap.Y
    local kirp, kisalt = Y.kirp, Y.kisalt

    local function dosyaAdi(yol)
        return (yol or ""):match("([^/]+)$") or yol
    end

    local function evDizini()
        local ok, Device = pcall(require, "device")
        local ev = G_reader_settings and G_reader_settings:readSetting("home_dir")
        if not ev and ok and Device then ev = Device.home_dir end
        return ev or "/mnt/onboard"
    end
    BinKitap.evDizini = evDizini

    -------------------------------------------------------------------------
    -- Genel seçim listesi (işaretle / işareti kaldır)
    -------------------------------------------------------------------------

    --- p = { baslik, ogeler = { {metin, ek, secili, veri} }, onay_metni ("…(%1)"), onay = function(veriler),
    --        bilgi (üstte bilgi satırı), aranabilir (listede arama) }
    function BinKitap:secimListesi(p)
        local menu
        local filtre = nil   -- normalleştirilmiş arama metni
        local function gorunur(o)
            if not filtre then return true end
            return Y.normal(o.metin .. " " .. (o.ek or "")):find(filtre, 1, true) ~= nil
        end
        local function itemler()
            local secili = 0
            for _i, o in ipairs(p.ogeler) do if o.secili then secili = secili + 1 end end
            local t = {}
            if p.bilgi then t[#t + 1] = { text = p.bilgi, eylem = "bilgi", dim = true } end
            t[#t + 1] = { text = T(p.onay_metni or _("Seçilenleri gönder (%1)"), secili), bold = true, eylem = "onay" }
            if p.aranabilir then
                if filtre then
                    t[#t + 1] = { text = T(_("Arama: %1 · temizle"), p._arama_metni or ""), eylem = "temizle" }
                else
                    t[#t + 1] = { text = _("Listede ara…"), eylem = "ara" }
                end
            end
            t[#t + 1] = { text = filtre and _("Görünenlerin hepsini seç") or _("Tümünü seç"), eylem = "hepsi" }
            t[#t + 1] = { text = _("Hiçbirini seçme"), eylem = "hicbiri", separator = true }
            for i, o in ipairs(p.ogeler) do
                if gorunur(o) then
                    t[#t + 1] = { text = (o.secili and "☑ " or "☐ ") .. o.metin, mandatory = o.ek, indeks = i }
                end
            end
            if filtre and #t == (p.bilgi and 5 or 4) then
                t[#t + 1] = { text = _("Aramaya uyan kitap yok."), eylem = "bilgi" }
            end
            return t
        end
        local function yenile(m, indeks)
            local t = itemler()
            local sira = 1
            if indeks then
                for i, it in ipairs(t) do if it.indeks == indeks then sira = i; break end end
            end
            local ok = pcall(function() m:switchItemTable(nil, t, sira) end)
            if not ok then
                UIManager:close(m)
                self:secimListesi(p)
            end
        end
        menu = Menu:new{
            title = p.baslik,
            item_table = itemler(),
            covers_fullscreen = true,
            is_borderless = true,
            is_popout = false,
            onMenuSelect = function(m, item)
                if item.eylem == "bilgi" then return true end
                if item.eylem == "onay" then
                    local veriler = {}
                    for _i, o in ipairs(p.ogeler) do
                        if o.secili then veriler[#veriler + 1] = o.veri end
                    end
                    if #veriler == 0 then return true end
                    UIManager:close(m)
                    p.onay(veriler)
                    return true
                elseif item.eylem == "ara" then
                    local dialog
                    dialog = InputDialog:new{
                        title = _("Listede ara"),
                        input = p._arama_metni or "",
                        buttons = {{
                            { text = _("Vazgeç"), id = "close", callback = function() UIManager:close(dialog) end },
                            { text = _("Ara"), is_enter_default = true, callback = function()
                                local q = kirp(dialog:getInputText())
                                UIManager:close(dialog)
                                p._arama_metni = q ~= "" and q or nil
                                filtre = q ~= "" and Y.normal(q) or nil
                                yenile(m)
                            end },
                        }},
                    }
                    UIManager:show(dialog)
                    dialog:onShowKeyboard()
                    return true
                elseif item.eylem == "temizle" then
                    filtre, p._arama_metni = nil, nil
                elseif item.eylem == "hepsi" or item.eylem == "hicbiri" then
                    for _i, o in ipairs(p.ogeler) do
                        if gorunur(o) then o.secili = (item.eylem == "hepsi") end
                    end
                elseif item.indeks then
                    local o = p.ogeler[item.indeks]
                    o.secili = not o.secili
                end
                yenile(m, item.indeks)
                return true
            end,
            close_callback = function() UIManager:close(menu) end,
        }
        UIManager:show(menu)
        return menu
    end

    -------------------------------------------------------------------------
    -- Vurguları gönder: hepsi ya da seçerek
    -------------------------------------------------------------------------

    function BinKitap:topluGonder()
        local kitap = self:kitapBilgisi()
        if not kitap then
            return self:kitapEslestir(function() self:topluGonder() end)
        end
        local liste = self.ui.annotation and self.ui.annotation.annotations
        if type(liste) ~= "table" then
            return self:hataGoster(_("Bu özellik KOReader 2024.07 veya daha yeni bir sürüm gerektirir."))
        end
        local gonderilen = self.ui.doc_settings:readSetting("binkitap_gonderilen") or {}
        local bekleyen = {}
        for _i, a in ipairs(liste) do
            if a.drawer and kirp(a.text) ~= "" and not gonderilen[self:vurguAnahtari(a)] then
                bekleyen[#bekleyen + 1] = a
            end
        end
        if #bekleyen == 0 then
            return self:bildir(_("Bu kitapta gönderilmemiş vurgu yok."))
        end

        local function gonder(secilenler)
            for _i, a in ipairs(secilenler) do
                self:siraya(self:vurgudanOge(kitap, a, false))
                gonderilen[self:vurguAnahtari(a)] = true
            end
            self.ui.doc_settings:saveSetting("binkitap_gonderilen", gonderilen)
            if not Api:kimlikVar() then return self:kimlikUyarisi() end
            NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
        end

        local dialog
        dialog = ButtonDialog:new{
            title = T(_("Bu kitapta daha önce gönderilmemiş %1 vurgu var. Gönderdiklerin 1000Kitap'ta herkese açık alıntı olarak paylaşılır."), #bekleyen),
            buttons = {
                {
                    { text = _("Hepsini gönder"), callback = function()
                        UIManager:close(dialog)
                        gonder(bekleyen)
                    end },
                    { text = _("Seçerek gönder"), callback = function()
                        UIManager:close(dialog)
                        local ogeler = {}
                        for _i, a in ipairs(bekleyen) do
                            local pos = a.page or a.pos0
                            local sayfa = self:basiliSayfa(pos, (type(pos) ~= "string") and a.pageno or nil)
                            ogeler[#ogeler + 1] = {
                                metin = kisalt(kirp(a.text):gsub("%s+", " "), 90),
                                ek = sayfa and T(_("s. %1"), sayfa) or nil,
                                secili = false,
                                veri = a,
                            }
                        end
                        self:secimListesi{
                            baslik = T(_("%1 — vurgular"), kitap.adi),
                            ogeler = ogeler,
                            onay_metni = _("Seçilenleri gönder (%1)"),
                            onay = gonder,
                        }
                    end },
                },
                {{ text = _("Vazgeç"), callback = function() UIManager:close(dialog) end }},
            },
        }
        UIManager:show(dialog)
    end

    -------------------------------------------------------------------------
    -- Otomatik eşleştirme çekirdeği
    -------------------------------------------------------------------------

    --- ISBN/kimlik varsa kesin eşleşme; yoksa başlık ve yazar birebir tutuyorsa eşleşme.
    -- Dönüş: kitap | nil, adaylar, sorgu, hata, hata_turu
    function BinKitap:otomatikEslestir(bilgi)
        local kitap = self:kesinEslesme(bilgi)
        if kitap then return kitap end
        local sorgu = kirp(bilgi.baslik .. " " .. bilgi.yazar)
        if sorgu == "" then return nil, {}, sorgu end
        local sonuclar, err, tur = Api:kitapAra(sorgu)
        if not sonuclar then return nil, nil, sorgu, err, tur end
        if #sonuclar == 0 and bilgi.yazar ~= "" then
            -- Yazar adı farklı yazılmış olabilir: sadece başlıkla dene
            sonuclar, err, tur = Api:kitapAra(bilgi.baslik)
            if not sonuclar then return nil, nil, bilgi.baslik, err, tur end
        end
        local ayni_baslik = {}
        for _i, s in ipairs(sonuclar) do
            if Y.baslikAyni(s.adi, bilgi.baslik) then ayni_baslik[#ayni_baslik + 1] = s end
        end
        if bilgi.yazar ~= "" then
            for _i, s in ipairs(ayni_baslik) do
                if s.yazar ~= "" and Y.yazarUyuyor(bilgi.yazar, s.yazar) then return s end
            end
        elseif #ayni_baslik == 1 then
            return ayni_baslik[1] -- yazar bilinmiyor ama bu başlıkta tek kitap var
        end
        return nil, sonuclar, sorgu
    end

    -------------------------------------------------------------------------
    -- Toplu eşleştirme (ilerleme göstergesi, durdurma, kaldığı yerden devam)
    -------------------------------------------------------------------------

    --- s = { baslik, bitince = function(eminler, belirsizler, durduruldu, hata), ara_kayit = function(belirsizler) }
    -- Kobo'yu kilitlememek için: belge açılmaz (sadece yan dosya / kapak önbelleği / dosya adı),
    -- ayarlar her kitapta değil PARCA kitapta bir yazılır, PARCA kitapta bir DINLENME saniye ara verilir.
    function BinKitap:topluEslestir(dosyalar, s)
        local i, eminler, belirsizler, iptal = 0, {}, {}, false
        local ilerleme, kapatiyorum

        local function goster(ek)
            if ilerleme then
                kapatiyorum = true
                UIManager:close(ilerleme)
                kapatiyorum = false
            end
            local kutu
            kutu = InfoMessage:new{
                text = T(_("%1\n\n%2 / %3 kitap · %4 eşleşti%5\n\nDurdurmak için dokun."), s.baslik, i, #dosyalar, #eminler, ek or ""),
                dismiss_callback = function()
                    if kapatiyorum then return end
                    if ilerleme == kutu then ilerleme = nil end
                    iptal = true
                end,
            }
            ilerleme = kutu
            UIManager:show(kutu)
            UIManager:forceRePaint()
        end

        local function araKayit()
            self.settings:flush()
            if s.ara_kayit then s.ara_kayit(belirsizler) end
            collectgarbage("collect")
        end

        local function bitir(durduruldu, hata)
            if ilerleme then
                kapatiyorum = true
                UIManager:close(ilerleme)
                ilerleme = nil
                kapatiyorum = false
            end
            araKayit()
            s.bitince(eminler, belirsizler, durduruldu, hata)
        end

        local adim
        local function sonraki()
            if iptal then return bitir(true) end
            if i > 0 and i % PARCA == 0 and i < #dosyalar then
                araKayit()
                goster(T(_("\n\nCihaz %1 saniye dinleniyor…"), DINLENME))
                UIManager:scheduleIn(DINLENME, adim)
            else
                UIManager:scheduleIn(ARAMA_ARALIGI, adim)
            end
        end

        adim = function()
            if iptal then return bitir(true) end
            i = i + 1
            local yol = dosyalar[i]
            if not yol then return bitir(false) end
            if i == 1 or i % 5 == 0 or (i - 1) % PARCA == 0 then goster() end
            local bilgi = Y.dosyaBilgisi(self.ui, yol, nil, true)
            local ok, kitap, adaylar, sorgu, err, tur = pcall(function() return self:otomatikEslestir(bilgi) end)
            if not ok then
                logger.warn("1000Kitap: eşleştirme hatası", yol, kitap)
                kitap, adaylar, sorgu = nil, {}, bilgi.baslik
            end
            if kitap then
                self:eslesmeKaydet(yol, kitap, true)
                eminler[#eminler + 1] = { yol = yol, kitap = kitap }
            elseif tur == "ag" or tur == "yetki" then
                i = i - 1
                return bitir(true, err)
            else
                local kisa = {}
                for n, a in ipairs(adaylar or {}) do
                    if n > 5 then break end
                    kisa[#kisa + 1] = a
                end
                belirsizler[yol] = { sorgu = sorgu, adaylar = kisa, baslik = bilgi.baslik }
            end
            sonraki()
        end
        adim()
    end

    --- Emin olunamayan dosyaları tek tek seçtirir.
    -- belirsizler: yol → {sorgu, adaylar, baslik}; secildi(yol, kitap, ertele); devam = {metin, callback} (isteğe bağlı)
    -- toplu_bitti verilirse "otomatik onayla" seçenekleri de çıkar; toplu onaydan sonra bir kez çağrılır.
    function BinKitap:belirsizListesi(belirsizler, secildi, devam, atlandi, toplu_bitti)
        local menu
        local function sayilar()
            local tek, adayli = 0, 0
            for _y, b in pairs(belirsizler) do
                local n = #(b.adaylar or {})
                if n == 1 then tek = tek + 1 end
                if n >= 1 then adayli = adayli + 1 end
            end
            return tek, adayli
        end
        local function itemler()
            local t = {}
            if devam then
                t[#t + 1] = { text = devam.metin(), bold = true, eylem = "devam", separator = true }
            end
            if toplu_bitti then
                local tek, adayli = sayilar()
                if tek > 0 then
                    t[#t + 1] = { text = T(_("Tek adaylıları otomatik onayla (%1)"), tek), eylem = "tek",
                        separator = adayli == tek }
                end
                if adayli > tek then
                    t[#t + 1] = { text = T(_("Hepsini ilk adayla onayla (%1)"), adayli), eylem = "ilk", separator = true }
                end
            end
            local yollar = {}
            for yol in pairs(belirsizler) do yollar[#yollar + 1] = yol end
            table.sort(yollar)
            for _i, yol in ipairs(yollar) do
                local b = belirsizler[yol]
                t[#t + 1] = {
                    text = dosyaAdi(yol),
                    mandatory = (#(b.adaylar or {}) > 0) and T(_("%1 aday"), #b.adaylar) or _("bulunamadı"),
                    yol = yol,
                }
            end
            if #yollar == 0 and not devam then
                t[#t + 1] = { text = _("Gözden geçirilecek kitap kalmadı."), eylem = "bos" }
            end
            return t
        end
        local function yenile()
            local ok = pcall(function() menu:switchItemTable(nil, itemler(), 1) end)
            if not ok then
                UIManager:close(menu)
                self:belirsizListesi(belirsizler, secildi, devam, atlandi)
            end
        end
        menu = Menu:new{
            title = _("Emin olunamayan kitaplar"),
            item_table = itemler(),
            covers_fullscreen = true,
            is_borderless = true,
            is_popout = false,
            onMenuSelect = function(m, item)
                if item.eylem == "devam" then
                    UIManager:close(m)
                    devam.callback()
                    return true
                end
                if item.eylem == "tek" or item.eylem == "ilk" then
                    local secilecek = {}
                    for y, b in pairs(belirsizler) do
                        local n = #(b.adaylar or {})
                        if (item.eylem == "tek" and n == 1) or (item.eylem == "ilk" and n >= 1) then
                            secilecek[#secilecek + 1] = y
                        end
                    end
                    table.sort(secilecek)
                    local aciklama = item.eylem == "tek"
                        and _("Tek aday bulunan %1 kitap o adayla eşleştirilecek.")
                        or _("Aday bulunan %1 kitabın her biri listedeki ilk adayla eşleştirilecek.")
                    UIManager:show(ConfirmBox:new{
                        text = T(aciklama, #secilecek) .. "\n\n"
                            .. _("Bunlar \"otomatik onaylandı\" diye işaretlenir. Birini açtığında eşleşmenin yanlış olabileceğini söyleyip doğrulamanı isteyeceğim; doğrulayana kadar o kitap için durum ve ilerleme kendiliğinden gönderilmez."),
                        ok_text = _("Onayla"),
                        ok_callback = function()
                            for _i, y in ipairs(secilecek) do
                                local b = belirsizler[y]
                                belirsizler[y] = nil
                                local k = {}
                                for a, v in pairs(b.adaylar[1]) do k[a] = v end
                                k.otomatik = true
                                secildi(y, k, true)
                            end
                            toplu_bitti()
                            yenile()
                            self:bildir(T(_("%1 kitap otomatik eşleştirildi."), #secilecek), 3)
                        end,
                    })
                    return true
                end
                if not item.yol then return true end
                local yol = item.yol
                local b = belirsizler[yol]
                local function sec(kitap)
                    belirsizler[yol] = nil
                    secildi(yol, kitap)
                    yenile()
                end
                local atla = { text = _("Atla"), callback = function()
                    belirsizler[yol] = nil
                    if atlandi then atlandi(yol) end
                    yenile()
                end }
                if b.adaylar and #b.adaylar > 0 then
                    NetworkMgr:runWhenOnline(function()
                        if not b.yayinevi_eklendi then
                            local bekle = self:bekle(_("Yayınevleri getiriliyor…"))
                            self:yayineviEkle(b.adaylar, 5)
                            UIManager:close(bekle)
                            b.yayinevi_eklendi = true
                        end
                        self:sonucListesi(b.sorgu, b.adaylar, sec, { atla })
                    end)
                else
                    self:aramaPenceresi(b.sorgu ~= "" and b.sorgu or b.baslik, sec,
                        T(_("1000Kitap'ta ara: %1"), dosyaAdi(yol)))
                end
                return true
            end,
            close_callback = function() UIManager:close(menu) end,
        }
        UIManager:show(menu)
    end

    -------------------------------------------------------------------------
    -- Kütüphaneyi eşleştir
    -------------------------------------------------------------------------

    function BinKitap:kutuphaneBelirsizleri()
        local b = self.settings:readSetting("kutuphane_belirsiz")
        return type(b) == "table" and b or {}
    end

    function BinKitap:belirsizSayisi()
        local n = 0
        for _k in pairs(self:kutuphaneBelirsizleri()) do n = n + 1 end
        return n
    end

    function BinKitap:kutuphaneGozdenGecir()
        local belirsizler = self:kutuphaneBelirsizleri()
        if next(belirsizler) == nil then
            return self:bildir(_("Gözden geçirilecek kitap yok."))
        end
        local function kaydet()
            self.settings:saveSetting("kutuphane_belirsiz", belirsizler)
            self.settings:flush()
        end
        self:belirsizListesi(belirsizler, function(yol, kitap, ertele)
            self:eslesmeKaydet(yol, kitap, ertele)
            if not ertele then kaydet() end
        end, nil, function(yol)
            local atlanan = self.settings:readSetting("kutuphane_atlanan") or {}
            atlanan[yol] = true
            self.settings:saveSetting("kutuphane_atlanan", atlanan)
            kaydet()
        end, kaydet)
    end

    function BinKitap:kutuphaneEslestir()
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        local bekle = self:bekle(_("Kitaplar taranıyor…"))
        local hepsi = Y.kitapDosyalari(evDizini(), true, 5000)
        UIManager:close(bekle)
        local eslesmeler = self.settings:readSetting("eslesmeler") or {}
        local atlanan = self.settings:readSetting("kutuphane_atlanan") or {}
        local belirsiz_onceki = self:kutuphaneBelirsizleri()
        local yapilacak = {}
        for _i, yol in ipairs(hepsi) do
            if not eslesmeler[yol] and not atlanan[yol] and not belirsiz_onceki[yol] then
                yapilacak[#yapilacak + 1] = yol
            end
        end
        if #yapilacak == 0 then
            local n = self:belirsizSayisi()
            if n > 0 then
                return UIManager:show(ConfirmBox:new{
                    text = T(_("Kütüphanendeki %1 kitabın hepsi tarandı. %2 kitap için seçim bekliyor."), #hepsi, n),
                    ok_text = _("Gözden geçir"),
                    ok_callback = function() self:kutuphaneGozdenGecir() end,
                })
            end
            return self:bildir(T(_("Kütüphanendeki %1 kitabın hepsi eşleşmiş."), #hepsi))
        end
        local dakika = math.max(1, math.ceil(#yapilacak * (ARAMA_ARALIGI + 2 + DINLENME / PARCA) / 60))
        UIManager:show(ConfirmBox:new{
            text = T(_("Kütüphanende %1 kitap var; %2 tanesi henüz eşleşmemiş.\n\nISBN'i ya da başlığı ve yazarı birebir tutanları kendim eşleştireceğim, emin olamadıklarını sonda soracağım. Okuma durumların değişmez.\n\nTahmini süre: yaklaşık %3 dakika. İstediğin an durdurabilirsin."), #hepsi, #yapilacak, dakika),
            ok_text = _("Başlat"),
            ok_callback = function()
                NetworkMgr:runWhenOnline(function()
                    local function belirsizKaydet(belirsizler)
                        local tum = self:kutuphaneBelirsizleri()
                        for yol, b in pairs(belirsizler) do tum[yol] = b end
                        self.settings:saveSetting("kutuphane_belirsiz", tum)
                        self.settings:flush()
                    end
                    self:topluEslestir(yapilacak, {
                        baslik = _("Kütüphane eşleştiriliyor"),
                        ara_kayit = belirsizKaydet,
                        bitince = function(eminler, belirsizler, durduruldu, hata)
                            belirsizKaydet(belirsizler)
                            local n_belirsiz = 0
                            for _k in pairs(belirsizler) do n_belirsiz = n_belirsiz + 1 end
                            local satirlar = { T(_("%1 kitap eşleşti."), #eminler) }
                            if n_belirsiz > 0 then
                                satirlar[#satirlar + 1] = T(_("%1 kitap için seçim gerekli."), n_belirsiz)
                            end
                            if durduruldu then
                                satirlar[#satirlar + 1] = hata or _("Durduruldu. Tekrar başlatınca kaldığı yerden devam eder.")
                            end
                            if self:belirsizSayisi() > 0 then
                                UIManager:show(ConfirmBox:new{
                                    text = table.concat(satirlar, "\n"),
                                    ok_text = _("Gözden geçir"),
                                    cancel_text = _("Sonra"),
                                    ok_callback = function() self:kutuphaneGozdenGecir() end,
                                })
                            else
                                UIManager:show(InfoMessage:new{ text = table.concat(satirlar, "\n") })
                            end
                        end,
                    })
                end)
            end,
        })
    end

    -------------------------------------------------------------------------
    -- Toplu "Okuyacağım"
    -------------------------------------------------------------------------

    function BinKitap:seciliDosyalar()
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and FileManager and FileManager.instance
        if not fm or type(fm.selected_files) ~= "table" then return nil end
        local liste = {}
        for yol, secili in pairs(fm.selected_files) do
            if secili and Y.kitapDosyasiMi(yol) then liste[#liste + 1] = yol end
        end
        table.sort(liste)
        return liste
    end

    function BinKitap:mevcutKlasor()
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and FileManager and FileManager.instance
        return (fm and fm.file_chooser and fm.file_chooser.path) or evDizini()
    end

    function BinKitap:topluOkuyacagim()
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        local secili = self:seciliDosyalar()
        if secili and #secili > 0 then
            return self:topluDurumEkle(secili, Api.DURUM.okuyacagim)
        end
        local klasor = self:mevcutKlasor()
        local liste = Y.kitapDosyalari(klasor, false)
        if #liste == 0 then
            return self:bildir(_("Bu klasörde kitap yok. Başka bir klasöre geç ya da \"Seç\" ile kitap seç."))
        end
        local ogeler = {}
        for _i, yol in ipairs(liste) do
            local esl = self:dosyaEslesmesi(yol)
            ogeler[#ogeler + 1] = { metin = dosyaAdi(yol), ek = esl and "✓" or nil, secili = false, veri = yol }
        end
        self:secimListesi{
            baslik = T(_("%1 — Okuyacağım olarak eklenecekler"), dosyaAdi(klasor)),
            ogeler = ogeler,
            onay_metni = _("Seçilenleri ekle (%1)"),
            onay = function(yollar) self:topluDurumEkle(yollar, Api.DURUM.okuyacagim) end,
        }
    end

    --- Okuyacaklarıma ekle: dosya tarayıcısına bağlı olmayan giriş (SimpleUI gibi arayüzlerde de çalışır).
    function BinKitap:okuyacaklaraEkle()
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        local secili = self:seciliDosyalar()
        local dialog
        local function kapatVe(f) return function() UIManager:close(dialog); f() end end
        local satirlar = {}
        if secili and #secili > 0 then
            satirlar[#satirlar + 1] = {{ text = T(_("Dosya tarayıcısında seçtiklerim (%1)"), #secili),
                callback = kapatVe(function() self:topluDurumEkle(secili, Api.DURUM.okuyacagim) end) }}
        end
        satirlar[#satirlar + 1] = {{ text = _("Kobo'daki kitaplarımdan seç"), callback = kapatVe(function() self:okuyacaklaraKobodan() end) }}
        satirlar[#satirlar + 1] = {{ text = _("1000Kitap'ta ara (Kobo'da olmayan kitap)"), callback = kapatVe(function() self:okuyacaklaraAra() end) }}
        satirlar[#satirlar + 1] = {{ text = _("Kapat"), callback = function() UIManager:close(dialog) end }}
        dialog = ButtonDialog:new{
            title = _("1000Kitap'ta Okuyacaklarıma ekle\n\nOkuduğun ya da okumakta olduğun kitaplara dokunulmaz."),
            buttons = satirlar,
        }
        UIManager:show(dialog)
    end

    function BinKitap:okuyacaklaraKobodan()
        local bekle = self:bekle(_("Kitapların taranıyor…"))
        local liste = Y.kitapDosyalari(evDizini(), true, 5000)
        UIManager:close(bekle)
        if #liste == 0 then return self:bildir(_("Kobo'da kitap bulunamadı.")) end
        local ogeler = {}
        for _i, yol in ipairs(liste) do
            local klasor = yol:match("^(.*)/[^/]+$") or ""
            ogeler[#ogeler + 1] = { metin = dosyaAdi(yol), ek = dosyaAdi(klasor), secili = false, veri = yol }
        end
        table.sort(ogeler, function(x, y) return Y.normal(x.metin) < Y.normal(y.metin) end)
        self:secimListesi{
            baslik = _("Okuyacaklarıma eklenecek kitaplar"),
            ogeler = ogeler,
            aranabilir = true,
            onay_metni = _("Seçilenleri ekle (%1)"),
            onay = function(yollar) self:topluDurumEkle(yollar, Api.DURUM.okuyacagim) end,
        }
    end

    function BinKitap:okuyacaklaraAra()
        self:aramaPenceresi("", function(kitap)
            self:siraya({
                tur = "durum", kitap_id = kitap.id, kitap_adi = kitap.adi,
                durum = Api.DURUM.okuyacagim, sadece_bossa = true,
            })
            self:bildir(T(_("“%1” Okuyacaklarına eklenecek."), kitap.adi), 2)
            NetworkMgr:runWhenOnline(function() self:kuyruguGonder(true) end)
        end, _("Okuyacaklarına eklenecek kitabı ara"))
    end

    function BinKitap:onBinKitapOkuyacaklaraEkle()
        self:okuyacaklaraEkle()
        return true
    end

    --- Dosyaları eşleştirir (eşleşmiş olanları tekrar aramaz) ve durumlarını sıraya alır.
    -- sonra(hazir): sıraya alındıktan sonra { {yol, kitap}, ... } ile çağrılır (isteğe bağlı)
    function BinKitap:topluDurumEkle(yollar, durum, sonra)
        local eslesmis, aranacak = {}, {}
        for _i, yol in ipairs(yollar) do
            local esl = self:dosyaEslesmesi(yol)
            if esl then eslesmis[#eslesmis + 1] = { yol = yol, kitap = esl } else aranacak[#aranacak + 1] = yol end
        end

        local function sirala(liste)
            if #liste == 0 then return self:bildir(_("Eklenecek kitap yok.")) end
            local ogeler = {}
            for _i, e in ipairs(liste) do
                ogeler[#ogeler + 1] = {
                    tur = "durum", kitap_id = e.kitap.id, kitap_adi = e.kitap.adi, durum = durum,
                    sadece_bossa = (durum == Api.DURUM.okuyacagim) or nil,
                }
            end
            self:topluSiraya(ogeler)
            if durum == Api.DURUM.okuyacagim then
                self:bildir(T(_("%1 kitap sıraya alındı. Okuduğun ya da okumakta olduğun kitaplara dokunulmaz."), #liste))
            else
                self:bildir(T(_("%1 kitap \"%2\" olarak sıraya alındı."), #liste, Api.DURUM_ADI[durum]))
            end
            NetworkMgr:runWhenOnline(function()
                self:kuyruguGonder(false, sonra and function() sonra(liste) end or nil)
            end)
        end

        if #aranacak == 0 then return sirala(eslesmis) end
        NetworkMgr:runWhenOnline(function()
            self:topluEslestir(aranacak, {
                baslik = _("Kitaplar eşleştiriliyor"),
                bitince = function(eminler, belirsizler, durduruldu, hata)
                    if hata then return self:hataGoster(hata) end
                    local hazir = {}
                    for _i, e in ipairs(eslesmis) do hazir[#hazir + 1] = e end
                    for _i, e in ipairs(eminler) do hazir[#hazir + 1] = e end
                    if durduruldu then return self:bildir(_("Durduruldu. Eşleşenler kaydedildi.")) end
                    if next(belirsizler) == nil then return sirala(hazir) end
                    self:belirsizListesi(belirsizler, function(yol, kitap)
                        self:eslesmeKaydet(yol, kitap)
                        hazir[#hazir + 1] = { yol = yol, kitap = kitap }
                    end, {
                        metin = function() return T(_("Devam: %1 kitabı \"%2\" yap"), #hazir, Api.DURUM_ADI[durum]) end,
                        callback = function() sirala(hazir) end,
                    })
                end,
            })
        end)
    end

    -------------------------------------------------------------------------
    -- Atlananlar (kütüphane eşleştirmesinde "Atla" denenler)
    -------------------------------------------------------------------------

    function BinKitap:atlananSayisi()
        local n = 0
        for _k in pairs(self.settings:readSetting("kutuphane_atlanan") or {}) do n = n + 1 end
        return n
    end

    function BinKitap:atlananlarListesi()
        local menu
        local function atlanan() return self.settings:readSetting("kutuphane_atlanan") or {} end
        local function kaydet(a)
            self.settings:saveSetting("kutuphane_atlanan", a)
            self.settings:flush()
        end
        local function itemler()
            local yollar = {}
            for yol in pairs(atlanan()) do yollar[#yollar + 1] = yol end
            table.sort(yollar)
            local t = {}
            if #yollar > 0 then
                t[#t + 1] = { text = _("Hepsini tekrar taramaya al"), eylem = "hepsi", separator = true }
            else
                t[#t + 1] = { text = _("Atlanan kitap kalmadı."), eylem = "bos" }
            end
            for _i, yol in ipairs(yollar) do
                local klasor = yol:match("^(.*)/[^/]+$") or ""
                t[#t + 1] = { text = dosyaAdi(yol), mandatory = dosyaAdi(klasor), yol = yol }
            end
            return t
        end
        local function yenile()
            local ok = pcall(function() menu:switchItemTable(nil, itemler(), 1) end)
            if not ok then
                UIManager:close(menu)
                self:atlananlarListesi()
            end
        end
        menu = Menu:new{
            title = _("Atlanan kitaplar"),
            item_table = itemler(),
            covers_fullscreen = true,
            is_borderless = true,
            is_popout = false,
            onMenuSelect = function(m, item)
                if item.eylem == "hepsi" then
                    local n = self:atlananSayisi()
                    UIManager:show(ConfirmBox:new{
                        text = T(_("%1 kitap bir sonraki \"Kütüphaneyi eşleştir\"de tekrar aranacak."), n),
                        ok_text = _("Tamam"),
                        ok_callback = function()
                            kaydet({})
                            yenile()
                        end,
                    })
                    return true
                end
                if not item.yol then return true end
                local yol = item.yol
                local dialog
                dialog = ButtonDialog:new{
                    title = dosyaAdi(yol),
                    buttons = {
                        {{ text = _("Şimdi eşleştir"), callback = function()
                            UIManager:close(dialog)
                            self:dosyaEslestir(yol, nil, function() yenile() end)
                        end }},
                        {{ text = _("Tekrar taramaya al"), callback = function()
                            UIManager:close(dialog)
                            local a = atlanan()
                            a[yol] = nil
                            kaydet(a)
                            yenile()
                        end }},
                        {{ text = _("Kapat"), callback = function() UIManager:close(dialog) end }},
                    },
                }
                UIManager:show(dialog)
                return true
            end,
            close_callback = function() UIManager:close(menu) end,
        }
        UIManager:show(menu)
    end

    -------------------------------------------------------------------------
    -- 1000Kitap kitaplığı
    -------------------------------------------------------------------------

    local function dosyaVar(yol)
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        if not ok then return true end
        return lfs.attributes(yol, "mode") == "file"
    end

    -- Kitaplık listesi kısa süre hatırlanır; ekle/çıkar sonrası tazelenir.
    local kitaplik_onbellek = nil   -- { zaman, liste }
    local KITAPLIK_OMRU = 10 * 60

    --- 1000Kitap kitaplığını sayfa sayfa getirir. Sayfalar arasında arayüze nefes aldırır,
    -- ilerlemeyi gösterir; dokununca durur.
    function BinKitap:kitaplikListesi(cb)
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        local kadi = self:kullaniciAdiGerekli()
        if not kadi then return end
        if kitaplik_onbellek and os.time() - kitaplik_onbellek.zaman < KITAPLIK_OMRU then
            return cb(kitaplik_onbellek.liste)
        end
        NetworkMgr:runWhenOnline(function()
            local hepsi, sayfalama, sayfa, iptal = {}, nil, 0, false
            local kutu, kapatiyorum
            local function goster()
                if kutu then kapatiyorum = true; UIManager:close(kutu); kapatiyorum = false end
                local k
                k = InfoMessage:new{
                    text = T(_("1000Kitap kitaplığın getiriliyor…\n\n%1 kitap\n\nDurdurmak için dokun."), #hepsi),
                    dismiss_callback = function()
                        if kapatiyorum then return end
                        if kutu == k then kutu = nil end
                        iptal = true
                    end,
                }
                kutu = k
                UIManager:show(k)
                UIManager:forceRePaint()
            end
            local function kapat()
                if kutu then kapatiyorum = true; UIManager:close(kutu); kutu = nil; kapatiyorum = false end
            end
            local adim
            adim = function()
                if iptal then kapat(); return end
                sayfa = sayfa + 1
                local liste, sonraki_veya_err = Api:rafListesi(kadi, "kutuphanesi", sayfalama)
                if not liste then kapat(); return self:hataGoster(sonraki_veya_err) end
                for _i, k in ipairs(liste) do hepsi[#hepsi + 1] = k end
                sayfalama = sonraki_veya_err
                if not sayfalama or sayfa >= 200 then
                    kapat()
                    kitaplik_onbellek = { zaman = os.time(), liste = hepsi }
                    return cb(hepsi)
                end
                if sayfa % 3 == 0 then goster() end
                UIManager:scheduleIn(0.3, adim)
            end
            goster()
            adim()
        end)
    end

    function BinKitap:kitaplikSirala(tur, kitaplar, yok_biliniyor)
        local ogeler = {}
        for _i, k in ipairs(kitaplar) do
            ogeler[#ogeler + 1] = { tur = tur, kitap_id = k.id, kitap_adi = k.adi, yok_biliniyor = yok_biliniyor or nil }
        end
        self:topluSiraya(ogeler)
        kitaplik_onbellek = nil
        NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
    end

    --- Kobo'daki eşleşmiş kitaplardan kitaplıkta olmayanları seçtirip ekler.
    function BinKitap:kitapligaEkleListesi()
        self:kitaplikListesi(function(kitaplik)
            local idler, adlar = {}, {}
            for _i, k in ipairs(kitaplik) do
                idler[k.id] = true
                adlar[Y.normal(k.adi .. (k.yazar or ""))] = true
            end
            local eslesmeler = self.settings:readSetting("eslesmeler") or {}
            local yollar = {}
            for yol in pairs(eslesmeler) do yollar[#yollar + 1] = yol end
            table.sort(yollar)
            local ogeler, gorulen = {}, {}
            local zaten, baska_baski, cihazdaki = 0, 0, 0
            for _i, yol in ipairs(yollar) do
                local k = eslesmeler[yol]
                if type(k) == "table" and k.id and dosyaVar(yol) and not gorulen[k.id] then
                    gorulen[k.id] = true
                    cihazdaki = cihazdaki + 1
                    if idler[k.id] then
                        zaten = zaten + 1
                    elseif adlar[Y.normal(k.adi .. (k.yazar or ""))] then
                        baska_baski = baska_baski + 1
                    else
                        ogeler[#ogeler + 1] = { metin = BinKitap.kitapEtiketi(k), secili = false, veri = k }
                    end
                end
            end
            local bilgi = T(_("Kobo'daki %1 eşleşmiş kitaptan %2 tanesi zaten kitaplığında, %3 tanesinin başka baskısı var. Eşleşmemiş kitaplar burada görünmez."),
                cihazdaki, zaten, baska_baski)
            if #ogeler == 0 then
                return UIManager:show(InfoMessage:new{ text = bilgi .. "\n\n" .. _("Eklenecek kitap yok.") })
            end
            self:secimListesi{
                baslik = _("Kitaplığa ekle"),
                bilgi = bilgi,
                ogeler = ogeler,
                onay_metni = _("Seçilenleri kitaplığa ekle (%1)"),
                onay = function(kitaplar) self:kitaplikSirala("kitaplik_ekle", kitaplar, true) end,
            }
        end)
    end

    --- 1000Kitap kitaplığındaki kitaplardan seçilenleri çıkarır.
    function BinKitap:kitapliktanCikarListesi()
        self:kitaplikListesi(function(kitaplik)
            if #kitaplik == 0 then return self:bildir(_("1000Kitap kitaplığın boş.")) end
            local bul = self.yerelBulucu and self:yerelBulucu()
            local ogeler = {}
            for _i, k in ipairs(kitaplik) do
                ogeler[#ogeler + 1] = {
                    metin = k.adi .. (k.yazar ~= "" and (" — " .. k.yazar) or ""),
                    ek = (bul and bul(k)) and _("Kobo'da") or nil,
                    secili = false,
                    veri = k,
                }
            end
            self:secimListesi{
                baslik = _("Kitaplığından çıkar"),
                bilgi = T(_("1000Kitap kitaplığındaki %1 kitap. Kobo'da olmayan basılı kitapların da burada olabilir; sadece işaretlediklerin çıkarılır."), #kitaplik),
                ogeler = ogeler,
                onay_metni = _("Seçilenleri çıkar (%1)"),
                onay = function(kitaplar)
                    UIManager:show(ConfirmBox:new{
                        text = T(_("%1 kitap 1000Kitap kitaplığından çıkarılacak. Emin misin?"), #kitaplar),
                        ok_text = _("Çıkar"),
                        ok_callback = function() self:kitaplikSirala("kitaplik_cikar", kitaplar) end,
                    })
                end,
            }
        end)
    end

    function BinKitap:kitaplikMenusu()
        local ogeler = {}
        if self.ui.document then
            ogeler[#ogeler + 1] = {
                text = _("Bu kitabı kitaplığa ekle"),
                callback = function() self:acikKitapKitaplik("kitaplik_ekle") end,
            }
            ogeler[#ogeler + 1] = {
                text = _("Bu kitabı kitaplıktan çıkar"),
                callback = function() self:acikKitapKitaplik("kitaplik_cikar") end,
                separator = true,
            }
        end
        ogeler[#ogeler + 1] = {
            text = _("Kobo'daki kitapları kitaplığa ekle"),
            callback = function() self:kitapligaEkleListesi() end,
            help_text = _("Kobo'daki eşleşmiş kitaplardan 1000Kitap kitaplığında olmayanları listeler; seçtiklerin eklenir."),
        }
        ogeler[#ogeler + 1] = {
            text = _("Kitaplığımdan çıkar"),
            callback = function() self:kitapliktanCikarListesi() end,
            help_text = _("1000Kitap kitaplığındaki tüm kitapları listeler; işaretlediklerin çıkarılır."),
        }
        return ogeler
    end

    function BinKitap:acikKitapKitaplik(tur)
        local kitap = self:kitapBilgisi()
        if not kitap then return self:kitapEslestir(function() self:acikKitapKitaplik(tur) end) end
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        self:kitaplikSirala(tur, { kitap })
    end

    -------------------------------------------------------------------------
    -- Dosyaya uzun basma menüsü
    -------------------------------------------------------------------------

    function BinKitap:dosyaMenusunuKaydet()
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        if not ok or type(FileManager) ~= "table" or not FileManager.addFileDialogButtons then return end
        local eklenti = self
        pcall(function() FileManager:removeFileDialogButtons("binkitap") end)
        pcall(function()
            FileManager:addFileDialogButtons("binkitap", function(file, is_file, book_props)
                if not is_file or not Y.kitapDosyasiMi(file) then return nil end
                return {{
                    text = _("1000Kitap"),
                    callback = function()
                        eklenti:dosyaDialogunuKapat()
                        eklenti:dosyaMenusu(file, book_props)
                    end,
                }}
            end)
        end)
    end

    function BinKitap:dosyaDialogunuKapat()
        local adaylar = {}
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and type(FileManager) == "table" and FileManager.instance
        local function ekle(d) if d then adaylar[#adaylar + 1] = d end end
        if fm then
            ekle(fm.file_chooser and fm.file_chooser.file_dialog)
            ekle(fm.file_dialog)
            ekle(fm.history and fm.history.file_dialog)
            ekle(fm.collections and fm.collections.file_dialog)
        end
        ekle(self.ui.history and self.ui.history.file_dialog)
        ekle(self.ui.collections and self.ui.collections.file_dialog)
        for _i, d in ipairs(adaylar) do pcall(function() UIManager:close(d) end) end
    end

    function BinKitap:dosyaEslestir(yol, book_props, sonra)
        local function kaydet(kitap)
            if self:acikDosya() == yol then
                self:kitapSecildi(kitap, function() if sonra then sonra(self:kitapBilgisi()) end end)
                return
            end
            if not kitap.yayinevi or not kitap.basili_sayfa then
                local b = Api:kitapBilgisi(kitap.id)
                if b then
                    kitap.yayinevi = kitap.yayinevi or b.yayinevi
                    kitap.basili_sayfa = kitap.basili_sayfa or b.sayfa
                end
            end
            self:eslesmeKaydet(yol, kitap)
            local belirsiz = self:kutuphaneBelirsizleri()
            if belirsiz[yol] then
                belirsiz[yol] = nil
                self.settings:saveSetting("kutuphane_belirsiz", belirsiz)
                self.settings:flush()
            end
            self:bildir(T(_("Eşleşti: %1"), BinKitap.kitapEtiketi(kitap)), 2)
            if sonra then sonra(kitap) end
        end
        local bilgi = Y.dosyaBilgisi(self.ui, yol, book_props)
        NetworkMgr:runWhenOnline(function()
            local kesin = (bilgi.isbn or bilgi.kitap_id) and self:kesinEslesme(bilgi)
            if kesin then return kaydet(kesin) end
            self:aramaPenceresi(kirp(bilgi.baslik .. " " .. bilgi.yazar), kaydet,
                T(_("1000Kitap'ta ara: %1"), dosyaAdi(yol)))
        end)
    end

    function BinKitap:dosyaMenusu(yol, book_props)
        local esl = self:dosyaEslesmesi(yol)
        local dialog
        local function durum(d)
            return function()
                UIManager:close(dialog)
                local function sirala(kitap)
                    if self:acikDosya() == yol then return self:durumIstegi(d) end
                    self:siraya({ tur = "durum", kitap_id = kitap.id, kitap_adi = kitap.adi, durum = d })
                    if not Api:kimlikVar() then return self:kimlikUyarisi() end
                    NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
                end
                if esl then sirala(esl) else self:dosyaEslestir(yol, book_props, sirala) end
            end
        end
        local function kitaplik(tur)
            return function()
                UIManager:close(dialog)
                local function sirala(kitap)
                    if not Api:kimlikVar() then return self:kimlikUyarisi() end
                    self:kitaplikSirala(tur, { kitap })
                end
                if esl then sirala(esl) else self:dosyaEslestir(yol, book_props, sirala) end
            end
        end
        dialog = ButtonDialog:new{
            title = (esl and (T(_("1000Kitap: %1"), BinKitap.kitapEtiketi(esl))
                    .. (esl.otomatik and _("\n(otomatik eşleşti, henüz onaylanmadı)") or "")) or _("1000Kitap'ta eşleşmedi"))
                .. "\n" .. dosyaAdi(yol),
            title_align = "left",
            buttons = {
                {{ text = esl and _("Eşleşmeyi değiştir") or _("Eşleştir"), callback = function()
                    UIManager:close(dialog)
                    if esl then
                        self:aramaPenceresi(kirp(esl.adi .. " " .. (esl.yazar or "")), function(kitap)
                            self:eslesmeKaydet(yol, kitap)
                            self:bildir(T(_("Eşleşti: %1"), BinKitap.kitapEtiketi(kitap)), 2)
                        end)
                    else
                        self:dosyaEslestir(yol, book_props)
                    end
                end }},
                {
                    { text = _("Okuyacağım"), callback = durum(Api.DURUM.okuyacagim) },
                    { text = _("Okuyorum"), callback = durum(Api.DURUM.okuyorum) },
                },
                {
                    { text = _("Okudum"), callback = durum(Api.DURUM.okudum) },
                    { text = _("Yarım bıraktım"), callback = durum(Api.DURUM.yarim) },
                },
                {
                    { text = _("Kitaplığa ekle"), callback = kitaplik("kitaplik_ekle") },
                    { text = _("Kitaplıktan çıkar"), callback = kitaplik("kitaplik_cikar") },
                },
                {{ text = _("Kapat"), callback = function() UIManager:close(dialog) end }},
            },
        }
        UIManager:show(dialog)
    end
end
