--[[
1000Kitap eklentisi: keşif özellikleri.

- Ne okusam?: Okuyacaklarım listesinden rastgele 10 kitap, Kobo'da olanlar açılır
- Okuyacaklarım koleksiyonu: listedeki ve Kobo'da bulunan kitaplar KOReader koleksiyonuna
- Kitap bilgisi: puan, okunma, senin durumun, takip ettiklerinden okuyanlar
- Popüler alıntılar
- Okuma hedefi: göster / belirle; "Okudum" sonrası ilerleme bildirimi
- Uyku ekranında kendi alıntılarından biri ve/veya hedef ilerlemesi
]]

local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local LISTE_OMRU = 12 * 3600       -- okuyacaklar listesini bu kadar süre hatırla
local ALINTI_OMRU = 24 * 3600      -- uyku ekranı alıntılarını günde bir yenile
local HEDEF_OMRU = 12 * 3600       -- uyku ekranındaki hedef bilgisini günde iki kez tazele
local KOLEKSIYON_ADI = "1000Kitap – Okuyacaklarım"

return function(BinKitap)
    local Api, Y = BinKitap.Api, BinKitap.Y
    local kisalt = Y.kisalt

    local function metinGoster(baslik, metin)
        local ok, TextViewer = pcall(require, "ui/widget/textviewer")
        if ok and TextViewer then
            UIManager:show(TextViewer:new{ title = baslik, text = metin })
        else
            UIManager:show(InfoMessage:new{ text = baslik .. "\n\n" .. metin })
        end
    end

    local function dosyaVar(yol)
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        if not ok then return true end
        return lfs.attributes(yol, "mode") == "file"
    end

    local function karistir(t)
        local k = {}
        for i, v in ipairs(t) do k[i] = v end
        for i = #k, 2, -1 do
            local j = math.random(1, i)
            k[i], k[j] = k[j], k[i]
        end
        return k
    end

    -------------------------------------------------------------------------
    -- Okuyacaklar listesi ve yerel dosya eşlemesi
    -------------------------------------------------------------------------

    function BinKitap:okuyacaklarListesi(zorla, cb)
        local kadi = self:kullaniciAdiGerekli()
        if not kadi then return end
        local onb = self.settings:readSetting("okuyacaklar_onbellek")
        if not zorla and type(onb) == "table" and onb.kadi == kadi
                and os.time() - (onb.zaman or 0) < LISTE_OMRU and type(onb.liste) == "table" then
            return cb(onb.liste)
        end
        self:rafiGetir(kadi, "okuyacaklari", _("Okuyacakların getiriliyor…"), function(liste)
            self.settings:saveSetting("okuyacaklar_onbellek", { kadi = kadi, zaman = os.time(), liste = liste })
            self.settings:flush()
            cb(liste)
        end)
    end

    --- 1000Kitap kitabından Kobo'daki dosyayı bulan bir işlev döndürür.
    -- Önce eşleştirilmiş dosyalara, sonra dosya adlarına bakar.
    function BinKitap:yerelBulucu()
        local dosyalar = self.settings:readSetting("kitap_dosyalari") or {}
        local dizin
        return function(k)
            local yol = dosyalar[tostring(k.id)]
            if yol and dosyaVar(yol) then return yol end
            if not dizin then dizin = Y.dosyaDizini(Y.kitapDosyalari(BinKitap.evDizini(), true, 5000)) end
            return Y.dosyadaBul(dizin, k.adi)
        end
    end

    -------------------------------------------------------------------------
    -- Ne okusam?
    -------------------------------------------------------------------------

    function BinKitap:neOkusam()
        self:okuyacaklarListesi(false, function(liste)
            if #liste == 0 then return self:bildir(_("Okuyacaklar listen boş.")) end
            local bekle = self:bekle(_("Kobo'daki kitaplarla karşılaştırılıyor…"))
            local bul = self:yerelBulucu()
            local cihazda, digerleri = {}, {}
            for _i, k in ipairs(liste) do
                local yol = bul(k)
                if yol then cihazda[#cihazda + 1] = { kitap = k, yol = yol }
                else digerleri[#digerleri + 1] = { kitap = k } end
            end
            UIManager:close(bekle)
            self:neOkusamGoster(cihazda, digerleri)
        end)
    end

    function BinKitap:kitapAc(yol)
        if self.ui.document and self.ui.switchDocument then
            self.ui:switchDocument(yol)
        else
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(yol)
        end
    end

    function BinKitap:neOkusamGoster(cihazda, digerleri)
        local secim = {}
        for _i, o in ipairs(karistir(cihazda)) do
            if #secim >= 10 then break end
            secim[#secim + 1] = o
        end
        for _i, o in ipairs(karistir(digerleri)) do
            if #secim >= 10 then break end
            secim[#secim + 1] = o
        end
        local dialog
        local buttons = {}
        for _i, o in ipairs(secim) do
            local k = o.kitap
            local etiket = (o.yol and "✓ " or "") .. k.adi .. (k.yazar ~= "" and (" — " .. k.yazar) or "")
            buttons[#buttons + 1] = {{
                text = etiket,
                align = "left",
                callback = function()
                    if o.yol then
                        UIManager:close(dialog)
                        self:kitapAc(o.yol)
                    else
                        self:bildir(T(_("“%1” Kobo'nda yok."), k.adi), 2)
                    end
                end,
            }}
        end
        buttons[#buttons + 1] = {
            { text = _("Başka 10"), callback = function()
                UIManager:close(dialog)
                self:neOkusamGoster(cihazda, digerleri)
            end },
            { text = _("Kapat"), callback = function() UIManager:close(dialog) end },
        }
        dialog = ButtonDialog:new{
            title = T(_("Okuyacaklarından rastgele kitaplar\n✓ = Kobo'nda var (%1 / %2)"), #cihazda, #cihazda + #digerleri),
            title_align = "left",
            buttons = buttons,
        }
        UIManager:show(dialog)
    end

    -------------------------------------------------------------------------
    -- Okuyacaklarım koleksiyonu
    -------------------------------------------------------------------------

    function BinKitap:koleksiyonGuncelle()
        self:okuyacaklarListesi(true, function(liste)
            local ok, RC = pcall(require, "readcollection")
            if not ok or type(RC) ~= "table" or not RC.addItem then
                return self:hataGoster(_("Bu KOReader sürümünde koleksiyonlara erişilemedi."))
            end
            local bekle = self:bekle(_("Koleksiyon güncelleniyor…"))
            local bul = self:yerelBulucu()
            local ad = KOLEKSIYON_ADI
            local sonuc = { cihazda = 0, eklenen = 0, cikarilan = 0 }
            local basarili, hata = pcall(function()
                if RC.addCollection and not (type(RC.coll) == "table" and RC.coll[ad]) then
                    RC:addCollection(ad)
                end
                local bulunan = {}
                for _i, k in ipairs(liste) do
                    local yol = bul(k)
                    if yol then
                        sonuc.cihazda = sonuc.cihazda + 1
                        bulunan[yol] = true
                        if not (RC.isFileInCollection and RC:isFileInCollection(yol, ad)) then
                            RC:addItem(yol, ad)
                            sonuc.eklenen = sonuc.eklenen + 1
                        end
                    end
                end
                -- Artık okuyacaklarında olmayanları (ör. okuduklarını) çıkar
                if type(RC.coll) == "table" and type(RC.coll[ad]) == "table" and RC.removeItem then
                    local cikacak = {}
                    for anahtar, oge in pairs(RC.coll[ad]) do
                        local yol = type(oge) == "table" and oge.file or anahtar
                        if type(yol) == "string" and not bulunan[yol] then cikacak[#cikacak + 1] = yol end
                    end
                    for _i, yol in ipairs(cikacak) do
                        RC:removeItem(yol, ad, true)
                        sonuc.cikarilan = sonuc.cikarilan + 1
                    end
                end
                if RC.write then
                    local ok_w = pcall(RC.write, RC, { [ad] = true })
                    if not ok_w then RC:write() end
                end
            end)
            UIManager:close(bekle)
            if not basarili then
                logger.err("1000Kitap: koleksiyon hatası", hata)
                return self:hataGoster(_("Koleksiyon güncellenemedi: ") .. tostring(hata))
            end
            UIManager:show(InfoMessage:new{
                text = T(_("Okuyacaklarındaki %1 kitaptan %2 tanesi Kobo'nda var.\n%3 kitap eklendi, %4 kitap çıkarıldı.\n\nKoleksiyon: %5"),
                    #liste, sonuc.cihazda, sonuc.eklenen, sonuc.cikarilan, ad),
            })
        end)
    end

    -------------------------------------------------------------------------
    -- Kitap bilgisi ve popüler alıntılar
    -------------------------------------------------------------------------

    function BinKitap:kitapKarti()
        local kitap = self:kitapBilgisi()
        if not kitap then return self:kitapEslestir(function() self:kitapKarti() end) end
        NetworkMgr:runWhenOnline(function()
            local bekle = self:bekle(_("Kitap bilgisi getiriliyor…"))
            local b, err = Api:kitapBilgisi(kitap.id)
            local m = Api:kimlikVar() and Api:okumaDurumu(kitap.id) or nil
            local tanidik = Api:kimlikVar() and Api:tanidikOkurlar(kitap.id) or nil
            UIManager:close(bekle)
            if not b then return self:hataGoster(err) end
            local satirlar = { b.adi .. (b.yazar ~= "" and (" — " .. b.yazar) or "") }
            local baski = {}
            if b.yayinevi ~= "" then baski[#baski + 1] = b.yayinevi end
            if b.baski_yili ~= "" and b.baski_yili ~= "0" then baski[#baski + 1] = b.baski_yili end
            if b.sayfa then baski[#baski + 1] = T(_("%1 sayfa"), b.sayfa) end
            if #baski > 0 then satirlar[#satirlar + 1] = table.concat(baski, " · ") end
            satirlar[#satirlar + 1] = ""
            if b.puan ~= "" then
                satirlar[#satirlar + 1] = T(_("1000Kitap puanı: %1/10 (%2 kişi)"), b.puan, b.puan_kisi ~= "" and b.puan_kisi or "?")
            end
            satirlar[#satirlar + 1] = T(_("%1 okunma · %2 beğeni · %3 alıntı · %4 inceleme"),
                b.okunma ~= "" and b.okunma or "0", b.begeni ~= "" and b.begeni or "0",
                b.alinti ~= "" and b.alinti or "0", b.inceleme ~= "" and b.inceleme or "0")
            if m then
                satirlar[#satirlar + 1] = ""
                local durum = Api.DURUM_ADI[m.durum] or "?"
                if m.mevcut_sayfa and m.mevcut_sayfa > 0 and m.toplam_sayfa then
                    durum = durum .. T(_(" (%1/%2 sayfa)"), m.mevcut_sayfa, m.toplam_sayfa)
                end
                satirlar[#satirlar + 1] = T(_("Senin durumun: %1"), durum)
                if m.puan and m.puan > 0 then satirlar[#satirlar + 1] = T(_("Puanın: %1"), m.puan) end
            end
            if tanidik and #tanidik > 0 then
                satirlar[#satirlar + 1] = ""
                local adlar = {}
                for i, ad in ipairs(tanidik) do
                    if i > 10 then break end
                    adlar[#adlar + 1] = ad
                end
                local ek = #tanidik > 10 and T(_(" ve %1 kişi daha"), #tanidik - 10) or ""
                satirlar[#satirlar + 1] = T(_("Takip ettiklerinden okuyanlar: %1%2"), table.concat(adlar, ", "), ek)
            end
            metinGoster(_("Kitap bilgisi"), table.concat(satirlar, "\n"))
        end)
    end

    function BinKitap:populerAlintilar()
        local kitap = self:kitapBilgisi()
        if not kitap then return self:kitapEslestir(function() self:populerAlintilar() end) end
        NetworkMgr:runWhenOnline(function()
            local bekle = self:bekle(_("Alıntılar getiriliyor…"))
            local liste, err = Api:populerAlintilar(kitap.id)
            UIManager:close(bekle)
            if not liste then return self:hataGoster(err) end
            if #liste == 0 then return self:bildir(_("Bu kitap için alıntı bulunamadı.")) end
            local parcalar = {}
            for _i, a in ipairs(liste) do
                local alt = {}
                if a.uye ~= "" then alt[#alt + 1] = a.uye end
                alt[#alt + 1] = T(_("%1 beğeni"), a.begeni)
                if a.sayfa and a.sayfa > 0 then alt[#alt + 1] = T(_("s. %1"), a.sayfa) end
                parcalar[#parcalar + 1] = "“" .. Y.kirp(a.soz) .. "”\n— " .. table.concat(alt, " · ")
            end
            metinGoster(T(_("%1 — popüler alıntılar"), kitap.adi), table.concat(parcalar, "\n\n"))
        end)
    end

    -------------------------------------------------------------------------
    -- Okuma hedefi
    -------------------------------------------------------------------------

    function BinKitap:hedefMenusu()
        local sene = tonumber(os.date("%Y"))
        return {
            {
                text_func = function()
                    local h = self.settings:readSetting("hedef_onbellek")
                    if type(h) == "table" and h.sene == sene and h.hedef then
                        if h.okunan then return T(_("%1 hedefi: %2 / %3 kitap"), sene, h.okunan, h.hedef) end
                        return T(_("%1 hedefi: %2 kitap"), sene, h.hedef)
                    end
                    return T(_("%1 hedefini göster"), sene)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if not Api:kimlikVar() then return self:kimlikUyarisi() end
                    NetworkMgr:runWhenOnline(function()
                        local h, err = Api:okumaHedefi(sene)
                        if not h then return self:hataGoster(err) end
                        if not h.hedef then
                            self.settings:delSetting("hedef_onbellek")
                            self:bildir(T(_("%1 için bir okuma hedefin yok. \"Hedef belirle\" ile ekleyebilirsin."), sene))
                        else
                            self.settings:saveSetting("hedef_onbellek", { sene = sene, hedef = h.hedef, okunan = h.okunan })
                            local metin = h.okunan and T(_("%1 hedefin: %2 kitap. Şimdiye kadar %3 kitap."), sene, h.hedef, h.okunan)
                                or T(_("%1 hedefin: %2 kitap."), sene, h.hedef)
                            self:bildir(metin, 5)
                        end
                        self.settings:flush()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end)
                end,
            },
            {
                text = _("Hedef belirle"),
                keep_menu_open = true,
                callback = function()
                    if not Api:kimlikVar() then return self:kimlikUyarisi() end
                    local dialog
                    dialog = InputDialog:new{
                        title = T(_("%1 yılında kaç kitap okumak istiyorsun?"), sene),
                        input = "",
                        input_type = "number",
                        buttons = {{
                            { text = _("Vazgeç"), id = "close", callback = function() UIManager:close(dialog) end },
                            { text = _("Kaydet"), is_enter_default = true, callback = function()
                                local n = tonumber(dialog:getInputText())
                                UIManager:close(dialog)
                                if not n or n <= 0 then return end
                                NetworkMgr:runWhenOnline(function()
                                    local ok, err = Api:okumaHedefiKaydet(sene, math.floor(n))
                                    if not ok then return self:hataGoster(err) end
                                    self.settings:saveSetting("hedef_onbellek", { sene = sene, hedef = math.floor(n) })
                                    self.settings:flush()
                                    self:bildir(T(_("%1 hedefin %2 kitap olarak kaydedildi."), sene, math.floor(n)))
                                end)
                            end },
                        }},
                    }
                    UIManager:show(dialog)
                    dialog:onShowKeyboard()
                end,
            },
        }
    end

    --- Hedef satırı: "2026 hedefi: 23 / 50 kitap" (önbellekten)
    function BinKitap:hedefSatiri()
        local sene = tonumber(os.date("%Y"))
        local h = self.settings:readSetting("hedef_onbellek")
        if type(h) ~= "table" or h.sene ~= sene or not h.hedef then return nil end
        if h.okunan then
            if h.okunan >= h.hedef then
                return T(_("%1 hedefi tamam: %2 / %3 kitap"), sene, h.okunan, h.hedef)
            end
            return T(_("%1 hedefi: %2 / %3 kitap"), sene, h.okunan, h.hedef)
        end
        return T(_("%1 hedefi: %2 kitap"), sene, h.hedef)
    end

    --- 1000Kitap'tan hedefi tazeler. cb(h) (h nil olabilir)
    function BinKitap:hedefTazele(cb)
        local sene = tonumber(os.date("%Y"))
        local h = Api:okumaHedefi(sene)
        if h then
            if h.hedef then
                self.settings:saveSetting("hedef_onbellek",
                    { sene = sene, hedef = h.hedef, okunan = h.okunan, zaman = os.time() })
            else
                self.settings:delSetting("hedef_onbellek")
            end
            self.settings:flush()
        end
        if cb then cb(h) end
    end

    --- "Okudum" gönderildikten sonra hedef ilerlemesini kısa bir bildirimle gösterir.
    -- Toplu gönderimde tek bildirim olsun diye gönderim bitene kadar bekler.
    function BinKitap:hedefBildirimiPlanla()
        if not self.settings:nilOrTrue("hedef_bildirimi") then return end
        if self._hedef_planli then UIManager:unschedule(self._hedef_planli) end
        local f
        f = function()
            if BinKitap.gonderimSuruyor() then return UIManager:scheduleIn(5, f) end
            self._hedef_planli = nil
            if not NetworkMgr:isOnline() then return end
            local onceki = self.settings:readSetting("hedef_onbellek")
            self:hedefTazele(function(h)
                if not h or not h.hedef or not h.okunan then return end
                local metin
                if h.okunan >= h.hedef then
                    local ilk_kez = type(onceki) == "table" and onceki.okunan and onceki.okunan < h.hedef
                    metin = ilk_kez and T(_("Tebrikler! %1 okuma hedefini tamamladın: %2 / %3 kitap."), os.date("%Y"), h.okunan, h.hedef)
                        or T(_("%1 hedefin: %2 / %3 kitap. Hedefin üstündesin."), os.date("%Y"), h.okunan, h.hedef)
                else
                    local kalan_gun = math.max(1, tonumber(os.date("%j", os.time{ year = tonumber(os.date("%Y")), month = 12, day = 31 }))
                        - tonumber(os.date("%j")))
                    local kalan = h.hedef - h.okunan
                    local hafta = math.max(1, math.floor(kalan_gun / 7 + 0.5))
                    metin = T(_("%1 hedefin: %2 / %3 kitap.\n%4 kitap kaldı; yıl sonuna %5 hafta var."),
                        os.date("%Y"), h.okunan, h.hedef, kalan, hafta)
                end
                UIManager:show(InfoMessage:new{ text = metin, timeout = 6 })
                if self.uykuMesajiGuncelle then self:uykuMesajiGuncelle() end
            end)
        end
        self._hedef_planli = f
        UIManager:scheduleIn(4, f)
    end

    -------------------------------------------------------------------------
    -- Uyku ekranında alıntı
    -------------------------------------------------------------------------

    function BinKitap:alintilarimiGetir(kadi)
        local hepsi, s = {}, nil
        for _i = 1, 5 do
            local liste, sonraki_veya_err = Api:okurAlintilari(kadi, s)
            if not liste then return (#hepsi > 0) and hepsi or nil, sonraki_veya_err end
            for _i, a in ipairs(liste) do hepsi[#hepsi + 1] = a.soz end
            s = sonraki_veya_err
            if not s then break end
        end
        return hepsi
    end

    function BinKitap:uykuMesajiGuncelle()
        local alinti_acik, hedef_acik = self.settings:isTrue("uyku_alinti"), self.settings:isTrue("uyku_hedef")
        if not (alinti_acik or hedef_acik) or not G_reader_settings then return end
        local parcalar = {}
        local onb = self.settings:readSetting("alintilarim")
        if alinti_acik and type(onb) == "table" and type(onb.liste) == "table" and #onb.liste > 0 then
            local soz = Y.kirp(onb.liste[math.random(1, #onb.liste)]):gsub("%s+", " ")
            soz = kisalt(soz, 450)
            parcalar[#parcalar + 1] = "“" .. soz .. "”"
        end
        if hedef_acik then
            local satir = self:hedefSatiri()
            if satir then parcalar[#parcalar + 1] = satir end
            local h = self.settings:readSetting("hedef_onbellek")
            local eski_hedef = type(h) ~= "table" or os.time() - (h.zaman or 0) > HEDEF_OMRU
            if eski_hedef and Api:kimlikVar() and NetworkMgr:isOnline() and not self.hedef_yenileniyor then
                self.hedef_yenileniyor = true
                UIManager:scheduleIn(12, function()
                    self:hedefTazele(function() self.hedef_yenileniyor = false end)
                end)
            end
        end
        if #parcalar > 0 then
            -- % işareti mesajda özel anlam taşıyabilir
            local mesaj = table.concat(parcalar, "\n\n"):gsub("%%", "％")
            G_reader_settings:saveSetting("screensaver_message", mesaj)
        end
        if not alinti_acik then return end
        -- Günde bir kez, bağlıysa listeyi tazele
        local eski = type(onb) ~= "table" or os.time() - (onb.zaman or 0) > ALINTI_OMRU
        if eski and self.kullanici_adi and NetworkMgr:isOnline() and not self.uyku_yenileniyor then
            self.uyku_yenileniyor = true
            UIManager:scheduleIn(10, function()
                local liste = self:alintilarimiGetir(self.kullanici_adi)
                self.uyku_yenileniyor = false
                if liste and #liste > 0 then
                    self.settings:saveSetting("alintilarim", { zaman = os.time(), liste = liste })
                    self.settings:flush()
                end
            end)
        end
    end

    function BinKitap:uykuAc()
        local kadi = self:kullaniciAdiGerekli()
        if not kadi then return end
        NetworkMgr:runWhenOnline(function()
            local bekle = self:bekle(_("Alıntıların getiriliyor…"))
            local liste, err = self:alintilarimiGetir(kadi)
            UIManager:close(bekle)
            if not liste then return self:hataGoster(err) end
            if #liste == 0 then return self:bildir(_("1000Kitap'ta henüz alıntın yok.")) end
            self:uykuEskiyiSakla()
            self.settings:saveSetting("alintilarim", { zaman = os.time(), liste = liste })
            self.settings:makeTrue("uyku_alinti")
            self.settings:flush()
            G_reader_settings:saveSetting("screensaver_show_message", true)
            self:uykuMesajiGuncelle()
            self:bildir(T(_("%1 alıntın alındı. Cihaz her uykuya geçtiğinde biri gösterilecek."), #liste))
        end)
    end

    function BinKitap:uykuEskiyiSakla()
        if not self.settings:readSetting("uyku_eski") and G_reader_settings then
            self.settings:saveSetting("uyku_eski", {
                mesaj = G_reader_settings:readSetting("screensaver_message"),
                goster = G_reader_settings:readSetting("screensaver_show_message"),
            })
        end
    end

    function BinKitap:uykuHedefAc()
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        NetworkMgr:runWhenOnline(function()
            self:hedefTazele(function(h)
                if not h then return self:hataGoster(_("Okuma hedefin alınamadı.")) end
                if not h.hedef then
                    return self:bildir(T(_("%1 için bir okuma hedefin yok. Önce \"Okuma hedefi → Hedef belirle\"."), os.date("%Y")))
                end
                self:uykuEskiyiSakla()
                self.settings:makeTrue("uyku_hedef")
                self.settings:flush()
                G_reader_settings:saveSetting("screensaver_show_message", true)
                self:uykuMesajiGuncelle()
                self:bildir(T(_("Uyku ekranında görünecek: %1"), self:hedefSatiri() or ""))
            end)
        end)
    end

    --- Uyku ekranı seçeneklerinden birini kapatır; ikisi de kapanınca eski mesaj geri gelir.
    function BinKitap:uykuKapat(hangisi)
        self.settings:saveSetting(hangisi == "hedef" and "uyku_hedef" or "uyku_alinti", false)
        if self.settings:isTrue("uyku_alinti") or self.settings:isTrue("uyku_hedef") then
            self.settings:flush()
            return self:uykuMesajiGuncelle()
        end
        local eski = self.settings:readSetting("uyku_eski")
        if type(eski) == "table" and G_reader_settings then
            if eski.mesaj == nil then G_reader_settings:delSetting("screensaver_message")
            else G_reader_settings:saveSetting("screensaver_message", eski.mesaj) end
            if eski.goster == nil then G_reader_settings:delSetting("screensaver_show_message")
            else G_reader_settings:saveSetting("screensaver_show_message", eski.goster) end
        end
        self.settings:delSetting("uyku_eski")
        self.settings:flush()
    end

    function BinKitap:uykuMenuOgesi()
        return {
            text = _("Uyku ekranı"),
            sub_item_table = {
                {
                    text = _("Alıntılarımdan biri"),
                    checked_func = function() return self.settings:isTrue("uyku_alinti") end,
                    callback = function()
                        if self.settings:isTrue("uyku_alinti") then self:uykuKapat("alinti") else self:uykuAc() end
                    end,
                    help_text = _("1000Kitap'taki kendi alıntılarından rastgele biri uyku ekranında mesaj olarak görünür. Kapatınca eski uyku ekranı mesajın geri gelir."),
                },
                {
                    text = _("Okuma hedefi ilerlemesi"),
                    checked_func = function() return self.settings:isTrue("uyku_hedef") end,
                    callback = function()
                        if self.settings:isTrue("uyku_hedef") then self:uykuKapat("hedef") else self:uykuHedefAc() end
                    end,
                    help_text = _("Uyku ekranının mesajına \"2026 hedefi: 23 / 50 kitap\" gibi bir satır ekler. Alıntıyla birlikte de açılabilir."),
                },
            },
        }
    end
end
