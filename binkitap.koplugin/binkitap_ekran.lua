--[[
1000Kitap eklentisi: tek bakışta 1000Kitap ekranı.

Okurken: şu an okuduğun kitap (kapak, sayfa, ilerleme) ve kısayolları, yıllık hedef,
Okuyacaklarım rafı, son alıntın, bekleyen işler.
Dosya tarayıcısında: son okuduğun kitap (Devam et), hedef, raf, kütüphane kısayolları.

Ekran önce hafızadaki bilgilerle hemen açılır; ağ isteği yapmaz. Hedef bilgisi eskiyse ve
Wi-Fi açıksa arkadan tazelenir. "Yenile" Okuyacaklar listesini de yeniden getirir.

Ekranı kuran kod bir hata verirse ekran açılmaz, hata günlüğe yazılır ve menü çalışmaya devam eder.
]]

local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local HEDEF_OMRU = 12 * 3600
local RAF_SAYISI = 4

return function(BinKitap)
    local Api, Y = BinKitap.Api, BinKitap.Y

    local function kisalt(s, n)
        s = Y.kirp(s or ""):gsub("%s+", " ")
        if #s <= n then return s end
        s = s:sub(1, n):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "")
        return s .. "…"
    end

    local function dosyaVar(yol)
        if type(yol) ~= "string" or yol == "" then return false end
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        return ok and lfs.attributes(yol, "mode") == "file"
    end

    --- "az önce", "5 dk önce", "2 saat önce", "3 gün önce"
    function BinKitap.gecenSure(zaman)
        local fark = os.time() - (tonumber(zaman) or 0)
        if fark < 60 then return _("az önce") end
        if fark < 3600 then return T(_("%1 dk önce"), math.floor(fark / 60)) end
        if fark < 86400 then return T(_("%1 saat önce"), math.floor(fark / 3600)) end
        return T(_("%1 gün önce"), math.floor(fark / 86400))
    end

    --- Gönderilen son alıntıyı ekranda göstermek için saklar.
    function BinKitap:sonAlintiKaydet(oge)
        local metin = oge.soz or oge.metin
        if type(metin) ~= "string" or metin == "" then return end
        self.settings:saveSetting("son_alinti", {
            metin = kisalt(metin, 400),
            kitap_adi = oge.kitap_adi,
            sayfa = tonumber(oge.sayfa),
            gizli = oge.tur == "ozel_not" or nil,
            zaman = os.time(),
        })
    end

    -------------------------------------------------------------------------
    -- Ekranın verisi (ağsız; test edilebilir)
    -------------------------------------------------------------------------

    --- Okuyacaklar rafı için hızlı arama: yalnızca bilinen eşleşmeler, kütüphane taranmaz.
    local function hizliBulucu(self)
        local id_yol = {}
        for yol, k in pairs(self.settings:readSetting("eslesmeler") or {}) do
            if type(k) == "table" and k.id then id_yol[tostring(k.id)] = id_yol[tostring(k.id)] or yol end
        end
        for id, yol in pairs(self.settings:readSetting("kitap_dosyalari") or {}) do
            id_yol[tostring(id)] = id_yol[tostring(id)] or yol
        end
        return function(k)
            local yol = id_yol[tostring(k.id)]
            if yol and dosyaVar(yol) then return yol end
        end
    end

    local function yanDosyaOku(yol)
        local ok, DocSettings = pcall(require, "docsettings")
        if not ok or not DocSettings then return nil end
        local ok2, var = pcall(function() return DocSettings:hasSidecarFile(yol) end)
        if not ok2 or not var then return nil end
        local ok3, ds = pcall(function() return DocSettings:open(yol) end)
        if ok3 then return ds end
    end

    local function durumMetni(self, kitap, ko_durum)
        if kitap and kitap.id and self.bkDurumGorulen then
            local g = self:bkDurumGorulen(kitap.id)
            if g and g.d ~= nil and Api.DURUM_ADI[g.d] and g.d ~= Api.DURUM.yok then return Api.DURUM_ADI[g.d] end
        end
        local ad = ko_durum and BinKitap.KO_ADI and BinKitap.KO_ADI[ko_durum]
        return ad
    end

    function BinKitap:ekranVerisi()
        local v = { okuyucu = self.ui.document ~= nil }

        -- Kitap: okurken açık olan, dosya tarayıcısında son okunan
        if v.okuyucu then
            local doc = self.ui.document
            local props = self.ui.doc_props or (doc.getProps and doc:getProps()) or {}
            local kitap = self:kitapBilgisi()
            local yuzde = self:mevcutYuzde()
            local ozet = self.ui.doc_settings and self.ui.doc_settings:readSetting("summary")
            local sayfa_metni
            local basili = kitap and tonumber(kitap.basili_sayfa)
            local s = self:basiliSayfa()
            if s and basili then
                sayfa_metni = T(_("s. %1 / %2"), s, basili)
            elseif s and doc.getPageCount then
                sayfa_metni = T(_("s. %1 / %2"), s, doc:getPageCount())
            end
            v.kitap = {
                baslik = Y.kirp(props.display_title or props.title or (kitap and kitap.adi) or Y.dosyaAdindanBaslik(self:acikDosya() or "")),
                yazar = (Y.kirp(props.authors or (kitap and kitap.yazar) or ""):gsub("\n", ", ")),
                yayinevi = kitap and kitap.yayinevi or nil,
                durum = durumMetni(self, kitap, type(ozet) == "table" and ozet.status or nil),
                sayfa = sayfa_metni,
                yuzde = yuzde,
                yol = self:acikDosya(),
                eslesmis = kitap ~= nil,
                puan = kitap and kitap.puan or nil,
            }
        else
            local son = G_reader_settings and G_reader_settings:readSetting("lastfile")
            if dosyaVar(son) then
                local bilgi = Y.dosyaBilgisi(self.ui, son, nil, true) or {}
                local ds = yanDosyaOku(son)
                local ozet = ds and ds:readSetting("summary")
                local yuzde = ds and tonumber(ds:readSetting("percent_finished"))
                local kitap = self:dosyaEslesmesi(son)
                v.kitap = {
                    baslik = (bilgi.baslik and bilgi.baslik ~= "" and bilgi.baslik) or (kitap and kitap.adi) or Y.dosyaAdindanBaslik(son),
                    yazar = (bilgi.yazar and bilgi.yazar ~= "" and bilgi.yazar) or (kitap and kitap.yazar) or "",
                    durum = durumMetni(self, kitap, type(ozet) == "table" and ozet.status or nil),
                    yuzde = yuzde,
                    yol = son,
                    eslesmis = kitap ~= nil,
                    puan = kitap and kitap.puan or nil,
                }
            end
        end
        if v.kitap and v.kitap.yuzde then
            local y = math.floor(v.kitap.yuzde * 100 + 0.5)
            v.kitap.yuzde_metni = "%" .. y
        end

        -- Hedef
        local sene = tonumber(os.date("%Y"))
        local h = self.settings:readSetting("hedef_onbellek")
        if type(h) == "table" and h.sene == sene and h.hedef then
            v.hedef = { sene = sene, hedef = h.hedef, okunan = h.okunan or 0 }
            v.hedef.kalan = math.max(0, v.hedef.hedef - v.hedef.okunan)
        end
        v.hedef_eski = type(h) ~= "table" or os.time() - (h.zaman or 0) > HEDEF_OMRU

        -- Okuyacaklar rafı
        local onb = self.settings:readSetting("okuyacaklar_onbellek")
        if type(onb) == "table" and type(onb.liste) == "table" and onb.kadi == self.kullanici_adi then
            local bul = hizliBulucu(self)
            local cihazda, digerleri = {}, {}
            for _i, k in ipairs(onb.liste) do
                local yol = bul(k)
                local oge = { id = k.id, adi = k.adi, yazar = k.yazar, puan = k.puan, yol = yol }
                if yol then cihazda[#cihazda + 1] = oge else digerleri[#digerleri + 1] = oge end
            end
            local raf = {}
            for _i, o in ipairs(cihazda) do if #raf < RAF_SAYISI then raf[#raf + 1] = o end end
            for _i, o in ipairs(digerleri) do if #raf < RAF_SAYISI then raf[#raf + 1] = o end end
            v.okuyacaklar = { toplam = #onb.liste, cihazda = #cihazda, raf = raf, liste = onb.liste, bul = bul }
        end

        -- Son alıntı
        local sa = self.settings:readSetting("son_alinti")
        if type(sa) == "table" and sa.metin then
            local alt = {}
            if sa.kitap_adi then alt[#alt + 1] = sa.kitap_adi end
            if sa.sayfa and sa.sayfa > 0 then alt[#alt + 1] = T(_("s. %1"), sa.sayfa) end
            alt[#alt + 1] = BinKitap.gecenSure(sa.zaman)
            if sa.gizli then alt[#alt + 1] = _("gizli") end
            v.son_alinti = { metin = sa.metin, alt = table.concat(alt, " · ") }
        end

        -- Alt satır
        local n = #self:kuyruk()
        v.bekleyen = n
        if n == 0 then
            v.bekleyen_metni = _("Bekleyen gönderi yok")
            v.bekleyen_kisa = _("Bekleyen yok")
        elseif self:arkaPlandaMi() then
            v.bekleyen_metni = T(_("%1 iş arka planda gönderiliyor"), n)
            v.bekleyen_kisa = T(_("%1 iş gidiyor"), n)
        else
            v.bekleyen_metni = T(_("%1 iş gönderilmeyi bekliyor"), n)
            v.bekleyen_kisa = T(_("%1 iş bekliyor"), n)
        end
        v.belirsiz = self.belirsizSayisi and self:belirsizSayisi() or 0
        v.hata = self:hataSayisi()
        return v
    end

    -------------------------------------------------------------------------
    -- Kapaklar
    -------------------------------------------------------------------------

    local function kapakAl(self, yol, acik_kitap)
        if acik_kitap and self.ui.bookinfo and self.ui.bookinfo.getCoverImage then
            local ok, bb = pcall(self.ui.bookinfo.getCoverImage, self.ui.bookinfo, self.ui.document)
            if ok and bb then return bb end
        end
        if not yol then return nil end
        local ok, BIM = pcall(require, "bookinfomanager")
        if not ok or type(BIM) ~= "table" or not BIM.getBookInfo then return nil end
        local ok2, bi = pcall(BIM.getBookInfo, BIM, yol, true)
        if ok2 and type(bi) == "table" and bi.cover_bb then return bi.cover_bb end
    end

    -------------------------------------------------------------------------
    -- Ekran
    -------------------------------------------------------------------------

    --- Bir alt menüyü (text + callback öğeleri) düğme listesi olarak gösterir.
    function BinKitap:menudenDiyalog(baslik, ogeler)
        local ButtonDialog = require("ui/widget/buttondialog")
        local dialog
        local buttons = {}
        for _i, o in ipairs(ogeler or {}) do
            local metin = o.text or (o.text_func and o.text_func())
            local alt = o.sub_item_table or (o.sub_item_table_func and o.sub_item_table_func)
            if metin and (o.callback or alt) then
                buttons[#buttons + 1] = {{
                    text = alt and (metin .. " ›") or metin,
                    align = "left",
                    callback = function()
                        UIManager:close(dialog)
                        if alt then
                            local liste = type(alt) == "function" and alt() or alt
                            self:menudenDiyalog(metin, liste)
                        else
                            o.callback()
                        end
                    end,
                }}
            end
        end
        buttons[#buttons + 1] = {{ text = _("Kapat"), callback = function() UIManager:close(dialog) end }}
        dialog = ButtonDialog:new{ title = baslik, title_align = "left", buttons = buttons }
        UIManager:show(dialog)
    end

    --- Okuyacaklarının tamamı: Kobo'da olanlar üstte, dokununca açılır.
    function BinKitap:okuyacaklarTumu(veri)
        local o = veri or (self:ekranVerisi().okuyacaklar)
        if not o then return self:neOkusam() end
        local Menu = require("ui/widget/menu")
        local cihazda, digerleri = {}, {}
        for _i, k in ipairs(o.liste) do
            local yol = o.bul(k)
            local metin = (yol and "✓ " or "") .. k.adi .. ((k.yazar or "") ~= "" and (" — " .. k.yazar) or "")
            local p = BinKitap.puanYazi(k.puan)
            local oge = { text = metin, mandatory = p, yol = yol, kitap = k }
            if yol then cihazda[#cihazda + 1] = oge else digerleri[#digerleri + 1] = oge end
        end
        local itemler = {}
        for _i, x in ipairs(cihazda) do itemler[#itemler + 1] = x end
        for _i, x in ipairs(digerleri) do itemler[#itemler + 1] = x end
        local menu
        menu = Menu:new{
            title = T(_("Okuyacaklarım (%1) · ✓ = Kobo'nda"), #itemler),
            item_table = itemler,
            covers_fullscreen = true,
            is_borderless = true,
            is_popout = false,
            onMenuSelect = function(m, item)
                if item.yol then
                    UIManager:close(m)
                    if self._ekran then UIManager:close(self._ekran); self._ekran = nil end
                    self:kitapAc(item.yol)
                else
                    local p = BinKitap.puanYazi(item.kitap.puan)
                    self:bildir(T(_("“%1” Kobo'nda yok."), item.kitap.adi) .. (p and ("\n" .. T(_("1000Kitap puanı: %1"), p)) or ""), 3)
                end
                return true
            end,
            close_callback = function() UIManager:close(menu) end,
        }
        UIManager:show(menu)
    end

    function BinKitap:ekranAc()
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        local ok, hata = pcall(function()
            if self._ekran then UIManager:close(self._ekran); self._ekran = nil end
            local ekran = self:ekranKur()
            self._ekran = ekran
            UIManager:show(ekran)
        end)
        if not ok then
            logger.err("1000Kitap: ekran açılamadı", hata)
            BinKitap.hataKaydet("eklenti", "Ekran", tostring(hata))
            self._ekran = nil
            return self:hataGoster(_("1000Kitap ekranı açılamadı. Ayrıntısı hata günlüğünde; menüdeki her şey çalışmaya devam ediyor."))
        end
        -- Hedef eskiyse arkadan tazele ve ekranı yenile
        local v = self._ekran and self._ekran.veri
        if v and v.hedef_eski and NetworkMgr:isOnline() and self.hedefTazele then
            UIManager:scheduleIn(1, function()
                if not self._ekran then return end
                self:hedefTazele(function() if self._ekran then self._ekran:yenile() end end)
            end)
        end
    end

    function BinKitap:onBinKitapEkran()
        self:ekranAc()
        return true
    end

    --- Widget ağacını kurar. KOReader modülleri burada (geç) yüklenir.
    function BinKitap:ekranKur()
        local Blitbuffer = require("ffi/blitbuffer")
        local Button = require("ui/widget/button")
        local ButtonTable = require("ui/widget/buttontable")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Device = require("device")
        local Font = require("ui/font")
        local FrameContainer = require("ui/widget/container/framecontainer")
        local Geom = require("ui/geometry")
        local GestureRange = require("ui/gesturerange")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan = require("ui/widget/horizontalspan")
        local ImageWidget = require("ui/widget/imagewidget")
        local InputContainer = require("ui/widget/container/inputcontainer")
        local LineWidget = require("ui/widget/linewidget")
        local ProgressWidget = require("ui/widget/progresswidget")
        local Size = require("ui/size")
        local TextBoxWidget = require("ui/widget/textboxwidget")
        local TextWidget = require("ui/widget/textwidget")
        local TitleBar = require("ui/widget/titlebar")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local VerticalSpan = require("ui/widget/verticalspan")
        local Screen = Device.screen

        local eklenti = self

        -- Dokunulabilir sarmalayıcı (kapaklar için)
        local Tiklanir = InputContainer:extend{ callback = nil }
        function Tiklanir:init()
            local boyut = self[1]:getSize()
            self.dimen = Geom:new{ x = 0, y = 0, w = boyut.w, h = boyut.h }
            self.ges_events = {
                Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
            }
        end
        function Tiklanir:onTap()
            if self.callback then self.callback() end
            return true
        end

        local Ekran = InputContainer:extend{ covers_fullscreen = true }

        function Ekran:init()
            self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
            self.key_events = self.key_events or {}
            self.ges_events = self.ges_events or {}
            if Device:hasKeys() and Device.input and Device.input.group then
                self.key_events.Close = { { Device.input.group.Back } }
            end
            if Device:isTouchDevice() then
                self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } }
            end
            self:kur()
        end

        function Ekran:kur()
            self.veri = eklenti:ekranVerisi()
            self[1] = FrameContainer:new{
                width = self.dimen.w,
                height = self.dimen.h,
                background = Blitbuffer.COLOR_WHITE,
                bordersize = 0,
                padding = 0,
                eklenti:ekranIcerigi(self, self.veri, {
                    Blitbuffer = Blitbuffer, Button = Button, ButtonTable = ButtonTable,
                    CenterContainer = CenterContainer, Font = Font, FrameContainer = FrameContainer,
                    Geom = Geom, HorizontalGroup = HorizontalGroup, HorizontalSpan = HorizontalSpan,
                    ImageWidget = ImageWidget, LineWidget = LineWidget, ProgressWidget = ProgressWidget,
                    Size = Size, TextBoxWidget = TextBoxWidget, TextWidget = TextWidget, TitleBar = TitleBar,
                    VerticalGroup = VerticalGroup, VerticalSpan = VerticalSpan, Screen = Screen, Tiklanir = Tiklanir,
                }),
            }
        end

        function Ekran:yenile()
            local ok, hata = pcall(function() self:kur() end)
            if not ok then
                logger.err("1000Kitap: ekran yenilenemedi", hata)
                BinKitap.hataKaydet("eklenti", "Ekran", tostring(hata))
                return
            end
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end

        function Ekran:onClose()
            UIManager:close(self, "flashpartial")
            if eklenti._ekran == self then eklenti._ekran = nil end
            return true
        end

        function Ekran:onSwipe(_arg, ges)
            if ges and ges.direction == "south" then return self:onClose() end
            return false
        end

        function Ekran:onShow()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end

        return Ekran:new{}
    end

    --- Bölümleri ekrana sığdırır: sığmazsa önce "atilabilir", sonra "kisaltilabilir" olanları
    -- (kısa hâliyle) değiştirir. bolumler: { {ad, w, kisa = function() end | nil, atilabilir = bool}, ... }
    -- Dönüş: seçilen widget listesi.
    function BinKitap.ekranaSigdir(bolumler, sabit_yukseklik, sinir)
        local function toplam()
            local h = sabit_yukseklik
            for _i, b in ipairs(bolumler) do
                if b.w then h = h + b.w:getSize().h end
            end
            return h
        end
        if toplam() > sinir then
            for _i, b in ipairs(bolumler) do
                if b.atilabilir and b.w then b.w = nil; b.atildi = true; if toplam() <= sinir then break end end
            end
        end
        if toplam() > sinir then
            for _i, b in ipairs(bolumler) do
                if b.kisa and b.w then b.w = b.kisa(); b.kisaldi = true; if toplam() <= sinir then break end end
            end
        end
        local sonuc = {}
        for _i, b in ipairs(bolumler) do if b.w then sonuc[#sonuc + 1] = b.w end end
        return sonuc
    end

    --- Ekranın içeriği. W: widget sınıfları (testte taklit edilebilsin diye parametre).
    function BinKitap:ekranIcerigi(ekran, v, W)
        local Screen, Size = W.Screen, W.Size
        local gen, yuk = Screen:getWidth(), Screen:getHeight()
        local kenar = Size.padding.fullscreen
        local ic_gen = gen - 2 * kenar
        local f_baslik = W.Font:getFace("tfont", 19)
        local f_normal = W.Font:getFace("cfont", 17)
        local f_kucuk = W.Font:getFace("cfont", 14)
        local f_etiket = W.Font:getFace("x_smalltfont", 12)
        local gri = W.Blitbuffer.COLOR_DARK_GRAY
        local ara = Size.span.vertical_large

        local function kapat_ve(f)
            return function()
                ekran:onClose()
                f()
            end
        end
        local function bosluk(h) return W.VerticalSpan:new{ width = h } end
        local function yazi(metin, yuz, opt)
            opt = opt or {}
            local gen_ = opt.width or ic_gen
            local boy = tonumber(yuz and yuz.size) or 18
            -- Satır sınırı yalnızca metin sığmayacak gibiyse: kısa metne boş yer ayırma
            local sinirla = false
            if opt.satir then
                local harf = select(2, tostring(metin):gsub("[^\128-\191]", ""))
                local satir_basina = math.max(1, math.floor(gen_ / (boy * 0.5)))
                sinirla = harf > satir_basina * opt.satir
            end
            return W.TextBoxWidget:new{
                text = metin, face = yuz, width = gen_, bold = opt.bold,
                fgcolor = opt.gri and gri or nil, alignment = opt.alignment or "left",
                height = sinirla and math.floor(opt.satir * boy * 1.35) or nil,
                height_adjust = sinirla or nil,
                height_overflow_show_ellipsis = sinirla or nil,
            }
        end
        local function cizgi()
            return W.LineWidget:new{
                background = W.Blitbuffer.COLOR_LIGHT_GRAY,
                dimen = W.Geom:new{ w = ic_gen, h = Size.line.thick },
            }
        end
        local function bolum(etiket, ...)
            local g = W.VerticalGroup:new{ align = "left" }
            g[#g + 1] = bosluk(ara)
            g[#g + 1] = cizgi()
            g[#g + 1] = bosluk(ara)
            g[#g + 1] = yazi(etiket, f_etiket, { gri = true })
            g[#g + 1] = bosluk(Size.span.vertical_default)
            for i = 1, select("#", ...) do
                local w = select(i, ...)
                if w then g[#g + 1] = w end
            end
            return g
        end
        local function dugmeler(satirlar)
            return W.ButtonTable:new{ width = ic_gen, buttons = satirlar, zero_sep = true, show_parent = ekran }
        end
        local function ilerleme(oran, gen_)
            return W.ProgressWidget:new{
                width = gen_ or ic_gen, height = Screen:scaleBySize(7),
                percentage = math.max(0, math.min(1, oran or 0)),
            }
        end
        local function kapakKutusu(bb, gen_, yuk_, yedek_metin)
            if bb then
                local ok, img = pcall(function()
                    return W.ImageWidget:new{ image = bb, width = gen_, height = yuk_, scale_factor = 0 }
                end)
                if ok and img then
                    return W.CenterContainer:new{ dimen = W.Geom:new{ w = gen_, h = yuk_ }, img }
                end
            end
            local ic = Size.padding.small + Size.border.thin
            return W.FrameContainer:new{
                width = gen_, height = yuk_, bordersize = Size.border.thin, padding = Size.padding.small,
                W.CenterContainer:new{
                    dimen = W.Geom:new{ w = gen_ - 2 * ic, h = yuk_ - 2 * ic },
                    yazi(kisalt(yedek_metin or "", 40), f_kucuk, { width = gen_ - 2 * ic, alignment = "center", satir = 4 }),
                },
            }
        end

        local bolumler = {}

        -- 1) Kitap
        local k = v.kitap
        if k then
            local kap_gen, kap_yuk = Screen:scaleBySize(84), Screen:scaleBySize(120)
            local bilgi_gen = ic_gen - kap_gen - Size.span.horizontal_default
            local bilgi = W.VerticalGroup:new{ align = "left" }
            bilgi[#bilgi + 1] = yazi(k.baslik, f_baslik, { width = bilgi_gen, bold = true, satir = 2 })
            local alt = k.yazar ~= "" and k.yazar or nil
            if k.yayinevi and k.yayinevi ~= "" then alt = (alt and (alt .. " · ") or "") .. k.yayinevi end
            if alt then bilgi[#bilgi + 1] = yazi(alt, f_kucuk, { width = bilgi_gen, gri = true, satir = 1 }) end
            bilgi[#bilgi + 1] = bosluk(ara)
            local durum = {}
            if k.durum then durum[#durum + 1] = k.durum end
            if k.sayfa then durum[#durum + 1] = k.sayfa end
            if k.yuzde_metni then durum[#durum + 1] = k.yuzde_metni end
            local py = BinKitap.puanYazi(k.puan)
            if py then durum[#durum + 1] = py end
            if #durum > 0 then bilgi[#bilgi + 1] = yazi(table.concat(durum, " · "), f_normal, { width = bilgi_gen, satir = 2 }) end
            if k.yuzde then
                bilgi[#bilgi + 1] = bosluk(ara)
                bilgi[#bilgi + 1] = ilerleme(k.yuzde, bilgi_gen)
            end
            if not k.eslesmis then
                bilgi[#bilgi + 1] = bosluk(ara)
                bilgi[#bilgi + 1] = yazi(_("1000Kitap'la eşleşmemiş"), f_kucuk, { width = bilgi_gen, gri = true })
            end
            local satir = W.HorizontalGroup:new{
                align = "top",
                kapakKutusu(self:_ekranKapak(k.yol, v.okuyucu), kap_gen, kap_yuk, k.baslik),
                W.HorizontalSpan:new{ width = Size.span.horizontal_default },
                bilgi,
            }
            local kisayol
            if v.okuyucu then
                kisayol = dugmeler({{
                    { text = _("Vurgular"), callback = kapat_ve(function() self:topluGonder() end) },
                    { text = _("İleti yaz"), callback = kapat_ve(function() self:iletiYaz() end) },
                    { text = _("Puan ver"), callback = kapat_ve(function() self:puanIstegi() end) },
                    { text = _("Bitirdim"), callback = kapat_ve(function() self:bitirdim() end) },
                }})
            else
                kisayol = dugmeler({{
                    { text = _("Devam et"), callback = kapat_ve(function() self:kitapAc(k.yol) end) },
                }})
            end
            bolumler[#bolumler + 1] = { ad = "kitap",
                w = bolum(v.okuyucu and _("ŞU AN OKUDUĞUN") or _("SON OKUDUĞUN"), satir, bosluk(ara), kisayol) }
        end

        -- 2) Hedef
        local sene = tonumber(os.date("%Y"))
        if v.hedef then
            local h = v.hedef
            local satir_metni = T(_("%1 / %2 kitap"), h.okunan, h.hedef) .. " · "
                .. (h.kalan == 0 and _("hedef tamam") or T(_("%1 kitap kaldı"), h.kalan))
            bolumler[#bolumler + 1] = { ad = "hedef", w = bolum(T(_("%1 OKUMA HEDEFİ"), sene),
                yazi(satir_metni, f_normal, { bold = true }),
                bosluk(Size.span.vertical_default),
                ilerleme(h.hedef > 0 and h.okunan / h.hedef or 0)) }
        else
            bolumler[#bolumler + 1] = { ad = "hedef", w = bolum(T(_("%1 OKUMA HEDEFİ"), sene),
                yazi(_("Hedef bilgisi henüz yok; Yenile'ye dokun."), f_kucuk, { gri = true })) }
        end

        -- 3) Okuyacaklarım rafı
        local o = v.okuyacaklar
        local raf_dugmeleri = function()
            return dugmeler({{
                { text = _("Ne okusam?"), callback = kapat_ve(function() self:neOkusam() end) },
                { text = T(_("Tümü (%1)"), o and o.toplam or 0), callback = function() self:okuyacaklarTumu(o) end },
                { text = _("Listeler"), callback = function()
                    self:menudenDiyalog(_("Kitap listeleri"), self:kesifListeleriMenusu())
                end },
            }})
        end
        if o and #o.raf > 0 then
            local etiket = T(_("OKUYACAKLARIM · %1 kitap, %2 tanesi Kobo'nda"), o.toplam, o.cihazda)
            local aralik = Size.span.horizontal_default
            local kutu_gen = math.floor((ic_gen - (RAF_SAYISI - 1) * aralik) / RAF_SAYISI)
            local kutu_yuk = math.floor(kutu_gen * 1.3)
            local raf = W.HorizontalGroup:new{ align = "top" }
            for i, b in ipairs(o.raf) do
                if i > 1 then raf[#raf + 1] = W.HorizontalSpan:new{ width = aralik } end
                local p = BinKitap.puanYazi(b.puan)
                local alt_satir = b.yol and _("✓ Kobo'da") or _("Kobo'da yok")
                if p then alt_satir = alt_satir .. " · " .. p end
                local kutu = W.VerticalGroup:new{
                    align = "left",
                    kapakKutusu(b.yol and self:_ekranKapak(b.yol, false) or nil, kutu_gen, kutu_yuk, b.adi),
                    bosluk(Size.span.vertical_default),
                    yazi(b.adi, f_kucuk, { width = kutu_gen, satir = 1 }),
                    yazi(alt_satir, f_etiket, { width = kutu_gen, gri = true, satir = 1 }),
                }
                raf[#raf + 1] = W.Tiklanir:new{
                    kutu,
                    callback = function()
                        if b.yol then
                            ekran:onClose()
                            self:kitapAc(b.yol)
                        else
                            self:bildir(T(_("“%1” Kobo'nda yok."), b.adi) .. (p and ("\n" .. T(_("1000Kitap puanı: %1"), p)) or ""), 3)
                        end
                    end,
                }
            end
            bolumler[#bolumler + 1] = { ad = "raf",
                w = bolum(etiket, raf, bosluk(ara), raf_dugmeleri()),
                -- Sığmazsa kapaksız: yalnızca sayılar ve düğmeler
                kisa = function() return bolum(etiket, raf_dugmeleri()) end,
            }
        else
            bolumler[#bolumler + 1] = { ad = "raf", w = bolum(_("OKUYACAKLARIM"),
                yazi(o and _("Okuyacaklar listen boş.") or _("Okuyacaklar listen henüz alınmadı."), f_kucuk, { gri = true }),
                bosluk(Size.span.vertical_default),
                dugmeler({{
                    { text = _("Listeyi getir"), callback = function()
                        self:okuyacaklarListesi(true, function() if self._ekran then self._ekran:yenile() end end)
                    end },
                    { text = _("Okuyacaklarıma ekle"), callback = kapat_ve(function() self:okuyacaklaraEkle() end) },
                }})) }
        end

        -- 4) Son alıntı (yer yoksa ilk bu çıkar)
        if v.son_alinti then
            bolumler[#bolumler + 1] = { ad = "alinti", atilabilir = true, w = bolum(_("SON ALINTIN"),
                yazi("“" .. v.son_alinti.metin .. "”", f_normal, { satir = 3 }),
                yazi(v.son_alinti.alt, f_kucuk, { gri = true })) }
        end

        -- 5) Dosya tarayıcısında kütüphane kısayolları
        if not v.okuyucu then
            bolumler[#bolumler + 1] = { ad = "kutuphane", w = bolum(_("KÜTÜPHANE"), dugmeler({
                {
                    { text = _("Okuyacaklarıma ekle"), callback = kapat_ve(function() self:okuyacaklaraEkle() end) },
                    { text = _("Okuduklarımı aktar"), callback = kapat_ve(function() self:okuduklarimiAktar() end) },
                },
                {
                    { text = _("Kütüphaneyi eşleştir"), callback = kapat_ve(function() self:kutuphaneEslestir() end) },
                    { text = _("1000Kitap kitaplığım"), callback = function()
                        self:menudenDiyalog(_("1000Kitap kitaplığım"), self:kitaplikMenusu())
                    end },
                },
            })) }
        end

        -- 6) Alt satır: bekleyenler, seçim bekleyenler / hata günlüğü, yenile (tek satır)
        local alt_satir = {
            { text = v.bekleyen_kisa, callback = function()
                if v.bekleyen > 0 then
                    ekran:onClose()
                    self:kuyruguGonder(false)
                else
                    self:bildir(v.bekleyen_metni, 2)
                end
            end },
        }
        if v.belirsiz > 0 then
            alt_satir[#alt_satir + 1] = { text = T(_("%1 seçim bekliyor"), v.belirsiz),
                callback = kapat_ve(function() self:kutuphaneGozdenGecir() end) }
        elseif v.hata > 0 then
            alt_satir[#alt_satir + 1] = { text = T(_("Hata günlüğü (%1)"), v.hata),
                callback = function() self:hataGunluguMenusu().sub_item_table[1].callback() end }
        end
        alt_satir[#alt_satir + 1] = { text = _("Yenile"), callback = function()
            if not NetworkMgr:isOnline() then return ekran:yenile() end
            self:hedefTazele(function()
                self:okuyacaklarListesi(true, function() if self._ekran then self._ekran:yenile() end end)
            end)
        end }
        local alt = W.VerticalGroup:new{ align = "left", bosluk(ara), cizgi(), dugmeler({ alt_satir }) }

        local baslik = W.TitleBar:new{
            width = gen,
            fullscreen = true,
            title = "1000Kitap",
            subtitle = self.kullanici_adi and ("@" .. self.kullanici_adi) or nil,
            with_bottom_line = true,
            close_callback = function() ekran:onClose() end,
            show_parent = ekran,
        }

        local secilen = BinKitap.ekranaSigdir(bolumler, baslik:getSize().h + alt:getSize().h, yuk)
        local govde = W.VerticalGroup:new{ align = "left" }
        for _i, w in ipairs(secilen) do govde[#govde + 1] = w end
        -- Alt satırı ekranın dibine it
        local kalan = yuk - baslik:getSize().h - govde:getSize().h - alt:getSize().h
        if kalan > 0 then govde[#govde + 1] = bosluk(math.floor(kalan)) end
        govde[#govde + 1] = alt
        ekran.bolumler = bolumler

        return W.VerticalGroup:new{
            align = "left",
            baslik,
            W.HorizontalGroup:new{
                W.HorizontalSpan:new{ width = kenar },
                govde,
            },
        }
    end

    --- "Bitirdim": eşleşmişse bitiş ekranı (Okudum + puan + inceleme), değilse durum isteği.
    function BinKitap:bitirdim()
        local kitap = self:kitapBilgisi()
        if not kitap then return self:durumIstegi(Api.DURUM.okudum) end
        if kitap.otomatik then
            return self:otomatikEslesmeSor(kitap, function() self:bitirdim() end)
        end
        self:bitisPenceresi(kitap, { puan = nil, inceleme = "" })
    end

    --- Kapak (test için ayrı yöntem: taklit edilebilsin)
    function BinKitap:_ekranKapak(yol, acik_kitap)
        return kapakAl(self, yol, acik_kitap)
    end
end
