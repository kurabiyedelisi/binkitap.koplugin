--[[
1000Kitap için küçük HTTP istemcisi (resmi değildir).

1000Kitap'ın herkese açık, belgelenmiş bir API'si yok. Buradaki uç noktalar
1000kitap.com web uygulamasının kullandığı iç API'den alındı (Kasım 2026).

Okuma
  GET  v2/diger/arama?q=                                  kitap arama (ISBN de olur)
  GET  v2/kitaplar/kitapCek?id=                           kitap ayrıntısı
  GET  v2/kitaplar/kitapCek?id=&bolum=alintilar&s=populer popüler alıntılar
  GET  v2/kitaplar/basimlar?kitapId=&sayfa=&kume=&z=      baskılar
  GET  v2/uye/kitap/modalVeBasimlar?kitapId=              senin bu kitaptaki durumun
  GET  v2/uyeler/kitaplar/liste?kadi=&raf=okuyacaklari    okuyacaklar listesi (kitaplık: raf=kutuphanesi)
  GET  v2/okurlar/okurCekV2?id=&bolum=alintilar           bir okurun alıntıları
  GET  v2/okuma-hedefleri/sene-detay?sene=                okuma hedefi
  GET  v2/konular/konuArama?q=                            konu arama
  GET  analiz…/v2/kitaplar/tanidikOkurlar?id=             takip ettiklerinden okuyanlar
Yazma
  GET  v2/kitaplar/kitapOku?id=&durum=                    okuma durumu
  GET  v2/kitaplar/kitapPuanVer?id=&puan=                 puan
  GET  v2/kitaplar/kitapOku?id=&durum=1&forceEkle=1&okuyorTarihsaat=&okuduTarihsaat=&isTopluIslem=1
                                                         tarihli okuma (sitedeki "Toplu okuma ekle")
  GET  v2/kitaplar/kitapCek?id=&bolum=incelemeler&s=populer popüler incelemeler
  GET  v2/kitaplar/kesifListe?siralama=sizeOzel&okuma=haric | donem=son7Gun | ilkYayinYili=son6Ay
       | siralama=yeni|okunan|enIyi  &sayfa=&kume=&z=     Kitaplar sekmesindeki listeler
  GET  v2/kitaplar/kitapSayfaGuncelle?id=&okumaId=&sayfa=&sayfa2=   ilerleme
  GET  v2/kitaplar/kitapKutuphanemeEkle?id=&forceEkle=1   kitaplığa ekle (forceEkle=0: ekle/çıkar)
  POST v2/alintilar/alintiEkle                            alıntı
  POST v2/koleksiyonlar/not-ayarla                        özel not
  POST v2/kitaplar/kitapIncelemeKaydet?kitapId=&id=       inceleme
  POST v2/uyeler/okumalar/gunluk/seansTamamla             okuma seansı
  POST v2/diger/okumaHedefiKaydet                         okuma hedefi

Kimlik doğrulama: "Api-V2: 1" ile birlikte
  1-OTURUM-KODU = "oturumkodube" çerezi,  1-CIHAZ-KODU = "cik-v2be" çerezi
]]

local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local http = require("socket.http")
local ok_https, https = pcall(require, "ssl.https")

local ok_json, json = pcall(require, "json")
if not ok_json then
    json = require("rapidjson")
end

math.randomseed(os.time())

local Api = {
    base_url = "https://api.1000kitap.com/v2/",
    analiz_url = "https://analiz.1000kitap.com/v2/",
    app_surumu = "2.61.92",
    oturum_kodu = nil,
    cihaz_kodu = nil,
}

Api.DURUM = { yok = -1, okuyacagim = 0, okudum = 1, okuyorum = 2, yarim = 3 }
Api.DURUM_ADI = {
    [-1] = "durum yok",
    [0] = "Okuyacağım",
    [1] = "Okudum",
    [2] = "Okuyorum",
    [3] = "Yarım bıraktım",
}

-- Alıntı ve incelemelerde "Kimler yorum yapıp alıntılayabilir?" (sitedeki kodlar)
Api.YORUM_AYARLARI = {
    { kod = 0, ad = "Bütün okurlar" },
    { kod = 3, ad = "Sadece takip ettiklerim" },
    { kod = 4, ad = "Takip ettiklerim ve sıkı takipçilerim" },
    { kod = 5, ad = "Sadece sıkı takipçilerim" },
    { kod = 6, ad = "Hiç kimse" },
}

local function urlencode(s)
    if s == nil then return "" end
    s = tostring(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end
Api._urlencode = urlencode

local function encodePairs(list)
    local parts = {}
    for _i, kv in ipairs(list or {}) do
        parts[#parts + 1] = urlencode(kv[1]) .. "=" .. urlencode(kv[2])
    end
    return table.concat(parts, "&")
end
Api._encodePairs = encodePairs

local function isNull(v)
    return v == nil or (json.null ~= nil and v == json.null)
end
Api._isNull = isNull

local function metin(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local RASTGELE_HARFLER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
function Api.rastgeleKod(uzunluk)
    local t = {}
    for i = 1, uzunluk do
        local n = math.random(1, #RASTGELE_HARFLER)
        t[i] = RASTGELE_HARFLER:sub(n, n)
    end
    return table.concat(t)
end

function Api:setKimlik(oturum_kodu, cihaz_kodu, app_surumu)
    self.oturum_kodu = oturum_kodu
    self.cihaz_kodu = cihaz_kodu
    if app_surumu and app_surumu ~= "" then
        self.app_surumu = app_surumu
    end
end

function Api:kimlikVar()
    return type(self.oturum_kodu) == "string" and self.oturum_kodu ~= ""
        and type(self.cihaz_kodu) == "string" and self.cihaz_kodu ~= ""
end

--- Tek bir istek gönderir.
-- Hata türleri: "ag" (geçici, tekrar denenir), "yetki" (oturum kodu geçersiz,
-- öğe sırada kalır), "sunucu" (istek reddedildi, tekrar denemenin anlamı yok).
-- @return data | nil, hata_mesaji, hata_turu
function Api:istek(method, yol, sorgu, form, kimlik_gerekli, taban)
    if kimlik_gerekli and not self:kimlikVar() then
        return nil, "1000Kitap hesap bilgileri girilmemiş.", "yetki"
    end

    local q = {}
    for _i, kv in ipairs(sorgu or {}) do q[#q + 1] = kv end
    q[#q + 1] = { "appVersion", self.app_surumu }
    q[#q + 1] = { "os", "web" }
    q[#q + 1] = { "hl", "tr" }
    local url = (taban or self.base_url) .. yol .. "?" .. encodePairs(q)

    local headers = {
        ["accept"] = "application/json, text/plain, */*",
        ["api-v2"] = "1",
        ["origin"] = "https://1000kitap.com",
        ["referer"] = "https://1000kitap.com/",
        ["user-agent"] = "Mozilla/5.0 (Linux; KOReader) 1000Kitap-KOReader/0.2",
    }
    if self:kimlikVar() then
        headers["1-oturum-kodu"] = self.oturum_kodu
        headers["1-cihaz-kodu"] = self.cihaz_kodu
    end

    local source
    if form then
        local body = encodePairs(form)
        headers["content-type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        headers["content-length"] = tostring(#body)
        source = ltn12.source.string(body)
    end

    local parcalar = {}
    local reqt = {
        url = url,
        method = method,
        headers = headers,
        source = source,
        sink = ltn12.sink.table(parcalar),
    }
    local requester = (ok_https and url:sub(1, 6) == "https:") and https or http

    socketutil:set_timeout(15, 45)
    local ok, code, resp_headers = pcall(function()
        return socket.skip(1, requester.request(reqt))
    end)
    socketutil:reset_timeout()

    if not ok or resp_headers == nil or type(code) ~= "number" then
        logger.warn("1000Kitap: ağ hatası", yol, code)
        return nil, "Bağlantı hatası: " .. tostring(code), "ag"
    end

    local govde = table.concat(parcalar)
    if code == 401 or code == 403 then
        logger.warn("1000Kitap: yetki hatası", yol, code)
        return nil, "1000Kitap isteği reddetti (HTTP " .. code .. "). Oturum kodu geçersiz olabilir.", "yetki"
    end
    if code == 429 or code >= 500 then
        return nil, "1000Kitap şu an yanıt vermiyor (HTTP " .. code .. ").", "ag"
    end
    if code ~= 200 then
        logger.warn("1000Kitap: HTTP", yol, code, govde:sub(1, 200))
        return nil, "Beklenmeyen yanıt (HTTP " .. code .. ").", "sunucu"
    end

    local ok_dec, data = pcall(json.decode, govde)
    if not ok_dec or type(data) ~= "table" then
        logger.warn("1000Kitap: JSON çözülemedi", yol, govde:sub(1, 200))
        return nil, "1000Kitap'tan anlaşılmayan bir yanıt geldi.", "sunucu"
    end
    if not isNull(data.hata) and data.hata ~= false and data.hata ~= 0 and data.hata ~= "0" then
        -- { hata = 1, hataTuru = 1, hataMesaji = "Lütfen giriş yapınız.", alertMesaji = "" }
        local mesaj = metin(data.hataMesaji) or metin(data.alertMesaji) or metin(data.bilgiMesaji)
            or "1000Kitap isteği kabul etmedi."
        local tur = "sunucu"
        if mesaj:find("giriş yap", 1, true) or mesaj:find("oturum", 1, true) then
            tur = "yetki"
            mesaj = mesaj .. " (Oturum kodu geçersiz ya da süresi dolmuş olabilir.)"
        end
        logger.warn("1000Kitap: sunucu hatası", yol, mesaj)
        return nil, mesaj, tur
    end
    return data
end

-- Başarısız her isteği eklentinin hata günlüğüne bildir (main.lua Api.gunluk'u kurar).
do
    local ham_istek = Api.istek
    function Api:istek(method, yol, ...)
        local data, err, tur = ham_istek(self, method, yol, ...)
        if not data and self.gunluk then pcall(self.gunluk, tur, yol, err) end
        return data, err, tur
    end
end

local function bul(t, anahtar, derinlik)
    derinlik = derinlik or 0
    if type(t) ~= "table" or derinlik > 8 then return nil end
    if not isNull(t[anahtar]) then return t[anahtar] end
    for _i, v in pairs(t) do
        local r = bul(v, anahtar, derinlik + 1)
        if r ~= nil then return r end
    end
    return nil
end
Api._bul = bul

local function yazi(v)
    if isNull(v) then return "" end
    return tostring(v)
end

local function sayfalama(s)
    if type(s) == "table" and (s.hasMore == true or s.hasMore == 1 or s.hasMore == "1") then
        return { kume = s.kume, z = s.z, sayfa = (tonumber(s.sayfa) or 1) + 1 }
    end
    return nil
end

--- 1000Kitap genel puanı (10 üzerinden). "7,8", "7.8", 7.8 ya da 0/boş gelebilir.
local function puanOku(v)
    if type(v) == "string" then v = tonumber((v:gsub(",", "."))) end
    v = tonumber(v)
    if v and v > 0 and v <= 10 then return v end
    return nil
end
Api.puanOku = puanOku

--- Parse dizisi (metin parçaları + etiketlenen kitap/yazar/okur) → düz metin
local function parseMetni(parse)
    if type(parse) ~= "table" then return nil end
    local parcalar = {}
    for _i, p in ipairs(parse) do
        if type(p) == "string" then
            parcalar[#parcalar + 1] = p
        elseif type(p) == "table" and type(p.item) == "table" then
            local ad = p.item.adi or p.item.kadi
            if type(ad) == "string" and ad ~= "" then
                parcalar[#parcalar + 1] = (p.type == "okurKadiler" and "@" or "") .. ad
            end
        end
    end
    if #parcalar == 0 then return nil end
    return table.concat(parcalar)
end

local function sozMetni(oge)
    local soz = type(oge.alt) == "table" and oge.alt.sozler
    if type(soz) ~= "table" then return nil end
    local parse = type(soz.sozParse) == "table" and soz.sozParse.parse
    if type(parse) == "table" then
        local parcalar = {}
        for _i, p in ipairs(parse) do
            if type(p) == "string" then parcalar[#parcalar + 1] = p end
        end
        if #parcalar > 0 then return table.concat(parcalar), soz end
    end
    if type(soz.soz) == "string" then return soz.soz, soz end
    return nil, soz
end

---------------------------------------------------------------------------
-- Okuma uç noktaları
---------------------------------------------------------------------------

--- Kitap arar (ISBN de verilebilir). Dönüş: { {id=, adi=, yazar=}, ... }
function Api:kitapAra(sorgu)
    local data, err, tur = self:istek("GET", "diger/arama", { { "q", sorgu }, { "sadece", "kitap" } }, nil, false)
    if not data then return nil, err, tur end
    local sonuc = {}
    local liste = data._sonuc and data._sonuc.sonuclar
    if type(liste) ~= "table" then return sonuc end
    for _i, s in ipairs(liste) do
        if s.turu == "kitap" and type(s.icerik) == "table" and s.icerik.id then
            sonuc[#sonuc + 1] = {
                id = tostring(s.icerik.id),
                adi = yazi(s.icerik.adi ~= nil and s.icerik.adi or s.name),
                yazar = yazi(s.icerik.yazarAdi),
                puan = puanOku(s.icerik.puan),
            }
        end
    end
    return sonuc
end

--- Kitap ayrıntısı: puan, okunma vb. ve basılı sayfa sayısı.
function Api:kitapBilgisi(kitap_id)
    local data, err, tur = self:istek("GET", "kitaplar/kitapCek", { { "id", kitap_id } }, nil, false)
    if not data then return nil, err, tur end
    local k = data._sonuc and data._sonuc.kitap
    if type(k) ~= "table" then
        return nil, "Kitap bilgisi alınamadı.", "sunucu"
    end
    -- Baskı bilgileri "Genel bakış" listesinin "hakkında" bölümünde
    local baski
    for _i, o in ipairs(type(data._sonuc.liste) == "table" and data._sonuc.liste or {}) do
        if type(o) == "table" and type(o.hakkinda) == "table" and type(o.hakkinda.baskiBilgileri) == "table" then
            baski = o.hakkinda.baskiBilgileri
            break
        end
    end
    baski = baski or {}
    return {
        yayinevi = yazi(baski.yayinevi ~= nil and baski.yayinevi or bul(data._sonuc, "yayinevi")),
        baski_yili = yazi(baski.baskiYili),
        id = yazi(k.id),
        adi = yazi(k.adi),
        yazar = yazi(k.yazarAdi),
        puan = yazi(k.puan),
        puan_kisi = yazi(k.puan_kisiDuz),
        okunma = yazi(k.okuduDuz ~= nil and k.okuduDuz or k.okudu),
        begeni = yazi(k.begeniDuz),
        alinti = yazi(k.alintiSayisiDuz),
        inceleme = yazi(k.incelemeSayisiDuz),
        isbn = yazi(k.isbn),
        sayfa = tonumber(baski.sayfaSayisi) or tonumber(bul(data._sonuc, "sayfaSayisi")),
    }
end

function Api:sayfaSayisi(kitap_id)
    local b = self:kitapBilgisi(kitap_id)
    return b and b.sayfa or nil
end

--- Bir kitabın baskıları. Dönüş: liste, sonraki_sayfa (nil = son sayfa)
function Api:basimlar(kitap_id, sayfalama_bilgisi)
    local s = sayfalama_bilgisi or { sayfa = 1, kume = -1, z = 0 }
    local data, err, tur = self:istek("GET", "kitaplar/basimlar", {
        { "kitapId", kitap_id }, { "q", "" },
        { "sayfa", s.sayfa }, { "kume", s.kume }, { "z", s.z },
    }, nil, false)
    if not data then return nil, err, tur end
    local liste = {}
    local L = data._sonuc and data._sonuc.liste
    for _i, b in ipairs(type(L) == "table" and L or {}) do
        if type(b) == "table" and b.id then
            local bb = type(b.baskiBilgileriArray) == "table" and b.baskiBilgileriArray or {}
            liste[#liste + 1] = {
                id = yazi(b.id),
                adi = yazi(b.adi),
                yayinevi = yazi(bb.yayinevi),
                sayfa = tonumber(bb.sayfaSayisi),
                isbn = yazi(bb.isbn),
                yil = yazi(bb.baskiYili),
                puan = puanOku(b.puan),
            }
        end
    end
    return liste, sayfalama(data._sonuc)
end

--- Senin bu kitaptaki durumun.
-- Dönüş: { durum = -1..3, okuma_id = "..."|nil, toplam_sayfa, mevcut_sayfa, puan }
function Api:okumaDurumu(kitap_id)
    local data, err, tur = self:istek("GET", "uye/kitap/modalVeBasimlar", { { "kitapId", kitap_id } }, nil, true)
    if not data then return nil, err, tur end
    local s = data._sonuc
    if type(s) ~= "table" then
        return nil, "1000Kitap'tan okuma durumu alınamadı.", "sunucu"
    end
    local m = type(s.modal) == "table" and s.modal or {}
    local durum
    local basim = type(s.basimlar) == "table" and s.basimlar[1]
    if type(basim) == "table" and type(basim.okumaDurumuButon) == "table" then
        durum = tonumber(basim.okumaDurumuButon.okumaDurumu)
    end
    if durum == nil then durum = tonumber(m.okumaSayi) end
    local okuma_id = metin(yazi(m.okumaId))
    if not okuma_id and type(m.okumalar) == "table" then
        for _i, o in ipairs(m.okumalar) do
            if type(o) == "table" and tostring(o.kitapId) == tostring(kitap_id) and o.id then
                okuma_id = yazi(o.id)
                break
            end
        end
    end
    local sv = type(m.sayfaVeri) == "table" and m.sayfaVeri or {}
    local kitaplikta = m.kutuphaneDurum
    if isNull(kitaplikta) and type(basim) == "table" then kitaplikta = basim.isKitapligimda end
    kitaplikta = kitaplikta == true or kitaplikta == "true" or kitaplikta == 1 or kitaplikta == "1"
    return {
        kitaplikta = kitaplikta,
        durum = durum or Api.DURUM.yok,
        okuma_id = okuma_id,
        toplam_sayfa = tonumber(sv.sayfa),
        mevcut_sayfa = tonumber(sv.sayfa2),
        puan = tonumber(m.puan),
    }
end

--- Bir okurun rafındaki kitaplar (ör. "okuyacaklari").
-- Dönüş: liste {id, adi, yazar, sayfa}, sonraki_sayfa
function Api:rafListesi(kadi, raf, sayfalama_bilgisi)
    local s = sayfalama_bilgisi or { sayfa = 1, kume = -1, z = 0 }
    local data, err, tur = self:istek("GET", "uyeler/kitaplar/liste", {
        { "konu", "" }, { "eserTuru", "" }, { "dil", "" }, { "ulke", "" },
        { "orijinalDil", "" }, { "orijinalUlke", "" }, { "uzunluk", "" }, { "kitapPuani", "" },
        { "hedefKitle", "" }, { "deneyim", "" }, { "kutuphane", "" },
        { "kadi", kadi }, { "raf", raf }, { "okumaBicimi", "" }, { "siralama", "" },
        { "yazarId", "" }, { "yayineviId", "" }, { "eserTuruId", "" }, { "puan", "" },
        { "q", "" }, { "sene", "" },
        { "sayfa", s.sayfa }, { "kume", s.kume }, { "z", s.z },
    }, nil, false)
    if not data then return nil, err, tur end
    local liste = {}
    local L = data._sonuc and data._sonuc.liste
    for _i, k in ipairs(type(L) == "table" and L or {}) do
        if type(k) == "table" and k.id and k.adi and not k.renderTuru then
            liste[#liste + 1] = {
                id = yazi(k.id),
                adi = yazi(k.adi),
                yazar = yazi(k.yazarAdi),
                sayfa = tonumber(k.sayfaSayisi),
                puan = puanOku(k.puan),
            }
        end
    end
    return liste, sayfalama(data._sonuc)
end

--- Bir rafın tamamı (en fazla `en_fazla_sayfa` sayfa).
function Api:rafinTamami(kadi, raf, en_fazla_sayfa)
    local hepsi, s = {}, nil
    for _i = 1, en_fazla_sayfa or 30 do
        local liste, sonraki_veya_err, tur = self:rafListesi(kadi, raf, s)
        if not liste then return nil, sonraki_veya_err, tur end
        for _i, k in ipairs(liste) do hepsi[#hepsi + 1] = k end
        s = sonraki_veya_err
        if not s then break end
    end
    return hepsi
end

--- Bir kitabın popüler alıntıları. Dönüş: { {soz, begeni, uye, sayfa}, ... }
function Api:populerAlintilar(kitap_id)
    local data, err, tur = self:istek("GET", "kitaplar/kitapCek", {
        { "id", kitap_id }, { "bolum", "alintilar" }, { "site", "" }, { "s", "populer" },
        { "puan", "" }, { "q", "" }, { "sayfa", 1 }, { "kume", -1 }, { "z", 0 },
    }, nil, false)
    if not data then return nil, err, tur end
    local liste = {}
    local L = data._sonuc and data._sonuc.liste
    for _i, o in ipairs(type(L) == "table" and L or {}) do
        if type(o) == "table" and o.turu == "sozler" then
            local soz, ham = sozMetni(o)
            if soz then
                liste[#liste + 1] = {
                    soz = soz,
                    begeni = tonumber(o.begeniSayisi) or 0,
                    uye = type(o.uye) == "table" and yazi(o.uye.adi) or "",
                    sayfa = ham and tonumber(ham.sayfa) or nil,
                }
            end
        end
    end
    return liste
end

--- Sitenin Kitaplar sekmesindeki listeler (Size özel öneriler, Son 7 günün en çok okunanları…).
-- parametreler: { {ad, değer}, ... }; sayfalama: önceki dönüşün ikinci değeri (ilk sayfa için nil).
-- Dönüş: liste {id, adi, yazar, puan, okunma, ek, durum}, sonraki_sayfalama (bitti ise nil)
function Api:kesifListe(parametreler, sayfalama)
    local q = {}
    for _i, p in ipairs(parametreler or {}) do q[#q + 1] = { p[1], p[2] } end
    sayfalama = sayfalama or { sayfa = 1, kume = -1, z = 0 }
    q[#q + 1] = { "sayfa", sayfalama.sayfa }
    q[#q + 1] = { "kume", sayfalama.kume }
    q[#q + 1] = { "z", sayfalama.z }
    local data, err, tur = self:istek("GET", "kitaplar/kesifListe", q, nil, true)
    if not data then return nil, err, tur end
    local s = data._sonuc or {}
    local liste = {}
    for _i, k in ipairs(type(s.liste) == "table" and s.liste or {}) do
        if type(k) == "table" and k.id and k.adi and k.renderTuru ~= "reklam" and k.turu ~= "reklam" then
            local db = type(k.okumaDurumuButon) == "table" and k.okumaDurumuButon or {}
            liste[#liste + 1] = {
                id = yazi(k.id),
                adi = yazi(k.adi),
                yazar = yazi(k.yazarAdi or k.ilkYazar),
                puan = puanOku(k.puan),
                okunma = tonumber(k.okuduDuz),
                ek = k.ekBilgi and yazi(k.ekBilgi) or nil,
                durum = tonumber(db.okumaDurumu),
            }
        end
    end
    local sonraki
    if s.hasMore and s.hasMore ~= 0 and s.hasMore ~= "0" then
        sonraki = { sayfa = (tonumber(s.sayfa) or sayfalama.sayfa) + 1, kume = s.kume or -1, z = s.z or 0 }
    end
    return liste, sonraki, s.baslik and yazi(s.baslik) or nil
end

--- Bir kitabın popüler incelemeleri.
-- Dönüş: { {id, metin, kisaltilmis, uye, begeni, yorum, puan (incelemecinin, 10 üzerinden), tarih}, ... }
function Api:populerIncelemeler(kitap_id)
    local data, err, tur = self:istek("GET", "kitaplar/kitapCek", {
        { "id", kitap_id }, { "bolum", "incelemeler" }, { "site", "" }, { "s", "populer" },
        { "puan", "" }, { "q", "" }, { "sayfa", 1 }, { "kume", -1 }, { "z", 0 },
    }, nil, false)
    if not data then return nil, err, tur end
    local liste = {}
    local L = data._sonuc and data._sonuc.liste
    for _i, o in ipairs(type(L) == "table" and L or {}) do
        local y = type(o) == "table" and o.turu == "yorumlar" and type(o.alt) == "table" and o.alt.yorumlar
        local yp = type(y) == "table" and y.yorumParse
        local metin = type(yp) == "table" and parseMetni(yp.parse)
        if metin and metin:match("%S") then
            local verdigi
            for _j, g in ipairs(type(o.govdeSayfa) == "table" and o.govdeSayfa or {}) do
                if type(g) == "table" and tonumber(g.isPuan) == 1 then
                    verdigi = tonumber(g.puan)
                    if verdigi and tonumber(g.max) and tonumber(g.max) ~= 10 and tonumber(g.max) > 0 then
                        verdigi = verdigi * 10 / tonumber(g.max)
                    end
                end
            end
            liste[#liste + 1] = {
                id = yazi(o.id),
                metin = metin,
                kisaltilmis = yp.isUzunKisaltma == true,
                uye = type(o.uye) == "table" and yazi(o.uye.adi) or "",
                begeni = tonumber(o.begeniSayisi) or 0,
                yorum = tonumber(o.yorumSayisi) or 0,
                puan = verdigi,
                tarih = yazi(o.tarihsaat),
            }
        end
    end
    return liste
end

--- Bir okurun alıntıları. Dönüş: liste {soz, kitap_id}, sonraki_sayfa
function Api:okurAlintilari(kadi, sayfalama_bilgisi)
    local s = sayfalama_bilgisi or { sayfa = 1, kume = -1, z = 0 }
    local data, err, tur = self:istek("GET", "okurlar/okurCekV2", {
        { "id", kadi }, { "bolum", "alintilar" }, { "s", "" }, { "sene", "" }, { "q", "" },
        { "kitapId", "" }, { "konuId", "" },
        { "sayfa", s.sayfa }, { "kume", s.kume }, { "z", s.z },
    }, nil, false)
    if not data then return nil, err, tur end
    local liste = {}
    local L = data._sonuc and data._sonuc.liste
    for _i, o in ipairs(type(L) == "table" and L or {}) do
        if type(o) == "table" and o.turu == "sozler" then
            local soz, ham = sozMetni(o)
            if soz then
                liste[#liste + 1] = { soz = soz, kitap_id = ham and yazi(ham.kitapid) or "" }
            end
        end
    end
    return liste, sayfalama(data._sonuc)
end

--- Takip ettiklerinden bu kitabı okuyanların adları.
function Api:tanidikOkurlar(kitap_id)
    local data, err, tur = self:istek("GET", "kitaplar/tanidikOkurlar", { { "id", kitap_id } }, nil, true, self.analiz_url)
    if not data then return nil, err, tur end
    local adlar, gorulen = {}, {}
    local function topla(t, d)
        if type(t) ~= "table" or d > 6 then return end
        local ad = metin(t.adi)
        if ad and (t.kadi ~= nil or t.uyeid ~= nil or t.resim ~= nil) and not gorulen[ad] then
            gorulen[ad] = true
            adlar[#adlar + 1] = ad
        end
        for _i, v in pairs(t) do topla(v, d + 1) end
    end
    topla(data._sonuc, 0)
    return adlar
end

--- Okuma hedefi. Dönüş: { hedef = n|nil, okunan = n|nil } ya da {} (hedef yok)
function Api:okumaHedefi(sene)
    local data, err, tur = self:istek("GET", "okuma-hedefleri/sene-detay", { { "sene", sene } }, nil, true)
    if not data then return nil, err, tur end
    local s = data._sonuc
    if type(s) ~= "table" or next(s) == nil then return {} end
    local hedef = tonumber(bul(s, "hedef")) or tonumber(bul(s, "hedefSayisi"))
    local okunan = tonumber(bul(s, "okunan")) or tonumber(bul(s, "okunanSayisi"))
        or tonumber(bul(s, "okunanKitapSayisi")) or tonumber(bul(s, "tamamlanan"))
        or tonumber(bul(s, "okuduSayisi"))
    return { hedef = hedef, okunan = okunan }
end

--- Konu arar. Dönüş: { {id, adi}, ... }
function Api:konuAra(q)
    local data, err, tur = self:istek("GET", "konular/konuArama", { { "q", q } }, nil, false)
    if not data then return nil, err, tur end
    local liste = {}
    local s = data._sonuc
    local L = type(s) == "table" and (s.liste or s) or {}
    for _i, k in ipairs(type(L) == "table" and L or {}) do
        if type(k) == "table" and k.id and k.adi then
            liste[#liste + 1] = { id = yazi(k.id), adi = yazi(k.adi) }
        end
    end
    return liste
end

---------------------------------------------------------------------------
-- Yazma uç noktaları
---------------------------------------------------------------------------

--- tarih verilirse ({ bas = zaman, bit = zaman }) okuma, sitenin "Toplu okuma ekle"
-- sayfasındaki gibi başlangıç ve bitiş tarihiyle kaydedilir; yıllık hedefe doğru yıla sayılır.
function Api:durumAyarla(kitap_id, durum, tarih)
    if type(tarih) == "table" and tarih.bas and tarih.bit then
        return self:istek("GET", "kitaplar/kitapOku", {
            { "id", kitap_id }, { "durum", durum }, { "forceEkle", 1 },
            { "okuyorTarihsaat", os.date("%d.%m.%Y %H:%M", tarih.bas) },
            { "okuduTarihsaat", os.date("%d.%m.%Y %H:%M", tarih.bit) },
            { "isTopluIslem", 1 },
        }, nil, true)
    end
    return self:istek("GET", "kitaplar/kitapOku", {
        { "id", kitap_id }, { "durum", durum }, { "yeniOkuma", 0 }, { "neOkusam", 0 },
    }, nil, true)
end

function Api:puanVer(kitap_id, puan)
    return self:istek("GET", "kitaplar/kitapPuanVer", {
        { "id", kitap_id }, { "puan", puan },
    }, nil, true)
end

function Api:sayfaGuncelle(kitap_id, okuma_id, toplam_sayfa, sayfa)
    return self:istek("GET", "kitaplar/kitapSayfaGuncelle", {
        { "id", kitap_id }, { "okumaId", okuma_id }, { "sayfa", toplam_sayfa }, { "sayfa2", sayfa },
    }, nil, true)
end

function Api:alintiEkle(kitap_id, soz, sayfa, ekbilgi, secenekler)
    secenekler = secenekler or {}
    return self:istek("POST", "alintilar/alintiEkle", nil, {
        { "soz", soz },
        { "kitapid", kitap_id },
        { "sayfa", sayfa or "" },
        { "konuId", secenekler.konu_id or "" },
        { "linkIceriyor", 0 },
        { "taslak", 0 },
        { "baslik", "" },
        { "ekbilgi", ekbilgi or "" },
        { "id", 0 },
        { "yorumAyari", secenekler.yorum_ayari or 0 },
        { "yorumOnayi", 0 },
        { "isOkumaSayfasiGuncelle", secenekler.ilerlemeyi_guncelle and 1 or 0 },
        { "isSayfaGuncellemesiniPaylas", 0 },
    }, true)
end

--- Herkese açık ileti (gönderi). Bir kitabı etiketlemek için metne "#k:<kitap id>" eklenir.
-- secenekler = { baslik, konu_id, konu_adi, yorum_ayari }
function Api:iletiEkle(metin, secenekler)
    secenekler = secenekler or {}
    return self:istek("POST", "iletiler/iletiEkle", nil, {
        { "id", "" },
        { "konuId", secenekler.konu_id or "" },
        { "konuAdi", secenekler.konu_adi or "" },
        { "gonderiId", "" },
        { "ileti", metin },
        { "anket", "" },
        { "baslik", secenekler.baslik or "" },
        { "yorumAyari", secenekler.yorum_ayari or 0 },
        { "resimIdler", "" },
        { "koleksiyonId", "" },
        { "ekKulupId", "" },
        { "anonimSoru", 0 },
        { "anonimSoruAkimi", 0 },
        { "anonimSoruMisafir", 1 },
        { "yorumOnayi", 0 },
    }, true)
end

function Api:ozelNotEkle(kitap_id, not_metni, anahtar)
    return self:istek("POST", "koleksiyonlar/not-ayarla", nil, {
        { "hedefTuru", "kitap" },
        { "hedefId", kitap_id },
        { "notId", "" },
        { "notAnahtari", anahtar or Api.rastgeleKod(16) },
        { "surum", 0 },
        { "not", not_metni },
    }, true)
end

function Api:incelemeKaydet(kitap_id, inceleme, yorum_ayari)
    return self:istek("POST", "kitaplar/kitapIncelemeKaydet",
        { { "kitapId", kitap_id }, { "id", kitap_id } },
        {
            { "inceleme", inceleme },
            { "konuId", 0 },
            { "baslik", "" },
            { "yorumAyari", yorum_ayari or 0 },
            { "yorumOnayi", 0 },
            { "kitapYeniKonuAdlari", "[]" },
            { "kitapKonuIdleri", "" },
            { "kitapDeneyimIdleri", "" },
            { "isYeni", 1 },
        }, true)
end

function Api:seansTamamla(okuma_id, bitis_sayfasi, sure_saniye, istemci_kodu)
    return self:istek("POST", "uyeler/okumalar/gunluk/seansTamamla", nil, {
        { "okumaId", okuma_id },
        { "bitisSayfasi", bitis_sayfasi },
        { "sureSaniye", sure_saniye },
        { "istemciKodu", istemci_kodu or ("W2-" .. Api.rastgeleKod(12)) },
    }, true)
end

--- Kitabı kitaplığa ekler. Zaten ekliyse bir şey değişmez (sitenin "Toplu ekle"si gibi).
function Api:kitapligaEkle(kitap_id)
    return self:istek("GET", "kitaplar/kitapKutuphanemeEkle", {
        { "id", kitap_id }, { "forceEkle", 1 }, { "isTopluIslem", 1 },
    }, nil, true)
end

--- "Kitaplığımda" düğmesi: kitaplıktaysa çıkarır, değilse ekler. Önce durumu kontrol et.
function Api:kitaplikDegistir(kitap_id)
    return self:istek("GET", "kitaplar/kitapKutuphanemeEkle", {
        { "id", kitap_id }, { "forceEkle", 0 },
    }, nil, true)
end

function Api:okumaHedefiKaydet(sene, hedef)
    return self:istek("POST", "diger/okumaHedefiKaydet", nil, {
        { "verilerimBen", 1 }, { "sene", sene }, { "hedef", hedef }, { "metin", "" },
    }, true)
end

return Api
