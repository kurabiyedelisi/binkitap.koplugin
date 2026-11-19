--[[
1000Kitap eklentisi: okuduklarını aktar.

KOReader'da "Bitti" olarak işaretlediğin (ya da sonuna kadar okuduğun) kitapları bulur,
seçtiklerini 1000Kitap'ta "Okudum" yapar; sonra bu kitaplardaki henüz gönderilmemiş
vurguları listeleyip alıntı olarak göndermek isteyip istemediğini sorar.

Kitaplar açılmaz: bilgi KOReader'ın yan dosyalarından (.sdr) okunur. Tarama küçük
adımlarla yapılır ki cihaz kilitlenmesin.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ADIM_BASINA = 8        -- her adımda bakılacak dosya
local soruldu_bu_oturumda = false

return function(BinKitap)
    local Api, Y = BinKitap.Api, BinKitap.Y
    local kirp = Y.kirp

    local function dosyaAdi(yol)
        return (yol or ""):match("([^/]+)$") or yol
    end

    local function yanDosya(yol)
        local ok, DocSettings = pcall(require, "docsettings")
        if not ok or not DocSettings then return nil end
        local ok2, var = pcall(function() return DocSettings:hasSidecarFile(yol) end)
        if not ok2 or not var then return nil end
        local ok3, ds = pcall(function() return DocSettings:open(yol) end)
        if ok3 then return ds end
    end

    --- Yan dosyadaki vurgular (yeni "annotations" ya da eski "highlight" biçimi).
    local function vurgular(ds)
        local liste = {}
        local ann = ds:readSetting("annotations")
        if type(ann) == "table" and #ann > 0 then
            for _i, a in ipairs(ann) do
                if a.drawer and kirp(a.text) ~= "" then liste[#liste + 1] = a end
            end
            return liste
        end
        local hl = ds:readSetting("highlight")
        if type(hl) == "table" then
            local sayfalar = {}
            for sayfa in pairs(hl) do sayfalar[#sayfalar + 1] = sayfa end
            table.sort(sayfalar, function(x, y) return (tonumber(x) or 0) < (tonumber(y) or 0) end)
            for _i, sayfa in ipairs(sayfalar) do
                for _j, a in ipairs(type(hl[sayfa]) == "table" and hl[sayfa] or {}) do
                    if kirp(a.text) ~= "" then
                        liste[#liste + 1] = {
                            text = a.text, note = a.note, datetime = a.datetime, pos0 = a.pos0,
                            pageno = tonumber(sayfa), drawer = a.drawer or "lighten",
                        }
                    end
                end
            end
        end
        return liste
    end

    local function gonderilmemis(self, ds)
        local gonderilen = ds:readSetting("binkitap_gonderilen") or {}
        local yeni = {}
        for _i, a in ipairs(vurgular(ds)) do
            if not gonderilen[self:vurguAnahtari(a)] then yeni[#yeni + 1] = a end
        end
        table.sort(yeni, function(x, y) return tostring(x.datetime or "") < tostring(y.datetime or "") end)
        return yeni
    end

    --- KOReader'da bitirilmiş kitapları küçük adımlarla bulur. bitince(bulunanlar, durduruldu)
    function BinKitap:bitenleriTara(bitince)
        local bekle = self:bekle(_("Kitapların taranıyor…"))
        local dosyalar = Y.kitapDosyalari(BinKitap.evDizini(), true, 5000)
        UIManager:close(bekle)
        local bulunan, i, iptal = {}, 0, false
        local kutu, kapatiyorum
        local function goster()
            if kutu then kapatiyorum = true; UIManager:close(kutu); kapatiyorum = false end
            local k
            k = InfoMessage:new{
                text = T(_("KOReader'da bitirdiğin kitaplar aranıyor…\n\n%1 / %2 kitap · %3 bulundu\n\nDurdurmak için dokun."),
                    i, #dosyalar, #bulunan),
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
            if iptal then kapat(); return bitince(bulunan, true) end
            for _n = 1, ADIM_BASINA do
                i = i + 1
                local yol = dosyalar[i]
                if not yol then kapat(); return bitince(bulunan, false) end
                local ds = yanDosya(yol)
                if ds then
                    local ozet = ds:readSetting("summary")
                    local durum = type(ozet) == "table" and ozet.status or nil
                    local yuzde = tonumber(ds:readSetting("percent_finished"))
                    if durum == "complete" or (yuzde and yuzde >= 0.99 and durum ~= "abandoned") then
                        local props = ds:readSetting("doc_props") or {}
                        local baslik = kirp(props.display_title or props.title)
                        bulunan[#bulunan + 1] = {
                            yol = yol,
                            baslik = baslik ~= "" and baslik or Y.dosyaAdindanBaslik(yol),
                            kesin = durum == "complete",
                            vurgu = #gonderilmemis(self, ds),
                        }
                    end
                end
            end
            if i % (ADIM_BASINA * 5) == 0 then goster() end
            UIManager:scheduleIn(0.05, adim)
        end
        goster()
        adim()
    end

    --- Okuduklarını aktar: bul → seç → "Okudum" yap → vurguları sor.
    function BinKitap:okuduklarimiAktar()
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        self:bitenleriTara(function(bulunan, durduruldu)
            if #bulunan == 0 then
                if durduruldu then return end
                return self:bildir(_("KOReader'da bitirdiğin kitap bulunamadı. (Kitabı bitirince KOReader'da \"Bitti\" olarak işaretlenmiş olmalı.)"), 5)
            end
            table.sort(bulunan, function(x, y) return Y.normal(x.baslik) < Y.normal(y.baslik) end)
            local ogeler, kesin = {}, 0
            for _i, b in ipairs(bulunan) do
                local ek = b.kesin and _("bitti") or _("sonuna kadar okunmuş")
                if b.vurgu > 0 then ek = ek .. " · " .. T(_("%1 vurgu"), b.vurgu) end
                ogeler[#ogeler + 1] = { metin = b.baslik, ek = ek, secili = b.kesin, veri = b.yol }
                if b.kesin then kesin = kesin + 1 end
            end
            local bilgi = T(_("KOReader'da bitirdiğin %1 kitap bulundu. Seçtiklerin 1000Kitap'ta \"Okudum\" yapılacak; ardından vurgularını alıntı olarak göndermek isteyip istemediğini soracağım. \"Bitti\" işaretlenmemiş ama sonuna kadar okunmuş olanlar seçili gelmez."),
                #bulunan)
            if durduruldu then bilgi = _("Tarama yarıda kesildi; bulunanlar:") .. "\n" .. bilgi end
            self:secimListesi{
                baslik = _("Okuduklarını 1000Kitap'a aktar"),
                bilgi = bilgi,
                ogeler = ogeler,
                aranabilir = #ogeler > 15,
                onay_metni = _("Seçilenleri \"Okudum\" yap (%1)"),
                onay = function(yollar)
                    self:topluDurumEkle(yollar, Api.DURUM.okudum, function(hazir)
                        UIManager:scheduleIn(1, function() self:aktarilanVurgular(hazir) end)
                    end)
                end,
            }
        end)
    end

    --- "Okudum" yapılan kitaplardan gönderilmemiş vurgusu olanları listeler.
    function BinKitap:aktarilanVurgular(hazir)
        local adaylar = {}
        for _i, e in ipairs(hazir or {}) do
            local ds = yanDosya(e.yol)
            if ds then
                local yeni = gonderilmemis(self, ds)
                if #yeni > 0 then
                    adaylar[#adaylar + 1] = { yol = e.yol, kitap = e.kitap, vurgular = yeni,
                        sayfa_sayisi = tonumber(ds:readSetting("doc_pages")) }
                end
            end
        end
        if #adaylar == 0 then return end
        local ogeler = {}
        for _i, a in ipairs(adaylar) do
            ogeler[#ogeler + 1] = { metin = a.kitap.adi, ek = T(_("%1 vurgu"), #a.vurgular), secili = false, veri = a }
        end
        self:secimListesi{
            baslik = _("Alıntılarını da göndereyim mi?"),
            bilgi = T(_("%1 kitapta KOReader'da yaptığın ve henüz gönderilmemiş vurgular var. Seçtiğin kitapların vurguları 1000Kitap'a gönderilecek; istemiyorsan bu listeyi kapat."), #adaylar),
            ogeler = ogeler,
            onay_metni = _("Seçilenlerin vurgularını gönder (%1)"),
            onay = function(secilen)
                local toplam = 0
                for _i, a in ipairs(secilen) do toplam = toplam + #a.vurgular end
                local dialog
                dialog = ButtonDialog:new{
                    title = T(_("%1 vurgu nasıl gönderilsin?"), toplam),
                    buttons = {
                        {{ text = _("Herkese açık alıntı"), callback = function()
                            UIManager:close(dialog)
                            self:aktarilanVurgulariSirala(secilen, false)
                        end }},
                        {{ text = _("Özel not (yalnızca sen görürsün)"), callback = function()
                            UIManager:close(dialog)
                            self:aktarilanVurgulariSirala(secilen, true)
                        end }},
                        {{ text = _("Vazgeç"), callback = function() UIManager:close(dialog) end }},
                    },
                }
                UIManager:show(dialog)
            end,
        }
    end

    function BinKitap:aktarilanVurgulariSirala(secilen, ozel)
        NetworkMgr:runWhenOnline(function()
            -- Basılı sayfa sayısı bilinmeyen kitaplar için bir kez sor
            local eksik = {}
            for _i, a in ipairs(secilen) do
                if not tonumber(a.kitap.basili_sayfa) then eksik[#eksik + 1] = a end
            end
            if #eksik > 0 then
                local bekle = self:bekle(_("Sayfa bilgileri alınıyor…"))
                for _i, a in ipairs(eksik) do
                    local b = Api:kitapBilgisi(a.kitap.id)
                    if b and b.sayfa then a.kitap.basili_sayfa = b.sayfa end
                end
                UIManager:close(bekle)
            end
            local ogeler = {}
            local yorum_ayari = self.settings:readSetting("yorum_ayari") or 0
            for _i, a in ipairs(secilen) do
                local basili = tonumber(a.kitap.basili_sayfa)
                local ds = yanDosya(a.yol)
                local gonderilen = ds and ds:readSetting("binkitap_gonderilen") or {}
                for _j, v in ipairs(a.vurgular) do
                    local sayfa = ""
                    local pageno = tonumber(v.pageno) or (type(v.page) == "number" and v.page) or nil
                    if pageno and basili and a.sayfa_sayisi and a.sayfa_sayisi > 0 then
                        sayfa = tostring(math.max(1, math.min(basili, math.floor(pageno / a.sayfa_sayisi * basili + 0.5))))
                    end
                    local soz, notu = kirp(v.text), kirp(v.note)
                    if ozel then
                        local metin = "“" .. soz .. "”" .. (sayfa ~= "" and T(_(" (s. %1)"), sayfa) or "")
                        if notu ~= "" then metin = metin .. "\n\n" .. notu end
                        ogeler[#ogeler + 1] = { tur = "ozel_not", kitap_id = a.kitap.id, kitap_adi = a.kitap.adi,
                            metin = metin, anahtar = Api.rastgeleKod(16) }
                    else
                        ogeler[#ogeler + 1] = { tur = "alinti", kitap_id = a.kitap.id, kitap_adi = a.kitap.adi,
                            soz = soz, sayfa = sayfa, ekbilgi = notu, yorum_ayari = yorum_ayari }
                    end
                    gonderilen[self:vurguAnahtari(v)] = true
                end
                if ds then
                    ds:saveSetting("binkitap_gonderilen", gonderilen)
                    local ok, err = pcall(function() ds:flush() end)
                    if not ok then logger.warn("1000Kitap: yan dosya yazılamadı", a.yol, err) end
                end
            end
            self:topluSiraya(ogeler)
            self:bildir(T(_("%1 vurgu sıraya alındı."), #ogeler), 2)
            self:kuyruguGonder(false)
        end)
    end

    --- Eklenti ilk kez hesapla kullanılınca bir kez sorar.
    function BinKitap:ilkAktarimSor()
        if soruldu_bu_oturumda or self.settings:readSetting("okunanlar_soruldu") then return end
        if not Api:kimlikVar() then return end
        soruldu_bu_oturumda = true
        UIManager:scheduleIn(3, function()
            if self.settings:readSetting("okunanlar_soruldu") then return end
            self.settings:saveSetting("okunanlar_soruldu", true)
            self.settings:flush()
            UIManager:show(ConfirmBox:new{
                text = _("1000Kitap eklentisi hazır.\n\nKOReader'da daha önce bitirdiğin kitapları bulup 1000Kitap'ta \"Okudum\" yapayım mı? Önce listeyi gösterip seçtireceğim, sonra vurgularını göndermek isteyip istemediğini soracağım."),
                ok_text = _("Bul"),
                cancel_text = _("Sonra"),
                ok_callback = function() self:okuduklarimiAktar() end,
                cancel_callback = function()
                    self:bildir(_("İstediğin zaman: Araçlar → 1000Kitap → Okuduklarımı aktar"), 4)
                end,
            })
        end)
    end
end
