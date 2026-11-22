--[[
1000Kitap eklentisi: yinelenen alıntıları temizleme.

Profildeki bütün alıntılar okunur (okurCekV2; 1000Kitap kitaba göre süzmeyi her
zaman yapamadığı için süzgeç kullanılmaz). Aynı kitapta metni aynı olan alıntılar
(boşluk, noktalama, tırnak ve büyük/küçük harf farkı gözetilmeden) bir grup olur;
her grubun ilk gönderileni kalır, sonrakiler kullanıcı onaylarsa silinir
(v2/alintilar/alintiKaldir?id=, sitenin kendi silme çağrısı).

Güvenlik:
- Okuma yarıda kalırsa (bağlantı, 1000Kitap'ın "çok fazla istek" yanıtı, Durdur)
  hiçbir şey silinmez.
- Hangisinin önce gönderildiği belirlenemeyen gruplara dokunulmaz.
- Tek kopyası olan alıntıya dokunulmaz; kitabı bilinmeyen alıntı gruplanmaz.
- İlk silmeden sonra liste yeniden okunur: silinen gitmiş, kalan duruyor olmalı;
  değilse başka hiçbir şey silinmez.
- Okuma ve silme yavaş yapılır; herhangi bir hatada durur.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local NOKTALAMA = { "“", "”", "„", "‘", "’", "«", "»", "‹", "›", "—", "–", "…", "‐", "‑", "·" }
local BUYUK = { { "İ", "i" }, { "Ş", "ş" }, { "Ğ", "ğ" }, { "Ü", "ü" }, { "Ö", "ö" }, { "Ç", "ç" }, { "Â", "â" }, { "Î", "î" }, { "Û", "û" } }

--- Karşılaştırma için sade metin.
local function sade(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("\194\160", " ")
    for _i, c in ipairs(NOKTALAMA) do s = s:gsub(c, " ") end
    for _i, c in ipairs(BUYUK) do s = s:gsub(c[1], c[2]) end
    s = s:gsub("%p", " "):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return s
end

local function kisalt(s, n)
    s = tostring(s or ""):gsub("%s+", " ")
    if #s <= n then return s end
    local k = s:sub(1, n)
    -- UTF-8 harfi ortadan bölme
    while #k > 0 and k:byte(#k) >= 0x80 and k:byte(#k) < 0xC0 do k = k:sub(1, -2) end
    if #k > 0 and k:byte(#k) >= 0xC0 then k = k:sub(1, -2) end
    return k .. "…"
end

return function(BinKitap)
    local Api = BinKitap.Api

    BinKitap.YINELEME = {
        okuma_araligi = 1.5,   -- sn, sayfalar arası
        silme_araligi = 4,     -- sn, silmeler arası
        en_fazla_sayfa = 1500,
    }
    BinKitap.sadeMetin = sade

    --- Okunan alıntılardan silinecekleri çıkarır.
    --- Dönüş: gruplar { {kalan=, silinecek={...}, kitap_id=, soz=} }, atlanan grup sayısı
    function BinKitap.yinelenenleriBul(alintilar)
        local gruplar, sira = {}, {}
        for _i, a in ipairs(alintilar) do
            local metin = sade(a.soz)
            if a.kitap_id ~= "" and metin ~= "" then
                local anahtar = a.kitap_id .. "\n" .. metin
                if not gruplar[anahtar] then
                    gruplar[anahtar] = {}
                    sira[#sira + 1] = anahtar
                end
                table.insert(gruplar[anahtar], a)
            end
        end
        local sonuc, atlanan = {}, 0
        for _i, anahtar in ipairs(sira) do
            local g = gruplar[anahtar]
            if #g > 1 then
                -- hangisi önce gönderildi: kimlikler zamanla artar; yoksa zaman
                local hepsi_sayi, hepsi_zaman = true, true
                for _j, a in ipairs(g) do
                    if not tonumber(a.id) then hepsi_sayi = false end
                    if not a.zaman then hepsi_zaman = false end
                end
                local karar = true
                if hepsi_sayi then
                    table.sort(g, function(x, y) return tonumber(x.id) < tonumber(y.id) end)
                elseif hepsi_zaman then
                    table.sort(g, function(x, y) return x.zaman < y.zaman end)
                    if g[1].zaman == g[2].zaman then karar = false end
                else
                    karar = false
                end
                for _j = 2, #g do
                    if not g[_j].id or g[_j].id == "" then karar = false end
                end
                if karar then
                    local sil = {}
                    for j = 2, #g do sil[#sil + 1] = g[j] end
                    sonuc[#sonuc + 1] = { kalan = g[1], silinecek = sil, kitap_id = g[1].kitap_id, soz = g[1].soz }
                else
                    atlanan = atlanan + 1
                end
            end
        end
        return sonuc, atlanan
    end

    function BinKitap:yinelenenAlintilar()
        if not Api:kimlikVar() then return self:kimlikUyarisi() end
        local kadi = self.kullanici_adi
        if not kadi or kadi == "" then
            return self:hataGoster(_("Bunun için Ayarlar'da 1000Kitap kullanıcı adını gir (profil adresindeki ad)."))
        end
        UIManager:show(ConfirmBox:new{
            text = _("Yinelenen alıntıları temizle\n\nProfilindeki bütün alıntılar okunur (çoksa birkaç dakika sürer). Aynı kitapta aynı metne sahip alıntılardan ilk gönderilen kalır, sonrakiler silinmek üzere listelenir.\n\nOkuma bitince kaç tane olduğunu görürsün; sormadan hiçbir şey silinmez."),
            ok_text = _("Oku"),
            ok_callback = function()
                NetworkMgr:runWhenOnline(function() self:yinelenenleriOku(kadi) end)
            end,
        })
    end

    --- Profildeki alıntıları sayfa sayfa okur; bitince (liste) ya da (nil, hata) ile döner.
    function BinKitap:alintilariOku(kadi, bitti, baslik)
        local Y = BinKitap.YINELEME
        local sayfa, alintilar, okunan, iptal, kutu = nil, {}, 0, false, nil
        local function goster()
            if kutu then UIManager:close(kutu) end
            kutu = InfoMessage:new{
                text = T(_("%1\n\n%2 sayfa · %3 alıntı\n\nDurdurmak için dokun; hiçbir şey silinmez."), baslik, okunan, #alintilar),
                dismiss_callback = function() iptal = true; kutu = nil end,
            }
            UIManager:show(kutu)
        end
        local function kapat()
            if kutu then UIManager:close(kutu); kutu = nil end
        end
        local adim
        adim = function()
            if iptal then kapat(); return bitti(nil, _("Durduruldu.")) end
            local liste, sonraki, tur = Api:okurAlintilari(kadi, sayfa)
            if not liste then
                kapat()
                return bitti(nil, tostring(sonraki or "?"), tur)
            end
            okunan = okunan + 1
            for _i, a in ipairs(liste) do
                a.sayfa = okunan
                alintilar[#alintilar + 1] = a
            end
            sayfa = sonraki
            if not sayfa then kapat(); return bitti(alintilar) end
            if okunan >= Y.en_fazla_sayfa then
                kapat()
                return bitti(nil, T(_("Alıntıların %1 sayfadan fazla; hepsi okunamadı."), okunan))
            end
            if okunan % 5 == 0 then goster() end
            UIManager:scheduleIn(Y.okuma_araligi, adim)
        end
        goster()
        UIManager:scheduleIn(0.3, adim)
    end

    function BinKitap:yinelenenleriOku(kadi)
        self:alintilariOku(kadi, function(alintilar, hata)
            if not alintilar then
                return self:hataGoster(T(_("Alıntılar okunamadı: %1\n\nHiçbir şey silinmedi. 1000Kitap yoğunsa bir süre sonra tekrar dene."), hata))
            end
            local gruplar, atlanan = BinKitap.yinelenenleriBul(alintilar)
            local silinecek, kitaplar = 0, {}
            for _i, g in ipairs(gruplar) do
                silinecek = silinecek + #g.silinecek
                kitaplar[g.kitap_id] = true
            end
            local kitap_sayisi = 0
            for _k in pairs(kitaplar) do kitap_sayisi = kitap_sayisi + 1 end
            local atlanan_metni = atlanan > 0
                and ("\n\n" .. T(_("%1 grupta hangisinin önce gönderildiği anlaşılamadı; onlara dokunulmayacak."), atlanan)) or ""
            if silinecek == 0 then
                return self:bildir(T(_("Profilindeki %1 alıntı okundu: yinelenen alıntı yok."), #alintilar) .. atlanan_metni, 5)
            end
            local dialog
            dialog = ButtonDialog:new{
                title = T(_("Profilindeki %1 alıntı okundu. %2 kitapta %3 yinelenen alıntı var: her birinin ilk gönderileni kalacak, sonrakiler silinecek.\n\nSilmek geri alınamaz. Yavaş silinir; 1000Kitap yoğunsa yarıda kalabilir, kalanlar silinmez."),
                    #alintilar, kitap_sayisi, silinecek) .. atlanan_metni,
                title_align = "left",
                buttons = {
                    {{ text = _("Listeyi gör"), callback = function() self:yinelenenListesi(gruplar) end }},
                    {{ text = T(_("Sil (%1)"), silinecek), callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenOnline(function() self:yinelenenleriSil(kadi, gruplar) end)
                    end }},
                    {{ text = _("Vazgeç"), callback = function() UIManager:close(dialog) end }},
                },
            }
            UIManager:show(dialog)
        end, _("1000Kitap'taki alıntıların okunuyor…"))
    end

    function BinKitap:yinelenenListesi(gruplar)
        local satirlar = {}
        for _i, g in ipairs(gruplar) do
            satirlar[#satirlar + 1] = T(_("“%1” — %2 kopya, %3 silinecek"), kisalt(g.soz, 120), #g.silinecek + 1, #g.silinecek)
        end
        UIManager:show(TextViewer:new{
            title = _("Yinelenen alıntılar"),
            text = table.concat(satirlar, "\n\n"),
        })
    end

    function BinKitap:yinelenenleriSil(kadi, gruplar)
        local Y = BinKitap.YINELEME
        local is = {}
        for _i, g in ipairs(gruplar) do
            for _j, a in ipairs(g.silinecek) do is[#is + 1] = { alinti = a, kalan = g.kalan } end
        end
        local i, silinen, olmayan, iptal, kutu = 1, 0, 0, false, nil
        local function goster()
            if kutu then UIManager:close(kutu) end
            kutu = InfoMessage:new{
                text = T(_("Yinelenen alıntılar siliniyor… %1\n\n%2 / %3\n\nDurdurmak için dokun; kalanlar silinmez."),
                    BinKitap.yuzde(i - 1, #is), i - 1, #is),
                dismiss_callback = function() iptal = true; kutu = nil end,
            }
            UIManager:show(kutu)
        end
        local function bitir(neden)
            if kutu then UIManager:close(kutu); kutu = nil end
            local satirlar = { T(_("%1 yinelenen alıntı silindi."), silinen) }
            if olmayan > 0 then satirlar[#satirlar + 1] = T(_("%1 tanesi zaten yoktu."), olmayan) end
            local kalan = #is - (i - 1)
            if kalan > 0 then satirlar[#satirlar + 1] = T(_("%1 tanesi silinmedi."), kalan) end
            if neden then satirlar[#satirlar + 1] = neden end
            logger.info("1000Kitap: yinelenen alıntılar:", silinen, "silindi,", kalan, "kaldı")
            if neden then self:hataGoster(table.concat(satirlar, "\n")) else self:bildir(table.concat(satirlar, "\n"), 5) end
        end

        local sil
        --- İlk silmeden sonra: silinen gitti mi, kalan duruyor mu? (liste baştan okunur)
        local function dogrula(oge)
            local gerek = math.max(oge.alinti.sayfa or 1, oge.kalan.sayfa or 1) + 1
            local sayfa, okunan, gorulen = nil, 0, {}
            local adim
            adim = function()
                local liste, sonraki = Api:okurAlintilari(kadi, sayfa)
                if not liste then
                    return bitir(T(_("İlk silme doğrulanamadı (%1); başka hiçbir şey silinmedi."), tostring(sonraki or "?")))
                end
                okunan = okunan + 1
                for _j, a in ipairs(liste) do gorulen[a.id] = true end
                sayfa = sonraki
                if sayfa and okunan < gerek then return UIManager:scheduleIn(Y.okuma_araligi, adim) end
                if gorulen[oge.alinti.id] or not gorulen[oge.kalan.id] then
                    logger.warn("1000Kitap: yinelenen silme doğrulanamadı", oge.alinti.id, oge.kalan.id)
                    return bitir(_("Silme beklendiği gibi çalışmadı; güvenlik için durdum, başka hiçbir şey silinmedi."))
                end
                goster()
                UIManager:scheduleIn(Y.silme_araligi, sil)
            end
            UIManager:scheduleIn(Y.okuma_araligi, adim)
        end

        sil = function()
            if iptal then return bitir(_("Durduruldu.")) end
            local oge = is[i]
            if not oge then return bitir() end
            local sonuc, err, tur = Api:alintiKaldir(oge.alinti.id)
            if not sonuc then
                if tur == "sunucu" then
                    -- bu alıntı silinemedi (ör. zaten yok): geç
                    olmayan = olmayan + 1
                else
                    return bitir(T(_("1000Kitap'a ulaşılamadı: %1"), tostring(err or "?")))
                end
            else
                silinen = silinen + 1
            end
            i = i + 1
            if silinen == 1 and sonuc then return dogrula(oge) end
            if i > #is then return bitir() end
            if (i - 1) % 5 == 0 then goster() end
            UIManager:scheduleIn(Y.silme_araligi, sil)
        end
        goster()
        UIManager:scheduleIn(0.5, sil)
    end
end
