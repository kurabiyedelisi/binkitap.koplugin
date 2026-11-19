--[[
1000Kitap eklentisi: keşif özellikleri.

- Ne okusam?: Okuyacaklarım listesinden rastgele 10 kitap, Kobo'da olanlar açılır
- Okuyacaklarım koleksiyonu: listedeki ve Kobo'da bulunan kitaplar KOReader koleksiyonuna
- Kitap bilgisi: puan, okunma, senin durumun, takip ettiklerinden okuyanlar
- Popüler alıntılar
- Okuma hedefi: göster / belirle
- Uyku ekranında kendi alıntılarından biri
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
        NetworkMgr:runWhenOnline(function()
            local bekle = self:bekle(_("Okuyacakların getiriliyor…"))
            local liste, err = Api:rafinTamami(kadi, "okuyacaklari", 40)
            UIManager:close(bekle)
            if not liste then return self:hataGoster(err) end
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
        if not self.settings:isTrue("uyku_alinti") or not G_reader_settings then return end
        local onb = self.settings:readSetting("alintilarim")
        if type(onb) == "table" and type(onb.liste) == "table" and #onb.liste > 0 then
            local soz = Y.kirp(onb.liste[math.random(1, #onb.liste)]):gsub("%s+", " ")
            soz = kisalt(soz, 450):gsub("%%", "％") -- % işareti mesajda özel anlam taşıyabilir
            G_reader_settings:saveSetting("screensaver_message", "“" .. soz .. "”")
        end
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
            if not self.settings:readSetting("uyku_eski") then
                self.settings:saveSetting("uyku_eski", {
                    mesaj = G_reader_settings:readSetting("screensaver_message"),
                    goster = G_reader_settings:readSetting("screensaver_show_message"),
                })
            end
            self.settings:saveSetting("alintilarim", { zaman = os.time(), liste = liste })
            self.settings:makeTrue("uyku_alinti")
            self.settings:flush()
            G_reader_settings:saveSetting("screensaver_show_message", true)
            self:uykuMesajiGuncelle()
            self:bildir(T(_("%1 alıntın alındı. Cihaz her uykuya geçtiğinde biri gösterilecek."), #liste))
        end)
    end

    function BinKitap:uykuKapat()
        local eski = self.settings:readSetting("uyku_eski")
        if type(eski) == "table" and G_reader_settings then
            if eski.mesaj == nil then G_reader_settings:delSetting("screensaver_message")
            else G_reader_settings:saveSetting("screensaver_message", eski.mesaj) end
            if eski.goster == nil then G_reader_settings:delSetting("screensaver_show_message")
            else G_reader_settings:saveSetting("screensaver_show_message", eski.goster) end
        end
        self.settings:delSetting("uyku_eski")
        self.settings:saveSetting("uyku_alinti", false)
        self.settings:flush()
    end

    function BinKitap:uykuMenuOgesi()
        return {
            text = _("Uyku ekranında alıntılarım"),
            checked_func = function() return self.settings:isTrue("uyku_alinti") end,
            callback = function()
                if self.settings:isTrue("uyku_alinti") then self:uykuKapat() else self:uykuAc() end
            end,
            help_text = _("1000Kitap'taki kendi alıntılarından rastgele biri uyku ekranında mesaj olarak görünür. Kapatınca eski uyku ekranı mesajın geri gelir."),
        }
    end
end
