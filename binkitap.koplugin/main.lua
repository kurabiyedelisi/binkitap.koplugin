--[[
1000Kitap eklentisi (resmi değildir)

Ana dosya: kurulum, eşleştirme, alıntı gönderme, okuma durumu, ilerleme,
okuma seansları, renkle otomatik gönderim, gönderim sırası, menü.
Dosya tarayıcısı ve toplu işler: binkitap_toplu.lua
Keşif (ne okusam, koleksiyon, bilgi kartı, hedef, uyku ekranı): binkitap_kesif.lua
GitHub'dan güncelleme: binkitap_guncelle.lua
İleti yazma: binkitap_ileti.lua
Okuduklarını aktarma: binkitap_aktar.lua
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local eklenti_dizini = (debug.getinfo(1, "S").source or ""):match("^@(.+)/[^/]+$") or "."

local function yukle(ad)
    local ok, m = pcall(require, ad)
    if ok then return m end
    return dofile(eklenti_dizini .. "/" .. ad .. ".lua")
end

local Api = yukle("binkitap_api")
local Y = yukle("binkitap_yardimci")
local kirp, kisalt = Y.kirp, Y.kisalt

-- Sürüm tek yerde, _meta.lua'da tutulur (güncelleme denetimi de onu okur).
local SURUM = (function()
    local ok, meta = pcall(dofile, eklenti_dizini .. "/_meta.lua")
    return ok and type(meta) == "table" and meta.version or "?"
end)()
local GONDERIM_ARALIGI = 1.5   -- saniye; art arda çok hızlı göndermemek için
local SAYFA_UST_SINIR = 300    -- bir sayfada en fazla bu kadar saniye sayılır (boşta kalma)
local SEANS_ALT_SINIR = 60     -- bundan kısa okuma seansı gönderilmez
local SEANS_UST_SINIR = 4 * 3600

-- Dosya tarayıcısı ve okuyucu ayrı eklenti örnekleri açar; ayarlar ve gönderim
-- kilidi hepsi için ortak olmalı.
local ORTAK = { settings = nil, gonderiliyor = false, wifi_biz_actik = false,
    arka_plan = nil,        -- arka planda gönderim sürüyorsa { gonderilen, hata, hatalar }
    son_etkilesim = 0 }     -- son sayfa çevirme zamanı: okurken araya girmemek için
local ARKA_ARALIK = 3        -- saniye; arka planda iki gönderim arası
local ARKA_SESSIZLIK = 4     -- saniye; sayfa çevirdikten sonra bu kadar beklenir
local TOPLU_ESIK = 5         -- bundan fazla iş tek seferde sıraya girerse arka planda gönderilir

local RENKLER = {
    { kod = "yellow", ad = "Sarı" }, { kod = "orange", ad = "Turuncu" },
    { kod = "red", ad = "Kırmızı" }, { kod = "green", ad = "Yeşil" },
    { kod = "olive", ad = "Zeytin" }, { kod = "cyan", ad = "Camgöbeği" },
    { kod = "blue", ad = "Mavi" }, { kod = "purple", ad = "Mor" },
    { kod = "gray", ad = "Gri" },
}

local KO_DURUMU = {
    complete = Api.DURUM.okudum,
    abandoned = Api.DURUM.yarim,
    reading = Api.DURUM.okuyorum,
    tbr = Api.DURUM.okuyacagim,
}

local BinKitap = WidgetContainer:extend{
    name = "binkitap",
    is_doc_only = false,
}
BinKitap.Api = Api
BinKitap.Y = Y
BinKitap.ORTAK = ORTAK
BinKitap.TOPLU_ESIK = TOPLU_ESIK
BinKitap.SURUM = SURUM
BinKitap.DIZIN = eklenti_dizini

function BinKitap:init()
    if not ORTAK.settings then
        ORTAK.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/binkitap.lua")
    end
    self.settings = ORTAK.settings
    Api.gunluk = BinKitap.hataKaydet
    self:kimlikYukle()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    if self.ui.highlight and self.ui.highlight.addToHighlightDialog then
        self.ui.highlight:addToHighlightDialog("12_binkitap", function(this)
            return {
                text = _("1000Kitap'a gönder"),
                callback = function()
                    local secim = this.selected_text
                    local metin = secim and secim.text
                    local pos = secim and secim.pos0
                    this:onClose()
                    metin = kirp(metin)
                    if metin ~= "" then
                        self:yeniAlinti(metin, pos, nil, "")
                    end
                end,
            }
        end)
    end
    if self.dosyaMenusunuKaydet then self:dosyaMenusunuKaydet() end
    if not self.ui.document and self.ilkAktarimSor then self:ilkAktarimSor() end
    if self.yenilikKontrol then self:yenilikKontrol() end
    -- KOReader yeniden açıldıysa yarım kalan kalabalık sırayı sürdür
    if not ORTAK.arka_plan and Api:kimlikVar() and #self:kuyruk() > TOPLU_ESIK and NetworkMgr:isOnline() then
        UIManager:scheduleIn(10, function() self:yavasGonder() end)
    end
end

function BinKitap:onDispatcherRegisterActions()
    Dispatcher:registerAction("binkitap_simdi_gonder", {
        category = "none", event = "BinKitapSimdiGonder",
        title = _("1000Kitap: bekleyenleri gönder"), general = true,
    })
    Dispatcher:registerAction("binkitap_ileti_yaz", {
        category = "none", event = "BinKitapIletiYaz",
        title = _("1000Kitap: ileti yaz"), general = true,
    })
    Dispatcher:registerAction("binkitap_okuyacaklara_ekle", {
        category = "none", event = "BinKitapOkuyacaklaraEkle",
        title = _("1000Kitap: Okuyacaklarıma ekle"), general = true,
    })
    Dispatcher:registerAction("binkitap_ne_okusam", {
        category = "none", event = "BinKitapNeOkusam",
        title = _("1000Kitap: ne okusam?"), general = true,
    })
    Dispatcher:registerAction("binkitap_ekran", {
        category = "none", event = "BinKitapEkran",
        title = _("1000Kitap: ekranı aç"), general = true,
    })
end

---------------------------------------------------------------------------
-- Kimlik ve genel yardımcılar
---------------------------------------------------------------------------

function BinKitap:kimlikYukle()
    -- Öncelik eklenti klasöründeki ayar.lua dosyasında (bilgisayardan düzenlemek kolay)
    local oturum, cihaz, surum, kadi
    local ok, ayar = pcall(dofile, eklenti_dizini .. "/ayar.lua")
    if ok and type(ayar) == "table" then
        oturum = kirp(ayar.oturum_kodu)
        cihaz = kirp(ayar.cihaz_kodu)
        surum = kirp(ayar.app_surumu)
        kadi = kirp(ayar.kullanici_adi)
    end
    if not oturum or oturum == "" then
        oturum = kirp(self.settings:readSetting("oturum_kodu"))
        cihaz = kirp(self.settings:readSetting("cihaz_kodu"))
    end
    if not kadi or kadi == "" then
        kadi = kirp(self.settings:readSetting("kullanici_adi"))
    end
    self.kullanici_adi = kadi ~= "" and kadi:gsub("^@", "") or nil
    Api:setKimlik(oturum, cihaz, surum)
end

function BinKitap:kimlikPenceresi()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("1000Kitap hesap bilgileri"),
        fields = {
            { text = self.settings:readSetting("oturum_kodu") or "", hint = _("Oturum kodu (oturumkodube çerezi)") },
            { text = self.settings:readSetting("cihaz_kodu") or "", hint = _("Cihaz kodu (cik-v2be çerezi)") },
            { text = self.settings:readSetting("kullanici_adi") or "", hint = _("Kullanıcı adı (profil adresindeki)") },
        },
        buttons = {{
            { text = _("Vazgeç"), id = "close", callback = function() UIManager:close(dialog) end },
            {
                text = _("Kaydet"),
                callback = function()
                    local a = dialog:getFields()
                    self.settings:saveSetting("oturum_kodu", kirp(a[1]))
                    self.settings:saveSetting("cihaz_kodu", kirp(a[2]))
                    self.settings:saveSetting("kullanici_adi", kirp(a[3]))
                    self.settings:flush()
                    UIManager:close(dialog)
                    self:kimlikYukle()
                    self:bildir(_("Kaydedildi."))
                    if self.ilkAktarimSor then self:ilkAktarimSor() end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function BinKitap:kimlikUyarisi()
    UIManager:show(InfoMessage:new{
        text = _("1000Kitap hesap bilgileri girilmemiş.\n\n1000Kitap → Ayarlar → Hesap bilgileri bölümünden ya da eklenti klasöründeki ayar.lua dosyasından girebilirsin."),
    })
end

function BinKitap:kullaniciAdiGerekli()
    if self.kullanici_adi then return self.kullanici_adi end
    UIManager:show(InfoMessage:new{
        text = _("Bu özellik için 1000Kitap kullanıcı adın gerekli (profil adresindeki ad, ör. 1000kitap.com/KullaniciAdin).\n\nAyar.lua dosyasına kullanici_adi olarak ya da 1000Kitap → Ayarlar → Hesap bilgileri'nden ekleyebilirsin."),
    })
    return nil
end

---------------------------------------------------------------------------
-- Hata günlüğü: son 50 hata; aynı hata art arda gelirse sayacı artar
---------------------------------------------------------------------------

local ISLEM_ADI = {
    ["alintilar/alintiEkle"] = "Alıntı", ["koleksiyonlar/not-ayarla"] = "Gizli alıntı",
    ["kitaplar/kitapKutuphanemeEkle"] = "Kitaplık", ["kitaplar/kitapOku"] = "Okuma durumu",
    ["diger/arama"] = "Arama", ["uyeler/kitaplar/liste"] = "Raf listesi", ["iletiler/iletiEkle"] = "İleti",
    ["kitaplar/kitapPuanVer"] = "Puan", ["kitaplar/kitapIncelemeKaydet"] = "İnceleme",
    ["kitaplar/kitapSayfaGuncelle"] = "İlerleme", ["uyeler/okumalar/gunluk/seansTamamla"] = "Okuma seansı",
    ["uye/kitap/modalVeBasimlar"] = "Durum sorgusu", ["kitaplar/basimlar"] = "Baskılar",
    ["kitaplar/kitapCek"] = "Kitap bilgisi",
}
local HATA_TURU = { ag = "bağlantı", yetki = "oturum", sunucu = "1000Kitap reddetti" }

--- Günlüğe yazmadan önce hesap kodlarına benzeyen her şeyi gizle.
local function kodlariGizle(m)
    m = tostring(m or "?")
    for _i, k in ipairs({ Api.oturum_kodu, Api.cihaz_kodu }) do
        if type(k) == "string" and #k >= 6 then
            m = m:gsub(k:gsub("%p", "%%%0"), "•••")
        end
    end
    return (m:gsub("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x", "•••"))
end

function BinKitap.hataKaydet(tur, yer, mesaj)
    local st = ORTAK.settings
    if not st then return end
    mesaj = kodlariGizle(mesaj)
    local g = st:readSetting("hata_gunlugu") or {}
    local son = g[#g]
    local simdi = os.time()
    local islem = ISLEM_ADI[yer or ""] or yer or "?"
    if son and son.islem == islem and son.mesaj == mesaj and simdi - (son.zaman or 0) < 600 then
        son.sayi = (son.sayi or 1) + 1
        son.zaman = simdi
    else
        g[#g + 1] = { zaman = simdi, tur = tur, islem = islem, mesaj = mesaj, sayi = 1 }
        while #g > 50 do table.remove(g, 1) end
    end
    st:saveSetting("hata_gunlugu", g)
    -- Ağ hataları sık ve zararsız: diske her seferinde yazma
    if tur ~= "ag" then st:flush() end
end

function BinKitap:hataSayisi()
    return #(self.settings:readSetting("hata_gunlugu") or {})
end

function BinKitap:hataGunluguMetni()
    local g = self.settings:readSetting("hata_gunlugu") or {}
    if #g == 0 then return _("Kayıtlı hata yok.") end
    local satirlar = {}
    for i = #g, 1, -1 do
        local h = g[i]
        local ust = os.date("%d.%m %H:%M", h.zaman or 0) .. " · " .. h.islem .. " · " .. (HATA_TURU[h.tur] or h.tur or "hata")
        if (h.sayi or 1) > 1 then ust = ust .. T(_(" (%1 kez)"), h.sayi) end
        satirlar[#satirlar + 1] = ust .. "\n" .. h.mesaj
    end
    return table.concat(satirlar, "\n\n")
end

function BinKitap:hataGunluguMenusu()
    return {
        text_func = function() return T(_("Hata günlüğü (%1)"), self:hataSayisi()) end,
        sub_item_table = {
            {
                text = _("Göster"),
                callback = function()
                    local ok, TextViewer = pcall(require, "ui/widget/textviewer")
                    local metin = self:hataGunluguMetni()
                    if ok and TextViewer then
                        UIManager:show(TextViewer:new{ title = _("1000Kitap hata günlüğü"), text = metin })
                    else
                        UIManager:show(InfoMessage:new{ text = metin })
                    end
                end,
            },
            {
                text = _("Temizle"),
                enabled_func = function() return self:hataSayisi() > 0 end,
                callback = function()
                    self.settings:delSetting("hata_gunlugu")
                    self.settings:flush()
                    self:bildir(_("Hata günlüğü temizlendi."))
                end,
            },
        },
        help_text = _("1000Kitap'a gönderilemeyen işlemler ve bağlantı sorunları burada tarihiyle durur. Bir sorun olursa buradakini yazman yeterli."),
        separator = true,
    }
end

function BinKitap:bildir(metin, sure)
    UIManager:show(InfoMessage:new{ text = metin, timeout = sure or 3 })
end

function BinKitap:hataGoster(metin)
    UIManager:show(InfoMessage:new{ text = metin, icon = "notice-warning" })
end

function BinKitap:bekle(metin)
    local m = InfoMessage:new{ text = metin }
    UIManager:show(m)
    UIManager:forceRePaint()
    return m
end

function BinKitap:baglantiTesti()
    if not Api:kimlikVar() then return self:kimlikUyarisi() end
    local kitap = self:kitapBilgisi()
    local sonuc, err = Api:okumaDurumu(kitap and kitap.id or "24319")
    if not sonuc then return self:hataGoster(err) end
    local metin = _("Bağlantı çalışıyor.")
    if kitap then
        metin = metin .. "\n\n" .. T(_("“%1” için 1000Kitap'taki durumun: %2"),
            kitap.adi, Api.DURUM_ADI[sonuc.durum] or tostring(sonuc.durum))
    end
    if not self.kullanici_adi then
        metin = metin .. "\n\n" .. _("Kullanıcı adı girilmemiş; Ne okusam, koleksiyon ve uyku ekranı özellikleri için gerekli.")
    end
    UIManager:show(InfoMessage:new{ text = metin })
end

---------------------------------------------------------------------------
-- Kitap eşleştirme
---------------------------------------------------------------------------

function BinKitap:acikDosya()
    return self.ui.document and self.ui.document.file
end

--- Açık kitabın 1000Kitap eşi (yoksa nil).
function BinKitap:kitapBilgisi()
    if not (self.ui.document and self.ui.doc_settings) then return nil end
    local k = self.ui.doc_settings:readSetting("binkitap")
    if type(k) == "table" and k.id then return k end
    -- Dosya tarayıcısında (kitap açılmadan) yapılmış eşleşme
    local yol = self:acikDosya()
    local eslesmeler = self.settings:readSetting("eslesmeler")
    if yol and type(eslesmeler) == "table" and type(eslesmeler[yol]) == "table" then
        k = {}
        for a, v in pairs(eslesmeler[yol]) do k[a] = v end
        self.ui.doc_settings:saveSetting("binkitap", k)
        return k
    end
    return nil
end

--- Bir dosyanın eşleşmesini eklenti ayarlarına yazar (açık olmasa da).
-- ertele: ayar dosyasını hemen yazma (toplu işlerde arada bir yazılır)
function BinKitap:eslesmeKaydet(yol, kitap, ertele)
    if not yol or not kitap or not kitap.id then return end
    local eslesmeler = self.settings:readSetting("eslesmeler") or {}
    local onceki = eslesmeler[yol]
    local yeni_onay = onceki and onceki.otomatik and not kitap.otomatik and onceki.id == kitap.id
    if self.settings:isTrue("kitapliga_ekle") and not kitap.otomatik
            and (not onceki or onceki.id ~= kitap.id or yeni_onay) then
        if onceki and onceki.id ~= kitap.id then
            -- sadece eklentinin kendi eklediği eski baskıyı çıkar; kullanıcının önceden kitaplığında olana dokunma
            self:siraya({ tur = "kitaplik_cikar", kitap_id = onceki.id, kitap_adi = onceki.adi, otomatik = true })
        end
        self:siraya({ tur = "kitaplik_ekle", kitap_id = kitap.id, kitap_adi = kitap.adi, otomatik = true })
    end
    local atlanan = self.settings:readSetting("kutuphane_atlanan")
    if type(atlanan) == "table" and atlanan[yol] then
        atlanan[yol] = nil
        self.settings:saveSetting("kutuphane_atlanan", atlanan)
    end
    eslesmeler[yol] = { id = kitap.id, adi = kitap.adi, yazar = kitap.yazar, basili_sayfa = kitap.basili_sayfa,
        yayinevi = kitap.yayinevi, otomatik = kitap.otomatik or nil }
    self.settings:saveSetting("eslesmeler", eslesmeler)
    local dosyalar = self.settings:readSetting("kitap_dosyalari") or {}
    dosyalar[tostring(kitap.id)] = yol
    self.settings:saveSetting("kitap_dosyalari", dosyalar)
    if not ertele then self.settings:flush() end
end

function BinKitap:dosyaEslesmesi(yol)
    local eslesmeler = self.settings:readSetting("eslesmeler")
    return type(eslesmeler) == "table" and eslesmeler[yol] or nil
end

function BinKitap:kitapKaydetAyar(kitap)
    self.ui.doc_settings:saveSetting("binkitap", kitap)
    if self.ui.doc_settings.flush then self.ui.doc_settings:flush() end
    self:eslesmeKaydet(self:acikDosya(), kitap)
end

function BinKitap:belgeBilgisi()
    local props = self.ui.doc_props
    if not props and self.ui.document and self.ui.document.getProps then
        local ok, p = pcall(self.ui.document.getProps, self.ui.document)
        if ok then props = p end
    end
    props = props or {}
    -- doc_props bazen tanımlayıcıları içermez; belgeden de dene
    if not props.identifiers and self.ui.document and self.ui.document.getProps then
        local ok, p = pcall(self.ui.document.getProps, self.ui.document)
        if ok and type(p) == "table" and p.identifiers then
            props = setmetatable({ identifiers = p.identifiers }, { __index = props })
        end
    end
    local baslik = kirp(props.display_title or props.title)
    if baslik == "" then baslik = Y.dosyaAdindanBaslik(self:acikDosya()) end
    return {
        baslik = baslik,
        yazar = kirp((props.authors or ""):gsub("\n.*", "")),
        isbn = Y.isbnBul(props),
        kitap_id = Y.binkitapIdBul(props),
    }
end

--- ISBN ya da Calibre'deki 1000kitap kimliğiyle sormadan eşleştirmeyi dener.
-- Dönüş: kitap {id, adi, yazar} ya da nil
function BinKitap:kesinEslesme(bilgi)
    if bilgi.kitap_id then
        local b = Api:kitapBilgisi(bilgi.kitap_id)
        if b then return { id = b.id, adi = b.adi, yazar = b.yazar, basili_sayfa = b.sayfa } end
    end
    if bilgi.isbn then
        local sonuc = Api:kitapAra(bilgi.isbn)
        if sonuc and #sonuc == 1 then return sonuc[1] end
        -- Birden çok sonuç geldiyse ISBN'i tutan baskıyı bul
        for i = 1, math.min(3, sonuc and #sonuc or 0) do
            local b = Api:kitapBilgisi(sonuc[i].id)
            if b and b.isbn:gsub("[%-%s]", "") == bilgi.isbn then
                return { id = b.id, adi = b.adi, yazar = b.yazar, basili_sayfa = b.sayfa, yayinevi = b.yayinevi }
            end
        end
    end
    return nil
end

function BinKitap:kitapEslestir(sonra, onceki_sorgu)
    local bilgi = self:belgeBilgisi()
    if not onceki_sorgu and (bilgi.isbn or bilgi.kitap_id) then
        NetworkMgr:runWhenOnline(function()
            local kitap = self:kesinEslesme(bilgi)
            if kitap then
                self:kitapSecildi(kitap, sonra)
            else
                self:aramaPenceresi(kirp(bilgi.baslik .. " " .. bilgi.yazar), function(s) self:kitapSecildi(s, sonra) end)
            end
        end)
        return
    end
    self:aramaPenceresi(onceki_sorgu or kirp(bilgi.baslik .. " " .. bilgi.yazar),
        function(s) self:kitapSecildi(s, sonra) end)
end

--- Arama kutusu → sonuç listesi → secildi(sonuc)
function BinKitap:aramaPenceresi(sorgu, secildi, baslik)
    local dialog
    dialog = InputDialog:new{
        title = baslik or _("1000Kitap'ta kitap ara"),
        input = sorgu,
        buttons = {{
            { text = _("Vazgeç"), id = "close", callback = function() UIManager:close(dialog) end },
            {
                text = _("Ara"),
                is_enter_default = true,
                callback = function()
                    local q = kirp(dialog:getInputText())
                    UIManager:close(dialog)
                    if q ~= "" then self:aramaYap(q, secildi) end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Arama sonuçlarına yayınevi (ve basılı sayfa) ekler; öğrendiklerini hatırlar.
function BinKitap:yayineviEkle(sonuclar, en_fazla)
    local onbellek = self.settings:readSetting("kitap_onbellek") or {}
    local degisti = false
    for i, s in ipairs(sonuclar) do
        if i > (en_fazla or 6) then break end
        local o = onbellek[s.id]
        if not o then
            local b = Api:kitapBilgisi(s.id)
            if b then
                o = { yayinevi = b.yayinevi, sayfa = b.sayfa, yil = b.baski_yili }
                onbellek[s.id] = o
                degisti = true
            end
        end
        if o then
            s.yayinevi = o.yayinevi
            s.yil = o.yil
            s.basili_sayfa = s.basili_sayfa or o.sayfa
        end
    end
    if degisti then
        local n = 0
        for _k in pairs(onbellek) do n = n + 1 end
        if n > 1000 then onbellek = {} end
        self.settings:saveSetting("kitap_onbellek", onbellek)
        self.settings:flush()
    end
end

--- 1000Kitap genel puanı, kısa: "★ 7,8"
function BinKitap.puanYazi(puan)
    puan = Api.puanOku(puan)
    if not puan then return nil end
    return "★ " .. (string.format("%.1f", puan):gsub("%.", ","))
end

function BinKitap.kitapEtiketi(s)
    local etiket = s.adi
    if s.yazar and s.yazar ~= "" then etiket = etiket .. " — " .. s.yazar end
    local ek = {}
    if s.yayinevi and s.yayinevi ~= "" then ek[#ek + 1] = s.yayinevi end
    if s.yil and s.yil ~= "" and s.yil ~= "0" then ek[#ek + 1] = s.yil end
    if #ek > 0 then etiket = etiket .. " · " .. table.concat(ek, ", ") end
    local p = BinKitap.puanYazi(s.puan)
    if p then etiket = etiket .. " · " .. p end
    return etiket
end

function BinKitap:aramaYap(q, secildi, ek_dugmeler)
    NetworkMgr:runWhenOnline(function()
        local bekle = self:bekle(_("1000Kitap'ta aranıyor…"))
        local sonuclar, err = Api:kitapAra(q)
        if sonuclar then self:yayineviEkle(sonuclar, 6) end
        UIManager:close(bekle)
        if not sonuclar then return self:hataGoster(err) end
        self:sonucListesi(q, sonuclar, secildi, ek_dugmeler)
    end)
end

function BinKitap:sonucListesi(q, sonuclar, secildi, ek_dugmeler)
    local dialog
    local buttons = {}
    for i, s in ipairs(sonuclar) do
        if i > 8 then break end
        buttons[#buttons + 1] = {{
            text = BinKitap.kitapEtiketi(s),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                secildi(s)
            end,
        }}
    end
    if #sonuclar == 0 then
        buttons[#buttons + 1] = {{ text = T(_("“%1” için sonuç yok"), q), enabled = false }}
    end
    local alt = {
        {
            text = _("Yeniden ara"),
            callback = function()
                UIManager:close(dialog)
                self:aramaPenceresi(q, secildi)
            end,
        },
    }
    for _i, d in ipairs(ek_dugmeler or {}) do
        alt[#alt + 1] = {
            text = d.text,
            callback = function()
                UIManager:close(dialog)
                d.callback()
            end,
        }
    end
    alt[#alt + 1] = { text = _("Vazgeç"), callback = function() UIManager:close(dialog) end }
    buttons[#buttons + 1] = alt
    dialog = ButtonDialog:new{ title = _("Hangi kitap?"), buttons = buttons }
    UIManager:show(dialog)
end

--- Gözden geçirmede toplu onaylanan (otomatik) eşleşmeyi kitap açılınca doğrulatır.
-- devam(kitap): eşleşme doğrulandıktan ya da değiştirildikten sonra çağrılır.
function BinKitap:otomatikEslesmeSor(kitap, devam)
    local dialog
    local function sonra()
        if devam then
            local k = self:kitapBilgisi()
            if k and not k.otomatik then devam(k) end
        end
    end
    dialog = ButtonDialog:new{
        title = T(_("Bu kitap 1000Kitap'ta otomatik eşleştirildi:\n\n%1\n\nYanlış olabilir. Doğrulayana kadar bu kitap için durum, ilerleme ve renkli vurgular kendiliğinden gönderilmez."),
            BinKitap.kitapEtiketi(kitap)),
        title_align = "left",
        buttons = {
            {
                { text = _("Doğru"), callback = function()
                    UIManager:close(dialog)
                    kitap.otomatik = nil
                    self:kitapKaydetAyar(kitap)
                    self:bildir(_("Eşleşme onaylandı."), 2)
                    sonra()
                end },
                { text = _("Baskıyı değiştir"), callback = function()
                    UIManager:close(dialog)
                    self:baskiSec()
                end },
            },
            {
                { text = _("Başka kitap ara"), callback = function()
                    UIManager:close(dialog)
                    self:kitapEslestir(sonra)
                end },
                { text = _("Sonra"), callback = function() UIManager:close(dialog) end },
            },
        },
    }
    UIManager:show(dialog)
end

function BinKitap:kitapSecildi(s, sonra)
    local eski = self:kitapBilgisi()
    local kitap = { id = s.id, adi = s.adi, yazar = s.yazar, basili_sayfa = s.basili_sayfa, yayinevi = s.yayinevi }
    if eski then
        for _i, alan in ipairs({ "okuyorum_islendi", "okudum_islendi", "son_ko_durum", "renk_baslangic", "bitis_reddedildi" }) do
            kitap[alan] = eski[alan]
        end
    end
    if not kitap.basili_sayfa or not kitap.yayinevi then
        local b = Api:kitapBilgisi(s.id)
        if b then
            kitap.basili_sayfa = kitap.basili_sayfa or b.sayfa
            kitap.yayinevi = kitap.yayinevi or b.yayinevi
        end
    end
    if not kitap.renk_baslangic then kitap.renk_baslangic = os.date("%Y-%m-%d %H:%M:%S") end
    self:kitapKaydetAyar(kitap)
    self:bildir(T(_("Eşleşti: %1"), kitap.adi), 2)
    if self.settings:nilOrTrue("acilista_okuyorum") and not kitap.okuyorum_islendi then
        self:okuyorumSirala(kitap)
    end
    if sonra then UIManager:scheduleIn(0.5, sonra) end
end

--- Eşleşen kitabın baskısını değiştirir (sayfa numaraları baskıya göre değişir).
function BinKitap:baskiSec(sayfalama_bilgisi, onceki)
    local kitap = self:kitapBilgisi()
    if not kitap then return self:kitapEslestir(function() self:baskiSec() end) end
    NetworkMgr:runWhenOnline(function()
        local bekle = self:bekle(_("Baskılar getiriliyor…"))
        local liste, sonraki = Api:basimlar(kitap.id, sayfalama_bilgisi)
        UIManager:close(bekle)
        if not liste then return self:hataGoster(sonraki) end
        local tumu = {}
        for _i, b in ipairs(onceki or {}) do tumu[#tumu + 1] = b end
        for _i, b in ipairs(liste) do tumu[#tumu + 1] = b end
        local dialog
        local buttons = {}
        for _i, b in ipairs(tumu) do
            local ek = {}
            if b.yayinevi ~= "" then ek[#ek + 1] = b.yayinevi end
            if b.yil ~= "" and b.yil ~= "0" then ek[#ek + 1] = b.yil end
            if b.sayfa then ek[#ek + 1] = T(_("%1 sayfa"), b.sayfa) end
            local etiket = b.adi .. (#ek > 0 and (" — " .. table.concat(ek, ", ")) or "")
            if b.id == kitap.id then etiket = "✓ " .. etiket end
            buttons[#buttons + 1] = {{
                text = etiket,
                align = "left",
                callback = function()
                    UIManager:close(dialog)
                    kitap.id, kitap.adi, kitap.basili_sayfa = b.id, b.adi, b.sayfa or kitap.basili_sayfa
                    kitap.yayinevi = b.yayinevi
                    kitap.otomatik = nil -- baskıyı kendin seçtin: eşleşme onaylandı
                    self:kitapKaydetAyar(kitap)
                    self:bildir(T(_("Baskı: %1"), etiket), 2)
                end,
            }}
        end
        local alt = {}
        if sonraki then
            alt[#alt + 1] = {
                text = _("Daha fazla"),
                callback = function()
                    UIManager:close(dialog)
                    self:baskiSec(sonraki, tumu)
                end,
            }
        end
        alt[#alt + 1] = { text = _("Vazgeç"), callback = function() UIManager:close(dialog) end }
        buttons[#buttons + 1] = alt
        dialog = ButtonDialog:new{ title = _("Hangi baskıyı okuyorsun?"), buttons = buttons }
        UIManager:show(dialog)
    end)
end

---------------------------------------------------------------------------
-- Basılı sayfa numarası
---------------------------------------------------------------------------

function BinKitap:mevcutYuzde()
    local doc = self.ui.document
    if not doc or not doc.getPageCount or not self.ui.getCurrentPage then return nil end
    local toplam = doc:getPageCount()
    local sayfa = self.ui:getCurrentPage()
    if not toplam or toplam <= 0 or not sayfa then return nil end
    return math.max(0, math.min(1, sayfa / toplam))
end

function BinKitap:basiliSayfa(pos, pageno)
    local doc = self.ui.document
    if not doc then return nil end
    -- 1) EPUB'da yayıncının sayfa listesi (referans sayfa) varsa onu kullan
    if type(pos) == "string" and self.ui.pagemap and self.ui.pagemap.wantsPageLabels
            and self.ui.pagemap:wantsPageLabels() and self.ui.pagemap.getXPointerPageLabel then
        local ok, etiket = pcall(self.ui.pagemap.getXPointerPageLabel, self.ui.pagemap, pos)
        if ok and tonumber(etiket) then return tonumber(etiket) end
    end
    -- 2) KOReader sayfası
    local sayfa = pageno
    if not sayfa then
        if type(pos) == "string" and doc.getPageFromXPointer then
            sayfa = doc:getPageFromXPointer(pos)
        elseif type(pos) == "table" and pos.page then
            sayfa = pos.page
        elseif type(pos) == "number" then
            sayfa = pos
        elseif self.ui.getCurrentPage then
            sayfa = self.ui:getCurrentPage()
        end
    end
    if not sayfa then return nil end
    if self.ui.paging then return sayfa end -- PDF/DjVu: sayfa zaten basılı sayfaya yakın
    -- 3) EPUB: okunan yüzdeyi 1000Kitap'taki basılı sayfa sayısına oranla
    local kitap = self:kitapBilgisi()
    local basili = kitap and tonumber(kitap.basili_sayfa)
    local toplam = doc.getPageCount and doc:getPageCount()
    if basili and toplam and toplam > 0 then
        return math.max(1, math.min(basili, math.floor(sayfa / toplam * basili + 0.5)))
    end
    return sayfa
end

---------------------------------------------------------------------------
-- Alıntı ve özel not
---------------------------------------------------------------------------

function BinKitap:yeniAlinti(metin, pos, pageno, not_metni, on_sirada)
    local kitap = self:kitapBilgisi()
    if not kitap then
        return self:kitapEslestir(function()
            self:yeniAlinti(metin, pos, pageno, not_metni, on_sirada)
        end)
    end
    local sayfa = self:basiliSayfa(pos, pageno)
    self:alintiPenceresi({
        kitap_id = kitap.id,
        kitap_adi = kitap.adi,
        otomatik = kitap.otomatik,
        soz = metin,
        sayfa = sayfa and tostring(sayfa) or "",
        ekbilgi = not_metni or "",
        ozel = self.settings:isTrue("alinti_gizli"),
        yorum_ayari = self.settings:readSetting("yorum_ayari") or 0,
        on_sirada = on_sirada,
    })
end

local function yorumAyariAdi(kod)
    for _i, y in ipairs(Api.YORUM_AYARLARI) do
        if y.kod == kod then return y.ad end
    end
    return Api.YORUM_AYARLARI[1].ad
end

function BinKitap:alintiPenceresi(taslak)
    local satirlar = {
        taslak.kitap_adi .. (taslak.otomatik and _(" (otomatik eşleşme, onaylanmadı)") or ""), "",
        "“" .. kisalt(taslak.soz, 700) .. "”", "",
        T(_("Sayfa: %1"), taslak.sayfa ~= "" and taslak.sayfa or "—"),
    }
    if taslak.ekbilgi ~= "" then satirlar[#satirlar + 1] = T(_("Not: %1"), kisalt(taslak.ekbilgi, 200)) end
    if taslak.ozel then
        satirlar[#satirlar + 1] = _("Gizli: yalnızca sen görürsün. 1000Kitap'ta kitabın sayfasında özel notların arasında durur; profilinde ve akışta görünmez.")
    else
        satirlar[#satirlar + 1] = T(_("Herkese açık alıntı · Konu: %1 · Yorumlar: %2"),
            taslak.konu_adi or _("yok"), yorumAyariAdi(taslak.yorum_ayari))
    end
    local dialog
    local function kapatVe(f) return function() UIManager:close(dialog); f() end end
    dialog = ButtonDialog:new{
        title = table.concat(satirlar, "\n"),
        title_align = "left",
        buttons = {
            {
                { text = _("Metni düzenle"), callback = kapatVe(function() self:alanDuzenle(taslak, "soz", _("Alıntı"), true) end) },
                { text = _("Sayfa"), callback = kapatVe(function() self:alanDuzenle(taslak, "sayfa", _("Sayfa numarası"), false) end) },
                { text = _("Not"), callback = kapatVe(function() self:alanDuzenle(taslak, "ekbilgi", _("Ek bilgi / not"), true) end) },
            },
            {
                {
                    text = taslak.ozel and _("Herkese açık yap") or _("Gizli yap"),
                    callback = kapatVe(function()
                        taslak.ozel = not taslak.ozel
                        self:alintiPenceresi(taslak)
                    end),
                },
                { text = _("Konu"), enabled = not taslak.ozel, callback = kapatVe(function() self:konuSec(taslak) end) },
                { text = _("Yorumlar"), enabled = not taslak.ozel, callback = kapatVe(function() self:yorumAyariSec(taslak) end) },
            },
            {
                { text = _("Vazgeç"), callback = function() UIManager:close(dialog) end },
                { text = _("Gönder"), callback = kapatVe(function() self:alintiSirala(taslak) end) },
            },
        },
    }
    UIManager:show(dialog)
end

--- Alıntı ya da ileti taslağının penceresine döner.
function BinKitap:taslakPenceresi(taslak)
    if taslak.ileti then return self:iletiPenceresi(taslak) end
    return self:alintiPenceresi(taslak)
end

function BinKitap:alanDuzenle(taslak, alan, baslik, cok_satir)
    local dialog
    dialog = InputDialog:new{
        title = baslik,
        input = taslak[alan] or "",
        input_type = (alan == "sayfa") and "number" or nil,
        allow_newline = cok_satir,
        buttons = {{
            {
                text = _("Geri"), id = "close",
                callback = function()
                    UIManager:close(dialog)
                    self:taslakPenceresi(taslak)
                end,
            },
            {
                text = _("Tamam"), is_enter_default = not cok_satir,
                callback = function()
                    taslak[alan] = kirp(dialog:getInputText())
                    UIManager:close(dialog)
                    self:taslakPenceresi(taslak)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function BinKitap:konuSec(taslak)
    local dialog
    dialog = InputDialog:new{
        title = _("Konu ara"),
        input = "",
        buttons = {{
            { text = _("Konu yok"), callback = function()
                UIManager:close(dialog)
                taslak.konu_id, taslak.konu_adi = nil, nil
                self:taslakPenceresi(taslak)
            end },
            { text = _("Ara"), is_enter_default = true, callback = function()
                local q = kirp(dialog:getInputText())
                UIManager:close(dialog)
                if q == "" then return self:taslakPenceresi(taslak) end
                NetworkMgr:runWhenOnline(function()
                    local liste, err = Api:konuAra(q)
                    if not liste then
                        self:hataGoster(err)
                        return self:taslakPenceresi(taslak)
                    end
                    local secim
                    local buttons = {}
                    for i, k in ipairs(liste) do
                        if i > 8 then break end
                        buttons[#buttons + 1] = {{ text = k.adi, align = "left", callback = function()
                            UIManager:close(secim)
                            taslak.konu_id, taslak.konu_adi = k.id, k.adi
                            self:taslakPenceresi(taslak)
                        end }}
                    end
                    buttons[#buttons + 1] = {{ text = _("Geri"), callback = function()
                        UIManager:close(secim)
                        self:taslakPenceresi(taslak)
                    end }}
                    secim = ButtonDialog:new{ title = _("Konu seç"), buttons = buttons }
                    UIManager:show(secim)
                end)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function BinKitap:yorumAyariSec(taslak)
    local dialog
    local buttons = {}
    for _i, y in ipairs(Api.YORUM_AYARLARI) do
        buttons[#buttons + 1] = {{
            text = (y.kod == taslak.yorum_ayari and "● " or "○ ") .. y.ad,
            align = "left",
            callback = function()
                UIManager:close(dialog)
                taslak.yorum_ayari = y.kod
                self.settings:saveSetting("yorum_ayari", y.kod)
                self.settings:flush()
                self:taslakPenceresi(taslak)
            end,
        }}
    end
    dialog = ButtonDialog:new{
        title = _("Kimler yorum yapıp alıntılayabilir?\n(Seçimin sonraki alıntı ve iletiler için de hatırlanır.)"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function BinKitap:alintiSirala(taslak)
    if kirp(taslak.soz) == "" then return end
    if taslak.ozel then
        local parcalar = { "“" .. taslak.soz .. "”" }
        if taslak.sayfa ~= "" then parcalar[1] = parcalar[1] .. T(_(" (s. %1)"), taslak.sayfa) end
        if taslak.ekbilgi ~= "" then parcalar[#parcalar + 1] = "\n" .. taslak.ekbilgi end
        self:siraya({
            tur = "ozel_not", kitap_id = taslak.kitap_id, kitap_adi = taslak.kitap_adi,
            metin = table.concat(parcalar, "\n"), anahtar = Api.rastgeleKod(16),
        })
    else
        self:siraya({
            tur = "alinti", kitap_id = taslak.kitap_id, kitap_adi = taslak.kitap_adi,
            soz = taslak.soz, sayfa = taslak.sayfa, ekbilgi = taslak.ekbilgi,
            konu_id = taslak.konu_id, yorum_ayari = taslak.yorum_ayari,
        })
    end
    if taslak.on_sirada then taslak.on_sirada() end
    if not Api:kimlikVar() then return self:kimlikUyarisi() end
    if NetworkMgr:isOnline() then
        self:kuyruguGonder(false)
    else
        self:bildir(_("Sıraya alındı. Wi-Fi açılınca gönderilecek."))
        NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
    end
end

function BinKitap:vurguAnahtari(a)
    return tostring(a.datetime or "") .. "|" .. tostring(a.page or a.pos0 or "")
end

--- Bir vurguyu (KOReader açıklaması) sıra öğesine çevirir.
function BinKitap:vurgudanOge(kitap, a, ozel)
    local pos = a.page or a.pos0
    local sayfa = self:basiliSayfa(pos, (type(pos) ~= "string") and a.pageno or nil)
    sayfa = sayfa and tostring(sayfa) or ""
    if ozel then
        local metin = "“" .. kirp(a.text) .. "”" .. (sayfa ~= "" and T(_(" (s. %1)"), sayfa) or "")
        if kirp(a.note) ~= "" then metin = metin .. "\n\n" .. kirp(a.note) end
        return { tur = "ozel_not", kitap_id = kitap.id, kitap_adi = kitap.adi, metin = metin, anahtar = Api.rastgeleKod(16) }
    end
    return {
        tur = "alinti", kitap_id = kitap.id, kitap_adi = kitap.adi,
        soz = kirp(a.text), sayfa = sayfa, ekbilgi = kirp(a.note),
        yorum_ayari = self.settings:readSetting("yorum_ayari") or 0,
    }
end

--- Renkle otomatik gönderim: eşlenmiş renkteki yeni vurguları sıraya alır.
function BinKitap:renkTaramasi()
    local eylemler = self.settings:readSetting("renk_eylemleri")
    if type(eylemler) ~= "table" or next(eylemler) == nil then return 0 end
    local kitap = self:kitapBilgisi()
    if not kitap or kitap.otomatik then return 0 end -- onaylanınca gönderilir
    local liste = self.ui.annotation and self.ui.annotation.annotations
    if type(liste) ~= "table" then return 0 end
    if not kitap.renk_baslangic then
        -- İlk kez: eski vurguları gönderme, bundan sonrakileri gönder
        kitap.renk_baslangic = os.date("%Y-%m-%d %H:%M:%S")
        self:kitapKaydetAyar(kitap)
        return 0
    end
    local zamanlar = self.settings:readSetting("renk_zamanlari") or {}
    local zaman_eklendi = false
    for renk, eylem in pairs(eylemler) do
        if eylem and not zamanlar[renk] then
            zamanlar[renk] = os.date("%Y-%m-%d %H:%M:%S") -- açılış zamanı bilinmiyorsa temkinli ol
            zaman_eklendi = true
        end
    end
    if zaman_eklendi then
        self.settings:saveSetting("renk_zamanlari", zamanlar)
        self.settings:flush()
    end
    local gonderilen = self.ui.doc_settings:readSetting("binkitap_gonderilen") or {}
    local eklenen = 0
    for _i, a in ipairs(liste) do
        local eylem = a.drawer and a.color and eylemler[a.color]
        local esik = kitap.renk_baslangic
        if eylem and zamanlar[a.color] and zamanlar[a.color] > esik then esik = zamanlar[a.color] end
        if eylem and kirp(a.text) ~= "" and tostring(a.datetime or "") > esik then
            local anahtar = self:vurguAnahtari(a)
            if not gonderilen[anahtar] then
                gonderilen[anahtar] = true
                self:siraya(self:vurgudanOge(kitap, a, eylem == "ozel"))
                eklenen = eklenen + 1
            end
        end
    end
    if eklenen > 0 then
        self.ui.doc_settings:saveSetting("binkitap_gonderilen", gonderilen)
    end
    return eklenen
end

---------------------------------------------------------------------------
-- Okuma durumu, puan, inceleme, bitiş ekranı
---------------------------------------------------------------------------

--- Otomatik (kullanıcı istemeden) yapılan durum değişikliği; istenirse önce sorar.
function BinKitap:otomatikDurum(kitap, durum, secenekler)
    secenekler = secenekler or {}
    if kitap.otomatik then
        logger.info("1000Kitap: onaylanmamış otomatik eşleşme, durum gönderilmedi", kitap.id, durum)
        return
    end
    local function sirala()
        self:siraya({
            tur = "durum", kitap_id = kitap.id, kitap_adi = kitap.adi, durum = durum,
            otomatik = true, sadece_bossa = secenekler.sadece_bossa,
        })
        self:arkaPlanGonder(true)
    end
    if self.settings:isTrue("onay_sor") then
        UIManager:show(ConfirmBox:new{
            text = T(_("“%1” 1000Kitap'ta \"%2\" yapılsın mı?"), kitap.adi, Api.DURUM_ADI[durum]),
            ok_text = _("Evet"),
            ok_callback = sirala,
        })
    else
        sirala()
    end
end

function BinKitap:okuyorumSirala(kitap)
    kitap.okuyorum_islendi = true
    self:kitapKaydetAyar(kitap)
    self:otomatikDurum(kitap, Api.DURUM.okuyorum)
end

function BinKitap:durumIstegi(durum)
    local kitap = self:kitapBilgisi()
    if not kitap then
        return self:kitapEslestir(function() self:durumIstegi(durum) end)
    end
    if durum == Api.DURUM.okudum then kitap.okudum_islendi = true end
    if durum == Api.DURUM.okuyorum then kitap.okuyorum_islendi = true end
    self:kitapKaydetAyar(kitap)
    self:siraya({ tur = "durum", kitap_id = kitap.id, kitap_adi = kitap.adi, durum = durum })
    if not Api:kimlikVar() then return self:kimlikUyarisi() end
    NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
end

function BinKitap:puanSec(secildi)
    local dialog
    local function dugme(n)
        return { text = tostring(n), callback = function() UIManager:close(dialog); secildi(n) end }
    end
    dialog = ButtonDialog:new{
        title = _("Puanın (1–10)"),
        buttons = {
            { dugme(1), dugme(2), dugme(3), dugme(4), dugme(5) },
            { dugme(6), dugme(7), dugme(8), dugme(9), dugme(10) },
            {{ text = _("Puan verme"), callback = function() UIManager:close(dialog); secildi(nil) end }},
        },
    }
    UIManager:show(dialog)
end

function BinKitap:puanIstegi()
    local kitap = self:kitapBilgisi()
    if not kitap then return self:kitapEslestir(function() self:puanIstegi() end) end
    self:puanSec(function(puan)
        if not puan then return end
        self:siraya({ tur = "puan", kitap_id = kitap.id, kitap_adi = kitap.adi, puan = puan })
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
    end)
end

function BinKitap:bitisEkrani()
    local kitap = self:kitapBilgisi()
    if not kitap or kitap.okudum_islendi or not self.settings:nilOrTrue("bitis_ekrani") then return end
    if kitap.otomatik then
        return self:otomatikEslesmeSor(kitap, function() self:bitisEkrani() end)
    end
    self:bitisPenceresi(kitap, { puan = nil, inceleme = "" })
end

function BinKitap:bitisPenceresi(kitap, d)
    local satirlar = {
        T(_("“%1” bitti!"), kitap.adi), "",
        _("1000Kitap'ta \"Okudum\" olarak işaretlenecek."),
        T(_("Puan: %1"), d.puan and tostring(d.puan) or "—"),
        T(_("İnceleme: %1"), d.inceleme ~= "" and kisalt(d.inceleme, 300) or "—"),
    }
    local dialog
    local function kapatVe(f) return function() UIManager:close(dialog); f() end end
    dialog = ButtonDialog:new{
        title = table.concat(satirlar, "\n"),
        title_align = "left",
        buttons = {
            {
                { text = _("Puan ver"), callback = kapatVe(function()
                    self:puanSec(function(p) d.puan = p; self:bitisPenceresi(kitap, d) end)
                end) },
                { text = _("İnceleme yaz"), callback = kapatVe(function()
                    local girdi
                    girdi = InputDialog:new{
                        title = _("Kısa inceleme"),
                        input = d.inceleme,
                        allow_newline = true,
                        buttons = {{
                            { text = _("Geri"), id = "close", callback = function()
                                UIManager:close(girdi); self:bitisPenceresi(kitap, d)
                            end },
                            { text = _("Tamam"), callback = function()
                                d.inceleme = kirp(girdi:getInputText())
                                UIManager:close(girdi); self:bitisPenceresi(kitap, d)
                            end },
                        }},
                    }
                    UIManager:show(girdi)
                    girdi:onShowKeyboard()
                end) },
            },
            {
                { text = _("Şimdi değil"), callback = kapatVe(function()
                    kitap.bitis_reddedildi = true
                    self:kitapKaydetAyar(kitap)
                end) },
                { text = _("Kaydet"), callback = kapatVe(function()
                    kitap.okudum_islendi = true
                    self:kitapKaydetAyar(kitap)
                    self:siraya({ tur = "durum", kitap_id = kitap.id, kitap_adi = kitap.adi, durum = Api.DURUM.okudum })
                    if d.puan then
                        self:siraya({ tur = "puan", kitap_id = kitap.id, kitap_adi = kitap.adi, puan = d.puan })
                    end
                    if d.inceleme ~= "" then
                        self:siraya({ tur = "inceleme", kitap_id = kitap.id, kitap_adi = kitap.adi,
                            metin = d.inceleme, yorum_ayari = self.settings:readSetting("yorum_ayari") or 0 })
                    end
                    if not Api:kimlikVar() then return self:kimlikUyarisi() end
                    NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
                end) },
            },
        },
    }
    UIManager:show(dialog)
end

--- KOReader'daki kitap durumu değiştiyse 1000Kitap'a yansıtır.
function BinKitap:koDurumuKontrol()
    if not self.settings:nilOrTrue("durum_senkron") then return end
    local kitap = self:kitapBilgisi()
    if not kitap or kitap.otomatik then return end -- onaylanınca işlenir
    local ozet = self.ui.doc_settings:readSetting("summary")
    local st = type(ozet) == "table" and ozet.status or nil
    if not st then return end
    if kitap.son_ko_durum == nil then
        kitap.son_ko_durum = st -- ilk görüş: sadece kaydet
        self:kitapKaydetAyar(kitap)
        return
    end
    if kitap.son_ko_durum == st then return end
    kitap.son_ko_durum = st
    local hedef = KO_DURUMU[st]
    if hedef == Api.DURUM.okudum then
        if kitap.bitis_reddedildi then self:kitapKaydetAyar(kitap); return end
        kitap.okudum_islendi = true
    end
    self:kitapKaydetAyar(kitap)
    if hedef then self:otomatikDurum(kitap, hedef) end
end

---------------------------------------------------------------------------
-- Okuma ilerlemesi ve okuma seansları
---------------------------------------------------------------------------

function BinKitap:ilerlemeSirala(kitap)
    if kitap.otomatik then return end
    local yuzde = self:mevcutYuzde()
    if not yuzde then return end
    self:siraya({ tur = "ilerleme", kitap_id = kitap.id, kitap_adi = kitap.adi,
        yuzde = yuzde, basili_sayfa = kitap.basili_sayfa })
end

function BinKitap:seansBaslat()
    self.seans = { toplam = 0, son = os.time() }
end

function BinKitap:seansIlerle()
    if not self.seans then return end
    local simdi = os.time()
    if self.seans.son then
        local fark = simdi - self.seans.son
        if fark > 0 then self.seans.toplam = self.seans.toplam + math.min(fark, SAYFA_UST_SINIR) end
    end
    self.seans.son = simdi
end

--- Seansı bitirir; uygunsa sıraya alır. Dönüş: sıraya alındıysa true
function BinKitap:seansBitir()
    self:seansIlerle()
    local s = self.seans
    self.seans = nil
    if not s or s.toplam < SEANS_ALT_SINIR or not self.settings:isTrue("seans_kaydi") then return false end
    local kitap = self:kitapBilgisi()
    local yuzde = self:mevcutYuzde()
    if not kitap or not yuzde or kitap.otomatik then return false end
    self:siraya({
        tur = "seans", kitap_id = kitap.id, kitap_adi = kitap.adi,
        sure = math.min(s.toplam, SEANS_UST_SINIR), yuzde = yuzde,
        basili_sayfa = kitap.basili_sayfa, istemci_kodu = "W2-" .. Api.rastgeleKod(12),
    })
    return true
end

--- Okumaya ara verirken (kapatma, uyku): seans/ilerleme kaydet, durum senkronu.
function BinKitap:araVer()
    local kitap = self:kitapBilgisi()
    local seans_gitti = self:seansBitir()
    if kitap and not seans_gitti and self.settings:readSetting("ilerleme_modu") == "kapaninca" then
        self:ilerlemeSirala(kitap)
    end
    self:koDurumuKontrol()
    self:renkTaramasi()
end

---------------------------------------------------------------------------
-- Gönderim sırası
---------------------------------------------------------------------------

function BinKitap:kuyruk()
    local k = self.settings:readSetting("kuyruk")
    if type(k) ~= "table" then
        k = {}
        self.settings:saveSetting("kuyruk", k)
    end
    return k
end

local function ayniIs(a, b)
    if a.kitap_id ~= b.kitap_id then return false end
    if b.tur == "durum" or b.tur == "ilerleme" or b.tur == "puan" then return a.tur == b.tur end
    if b.tur == "kitaplik_ekle" or b.tur == "kitaplik_cikar" then
        return a.tur == "kitaplik_ekle" or a.tur == "kitaplik_cikar"
    end
    return false
end

--- Birden çok öğeyi sıraya tek seferde ekler: aynı kitabın bekleyen eski durum/ilerleme/puan/
-- kitaplık işini yenisiyle değiştirir; ayar dosyası bir kez yazılır (yüzlerce kitapta cihaz kilitlenmesin).
function BinKitap:topluSiraya(ogeler)
    local k = self:kuyruk()
    local yeni = {}
    for _i, o in ipairs(ogeler) do
        if o.kitap_id then yeni[tostring(o.kitap_id)] = o end
    end
    local kalan = {}
    for _i, eski in ipairs(k) do
        local o = eski.kitap_id and yeni[tostring(eski.kitap_id)]
        if not (o and ayniIs(eski, o)) then kalan[#kalan + 1] = eski end
    end
    for _i, o in ipairs(ogeler) do kalan[#kalan + 1] = o end
    self.settings:saveSetting("kuyruk", kalan)
    self.settings:flush()
end

function BinKitap:siraya(oge)
    self:topluSiraya({ oge })
end

local function sayfaHesapla(oge, m)
    local toplam = m.toplam_sayfa or tonumber(oge.basili_sayfa)
    if not toplam or toplam <= 0 then return nil, nil end
    return math.max(1, math.min(toplam, math.floor(oge.yuzde * toplam + 0.5))), toplam
end

--- Tek bir sıra öğesini gönderir. Dönüş: sonuç | nil, hata, tür
function BinKitap:ogeGonder(oge)
    if oge.tur == "alinti" then
        local sonuc, err, tur = Api:alintiEkle(oge.kitap_id, oge.soz, oge.sayfa, oge.ekbilgi, {
            ilerlemeyi_guncelle = self.settings:isTrue("ilerleme_guncelle"),
            konu_id = oge.konu_id, yorum_ayari = oge.yorum_ayari,
        })
        if sonuc and self.sonAlintiKaydet then self:sonAlintiKaydet(oge) end
        return sonuc, err, tur
    elseif oge.tur == "ozel_not" then
        local sonuc, err, tur = Api:ozelNotEkle(oge.kitap_id, oge.metin, oge.anahtar)
        if sonuc and self.sonAlintiKaydet then self:sonAlintiKaydet(oge) end
        return sonuc, err, tur
    elseif oge.tur == "ileti" then
        return Api:iletiEkle(oge.metin, {
            baslik = oge.baslik, konu_id = oge.konu_id, konu_adi = oge.konu_adi, yorum_ayari = oge.yorum_ayari,
        })
    elseif oge.tur == "puan" then
        return Api:puanVer(oge.kitap_id, oge.puan)
    elseif oge.tur == "inceleme" then
        return Api:incelemeKaydet(oge.kitap_id, oge.metin, oge.yorum_ayari)
    elseif oge.tur == "kitaplik_ekle" then
        local eklenen = self.settings:readSetting("kitapliga_eklenen") or {}
        if not oge.yok_biliniyor then
            local m, err, tur = Api:okumaDurumu(oge.kitap_id)
            if not m then return nil, err, tur end
            if m.kitaplikta then return { atlandi = true } end
        end
        local sonuc, err, tur = Api:kitapligaEkle(oge.kitap_id)
        if sonuc then
            eklenen[tostring(oge.kitap_id)] = true
            self.settings:saveSetting("kitapliga_eklenen", eklenen)
        end
        return sonuc, err, tur
    elseif oge.tur == "kitaplik_cikar" then
        local eklenen = self.settings:readSetting("kitapliga_eklenen") or {}
        local anahtar = tostring(oge.kitap_id)
        if oge.otomatik and not eklenen[anahtar] then return { atlandi = true, sessiz = true } end
        -- Aynı istek ekle/çıkar diye çalışıyor: sadece gerçekten kitaplıktaysa gönder
        local m, err, tur = Api:okumaDurumu(oge.kitap_id)
        if not m then return nil, err, tur end
        local sonuc
        if m.kitaplikta then
            sonuc, err, tur = Api:kitaplikDegistir(oge.kitap_id)
        else
            sonuc = { atlandi = true, sessiz = oge.otomatik }
        end
        if sonuc and eklenen[anahtar] then
            eklenen[anahtar] = nil
            self.settings:saveSetting("kitapliga_eklenen", eklenen)
        end
        return sonuc, err, tur
    elseif oge.tur == "durum" then
        -- Aynı durumu tekrar göndermek onu kaldırabilir; önce mevcut duruma bak.
        local m, err, tur = Api:okumaDurumu(oge.kitap_id)
        if not m then return nil, err, tur end
        if m.durum == oge.durum then return { atlandi = true } end
        if oge.sadece_bossa and m.durum ~= Api.DURUM.yok then return { atlandi = true } end
        if oge.otomatik and oge.durum == Api.DURUM.okuyorum
                and (m.durum == Api.DURUM.okudum or m.durum == Api.DURUM.okuyorum) then
            return { atlandi = true } -- daha önce okunmuş kitabı açınca "Okudum"u bozma
        end
        -- Tarihli okuma yalnızca kitapta açık bir okuma yokken: yoksa ikinci bir okuma kaydı açılır
        local tarih
        if oge.tarih_bas and oge.tarih_bit and oge.durum == Api.DURUM.okudum
                and (m.durum == Api.DURUM.yok or m.durum == Api.DURUM.okuyacagim) then
            tarih = { bas = oge.tarih_bas, bit = oge.tarih_bit }
        end
        local sonuc, err2, tur2 = Api:durumAyarla(oge.kitap_id, oge.durum, tarih)
        -- Kendi değişikliğimizi "sitede değişmiş" sanıp KOReader'a geri yansıtmayalım
        if sonuc and self.bkDurumKaydet then self:bkDurumKaydet(oge.kitap_id, oge.durum, true) end
        -- Bildirim planlanamazsa bile gönderim başarılıdır
        if sonuc and oge.durum == Api.DURUM.okudum and self.hedefBildirimiPlanla then pcall(self.hedefBildirimiPlanla, self) end
        return sonuc, err2, tur2
    elseif oge.tur == "ilerleme" or oge.tur == "seans" then
        local m, err, tur = Api:okumaDurumu(oge.kitap_id)
        if not m then return nil, err, tur end
        if not m.okuma_id or m.durum ~= Api.DURUM.okuyorum then return { atlandi = true } end
        local sayfa, toplam = sayfaHesapla(oge, m)
        if not sayfa then return { atlandi = true } end
        if oge.tur == "seans" then
            return Api:seansTamamla(m.okuma_id, sayfa, oge.sure, oge.istemci_kodu)
        end
        if m.mevcut_sayfa and sayfa <= m.mevcut_sayfa then return { atlandi = true } end
        return Api:sayfaGuncelle(oge.kitap_id, m.okuma_id, toplam, sayfa)
    end
    return { atlandi = true }
end

local OZET_METNI = {
    alinti = "%1 alıntı gönderildi.", ozel_not = "%1 gizli alıntı gönderildi.", ileti = "%1 ileti paylaşıldı.",
    puan = "%1 puan gönderildi.", inceleme = "%1 inceleme gönderildi.",
    ilerleme = "%1 ilerleme gönderildi.", seans = "%1 okuma seansı gönderildi.",
    kitaplik_ekle = "%1 kitap kitaplığına eklendi.", kitaplik_cikar = "%1 kitap kitaplığından çıkarıldı.",
}

--- Sırayı arka planda, okumayı bölmeden yavaş yavaş gönderir: bir seferde tek iş,
-- işler arasında ARKA_ARALIK saniye; sayfa yeni çevrildiyse biraz bekler. Ağ yoksa durur,
-- Wi-Fi gelince (onNetworkConnected) kaldığı yerden sürer. Bitince kısa bir özet gösterir.
function BinKitap:yavasGonder()
    if ORTAK.arka_plan or #self:kuyruk() == 0 or not Api:kimlikVar() then return end
    ORTAK.arka_plan = { gonderilen = 0, hata = 0, hatalar = {} }
    local adim
    local function devam(sn) UIManager:scheduleIn(sn, adim) end
    local function bitir(mesaj)
        local d = ORTAK.arka_plan
        ORTAK.arka_plan = nil
        self.settings:flush()
        if not d then return end
        local satirlar = {}
        if d.gonderilen > 0 then satirlar[#satirlar + 1] = T(_("1000Kitap: %1 iş arka planda gönderildi."), d.gonderilen) end
        if d.hata > 0 then
            satirlar[#satirlar + 1] = T(_("%1 iş gönderilemedi:"), d.hata)
            for _i, h in ipairs(d.hatalar) do satirlar[#satirlar + 1] = h end
        end
        if mesaj then satirlar[#satirlar + 1] = mesaj end
        if #satirlar > 0 and (d.gonderilen + d.hata >= TOPLU_ESIK or d.hata > 0 or mesaj) then
            UIManager:show(InfoMessage:new{ text = table.concat(satirlar, "\n"), timeout = d.hata > 0 and 8 or 4 })
        end
    end
    local yazilmadi = 0
    adim = function()
        local d = ORTAK.arka_plan
        if not d then return end
        if ORTAK.gonderiliyor then return devam(5) end -- elle gönderim sürüyor
        if not Api:kimlikVar() then return bitir() end
        if not NetworkMgr:isOnline() then
            ORTAK.arka_plan = nil -- Wi-Fi gelince yeniden başlar
            return
        end
        if os.time() - (ORTAK.son_etkilesim or 0) < ARKA_SESSIZLIK then return devam(ARKA_SESSIZLIK) end
        local k = self:kuyruk()
        local oge = k[1]
        if not oge then return bitir() end
        ORTAK.gonderiliyor = true
        local ok, sonuc, err, tur = pcall(function() return self:ogeGonder(oge) end)
        ORTAK.gonderiliyor = false
        if not ok then
            logger.err("1000Kitap: arka plan gönderim hatası", sonuc)
            BinKitap.hataKaydet("eklenti", oge.tur, tostring(sonuc))
            err, tur, sonuc = tostring(sonuc), "sunucu", nil
        end
        if not sonuc and tur == "ag" then
            ORTAK.arka_plan = nil -- sırada kalsın; ağ gelince tekrar denenir
            return
        end
        if not sonuc and tur == "yetki" then
            return bitir(err)
        end
        table.remove(k, 1)
        self.settings:saveSetting("kuyruk", k)
        local tekrarlanabilir = oge.tur == "kitaplik_ekle" or oge.tur == "kitaplik_cikar"
            or oge.tur == "durum" or oge.tur == "ilerleme" or oge.tur == "puan"
        yazilmadi = yazilmadi + 1
        if not tekrarlanabilir or yazilmadi >= 10 then
            self.settings:flush()
            yazilmadi = 0
        end
        if sonuc then
            if not sonuc.atlandi then d.gonderilen = d.gonderilen + 1 end
        else
            d.hata = d.hata + 1
            if #d.hatalar < 5 then
                local ozet = (oge.tur == "alinti" and kisalt(oge.soz or "", 50))
                    or ((oge.tur == "ozel_not" or oge.tur == "ileti") and kisalt(oge.metin or "", 50))
                    or (oge.kitap_adi or "")
                d.hatalar[#d.hatalar + 1] = T(_("• %1: %2"), ozet, err or "?")
            end
            if oge.tur == "ileti" and self.iletiGeriAl then self:iletiGeriAl(oge) end
        end
        if #k == 0 then return bitir() end
        devam(ARKA_ARALIK)
    end
    devam(2)
end

--- Cihaz uykuya geçerken sıradaki birkaç işi hemen gönderir (en fazla 5 iş / 8 sn).
-- Yalnızca başarılı olanlar sıradan çıkar; hata olursa durur, iş sırada kalır.
local UYKU_EN_FAZLA, UYKU_SURESI = 5, 8
function BinKitap:uykuOncesiGonder()
    if not self.settings:nilOrTrue("uykuda_gonder") then return 0 end
    if ORTAK.gonderiliyor or not Api:kimlikVar() or not NetworkMgr:isOnline() then return 0 end
    local k = self:kuyruk()
    if #k == 0 then return 0 end
    local bas, gonderilen = os.time(), 0
    ORTAK.gonderiliyor = true
    while k[1] and gonderilen < UYKU_EN_FAZLA and os.time() - bas < UYKU_SURESI do
        local oge = k[1]
        local ok, sonuc = pcall(function() return self:ogeGonder(oge) end)
        if not ok then
            logger.err("1000Kitap: uyku öncesi gönderim hatası", sonuc)
            BinKitap.hataKaydet("eklenti", oge.tur, tostring(sonuc))
            sonuc = nil
        end
        if not sonuc then break end
        table.remove(k, 1)
        gonderilen = gonderilen + 1
    end
    ORTAK.gonderiliyor = false
    if gonderilen > 0 then
        self.settings:saveSetting("kuyruk", k)
        self.settings:flush()
    end
    return gonderilen
end

--- Bekleyen işleri uygun yoldan sürdürür (çoksa arka planda, azsa sessizce).
function BinKitap:bekleyenleriSurdur(gecikme)
    local n = #self:kuyruk()
    if n == 0 or not Api:kimlikVar() or not NetworkMgr:isOnline() then return end
    if n > TOPLU_ESIK then
        self:yavasGonder()
    else
        UIManager:scheduleIn(gecikme or 3, function()
            if NetworkMgr:isOnline() then self:kuyruguGonder(true) end
        end)
    end
end

--- Elle ya da arka planda gönderim sürüyor mu?
function BinKitap.gonderimSuruyor()
    return ORTAK.gonderiliyor or ORTAK.arka_plan ~= nil
end

function BinKitap:arkaPlandaMi()
    return ORTAK.arka_plan ~= nil
end

--- Çok iş birden sıraya girdiyse arka planda, azsa hemen (ilerlemeyle) gönderir.
function BinKitap:sirayiGonder(yeni_is_sayisi)
    if not Api:kimlikVar() then return self:kimlikUyarisi() end
    if (yeni_is_sayisi or 0) > TOPLU_ESIK then
        self:bildir(T(_("%1 iş sıraya alındı. Arka planda, okumanı bölmeden yavaş yavaş gönderilecek; \"Bekleyen gönderiler\"den izleyebilirsin."), yeni_is_sayisi), 5)
        if NetworkMgr:isOnline() then self:yavasGonder() end
        return
    end
    NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
end

function BinKitap:kuyruguGonder(sessiz, bitince)
    local function son()
        if bitince then bitince() end
    end
    if ORTAK.gonderiliyor then return son() end
    if not Api:kimlikVar() then
        if not sessiz then self:kimlikUyarisi() end
        return son()
    end
    if #self:kuyruk() == 0 then
        if not sessiz then self:bildir(_("Bekleyen gönderi yok.")) end
        return son()
    end
    ORTAK.gonderiliyor = true
    local sayac, durum_mesajlari, hatalar = {}, {}, {}
    local toplam, yapilan, iptal = #self:kuyruk(), 0, false
    local kutu, kapatiyorum
    local ilerleme_goster = not sessiz and toplam >= 10
    local function goster()
        if kutu then kapatiyorum = true; UIManager:close(kutu); kapatiyorum = false end
        local k
        k = InfoMessage:new{
            text = T(_("1000Kitap'a gönderiliyor…\n\n%1 / %2\n\nDurdurmak için dokun; kalanlar sırada bekler."), yapilan, toplam),
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
    local yazilmadi = 0

    local function bitir(durdu_mesaji, durdu_tur)
        if kutu then kapatiyorum = true; UIManager:close(kutu); kutu = nil; kapatiyorum = false end
        if yazilmadi > 0 then self.settings:flush() end
        ORTAK.gonderiliyor = false
        local satirlar = {}
        for tur, n in pairs(sayac) do
            satirlar[#satirlar + 1] = T(_(OZET_METNI[tur] or "%1 gönderildi."), n)
        end
        table.sort(satirlar)
        for _i, m in ipairs(durum_mesajlari) do satirlar[#satirlar + 1] = m end
        for _i, h in ipairs(hatalar) do satirlar[#satirlar + 1] = h end
        local basarili_bir_sey = #satirlar > 0
        if durdu_mesaji then
            satirlar[#satirlar + 1] = durdu_mesaji
            local kalan = #self:kuyruk()
            if kalan > 0 then satirlar[#satirlar + 1] = T(_("%1 gönderi sırada bekliyor."), kalan) end
        end
        if #satirlar > 0 then
            local metin = table.concat(satirlar, "\n")
            if #hatalar > 0 then
                self:hataGoster(metin)
            elseif durdu_mesaji then
                if sessiz and not basarili_bir_sey and durdu_tur ~= "yetki" then
                    logger.info("1000Kitap: gönderim ertelendi:", durdu_mesaji)
                else
                    self:hataGoster(metin)
                end
            else
                self:bildir(metin, sessiz and 2 or 3)
            end
        end
        son()
    end

    local function sonraki()
        if iptal then
            return bitir(_("Durduruldu."), "durdu")
        end
        local k = self:kuyruk()
        local oge = k[1]
        if not oge then return bitir() end
        local ok, sonuc, err, tur = pcall(function() return self:ogeGonder(oge) end)
        if not ok then
            logger.err("1000Kitap: gönderim hatası", sonuc)
            BinKitap.hataKaydet("eklenti", oge.tur, tostring(sonuc))
            err, tur, sonuc = tostring(sonuc), "sunucu", nil
        end
        if not sonuc and (tur == "ag" or tur == "yetki") then
            return bitir(err, tur) -- öğe sırada kalsın, sonra tekrar denenir
        end
        table.remove(k, 1)
        self.settings:saveSetting("kuyruk", k)
        -- Tekrar gönderilmesi zarar vermeyen işlerde ayar dosyasını her seferinde yazma
        local tekrarlanabilir = oge.tur == "kitaplik_ekle" or oge.tur == "kitaplik_cikar"
            or oge.tur == "durum" or oge.tur == "ilerleme" or oge.tur == "puan"
        yazilmadi = yazilmadi + 1
        if not tekrarlanabilir or yazilmadi >= 10 then
            self.settings:flush()
            yazilmadi = 0
        end
        yapilan = yapilan + 1
        if ilerleme_goster and (yapilan == 1 or yapilan % 5 == 0) then goster() end
        if sonuc then
            if oge.tur == "durum" then
                if not sonuc.atlandi then
                    durum_mesajlari[#durum_mesajlari + 1] = T(_("“%1”: %2"), oge.kitap_adi or "?", Api.DURUM_ADI[oge.durum] or "?")
                end
            elseif not sonuc.atlandi then
                sayac[oge.tur] = (sayac[oge.tur] or 0) + 1
            elseif oge.tur == "kitaplik_cikar" and not sonuc.sessiz then
                durum_mesajlari[#durum_mesajlari + 1] = T(_("“%1” zaten kitaplığında değildi."), oge.kitap_adi or "?")
            elseif oge.tur == "kitaplik_ekle" and not oge.otomatik then
                durum_mesajlari[#durum_mesajlari + 1] = T(_("“%1” zaten kitaplığındaydı."), oge.kitap_adi or "?")
            end
        else
            local ozet = (oge.tur == "alinti" and kisalt(oge.soz or "", 60))
                or ((oge.tur == "ozel_not" or oge.tur == "ileti") and kisalt(oge.metin or "", 60))
                or (oge.kitap_adi or "")
            hatalar[#hatalar + 1] = T(_("Gönderilemedi (%1): %2"), ozet, err or "?")
            if oge.tur == "ileti" and self.iletiGeriAl and self:iletiGeriAl(oge) then
                hatalar[#hatalar + 1] = _("İletin kaybolmadı: \"İleti yaz\"ı açınca taslak olarak duruyor.")
            end
        end
        if #k > 0 then
            -- uzun sıralarda 25 işte bir kısa mola: işlemci ve pil rahatlasın
            local bekle = (yapilan % 25 == 0) and 8 or GONDERIM_ARALIGI
            UIManager:scheduleIn(bekle, sonraki)
        else
            bitir()
        end
    end
    if ilerleme_goster then goster() end
    sonraki()
end

--- Arka planda gönderim: bağlıysa hemen; değilse ve izin varsa Wi-Fi'yi açıp
-- gönderdikten sonra kapatır.
function BinKitap:arkaPlanGonder(wifi_acabilir)
    if #self:kuyruk() == 0 or not Api:kimlikVar() then return end
    if NetworkMgr:isOnline() then
        return self:kuyruguGonder(true)
    end
    if not wifi_acabilir or not self.settings:isTrue("otomatik_wifi") then return end
    if not NetworkMgr.turnOnWifiAndWaitForConnection or ORTAK.wifi_biz_actik then return end
    ORTAK.wifi_biz_actik = true
    local ok = pcall(function()
        NetworkMgr:turnOnWifiAndWaitForConnection(function()
            self:kuyruguGonder(true, function()
                if ORTAK.wifi_biz_actik then
                    ORTAK.wifi_biz_actik = false
                    pcall(function() NetworkMgr:turnOffWifi() end)
                end
            end)
        end)
    end)
    if not ok then ORTAK.wifi_biz_actik = false end
end

---------------------------------------------------------------------------
-- Olaylar
---------------------------------------------------------------------------

function BinKitap:onReaderReady()
    self:seansBaslat()
    local kitap = self:kitapBilgisi()
    if kitap then
        if not kitap.renk_baslangic then
            kitap.renk_baslangic = os.date("%Y-%m-%d %H:%M:%S")
            self:kitapKaydetAyar(kitap)
        end
        if not kitap.basili_sayfa and NetworkMgr:isOnline() then
            -- Kütüphane eşleştirmesinde atlanan basılı sayfa sayısını şimdi al
            UIManager:scheduleIn(5, function()
                local b = Api:kitapBilgisi(kitap.id)
                if b and b.sayfa and self.ui.document then
                    kitap.basili_sayfa = b.sayfa
                    kitap.yayinevi = kitap.yayinevi or b.yayinevi
                    self:kitapKaydetAyar(kitap)
                end
            end)
        end
        local function acilisIsleri(k)
            self:koDurumuKontrol()
            if self.acilistaBkDurumu then self:acilistaBkDurumu(k) end
            if self.settings:nilOrTrue("acilista_okuyorum") and not k.okuyorum_islendi then
                self:okuyorumSirala(k)
            end
        end
        if kitap.otomatik then
            UIManager:scheduleIn(1, function()
                if self.ui.document then self:otomatikEslesmeSor(kitap, acilisIsleri) end
            end)
        else
            acilisIsleri(kitap)
        end
    elseif Api:kimlikVar() and NetworkMgr:isOnline() then
        -- ISBN ya da Calibre kimliği varsa sormadan eşleştir
        local bilgi = self:belgeBilgisi()
        if bilgi.isbn or bilgi.kitap_id then
            UIManager:scheduleIn(2, function()
                if self:kitapBilgisi() then return end
                local k = self:kesinEslesme(bilgi)
                if k then self:kitapSecildi(k) end
            end)
        end
    end
    if self.uykuMesajiGuncelle then self:uykuMesajiGuncelle() end
    if #self:kuyruk() > TOPLU_ESIK and Api:kimlikVar() and NetworkMgr:isOnline() then
        self:yavasGonder()
    elseif #self:kuyruk() > 0 and Api:kimlikVar() and NetworkMgr:isOnline() then
        UIManager:scheduleIn(4, function() self:kuyruguGonder(true) end)
    end
end

function BinKitap:onPageUpdate()
    ORTAK.son_etkilesim = os.time()
    self:seansIlerle()
    if self.settings:readSetting("ilerleme_modu") ~= "yuzde10" then return end
    local kitap = self:kitapBilgisi()
    local yuzde = self:mevcutYuzde()
    if not kitap or not yuzde then return end
    local dilim = math.floor(yuzde * 10)
    if dilim > (kitap.son_ilerleme_dilimi or 0) then
        kitap.son_ilerleme_dilimi = dilim
        self:kitapKaydetAyar(kitap)
        self:ilerlemeSirala(kitap)
        self:arkaPlanGonder(false)
    end
end

function BinKitap:onCloseDocument()
    self:araVer()
    self:arkaPlanGonder(true)
end

function BinKitap:onSuspend()
    if self.ui.document then self:araVer() end
    self:uykuOncesiGonder()
end

function BinKitap:onResume()
    if self.ui.document then self:seansBaslat() end
    if self.uykuMesajiGuncelle then self:uykuMesajiGuncelle() end
    -- Wi-Fi uyanınca açık kaldıysa bekleyenleri sürdür; kapalıysa onNetworkConnected halleder
    UIManager:scheduleIn(5, function() self:bekleyenleriSurdur(1) end)
end

function BinKitap:onEndOfBook()
    self:bitisEkrani()
end

function BinKitap:onAnnotationsModified()
    if not self.ui.document then return end
    UIManager:scheduleIn(3, function()
        if not self.ui.document then return end
        if self:renkTaramasi() > 0 then self:arkaPlanGonder(false) end
    end)
end

function BinKitap:onNetworkConnected()
    self:bekleyenleriSurdur(3)
    if self.guncellemeKendiliginden then self:guncellemeKendiliginden() end
end

function BinKitap:onBinKitapSimdiGonder()
    NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
    return true
end

function BinKitap:onBinKitapNeOkusam()
    if self.neOkusam then self:neOkusam() end
    return true
end

---------------------------------------------------------------------------
-- Menü
---------------------------------------------------------------------------

function BinKitap:addToMainMenu(menu_items)
    menu_items.binkitap = {
        text = _("1000Kitap"),
        sorting_hint = "tools",
        sub_item_table_func = function() return self:menuOgeleri() end,
    }
end

function BinKitap:secenekMenusu(anahtar, varsayilan, secenekler)
    local ogeler = {}
    for _i, s in ipairs(secenekler) do
        ogeler[#ogeler + 1] = {
            text = s.ad,
            radio = true,
            checked_func = function()
                local v = self.settings:readSetting(anahtar)
                if v == nil then v = varsayilan end
                return v == s.kod
            end,
            callback = function()
                self.settings:saveSetting(anahtar, s.kod)
                self.settings:flush()
                if s.sonra then s.sonra() end
            end,
            help_text = s.yardim,
        }
    end
    return ogeler
end

function BinKitap:renkMenusu()
    local ogeler = {}
    local secenekler = {
        { kod = nil, ad = _("Gönderme") },
        { kod = "alinti", ad = _("Herkese açık alıntı") },
        { kod = "ozel", ad = _("Gizli alıntı (yalnızca sen)") },
    }
    for _i, r in ipairs(RENKLER) do
        local alt = {}
        for _i, s in ipairs(secenekler) do
            alt[#alt + 1] = {
                text = s.ad,
                radio = true,
                checked_func = function()
                    local e = self.settings:readSetting("renk_eylemleri") or {}
                    return e[r.kod] == s.kod
                end,
                callback = function()
                    local e = self.settings:readSetting("renk_eylemleri") or {}
                    local z = self.settings:readSetting("renk_zamanlari") or {}
                    -- Renk ilk kez açılınca o andan önceki vurgular gönderilmesin
                    if s.kod and not e[r.kod] then z[r.kod] = os.date("%Y-%m-%d %H:%M:%S") end
                    if not s.kod then z[r.kod] = nil end
                    e[r.kod] = s.kod
                    self.settings:saveSetting("renk_eylemleri", e)
                    self.settings:saveSetting("renk_zamanlari", z)
                    self.settings:flush()
                end,
            }
        end
        ogeler[#ogeler + 1] = {
            text_func = function()
                local e = self.settings:readSetting("renk_eylemleri") or {}
                local ad = (e[r.kod] == "alinti" and _("herkese açık alıntı"))
                    or (e[r.kod] == "ozel" and _("gizli alıntı")) or _("gönderme")
                return T(_("%1: %2"), r.ad, ad)
            end,
            sub_item_table = alt,
        }
    end
    ogeler[1].help_text = _("Seçtiğin renkte yeni bir vurgu yaptığında eklenti onu otomatik gönderir. Bir rengi açmadan önce o renkle yaptığın vurgular gönderilmez.")
    return ogeler
end

function BinKitap:ayarlarMenusu()
    local ogeler = {
        self:hataGunluguMenusu(),
        { text = _("Hesap bilgileri"), keep_menu_open = true, callback = function() self:kimlikPenceresi() end },
        {
            text = _("Bağlantıyı test et"), keep_menu_open = true,
            callback = function() NetworkMgr:runWhenOnline(function() self:baglantiTesti() end) end,
            separator = true,
        },
        {
            text = _("Eşleşince / açılınca \"Okuyorum\" yap"),
            checked_func = function() return self.settings:nilOrTrue("acilista_okuyorum") end,
            callback = function() self.settings:flipNilOrTrue("acilista_okuyorum"); self.settings:flush() end,
        },
        {
            text = _("Kitap bitince bitiş ekranını göster"),
            checked_func = function() return self.settings:nilOrTrue("bitis_ekrani") end,
            callback = function() self.settings:flipNilOrTrue("bitis_ekrani"); self.settings:flush() end,
            help_text = _("Kitabın sonunda \"Okudum\", puan ve kısa incelemeyi tek ekranda sorar."),
        },
        {
            text = _("KOReader'daki kitap durumunu yansıt"),
            checked_func = function() return self.settings:nilOrTrue("durum_senkron") end,
            callback = function() self.settings:flipNilOrTrue("durum_senkron"); self.settings:flush() end,
            help_text = _("KOReader'da kitap durumunu değiştirdiğinde 1000Kitap'a da yansır: Bitti → Okudum, Beklemede → Yarım bıraktım, Okunuyor → Okuyorum."),
        },
        {
            text = _("1000Kitap'taki değişiklikleri KOReader'a yansıt"),
            checked_func = function() return self.settings:nilOrTrue("durum_ters") end,
            callback = function() self.settings:flipNilOrTrue("durum_ters"); self.settings:flush() end,
            help_text = _("Bir kitabın durumunu 1000Kitap'ta (site ya da telefon) değiştirdiysen, kitabı Kobo'da açınca KOReader'daki durumu da değiştirmeyi önerir: Okudum → Bitti, Yarım bıraktım → Beklemede, Okuyorum → Okunuyor. Tüm kitaplar için menüdeki \"Durumları 1000Kitap'tan al\"ı kullan."),
        },
        {
            text = _("\"Okudum\"dan sonra hedef ilerlemesini göster"),
            checked_func = function() return self.settings:nilOrTrue("hedef_bildirimi") end,
            callback = function() self.settings:flipNilOrTrue("hedef_bildirimi"); self.settings:flush() end,
            help_text = _("Bir kitap 1000Kitap'ta \"Okudum\" olunca yıllık okuma hedefinde nerede olduğunu kısa bir bildirimle gösterir. Hedefin yoksa bir şey göstermez."),
        },
        {
            text = _("Otomatik durum değişikliklerinde onay iste"),
            checked_func = function() return self.settings:isTrue("onay_sor") end,
            callback = function() self.settings:flipTrue("onay_sor"); self.settings:flush() end,
            separator = true,
        },
        {
            text_func = function()
                local m = self.settings:readSetting("ilerleme_modu") or "kapali"
                local ad = (m == "kapaninca" and _("kitabı kapatınca")) or (m == "yuzde10" and _("her %10'da")) or _("kapalı")
                return T(_("Okuma ilerlemesi: %1"), ad)
            end,
            sub_item_table = self:secenekMenusu("ilerleme_modu", "kapali", {
                { kod = "kapali", ad = _("Gönderme") },
                { kod = "kapaninca", ad = _("Kitabı kapatınca / uykuya geçince") },
                { kod = "yuzde10", ad = _("Her %10'da bir") },
            }),
            help_text = _("Dikkat: 1000Kitap'ta \"Okuduğun sayfa sayısını güncellerken yeni bir gönderi paylaşılsın mı?\" ayarı açıksa her güncelleme herkese açık bir gönderi oluşturur. Önce o ayarı kapatmanı öneririm."),
        },
        {
            text = _("Okuma seanslarını kaydet (günlük seri)"),
            checked_func = function() return self.settings:isTrue("seans_kaydi") end,
            callback = function() self.settings:flipTrue("seans_kaydi"); self.settings:flush() end,
            help_text = _("Kitabı kapatınca ya da cihaz uykuya geçince okuduğun süreyi ve sayfayı 1000Kitap'taki okuma seanslarına ekler. 1 dakikadan kısa seanslar gönderilmez; bir sayfada 5 dakikadan uzun kalınan süre sayılmaz. Sayfa güncellemesi paylaşımı ayarın açıksa bir gönderi de oluşabilir."),
        },
        {
            text = _("Alıntıyla okuma ilerlemesini de güncelle"),
            checked_func = function() return self.settings:isTrue("ilerleme_guncelle") end,
            callback = function() self.settings:flipTrue("ilerleme_guncelle"); self.settings:flush() end,
            separator = true,
        },
        {
            text = _("Eşleşen kitapları 1000Kitap kitaplığıma ekle"),
            checked_func = function() return self.settings:isTrue("kitapliga_ekle") end,
            callback = function() self.settings:flipTrue("kitapliga_ekle"); self.settings:flush() end,
            help_text = _("Bir kitap 1000Kitap'la eşleştiğinde (kütüphane eşleştirmesi dahil) 1000Kitap'taki kitaplığına da eklenir. Eşleşmeyi değiştirirsen eklentinin eklediği eski baskı çıkarılır; önceden kitaplığında olan kitaplara dokunulmaz."),
            separator = true,
        },
        {
            text = _("Alıntıları varsayılan olarak gizli paylaş"),
            checked_func = function() return self.settings:isTrue("alinti_gizli") end,
            callback = function() self.settings:flipTrue("alinti_gizli"); self.settings:flush() end,
            help_text = _("Açıksa alıntı penceresi \"Gizli\" seçili açılır ve toplu gönderimde önce gizli seçenek gelir. Gizli alıntılar 1000Kitap'ta kitabın sayfasında yalnızca senin görebildiğin özel not olarak saklanır."),
        },
        { text = _("Renkle otomatik gönderim"), sub_item_table = self:renkMenusu() },
        {
            text_func = function()
                return T(_("Alıntılarda yorum izni: %1"), yorumAyariAdi(self.settings:readSetting("yorum_ayari") or 0))
            end,
            sub_item_table = (function()
                local s = {}
                for _i, y in ipairs(Api.YORUM_AYARLARI) do s[#s + 1] = { kod = y.kod, ad = y.ad } end
                return self:secenekMenusu("yorum_ayari", 0, s)
            end)(),
            separator = true,
        },
        {
            text = _("İhtiyaç anında Wi-Fi"),
            checked_func = function() return self.settings:isTrue("otomatik_wifi") end,
            callback = function() self.settings:flipTrue("otomatik_wifi"); self.settings:flush() end,
            help_text = _("Kitabı kapatınca sırada bekleyen bir şey varsa Wi-Fi'yi açar, gönderir ve kapatır."),
        },
        {
            text = _("Okuduklarımı aktarırken okuma tarihlerini de gönder"),
            checked_func = function() return self.settings:nilOrTrue("aktar_tarihli") end,
            callback = function() self.settings:flipNilOrTrue("aktar_tarihli"); self.settings:flush() end,
            help_text = _("Okuduklarımı aktar, kitapları KOReader'daki okuma tarihleriyle (istatistiklerden ilk ve son okuma; yoksa Bitti işaretlediğin gün) \"Okudum\" yapar. Kapalıysa bugünün tarihiyle kaydedilir ve hepsi bu yılın hedefine sayılır."),
        },
        {
            text = _("Uykuya geçerken bekleyenleri gönder"),
            checked_func = function() return self.settings:nilOrTrue("uykuda_gonder") end,
            callback = function() self.settings:flipNilOrTrue("uykuda_gonder"); self.settings:flush() end,
            help_text = _("Cihaz uykuya geçerken Wi-Fi açıksa sıradaki birkaç işi (en fazla 5, 8 saniye) hemen gönderir. Kalanlar uyanınca ya da Wi-Fi bağlanınca sürer."),
        },
    }
    if self.uykuMenuOgesi then
        ogeler[#ogeler + 1] = self:uykuMenuOgesi()
    end
    if self.guncellemeMenuOgeleri then
        for _i, o in ipairs(self:guncellemeMenuOgeleri()) do ogeler[#ogeler + 1] = o end
    else
        ogeler[#ogeler + 1] = { text = T(_("Sürüm %1"), SURUM), enabled = false }
    end
    return ogeler
end

function BinKitap:bekleyenlerMenuOgesi()
    return {
        text_func = function()
            if ORTAK.arka_plan then
                return T(_("Bekleyen gönderiler: %1 (arka planda gönderiliyor)"), #self:kuyruk())
            end
            return T(_("Bekleyen gönderiler: %1"), #self:kuyruk())
        end,
        keep_menu_open = true,
        callback = function()
            if #self:kuyruk() == 0 then return self:bildir(_("Bekleyen gönderi yok.")) end
            NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
        end,
        hold_callback = function(touchmenu_instance)
            if #self:kuyruk() == 0 then return end
            UIManager:show(ConfirmBox:new{
                text = _("Bekleyen tüm gönderiler silinsin mi?"),
                ok_text = _("Sil"),
                ok_callback = function()
                    ORTAK.arka_plan = nil
                    self.settings:saveSetting("kuyruk", {})
                    self.settings:flush()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
        help_text = _("Dokun: beklemeden şimdi gönder (ilerleme gösterilir). Basılı tut: sırayı temizle. Çok iş birden sıraya girince arka planda kendiliğinden gönderilir."),
    }
end

function BinKitap:menuOgeleri()
    local ogeler = {}
    if self.ekranAc then
        ogeler[#ogeler + 1] = {
            text = _("1000Kitap ekranı"),
            callback = function(touchmenu_instance)
                if touchmenu_instance and touchmenu_instance.closeMenu then touchmenu_instance:closeMenu() end
                self:ekranAc()
            end,
            help_text = _("Okuduğun kitap, yıllık hedefin, Okuyacaklarım rafı, son alıntın ve bekleyen işler tek ekranda. Hareket ayarlarından \"1000Kitap: ekranı aç\" eylemine de bağlayabilirsin."),
            separator = true,
        }
    end
    if self.ui.document then
        ogeler[#ogeler + 1] = {
            text_func = function()
                local k = self:kitapBilgisi()
                if not k then return _("Kitabı 1000Kitap'ta eşleştir") end
                local ek = k.otomatik and _(" · otomatik, onaylanmadı") or ""
                if k.yayinevi and k.yayinevi ~= "" then return T(_("Kitap: %1 (%2)"), k.adi, k.yayinevi) .. ek end
                return T(_("Kitap: %1"), k.adi) .. ek
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local k = self:kitapBilgisi()
                local yenile = function() if touchmenu_instance then touchmenu_instance:updateItems() end end
                if k then
                    self:aramaPenceresi(kirp(k.adi .. " " .. (k.yazar or "")), function(s) self:kitapSecildi(s, yenile) end)
                else
                    self:kitapEslestir(yenile)
                end
            end,
        }
        ogeler[#ogeler + 1] = {
            text = _("Baskıyı değiştir"),
            enabled_func = function() return self:kitapBilgisi() ~= nil end,
            callback = function() self:baskiSec() end,
        }
        ogeler[#ogeler + 1] = {
            text = _("Okuma durumunu ayarla"),
            sub_item_table = {
                { text = _("Okuyorum"), callback = function() self:durumIstegi(Api.DURUM.okuyorum) end },
                { text = _("Okudum"), callback = function() self:durumIstegi(Api.DURUM.okudum) end },
                { text = _("Yarım bıraktım"), callback = function() self:durumIstegi(Api.DURUM.yarim) end },
                { text = _("Okuyacağım"), callback = function() self:durumIstegi(Api.DURUM.okuyacagim) end },
            },
        }
        ogeler[#ogeler + 1] = { text = _("Puan ver"), callback = function() self:puanIstegi() end }
        if self.topluGonder then
            ogeler[#ogeler + 1] = { text = _("Bu kitabın vurgularını gönder"), callback = function() self:topluGonder() end }
        end
        if self.kitapKarti then
            ogeler[#ogeler + 1] = { text = _("Kitap bilgisi"), callback = function() self:kitapKarti() end }
            ogeler[#ogeler + 1] = {
                text = _("Popüler alıntılar"), callback = function() self:populerAlintilar() end,
            }
            ogeler[#ogeler + 1] = {
                text = _("Popüler incelemeler"), callback = function() self:populerIncelemeler() end,
                separator = true,
            }
        end
    end
    if self.okuyacaklaraEkle then
        ogeler[#ogeler + 1] = {
            text = _("Okuyacaklarıma ekle"),
            callback = function() self:okuyacaklaraEkle() end,
            help_text = _("Kobo'daki kitaplarından seçerek ya da 1000Kitap'ta arayarak \"Okuyacağım\" listene ekler. Okuduğun ya da okumakta olduğun kitaplara dokunulmaz."),
        }
    end
    if self.kutuphaneEslestir then
        ogeler[#ogeler + 1] = {
            text = _("Kütüphaneyi eşleştir"),
            callback = function() self:kutuphaneEslestir() end,
            help_text = _("Kobo'daki tüm kitapları 1000Kitap'ta arar; ISBN'i ya da başlığı ve yazarı birebir tutanları kendisi eşleştirir. Okuma durumlarını değiştirmez."),
        }
        if self.okuduklarimiAktar then
            ogeler[#ogeler + 1] = {
                text = _("Okuduklarımı aktar"),
                callback = function() self:okuduklarimiAktar() end,
                help_text = _("KOReader'da bitirdiğin kitapları bulur; seçtiklerini 1000Kitap'ta \"Okudum\" yapar, sonra vurgularını göndermek isteyip istemediğini sorar."),
            }
        end
        if self.durumlariAl then
            ogeler[#ogeler + 1] = {
                text = _("Durumları 1000Kitap'tan al"),
                callback = function() self:durumlariAl() end,
                help_text = _("Eşleşmiş kitapların 1000Kitap'taki durumlarına yavaşça bakar, KOReader'dakinden farklı olanları listeler; seçtiklerini KOReader'da Bitti / Beklemede / Okunuyor yapar. KOReader'da durumu olan kitaplara ancak 1000Kitap'ta değiştiyse dokunmayı önerir."),
            }
        end
        ogeler[#ogeler + 1] = {
            text_func = function() return T(_("Emin olunamayanları gözden geçir (%1)"), self:belirsizSayisi()) end,
            enabled_func = function() return self:belirsizSayisi() > 0 end,
            callback = function() self:kutuphaneGozdenGecir() end,
        }
        ogeler[#ogeler + 1] = {
            text_func = function() return T(_("Atlananlar (%1)"), self:atlananSayisi()) end,
            enabled_func = function() return self:atlananSayisi() > 0 end,
            callback = function() self:atlananlarListesi() end,
        }
        ogeler[#ogeler + 1] = {
            text = _("1000Kitap kitaplığım"),
            sub_item_table_func = function() return self:kitaplikMenusu() end,
            separator = true,
        }
    end
    if self.neOkusam then
        ogeler[#ogeler + 1] = { text = _("Ne okusam?"), callback = function() self:neOkusam() end }
        if self.kesifListeleriMenusu then
            ogeler[#ogeler + 1] = {
                text = _("Kitap listeleri"),
                help_text = _("Sitenin Kitaplar sekmesindeki listeler: sana özel öneriler, son 7 günün en çok okunanları, yeni çıkanlar, en iyiler… Kobo'nda olanlar ✓ ile işaretli; dokununca açabilir ya da Okuyacaklarına ekleyebilirsin."),
                sub_item_table_func = function() return self:kesifListeleriMenusu() end,
            }
        end
        ogeler[#ogeler + 1] = {
            text = _("Okuyacaklarım koleksiyonunu güncelle"),
            callback = function() self:koleksiyonGuncelle() end,
        }
        ogeler[#ogeler + 1] = { text = _("Okuma hedefi"), sub_item_table_func = function() return self:hedefMenusu() end }
    end
    if self.iletiYaz then
        ogeler[#ogeler + 1] = {
            text_func = function()
                return self:iletiTaslagi() and _("İleti yaz (taslak var)") or _("İleti yaz")
            end,
            callback = function() self:iletiYaz() end,
            help_text = _("Alıntı değil, kendi yazını 1000Kitap'ta ileti olarak paylaşır. Okuduğun kitabı etiketleyebilirsin."),
        }
    end
    ogeler[#ogeler + 1] = self:bekleyenlerMenuOgesi()
    ogeler[#ogeler + 1] = { text = _("Ayarlar"), sub_item_table_func = function() return self:ayarlarMenusu() end }
    return ogeler
end

-- Dosya tarayıcısı ve toplu işler, keşif özellikleri
yukle("binkitap_toplu")(BinKitap)
yukle("binkitap_kesif")(BinKitap)
yukle("binkitap_guncelle")(BinKitap)
yukle("binkitap_ileti")(BinKitap)
yukle("binkitap_aktar")(BinKitap)
yukle("binkitap_durum")(BinKitap)
yukle("binkitap_ekran")(BinKitap)

return BinKitap
