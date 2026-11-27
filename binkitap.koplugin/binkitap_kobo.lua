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
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local function kirp(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local eklenti_dizini = (debug.getinfo(1, "S").source or ""):match("^@(.+)/[^/]+$") or "."
local function yukle(ad)
    local ok, m = pcall(require, ad)
    if ok then return m end
    return dofile(eklenti_dizini .. "/" .. ad .. ".lua")
end

local Kobo = yukle("binkitap_kobo_senkron")
local KoboDB = yukle("binkitap_kobo_db")
local KUtil = yukle("binkitap_kobo_util")

local ESKI_AD = "kobosync"            -- eski eklentinin klasör adı (kobosync.koplugin)
local eski_soruldu = false            -- bu KOReader oturumunda soruldu mu

return function(BinKitap)
    local Api = BinKitap.Api
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

    ---------------------------------------------------------------------------
    -- Kobo'dan gelen vurguları 1000Kitap'a tek tuşla gönderme
    ---------------------------------------------------------------------------

    --- Kobo'dan gelmiş ve henüz gönderilmemiş vurgular. recs verilirse işaretsiz
    --- eski aktarımlar da tarihlerinden tanınır (işaret eklenir).
    function BinKitap:koboGonderilmemis(annotations, gonderilen, recs)
        if recs then pcall(Kobo.kimlikleriTamamla, annotations, recs) end
        local t = {}
        for _i, a in ipairs(type(annotations) == "table" and annotations or {}) do
            if a.kobo_id and a.drawer and kirp(a.text) ~= "" and not gonderilen[self:vurguAnahtari(a)] then
                t[#t + 1] = a
            end
        end
        return t
    end

    --- Herkese açık mı gizli mi: tek soru, varsayılan "alıntılar gizli" ayarına göre önde.
    function BinKitap:koboGonderSor(baslik, gonder, ek_dugmeler)
        local dialog
        local acik = { text = _("Herkese açık gönder"), callback = function() UIManager:close(dialog); gonder(false) end }
        local gizli = { text = _("Gizli gönder"), callback = function() UIManager:close(dialog); gonder(true) end }
        local dugmeler = { self.settings:isTrue("alinti_gizli") and { gizli, acik } or { acik, gizli } }
        for _i, d in ipairs(ek_dugmeler or {}) do
            local cb = d.callback
            dugmeler[#dugmeler + 1] = {{ text = d.text, callback = function() UIManager:close(dialog); cb() end }}
        end
        dugmeler[#dugmeler + 1] = {{ text = _("Vazgeç"), callback = function() UIManager:close(dialog) end }}
        dialog = ButtonDialog:new{
            title = baslik .. "\n\n" .. _("Herkese açık alıntılar profilinde ve akışta görünür; gizlileri yalnızca sen görürsün."),
            title_align = "left",
            buttons = dugmeler,
        }
        UIManager:show(dialog)
    end

    --- Okurken: bu kitabın Kobo vurguları. Dosya tarayıcısında: bütün kitaplarınki.
    function BinKitap:koboVurgulariniGonder()
        if not (self.ui.document and self.ui.doc_settings) then return self:koboTumunuGonder() end
        local kitap = self:kitapBilgisi()
        if not kitap then
            return self:kitapEslestir(function() self:koboVurgulariniGonder() end)
        end
        local liste = self.ui.annotation and self.ui.annotation.annotations
        if type(liste) ~= "table" then
            return self:hataGoster(_("Bu özellik KOReader 2024.07 veya daha yeni bir sürüm gerektirir."))
        end
        local recs
        if self.kobo and KoboDB.exists(self.kobo:dbPath()) then
            local db = KoboDB.read(self.kobo:dbPath(), { file = self:acikDosya(), bookmarks = true })
            recs = db and db.annotations[self:acikDosya()]
        end
        local gonderilen = self.ui.doc_settings:readSetting("binkitap_gonderilen") or {}
        local bekleyen = self:koboGonderilmemis(liste, gonderilen, recs)
        if #bekleyen == 0 then
            return self:bildir(_("Bu kitapta 1000Kitap'a gönderilmemiş Kobo vurgusu yok."), 3)
        end
        self:koboGonderSor(T(_("“%1” kitabında Kobo'dan gelen %2 vurgu 1000Kitap'a gönderilsin mi?"), kitap.adi, #bekleyen),
            function(ozel)
                local n = self:vurgulariSirala(kitap, bekleyen, ozel)
                if n <= BinKitap.TOPLU_ESIK then self:bildir(T(_("%1 vurgu sıraya alındı."), n), 2) end
            end)
    end

    --- Dosya tarayıcısından: Kobo'dan vurgu gelen bütün kitaplar.
    function BinKitap:koboTumunuGonder()
        if not self.kobo or not KoboDB.exists(self.kobo:dbPath()) then
            return self:bildir(_("Kobo veritabanı bulunamadı."), 3)
        end
        local db = KoboDB.read(self.kobo:dbPath(), { bookmarks = true })
        if not db then return self:bildir(_("Kobo veritabanı okunamadı."), 3) end
        local DocSettings = require("docsettings")
        local hazir, dogrulanmamis, eslesmemis, toplam = {}, {}, 0, 0
        local hayaletler = {} -- hayalet modundaki kitaplar: "hepsini gönder"e girmez, elle seçilebilir
        for dosya, recs in pairs(db.annotations) do
            local ok_ds, ds = pcall(function()
                return DocSettings:hasSidecarFile(dosya) and DocSettings:open(dosya) or nil
            end)
            if ok_ds and ds then
                local ann = ds:readSetting("annotations")
                local gonderilen = ds:readSetting("binkitap_gonderilen") or {}
                local yeni = self:koboGonderilmemis(ann, gonderilen, recs)
                if #yeni > 0 then
                    local k = ds:readSetting("binkitap")
                    if type(k) ~= "table" or not k.id then k = self:dosyaEslesmesi(dosya) end
                    if type(k) ~= "table" or not k.id then
                        eslesmemis = eslesmemis + 1
                    else
                        table.sort(yeni, function(x, y) return tostring(x.datetime or "") < tostring(y.datetime or "") end)
                        local e = { yol = dosya, kitap = k, vurgular = yeni, sayfa_sayisi = tonumber(ds:readSetting("doc_pages")) }
                        if k.otomatik then
                            dogrulanmamis[#dogrulanmamis + 1] = e
                        elseif self:hayaletKitap(k.id) then
                            hayaletler[#hayaletler + 1] = e
                        else
                            hazir[#hazir + 1] = e
                            toplam = toplam + #yeni
                        end
                    end
                end
            end
        end
        table.sort(hazir, function(x, y) return tostring(x.kitap.adi) < tostring(y.kitap.adi) end)
        local karsilastir = { text = _("1000Kitap'ta olmayanları bul"), callback = function() self:koboKarsilastir() end }
        if #hazir == 0 and #dogrulanmamis == 0 and #hayaletler == 0 then
            local metin = eslesmemis > 0
                and T(_("Kobo'dan gelen gönderilmemiş vurgular %1 kitapta, ama bu kitaplar 1000Kitap'ta eşleşmemiş. Önce Kütüphaneyi eşleştir'i çalıştır."), eslesmemis)
                or _("1000Kitap'a gönderilmemiş Kobo vurgusu yok.")
            local dialog
            dialog = ButtonDialog:new{
                title = metin .. "\n\n" .. _("Gönderildi görünen ama 1000Kitap'ta olmayan (ör. günlük sınıra takılıp reddedilen) vurguları bulmak için alıntılarınla karşılaştırabilirsin."),
                title_align = "left",
                buttons = {
                    {{ text = karsilastir.text, callback = function() UIManager:close(dialog); karsilastir.callback() end }},
                    {{ text = _("Kapat"), callback = function() UIManager:close(dialog) end }},
                },
            }
            return UIManager:show(dialog)
        end

        local function kitapKitapSec()
            local ogeler = {}
            for _i, e in ipairs(hazir) do
                ogeler[#ogeler + 1] = { metin = e.kitap.adi, ek = T(_("%1 vurgu"), #e.vurgular), secili = true, veri = e }
            end
            for _i, e in ipairs(hayaletler) do
                ogeler[#ogeler + 1] = { metin = e.kitap.adi, ek = T(_("%1 vurgu · hayalet modu"), #e.vurgular), secili = false, veri = e }
            end
            for _i, e in ipairs(dogrulanmamis) do
                ogeler[#ogeler + 1] = { metin = e.kitap.adi, ek = T(_("%1 vurgu · eşleşme doğrulanmadı"), #e.vurgular), secili = false, veri = e }
            end
            self:secimListesi{
                baslik = _("Kobo vurguları — kitaplar"),
                bilgi = _("Seçtiğin kitapların Kobo'dan gelen vurguları 1000Kitap'a gönderilir. Eşleşmesi doğrulanmamış kitaplar seçili gelmez: yanlış kitaba gitmesin."),
                ogeler = ogeler,
                onay_metni = _("Seçilenlerin vurgularını gönder (%1)"),
                onay = function(secilen)
                    local n = 0
                    for _i, e in ipairs(secilen) do n = n + #e.vurgular end
                    self:koboGonderSor(T(_("%1 kitaptan %2 Kobo vurgusu gönderilsin mi?"), #secilen, n),
                        function(ozel) self:aktarilanVurgulariSirala(secilen, ozel) end)
                end,
            }
        end

        if #hazir == 0 then return kitapKitapSec() end
        local baslik = T(_("Kobo'dan gelen ve henüz gönderilmemiş %1 vurgu var (%2 kitap). Hepsi 1000Kitap'a gönderilsin mi?"), toplam, #hazir)
        if #dogrulanmamis > 0 then
            baslik = baslik .. "\n" .. T(_("%1 kitabın eşleşmesi doğrulanmadığı için dahil değil; Kitap kitap seç'ten ekleyebilirsin."), #dogrulanmamis)
        end
        if eslesmemis > 0 then
            baslik = baslik .. "\n" .. T(_("%1 kitap 1000Kitap'ta eşleşmediği için atlanacak."), eslesmemis)
        end
        self:koboGonderSor(baslik, function(ozel) self:aktarilanVurgulariSirala(hazir, ozel) end,
            {{ text = _("Kitap kitap seç"), callback = kitapKitapSec }, karsilastir})
    end

    ---------------------------------------------------------------------------
    -- "Gönderildi" işaretli Kobo vurgularını 1000Kitap'taki alıntılarla karşılaştır
    --
    -- 1.3.3'ten önce 1000Kitap'ın reddettiği alıntılar (ör. "1 günde en fazla 500
    -- alıntı") sıradan silinirdi ama vurgu "gönderildi" işaretli kalırdı. Burada
    -- profilindeki bütün alıntılar bir kez okunur (yalnızca okuma; 1000Kitap kitaba
    -- göre süzmeyi her zaman yapamıyor, bu yüzden süzgece güvenilmez), metni
    -- hiçbirinde olmayan vurgunun işareti onayla kaldırılır: tekrar gönderilebilir olur.
    -- Okuma yarıda kalırsa hiçbir şey değişmez (eksik listeyle çift gönderim olmasın).
    ---------------------------------------------------------------------------

    --- Karşılaştırma için sade metin: boşluk, noktalama (tırnaklar dahil) ve
    --- büyük/küçük harf farkları yok sayılır. İki taraf da aynı biçimde sadeleşir.
    local NOKTALAMA = { "“", "”", "„", "‘", "’", "«", "»", "‹", "›", "—", "–", "…", "‐", "‑", "·" }
    local BUYUK = { { "İ", "i" }, { "Ş", "ş" }, { "Ğ", "ğ" }, { "Ü", "ü" }, { "Ö", "ö" }, { "Ç", "ç" }, { "Â", "â" }, { "Î", "î" }, { "Û", "û" } }
    local function normal(s)
        local ok, n = pcall(KUtil.normalize, s or "")
        if not ok then return "" end
        for _i, c in ipairs(NOKTALAMA) do n = n:gsub(c, " ") end
        for _i, c in ipairs(BUYUK) do n = n:gsub(c[1], c[2]) end
        n = n:gsub("%p", " "):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        return n
    end

    BinKitap.KARSILASTIR_EN_FAZLA_SAYFA = 1500

    --- Sitedeki alıntılar: önce baştan 30 harf (hızlı), olmazsa içinde arama
    --- (site uzun alıntıları kısaltabilir, baştaki tırnak vb. farklı olabilir).
    local function siteDizini(metinler)
        local bas = {}
        for _i, b in ipairs(metinler) do bas[b:sub(1, 30)] = true end
        return { liste = metinler, bas = bas }
    end

    local function sitedeVar(yerel, dizin)
        local a = normal(yerel)
        if a == "" then return true end
        if dizin.bas[a:sub(1, 30)] then return true end
        local parca = a:sub(1, 40)
        for _i, b in ipairs(dizin.liste) do
            if b:find(parca, 1, true) or (#b >= 20 and a:find(b:sub(1, 40), 1, true)) then return true end
        end
        return false
    end
    BinKitap._sitedeVar = function(yerel, metinler)
        local n = {}
        for _i, m in ipairs(metinler) do n[#n + 1] = normal(m) end
        return sitedeVar(yerel, siteDizini(n))
    end

    function BinKitap:koboKarsilastir()
        local kadi = self.kullanici_adi
        if not kadi or kadi == "" then
            return self:hataGoster(_("Bunun için Ayarlar'da 1000Kitap kullanıcı adını gir (profil adresindeki ad)."))
        end
        if not self.kobo or not KoboDB.exists(self.kobo:dbPath()) then
            return self:bildir(_("Kobo veritabanı bulunamadı."), 3)
        end
        local db = KoboDB.read(self.kobo:dbPath(), { bookmarks = true })
        if not db then return self:bildir(_("Kobo veritabanı okunamadı."), 3) end
        local DocSettings = require("docsettings")
        local kitaplar, toplam = {}, 0
        for dosya, recs in pairs(db.annotations) do
            local ok_ds, ds = pcall(function()
                return DocSettings:hasSidecarFile(dosya) and DocSettings:open(dosya) or nil
            end)
            if ok_ds and ds then
                local ann = ds:readSetting("annotations")
                local gonderilen = ds:readSetting("binkitap_gonderilen") or {}
                pcall(Kobo.kimlikleriTamamla, ann, recs)
                local k = ds:readSetting("binkitap")
                if type(k) ~= "table" or not k.id then k = self:dosyaEslesmesi(dosya) end
                if type(k) == "table" and k.id then
                    local adaylar = {}
                    for _i, a in ipairs(type(ann) == "table" and ann or {}) do
                        local isaret = a.kobo_id and a.drawer and gonderilen[self:vurguAnahtari(a)]
                        -- gizli gönderilenler alıntılarda görünmez: onlara dokunma
                        if isaret and isaret ~= "gizli" and kirp(a.text) ~= "" then adaylar[#adaylar + 1] = a end
                    end
                    if #adaylar > 0 then
                        kitaplar[#kitaplar + 1] = { yol = dosya, kitap = k, adaylar = adaylar }
                        toplam = toplam + #adaylar
                    end
                end
            end
        end
        if #kitaplar == 0 then
            return self:bildir(_("Gönderildi diye işaretli Kobo vurgusu yok."), 3)
        end
        table.sort(kitaplar, function(x, y) return tostring(x.kitap.adi) < tostring(y.kitap.adi) end)
        UIManager:show(ConfirmBox:new{
            text = T(_("%1 kitapta \"gönderildi\" işaretli %2 Kobo vurgusu, 1000Kitap'taki bütün alıntılarınla karşılaştırılacak (alıntıların çoksa birkaç dakika sürebilir). Sonunda orada olmayanların sayısını görürsün; onaylarsan yeniden gönderilebilir olurlar.\n\nYalnızca okur, hesabına bir şey yazmaz.\n\n1.3.3'ten önce gizli gönderdiğin vurgular alıntılarında görünmediği için onlar da sayıya girebilir."), #kitaplar, toplam),
            ok_text = _("Karşılaştır"),
            ok_callback = function()
                NetworkMgr:runWhenOnline(function() self:koboKarsilastirCalistir(kadi, kitaplar) end)
            end,
        })
    end

    function BinKitap:koboKarsilastirCalistir(kadi, kitaplar)
        local DocSettings = require("docsettings")
        local sayfa, metinler, iptal, kutu, okunan = nil, {}, false, nil, 0
        local function goster()
            if kutu then UIManager:close(kutu) end
            kutu = InfoMessage:new{
                text = T(_("1000Kitap'taki alıntıların okunuyor…\n\n%1 sayfa · %2 alıntı\n\nBitince karşılaştırılacak; o zamana kadar hiçbir şey değişmez. Durdurmak için dokun."),
                    okunan, #metinler),
                dismiss_callback = function() iptal = true; kutu = nil end,
            }
            UIManager:show(kutu)
        end
        local function isaretle()
            local n = 0
            for _j, e in ipairs(kitaplar) do
                if e.eksik and #e.eksik > 0 then
                    local ds = DocSettings:open(e.yol)
                    local gonderilen = ds:readSetting("binkitap_gonderilen") or {}
                    for _k, anahtar in ipairs(e.eksik) do
                        if gonderilen[anahtar] then gonderilen[anahtar] = nil; n = n + 1 end
                    end
                    ds:saveSetting("binkitap_gonderilen", gonderilen)
                    pcall(function() ds:flush() end)
                end
            end
            return n
        end
        local function sonuc()
            if kutu then UIManager:close(kutu); kutu = nil end
            local dizin = siteDizini(metinler)
            local eksik, kitap_sayisi = 0, 0
            for _j, e in ipairs(kitaplar) do
                e.eksik = {}
                for _k, v in ipairs(e.adaylar) do
                    if not sitedeVar(v.text, dizin) then e.eksik[#e.eksik + 1] = self:vurguAnahtari(v) end
                end
                if #e.eksik > 0 then eksik = eksik + #e.eksik; kitap_sayisi = kitap_sayisi + 1 end
            end
            if eksik == 0 then
                return self:bildir(T(_("1000Kitap'taki %1 alıntınla karşılaştırıldı: gönderildi görünen bütün Kobo vurguları orada var."), #metinler), 5)
            end
            local sinir = self:sinirMetni()
            local dialog
            dialog = ButtonDialog:new{
                title = T(_("1000Kitap'taki %1 alıntınla karşılaştırıldı: %2 Kobo vurgusu orada yok (%3 kitap)."), #metinler, eksik, kitap_sayisi)
                    .. "\n\n" .. _("Yeniden gönderilebilir olarak işaretlensin mi? Sayı beklediğinden çok fazlaysa Vazgeç: hiçbir şey değişmez.")
                    .. (sinir and ("\n\n" .. sinir) or ""),
                title_align = "left",
                buttons = {
                    {{ text = _("İşaretle ve gönder"), callback = function()
                        UIManager:close(dialog)
                        isaretle()
                        self:koboTumunuGonder()
                    end }},
                    {{ text = _("Yalnızca işaretle"), callback = function()
                        UIManager:close(dialog)
                        local n = isaretle()
                        self:bildir(T(_("%1 vurgu yeniden gönderilebilir olarak işaretlendi."), n), 4)
                    end }},
                    {{ text = _("Vazgeç"), callback = function() UIManager:close(dialog) end }},
                },
            }
            UIManager:show(dialog)
        end
        local function vazgec(neden)
            if kutu then UIManager:close(kutu); kutu = nil end
            self:hataGoster(neden .. "\n\n" .. _("Karşılaştırma yapılmadı, hiçbir şey değişmedi."))
        end
        local adim
        adim = function()
            if iptal then return vazgec(_("Durduruldu.")) end
            local liste, sonraki = Api:okurAlintilari(kadi, sayfa)
            if not liste then
                return vazgec(T(_("1000Kitap'a ulaşılamadı: %1"), tostring(sonraki or "?")))
            end
            okunan = okunan + 1
            for _j, o in ipairs(liste) do metinler[#metinler + 1] = normal(o.soz) end
            sayfa = sonraki
            if not sayfa then return sonuc() end
            if okunan >= BinKitap.KARSILASTIR_EN_FAZLA_SAYFA then
                return vazgec(T(_("Alıntıların %1 sayfadan fazla; hepsi okunamadı."), okunan))
            end
            if okunan % 5 == 0 then goster() end
            UIManager:scheduleIn(0.3, adim)
        end
        goster()
        UIManager:scheduleIn(0.3, adim)
    end

    --- Arka planda Kobo aktarımı sürüyor mu (eski eklenti açıksa hayır)
    function BinKitap:koboArkaSuruyor()
        return not self:eskiKoboEklentisi() and Kobo.arkaCalisiyor()
    end

    function BinKitap:koboArkaDurumu()
        if self.kobo then self.kobo:arkaDurumGoster() end
    end

    --- 1000Kitap menüsündeki "Kobo Senkron" alt menüsü
    function BinKitap:koboMenusu()
        local eski = self:eskiKoboEklentisi()
        local ogeler = {}
        if self:koboArkaSuruyor() then
            ogeler[#ogeler + 1] = {
                text_func = function()
                    return Kobo.arkaCalisiyor() and T(_("Kobo aktarımı sürüyor · %1"), Kobo.arkaYuzde()) or _("Kobo aktarımı bitti")
                end,
                help_text = _("Kobo notları arka planda kitap kitap aktarılıyor. Dokununca ayrıntıyı görür, istersen durdurursun."),
                keep_menu_open = true,
                callback = function() self:koboArkaDurumu() end,
                separator = true,
            }
        end
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
        -- tek tuşla gönderim: "Şimdi senkronize et"in hemen altında
        local once = (eski and 1 or 0) + (self:koboArkaSuruyor() and 1 or 0)
        table.insert(ogeler, math.min(#ogeler + 1, once + 2), {
            text = self.ui.document and _("Bu kitabın Kobo vurgularını 1000Kitap'a gönder") or _("Kobo vurgularını 1000Kitap'a gönder"),
            help_text = _("Kobo'dan aktarılan ve henüz gönderilmemiş vurguları tek seferde 1000Kitap'a alıntı olarak gönderir. Herkese açık mı gizli mi diye bir kez sorar."),
            callback = function() self:koboVurgulariniGonder() end,
        })
        if not self.ui.document then
            table.insert(ogeler, math.min(#ogeler + 1, once + 3), {
                text = _("Gönderilenleri 1000Kitap'la karşılaştır"),
                help_text = _("Gönderildi diye işaretli Kobo vurgularını 1000Kitap'taki alıntılarınla karşılaştırır; orada olmayanları (ör. günlük sınıra takılıp reddedilenleri) yeniden gönderilebilir yapar. Yalnızca okur."),
                callback = function() self:koboKarsilastir() end,
            })
        end
        return ogeler
    end
end
