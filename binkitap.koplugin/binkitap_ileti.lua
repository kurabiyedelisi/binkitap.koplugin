--[[
1000Kitap eklentisi: ileti (gönderi) yazma.

Alıntı değil, kendi yazını paylaşmak için. Başlık isteğe bağlı; okuduğun kitap
iletiye etiketlenebilir (1000Kitap'ta "#k:<kitap id>" olarak görünür). Yazdığın
metin taslak olarak saklanır: pencereyi kapatsan da, gönderim başarısız olsa da kaybolmaz.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

return function(BinKitap)
    local Api, Y = BinKitap.Api, BinKitap.Y
    local kirp, kisalt = Y.kirp, Y.kisalt

    local function yorumAyariAdi(kod)
        for _i, y in ipairs(Api.YORUM_AYARLARI) do
            if y.kod == kod then return y.ad end
        end
        return Api.YORUM_AYARLARI[1].ad
    end

    function BinKitap:iletiTaslagi()
        local t = self.settings:readSetting("ileti_taslagi")
        return type(t) == "table" and t or nil
    end

    function BinKitap:iletiTaslagiKaydet(taslak)
        if taslak then
            local kayit = {}
            for k, v in pairs(taslak) do
                if type(v) ~= "function" then kayit[k] = v end
            end
            self.settings:saveSetting("ileti_taslagi", kayit)
        else
            self.settings:delSetting("ileti_taslagi")
        end
        self.settings:flush()
    end

    --- İleti penceresini açar; varsa taslaktan devam eder.
    function BinKitap:iletiYaz()
        local taslak = self:iletiTaslagi() or {
            metin = "", baslik = "",
            yorum_ayari = self.settings:readSetting("yorum_ayari") or 0,
        }
        taslak.ileti = true
        local kitap = self.ui.document and self:kitapBilgisi()
        if kitap and not taslak.kitap_id and not taslak.kitapsiz then
            taslak.kitap_id, taslak.kitap_adi = kitap.id, kitap.adi
        end
        self:iletiPenceresi(taslak)
    end

    function BinKitap:iletiPenceresi(taslak)
        self:iletiTaslagiKaydet(taslak)
        local satirlar = { _("Yeni ileti"), "" }
        if kirp(taslak.baslik) ~= "" then satirlar[#satirlar + 1] = T(_("Başlık: %1"), kisalt(taslak.baslik, 120)) end
        if kirp(taslak.metin) ~= "" then
            satirlar[#satirlar + 1] = kisalt(taslak.metin, 600)
        else
            satirlar[#satirlar + 1] = _("(Henüz metin yok. \"Metni yaz\"a dokun.)")
        end
        satirlar[#satirlar + 1] = ""
        satirlar[#satirlar + 1] = taslak.kitap_id
            and T(_("Etiketli kitap: %1"), taslak.kitap_adi or "?")
            or _("Kitap etiketlenmedi")
        satirlar[#satirlar + 1] = T(_("Konu: %1 · Yorumlar: %2"), taslak.konu_adi or _("yok"), yorumAyariAdi(taslak.yorum_ayari))

        local acik_kitap = self.ui.document and self:kitapBilgisi()
        local dialog
        local function kapatVe(f) return function() UIManager:close(dialog); f() end end
        local kitap_dugmesi
        if taslak.kitap_id then
            kitap_dugmesi = { text = _("Kitap etiketini kaldır"), callback = kapatVe(function()
                taslak.kitap_id, taslak.kitap_adi, taslak.kitapsiz = nil, nil, true
                self:iletiPenceresi(taslak)
            end) }
        else
            kitap_dugmesi = { text = _("Kitabı etiketle"), enabled = acik_kitap and true or false,
                callback = kapatVe(function()
                    taslak.kitap_id, taslak.kitap_adi, taslak.kitapsiz = acik_kitap.id, acik_kitap.adi, nil
                    self:iletiPenceresi(taslak)
                end) }
        end
        dialog = ButtonDialog:new{
            title = table.concat(satirlar, "\n"),
            title_align = "left",
            buttons = {
                {
                    { text = _("Metni yaz"), callback = kapatVe(function() self:alanDuzenle(taslak, "metin", _("İleti"), true) end) },
                    { text = _("Başlık"), callback = kapatVe(function() self:alanDuzenle(taslak, "baslik", _("Başlık (isteğe bağlı)"), false) end) },
                },
                {
                    kitap_dugmesi,
                    { text = _("Konu"), callback = kapatVe(function() self:konuSec(taslak) end) },
                    { text = _("Yorumlar"), callback = kapatVe(function() self:yorumAyariSec(taslak) end) },
                },
                {
                    { text = _("Taslağı sil"), callback = kapatVe(function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Bu ileti taslağı silinsin mi?"),
                            ok_text = _("Sil"),
                            ok_callback = function() self:iletiTaslagiKaydet(nil) end,
                            cancel_callback = function() self:iletiPenceresi(taslak) end,
                        })
                    end) },
                    { text = _("Kapat"), callback = function() UIManager:close(dialog) end },
                    { text = _("Paylaş"), enabled = kirp(taslak.metin) ~= "", callback = kapatVe(function()
                        self:iletiSirala(taslak)
                    end) },
                },
            },
        }
        UIManager:show(dialog)
    end

    function BinKitap:iletiSirala(taslak)
        local metin = kirp(taslak.metin)
        if metin == "" then return end
        local gonderilecek = metin
        if taslak.kitap_id then gonderilecek = metin .. "\n\n#k:" .. tostring(taslak.kitap_id) end
        self:siraya({
            tur = "ileti",
            metin = gonderilecek,
            baslik = kirp(taslak.baslik),
            konu_id = taslak.konu_id, konu_adi = taslak.konu_adi,
            yorum_ayari = taslak.yorum_ayari or 0,
            kitap_adi = taslak.kitap_adi,
            taslak = {
                metin = taslak.metin, baslik = taslak.baslik, kitap_id = taslak.kitap_id,
                kitap_adi = taslak.kitap_adi, kitapsiz = taslak.kitapsiz, konu_id = taslak.konu_id,
                konu_adi = taslak.konu_adi, yorum_ayari = taslak.yorum_ayari,
            },
        })
        self:iletiTaslagiKaydet(nil)
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        if NetworkMgr:isOnline() then
            self:kuyruguGonder(false)
        else
            self:bildir(_("İleti sıraya alındı. Wi-Fi açılınca paylaşılacak."))
            NetworkMgr:runWhenOnline(function() self:kuyruguGonder(false) end)
        end
    end

    --- 1000Kitap iletiyi reddederse metin kaybolmasın: taslağa geri koy.
    function BinKitap:iletiGeriAl(oge)
        if type(oge.taslak) ~= "table" or self:iletiTaslagi() then return false end
        self:iletiTaslagiKaydet(oge.taslak)
        return true
    end

    function BinKitap:onBinKitapIletiYaz()
        self:iletiYaz()
        return true
    end
end
