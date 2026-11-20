--[[
1000Kitap eklentisi: 1000Kitap'taki okuma durumunu KOReader'a yansıtma.

KOReader → 1000Kitap yönü main.lua'daki koDurumuKontrol'de. Bu dosya ters yönü yapar:
  • Kitap açılınca: 1000Kitap'taki durum en son görülenden farklıysa (yani sitede ya da
    telefonda değiştirildiyse) KOReader'daki durumu da değiştirmeyi önerir.
  • Elle: eşleşmiş kitapların 1000Kitap durumlarını yavaşça toplar, farkları listeler;
    seçilenleri KOReader'da işaretler.

Döngü olmasın diye KOReader durumunu yazarken kitabın son_ko_durum alanı da aynı değere
çekilir; böylece koDurumuKontrol bunu yeni bir değişiklik sanıp geri göndermez.
"Okuyacağım" KOReader'a aktarılmaz (bunun için Okuyacaklarım koleksiyonu var).
]]

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local TAZE = 6 * 3600        -- bu süre içinde bakılmış kitabın durumu yeniden istenmez
local ACILIS_ARALIK = 3600   -- açılışta aynı kitaba en fazla saatte bir bakılır
local ISTEK_ARALIGI = 1.0    -- toplu taramada istekler arası bekleme (sn)
local DINLENME_HER = 20      -- her 20 istekte bir…
local DINLENME = 6           -- …6 sn dinlen

return function(BinKitap)
    local Api, Y = BinKitap.Api, BinKitap.Y

    local BK_KO = {
        [Api.DURUM.okudum] = "complete",
        [Api.DURUM.yarim] = "abandoned",
        [Api.DURUM.okuyorum] = "reading",
    }
    local KO_ADI = {
        complete = _("Bitti"), abandoned = _("Beklemede"), reading = _("Okunuyor"), tbr = _("Okunacak"),
    }
    BinKitap.KO_ADI = KO_ADI

    local function koAdi(st) return st and (KO_ADI[st] or st) or _("durum yok") end

    --- 1000Kitap'ta en son görülen durumlar: { [kitap_id] = { d = durum, z = zaman } }
    function BinKitap:bkDurumGorulen(kitap_id)
        local g = self.settings:readSetting("bk_durum_gorulen")
        return type(g) == "table" and g[tostring(kitap_id)] or nil
    end

    function BinKitap:bkDurumKaydet(kitap_id, durum, ertele)
        if not kitap_id or durum == nil then return end
        local g = self.settings:readSetting("bk_durum_gorulen") or {}
        g[tostring(kitap_id)] = { d = durum, z = os.time() }
        self.settings:saveSetting("bk_durum_gorulen", g)
        if not ertele then self.settings:flush() end
    end

    --- Bir dosyanın KOReader durumunu okur (açık kitapsa açık belgeden).
    function BinKitap:koDurumuOku(yol)
        if self.ui and self.ui.document and self.ui.doc_settings and self:acikDosya() == yol then
            local o = self.ui.doc_settings:readSetting("summary")
            return type(o) == "table" and o.status or nil
        end
        local ok, DocSettings = pcall(require, "docsettings")
        if not ok or not DocSettings then return nil end
        local ok2, var = pcall(function() return DocSettings:hasSidecarFile(yol) end)
        if not ok2 or not var then return nil end
        local ok3, ds = pcall(function() return DocSettings:open(yol) end)
        if not ok3 or not ds then return nil end
        local o = ds:readSetting("summary")
        return type(o) == "table" and o.status or nil, tonumber(ds:readSetting("percent_finished"))
    end

    --- Bir dosyanın KOReader durumunu yazar; geri gönderilmesin diye son_ko_durum'u da günceller.
    function BinKitap:koDurumuYaz(yol, st)
        if self.ui and self.ui.document and self.ui.doc_settings and self:acikDosya() == yol then
            local o = self.ui.doc_settings:readSetting("summary") or {}
            o.status = st
            o.modified = os.date("%Y-%m-%d")
            self.ui.doc_settings:saveSetting("summary", o)
            local k = self:kitapBilgisi()
            if k then
                k.son_ko_durum = st
                self:kitapKaydetAyar(k)
            end
        else
            local ok, DocSettings = pcall(require, "docsettings")
            if not ok or not DocSettings then return false end
            local ok2, hata = pcall(function()
                local ds = DocSettings:open(yol)
                local o = ds:readSetting("summary") or {}
                o.status = st
                o.modified = os.date("%Y-%m-%d")
                ds:saveSetting("summary", o)
                local k = ds:readSetting("binkitap")
                if type(k) == "table" then
                    k.son_ko_durum = st
                    ds:saveSetting("binkitap", k)
                end
                ds:flush()
            end)
            if not ok2 then
                logger.warn("1000Kitap: KOReader durumu yazılamadı", yol, hata)
                return false
            end
        end
        -- Dosya tarayıcısının önbelleğindeki durumu da tazele (yeni KOReader sürümleri)
        local okb, BookList = pcall(require, "ui/widget/booklist")
        if okb and type(BookList) == "table" and BookList.setBookInfoCacheProperty then
            pcall(BookList.setBookInfoCacheProperty, yol, "status", st)
        end
        return true
    end

    --- 1000Kitap durumuna göre KOReader'da ne yapılmalı?
    -- Dönüş: hedef durum (ya da nil), önerilir mi (varsayılan seçili)
    function BinKitap.koHedefi(bk, ko, onceki_bk)
        local h = BK_KO[bk]
        if not h or h == ko then return nil end
        if ko == nil then return h, true end                               -- KOReader'da hiç durum yok
        if onceki_bk ~= nil and onceki_bk ~= bk then return h, true end   -- sitede değişmiş
        if ko == "reading" and h == "complete" then return h, false end   -- belki kâğıttan bitirdin
        return nil -- KOReader'daki daha yeni olabilir; dokunma
    end

    -------------------------------------------------------------------------
    -- Açılışta
    -------------------------------------------------------------------------

    function BinKitap:acilistaBkDurumu(kitap)
        if not self.settings:nilOrTrue("durum_ters") then return end
        if not kitap or kitap.otomatik or not Api:kimlikVar() or not NetworkMgr:isOnline() then return end
        local g = self:bkDurumGorulen(kitap.id)
        if g and os.time() - (g.z or 0) < ACILIS_ARALIK then return end
        UIManager:scheduleIn(6, function()
            if not self.ui.document then return end
            local k = self:kitapBilgisi()
            if not k or k.id ~= kitap.id then return end
            local m = Api:okumaDurumu(k.id)
            if not m then return end
            local onceki = g and g.d
            self:bkDurumKaydet(k.id, m.durum)
            if onceki == nil or onceki == m.durum then return end -- ilk görüş ya da değişmemiş
            local yol = self:acikDosya()
            local ko = self:koDurumuOku(yol)
            local h = BK_KO[m.durum]
            if not h or h == ko then return end
            UIManager:show(ConfirmBox:new{
                text = T(_("1000Kitap'ta bu kitabın durumu değişmiş: %1.\n\nKOReader'da da \"%2\" yapayım mı? (Şu an: %3)"),
                    Api.DURUM_ADI and Api.DURUM_ADI[m.durum] or tostring(m.durum), koAdi(h), koAdi(ko)),
                ok_text = _("Yap"),
                cancel_text = _("Dokunma"),
                ok_callback = function()
                    if self:koDurumuYaz(yol, h) then
                        self:bildir(T(_("KOReader'da \"%1\" yapıldı."), koAdi(h)))
                    end
                end,
            })
        end)
    end

    -------------------------------------------------------------------------
    -- Elle, toplu
    -------------------------------------------------------------------------

    local function eslesmisDosyalar(self)
        local eslesmeler = self.settings:readSetting("eslesmeler") or {}
        local liste, gorulen = {}, {}
        local okl, lfs = pcall(require, "libs/libkoreader-lfs")
        for yol, k in pairs(eslesmeler) do
            if type(k) == "table" and k.id and not k.otomatik and not gorulen[yol]
                    and (not okl or lfs.attributes(yol, "mode") == "file") then
                gorulen[yol] = true
                liste[#liste + 1] = { yol = yol, kitap = k }
            end
        end
        table.sort(liste, function(a, b) return a.yol < b.yol end)
        return liste
    end

    --- Eşleşmiş kitapların 1000Kitap durumlarını yavaşça toplar. bitince(farklar, durduruldu)
    function BinKitap:bkDurumlariniTopla(bitince)
        local dosyalar = eslesmisDosyalar(self)
        if #dosyalar == 0 then
            return UIManager:show(InfoMessage:new{
                text = _("Henüz eşleşmiş kitap yok. Önce \"Kütüphaneyi eşleştir\"i çalıştır."),
            })
        end
        NetworkMgr:runWhenOnline(function()
            local farklar, i, istek, iptal = {}, 0, 0, false
            local kutu, kapatiyorum
            local function goster()
                if kutu then kapatiyorum = true; UIManager:close(kutu); kapatiyorum = false end
                local k
                k = InfoMessage:new{
                    text = T(_("1000Kitap'taki durumlar alınıyor…\n\n%1 / %2 kitap · %3 fark\n\nDurdurmak için dokun."),
                        i, #dosyalar, #farklar),
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
            local function bitir(durduruldu)
                kapat()
                self.settings:flush()
                bitince(farklar, durduruldu)
            end
            local adim
            adim = function()
                if iptal then return bitir(true) end
                -- Önbellekte taze olanları beklemeden geç
                while true do
                    i = i + 1
                    local d = dosyalar[i]
                    if not d then return bitir(false) end
                    local g = self:bkDurumGorulen(d.kitap.id)
                    local bk, onceki
                    if g and os.time() - (g.z or 0) < TAZE then
                        bk, onceki = g.d, g.onceki
                    else
                        local m, err, tur = Api:okumaDurumu(d.kitap.id)
                        istek = istek + 1
                        if not m then
                            if tur == "ag" or tur == "yetki" then
                                kapat()
                                self.settings:flush()
                                return self:hataGoster(err)
                            end
                        else
                            bk, onceki = m.durum, g and g.d
                            local tablo = self.settings:readSetting("bk_durum_gorulen") or {}
                            tablo[tostring(d.kitap.id)] = { d = bk, z = os.time(), onceki = onceki }
                            self.settings:saveSetting("bk_durum_gorulen", tablo)
                        end
                    end
                    if bk ~= nil then
                        local ko, yuzde = self:koDurumuOku(d.yol)
                        local h, oneri = BinKitap.koHedefi(bk, ko, onceki)
                        if h then
                            farklar[#farklar + 1] = { yol = d.yol, kitap = d.kitap, ko = ko, hedef = h,
                                oneri = oneri, yuzde = yuzde }
                        end
                    end
                    if not g or os.time() - (g.z or 0) >= TAZE then break end
                end
                if i % 5 == 0 then goster() end
                local bekleme = ISTEK_ARALIGI
                if istek > 0 and istek % DINLENME_HER == 0 then
                    bekleme = DINLENME
                    self.settings:flush()
                end
                UIManager:scheduleIn(bekleme, adim)
            end
            goster()
            adim()
        end)
    end

    --- "1000Kitap'tan durumları al": topla → farkları seçtir → KOReader'a yaz.
    function BinKitap:durumlariAl()
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        self:bkDurumlariniTopla(function(farklar, durduruldu)
            if #farklar == 0 then
                return UIManager:show(InfoMessage:new{
                    text = durduruldu and _("Durduruldu. Şimdiye kadar bakılanlarda KOReader'a aktarılacak fark yok.")
                        or _("KOReader'daki durumlar 1000Kitap'la uyumlu; aktarılacak fark yok."),
                })
            end
            local ogeler = {}
            for _i, f in ipairs(farklar) do
                local not_ = ""
                if not f.oneri and f.yuzde then
                    not_ = T(_(" (%1 okunmuş)"), "%" .. math.floor(f.yuzde * 100 + 0.5))
                end
                ogeler[#ogeler + 1] = {
                    metin = T(_("%1: %2 → %3%4"), BinKitap.kitapEtiketi(f.kitap), koAdi(f.ko), koAdi(f.hedef), not_),
                    secili = f.oneri,
                    veri = f,
                }
            end
            self:secimListesi{
                baslik = T(_("KOReader'a aktarılacak durumlar (%1)"), #farklar),
                bilgi = durduruldu and _("Tarama durduruldu; şimdiye kadar bakılanlar listelendi.")
                    or _("Seçili olanlar 1000Kitap'taki duruma göre KOReader'da işaretlenir. Seçili gelmeyenler KOReader'da \"Okunuyor\" olup 1000Kitap'ta \"Okudum\" olan kitaplar; yeniden okuyorsan dokunma."),
                ogeler = ogeler,
                aranabilir = #ogeler > 10,
                onay_metni = _("KOReader'da işaretle (%1)"),
                onay = function(secilenler)
                    local n = 0
                    for _i, f in ipairs(secilenler) do
                        if self:koDurumuYaz(f.yol, f.hedef) then n = n + 1 end
                    end
                    self:bildir(T(_("%1 kitabın KOReader durumu güncellendi."), n))
                end,
            }
        end)
    end
end
