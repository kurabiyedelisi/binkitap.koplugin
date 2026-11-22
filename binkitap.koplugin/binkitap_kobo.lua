--[[
1000Kitap eklentisi: Kobo Senkron bölümü.

Kobo'nun kendi okuyucusunda yapılan vurguları, notları, yer imlerini, okuma
ilerlemesini ve listeleri KOReader'a aktaran Kobo Senkron (önceden ayrı
kobosync.koplugin eklentisi) artık 1000Kitap'ın içinde. Asıl iş
binkitap_kobo_senkron.lua'da; burası onu 1000Kitap'a bağlar: menü, 1000Kitap
ekranı, hareket eylemleri, SimpleUI düğmesi.

Eski eklentiden kalanlar aynen kullanılır: ayarlar (kobosync.lua), kitapların yan
dosyalarındaki kobosync_* kayıtları, hareket eylemlerinin adları (kobosync_sync,
kobosync_menu, kobosync_report) ve SimpleUI düğmesinin kimliği (kobosync). Yani
kurulu hareketler ve SimpleUI düğmesi çalışmaya devam eder, aktarılmış notlar
tekrar eklenmez.

Eski eklenti hâlâ açıksa Kobo işlerini o yapar (ikisi aynı anda aktarmasın diye),
1000Kitap da onu kapatmayı önerir.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local eklenti_dizini = (debug.getinfo(1, "S").source or ""):match("^@(.+)/[^/]+$") or "."
local function yukle(ad)
    local ok, m = pcall(require, ad)
    if ok then return m end
    return dofile(eklenti_dizini .. "/" .. ad .. ".lua")
end

local Kobo = yukle("binkitap_kobo_senkron")
local KoboDB = yukle("binkitap_kobo_db")

local ESKI_AD = "kobosync"            -- eski eklentinin klasör adı (kobosync.koplugin)
local eski_soruldu = false            -- bu KOReader oturumunda soruldu mu

return function(BinKitap)
    BinKitap.Kobo = Kobo
    BinKitap.KoboDB = KoboDB

    --- Eski, ayrı Kobo Senkron eklentisi açıksa onun örneği.
    function BinKitap:eskiKoboEklentisi()
        local ui = self.ui
        local eski = type(ui) == "table" and ui[ESKI_AD] or nil
        if type(eski) == "table" and eski ~= self.kobo then return eski end
    end

    --- Kobo işlerini yapacak nesne: eski eklenti açıksa o, değilse bizimki.
    function BinKitap:koboNesnesi()
        return self:eskiKoboEklentisi() or self.kobo
    end

    --- Bu cihazda Kobo Senkron'un yapacak işi var mı (Kobo veritabanı ya da eski eklenti)?
    function BinKitap:koboVarMi()
        if self:eskiKoboEklentisi() then return true end
        return self.kobo ~= nil and KoboDB.exists(self.kobo:dbPath()) and true or false
    end

    function BinKitap:koboBaslat()
        self.kobo = Kobo.yeni{
            ui = self.ui, view = self.view, dialog = self.dialog, sahip = self,
        }
        if not self.ui.document then
            UIManager:scheduleIn(4, function() self:eskiKoboUyarisi() end)
        end
    end

    function BinKitap:koboEylemleriKaydet()
        Dispatcher:registerAction("kobosync_sync", {
            category = "none", event = "KoboSyncNow", title = _("Kobo: şimdi senkronize et"), general = true,
        })
        Dispatcher:registerAction("kobosync_menu", {
            category = "none", event = "KoboSyncMenu", title = _("Kobo senkron menüsü"), general = true,
        })
        Dispatcher:registerAction("kobosync_report", {
            category = "none", event = "KoboSyncReport", title = _("Kobo'da notlu kitaplar"), general = true,
        })
    end

    -- Hareket eylemleri. Eski eklenti açıksa olayı ona bırak (true dönme).
    function BinKitap:onKoboSyncNow()
        if self:eskiKoboEklentisi() or not self.kobo then return end
        self.kobo:runScan(true)
        return true
    end

    function BinKitap:onKoboSyncMenu()
        if self:eskiKoboEklentisi() or not self.kobo then return end
        self.kobo:showQuickDialog()
        return true
    end

    function BinKitap:onKoboSyncReport()
        if self:eskiKoboEklentisi() or not self.kobo then return end
        self.kobo:showReport()
        return true
    end

    --- Okuyucu açıldı: o kitabın yeni Kobo notlarını ekle, Kobo'da daha ileride kaldıysan sor.
    function BinKitap:koboKitapAcildi()
        if self.kobo then self.kobo:onReaderReady() end
    end

    --- 1000Kitap ekranı ve SimpleUI'deki "Kobo" düğmesi
    function BinKitap:koboHizliMenu()
        local k = self:koboNesnesi()
        if not k then return self:bildir(_("Kobo Senkron bu cihazda çalışmıyor."), 3) end
        k:showQuickDialog()
    end

    function BinKitap:koboSimdi()
        local k = self:koboNesnesi()
        if k then k:runScan(true) end
    end

    function BinKitap:koboRapor()
        local k = self:koboNesnesi()
        if k then k:showReport() end
    end

    --- Eski eklentiyi KOReader'ın eklenti ayarından kapatır; yeniden başlatınca geçerli olur.
    function BinKitap:eskiKoboyuKapat()
        local kapali = G_reader_settings:readSetting("plugins_disabled")
        if type(kapali) ~= "table" then kapali = {} end
        kapali[ESKI_AD] = true
        G_reader_settings:saveSetting("plugins_disabled", kapali)
        if G_reader_settings.flush then G_reader_settings:flush() end
        logger.info("1000Kitap: eski Kobo Senkron eklentisi kapatıldı")
        local mesaj = _("Eski Kobo Senkron eklentisi kapatıldı. KOReader yeniden başlayınca Kobo işlerini 1000Kitap yapar; ayarların ve aktarılmış notların aynen kalır.\n\nİstersen sonra koreader/plugins içindeki kobosync.koplugin klasörünü silebilirsin.")
        if UIManager.askForRestart then
            UIManager:askForRestart(mesaj)
        else
            self:bildir(mesaj, 8)
        end
    end

    --- Dosya tarayıcısı açılınca, eski eklenti hâlâ açıksa bir kez sorar.
    function BinKitap:eskiKoboUyarisi()
        if eski_soruldu or not self:eskiKoboEklentisi() then return end
        if self.settings:isTrue("kobo_eski_sorma") then return end
        eski_soruldu = true
        local dialog
        dialog = ButtonDialog:new{
            title = _("Kobo Senkron artık 1000Kitap'ın içinde.\n\nEski Kobo Senkron eklentisi hâlâ açık. İkisi aynı işi yapmasın diye şimdilik Kobo işlerini o yapıyor. Eskisini kapatayım mı?"),
            title_align = "left",
            buttons = {
                {{ text = _("Eski eklentiyi kapat"), callback = function()
                    UIManager:close(dialog)
                    self:eskiKoboyuKapat()
                end }},
                {
                    { text = _("Bir daha sorma"), callback = function()
                        UIManager:close(dialog)
                        self.settings:makeTrue("kobo_eski_sorma")
                        self.settings:flush()
                    end },
                    { text = _("Sonra"), callback = function() UIManager:close(dialog) end },
                },
            },
        }
        UIManager:show(dialog)
    end

    --- 1000Kitap menüsündeki "Kobo Senkron" alt menüsü
    function BinKitap:koboMenusu()
        local eski = self:eskiKoboEklentisi()
        local ogeler = {}
        if eski then
            ogeler[#ogeler + 1] = {
                text = _("Eski Kobo Senkron eklentisini kapat"),
                help_text = _("Eski eklenti açık olduğu sürece Kobo işlerini o yapar. Kapatınca (KOReader yeniden başlayınca) aynısını 1000Kitap yapar."),
                callback = function() self:eskiKoboyuKapat() end,
                separator = true,
            }
        end
        local k = eski or self.kobo
        if k and k.getMenuItems then
            local ok, liste = pcall(k.getMenuItems, k)
            if ok and type(liste) == "table" then
                for _i, o in ipairs(liste) do ogeler[#ogeler + 1] = o end
            else
                logger.warn("1000Kitap: Kobo menüsü kurulamadı", liste)
            end
        end
        return ogeler
    end
end
