-- v0.2 uçtan uca testi: KOReader ve 1000Kitap sunucusu taklit edilir.
local KOK = ((arg and arg[0]) or ""):match("^(.*)/test/[^/]*$") or "."
local EKLENTI = KOK .. "/binkitap.koplugin"
package.path = EKLENTI .. "/?.lua;" .. package.path

local gercek_lfs = lfs   -- texlua yerleşik; güncelleme testi gerçek geçici klasörde çalışır
local GERCEK = "/tmp/binkitap-test-" .. tostring(os.time())
local gercek_time = os.time
local saat = 1795000000
os.time = function(t) if t then return gercek_time(t) end return saat end
local gercek_date = os.date
os.date = function(f, t) return gercek_date(f, t or saat) end
local function ilerlet(sn) saat = saat + sn end

------------------------------------------------------------------ mini json
local json = { null = setmetatable({}, { __tostring = function() return "null" end }) }
function json.decode(s)
  local i = 1
  local function ws() i = s:find("[^%s]", i) or #s + 1 end
  local val
  local function str()
    i = i + 1
    local out = {}
    while true do
      local c = s:sub(i, i)
      if c == '"' then i = i + 1; break end
      if c == "\\" then
        local n = s:sub(i + 1, i + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if n == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
        else out[#out + 1] = map[n]; i = i + 2 end
      else out[#out + 1] = c; i = i + 1 end
    end
    return table.concat(out)
  end
  function val()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      i = i + 1; local t = {}; ws()
      if s:sub(i, i) == "}" then i = i + 1; return t end
      while true do
        ws(); local k = str(); ws(); i = i + 1
        t[k] = val(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == "}" then return t end
      end
    elseif c == "[" then
      i = i + 1; local t = {}; ws()
      if s:sub(i, i) == "]" then i = i + 1; return t end
      while true do
        t[#t + 1] = val(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == "]" then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4; return json.null
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
      i = i + #num; return tonumber(num)
    end
  end
  return val()
end
local function encode(v)
  local t = type(v)
  if v == nil or v == json.null then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then return tostring(v) end
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  end
  if t == "table" then
    if next(v) == nil then return (getmetatable(v) == "obj") and "{}" or "[]" end
    if v[1] ~= nil then
      local p = {}
      for _, x in ipairs(v) do p[#p + 1] = encode(x) end
      return "[" .. table.concat(p, ",") .. "]"
    end
    local p = {}
    for k, x in pairs(v) do p[#p + 1] = encode(tostring(k)) .. ":" .. encode(x) end
    return "{" .. table.concat(p, ",") .. "}"
  end
  error("encode " .. t)
end
package.preload["json"] = function() return json end

------------------------------------------------------------------ sahte 1000Kitap
local Y = require("binkitap_yardimci")
local KITAPLAR = {
  ["24319"] = { adi = "Walden", yazar = "Henry David Thoreau", yayinevi = "Zeplin Kitap", sayfa = 357, isbn = "9786054849789", yil = "2019" },
  ["359215"] = { adi = "Walden", yazar = "Henry David Thoreau", yayinevi = "Can Yayınları", sayfa = 352, isbn = "9789750758928", yil = "2022" },
  ["9517"] = { adi = "Kaos Lordu", yazar = "Robert Jordan", yayinevi = "İthaki", sayfa = 1080, isbn = "9786053751234", yil = "2021" },
  ["700"] = { adi = "Dönüşüm", yazar = "Franz Kafka", yayinevi = "İş Bankası", sayfa = 80, isbn = "", yil = "2015" },
  ["701"] = { adi = "Dönüşüm", yazar = "Franz Kafka", yayinevi = "Can Yayınları", sayfa = 96, isbn = "", yil = "2018" },
  ["702"] = { adi = "Dönüşüm", yazar = "Ovidius", yayinevi = "Kabalcı", sayfa = 400, isbn = "", yil = "2010" },
  ["800"] = { adi = "Gog", yazar = "Giovanni Papini", yayinevi = "Can", sayfa = 496, isbn = "", yil = "2016" },
  ["801"] = { adi = "Şairin Romanı", yazar = "Murathan Mungan", yayinevi = "Metis", sayfa = 300, isbn = "", yil = "2001" },
  ["900"] = { adi = "Yaşam Yolu 1", yazar = "Anton Makarenko", yayinevi = "Kaynak", sayfa = 420, isbn = "", yil = "2020" },
  ["92807"] = { adi = "Shenzen", yazar = "Guy Delisle", yayinevi = "Karakarga", sayfa = 152, isbn = "", yil = "2014" },
}
-- 1000Kitap kitaplığı: Walden (Zeplin) aynı baskı, Dönüşüm (İş Bankası) başka baskı, Shenzen basılı kitap
local KITAPLIK = { "24319", "700", "92807" }
local function kitaplikta(id) for _, x in ipairs(KITAPLIK) do if x == id then return true end end return false end
local SIRA = { "24319", "359215", "9517", "700", "701", "702", "800", "801", "900", "92807" }
local durum, sayfa2, puan, notlar, alintilar, incelemeler, seanslar, hedefler = {}, {}, {}, {}, {}, {}, {}, {}
local OKUYACAKLAR = { "800", "801", "700", "900" }
local OTURUM = "11111111-2222-3333-4444-555555555555"
local CIHAZ = "CIHAZKODU123456"
local istekler = {}
local ag_acik = true
local sunucu_kapali = false

local function kimlikli(r) return r.headers["1-oturum-kodu"] == OTURUM and r.headers["1-cihaz-kodu"] == CIHAZ end
local function giris_hatasi() return { hata = 1, hataTuru = 1, hataMesaji = "Lütfen giriş yapınız.", alertMesaji = "" } end
local function obj(t) return setmetatable(t or {}, { __metatable = "obj" }) end

local function aramaSonucu(q)
  local sonuc = { { id = 0, name = q, turu = "etiket", icerik = { id = "9", adi = q } } }
  local temiz = q:gsub("[%-%s]", "")
  for _, id in ipairs(SIRA) do
    local k = KITAPLAR[id]
    if k.isbn ~= "" and k.isbn == temiz then
      sonuc[#sonuc + 1] = { id = 1, name = k.adi, turu = "kitap", icerik = { id = id, adi = k.adi, yazarAdi = k.yazar ~= "" and k.yazar or json.null } }
      return sonuc
    end
  end
  for _, id in ipairs(SIRA) do
    local k = KITAPLAR[id]
    local metin = Y.normal(k.adi .. k.yazar)
    local hepsi = true
    for kelime in q:gmatch("%S+") do
      if not metin:find(Y.normal(kelime), 1, true) then hepsi = false break end
    end
    if hepsi then
      sonuc[#sonuc + 1] = { id = #sonuc, name = k.adi, turu = "kitap", icerik = { id = id, adi = k.adi, yazarAdi = k.yazar ~= "" and k.yazar or json.null } }
    end
  end
  sonuc[#sonuc + 1] = { id = 99, name = "Biri", turu = "yazar", icerik = { id = "4148", adi = "Biri" } }
  return sonuc
end

local YANIT = {}
YANIT["diger/arama"] = function(r) return { _sonuc = { sonuclar = aramaSonucu(r.q.q), kelime = r.q.q }, bilgi = 1, bilgiMesaji = "" } end
YANIT["kitaplar/kitapCek"] = function(r)
  local k = KITAPLAR[r.q.id]
  if not k then return { hata = 1, hataMesaji = "Kitap yok" } end
  if r.q.bolum == "incelemeler" then
    assert(r.q.s == "populer", "incelemeler popüler sırayla")
    return { _sonuc = { liste = {
      { turu = "reklam" },
      { turu = "yorumlar", id = "274933988", begeniSayisi = 194, yorumSayisi = 1, tarihsaat = "2025-06-05 00:14:44",
        uye = { adi = "Ece" }, govde = { { baslik = "Kitabı okudu" } },
        govdeSayfa = { { baslik = "5/10 puan verdi", isPuan = 1, puan = 5, max = 10 }, { tip = "yillikSira", sira = 18 } },
        alt = { yorumlar = { yorumParse = { parse = { "Doğada yaşamak üzerine. ", { type = "okurKadiler", id = "osgr", item = { adi = "osgr", kadi = "osgr" } }, " da sevdi." }, isUzunKisaltma = true } },
                kitaplar = { id = r.q.id, adi = k.adi, puan = 7.8 } } },
      { turu = "duvar" },
      { turu = "yorumlar", id = "2", begeniSayisi = 3, yorumSayisi = 0, uye = { adi = "Can" }, govdeSayfa = {},
        alt = { yorumlar = { yorumParse = { parse = { "Kısa ve güzel." }, isUzunKisaltma = false } } } },
      { turu = "yorumlar", id = "3", uye = { adi = "Boş" }, alt = { yorumlar = { yorumParse = { parse = { "   " } } } } },
    }, hasMore = true }, bilgi = 1 }
  end
  if r.q.bolum == "alintilar" then
    return { _sonuc = { liste = {
      { turu = "sozler", begeniSayisi = 489, uye = { adi = "Ersin Yaman" }, alt = { sozler = { kitapid = r.q.id, sayfa = "12", sozParse = { parse = { "Kim bilir kaç insan ", "bir kitabı okuyup..." } } } } },
      { turu = "reklam" },
      { turu = "sozler", begeniSayisi = 10, uye = { adi = "Ayşe" }, alt = { sozler = { kitapid = r.q.id, sayfa = "0", sozParse = { parse = { "İkinci alıntı" } } } } },
    }, hasMore = true }, bilgi = 1 }
  end
  return { _sonuc = {
    kitap = { id = r.q.id, adi = k.adi, yazarAdi = k.yazar, puan = "7.8", puan_kisiDuz = "596", okuduDuz = "1911", begeniDuz = "545", alintiSayisiDuz = "9526", incelemeSayisiDuz = "127", isbn = k.isbn },
    liste = { { hakkinda = { baskiBilgileri = { yayinevi = k.yayinevi, isbn = k.isbn, sayfaSayisi = tostring(k.sayfa), baskiYili = k.yil } } },
              { fiyatlar = { { baskiBilgileriArray = { sayfaSayisi = "999", yayinevi = "Yanlış" } } } } },
  }, bilgi = 1 }
end
YANIT["kitaplar/basimlar"] = function(r)
  local sayfa = tonumber(r.q.sayfa)
  local ids = sayfa == 1 and { "24319", "359215" } or { "9517" }
  local liste = {}
  for _, id in ipairs(ids) do
    local k = KITAPLAR[id]
    liste[#liste + 1] = { id = id, adi = k.adi, baskiBilgileriArray = { yayinevi = k.yayinevi, sayfaSayisi = tostring(k.sayfa), isbn = k.isbn, baskiYili = k.yil } }
  end
  return { _sonuc = { hasMore = sayfa == 1, kume = 4973230052879385, z = 10, sayfa = sayfa, liste = liste }, bilgi = 1 }
end
rawset(_G, "baska_baski", {})  -- [kitap_id] = okumanın olduğu başka baskının kimliği (yerel sayı sınırı yüzünden global)
YANIT["uye/kitap/modalVeBasimlar"] = function(r)
  if not kimlikli(r) then return giris_hatasi() end
  local id = r.q.kitapId
  local d = durum[id] or -1
  local k = KITAPLAR[id] or { sayfa = 100 }
  local bb = baska_baski[id]
  return { _sonuc = {
    basimlar = { { id = id, okumaDurumuButon = { yazi = "x", durum = "0", okumaDurumu = d } } },
    modal = { okumaSayi = tostring(d), okumaId = (d >= 0 and not bb) and ("OK" .. id) or "",
      okumalar = bb and { { id = "OK" .. bb, kitapId = bb } } or {}, kutuphaneDurum = kitaplikta(id),
      sayfaVeri = { sayfa = tostring(k.sayfa), sayfa2 = tostring(sayfa2[id] or 0) }, puan = puan[id] or 0 },
  }, bilgi = 1 }
end
local iletiler, ileti_reddet = {}, false
YANIT["iletiler/iletiEkle"] = function(r)
  if not kimlikli(r) then return giris_hatasi() end
  assert(r.method == "POST", "ileti POST")
  if ileti_reddet then return { hata = 1, hataTuru = 2, hataMesaji = "Bu ileti paylaşılamaz.", alertMesaji = "" } end
  iletiler[#iletiler + 1] = r.form
  return { _sonuc = { id = 5000 + #iletiler }, bilgi = 1 }
end
local kesif_istekleri = {}
YANIT["kitaplar/kesifListe"] = function(r)
  if not kimlikli(r) then return giris_hatasi() end
  kesif_istekleri[#kesif_istekleri + 1] = r.q
  local sayfa = tonumber(r.q.sayfa)
  local liste = {}
  if sayfa == 1 then
    liste = {
      { id = "378538", adi = "Hizmetçi", yazarAdi = "Freida McFadden", puan = "8.5", okuduDuz = "15490", ekBilgi = "Son 7 Gün: 323 okuma", okumaDurumuButon = { okumaDurumu = -1 } },
      { renderTuru = "reklam", id = "x", adi = "Reklam" },
      { id = "24319", adi = "Walden", ilkYazar = "Henry David Thoreau", puan = 7.8, okuduDuz = 1911, okumaDurumuButon = { okumaDurumu = 1 } },
    }
  else
    liste = { { id = "800", adi = "Gog", yazarAdi = "Giovanni Papini", puan = "8.1", okumaDurumuButon = { okumaDurumu = -1 } } }
  end
  return { _sonuc = { liste = liste, hasMore = sayfa == 1, sayfa = sayfa, kume = 777, z = 10, baslik = "Liste", params = {} }, bilgi = 1 }
end

local okuma_tarihi = {}
rawset(_G, "YENI_OKUMA", {}) -- [kitap_id] = yeniOkuma=1 ile açılan okuma sayısı
YANIT["kitaplar/kitapOku"] = function(r)
  if not kimlikli(r) then return giris_hatasi() end
  durum[r.q.id] = tonumber(r.q.durum)
  if r.q.yeniOkuma == "1" then
    assert(not r.q.forceEkle and r.q.neOkusam == "0", "yeni okuma sitedeki biçimde")
    YENI_OKUMA[r.q.id] = (YENI_OKUMA[r.q.id] or 0) + 1
  end
  okuma_tarihi[r.q.id] = r.q.forceEkle and { bas = r.q.okuyorTarihsaat, bit = r.q.okuduTarihsaat, toplu = r.q.isTopluIslem } or false
  return { _sonuc = { durum = true }, bilgi = 1 }
end
YANIT["kitaplar/kitapPuanVer"] = function(r) puan[r.q.id] = tonumber(r.q.puan); return { _sonuc = {}, bilgi = 1 } end
YANIT["kitaplar/kitapSayfaGuncelle"] = function(r)
  assert(r.q.okumaId == "OK" .. r.q.id, "okumaId")
  sayfa2[r.q.id] = tonumber(r.q.sayfa2)
  return { _sonuc = {}, bilgi = 1 }
end
YANIT["alintilar/alintiEkle"] = function(r)
  if not kimlikli(r) then return giris_hatasi() end
  if r.form.soz == "TEKRAR" then return { hata = 1, hataTuru = 2, hataMesaji = "Bu alıntı daha önce eklenmiş.", alertMesaji = "" } end
  alintilar[#alintilar + 1] = r.form
  return { _sonuc = { id = "999" }, bilgi = 1 }
end
YANIT["koleksiyonlar/not-ayarla"] = function(r) notlar[#notlar + 1] = r.form; return { _sonuc = {}, bilgi = 1 } end
YANIT["kitaplar/kitapIncelemeKaydet"] = function(r) incelemeler[#incelemeler + 1] = { q = r.q, form = r.form }; return { _sonuc = {}, bilgi = 1 } end
YANIT["uyeler/okumalar/gunluk/seansTamamla"] = function(r) seanslar[#seanslar + 1] = r.form; return { _sonuc = {}, bilgi = 1 } end
YANIT["diger/okumaHedefiKaydet"] = function(r) hedefler[r.form.sene] = tonumber(r.form.hedef); return { _sonuc = {}, bilgi = 1 } end
YANIT["okuma-hedefleri/sene-detay"] = function(r)
  local h = hedefler[r.q.sene]
  if not h then return { _sonuc = {}, bilgi = 1 } end
  return { _sonuc = { hedef = h, okunanKitapSayisi = 4 }, bilgi = 1 }
end
YANIT["kitaplar/kitapKutuphanemeEkle"] = function(r)
  if not kimlikli(r) then return giris_hatasi() end
  local id = r.q.id
  if r.q.forceEkle == "1" then
    if not kitaplikta(id) then KITAPLIK[#KITAPLIK + 1] = id end
  elseif kitaplikta(id) then
    for i = #KITAPLIK, 1, -1 do if KITAPLIK[i] == id then table.remove(KITAPLIK, i) end end
  else
    KITAPLIK[#KITAPLIK + 1] = id
  end
  return { _sonuc = { durum = kitaplikta(id) }, bilgi = 1 }
end
YANIT["uyeler/kitaplar/liste"] = function(r)
  assert(r.q.kadi == "ornek_okur", "raf kadi")
  if r.q.raf == "kutuphanesi" then
    local liste, sayfa, BOYUT = {}, tonumber(r.q.sayfa) or 1, 20
    for n = (sayfa - 1) * BOYUT + 1, math.min(#KITAPLIK, sayfa * BOYUT) do
      local id = KITAPLIK[n]
      local k = KITAPLAR[id] or { adi = "Kitap " .. id, yazar = "", sayfa = 100 }
      liste[#liste + 1] = { id = id, adi = k.adi, yazarAdi = k.yazar, sayfaSayisi = tostring(k.sayfa) }
    end
    return { _sonuc = { hasMore = sayfa * BOYUT < #KITAPLIK, kume = 7, z = 1, sayfa = sayfa, liste = liste }, bilgi = 1 }
  end
  assert(r.q.raf == "okuyacaklari", "raf params")
  local sayfa = tonumber(r.q.sayfa)
  if sayfa == 2 then assert(r.q.kume == "4973230052879385" and r.q.z == "10", "kume/z") end
  local ids = sayfa == 1 and { OKUYACAKLAR[1], OKUYACAKLAR[2] } or { OKUYACAKLAR[3], OKUYACAKLAR[4] }
  local liste = {}
  for _, id in ipairs(ids) do
    local k = KITAPLAR[id]
    liste[#liste + 1] = { id = id, adi = k.adi, yazarAdi = k.yazar, sayfaSayisi = tostring(k.sayfa), puan = (id == OKUYACAKLAR[1]) and "8.1" or 0 }
  end
  liste[#liste + 1] = { renderTuru = "reklam", id = "x", adi = "reklam" }
  return { _sonuc = { hasMore = sayfa == 1, kume = 4973230052879385, z = 10, sayfa = sayfa, liste = liste }, bilgi = 1 }
end
YANIT["okurlar/okurCekV2"] = function(r)
  assert(r.q.bolum == "alintilar")
  local sayfa = tonumber(r.q.sayfa)
  return { _sonuc = { hasMore = sayfa == 1, kume = 1, z = 1, sayfa = sayfa, liste = {
    { turu = "sozler", alt = { sozler = { kitapid = "9477", sozParse = { parse = { "Alıntı " .. sayfa .. " %50" } } } } },
    { turu = "reklam" },
  } }, bilgi = 1 }
end
YANIT["konular/konuArama"] = function(r) return { _sonuc = { sinir = 10, liste = { { id = "24", adi = "Felsefe" }, { id = "3498", adi = "Felsefe ve Düşünce" } } }, bilgi = 1 } end
YANIT["kitaplar/tanidikOkurlar"] = function(r)
  assert(r.host == "analiz.1000kitap.com", "analiz host")
  return { _sonuc = { liste = { { uye = { adi = "Gökhan", kadi = "gokhan", resim = "x" } }, { uye = { adi = "Ece", kadi = "ece", resim = "y" } } } }, bilgi = 1 }
end

local function urldecode(s) return (s:gsub("+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
local function parseq(s)
  local t = {}
  for k, v in (s or ""):gmatch("([^&=]+)=([^&]*)") do t[urldecode(k)] = urldecode(v) end
  return t
end

local GITHUB = {}   -- url -> gövde (metin) ya da HTTP kodu (sayı)
local function fake_request(reqt)
  if reqt.url:find("github", 1, true) then
    istekler[#istekler + 1] = { url = reqt.url, github = true }
    if not ag_acik then return nil, "network unreachable" end
    local g = GITHUB[reqt.url]
    local code, resp = 200, g
    if type(g) == "number" then code, resp = g, "x" elseif g == nil then code, resp = 404, "yok" end
    reqt.sink(resp); reqt.sink(nil)
    return 1, code, {}, "HTTP/1.1 " .. code
  end
  local body
  if reqt.source then
    local parts = {}
    while true do local c = reqt.source(); if not c then break end; parts[#parts + 1] = c end
    body = table.concat(parts)
  end
  local host, yol, qs = reqt.url:match("^https://([^/]+)/v2/([^?]+)%??(.*)$")
  local r = { method = reqt.method, url = reqt.url, host = host, yol = yol, q = parseq(qs), headers = reqt.headers, body = body, form = parseq(body) }
  istekler[#istekler + 1] = r
  if not ag_acik then return nil, "network unreachable" end
  local code, resp = 200, nil
  if sunucu_kapali then code, resp = 503, "x"
  else
    local f = YANIT[yol]
    if f then
      local v = f(r)
      if type(v) == "number" then code, resp = v, "x" else resp = encode(v) end -- sayı: HTTP durum kodu
    else code, resp = 404, "yok" end
  end
  reqt.sink(resp); reqt.sink(nil)
  return 1, code, { ["content-type"] = "application/json" }, "HTTP/1.1 " .. code
end
local function istekSay(yol, kosul)
  local n = 0
  for _, r in ipairs(istekler) do if r.yol == yol and (not kosul or kosul(r)) then n = n + 1 end end
  return n
end
local function sonIstek(yol)
  for i = #istekler, 1, -1 do if istekler[i].yol == yol then return istekler[i] end end
end

package.preload["socket.http"] = function() return { request = fake_request } end
package.preload["ssl.https"] = function() return { request = fake_request } end
package.preload["socket"] = function() return { skip = function(n, ...) return select(n + 1, ...) end } end
package.preload["ltn12"] = function()
  return {
    source = { string = function(s) local done = false; return function() if done then return nil end; done = true; return s end end },
    sink = { table = function(t) return function(c) if c then t[#t + 1] = c end; return 1 end end },
  }
end
package.preload["socketutil"] = function() return { set_timeout = function() end, reset_timeout = function() end } end
local loglar = {}
package.preload["logger"] = function()
  local function l(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end; loglar[#loglar + 1] = table.concat(t, " ") end
  return { warn = l, info = l, err = l, dbg = l }
end

------------------------------------------------------------------ UI taklidi
local gosterilen, zamanlanan = {}, {}
local function widget(tur)
  local W = {}
  function W:new(o) o = o or {}; o._tur = tur; setmetatable(o, { __index = W }); return o end
  function W:onShowKeyboard() end
  function W:getInputText() return self._girdi or self.input end
  function W:getFields() local t = {}; for i, f in ipairs(self.fields) do t[i] = (self._alanlar and self._alanlar[i]) or f.text end; return t end
  function W:switchItemTable(_, items) self.item_table = items end
  return W
end
for _, ad in ipairs({ "buttondialog", "confirmbox", "infomessage", "inputdialog", "multiinputdialog", "menu", "textviewer" }) do
  local tur = ({ buttondialog = "ButtonDialog", confirmbox = "ConfirmBox", infomessage = "InfoMessage", inputdialog = "InputDialog",
    multiinputdialog = "MultiInputDialog", menu = "Menu", textviewer = "TextViewer" })[ad]
  package.preload["ui/widget/" .. ad] = function() return widget(tur) end
end
package.preload["ui/uimanager"] = function()
  return {
    show = function(_, w) gosterilen[#gosterilen + 1] = w end,
    close = function(_, w) if w then w._kapandi = true end end,
    scheduleIn = function(_, s, f) zamanlanan[#zamanlanan + 1] = f end,
    unschedule = function(_, f) for i = #zamanlanan, 1, -1 do if zamanlanan[i] == f then table.remove(zamanlanan, i) end end end,
    setDirty = function() end,
    forceRePaint = function() end,
    askForRestart = function(_, m) gosterilen[#gosterilen + 1] = { _tur = "Restart", text = m } end,
  }
end
local network = { online = true, wifi_acildi = 0, wifi_kapandi = 0 }
package.preload["ui/network/manager"] = function()
  return {
    isOnline = function() return network.online end,
    runWhenOnline = function(_, cb) if network.online then cb() else network.bekleyen = cb end end,
    turnOnWifiAndWaitForConnection = function(_, cb) network.wifi_acildi = network.wifi_acildi + 1; network.online = true; ag_acik = true; cb() end,
    turnOffWifi = function() network.wifi_kapandi = network.wifi_kapandi + 1; network.online = false end,
  }
end
package.preload["datastorage"] = function() return { getSettingsDir = function() return "/tmp" end } end
local function yeniAyarlar()
  local S = {}
  function S:open() local o = { data = {} }; setmetatable(o, { __index = S }); return o end
  function S:readSetting(k) return self.data[k] end
  function S:saveSetting(k, v) self.data[k] = v end
  function S:delSetting(k) self.data[k] = nil end
  function S:flush() end
  function S:nilOrTrue(k) return self.data[k] == nil or self.data[k] == true end
  function S:isTrue(k) return self.data[k] == true end
  function S:makeTrue(k) self.data[k] = true end
  function S:flipNilOrTrue(k) if self:nilOrTrue(k) then self.data[k] = false else self.data[k] = nil end end
  function S:flipTrue(k) self.data[k] = not self:isTrue(k) end
  return S
end
local LuaSettings = yeniAyarlar()
package.preload["luasettings"] = function() return LuaSettings end
G_reader_settings = LuaSettings:open()
G_reader_settings:saveSetting("home_dir", "/kobo")
package.preload["ui/widget/container/widgetcontainer"] = function()
  return { extend = function(_, o) o.new = function(cls, inst) setmetatable(inst, { __index = cls }); if inst.init then inst:init() end; return inst end; return o end }
end
package.preload["gettext"] = function() return function(s) return s end end
rawset(_G, "ALT", { sayi = 0, bekle = false, fd = {}, durdurulan = 0 })
package.preload["ffi/util"] = function()
  return { template = function(s, ...) local p = { ... }; return (s:gsub("%%(%d)", function(i) return tostring(p[tonumber(i)]) end)) end,
           realpath = function(p) return p end,
           runInSubProcess = function(f)
             ALT.sayi = ALT.sayi + 1
             local fd = { veri = "" }
             f(ALT.sayi, fd)
             return ALT.sayi, fd
           end,
           writeToFD = function(fd, s) fd.veri = s end,
           isSubProcessDone = function() return not ALT.bekle end,
           getNonBlockingReadSize = function(fd) return ALT.bekle and 0 or #fd.veri end,
           readAllFromFD = function(fd) local v = fd.veri; fd.veri = ""; return v end,
           terminateSubProcess = function() ALT.durdurulan = ALT.durdurulan + 1 end }
end
-- LuaJIT'in string.buffer'ı yok: tabloyu bir anahtarla sakla
package.preload["string.buffer"] = function()
  local depo, n = {}, 0
  return { encode = function(t) n = n + 1; depo["b" .. n] = t; return "b" .. n end,
           decode = function(s) return depo[s] end }
end
local eylemler = {}
package.preload["dispatcher"] = function() return { registerAction = function(_, ad, t) eylemler[ad] = t end } end
rawset(_G, "EKRAN_YUK", 1200)
package.preload["device"] = function()
  return { home_dir = "/kobo",
    screen = { getWidth = function() return 600 end, getHeight = function() return EKRAN_YUK or 1200 end, scaleBySize = function(_, x) return x end },
    hasKeys = function() return false end, isTouchDevice = function() return true end }
end

-- Ekran (binkitap_ekran) için KOReader arayüz sınıflarının taklidi
local function sinif(ad)
  local C = { _ad = ad }
  function C:extend(o) o = o or {}; setmetatable(o, { __index = self }); return o end
  function C:new(o) o = self:extend(o or {}); o._tur = ad; if o._init then o:_init() end; if o.init then o:init() end; return o end
  function C:getSize() return { w = self.width or (self.dimen and self.dimen.w) or 100, h = self.height or 20 } end
  -- Kapsayıcılar çocuklarını çizer (KOReader gibi)
  function C:paintTo(bb, x, y) for _, w in ipairs(self) do w:paintTo(bb, x, y) end end
  return C
end
-- KOReader'daki gibi ölçüsünü ilk getSize'da önbelleğe alan gruplar: ölçtükten sonra
-- çocuk eklenirse paintTo'da _offsets[i] nil kalır ve çöker.
local function grup(ad, dikey)
  local C = sinif(ad)
  function C:getSize()
    if not self._size then
      self._size = { w = 0, h = 0 }
      self._offsets = {}
      for i, w in ipairs(self) do
        local b = w:getSize()
        self._offsets[i] = dikey and { x = b.w, y = self._size.h } or { x = self._size.w, y = b.h }
        if dikey then
          self._size.h = self._size.h + b.h
          if b.w > self._size.w then self._size.w = b.w end
        else
          self._size.w = self._size.w + b.w
          if b.h > self._size.h then self._size.h = b.h end
        end
      end
    end
    return self._size
  end
  function C:paintTo(bb, x, y)
    self:getSize()
    for i, w in ipairs(self) do
      local o = self._offsets[i]
      if not o then error(ad .. ".paintTo: ölçüldükten sonra eklenen çocuk (" .. i .. ")") end
      w:paintTo(bb, x + (dikey and 0 or o.x), y + (dikey and o.y or 0))
    end
  end
  return C
end
for yol, ad in pairs({
  ["ui/widget/button"] = "Button", ["ui/widget/buttontable"] = "ButtonTable",
  ["ui/widget/container/centercontainer"] = "CenterContainer", ["ui/widget/container/framecontainer"] = "FrameContainer",
  ["ui/widget/horizontalspan"] = "HorizontalSpan",
  ["ui/widget/imagewidget"] = "ImageWidget", ["ui/widget/linewidget"] = "LineWidget",
  ["ui/widget/progresswidget"] = "ProgressWidget", ["ui/widget/textboxwidget"] = "TextBoxWidget",
  ["ui/widget/textwidget"] = "TextWidget", ["ui/widget/titlebar"] = "TitleBar",
  ["ui/widget/verticalspan"] = "VerticalSpan",
}) do
  package.preload[yol] = function() return sinif(ad) end
end
package.preload["ui/widget/verticalgroup"] = function() return grup("VerticalGroup", true) end
package.preload["ui/widget/horizontalgroup"] = function() return grup("HorizontalGroup", false) end
package.preload["ui/widget/container/inputcontainer"] = function()
  local C = sinif("InputContainer")
  function C:_init() self.key_events = self.key_events or {}; self.ges_events = self.ges_events or {} end
  function C:paintTo(bb, x, y) if self[1] then self[1]:paintTo(bb, x, y) end end
  return C
end
package.preload["ui/geometry"] = function() return { new = function(_, o) return o end } end
package.preload["ui/gesturerange"] = function() return { new = function(_, o) return o end } end
package.preload["ui/font"] = function() return { getFace = function(_, ad, boy) return { name = ad, size = boy or 18 } end } end
package.preload["ui/size"] = function()
  return { padding = { fullscreen = 15, small = 2, large = 10 }, border = { thin = 1 }, line = { thick = 2 },
           span = { horizontal_default = 10, vertical_large = 5, vertical_default = 2 } }
end
package.preload["ffi/blitbuffer"] = function() return { COLOR_WHITE = 0, COLOR_DARK_GRAY = 1, COLOR_LIGHT_GRAY = 2 } end

-- dosya sistemi
local FS = {
  ["/kobo"] = { "Walden - Thoreau.epub", "Kafka", "notlar.txt.sdr", ".gizli", "Gog.epub", "resim.jpg" },
  ["/kobo/Kafka"] = { "Donusum.epub", "Bilinmeyen.epub", "Sairin Romani.epub" },
}
local DOSYALAR = {}
local function fsEkle()
  for dizin, adlar in pairs(FS) do
    for _, ad in ipairs(adlar) do
      local yol = dizin .. "/" .. ad
      if not FS[yol] then DOSYALAR[yol] = true end
    end
  end
end
fsEkle()
package.preload["libs/libkoreader-lfs"] = function()
  return {
    mkdir = function(d) return gercek_lfs.mkdir(d) end,
    dir = function(d)
      if d:sub(1, #GERCEK) == GERCEK then return gercek_lfs.dir(d) end
      local adlar = FS[d]
      if not adlar then error("dir yok " .. d) end
      local i = 0
      return function() i = i + 1; return adlar[i] end, nil
    end,
    attributes = function(yol, alan)
      if yol:sub(1, #GERCEK) == GERCEK then return gercek_lfs.attributes(yol, alan) end
      if FS[yol] or yol:match("%.sdr$") then return "directory" end
      if DOSYALAR[yol] then return "file" end
      return nil
    end,
  }
end
local KAPAK_ONBELLEK = {}
package.preload["bookinfomanager"] = function()
  return { getBookInfo = function(_, yol) return KAPAK_ONBELLEK[yol] end }
end
rawset(_G, "KOBO_BELGE", false)   -- Kobo testleri: yol -> sahte belge
package.preload["document/documentregistry"] = function()
  return { hasProvider = function(_, yol) return yol:match("%.epub$") ~= nil or yol:match("%.pdf$") ~= nil end,
           getProvider = function(_, yol) return yol:match("%.epub$") and { provider = "crengine" } or { provider = "mupdf" } end,
           openDocument = function(_, yol) return KOBO_BELGE and KOBO_BELGE(yol) end }
end
local YAN_DOSYALAR = {
  ["/kobo/Walden - Thoreau.epub"] = { doc_props = { title = "Walden", authors = "Henry David Thoreau", identifiers = "uuid:abc\nisbn:978-975-07-5892-8" } },
  ["/kobo/Kafka/Donusum.epub"] = { doc_props = { title = "Dönüşüm", authors = "Franz Kafka" } },
  ["/kobo/Kafka/Bilinmeyen.epub"] = { doc_props = { title = "Hiç Olmayan Kitap", authors = "Kimse" } },
}
package.preload["docsettings"] = function()
  return {
    hasSidecarFile = function(_, yol) return YAN_DOSYALAR[yol] ~= nil end,
    open = function(_, yol)
      local d = YAN_DOSYALAR[yol] or {}
      return {
        readSetting = function(_, k) return d[k] end,
        saveSetting = function(_, k, v) d[k] = v end,
        delSetting = function(_, k) d[k] = nil end,
        has = function(_, k) return d[k] ~= nil end,
        hasNot = function(_, k) return d[k] == nil end,
        makeTrue = function(_, k) d[k] = true end,
        isTrue = function(_, k) return d[k] == true end,
        flush = function() YAN_DOSYALAR[yol] = d; d._yazildi = (d._yazildi or 0) + 1 end,
      }
    end,
    findSidecarFile = function() return nil end,
  }
end
local acilan
package.preload["apps/reader/readerui"] = function() return { showReader = function(_, yol) acilan = yol end } end
local RC = { coll = {}, yazildi = 0 }
function RC:addCollection(ad) self.coll[ad] = {} end
function RC:addItem(yol, ad) self.coll[ad][yol] = { file = yol } end
function RC:isFileInCollection(yol, ad) return self.coll[ad] and self.coll[ad][yol] ~= nil end
function RC:removeItem(yol, ad) self.coll[ad][yol] = nil end
function RC:write() self.yazildi = self.yazildi + 1 end
function RC:removeCollection(ad) self.coll[ad] = nil end
package.preload["readcollection"] = function() return RC end
local FileManager = { file_dialog_added_buttons = nil }
function FileManager:addFileDialogButtons(id, f)
  self.file_dialog_added_buttons = self.file_dialog_added_buttons or { index = {} }
  if self.file_dialog_added_buttons.index[id] == nil then
    table.insert(self.file_dialog_added_buttons, f)
    self.file_dialog_added_buttons.index[id] = #self.file_dialog_added_buttons
  end
end
function FileManager:removeFileDialogButtons(id)
  local idx = self.file_dialog_added_buttons and self.file_dialog_added_buttons.index[id]
  if idx then table.remove(self.file_dialog_added_buttons, idx); self.file_dialog_added_buttons.index[id] = nil end
end
package.preload["apps/filemanager/filemanager"] = function() return FileManager end

-- Kobo Senkron'un kullandığı KOReader parçaları
rawset(_G, "TRAPPER", { bilgi = {}, alt_islem = 0, durdur = false })
package.preload["ui/trapper"] = function()
  return {
    wrap = function(_, f) return f() end,
    info = function(_, m) TRAPPER.bilgi[#TRAPPER.bilgi + 1] = m; return true end,
    clear = function() end,
    dismissableRunInSubprocess = function(_, f, etiket)
      TRAPPER.alt_islem = TRAPPER.alt_islem + 1
      TRAPPER.etiketler = TRAPPER.etiketler or {}
      TRAPPER.etiketler[#TRAPPER.etiketler + 1] = etiket
      if TRAPPER.durdur then return false end
      return true, f()
    end,
  }
end
package.preload["ui/event"] = function() return { new = function(_, ad, a) return { ad = ad, a = a } end } end
package.preload["document/credocument"] = function()
  local cre = { getDomVersionWithNormalizedXPointers = function() return 20240114 end, getLatestDomVersion = function() return 20240114 end }
  return { engineInit = function() return cre end }
end

-- Tanımsız global kullanımı hata versin
setmetatable(_G, { __newindex = function(_, k) error("global atama: " .. tostring(k), 2) end,
                   __index = function(_, k) error("tanımsız global: " .. tostring(k), 2) end })

------------------------------------------------------------------ yardımcılar
local function son(tur)
  for i = #gosterilen, 1, -1 do if gosterilen[i]._tur == tur and not gosterilen[i]._kapandi then return gosterilen[i] end end
end
local function dugme(w, metin)
  for _, satir in ipairs(w.buttons) do for _, b in ipairs(satir) do if b.text == metin or (b.text and b.text:find(metin, 1, true) == 1) then return b end end end
  local t = {}
  for _, satir in ipairs(w.buttons) do for _, b in ipairs(satir) do t[#t + 1] = b.text end end
  error("düğme yok: " .. metin .. " | var: " .. table.concat(t, " / "))
end
local function calistir()
  local n = 0
  while #zamanlanan > 0 do local f = table.remove(zamanlanan, 1); f(); n = n + 1; assert(n < 500, "sonsuz zamanlama") end
end
local function menuSec(menu, kosul)
  for _, it in ipairs(menu.item_table) do
    if kosul(it) then return menu.onMenuSelect(menu, it) end
  end
  error("menü öğesi yok")
end
local hatalar = 0
local function kontrol(kosul, ad)
  print((kosul and "  ✓ " or "  ✗ ") .. ad)
  if not kosul then hatalar = hatalar + 1 end
end

------------------------------------------------------------------ eklenti
local Plugin = dofile(EKLENTI .. "/main.lua")
local Api = Plugin.Api

local function docSettings(veri)
  local d = { data = veri or {} }
  function d:readSetting(k) return self.data[k] end
  function d:saveSetting(k, v) self.data[k] = v end
  function d:flush() end
  return d
end

local function yeniOkuyucu(dosya, props, toplam_sayfa, annotations)
  local ui = {
    menu = { registerToMainMenu = function() end },
    highlight = { addToHighlightDialog = function(this, id, fn) this._dugme = { id = id, fn = fn } end },
    document = {
      file = dosya,
      getPageCount = function() return toplam_sayfa end,
      getPageFromXPointer = function(_, xp) return tonumber(xp:match("DocFragment%[(%d+)%]")) * 20 end,
      getProps = function() return props end,
    },
    doc_settings = docSettings(),
    doc_props = { display_title = props.title, authors = props.authors },
    rolling = true,
    sayfa = 1,
    annotation = { annotations = annotations or {} },
  }
  ui.getCurrentPage = function() return ui.sayfa end
  return ui
end

print("1) Kurulum")
local fm_ui = { menu = { registerToMainMenu = function() end } }
local fm = Plugin:new{ ui = fm_ui }
FileManager.instance = { file_chooser = { path = "/kobo/Kafka" } }
kontrol(eylemler.binkitap_simdi_gonder and eylemler.binkitap_ne_okusam, "hareket eylemleri kaydedildi")
kontrol(FileManager.file_dialog_added_buttons and #FileManager.file_dialog_added_buttons == 1, "dosya menüsü düğmesi eklendi")
fm:kimlikPenceresi()
local kd = son("MultiInputDialog")
kd._alanlar = { OTURUM, CIHAZ, "@ornek_okur" }
dugme(kd, "Kaydet").callback()
kontrol(Api:kimlikVar() and fm.kullanici_adi == "ornek_okur", "hesap ve kullanıcı adı (@ atılarak) kaydedildi")
local fm2 = Plugin:new{ ui = fm_ui }
kontrol(#FileManager.file_dialog_added_buttons == 1, "ikinci örnek düğmeyi çoğaltmadı")
kontrol(fm2.settings == fm.settings, "ayarlar örnekler arasında ortak")

print("2) Okuyucu: ISBN'den sormadan eşleştirme + otomatik Okuyorum")
local okuyucu_ui = yeniOkuyucu("/kobo/Walden - Thoreau.epub",
  { title = "Walden", authors = "Henry David Thoreau", identifiers = "uuid:1\nisbn:978-975-07-5892-8" }, 400)
local p = Plugin:new{ ui = okuyucu_ui }
kontrol(okuyucu_ui.highlight._dugme.id == "12_binkitap", "vurgu menüsü düğmesi")
p:onReaderReady(); calistir()
local k = okuyucu_ui.doc_settings.data.binkitap
kontrol(k and k.id == "359215", "ISBN ile doğru baskı (Can Yayınları) eşleşti")
kontrol(k and k.yayinevi == "Can Yayınları" and k.basili_sayfa == 352, "yayınevi ve basılı sayfa kaydedildi")
kontrol(durum["359215"] == nil and not k.okuyorum_islendi, "açılınca hemen Okuyorum yapılmadı (önce okunmalı)")
for sf = 2, 8 do okuyucu_ui.sayfa = sf; p:onPageUpdate(sf) end; calistir()
kontrol(durum["359215"] == nil, "7 sayfa (%1,75) okununca henüz gönderilmedi")
okuyucu_ui.sayfa = 200; p:onPageUpdate(200); calistir()
kontrol(durum["359215"] == nil, "içindekilerden atlamak okuma sayılmadı")
okuyucu_ui.sayfa = 201; p:onPageUpdate(201); calistir()
kontrol(durum["359215"] == 2 and okuyucu_ui.doc_settings.data.binkitap.okuyorum_islendi, "%2 okununca 1000Kitap'ta Okuyorum yapıldı")
okuyucu_ui.sayfa = 202; p:onPageUpdate(202); okuyucu_ui.sayfa = 1
Plugin.ORTAK.son_etkilesim = nil -- sahte sayfa çevirmeleri arka plan gönderimini bekletmesin
kontrol(fm:dosyaEslesmesi("/kobo/Walden - Thoreau.epub").id == "359215", "eşleşme dosya tarayıcısı için de kaydedildi")

print("3) Aramada yayınevi gösterimi ve önbellek")
local once = istekSay("kitaplar/kitapCek")
p:aramaYap("Dönüşüm", function() end)
local liste = son("ButtonDialog")
local etiketler = {}
for _, satir in ipairs(liste.buttons) do etiketler[#etiketler + 1] = satir[1].text end
kontrol(etiketler[1] == "Dönüşüm — Franz Kafka · İş Bankası, 2015", "etiket: " .. etiketler[1])
kontrol(etiketler[2] == "Dönüşüm — Franz Kafka · Can Yayınları, 2018", "etiket: " .. etiketler[2])
kontrol(etiketler[3] == "Dönüşüm — Ovidius · Kabalcı, 2010", "etiket: " .. etiketler[3])
kontrol(istekSay("kitaplar/kitapCek") - once == 3, "3 sonuç için yayınevi soruldu")
p:aramaYap("Dönüşüm", function() end)
kontrol(istekSay("kitaplar/kitapCek") - once == 3, "ikinci aramada önbellekten geldi")

print("4) Baskı değiştirme (sayfalı liste)")
p:baskiSec()
local bd = son("ButtonDialog")
kontrol(bd.buttons[2][1].text:find("^✓ Walden — Can Yayınları, 2022, 352 sayfa") ~= nil, "mevcut baskı işaretli: " .. bd.buttons[2][1].text)
dugme(bd, "Daha fazla").callback()
bd = son("ButtonDialog")
kontrol(#bd.buttons == 4, "ikinci sayfayla 3 baskı listelendi")
bd.buttons[1][1].callback()
k = okuyucu_ui.doc_settings.data.binkitap
kontrol(k.id == "24319" and k.basili_sayfa == 357 and k.yayinevi == "Zeplin Kitap", "baskı Zeplin olarak değişti")
durum["24319"] = 2

print("5) Alıntı: konu ve yorum izni; özel not")
okuyucu_ui.highlight._dugme.fn({ selected_text = { text = "Ormana gittim.", pos0 = "/body/DocFragment[5]/body/p[3]/text().0" }, onClose = function() end }).callback()
local ap = son("ButtonDialog")
kontrol(ap.title:find("Sayfa: 89", 1, true) ~= nil, "sayfa 100/400*357 ≈ 89")
dugme(ap, "Konu").callback()
local kara = son("InputDialog"); kara._girdi = "felsefe"
dugme(kara, "Ara").callback()
son("ButtonDialog").buttons[1][1].callback()
ap = son("ButtonDialog")
kontrol(ap.title:find("Konu: Felsefe", 1, true) ~= nil, "konu seçildi")
dugme(ap, "Yorumlar").callback()
dugme(son("ButtonDialog"), "○ Hiç kimse").callback()
ap = son("ButtonDialog")
kontrol(ap.title:find("Yorumlar: Hiç kimse", 1, true) ~= nil, "yorum izni seçildi")
dugme(ap, "Gönder").callback(); calistir()
local a = alintilar[#alintilar]
kontrol(a and a.soz == "Ormana gittim." and a.konuId == "24" and a.yorumAyari == "6" and a.kitapid == "24319" and a.sayfa == "89", "alintiEkle: konuId=24, yorumAyari=6")
kontrol(p.settings:readSetting("yorum_ayari") == 6, "yorum izni sonraki alıntılar için hatırlandı")
okuyucu_ui.highlight._dugme.fn({ selected_text = { text = "Gizli düşünce", pos0 = "/body/DocFragment[10]/body/p[1]/text().0" }, onClose = function() end }).callback()
ap = son("ButtonDialog")
dugme(ap, "Not").callback()
local nd = son("InputDialog"); nd._girdi = "bana not"
dugme(nd, "Tamam").callback()
dugme(son("ButtonDialog"), "Gizli yap").callback()
ap = son("ButtonDialog")
kontrol(ap.title:find("Gizli: yalnızca sen görürsün", 1, true) ~= nil, "gizli modu")
dugme(ap, "Gönder").callback(); calistir()
local n = notlar[#notlar]
kontrol(n and n.hedefTuru == "kitap" and n.hedefId == "24319" and n["not"] == "“Gizli düşünce” (s. 179)\n\nbana not" and #n.notAnahtari == 16 and n.surum == "0" and n.notId == "", "not-ayarla gövdesi doğru")

print("6) Renkle otomatik gönderim")
p.settings:saveSetting("renk_eylemleri", { yellow = "alinti", blue = "ozel" })
local ann = okuyucu_ui.annotation.annotations
ann[#ann + 1] = { datetime = "2001-01-01 10:00:00", drawer = "lighten", color = "yellow", text = "eski vurgu", page = "/body/DocFragment[3]/body/p[1]/text().0" }
local onceki_alinti = #alintilar
ilerlet(5)
ann[#ann + 1] = { datetime = os.date("%Y-%m-%d %H:%M:%S", saat + 3600), drawer = "lighten", color = "yellow", text = "yeni sarı", page = "/body/DocFragment[6]/body/p[1]/text().0" }
ann[#ann + 1] = { datetime = os.date("%Y-%m-%d %H:%M:%S", saat + 3601), drawer = "lighten", color = "blue", text = "yeni mavi", note = "n", page = "/body/DocFragment[7]/body/p[1]/text().0" }
ann[#ann + 1] = { datetime = os.date("%Y-%m-%d %H:%M:%S", saat + 3602), drawer = "lighten", color = "red", text = "kırmızı", page = "/body/DocFragment[8]/body/p[1]/text().0" }
local onceki_not = #notlar
p:onAnnotationsModified(); calistir()
kontrol(#alintilar == onceki_alinti + 1 and alintilar[#alintilar].soz == "yeni sarı", "sarı vurgu alıntı olarak gitti, eski vurgu gitmedi")
kontrol(#notlar == onceki_not + 1 and notlar[#notlar]["not"]:find("yeni mavi", 1, true), "mavi vurgu özel not olarak gitti")
p:onAnnotationsModified(); calistir()
kontrol(#alintilar == onceki_alinti + 1, "aynı vurgu ikinci kez gönderilmedi")

print("7) Vurguları seçerek gönder")
ann[#ann + 1] = { datetime = "2001-01-02 10:00:00", drawer = "lighten", color = "red", text = "elle bir", page = "/body/DocFragment[9]/body/p[1]/text().0" }
p:topluGonder()
local tg = son("ButtonDialog")
kontrol(tg.title:find("gönderilmemiş 3 vurgu", 1, true) ~= nil, "3 gönderilmemiş vurgu: " .. tg.title)
dugme(tg, "Seçerek gönder").callback()
local menu = son("Menu")
menuSec(menu, function(it) return it.text and it.text:find("elle bir", 1, true) end)
kontrol(menu.item_table[1].text == "Seçilenleri gönder (1)", "sayaç güncellendi")
onceki_alinti = #alintilar
menuSec(menu, function(it) return it.eylem == "onay" end)
dugme(son("ButtonDialog"), "Herkese açık alıntı").callback(); calistir()
kontrol(#alintilar == onceki_alinti + 1 and alintilar[#alintilar].soz == "elle bir", "sadece seçilen gönderildi")
p:topluGonder()
kontrol(son("ButtonDialog").title:find("gönderilmemiş 2 vurgu", 1, true) ~= nil, "gönderilen tekrar sayılmadı")
dugme(son("ButtonDialog"), "Vazgeç").callback()

print("8) İlerleme her %10'da ve okuma seansı")
p.settings:saveSetting("ilerleme_modu", "yuzde10")
p.settings:saveSetting("seans_kaydi", true)
p:seansBaslat()
okuyucu_ui.sayfa = 30; ilerlet(100); p:onPageUpdate(); calistir()
kontrol(sayfa2["24319"] == nil, "%7.5'te ilerleme gönderilmedi")
okuyucu_ui.sayfa = 45; ilerlet(100); p:onPageUpdate(); calistir()
kontrol(sayfa2["24319"] == 40, "%11'de sayfa 40/357 gönderildi (" .. tostring(sayfa2["24319"]) .. ")")
okuyucu_ui.sayfa = 50; ilerlet(1000); p:onPageUpdate(); calistir()
kontrol(sayfa2["24319"] == 40, "aynı dilimde tekrar gönderilmedi")
ilerlet(40)
local onceki_seans = #seanslar
p:onSuspend()
-- 100+100+300(üst sınır)+40 = 540 sn
kontrol(#seanslar == onceki_seans + 1 and #p:kuyruk() == 0, "uykuya geçerken seans hemen gönderildi")
calistir()
local s = seanslar[#seanslar]
kontrol(s and s.okumaId == "OK24319" and s.sureSaniye == "540" and s.bitisSayfasi == "45" and s.istemciKodu:match("^W2%-%w+$") and #s.istemciKodu == 15, "seansTamamla: 540 sn, sayfa 45")
p:onResume()
ilerlet(30); p:onCloseDocument(); calistir()
kontrol(#seanslar == onceki_seans + 1, "1 dakikadan kısa seans gönderilmedi")

print("9) KOReader durum senkronu")
okuyucu_ui.doc_settings.data.summary = { status = "reading" }
p:koDurumuKontrol()
kontrol(okuyucu_ui.doc_settings.data.binkitap.son_ko_durum == "reading", "ilk görüş sadece kaydedildi")
okuyucu_ui.doc_settings.data.summary = { status = "abandoned" }
p:onCloseDocument(); calistir()
kontrol(durum["24319"] == 3, "Beklemede → Yarım bıraktım")

print("10) Bitiş ekranı: Okudum + puan + inceleme")
p:onEndOfBook()
local be = son("ButtonDialog")
dugme(be, "Puan ver").callback()
dugme(son("ButtonDialog"), "8").callback()
dugme(son("ButtonDialog"), "İnceleme yaz").callback()
local ig = son("InputDialog"); ig._girdi = "  Güzel kitap. "
dugme(ig, "Tamam").callback()
be = son("ButtonDialog")
kontrol(be.title:find("Puan: 8", 1, true) and be.title:find("İnceleme: Güzel kitap.", 1, true), "bitiş ekranı özeti")
dugme(be, "Kaydet").callback(); calistir()
kontrol(durum["24319"] == 1 and puan["24319"] == 8, "Okudum ve puan 8")
local inc = incelemeler[#incelemeler]
kontrol(inc and inc.q.kitapId == "24319" and inc.q.id == "24319" and inc.form.inceleme == "Güzel kitap." and inc.form.isYeni == "1" and inc.form.kitapYeniKonuAdlari == "[]" and inc.form.yorumAyari == "6", "kitapIncelemeKaydet doğru")
p:onEndOfBook()
kontrol(son("ButtonDialog") == nil or son("ButtonDialog") ~= be, "bitiş ekranı ikinci kez açılmadı")
okuyucu_ui.doc_settings.data.summary = { status = "complete" }
local oku_once = istekSay("kitaplar/kitapOku")
p:koDurumuKontrol(); calistir()
kontrol(istekSay("kitaplar/kitapOku") == oku_once, "zaten Okudum: tekrar gönderilmedi (toggle riski yok)")

print("11) Dosya menüsü (uzun basma)")
local row = FileManager.file_dialog_added_buttons[1]("/kobo/Kafka/Donusum.epub", true, nil)
kontrol(row and row[1].text == "1000Kitap", "kitap dosyasında düğme var")
kontrol(FileManager.file_dialog_added_buttons[1]("/kobo/resim.jpg", true, nil) == nil, "resimde düğme yok")
FileManager.instance.file_chooser.file_dialog = { _tur = "fd" }
row[1].callback()
kontrol(FileManager.instance.file_chooser.file_dialog._kapandi, "uzun basma penceresi kapatıldı")
local dm = son("ButtonDialog")
kontrol(dm.title:find("eşleşmedi", 1, true) ~= nil, "eşleşmemiş görünüyor")
dugme(dm, "Okuyacağım").callback()
local ara = son("InputDialog")
kontrol(ara.input == "Dönüşüm Franz Kafka", "dosyadaki bilgilerle arama: " .. ara.input)
dugme(ara, "Ara").callback()
son("ButtonDialog").buttons[2][1].callback(); calistir()
kontrol(fm:dosyaEslesmesi("/kobo/Kafka/Donusum.epub").id == "701" and durum["701"] == 0, "Can baskısı eşleşti ve Okuyacağım yapıldı")

print("12) Toplu Okuyacağım (seçili dosyalar)")
durum["800"] = 1 -- Gog zaten okunmuş
FileManager.instance.selected_files = { ["/kobo/Gog.epub"] = true, ["/kobo/Kafka/Bilinmeyen.epub"] = true, ["/kobo/Kafka/Sairin Romani.epub"] = true, ["/kobo/resim.jpg"] = true }
fm:topluOkuyacagim(); calistir()
local bl = son("Menu")
kontrol(bl.title == "Emin olunamayan kitaplar", "belirsizler listesi açıldı")
kontrol(#bl.item_table == 2 and bl.item_table[2].text == "Bilinmeyen.epub", "sadece bulunamayan kitap belirsiz")
kontrol(fm:dosyaEslesmesi("/kobo/Gog.epub").id == "800" and fm:dosyaEslesmesi("/kobo/Kafka/Sairin Romani.epub").id == "801", "dosya adından (Türkçe karaktersiz) eşleşti")
menuSec(bl, function(it) return it.yol end)
local aw = son("InputDialog"); aw._girdi = "Kaos Lordu"
dugme(aw, "Ara").callback()
son("ButtonDialog").buttons[1][1].callback()
kontrol(bl.item_table[1].text:find("Devam: 3 kitabı", 1, true) ~= nil, "seçim sonrası liste: " .. bl.item_table[1].text)
menuSec(bl, function(it) return it.eylem == "devam" end); calistir()
kontrol(durum["801"] == 0 and durum["9517"] == 0, "boş durumdakiler Okuyacağım oldu")
kontrol(durum["800"] == 1, "okunmuş kitaba dokunulmadı")
FileManager.instance.selected_files = nil

print("13) Kütüphaneyi eşleştir (durdur, devam, gözden geçir)")
local eslesmeler = fm.settings:readSetting("eslesmeler")
eslesmeler["/kobo/Gog.epub"] = nil
eslesmeler["/kobo/Kafka/Bilinmeyen.epub"] = nil
fm:kutuphaneEslestir()
local cb = son("ConfirmBox")
kontrol(cb.text:find("5 kitap var; 2 tanesi", 1, true) ~= nil, "doğru sayım: " .. cb.text:gsub("\n.*", ""))
cb.ok_callback()
local ilk = son("InfoMessage")
kontrol(ilk.text:find("0 / 2", 1, true) == nil and ilk.text:find("Durdurmak için dokun", 1, true), "ilerleme gösterildi")
ilk.dismiss_callback()
calistir()
kontrol(son("InfoMessage").text:find("Durduruldu", 1, true) ~= nil, "durduruldu bildirimi")
fm:kutuphaneEslestir()
kontrol(son("ConfirmBox").text:find("1 tanesi", 1, true) ~= nil, "kaldığı yerden: 1 kitap kaldı")
son("ConfirmBox").ok_callback(); calistir()
local oz = son("ConfirmBox")
kontrol(oz.text:find("1 kitap için seçim gerekli", 1, true) ~= nil, "özet: " .. oz.text:gsub("\n", " / "))
oz.ok_callback()
local gl = son("Menu")
menuSec(gl, function(it) return it.yol end)
dugme(son("InputDialog"), "Vazgeç").callback()
kontrol(fm:belirsizSayisi() == 1, "vazgeçince listede kaldı")
fm:kutuphaneEslestir()
kontrol(son("ConfirmBox").text:find("1 kitap için seçim bekliyor", 1, true) ~= nil, "tekrar çalıştırınca bekleyeni söyledi")

print("14) Ne okusam?")
DOSYALAR["/kobo/Gog.epub"] = true
fm:neOkusam()
kontrol(son("InfoMessage").text:find("Okuyacakların getiriliyor", 1, true) ~= nil, "okuyacaklar sayfa sayfa getiriliyor")
calistir()
local no = son("ButtonDialog")
kontrol(no.title:find("(3 / 4)", 1, true) ~= nil, "4 kitaptan 3'ü Kobo'da: " .. no.title:gsub("\n", " / "))
local cihazda = 0
for _, satir in ipairs(no.buttons) do if satir[1].text:find("^✓ ") then cihazda = cihazda + 1 end end
kontrol(cihazda == 3, "Kobo'dakiler işaretli")
for _, satir in ipairs(no.buttons) do if satir[1].text:find("Gog", 1, true) then satir[1].callback() end end
kontrol(acilan == "/kobo/Gog.epub", "seçilen kitap açıldı")
local raf_once = istekSay("uyeler/kitaplar/liste")
fm:neOkusam()
kontrol(istekSay("uyeler/kitaplar/liste") == raf_once, "liste önbellekten geldi")

print("15) Okuyacaklarım koleksiyonu")
RC.coll["1000Kitap – Okuyacaklarım"] = { ["/kobo/eski.epub"] = { file = "/kobo/eski.epub" } }
fm:koleksiyonGuncelle()
calistir()
local kol = RC.coll["1000Kitap – Okuyacaklarım"]
kontrol(kol["/kobo/Gog.epub"] and kol["/kobo/Kafka/Sairin Romani.epub"] and kol["/kobo/Kafka/Donusum.epub"] and not kol["/kobo/eski.epub"], "koleksiyon güncellendi, eski kitap çıkarıldı")
kontrol(RC.yazildi == 1 and son("InfoMessage").text:find("3 kitap eklendi, 1 kitap çıkarıldı", 1, true), "özet: " .. son("InfoMessage").text:gsub("\n", " / "))

print("16) Kitap bilgisi, popüler alıntılar, hedef")
p:kitapKarti()
local tv = son("TextViewer")
kontrol(tv.text:find("Zeplin Kitap · 2019 · 357 sayfa", 1, true) and tv.text:find("7.8/10 (596 kişi)", 1, true)
  and tv.text:find("Senin durumun: Okudum", 1, true) and tv.text:find("Puanın: 8", 1, true)
  and tv.text:find("okuyanlar: Gökhan, Ece", 1, true), "bilgi kartı içeriği")
p:populerAlintilar()
tv = son("TextViewer")
kontrol(tv.text:find("“Kim bilir kaç insan bir kitabı okuyup...”\n— Ersin Yaman · 489 beğeni · s. 12", 1, true) and tv.text:find("İkinci alıntı", 1, true), "popüler alıntılar")
local hm = fm:hedefMenusu()
hm[1].callback()
kontrol(son("InfoMessage").text:find("okuma hedefin yok", 1, true) ~= nil, "hedef yok mesajı")
hm[2].callback()
local hd = son("InputDialog"); hd._girdi = "30"
dugme(hd, "Kaydet").callback()
local yil = os.date("%Y")
kontrol(hedefler[yil] == 30 and sonIstek("diger/okumaHedefiKaydet").form.verilerimBen == "1", "hedef kaydedildi")
hm[1].callback()
kontrol(hm[1].text_func():find(yil .. " hedefi: 4 / 30 kitap", 1, true) ~= nil, "hedef göstergesi: " .. hm[1].text_func())

print("17) Uyku ekranında alıntı")
G_reader_settings:saveSetting("screensaver_message", "Uyuyorum")
fm:uykuAc()
kontrol(G_reader_settings:readSetting("screensaver_show_message") == true, "uyku mesajı açıldı")
local msj = G_reader_settings:readSetting("screensaver_message")
kontrol(msj == "“Alıntı 1 ％50”" or msj == "“Alıntı 2 ％50”", "mesaj alıntılardan biri ve % güvenli: " .. msj)
fm:uykuKapat()
kontrol(G_reader_settings:readSetting("screensaver_message") == "Uyuyorum" and G_reader_settings:readSetting("screensaver_show_message") == nil, "kapatınca eski ayarlar geri geldi")
fm:uykuAc()
fm:uykuHedefAc(); calistir()
msj = G_reader_settings:readSetting("screensaver_message")
kontrol(msj:find("^“Alıntı %d ％50”\n\n" .. yil .. " hedefi: 4 / 30 kitap$") ~= nil, "alıntı + hedef satırı: " .. msj:gsub("\n", " / "))
fm:uykuKapat("alinti")
kontrol(G_reader_settings:readSetting("screensaver_message") == yil .. " hedefi: 4 / 30 kitap", "alıntı kapanınca yalnız hedef kaldı")
fm:uykuKapat("hedef")
kontrol(G_reader_settings:readSetting("screensaver_message") == "Uyuyorum" and G_reader_settings:readSetting("screensaver_show_message") == nil, "ikisi de kapanınca eski ayarlar geri geldi")

print("18) İhtiyaç anında Wi-Fi ve ortak kilit")
p.settings:saveSetting("otomatik_wifi", true)
network.online = false; ag_acik = false
p:siraya({ tur = "puan", kitap_id = "9517", kitap_adi = "Kaos Lordu", puan = 9 })
p:onCloseDocument(); calistir()
kontrol(network.wifi_acildi == 1 and network.wifi_kapandi == 1 and puan["9517"] == 9, "Wi-Fi açıldı, gönderildi, kapandı")
network.online = true; ag_acik = true
local once_puan = istekSay("kitaplar/kitapPuanVer")
p:siraya({ tur = "puan", kitap_id = "9517", kitap_adi = "Kaos Lordu", puan = 7 })
p:siraya({ tur = "puan", kitap_id = "700", kitap_adi = "Dönüşüm", puan = 6 })
p:kuyruguGonder(true)
fm:kuyruguGonder(true)
calistir()
kontrol(istekSay("kitaplar/kitapPuanVer") - once_puan == 2, "iki örnek aynı anda göndermeye çalışınca tekrar yok")

print("19) Oturum düşerse sıra korunur")
Api.oturum_kodu = "SURESI-DOLMUS"
p:siraya({ tur = "durum", kitap_id = "700", kitap_adi = "Dönüşüm", durum = 2 })
p:kuyruguGonder(true); calistir()
kontrol(#p:kuyruk() == 1 and son("InfoMessage").text:find("giriş yapınız", 1, true), "sırada kaldı, uyarıldı")
Api.oturum_kodu = OTURUM
p:kuyruguGonder(false); calistir()
kontrol(#p:kuyruk() == 0 and durum["700"] == 2, "kod düzelince gönderildi")

print("21) Renk sonradan açılınca eski vurgular gitmez")
local ann2 = okuyucu_ui.annotation.annotations
ilerlet(600)
ann2[#ann2 + 1] = { datetime = os.date("%Y-%m-%d %H:%M:%S", saat - 300), drawer = "lighten", color = "green", text = "yeşil eski", page = "/body/DocFragment[11]/body/p[1]/text().0" }
local rm = p:renkMenusu()
local yesil
for _, o in ipairs(rm) do if o.text_func():find("^Yeşil") then yesil = o end end
for _, alt in ipairs(yesil.sub_item_table) do if alt.text == "Herkese açık alıntı" then alt.callback() end end
kontrol(yesil.text_func() == "Yeşil: herkese açık alıntı", "menü: " .. yesil.text_func())
ilerlet(5)
ann2[#ann2 + 1] = { datetime = os.date("%Y-%m-%d %H:%M:%S", saat + 1), drawer = "lighten", color = "green", text = "yeşil yeni", page = "/body/DocFragment[12]/body/p[1]/text().0" }
ilerlet(5)
local once_y = #alintilar
p:onAnnotationsModified(); calistir()
kontrol(#alintilar == once_y + 1 and alintilar[#alintilar].soz == "yeşil yeni", "sadece renk açıldıktan sonraki vurgu gitti")

print("22) Gözden geçirmede adaylar yayınevleriyle")
fm:belirsizListesi({ ["/kobo/x.epub"] = { sorgu = "Dönüşüm", baslik = "Dönüşüm",
  adaylar = { { id = "701", adi = "Dönüşüm", yazar = "Franz Kafka" }, { id = "702", adi = "Dönüşüm", yazar = "Ovidius" } } } }, function() end)
menuSec(son("Menu"), function(it) return it.yol end)
local adl = son("ButtonDialog")
kontrol(adl.buttons[1][1].text == "Dönüşüm — Franz Kafka · Can Yayınları, 2018" and adl.buttons[2][1].text == "Dönüşüm — Ovidius · Kabalcı, 2010", "adaylar: " .. adl.buttons[1][1].text .. " / " .. adl.buttons[2][1].text)
kontrol(dugme(adl, "Atla") ~= nil, "Atla düğmesi var")


print("23) Atlananlar listesi")
local bel = fm:kutuphaneBelirsizleri()
kontrol(bel["/kobo/Kafka/Bilinmeyen.epub"] ~= nil, "Bilinmeyen.epub gözden geçirmede bekliyor")
fm:kutuphaneGozdenGecir()
menuSec(son("Menu"), function(it) return it.yol == "/kobo/Kafka/Bilinmeyen.epub" end)
local ap = son("InputDialog")
kontrol(ap ~= nil, "aday yoksa arama penceresi açıldı")
-- arama sonucunda Atla düğmesi yok; adaylı akışı taklit et
fm.settings:saveSetting("kutuphane_belirsiz", { ["/kobo/Kafka/Bilinmeyen.epub"] = { sorgu = "Kaos", baslik = "Hiç Olmayan Kitap",
  adaylar = { { id = "9517", adi = "Kaos Lordu", yazar = "Robert Jordan", yayinevi = "İthaki" } }, yayinevi_eklendi = true } })
fm:kutuphaneGozdenGecir()
menuSec(son("Menu"), function(it) return it.yol == "/kobo/Kafka/Bilinmeyen.epub" end)
dugme(son("ButtonDialog"), "Atla").callback()
kontrol(fm:atlananSayisi() == 1 and fm:belirsizSayisi() == 0, "atlanan listeye geçti")
local mo = fm:menuOgeleri()
local atl_oge
for _, o in ipairs(mo) do if o.text_func and o.text_func():find("^Atlananlar") then atl_oge = o end end
kontrol(atl_oge.text_func() == "Atlananlar (1)" and atl_oge.enabled_func(), "menüde sayı: " .. atl_oge.text_func())
atl_oge.callback()
local al = son("Menu")
kontrol(al.title == "Atlanan kitaplar" and al.item_table[1].text == "Hepsini tekrar taramaya al"
  and al.item_table[2].text == "Bilinmeyen.epub" and al.item_table[2].mandatory == "Kafka", "liste: dosya adı + klasör")
menuSec(al, function(it) return it.yol end)
dugme(son("ButtonDialog"), "Tekrar taramaya al").callback()
kontrol(fm:atlananSayisi() == 0 and al.item_table[1].text == "Atlanan kitap kalmadı.", "tekrar taramaya alındı, liste yenilendi")
fm:kutuphaneEslestir()
kontrol(son("ConfirmBox").text:find("1 tanesi", 1, true) ~= nil, "kütüphane taramasında yine aranacak")
son("ConfirmBox").ok_callback(); calistir()
son("ConfirmBox").ok_callback()
menuSec(son("Menu"), function(it) return it.yol end)
-- aday yok: arama penceresinde Vazgeç; doğrudan atla
fm.settings:saveSetting("kutuphane_belirsiz", {})
fm.settings:saveSetting("kutuphane_atlanan", { ["/kobo/Kafka/Bilinmeyen.epub"] = true, ["/kobo/silinmis.epub"] = true })
fm:atlananlarListesi()
al = son("Menu")
menuSec(al, function(it) return it.eylem == "hepsi" end)
son("ConfirmBox").ok_callback()
kontrol(fm:atlananSayisi() == 0, "hepsi tekrar taramaya alındı")
fm.settings:saveSetting("kutuphane_atlanan", { ["/kobo/Kafka/Bilinmeyen.epub"] = true })
fm:atlananlarListesi()
al = son("Menu")
menuSec(al, function(it) return it.yol end)
dugme(son("ButtonDialog"), "Şimdi eşleştir").callback()
local sa = son("InputDialog"); sa._girdi = "Kaos Lordu"
dugme(sa, "Ara").callback()
son("ButtonDialog").buttons[1][1].callback()
kontrol(fm:dosyaEslesmesi("/kobo/Kafka/Bilinmeyen.epub").id == "9517" and fm:atlananSayisi() == 0, "eşleştirilince atlananlardan çıktı")
kontrol(al.item_table[1].text == "Atlanan kitap kalmadı.", "liste yenilendi")

print("24) Kobo'daki kitapları 1000Kitap kitaplığına ekle")
local esl = fm.settings:readSetting("eslesmeler")
esl["/kobo/eski-silinmis.epub"] = { id = "900", adi = "Yaşam Yolu 1", yazar = "Anton Makarenko" }
local km = fm:kitaplikMenusu()
kontrol(#km == 2, "dosya tarayıcısında sadece toplu öğeler")
km[1].callback()
local kl = son("Menu")
kontrol(kl.title == "Kitaplığa ekle", "seçim listesi açıldı")
kontrol(kl.item_table[1].eylem == "bilgi" and kl.item_table[1].text:find("1 tanesi zaten kitaplığında, 1 tanesinin başka baskısı var", 1, true) ~= nil,
  "bilgi: " .. kl.item_table[1].text)
local adlar = {}
for _, it in ipairs(kl.item_table) do if it.indeks then adlar[#adlar + 1] = it.text end end
kontrol(#adlar == 3, "eklenebilecek 3 kitap: " .. table.concat(adlar, " / "))
local hic_secili = true
for _, it in ipairs(kl.item_table) do if it.indeks and it.text:find("^☑") then hic_secili = false end end
kontrol(hic_secili, "varsayılan olarak hiçbiri seçili değil")
local walden_yok, donusum_yok, silinmis_yok = true, true, true
for _, a in ipairs(adlar) do
  if a:find("Walden", 1, true) then walden_yok = false end
  if a:find("Dönüşüm", 1, true) then donusum_yok = false end
  if a:find("Yaşam Yolu", 1, true) then silinmis_yok = false end
end
kontrol(walden_yok and donusum_yok and silinmis_yok, "kitaplıktakiler, başka baskısı olan ve silinmiş dosya listede yok")
menuSec(kl, function(it) return it.eylem == "bilgi" end)
kontrol(not kl._kapandi, "bilgi satırına dokunmak bir şey yapmadı")
menuSec(kl, function(it) return it.text and it.text:find("Gog", 1, true) end)
menuSec(kl, function(it) return it.text and it.text:find("Kaos Lordu", 1, true) end)
kontrol(kl.item_table[2].text == "Seçilenleri kitaplığa ekle (2)", "onay: " .. kl.item_table[2].text)
menuSec(kl, function(it) return it.eylem == "onay" end); calistir()
kontrol(kitaplikta("800") and kitaplikta("9517") and not kitaplikta("801"), "seçilen 2 kitap eklendi")
kontrol(sonIstek("kitaplar/kitapKutuphanemeEkle").q.forceEkle == "1", "ekleme zorla-ekle ile gitti")
kontrol(son("InfoMessage").text:find("2 kitap kitaplığına eklendi", 1, true) ~= nil, "özet: " .. son("InfoMessage").text)
esl["/kobo/eski-silinmis.epub"] = nil

print("25) 1000Kitap kitaplığından çıkar")
km[2].callback()
local cl = son("Menu")
kontrol(cl.title == "Kitaplığından çıkar" and cl.item_table[1].text:find("Kobo'da olmayan basılı", 1, true), "liste ve uyarı")
local shen, gog
for _, it in ipairs(cl.item_table) do
  if it.text and it.text:find("Shenzen", 1, true) then shen = it end
  if it.text and it.text:find("Gog", 1, true) then gog = it end
end
kontrol(shen and shen.mandatory == nil and gog and gog.mandatory == "Kobo'da", "Kobo'dakiler işaretli, basılı kitap değil")
menuSec(cl, function(it) return it.text and it.text:find("Gog", 1, true) end)
menuSec(cl, function(it) return it.eylem == "onay" end)
local ec = son("ConfirmBox")
kontrol(ec.text:find("1 kitap 1000Kitap kitaplığından çıkarılacak", 1, true) ~= nil, "onay soruldu")
-- bu arada sitede elle çıkarılmış olsun
local eski_kitaplik = #KITAPLIK
for i = #KITAPLIK, 1, -1 do if KITAPLIK[i] == "800" then table.remove(KITAPLIK, i) end end
local once_degistir = istekSay("kitaplar/kitapKutuphanemeEkle")
ec.ok_callback(); calistir()
kontrol(istekSay("kitaplar/kitapKutuphanemeEkle") == once_degistir and not kitaplikta("800"),
  "zaten kitaplıkta değilse değiştir isteği gönderilmedi (tekrar eklenmedi)")
kontrol(son("InfoMessage").text:find("zaten kitaplığında değildi", 1, true) ~= nil, "bildirildi: " .. son("InfoMessage").text)
km[2].callback()
cl = son("Menu")
menuSec(cl, function(it) return it.text and it.text:find("Kaos Lordu", 1, true) end)
menuSec(cl, function(it) return it.eylem == "onay" end)
son("ConfirmBox").ok_callback(); calistir()
kontrol(not kitaplikta("9517") and kitaplikta("92807") and kitaplikta("24319"), "sadece seçilen çıkarıldı, basılı kitap yerinde")
kontrol(sonIstek("kitaplar/kitapKutuphanemeEkle").q.forceEkle == "0", "çıkarma değiştir isteğiyle gitti")

print("26) Okuyucu ve uzun basma menüsünden tek kitap")
local rkm = p:kitaplikMenusu()
kontrol(#rkm == 4 and rkm[1].text == "Bu kitabı kitaplığa ekle", "okuyucuda tek kitap öğeleri var")
local acik = p:kitapBilgisi()
rkm[2].callback(); calistir()
kontrol(not kitaplikta(acik.id), "açık kitap (" .. acik.adi .. ") kitaplıktan çıkarıldı")
rkm[1].callback(); calistir()
kontrol(kitaplikta(acik.id), "tekrar eklendi")
local row2 = FileManager.file_dialog_added_buttons[1]("/kobo/Kafka/Sairin Romani.epub", true, nil)
row2[1].callback()
dugme(son("ButtonDialog"), "Kitaplığa ekle").callback(); calistir()
kontrol(kitaplikta("801"), "uzun basmadan eklendi")
row2[1].callback()
dugme(son("ButtonDialog"), "Kitaplıktan çıkar").callback(); calistir()
kontrol(not kitaplikta("801"), "uzun basmadan çıkarıldı")

print("27) Ayar açıkken eşleşen kitap otomatik eklenir, değişince eskisi çıkar")
fm.settings:saveSetting("kitapliga_ekle", true)
fm:eslesmeKaydet("/kobo/Kafka/Donusum.epub", { id = "702", adi = "Dönüşüm", yazar = "Ovidius" })
fm:kuyruguGonder(true); calistir()
kontrol(kitaplikta("702"), "eşleşen kitap otomatik eklendi")
fm:eslesmeKaydet("/kobo/Kafka/Donusum.epub", { id = "701", adi = "Dönüşüm", yazar = "Franz Kafka" })
local turler = {}
for _, o in ipairs(fm:kuyruk()) do turler[#turler + 1] = o.tur .. ":" .. o.kitap_id end
kontrol(table.concat(turler, ",") == "kitaplik_cikar:702,kitaplik_ekle:701", "sıra: " .. table.concat(turler, ","))
fm:kuyruguGonder(true); calistir()
kontrol(kitaplikta("701") and not kitaplikta("702"), "eklentinin eklediği eski baskı çıktı, yenisi eklendi")
-- kullanıcının zaten kitaplığında olan (basılı) baskıya dokunulmamalı
fm:eslesmeKaydet("/kobo/Gog.epub", { id = "92807", adi = "Shenzen", yazar = "Guy Delisle" })
fm:kuyruguGonder(true); calistir()
fm:eslesmeKaydet("/kobo/Gog.epub", { id = "800", adi = "Gog", yazar = "Giovanni Papini" })
local once_bilgi = #gosterilen
fm:kuyruguGonder(true); calistir()
kontrol(kitaplikta("92807") and kitaplikta("800"), "önceden kitaplıkta olan Shenzen yanlış eşleşme düzelince silinmedi")
local ses = true
for i = once_bilgi + 1, #gosterilen do if gosterilen[i].text and gosterilen[i].text:find("değildi", 1, true) then ses = false end end
kontrol(ses, "otomatik atlamalar için gereksiz bildirim yok")
fm:eslesmeKaydet("/kobo/Kafka/Donusum.epub", { id = "701", adi = "Dönüşüm", yazar = "Franz Kafka" })
kontrol(#fm:kuyruk() == 0, "aynı eşleşme tekrar kaydedilince bir şey gönderilmedi")
fm.settings:saveSetting("kitapliga_ekle", nil)


do
print("28) GitHub'dan güncelleme")
local G = Plugin._guncelleme
kontrol(Plugin.SURUM == "1.3.11", "sürüm _meta.lua'dan okundu: " .. tostring(Plugin.SURUM))
kontrol(G.dahaYeni("1.2.30", "1.2.9") and G.dahaYeni("1.3", "1.2.9") and not G.dahaYeni("1.3.14", "1.3.14")
  and not G.dahaYeni("1.3.13", "1.3.14"), "sürüm karşılaştırma sayıyla yapılıyor")
local ayar_ogeleri = fm:ayarlarMenusu()
local gun_oge, oto_oge
for _, o in ipairs(ayar_ogeleri) do
  if o.text and o.text:find("^Güncellemeleri denetle") then gun_oge = o end
  if o.text == "Haftada bir kendiliğinden denetle" then oto_oge = o end
end
kontrol(gun_oge and gun_oge.text == "Güncellemeleri denetle (sürüm 1.3.11)" and oto_oge and oto_oge.checked_func(),
  "ayarlarda denetle düğmesi ve varsayılan açık haftalık denetim")

local DIZ = GERCEK .. "/binkitap.koplugin"
gercek_lfs.mkdir(GERCEK); gercek_lfs.mkdir(DIZ)
local function yaz(yol, m) local h = assert(io.open(yol, "wb")); h:write(m); h:close() end
local function oku(yol) local h = io.open(yol, "rb"); if not h then return nil end; local m = h:read("*a"); h:close(); return m end
yaz(DIZ .. "/main.lua", "-- eski main\n")
yaz(DIZ .. "/_meta.lua", 'return { version = "1.3.11" }\n')
yaz(DIZ .. "/ayar.lua", 'return { oturum_kodu = "GIZLI" }\n')
fm.path = DIZ

local DEPO_KOK = "kurabiyedelisi/binkitap.koplugin"
local REF = "https://api.github.com/repos/" .. DEPO_KOK .. "/git/ref/heads/main"
local function hamAdres(ref) return "https://raw.githubusercontent.com/" .. DEPO_KOK .. "/" .. ref .. "/binkitap.koplugin/" end
local function listeAdres(ref) return "https://api.github.com/repos/" .. DEPO_KOK .. "/contents/binkitap.koplugin?ref=" .. ref end
local HAM = hamAdres("main")       -- dal adresleri (önbelleğe takılabilen)
local depo = { sayac = 0 }          -- depo.ham: son commit'in adresleri
-- Hem commit'e sabit hem dal adreslerine aynı dosyaları koyar.
local function depoKur(surum, dosyalar, bozuk)
  depo.sayac = depo.sayac + 1
  depo.sha = string.format("%040x", 0xabc000 + depo.sayac)
  depo.ham = hamAdres(depo.sha)
  GITHUB[REF] = encode({ ref = "refs/heads/main", object = { type = "commit", sha = depo.sha } })
  dosyalar["_meta.lua"] = 'return { version = "' .. surum .. '" }\n'
  local adlar, liste = {}, {}
  for ad in pairs(dosyalar) do adlar[#adlar + 1] = ad end
  table.sort(adlar)
  for _, ad in ipairs(adlar) do
    GITHUB[depo.ham .. ad] = dosyalar[ad]
    GITHUB[HAM .. ad] = dosyalar[ad]
    liste[#liste + 1] = { type = (bozuk and bozuk.klasor == ad) and "dir" or "file", name = ad,
      size = (bozuk and bozuk.boyut == ad) and 99999 or #dosyalar[ad], download_url = HAM .. ad }
  end
  GITHUB[listeAdres(depo.sha)] = encode(liste)
  GITHUB[listeAdres("main")] = encode(liste)
end

depoKur("1.3.11", { ["main.lua"] = "-- aynı\n" })
fm:guncellemeDenetle(false)
kontrol(son("InfoMessage").text == "En son sürümü kullanıyorsun (1.3.11).", "güncel: " .. son("InfoMessage").text)
kontrol(fm.settings:readSetting("guncelleme_son_denetim") == os.time(), "denetim zamanı kaydedildi")

GITHUB[depo.ham .. "_meta.lua"] = 503
fm:guncellemeDenetle(false)
kontrol(son("InfoMessage").text:find("HTTP 503", 1, true) ~= nil, "hata gösterildi: " .. son("InfoMessage").text)

depoKur("1.3.12", { ["main.lua"] = "-- yeni main\nreturn 1\n", ["binkitap_yeni.lua"] = "return {}\n", ["ayar.lua"] = "return { oturum_kodu = \"SIFIRLANDI\" }\n",
  ["binkitap_yenilikler.lua"] = 'return { { surum = "1.3.12", maddeler = { "Yeni şey bir", "Yeni şey iki" } }, { surum = "1.3.11", maddeler = { "Eski şey" } } }\n' })
fm:guncellemeDenetle(false)
local gk = son("ConfirmBox")
kontrol(gk and gk.text:find("yeni sürümü var: 1.3.12 (sendeki 1.3.11)", 1, true) ~= nil, "yeni sürüm soruldu")
kontrol(gk.text:find("Yenilikler:\n• Yeni şey bir\n• Yeni şey iki", 1, true) and not gk.text:find("Eski şey", 1, true),
  "onay penceresinde yalnızca yeni sürümün notları: " .. gk.text:gsub("\n", " / "))
gk.ok_callback()
kontrol(oku(DIZ .. "/main.lua") == "-- yeni main\nreturn 1\n" and oku(DIZ .. "/binkitap_yeni.lua") == "return {}\n"
  and oku(DIZ .. "/_meta.lua"):find("1.3.12", 1, true), "yeni dosyalar yerinde")
kontrol(oku(DIZ .. "/ayar.lua") == 'return { oturum_kodu = "GIZLI" }\n', "ayar.lua'ya dokunulmadı")
local ayar_istendi = false
local sabit_indirme, dal_indirme = false, false
for _, r in ipairs(istekler) do
  if r.url:find("/ayar.lua", 1, true) then ayar_istendi = true end
  if r.url == depo.ham .. "main.lua" then sabit_indirme = true end
  if r.url == HAM .. "main.lua" then dal_indirme = true end
end
kontrol(sabit_indirme and not dal_indirme, "dosyalar commit'e sabit adresten indirildi")
kontrol(not ayar_istendi, "depodaki ayar.lua indirilmedi bile")
kontrol(oku(DIZ .. "/.yedek/main.lua") == "-- eski main\n", "eski sürüm .yedek'te")
kontrol(gercek_lfs.attributes(DIZ .. "/.guncelleme/main.lua", "mode") == nil, "geçici klasörde dosya kalmadı")
kontrol(son("Restart") and son("Restart").text:find("1.3.12", 1, true), "yeniden başlatma istendi")
kontrol(fm.settings:readSetting("guncelleme_kurulan") == "1.3.12", "kurulan sürüm kaydedildi")
fm:guncellemeDenetle(false)
kontrol(son("InfoMessage").text:find("1.3.12 zaten indirildi", 1, true) ~= nil, "yeniden başlatmadan önce tekrar sormuyor")

local once_main = oku(DIZ .. "/main.lua")
depoKur("1.3.13", { ["main.lua"] = "bu lua değil (\n" })
fm:guncellemeKur("1.3.13")
kontrol(son("InfoMessage").text:find("main.lua bozuk", 1, true) and oku(DIZ .. "/main.lua") == once_main,
  "bozuk dosya: hiçbir şey değişmedi")
depoKur("1.3.13", { ["main.lua"] = "return 2\n" }, { boyut = "main.lua" })
fm:guncellemeKur("1.3.13")
kontrol(son("InfoMessage").text:find("main.lua tam inmedi", 1, true) and son("InfoMessage").text:find("birkaç dakika sonra", 1, true)
  and oku(DIZ .. "/main.lua") == once_main, "eksik indirme: hiçbir şey değişmedi")
depoKur("1.3.13", { ["main.lua"] = "return 2\n", ["resimler"] = "x" }, { klasor = "resimler" })
fm:guncellemeKur("1.3.13")
kontrol(son("InfoMessage").text:find("elle kurulmalı", 1, true) and oku(DIZ .. "/main.lua") == once_main,
  "yeni klasör içeren sürüm otomatik kurulmadı")

-- yayından hemen sonra: dal adresleri (ham önbellek) hâlâ eski dosyaları veriyor
depoKur("1.3.13", { ["main.lua"] = "return 24\n", ["binkitap_yenilikler.lua"] = 'return { { surum = "1.3.13", maddeler = { "Dört" } } }\n' })
GITHUB[HAM .. "_meta.lua"] = 'return { version = "1.3.12" }\n'
GITHUB[HAM .. "main.lua"] = "-- yeni main\nreturn 1\n"
GITHUB[HAM .. "binkitap_yenilikler.lua"] = 'return {}\n'
fm.settings:delSetting("guncelleme_kurulan")
fm:guncellemeDenetle(false)
local bk = son("ConfirmBox")
kontrol(bk and bk.text:find("yeni sürümü var: 1.3.13", 1, true) and bk.text:find("• Dört", 1, true),
  "bayat önbellekte bile yeni sürüm ve notları görüldü")
bk.ok_callback()
kontrol(oku(DIZ .. "/main.lua") == "return 24\n" and oku(DIZ .. "/_meta.lua"):find("1.3.13", 1, true),
  "bayat önbellek: commit'e sabit dosyalar kuruldu")
kontrol(son("Restart") and son("Restart").text:find("1.3.13", 1, true), "bayat önbellek: kurulum tamamlandı")
once_main = oku(DIZ .. "/main.lua")

-- commit bulunamazsa dal adreslerine düşer; eski dosyalarla karışık kurulum yapmaz
GITHUB[REF] = 403
GITHUB[HAM .. "_meta.lua"] = 'return { version = "1.3.11" }\n'
GITHUB[listeAdres("main")] = encode({ { type = "file", name = "_meta.lua", size = #GITHUB[HAM .. "_meta.lua"] },
  { type = "file", name = "main.lua", size = #GITHUB[HAM .. "main.lua"] } })
fm:guncellemeKur("1.3.14")
kontrol(son("InfoMessage").text:find("henüz yeni sürümün dosyalarını vermiyor", 1, true) and oku(DIZ .. "/main.lua") == once_main,
  "dal adresi eski sürümü verince kurulum yapılmadı")
depoKur("1.3.14", { ["main.lua"] = "return 25\n" })
GITHUB[REF] = 404
fm:guncellemeKur("1.3.14")
kontrol(oku(DIZ .. "/main.lua") == "return 25\n", "commit bulunamayınca dal adresleriyle kuruldu")
fm.settings:delSetting("guncelleme_kurulan")

-- haftalık sessiz denetim
depoKur("1.3.14", { ["main.lua"] = "return 3\n" })
fm.settings:saveSetting("guncelleme_son_denetim", os.time() - 2 * 24 * 3600)
fm:onNetworkConnected(); calistir()
kontrol(son("ConfirmBox") == gk or not son("ConfirmBox").text:find("1.3.14", 1, true), "iki gün önce denetlendiyse sormadı")
fm.settings:saveSetting("guncelleme_son_denetim", os.time() - 8 * 24 * 3600)
fm:onNetworkConnected(); fm2:onNetworkConnected(); calistir()
local sorular = 0
for _, w in ipairs(gosterilen) do if w._tur == "ConfirmBox" and w.text:find("1.3.14", 1, true) then sorular = sorular + 1 end end
kontrol(sorular == 1, "bir hafta geçince bir kez sordu (iki örnek açıkken bile)")
kontrol(son("ConfirmBox").cancel_text == "Sonra", "sormadan kurmuyor")
fm.settings:saveSetting("guncelleme_son_denetim", os.time() - 8 * 24 * 3600)
GITHUB[depo.ham .. "_meta.lua"] = 503
local once_bilgi = #gosterilen
fm:onNetworkConnected(); calistir()
kontrol(#gosterilen == once_bilgi, "sessiz denetimde hata gösterilmedi")
oto_oge.callback()
fm.settings:saveSetting("guncelleme_son_denetim", 0)
fm:onNetworkConnected()
kontrol(#zamanlanan == 0 and not oto_oge.checked_func(), "kapatınca hiç denetlemiyor")
oto_oge.callback()
fm.settings:delSetting("guncelleme_kurulan")
fm.path = nil
os.execute("rm -rf " .. GERCEK)
end

print("29) Toplu eşleştirme cihazı kilitlemesin")
FS["/kobo/Toplu"] = {}
for n = 1, 25 do FS["/kobo/Toplu"][n] = string.format("Bilinmez Kitap %02d.epub", n) end
table.insert(FS["/kobo"], "Toplu")
fsEkle()
KAPAK_ONBELLEK["/kobo/Toplu/Bilinmez Kitap 03.epub"] = { title = "Gog", authors = "Giovanni Papini" }
local acilan_belge = 0
fm.ui.bookinfo = { getDocProps = function() acilan_belge = acilan_belge + 1; return { title = "Açıldı" } end }
local gercek_flush, flush_sayisi = fm.settings.flush, 0
fm.settings.flush = function(self_) flush_sayisi = flush_sayisi + 1 end
fm.settings:saveSetting("kutuphane_belirsiz", {})
fm:kutuphaneEslestir()
local kb = son("ConfirmBox")
kontrol(kb.text:find("25 tanesi henüz eşleşmemiş", 1, true) ~= nil, "25 yeni kitap bulundu")
kb.ok_callback()
local dinlenme_goruldu = false
while #zamanlanan > 0 do
  local f = table.remove(zamanlanan, 1); f()
  local im = son("InfoMessage")
  if im and im.text:find("dinleniyor", 1, true) then dinlenme_goruldu = true; break end
end
kontrol(dinlenme_goruldu and son("InfoMessage").text:find("20 / 25", 1, true), "20 kitapta bir dinlenme molası")
local ara_belirsiz = 0
for _ in pairs(fm:kutuphaneBelirsizleri()) do ara_belirsiz = ara_belirsiz + 1 end
kontrol(ara_belirsiz == 19, "mola anında emin olunamayanlar kaydedilmiş: " .. ara_belirsiz)
calistir()
kontrol(acilan_belge == 0, "hiçbir belge açılmadı (meta veri sadece yan dosya / önbellek / dosya adından)")
kontrol(fm:dosyaEslesmesi("/kobo/Toplu/Bilinmez Kitap 03.epub").id == "800", "kapak tarayıcısı önbelleğinden başlık okundu ve eşleşti")
kontrol(flush_sayisi <= 6, "ayarlar her kitapta değil, arada bir yazıldı: " .. flush_sayisi .. " kez")
fm.settings.flush = gercek_flush
fm.ui.bookinfo = nil

print("30) Gözden geçirmede otomatik onay")
fm.settings:saveSetting("kitapliga_ekle", true)
local kuyruk_once = #fm:kuyruk()
fm.settings:saveSetting("kutuphane_belirsiz", {
  ["/kobo/Kafka/Bilinmeyen.epub"] = { sorgu = "Kaos", baslik = "Kaos", adaylar = { { id = "9517", adi = "Kaos Lordu", yazar = "Robert Jordan", yayinevi = "İthaki" } } },
  ["/kobo/Toplu/Bilinmez Kitap 01.epub"] = { sorgu = "Dönüşüm", baslik = "Dönüşüm", adaylar = {
    { id = "700", adi = "Dönüşüm", yazar = "Franz Kafka", yayinevi = "İş Bankası" }, { id = "702", adi = "Dönüşüm", yazar = "Ovidius" } } },
  ["/kobo/Toplu/Bilinmez Kitap 02.epub"] = { sorgu = "x", baslik = "x", adaylar = {} },
})
fm:kutuphaneGozdenGecir()
local gm = son("Menu")
kontrol(gm.item_table[1].text == "Tek adaylıları otomatik onayla (1)" and gm.item_table[2].text == "Hepsini ilk adayla onayla (2)",
  "iki toplu onay seçeneği: " .. gm.item_table[1].text .. " / " .. tostring(gm.item_table[2].text))
flush_sayisi = 0
fm.settings.flush = function() flush_sayisi = flush_sayisi + 1 end
menuSec(gm, function(it) return it.eylem == "tek" end)
local oc = son("ConfirmBox")
kontrol(oc.text:find("Tek aday bulunan 1 kitap", 1, true) and oc.text:find("otomatik onaylandı", 1, true), "ne yapılacağı ve işaretleneceği söylendi")
oc.ok_callback()
local ea = fm:dosyaEslesmesi("/kobo/Kafka/Bilinmeyen.epub")
kontrol(ea.id == "9517" and ea.otomatik == true, "tek aday otomatik işaretiyle eşleşti")
kontrol(gm.item_table[1].text == "Hepsini ilk adayla onayla (1)", "liste yenilendi: " .. gm.item_table[1].text)
menuSec(gm, function(it) return it.eylem == "ilk" end)
son("ConfirmBox").ok_callback()
local eb = fm:dosyaEslesmesi("/kobo/Toplu/Bilinmez Kitap 01.epub")
kontrol(eb.id == "700" and eb.otomatik, "ilk adayla eşleşti (otomatik)")
kontrol(fm:belirsizSayisi() == 1, "adayı olmayan listede kaldı")
kontrol(flush_sayisi == 2, "toplu onayda ayarlar bir kez yazıldı: " .. flush_sayisi)
fm.settings.flush = gercek_flush
local kitaplik_kuyrugu = 0
for _, o in ipairs(fm:kuyruk()) do if o.tur == "kitaplik_ekle" then kitaplik_kuyrugu = kitaplik_kuyrugu + 1 end end
kontrol(kitaplik_kuyrugu == 0, "otomatik eşleşmeler onaylanmadan kitaplığa eklenmedi")
local row3 = FileManager.file_dialog_added_buttons[1]("/kobo/Kafka/Bilinmeyen.epub", true, nil)
row3[1].callback()
kontrol(son("ButtonDialog").title:find("otomatik eşleşti, henüz onaylanmadı", 1, true) ~= nil, "uzun basmada da belirtiliyor")
son("ButtonDialog")._kapandi = true

-- kitap açılınca
durum["9517"] = nil
local oui = yeniOkuyucu("/kobo/Kafka/Bilinmeyen.epub", { title = "Kaos", authors = "" }, 500)
local op = Plugin:new{ ui = oui }
op:onReaderReady(); calistir()
local ob = son("ButtonDialog")
kontrol(ob and ob.title:find("otomatik eşleştirildi", 1, true) and ob.title:find("Kaos Lordu", 1, true)
  and ob.title:find("Yanlış olabilir", 1, true), "açılışta otomatik eşleşme hatırlatıldı")
kontrol(durum["9517"] == nil, "doğrulanmadan Okuyorum gönderilmedi")
local menu_metni = op:menuOgeleri()[2].text_func()
kontrol(menu_metni:find("otomatik, onaylanmadı", 1, true) ~= nil, "menüde de görünüyor: " .. menu_metni)
oui.highlight._dugme.fn({ selected_text = { text = "Deneme.", pos0 = "/body/DocFragment[2]/body/p[1]/text().0" }, onClose = function() end }).callback()
kontrol(son("ButtonDialog").title:find("otomatik eşleşme, onaylanmadı", 1, true) ~= nil, "alıntı penceresinde uyarı")
son("ButtonDialog")._kapandi = true
dugme(ob, "Doğru").callback(); calistir()
kontrol(oui.doc_settings.data.binkitap.otomatik == nil and fm:dosyaEslesmesi("/kobo/Kafka/Bilinmeyen.epub").otomatik == nil,
  "doğrulanınca işaret kalktı")
kontrol(durum["9517"] == nil, "doğrulandı; okumadan Okuyorum gönderilmedi")
for sf = 2, 11 do oui.sayfa = sf; op:onPageUpdate(sf) end; calistir()
Plugin.ORTAK.son_etkilesim = nil
kontrol(durum["9517"] == 2, "doğrulanıp %2 okununca Okuyorum gönderildi")
kontrol(kitaplikta("9517"), "Okuyorum'la kitaplığa eklendi (ayar açık)")
op:onReaderReady(); calistir()
kontrol(not (son("ButtonDialog") and son("ButtonDialog").title:find("otomatik eşleştirildi", 1, true)), "bir daha sormadı")
fm.settings:saveSetting("kitapliga_ekle", nil)

do
print("31) İleti yaz")
kontrol(eylemler.binkitap_ileti_yaz ~= nil, "hareket eylemi kaydedildi")
fm:iletiYaz()
local iw = son("ButtonDialog")
kontrol(iw.title:find("Yeni ileti", 1, true) and iw.title:find("Kitap etiketlenmedi", 1, true), "dosya tarayıcısında kitapsız açıldı")
kontrol(dugme(iw, "Kitabı etiketle").enabled == false and dugme(iw, "Paylaş").enabled == false, "boşken paylaşılamıyor")
dugme(iw, "Metni yaz").callback()
local mi = son("InputDialog")
kontrol(mi.allow_newline == true, "metin çok satırlı")
mi._girdi = "Bugün harika bir kitap bitirdim.\nİkinci paragraf.  "
dugme(mi, "Tamam").callback()
iw = son("ButtonDialog")
kontrol(iw.title:find("Bugün harika", 1, true) ~= nil, "metin pencerede")
dugme(iw, "Başlık").callback()
local bi = son("InputDialog"); bi._girdi = "Kısa not"
dugme(bi, "Tamam").callback()
dugme(son("ButtonDialog"), "Yorumlar").callback()
dugme(son("ButtonDialog"), "○ Sadece takip ettiklerim").callback()
iw = son("ButtonDialog")
kontrol(iw.title:find("Başlık: Kısa not", 1, true) and iw.title:find("Yorumlar: Sadece takip ettiklerim", 1, true), "başlık ve yorum izni")
dugme(iw, "Kapat").callback()
local ileti_ogesi
for _, o in ipairs(fm:menuOgeleri()) do if o.text_func and o.text_func():find("^İleti yaz") then ileti_ogesi = o end end
kontrol(ileti_ogesi.text_func() == "İleti yaz (taslak var)", "kapatınca taslak kaldı")
ileti_ogesi.callback()
iw = son("ButtonDialog")
kontrol(iw.title:find("Bugün harika", 1, true) ~= nil, "taslaktan devam")
dugme(iw, "Paylaş").callback(); calistir()
local il = iletiler[#iletiler]
kontrol(il and il.ileti == "Bugün harika bir kitap bitirdim.\nİkinci paragraf." and il.baslik == "Kısa not"
  and il.yorumAyari == "3" and il.konuId == "" and il.anonimSoruMisafir == "1", "iletiler/iletiEkle doğru alanlarla gitti")
kontrol(son("InfoMessage").text:find("1 ileti paylaşıldı", 1, true) ~= nil, "özet: " .. son("InfoMessage").text)
kontrol(fm:iletiTaslagi() == nil and ileti_ogesi.text_func() == "İleti yaz", "paylaşınca taslak silindi")

p:iletiYaz()
iw = son("ButtonDialog")
kontrol(iw.title:find("Etiketli kitap: Walden", 1, true) ~= nil, "okurken kitap kendiliğinden etiketlendi")
dugme(iw, "Metni yaz").callback()
mi = son("InputDialog"); mi._girdi = "Ormanda bir gün."
dugme(mi, "Tamam").callback()
dugme(son("ButtonDialog"), "Paylaş").callback(); calistir()
kontrol(iletiler[#iletiler].ileti == "Ormanda bir gün.\n\n#k:24319", "kitap etiketi #k: ile eklendi")

p:iletiYaz()
dugme(son("ButtonDialog"), "Kitap etiketini kaldır").callback()
iw = son("ButtonDialog")
kontrol(iw.title:find("Kitap etiketlenmedi", 1, true) ~= nil, "etiket kaldırıldı")
dugme(iw, "Metni yaz").callback()
mi = son("InputDialog"); mi._girdi = "Reddedilecek ileti"
dugme(mi, "Tamam").callback()
ileti_reddet = true
local once_ileti = #iletiler
dugme(son("ButtonDialog"), "Paylaş").callback(); calistir()
ileti_reddet = false
kontrol(#iletiler == once_ileti and son("InfoMessage").text:find("Bu ileti paylaşılamaz", 1, true)
  and son("InfoMessage").text:find("taslak olarak duruyor", 1, true), "reddedilince söylendi: " .. son("InfoMessage").text)
kontrol(fm:iletiTaslagi() and fm:iletiTaslagi().metin == "Reddedilecek ileti" and fm:iletiTaslagi().kitapsiz,
  "metin taslağa geri kondu")
p:iletiYaz()
iw = son("ButtonDialog")
kontrol(iw.title:find("Reddedilecek ileti", 1, true) and iw.title:find("Kitap etiketlenmedi", 1, true), "taslak etiket seçimiyle döndü")
network.online = false; ag_acik = false
dugme(iw, "Paylaş").callback(); calistir()
kontrol(son("InfoMessage").text:find("İleti sıraya alındı", 1, true) ~= nil and #iletiler == once_ileti, "çevrimdışı: sıraya alındı")
network.online = true; ag_acik = true
if network.bekleyen then local b = network.bekleyen; network.bekleyen = nil; b() end
calistir()
kontrol(#iletiler == once_ileti + 1 and iletiler[#iletiler].ileti == "Reddedilecek ileti", "bağlanınca paylaşıldı")
end

do
print("32) Çok kitabı kitaplığa eklemek cihazı kilitlemesin")
FS["/kobo/Cok"] = {}
local cok_esl = fm.settings:readSetting("eslesmeler")
for n = 1, 30 do
  local ad = string.format("Cok %02d.epub", n)
  FS["/kobo/Cok"][n] = ad
  cok_esl["/kobo/Cok/" .. ad] = { id = tostring(6000 + n), adi = "Çok Kitap " .. n, yazar = "Yazar " .. n }
end
fsEkle()
for n = 1, 45 do KITAPLIK[#KITAPLIK + 1] = tostring(7000 + n) end  -- uzun kitaplık: 3 sayfa
local liste_once = istekSay("uyeler/kitaplar/liste", function(r) return r.q.raf == "kutuphanesi" end)
local fl = 0
fm.settings.flush = function() fl = fl + 1 end
fm:kitapligaEkleListesi()
local gr = false
while #zamanlanan > 0 do
  table.remove(zamanlanan, 1)()
  if son("InfoMessage") and son("InfoMessage").text:find("kitaplığın getiriliyor", 1, true) then gr = true end
end
local sayfa_istegi = istekSay("uyeler/kitaplar/liste", function(r) return r.q.raf == "kutuphanesi" end) - liste_once
kontrol(gr and sayfa_istegi >= 3, "kitaplık sayfa sayfa, ilerleme gösterilerek getirildi (" .. sayfa_istegi .. " sayfa)")
local cl2 = son("Menu")
kontrol(cl2.title == "Kitaplığa ekle", "seçim listesi açıldı")
menuSec(cl2, function(it) return it.eylem == "hepsi" end)
fl = 0
local once_ek = istekSay("kitaplar/kitapKutuphanemeEkle")
menuSec(cl2, function(it) return it.eylem == "onay" end)
kontrol(fl == 1, "30+ kitap sıraya tek seferde yazıldı (" .. fl .. " yazma)")
local bm = son("InfoMessage")
kontrol(bm and bm.text:find("iş sıraya alındı. Arka planda", 1, true), "arka plana alındı, ekran meşgul edilmedi: " .. tostring(bm and bm.text))
kontrol(istekSay("kitaplar/kitapKutuphanemeEkle") == once_ek, "hemen gönderilmedi")
local ORT = Plugin.ORTAK
local function tik() local f = table.remove(zamanlanan, 1); if f then f() end end
local bekleyen_oge
for _, o in ipairs(fm:menuOgeleri()) do if o.text_func and o.text_func():find("^Bekleyen gönderiler") then bekleyen_oge = o end end
kontrol(bekleyen_oge.text_func():find("arka planda gönderiliyor", 1, true), "menüde arka planda gönderildiği görünüyor")
tik(); tik(); tik()
kontrol(istekSay("kitaplar/kitapKutuphanemeEkle") - once_ek == 3, "her adımda tek iş gönderildi")
ORT.son_etkilesim = os.time() -- okurken sayfa çevrildi
tik()
kontrol(istekSay("kitaplar/kitapKutuphanemeEkle") - once_ek == 3, "sayfa yeni çevrildiyse araya girmedi")
saat = saat + 10
tik()
kontrol(istekSay("kitaplar/kitapKutuphanemeEkle") - once_ek == 4, "biraz sonra devam etti")
network.online = false
tik()
kontrol(ORT.arka_plan == nil and #zamanlanan == 0, "Wi-Fi gidince durdu")
local kalan = 0
for _, o in ipairs(fm:kuyruk()) do if o.tur == "kitaplik_ekle" then kalan = kalan + 1 end end
kontrol(kalan > 20, "kalanlar sırada (" .. kalan .. ")")
network.online = true
fm:onNetworkConnected(); calistir()
kalan = 0
for _, o in ipairs(fm:kuyruk()) do if o.tur == "kitaplik_ekle" then kalan = kalan + 1 end end
kontrol(kalan == 0 and kitaplikta("6030"), "Wi-Fi gelince kaldığı yerden bitirdi")
kontrol(son("InfoMessage").text:find("iş arka planda gönderildi", 1, true) and son("InfoMessage").timeout,
  "bitince kendiliğinden kapanan kısa özet: " .. son("InfoMessage").text)
kontrol(fl <= 6, "ayar dosyası seyrek yazıldı (" .. fl .. ")")
kontrol(not bekleyen_oge.text_func():find("arka planda", 1, true), "menüdeki ibare kalktı")
-- KOReader yeniden açılınca kalabalık sıra kendiliğinden sürer
local ek_is = {}
for n = 1, 8 do ek_is[n] = { tur = "kitaplik_ekle", kitap_id = tostring(6100 + n), kitap_adi = "Ek " .. n, yok_biliniyor = true } end
fm:topluSiraya(ek_is)
local fm4 = Plugin:new{ ui = fm_ui }
calistir()
kontrol(#fm:kuyruk() == 0 and kitaplikta("6108"), "yeniden açılışta yarım kalan sıra arka planda bitti")
fm.settings.flush = gercek_flush
fm.settings:flush()
local l1 = istekSay("uyeler/kitaplar/liste")
fm:kitapliktanCikarListesi(); calistir()
local l2 = istekSay("uyeler/kitaplar/liste")
son("Menu")._kapandi = true
fm:kitapliktanCikarListesi(); calistir()
kontrol(l2 > l1 and istekSay("uyeler/kitaplar/liste") == l2, "kitaplık listesi kısa süre hatırlandı")
son("Menu")._kapandi = true
end

do
print("33) Okuyacaklarıma ekle (dosya tarayıcısından bağımsız)")
kontrol(eylemler.binkitap_okuyacaklara_ekle ~= nil, "hareket eylemi kaydedildi")
local oe
for _, o in ipairs(fm:menuOgeleri()) do if o.text == "Okuyacaklarıma ekle" then oe = o end end
local poe
for _, o in ipairs(p:menuOgeleri()) do if o.text == "Okuyacaklarıma ekle" then poe = o end end
kontrol(oe and poe, "menüde hem dosya tarayıcısında hem okurken var")
oe.callback()
local sd = son("ButtonDialog")
kontrol(dugme(sd, "Kobo'daki kitaplarımdan seç") and dugme(sd, "1000Kitap'ta ara"), "iki yol sunuldu")
dugme(sd, "Kobo'daki kitaplarımdan seç").callback()
local ol = son("Menu")
kontrol(ol.title == "Okuyacaklarıma eklenecek kitaplar" and ol.item_table[2].text == "Listede ara…", "Kobo'daki tüm kitaplar, aranabilir liste")
local toplam_kitap = 0
for _, it in ipairs(ol.item_table) do if it.indeks then toplam_kitap = toplam_kitap + 1 end end
kontrol(toplam_kitap >= 30, "alt klasörler dahil tüm kitaplar listelendi (" .. toplam_kitap .. ")")
menuSec(ol, function(it) return it.eylem == "ara" end)
local ad = son("InputDialog"); ad._girdi = "şairin"
dugme(ad, "Ara").callback()
local gor = {}
for _, it in ipairs(ol.item_table) do if it.indeks then gor[#gor + 1] = it.text end end
kontrol(#gor == 1 and gor[1] == "☐ Sairin Romani.epub" and ol.item_table[2].text == "Arama: şairin · temizle",
  "Türkçe harfle arama süzdü: " .. table.concat(gor, ","))
menuSec(ol, function(it) return it.eylem == "hepsi" end)
menuSec(ol, function(it) return it.eylem == "temizle" end)
local secili_n = 0
for _, it in ipairs(ol.item_table) do if it.indeks and it.text:find("^☑") then secili_n = secili_n + 1 end end
kontrol(secili_n == 1 and ol.item_table[3].text == "Tümünü seç", "sadece görünen seçildi, arama temizlendi")
menuSec(ol, function(it) return it.eylem == "ara" end)
ad = son("InputDialog"); ad._girdi = "zzzz"
dugme(ad, "Ara").callback()
kontrol(ol.item_table[#ol.item_table].text == "Aramaya uyan kitap yok.", "sonuç yoksa söylendi")
menuSec(ol, function(it) return it.eylem == "temizle" end)
durum["801"] = nil
menuSec(ol, function(it) return it.eylem == "onay" end); calistir()
kontrol(durum["801"] == 0, "Şairin Romanı Okuyacağım yapıldı")

durum["92807"] = nil
oe.callback()
dugme(son("ButtonDialog"), "1000Kitap'ta ara").callback()
local ai = son("InputDialog")
kontrol(ai.title == "Okuyacaklarına eklenecek kitabı ara", "arama penceresi açıldı")
ai._girdi = "Shenzen"
dugme(ai, "Ara").callback()
son("ButtonDialog").buttons[1][1].callback(); calistir()
kontrol(durum["92807"] == 0, "Kobo'da olmayan kitap aranıp Okuyacağım yapıldı")
durum["800"] = 1
oe.callback()
dugme(son("ButtonDialog"), "1000Kitap'ta ara").callback()
ai = son("InputDialog"); ai._girdi = "Gog Papini"
dugme(ai, "Ara").callback()
son("ButtonDialog").buttons[1][1].callback(); calistir()
kontrol(durum["800"] == 1, "okunmuş kitap Okuyacağım'a çevrilmedi")
end

do
print("34) Okuduklarımı aktar")
local ilk
for _, w in ipairs(gosterilen) do
  if w._tur == "ConfirmBox" and w.text and w.text:find("1000Kitap eklentisi hazır", 1, true) then ilk = w end
end
kontrol(ilk and ilk.ok_text == "Bul" and ilk.cancel_text == "Sonra" and fm.settings:readSetting("okunanlar_soruldu") == true,
  "hesap girilince bir kez soruldu")
local soru_sayisi = 0
for _, w in ipairs(gosterilen) do
  if w._tur == "ConfirmBox" and w.text and w.text:find("1000Kitap eklentisi hazır", 1, true) then soru_sayisi = soru_sayisi + 1 end
end
local fm3 = Plugin:new{ ui = fm_ui }; calistir()
local soru_sonra = 0
for _, w in ipairs(gosterilen) do
  if w._tur == "ConfirmBox" and w.text and w.text:find("1000Kitap eklentisi hazır", 1, true) then soru_sonra = soru_sonra + 1 end
end
kontrol(soru_sayisi == 1 and soru_sonra == 1, "bir daha sorulmadı")

YAN_DOSYALAR["/kobo/Kafka/Donusum.epub"].summary = { status = "complete", modified = "2026-10-01" }
YAN_DOSYALAR["/kobo/Kafka/Donusum.epub"].partial_md5_checksum = "md5-donusum"
-- KOReader istatistik veritabanı taklidi
local sq3_acik = 0
package.preload["lua-ljsqlite3/init"] = function()
  return { open = function()
    sq3_acik = sq3_acik + 1
    local md5
    local stmt = {}
    function stmt:reset() return self end
    function stmt:bind(m) md5 = m; return self end
    function stmt:step()
      if md5 == "md5-donusum" then return { os.time{ year = 2026, month = 9, day = 1, hour = 20, min = 0 }, os.time{ year = 2026, month = 9, day = 20, hour = 22, min = 30 } } end
      return { nil, nil }
    end
    function stmt:close() end
    return { prepare = function() return stmt end, close = function() sq3_acik = sq3_acik - 1 end }
  end }
end
DOSYALAR["/tmp/statistics.sqlite3"] = true
YAN_DOSYALAR["/kobo/Kafka/Donusum.epub"].doc_pages = 100
YAN_DOSYALAR["/kobo/Kafka/Donusum.epub"].annotations = {
  { text = "Bir sabah Gregor Samsa", note = "Ünlü açılış", datetime = "2026-09-01 10:00:00", page = "/body/DocFragment[2].0", pos0 = "/body/DocFragment[2].0", pageno = 50, drawer = "lighten" },
  { text = "Böceğe dönüşmüş", datetime = "2026-09-02 10:00:00", page = "/body/DocFragment[3].0", pos0 = "/body/DocFragment[3].0", pageno = 80, drawer = "lighten" },
  { text = "Zaten gönderilmiş", datetime = "2026-09-03 10:00:00", page = "/body/DocFragment[4].0", pos0 = "/body/DocFragment[4].0", pageno = 90, drawer = "lighten" },
  { page = 33, datetime = "2026-09-04 10:00:00" }, -- yer imi, vurgu değil
}
YAN_DOSYALAR["/kobo/Kafka/Donusum.epub"].binkitap_gonderilen = { ["2026-09-03 10:00:00|/body/DocFragment[4].0"] = true }
YAN_DOSYALAR["/kobo/Gog.epub"] = { doc_props = { title = "Gog", authors = "Giovanni Papini" }, percent_finished = 0.995, doc_pages = 200,
  highlight = { ["120"] = { { text = "Eski biçim vurgu", datetime = "2020-01-01 10:00:00", pos0 = "x1" } } } }
YAN_DOSYALAR["/kobo/Kafka/Sairin Romani.epub"] = { doc_props = { title = "Şairin Romanı" }, summary = { status = "abandoned" }, percent_finished = 1 }
fm:dosyaEslesmesi("/kobo/Kafka/Donusum.epub").basili_sayfa = nil

local tarama_goruldu = false
fm:okuduklarimiAktar()
while #zamanlanan > 0 do
  table.remove(zamanlanan, 1)()
  local im = son("InfoMessage")
  if im and im.text:find("bitirdiğin kitaplar aranıyor", 1, true) then tarama_goruldu = true end
end
kontrol(tarama_goruldu, "tarama ilerlemesi gösterildi")
local al = son("Menu")
kontrol(al.title == "Okuduklarını 1000Kitap'a aktar", "liste açıldı")
local sat = {}
for _, it in ipairs(al.item_table) do if it.indeks then sat[#sat + 1] = it.text .. " [" .. tostring(it.mandatory) .. "]" end end
kontrol(sq3_acik == 0, "istatistik veritabanı tarama sonunda kapatıldı")
kontrol(#sat == 2 and sat[1] == "☑ Dönüşüm [bitti 20.09.2026 · 2 vurgu]" and sat[2] == "☐ Gog [sonuna kadar okunmuş · 1 vurgu]",
  "bitenler (yarım bırakılan hariç), işaretli olan seçili: " .. table.concat(sat, " | "))
menuSec(al, function(it) return it.text == "☐ Gog" end)
durum["701"] = -1; durum["800"] = 2
menuSec(al, function(it) return it.eylem == "onay" end)
local once_alinti, once_not = #alintilar, #notlar
calistir()
kontrol(durum["701"] == 1 and durum["800"] == 1, "seçilenler 1000Kitap'ta Okudum yapıldı")
local ot = okuma_tarihi["701"]
kontrol(ot and ot.bas == "01.09.2026 20:00" and ot.bit == "20.09.2026 22:30" and ot.toplu == "1",
  "okuma istatistiklerdeki tarihlerle kaydedildi: " .. (ot and (ot.bas .. " → " .. ot.bit) or "tarihsiz"))
kontrol(okuma_tarihi["800"] == false, "1000Kitap'ta açık okuması olan kitap tarihsiz (ikinci okuma açılmasın)")
local vl = son("Menu")
kontrol(vl.title == "Alıntılarını da göndereyim mi?", "ardından vurgular soruldu")
local vs = {}
for _, it in ipairs(vl.item_table) do if it.indeks then vs[#vs + 1] = it.text .. " [" .. tostring(it.mandatory) .. "]" end end
kontrol(#vs == 2 and vs[1]:find("☐", 1, true) and vs[2]:find("☐", 1, true), "kitaplar varsayılan olarak seçili değil: " .. table.concat(vs, " | "))
menuSec(vl, function(it) return it.text and it.text:find("Dönüşüm", 1, true) end)
menuSec(vl, function(it) return it.eylem == "onay" end)
local nb = son("ButtonDialog")
kontrol(nb.title == "2 vurgu nasıl gönderilsin?", "nasıl gönderileceği soruldu: " .. nb.title)
dugme(nb, "Herkese açık alıntı").callback(); calistir()
kontrol(#alintilar == once_alinti + 2, "2 vurgu alıntı olarak gitti (gönderilmiş olan atlandı)")
local a1 = alintilar[once_alinti + 1]
kontrol(a1.soz == "Bir sabah Gregor Samsa" and a1.ekbilgi == "Ünlü açılış" and a1.kitapid == "701" and a1.sayfa == "48",
  "metin, not ve basılı sayfa (50/100 × 96 ≈ 48): sayfa " .. tostring(a1.sayfa))
local gd = YAN_DOSYALAR["/kobo/Kafka/Donusum.epub"].binkitap_gonderilen
kontrol(gd["2026-09-01 10:00:00|/body/DocFragment[2].0"] and gd["2026-09-02 10:00:00|/body/DocFragment[3].0"]
  and YAN_DOSYALAR["/kobo/Kafka/Donusum.epub"]._yazildi, "gönderilenler kitabın yan dosyasına işlendi")

fm:aktarilanVurgular({ { yol = "/kobo/Kafka/Donusum.epub", kitap = fm:dosyaEslesmesi("/kobo/Kafka/Donusum.epub") },
                       { yol = "/kobo/Gog.epub", kitap = fm:dosyaEslesmesi("/kobo/Gog.epub") } })
vl = son("Menu")
local kalan_kitap = 0
for _, it in ipairs(vl.item_table) do if it.indeks then kalan_kitap = kalan_kitap + 1 end end
kontrol(kalan_kitap == 1, "ikinci kez sadece gönderilmemiş vurgusu olan kitap çıktı")
menuSec(vl, function(it) return it.eylem == "hepsi" end)
menuSec(vl, function(it) return it.eylem == "onay" end)
dugme(son("ButtonDialog"), "Gizli").callback(); calistir()
local sn = notlar[#notlar]
kontrol(#notlar == once_not + 1 and sn.hedefId == "800" and sn["not"]:find("“Eski biçim vurgu” (s. 298)", 1, true),
  "eski biçim vurgu özel not olarak gitti (120/200 × 496 ≈ 298): " .. tostring(sn["not"]))
end

do
print("35) Gizli alıntı")
local gann = {
  { datetime = "2026-11-01 10:00:00", drawer = "lighten", text = "Gizli bir", page = "/body/DocFragment[2]/body/p[1]/text().0" },
  { datetime = "2026-11-01 10:01:00", drawer = "lighten", text = "Gizli iki", page = "/body/DocFragment[3]/body/p[1]/text().0", note = "notum" },
  { datetime = "2026-11-01 10:02:00", drawer = "lighten", text = "Gizli üç", page = "/body/DocFragment[4]/body/p[1]/text().0" },
}
local gui = yeniOkuyucu("/kobo/Kafka/Donusum.epub", { title = "Dönüşüm", authors = "Franz Kafka" }, 200, gann)
local gp = Plugin:new{ ui = gui }
gp:topluGonder()
local d1 = son("ButtonDialog")
kontrol(d1.buttons[1][1].text == "Hepsini herkese açık" and d1.buttons[1][2].text == "Hepsini gizli"
  and d1.title:find("gizli alıntıları 1000Kitap'ta yalnızca sen görürsün", 1, true), "toplu gönderimde gizli seçeneği var")
d1._kapandi = true
gp.settings:saveSetting("alinti_gizli", true)
local ayar_var = false
for _, o in ipairs(gp:ayarlarMenusu()) do if o.text == "Alıntıları varsayılan olarak gizli paylaş" and o.checked_func() then ayar_var = true end end
kontrol(ayar_var, "ayarlarda varsayılan gizli seçeneği")
gp:topluGonder()
local d2 = son("ButtonDialog")
kontrol(d2.buttons[1][1].text == "Hepsini gizli", "varsayılan gizliyken önce gizli seçenek geliyor")
local once_not, once_al = #notlar, #alintilar
dugme(d2, "Hepsini gizli").callback(); calistir()
kontrol(#notlar == once_not + 3 and #alintilar == once_al, "3 vurgu gizli gitti, herkese açık alıntı gitmedi")
kontrol(notlar[once_not + 2]["not"]:find("“Gizli iki”", 1, true) and notlar[once_not + 2]["not"]:find("notum", 1, true)
  and notlar[once_not + 2].hedefId == "701", "gizli alıntı metni, notu ve kitabı doğru")
kontrol(son("InfoMessage").text:find("3 gizli alıntı gönderildi", 1, true) ~= nil, "özet: " .. son("InfoMessage").text)
gui.highlight._dugme.fn({ selected_text = { text = "Yeni bir cümle.", pos0 = "/body/DocFragment[5]/body/p[1]/text().0" }, onClose = function() end }).callback()
local gw = son("ButtonDialog")
kontrol(gw.title:find("Gizli: yalnızca sen", 1, true) and dugme(gw, "Herkese açık yap"), "alıntı penceresi gizli açıldı")
gw._kapandi = true
local renk_secenegi = gp:renkMenusu()[1].sub_item_table[3].text
kontrol(renk_secenegi == "Gizli alıntı (yalnızca sen)", "renk seçeneğinde de gizli: " .. renk_secenegi)
gp.settings:saveSetting("alinti_gizli", nil)
end

do
print("36) Hata günlüğü")
local A = Plugin.Api
p.settings:delSetting("hata_gunlugu")
ileti_reddet = true
A:iletiEkle("deneme", {})
A:iletiEkle("deneme", {})
ileti_reddet = false
local g = p.settings:readSetting("hata_gunlugu")
kontrol(#g == 1 and g[1].islem == "İleti" and g[1].sayi == 2 and g[1].mesaj:find("paylaşılamaz", 1, true), "aynı hata tek satırda sayıldı")
ag_acik = false; A:okumaDurumu("24319"); ag_acik = true
local metin = p:hataGunluguMetni()
kontrol(metin:find("Durum sorgusu · bağlantı", 1, true) and metin:find("(2 kez)", 1, true)
  and metin:find("Durum sorgusu", 1, true) < metin:find("İleti", 1, true), "metin yeniden eskiye, türüyle: " .. metin:gsub("\n", " / "))
kontrol(p:ayarlarMenusu()[1].text_func() == "Mod: Normal (kendi ayarların)", "ayarların başında mod seçimi")
local hm = p:ayarlarMenusu()[2]
kontrol(hm.text_func() == "Hata günlüğü (2)", "ayarlarda sayaç: " .. hm.text_func())
hm.sub_item_table[1].callback()
kontrol(son("TextViewer").text == metin, "günlük gösterildi")
hm.sub_item_table[2].callback()
kontrol(p:hataSayisi() == 0 and hm.text_func() == "Hata günlüğü (0)", "temizlendi")
Plugin.hataKaydet("sunucu", "x", "kod " .. OTURUM .. " / " .. CIHAZ .. " / aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
local gm = p.settings:readSetting("hata_gunlugu")[1].mesaj
kontrol(not gm:find(OTURUM, 1, true) and not gm:find(CIHAZ, 1, true) and not gm:find("aaaaaaaa", 1, true), "hesap kodları günlüğe yazılmıyor: " .. gm)
p.settings:delSetting("hata_gunlugu")
end

do
print("37) Uykuya geçerken gönderim")
puan["9517"] = nil
p.settings:saveSetting("uykuda_gonder", false)
p:siraya({ tur = "puan", kitap_id = "9517", kitap_adi = "Kaos Lordu", puan = 4 })
p:onSuspend()
kontrol(puan["9517"] == nil and #p:kuyruk() == 1, "ayar kapalıyken uykuda gönderilmedi")
p.settings:saveSetting("uykuda_gonder", nil)
network.online = false; ag_acik = false
p:onSuspend()
kontrol(puan["9517"] == nil and #p:kuyruk() == 1, "Wi-Fi yokken beklemedi, sırada kaldı")
network.online = true; ag_acik = true
p:onResume(); calistir()
kontrol(puan["9517"] == 4 and #p:kuyruk() == 0, "uyanınca Wi-Fi açıksa gönderildi")
p:siraya({ tur = "puan", kitap_id = "9517", kitap_adi = "Kaos Lordu", puan = 5 })
p:onSuspend()
kontrol(puan["9517"] == 5 and #p:kuyruk() == 0, "uykuya geçerken hemen gönderildi")
end

do
print("38) 1000Kitap'tan KOReader'a durum")
local eski_es = p.settings:readSetting("eslesmeler")
p.settings:saveSetting("eslesmeler", {
  ["/kobo/T/A.epub"] = { id = "900", adi = "Yaşam Yolu 1", yazar = "Anton Makarenko" },
  ["/kobo/T/B.epub"] = { id = "801", adi = "Şairin Romanı", yazar = "Murathan Mungan" },
  ["/kobo/T/C.epub"] = { id = "92807", adi = "Shenzen", yazar = "Guy Delisle" },
  ["/kobo/T/D.epub"] = { id = "359215", adi = "Walden", otomatik = true },
})
for _, y in ipairs({ "A", "B", "C", "D" }) do DOSYALAR["/kobo/T/" .. y .. ".epub"] = true end
YAN_DOSYALAR["/kobo/T/B.epub"] = { summary = { status = "reading" }, percent_finished = 0.4 }
YAN_DOSYALAR["/kobo/T/C.epub"] = { summary = { status = "complete" }, binkitap = { id = "92807", son_ko_durum = "complete" } }
durum["900"], durum["801"], durum["92807"], durum["359215"] = 1, 1, 2, 1
p.settings:delSetting("bk_durum_gorulen")
local once = istekSay("uye/kitap/modalVeBasimlar")
fm:durumlariAl()
kontrol(son("InfoMessage").text:find("durumlar alınıyor", 1, true) ~= nil, "ilerleme gösterildi")
calistir()
kontrol(istekSay("uye/kitap/modalVeBasimlar") == once + 3, "otomatik eşleşme sorulmadı, 3 kitaba bakıldı")
local sl = son("Menu")
local satir_a, satir_b, satir_c
for _, it in ipairs(sl.item_table) do
  if it.text:find("Yaşam Yolu", 1, true) then satir_a = it.text end
  if it.text:find("Şairin", 1, true) then satir_b = it.text end
  if it.text:find("Shenzen", 1, true) then satir_c = it.text end
end
kontrol(sl.title == "KOReader'a aktarılacak durumlar (2)", "başlık: " .. sl.title)
kontrol(satir_a and satir_a:find("^☑ ") and satir_a:find("durum yok → Bitti", 1, true), "hiç durumu olmayan seçili: " .. tostring(satir_a))
kontrol(satir_b and satir_b:find("^☐ ") and satir_b:find("Okunuyor → Bitti (%40 okunmuş)", 1, true), "okunuyor olan seçili değil: " .. tostring(satir_b))
kontrol(satir_c == nil, "KOReader'da bitmiş kitaba dokunulmadı")
menuSec(sl, function(it) return it.eylem == "onay" end)
kontrol(YAN_DOSYALAR["/kobo/T/A.epub"] and YAN_DOSYALAR["/kobo/T/A.epub"].summary.status == "complete"
  and YAN_DOSYALAR["/kobo/T/B.epub"].summary.status == "reading", "sadece seçilen işaretlendi")
kontrol(son("InfoMessage").text:find("1 kitabın KOReader durumu", 1, true) ~= nil, "özet")
-- Sitede değişince önerilir; taze önbellek yeniden istenmez
durum["92807"] = 3
once = istekSay("uye/kitap/modalVeBasimlar")
fm:durumlariAl(); calistir()
kontrol(istekSay("uye/kitap/modalVeBasimlar") == once and son("Menu").title == "KOReader'a aktarılacak durumlar (1)", "6 saat dolmadan yeniden sormadı; kalan tek fark listelendi")
ilerlet(7 * 3600)
fm:durumlariAl(); calistir()
sl = son("Menu")
satir_c = nil
for _, it in ipairs(sl.item_table) do if it.text:find("Shenzen", 1, true) then satir_c = it.text end end
kontrol(satir_c and satir_c:find("^☑ ") and satir_c:find("Bitti → Beklemede", 1, true), "sitede değişen önerildi: " .. tostring(satir_c))
menuSec(sl, function(it) return it.eylem == "onay" end)
kontrol(YAN_DOSYALAR["/kobo/T/C.epub"].summary.status == "abandoned" and YAN_DOSYALAR["/kobo/T/C.epub"].binkitap.son_ko_durum == "abandoned", "yan dosyada son_ko_durum da güncellendi")
p.settings:saveSetting("eslesmeler", eski_es)

-- Açılışta: sitede değişmişse sor
local kitap = p:kitapBilgisi()
okuyucu_ui.doc_settings.data.summary = { status = "reading" }
kitap.son_ko_durum = "reading"; p:kitapKaydetAyar(kitap)
p:bkDurumKaydet(kitap.id, 2)
durum[kitap.id] = 1
p:acilistaBkDurumu(kitap); calistir()
kontrol(#gosterilen == 0 or not son("ConfirmBox") or not son("ConfirmBox").text:find("durumu değişmiş", 1, true), "saat dolmadan bakmadı")
ilerlet(2 * 3600)
p:acilistaBkDurumu(kitap); calistir()
local cb = son("ConfirmBox")
kontrol(cb and cb.text:find("durumu değişmiş: Okudum", 1, true) and cb.text:find("\"Bitti\"", 1, true), "açılışta soruldu: " .. (cb and cb.text:gsub("\n", " / ") or "yok"))
local kuyruk_once = #p:kuyruk()
cb.ok_callback()
kontrol(okuyucu_ui.doc_settings.data.summary.status == "complete" and p:kitapBilgisi().son_ko_durum == "complete", "KOReader'da Bitti yapıldı")
p:koDurumuKontrol()
kontrol(#p:kuyruk() == kuyruk_once, "1000Kitap'a geri gönderilmedi (döngü yok)")
ilerlet(2 * 3600)
p:acilistaBkDurumu(kitap); calistir()
kontrol(son("ConfirmBox") == cb, "değişmeyince bir daha sormadı")
end

do
print("39) Okudum sonrası hedef bildirimi")
local yil = os.date("%Y")
kontrol(hedefler[yil] == 30, "hedef var")
durum["9517"] = -1
p:siraya({ tur = "durum", kitap_id = "9517", kitap_adi = "Kaos Lordu", durum = 1 })
p:kuyruguGonder(true); calistir()
local im = son("InfoMessage")
kontrol(im.text:find(yil .. " hedefin: 4 / 30 kitap.", 1, true) and im.text:find("26 kitap kaldı", 1, true) and im.timeout, "hedef bildirimi: " .. im.text:gsub("\n", " / "))
p.settings:saveSetting("hedef_bildirimi", false)
durum["9517"] = -1
p:siraya({ tur = "durum", kitap_id = "9517", kitap_adi = "Kaos Lordu", durum = 1 })
local n = #gosterilen
p:kuyruguGonder(true); calistir()
local yeni_hedef = false
for i = n + 1, #gosterilen do if gosterilen[i].text and gosterilen[i].text:find("hedefin", 1, true) then yeni_hedef = true end end
kontrol(not yeni_hedef, "ayar kapalıyken bildirim yok")
p.settings:saveSetting("hedef_bildirimi", nil)
end

do
print("40) Bu sürümde neler var")
local G = Plugin._guncelleme
kontrol(G.yenilikleriCoz("os.exit(3)") == nil and G.yenilikleriCoz("return { { surum = '1', maddeler = { io and 'x' or 'y' } } }")[1].maddeler[1] == "y",
  "sürüm notları boş ortamda okunuyor (kod çalışmıyor)")
kontrol(G.dahaYeni("1.0.0", "0.4.2") and not G.dahaYeni("0.4.2", "1.0.0") and G.dahaYeni("1.0.0", "0.10.9"), "0.4.2'den 1.0.0'a güncelleme görülür")
local yl = fm:yenilikListesi()
kontrol(yl and yl[1].surum == Plugin.SURUM and #yl[1].maddeler >= 1, "kurulu sürümün notları var")
local n = #gosterilen
fm.settings:saveSetting("son_gorulen_surum", "0.2.8")
fm:yenilikKontrol(); calistir()
local tv = son("TextViewer")
kontrol(#gosterilen > n and tv.title == "1000Kitap " .. Plugin.SURUM .. ": neler var" and tv.text:find("Sürüm 0.3.0", 1, true)
  and tv.text:find("Sürüm 0.2.9", 1, true) and not tv.text:find("Sürüm 0.2.8", 1, true), "güncellemeden sonra aradaki sürümler gösterildi")
kontrol(fm.settings:readSetting("son_gorulen_surum") == Plugin.SURUM, "görüldü olarak kaydedildi")
n = #gosterilen
fm:yenilikKontrol(); p:yenilikKontrol(); calistir()
kontrol(#gosterilen == n, "bir daha gösterilmedi")
local oge
for _, o in ipairs(fm:ayarlarMenusu()) do if o.text == "Bu sürümde neler var" then oge = o end end
oge.callback()
tv = son("TextViewer")
kontrol(tv.text:find("^Sürüm " .. Plugin.SURUM:gsub("%.", "%%.")) and not tv.text:find("Sürüm 0.2.9", 1, true), "menüden yalnızca bu sürüm")
end

do
print("41) 1000Kitap puanı ve popüler incelemeler")
kontrol(Plugin.puanYazi("7.8") == "★ 7,8" and Plugin.puanYazi(8) == "★ 8,0" and Plugin.puanYazi("7,26") == "★ 7,3"
  and Plugin.puanYazi(0) == nil and Plugin.puanYazi("") == nil and Plugin.puanYazi(11) == nil, "puan biçimi")
kontrol(Plugin.kitapEtiketi({ adi = "Gog", yazar = "Giovanni Papini", puan = 8.1 }) == "Gog — Giovanni Papini · ★ 8,1"
  and Plugin.kitapEtiketi({ adi = "Gog", yazar = "" }) == "Gog", "listelerde kitabın yanında puan")
local raf = Plugin.Api:rafListesi("ornek_okur", "okuyacaklari")
kontrol(raf[1].puan == 8.1 and raf[2].puan == nil, "raf listesinden puan okunuyor (0 = puan yok)")
p:populerIncelemeler()
local tv = son("TextViewer")
kontrol(tv.title:find("popüler incelemeler", 1, true) ~= nil, "incelemeler açıldı: " .. tv.title)
kontrol(tv.text:find("Ece · 5/10 puan verdi · 194 beğeni · 1 yorum\n\nDoğada yaşamak üzerine. @osgr da sevdi.…", 1, true) ~= nil,
  "yazan, verdiği puan, beğeni; etiketlenen okur metinde: " .. tv.text:sub(1, 120):gsub("\n", " / "))
kontrol(tv.text:find("1000kitap.com/gonderi/274933988", 1, true) and tv.text:find("Can · 3 beğeni\n\nKısa ve güzel.", 1, true)
  and not tv.text:find("Boş", 1, true), "kısaltılmışa bağlantı, boş inceleme atlandı")
-- Tarih yedeği: istatistik yoksa "Bitti" işaretleme günü
local ds = { readSetting = function(_, k) return ({ summary = { status = "complete", modified = "2025-03-14" } })[k] end }
local t = Plugin._okumaTarihleri(ds, nil)
kontrol(t and os.date("%d.%m.%Y %H:%M", t.bit) == "14.03.2025 12:00" and t.bas == t.bit and t.kaynak == "bitti", "istatistik yoksa Bitti günü")
local gelecek = { readSetting = function(_, k) return ({ summary = { modified = "2099-01-01" } })[k] end }
kontrol(Plugin._okumaTarihleri(gelecek, nil) == nil, "gelecekteki tarih gönderilmez")
end

do
print("42) 1000Kitap ekranı")
local function metinler(w, out, gorulen)
  out = out or {}; gorulen = gorulen or {}
  if type(w) ~= "table" or gorulen[w] then return out end
  gorulen[w] = true
  if type(w.text) == "string" then out[#out + 1] = w.text end
  if type(w.title) == "string" then out[#out + 1] = w.title end
  if w._tur == "ButtonTable" then
    for _, satir in ipairs(w.buttons) do for _, b in ipairs(satir) do out[#out + 1] = "[" .. b.text .. "]" end end
  end
  for _, c in ipairs(w) do metinler(c, out, gorulen) end
  return out
end
local function dugmeBul(w, metin, gorulen)
  gorulen = gorulen or {}
  if type(w) ~= "table" or gorulen[w] then return nil end
  gorulen[w] = true
  if w._tur == "ButtonTable" then
    for _, satir in ipairs(w.buttons) do for _, b in ipairs(satir) do if b.text == metin then return b end end end
  end
  for _, c in ipairs(w) do local b = dugmeBul(c, metin, gorulen); if b then return b end end
end
local function ekranBul()
  for i = #gosterilen, 1, -1 do if gosterilen[i].covers_fullscreen and gosterilen[i].veri then return gosterilen[i] end end
end
local yil = os.date("%Y")
DOSYALAR["/kobo/Walden - Thoreau.epub"] = true
G_reader_settings:saveSetting("lastfile", "/kobo/Walden - Thoreau.epub")
fm:sonAlintiKaydet({ tur = "ozel_not", metin = "Ormana gittim, çünkü bilinçli yaşamak istiyordum.", kitap_adi = "Walden", sayfa = "89" })
fm:ekranAc(); calistir()
local e = ekranBul()
kontrol(e ~= nil, "dosya tarayıcısında ekran açıldı")
local ok_ciz, hata_ciz = pcall(function() e:paintTo(nil, 0, 0) end)
kontrol(ok_ciz, "ekran KOReader gibi çizilebiliyor: " .. tostring(hata_ciz))
local hepsi = table.concat(metinler(e), " | ")
for _, beklenen in ipairs({ "1000Kitap", "SON OKUDUĞUN", "Henry David Thoreau", "[Devam et]", yil .. " OKUMA HEDEFİ", "4 / 30 kitap · 26 kitap kaldı",
    "OKUYACAKLARIM · 4 kitap", "[Ne okusam?]", "[Tümü (4)]", "SON ALINTIN", "“Ormana gittim, çünkü bilinçli yaşamak istiyordum.”",
    "Walden · s. 89 · az önce · gizli", "KÜTÜPHANE", "[Okuduklarımı aktar]", "[Durumları al]", "[Kitaplığım ›]", "[İleti yaz]", "[Menü ›]", "[Yenile]", "[Bekleyen yok]" }) do
  kontrol(hepsi:find(beklenen, 1, true) ~= nil, "ekranda: " .. beklenen)
end
kontrol(hepsi:find("★ 8,1", 1, true) ~= nil, "rafta 1000Kitap puanı")
dugmeBul(e, "Listeler").callback()
local ld = son("ButtonDialog")
kontrol(ld.title == "Kitap listeleri" and ld.buttons[1][1].text == "Sana özel öneriler" and #ld.buttons == 10
  and ld.buttons[9][1].text == "Konulara göre ›", "ekrandan kitap listelerine")
ld.buttons[9][1].callback()
local kd = son("ButtonDialog")
kontrol(kd.title == "Konulara göre" and kd.buttons[1][1].text == "Edebiyat" and #kd.buttons == 21, "ekrandan konulara")
-- Menü: eklentinin tüm özellikleri
dugmeBul(e, "Menü ›").callback()
local md = son("ButtonDialog")
local md_metin = {}
for _, satir in ipairs(md.buttons) do for _, b in ipairs(satir) do md_metin[#md_metin + 1] = b.text end end
local md_hepsi = table.concat(md_metin, " | ")
kontrol(md.title == "1000Kitap · tüm özellikler" and not md_hepsi:find("1000Kitap ekranı", 1, true)
  and md_hepsi:find("Ayarlar ›", 1, true) and md_hepsi:find("Kitap listeleri ›", 1, true) and md_hepsi:find("Ne okusam?", 1, true),
  "tüm özellikler listelendi: " .. md_hepsi:sub(1, 160))
local ayar_b
for _, satir in ipairs(md.buttons) do for _, b in ipairs(satir) do if b.text == "Ayarlar ›" then ayar_b = b end end end
ayar_b.callback()
local ad = son("ButtonDialog")
local toggle, geri_b
for _, satir in ipairs(ad.buttons) do for _, b in ipairs(satir) do
  if b.text:find("Uykuya geçerken bekleyenleri gönder", 1, true) then toggle = b end
  if b.text == "‹ Geri" then geri_b = b end
end end
kontrol(toggle and toggle.text:sub(1, 4) == "☑ " and geri_b ~= nil, "ayarlarda açık/kapalı işareti ve Geri: " .. tostring(toggle and toggle.text))
toggle.callback(); calistir()
local ad2 = son("ButtonDialog")
local toggle2
for _, satir in ipairs(ad2.buttons) do for _, b in ipairs(satir) do if b.text:find("Uykuya geçerken", 1, true) then toggle2 = b end end end
kontrol(fm.settings:readSetting("uykuda_gonder") == false and toggle2 and toggle2.text:sub(1, 4) == "☐ ", "değiştirince liste yeniden açıldı, yeni durumla")
toggle2.callback(); calistir()
kontrol(fm.settings:nilOrTrue("uykuda_gonder"), "geri açıldı")
for _, satir in ipairs(son("ButtonDialog").buttons) do for _, b in ipairs(satir) do if b.text == "‹ Geri" then b.callback() end end end
kontrol(son("ButtonDialog").title == "1000Kitap · tüm özellikler", "Geri ile üst listeye dönüldü")
-- Hedefe dokununca hedef menüsü
local hedef_t
local function tiklanirBul(w, gorulen)
  gorulen = gorulen or {}
  if type(w) ~= "table" or gorulen[w] then return end
  gorulen[w] = true
  if w.callback and w._tur == "InputContainer" then
    local m = table.concat(metinler(w), " ")
    if m:find("kitap kaldı", 1, true) then hedef_t = w end
  end
  for _, c in ipairs(w) do tiklanirBul(c, gorulen) end
end
tiklanirBul(e)
kontrol(hedef_t ~= nil, "hedef bölümü dokunulabilir")
hedef_t:onTap()
kontrol(son("ButtonDialog").title == yil .. " okuma hedefi", "hedefe dokununca hedef menüsü: " .. son("ButtonDialog").title)
-- Dosya tarayıcısı kapanınca ekran da kapanır
fm:onCloseWidget()
kontrol(e._kapandi and fm._ekran == nil, "eklenti kapanınca ekran da kapandı")
fm:ekranAc(); e = ekranBul()
-- Küçük ekranda: son alıntı çıkar, yine çizilebilir
EKRAN_YUK = 700
fm:ekranAc(); local ke = ekranBul()
local khepsi = table.concat(metinler(ke), " | ")
ok_ciz, hata_ciz = pcall(function() ke:paintTo(nil, 0, 0) end)
kontrol(ok_ciz and not khepsi:find("SON ALINTIN", 1, true) and khepsi:find("[Yenile]", 1, true), "küçük ekranda son alıntı gizlendi, alt satır yerinde: " .. tostring(hata_ciz))
ke:onClose()
EKRAN_YUK = 1200
fm:ekranAc(); e = ekranBul()
dugmeBul(e, "Devam et").callback()
kontrol(e._kapandi and acilan == "/kobo/Walden - Thoreau.epub", "Devam et son kitabı açtı")
-- Tümü listesi
fm:ekranAc(); e = ekranBul()
dugmeBul(e, "Tümü (4)").callback()
local tm = son("Menu")
kontrol(tm.title:find("Okuyacaklarım (4)", 1, true) ~= nil, "Tümü listesi: " .. tm.title)
local puanli
for _, it in ipairs(tm.item_table) do if it.mandatory == "★ 8,1" then puanli = it end end
kontrol(puanli ~= nil, "Tümü listesinde puan sağda")
-- Hata olursa ekran açılmaz, günlüğe yazılır
local eski = Plugin.ekranIcerigi
Plugin.ekranIcerigi = function() error("deneme hatası") end
p.settings:delSetting("hata_gunlugu")
fm:ekranAc()
Plugin.ekranIcerigi = eski
kontrol(son("InfoMessage").text:find("ekranı açılamadı", 1, true) and p:hataGunluguMetni():find("deneme hatası", 1, true), "ekran hatası güvenle yakalandı")
p.settings:delSetting("hata_gunlugu")
-- Çizimde hata olursa KOReader çökmez
Plugin.ekranIcerigi = function() return { getSize = function() return { w = 1, h = 1 } end, paintTo = function() error("çizim hatası") end } end
fm:ekranAc()
local he = ekranBul()
local ok_h = pcall(function() he:paintTo(nil, 0, 0) end)
calistir()
Plugin.ekranIcerigi = eski
kontrol(ok_h and he._kapandi and son("InfoMessage").text:find("gösterilemedi", 1, true)
  and p:hataGunluguMetni():find("çizim hatası", 1, true), "çizim hatası yakalandı, ekran kapandı, günlüğe yazıldı")
p.settings:delSetting("hata_gunlugu")
-- Okurken
p:ekranAc(); calistir()
e = ekranBul()
ok_ciz, hata_ciz = pcall(function() e:paintTo(nil, 0, 0) end)
kontrol(ok_ciz, "okurken ekran çizilebiliyor: " .. tostring(hata_ciz))
e:yenile()
ok_ciz, hata_ciz = pcall(function() e:paintTo(nil, 0, 0) end)
kontrol(ok_ciz, "yenilendikten sonra da çizilebiliyor: " .. tostring(hata_ciz))
hepsi = table.concat(metinler(e), " | ")
for _, beklenen in ipairs({ "ŞU AN OKUDUĞUN", "Walden", "[Vurgular]", "[İleti yaz]", "[Puan ver]", "[Bitirdim]",
    "[Kitap bilgisi]", "[Alıntılar]", "[İncelemeler]", "[Durum]", "[Menü ›]" }) do
  kontrol(hepsi:find(beklenen, 1, true) ~= nil, "okurken ekranda: " .. beklenen)
end
kontrol(hepsi:find("s. %d+ / %d+") ~= nil and hepsi:find("%%%d+") ~= nil, "sayfa ve yüzde: " .. (hepsi:match("s%. %d+ / %d+[^|]*") or "yok"))
kontrol(not hepsi:find("KÜTÜPHANE", 1, true), "okurken kütüphane kısayolları yok")
e:onClose()
kontrol(e._kapandi and p._ekran == nil, "kapandı")
-- Sığmayınca: önce son alıntı çıkar, sonra raf kapaksız kısalır
local function w(h) return { getSize = function() return { h = h } end } end
local bl = { { ad = "kitap", w = w(200) }, { ad = "raf", w = w(250), kisa = function() return w(60) end },
             { ad = "alinti", w = w(120), atilabilir = true } }
local sec = Plugin.ekranaSigdir(bl, 100, 1000)
kontrol(#sec == 3, "sığıyorsa hepsi")
sec = Plugin.ekranaSigdir(bl, 100, 560)
kontrol(#sec == 2 and bl[3].atildi and not bl[2].kisaldi, "önce son alıntı çıktı")
bl = { { ad = "kitap", w = w(200) }, { ad = "raf", w = w(250), kisa = function() return w(60) end },
       { ad = "alinti", w = w(120), atilabilir = true } }
sec = Plugin.ekranaSigdir(bl, 100, 400)
kontrol(#sec == 2 and bl[3].atildi and bl[2].kisaldi and sec[2]:getSize().h == 60, "sonra raf kısaldı")
bl = { { ad = "raf", w = w(250), kisa_sira = 2, kisa = function() return w(60) end },
       { ad = "kutuphane", w = w(150), kisa_sira = 1, kisa = function() return w(60) end } }
Plugin.ekranaSigdir(bl, 100, 420)
kontrol(bl[2].kisaldi and not bl[1].kisaldi, "önce kütüphane kısalır, raf kapakları kalır")
kontrol(eylemler.binkitap_ekran and eylemler.binkitap_ekran.event == "BinKitapEkran", "hareket eylemi kayıtlı")
end

do
print("43) Kitap listeleri (Kitaplar sekmesi)")
local lm = fm:kesifListeleriMenusu()
kontrol(#lm == 9 and lm[1].text == "Sana özel öneriler" and lm[2].text == "Son 7 günün en çok okunanları"
  and lm[8].text == "Romanlar" and lm[9].text == "Konulara göre", "sekiz liste + konular: " .. #lm)
local km = lm[9].sub_item_table_func()
kontrol(#km == 20 and km[1].text == "Edebiyat" and km[18].text == "Bilimkurgu", "20 konu")
km[18].callback()
local kq = kesif_istekleri[#kesif_istekleri]
kontrol(kq.konu == "10279" and son("Menu").title == "Bilimkurgu konulu kitaplar", "konu listesi: konu=" .. tostring(kq.konu))
lm[8].callback()
kq = kesif_istekleri[#kesif_istekleri]
kontrol(kq.eserTuru == "roman", "romanlar")
lm[2].callback()
local q = kesif_istekleri[#kesif_istekleri]
kontrol(q.donem == "son7Gun" and q.siralama == "okunan" and q.sayfa == "1" and q.kume == "-1" and q.z == "0", "ilk sayfa isteği")
local m = son("Menu")
kontrol(m.title == "Son 7 günün en çok okunanları" and #m.item_table == 3, "iki kitap + daha fazla (reklam atlandı)")
kontrol(m.item_table[1].text == "1. Hizmetçi — Freida McFadden" and m.item_table[1].mandatory == "★ 8,5", "puan sağda: " .. m.item_table[1].text)
kontrol(m.item_table[2].text:find("✓ Walden — Henry David Thoreau · Okudum", 1, true) ~= nil, "Kobo'daki ve okunmuş işaretli: " .. m.item_table[2].text)
m.onMenuSelect(m, m.item_table[3])
q = kesif_istekleri[#kesif_istekleri]
kontrol(q.sayfa == "2" and q.kume == "777" and q.z == "10", "sonraki sayfa kume/z ile")
kontrol(#m.item_table == 3 and m.item_table[3].text == "3. ✓ Gog — Giovanni Papini", "sonraki sayfa eklendi, liste bitti: " .. m.item_table[3].text)
lm[1].callback()
q = kesif_istekleri[#kesif_istekleri]
kontrol(q.siralama == "sizeOzel" and q.okuma == "haric", "sana özel öneriler: okuduklarım hariç")
m = son("Menu")
m.onMenuSelect(m, m.item_table[1])
local kart = son("ButtonDialog")
kontrol(kart.title:find("Hizmetçi\nFreida McFadden\n★ 8,5 · 15490 okunma\nSon 7 Gün: 323 okuma\nKobo'nda yok", 1, true) ~= nil, "kitap kartı: " .. kart.title:gsub("\n", " / "))
local ekle
for _, satir in ipairs(kart.buttons) do for _, b in ipairs(satir) do if b.text == "Okuyacaklarıma ekle" then ekle = b end end end
local once = #fm:kuyruk()
durum["378538"] = -1
ekle.callback(); calistir()
kontrol(durum["378538"] == 0, "Okuyacaklarına eklendi")
m.onMenuSelect(m, m.item_table[2])
kart = son("ButtonDialog")
local ac, ekle2
for _, satir in ipairs(kart.buttons) do for _, b in ipairs(satir) do if b.text == "Kobo'da aç" then ac = b end; if b.text == "Okuyacaklarıma ekle" then ekle2 = b end end end
kontrol(ac and not ekle2, "okunmuş ve Kobo'daki kitapta: aç var, ekle yok")
ac.callback()
kontrol(acilan == "/kobo/Walden - Thoreau.epub", "Kobo'da açıldı")
end

do
print("44) Liste satırlarında sağdaki yazı kısa")
fm:secimListesi{ baslik = "Deneme", ogeler = {
  { metin = "Kitap", ek = "Çok Uzun Bir Calibre Klasör Adı (Yazar Adı Soyadı) 12345 ve daha da uzun", veri = 1 },
  { metin = "Kısa", ek = "kısa", veri = 2 } }, onay = function() end }
local sm = son("Menu")
local uzun, kisa
for _, it in ipairs(sm.item_table) do
  if it.text == "☐ Kitap" then uzun = it.mandatory end
  if it.text == "☐ Kısa" then kisa = it.mandatory end
end
local harf = select(2, uzun:gsub("[^\128-\191]", ""))
kontrol(harf <= 33 and uzun:sub(-3) == "…" and kisa == "kısa", "uzun klasör adı kısaltıldı: " .. uzun)
kontrol(Plugin.sagYazi(nil) == nil and Plugin.sagYazi("") == nil and Plugin.sagYazi("ğüşiöç ĞÜŞİÖÇ ğüşiöç ĞÜŞİÖÇ ğüşiöç ĞÜ") == "ğüşiöç ĞÜŞİÖÇ ğüşiöç ĞÜŞİÖÇ ğüşi…", "Türkçe harfler bölünmeden kısaltılıyor")
end

do
print("45) SimpleUI ve ana menüde kısayol")
local kayitli = {}
package.preload["features/sui_quickactions"] = function()
  return { register = function(d) kayitli[d.id] = d end }
end
kontrol(fm:simpleUIKaydet() == true, "SimpleUI'ye kaydoldu")
local d = kayitli.binkitap_ekran
kontrol(d and d.label == "1000Kitap" and d.icon:match("/1000kitap%.svg$") and d.is_in_place and d.is_async_in_place,
  "1000Kitap eylemi: etiket, simge, yerinde açılır")
kontrol(kayitli.binkitap_ne_okusam and kayitli.binkitap_okuyacaklara_ekle and kayitli.binkitap_kitap_listeleri, "diğer eylemler de var")
local n = #gosterilen
d.execute({ fm = { binkitap = fm } })
local acilan_ekran
for i = n + 1, #gosterilen do if gosterilen[i].covers_fullscreen and gosterilen[i].veri then acilan_ekran = gosterilen[i] end end
kontrol(acilan_ekran ~= nil, "SimpleUI'den 1000Kitap ekranı açıldı")
acilan_ekran:onClose()
kayitli.binkitap_kitap_listeleri.execute({ fm = { binkitap = fm } })
kontrol(son("ButtonDialog").title == "Kitap listeleri", "SimpleUI'den kitap listeleri")
kontrol(io.open("binkitap.koplugin/1000kitap.svg", "rb") ~= nil, "simge dosyası eklentinin kök klasöründe (güncelleyici alt klasörü kabul etmiyor)")
local mi = {}
fm:addToMainMenu(mi)
kontrol(mi.binkitap and mi.binkitap_ekran and mi.binkitap_ekran.sorting_hint == "main", "ana menü sekmesinde 1000Kitap ekranı")
n = #gosterilen
mi.binkitap_ekran.callback()
local e2
for i = n + 1, #gosterilen do if gosterilen[i].covers_fullscreen and gosterilen[i].veri then e2 = gosterilen[i] end end
kontrol(e2 ~= nil, "ana menüden açıldı")
e2:onClose()
package.preload["features/sui_quickactions"] = nil
package.loaded["features/sui_quickactions"] = nil
end

do
print("46) Sayfa ilerlemesi")
local k = p:kitapBilgisi()
-- Okuyorum: hemen gönderir
durum[k.id] = 2; sayfa2[k.id] = 0
p:sayfamiGonder(); calistir()
kontrol((sayfa2[k.id] or 0) > 0 and son("InfoMessage").text:find("1000Kitap'ta sayfan güncellendi: s. " .. sayfa2[k.id] .. " / ", 1, true),
  "Okuyorum'da sayfa gönderildi: " .. son("InfoMessage").text)
-- Okuyacağım: önce Okuyorum yapmayı önerir
durum[k.id] = 0; sayfa2[k.id] = 0
p:sayfamiGonder(); calistir()
local cb = son("ConfirmBox")
kontrol(cb and cb.text:find("\"Okuyacağım\" görünüyor", 1, true) and cb.ok_text == "Okuyorum yap ve gönder", "Okuyorum yapmayı önerdi")
cb.ok_callback(); calistir()
kontrol(durum[k.id] == 2 and sayfa2[k.id] > 0, "Okuyorum yapıldı ve sayfa gönderildi")
-- Okuma başka baskıdaysa o okumaya yazılır
durum[k.id] = 2; durum["555"] = 2; baska_baski[k.id] = "555"; sayfa2["555"] = 0
p:sayfamiGonder(); calistir()
kontrol(sayfa2["555"] > 0 and son("InfoMessage").text:find("sayfan güncellendi", 1, true), "başka baskıdaki okumaya yazıldı")
baska_baski[k.id] = nil
-- Okudum: ne yapılacağını sorar
durum[k.id] = 1; sayfa2[k.id] = 0
p:sayfamiGonder(); calistir()
local od = son("ButtonDialog")
kontrol(od.title:find("\"Okudum\" görünüyor", 1, true) and od.buttons[1][1].text == "Yeniden okuyorum: yeni okuma başlat"
  and od.buttons[2][1].text == "\"Okudum\" yanlış: Okuyorum yap" and sayfa2[k.id] == 0, "Okudum'da seçenek sundu, kendiliğinden dokunmadı")
od.buttons[1][1].callback(); calistir()
kontrol(durum[k.id] == 2 and okuma_tarihi[k.id] == false and (YENI_OKUMA[k.id] or 0) >= 1 and sayfa2[k.id] > 0,
  "yeni okuma (yeniOkuma=1) başlatıldı ve sayfa gönderildi")
durum[k.id] = 1; sayfa2[k.id] = 0
YENI_OKUMA[k.id] = nil
p:sayfamiGonder(); calistir()
son("ButtonDialog").buttons[2][1].callback(); calistir()
kontrol(durum[k.id] == 2 and okuma_tarihi[k.id] == false and YENI_OKUMA[k.id] == nil and sayfa2[k.id] > 0, "Okudum düzeltildi (yeni okuma açmadan) ve sayfa gönderildi")
durum[k.id] = 1; sayfa2[k.id] = 0
p:sayfamiGonder(); calistir()
son("ButtonDialog").buttons[3][1].callback(); calistir()
kontrol(durum[k.id] == 1 and sayfa2[k.id] == 0, "Vazgeç: hiçbir şey değişmedi")
-- Sıradaki ilerleme atlanırsa sebebi günlükte
p.settings:delSetting("hata_gunlugu")
durum[k.id] = 0
p:siraya({ tur = "ilerleme", kitap_id = k.id, kitap_adi = k.adi, yuzde = 0.4, basili_sayfa = k.basili_sayfa })
p:kuyruguGonder(true); calistir()
local gm = p:hataGunluguMetni()
kontrol(gm:find("İlerleme · gönderilmedi", 1, true) and gm:find("sayfa yalnızca \"Okuyorum\"", 1, true), "atlanan ilerlemenin sebebi günlükte: " .. gm:gsub("\n", " / "))
p.settings:delSetting("hata_gunlugu")
-- Otomatik eşleşmede de ilerleme sıraya girer
local once = #p:kuyruk()
k.otomatik = true
p:ilerlemeSirala(k)
kontrol(#p:kuyruk() == once + 1, "otomatik eşleşmede ilerleme sıraya girdi (Okuyorum şartıyla)")
k.otomatik = nil
p.settings:saveSetting("kuyruk", {})
-- İlk açılışta bir kez sorulur
p.settings:delSetting("ilerleme_modu"); p.settings:delSetting("ilerleme_soruldu")
p:ilerlemeSor()
local sd = son("ButtonDialog")
kontrol(sd.title:find("kaçıncı sayfada olduğun güncellensin mi", 1, true) and sd.buttons[1][1].text == "Kitabı kapatınca / uykuya geçince", "ilerleme sorusu")
sd.buttons[1][1].callback()
kontrol(p.settings:readSetting("ilerleme_modu") == "kapaninca", "seçim kaydedildi")
local n = #gosterilen
p.settings:delSetting("ilerleme_modu")
p:ilerlemeSor()
kontrol(#gosterilen == n, "bir daha sorulmadı")
p.settings:saveSetting("ilerleme_modu", "kapaninca")
local menu_metin = {}
for _, o in ipairs(p:menuOgeleri()) do menu_metin[#menu_metin + 1] = o.text or "" end
kontrol(table.concat(menu_metin, "|"):find("Sayfamı şimdi gönder", 1, true), "okuyucu menüsünde")
end

-- Ayrı fonksiyon: ana bölümün 200 yerel değişken sınırına takılmasın
;(function()
print("47) Kobo Senkron (1000Kitap'ın içinde)")
kontrol(Plugin.Kobo ~= nil and fm.kobo ~= nil and p.kobo ~= nil, "Kobo bölümü yüklendi, her örnekte hazır")
kontrol(eylemler.kobosync_sync and eylemler.kobosync_sync.event == "KoboSyncNow" and eylemler.kobosync_menu and eylemler.kobosync_report,
  "eski eklentinin hareket eylemleri aynı adlarla kayıtlı")
local function fmMetinleri(pl) local t = {} for _, o in ipairs(pl:menuOgeleri()) do t[#t + 1] = o.text or "" end return table.concat(t, "|") end
kontrol(not fmMetinleri(fm):find("Kobo Senkron", 1, true), "Kobo veritabanı yoksa menüde görünmüyor")

-- Kobo veritabanı ve kitaplar
local DB = "/mnt/onboard/.kobo/KoboReader.sqlite"
DOSYALAR[DB] = true
local K1, K2 = "/kobo/Kobo Kitap.epub", "/kobo/Kobo Iki.epub"
DOSYALAR[K1] = true; DOSYALAR[K2] = true
local METIN = "Uzun bir yolculuğun ilk adımı burada başlar. Deniz sakin, rüzgâr hafifti. Sonra fırtına geldi ve her şey değişti."
local KOBO = {
  kolonlar = {
    Bookmark = { "BookmarkID", "VolumeID", "ContentID", "StartContainerPath", "Text", "Annotation", "DateCreated", "ChapterProgress", "Type", "Hidden" },
    Shelf = { "Name", "InternalName", "_IsDeleted" },
    ShelfContent = { "ShelfName", "ContentId", "_IsDeleted" },
  },
  kitaplar = {
    { "file://" .. K1, "Kobo Kitap", "Yazar Bir", 1, 42, "2099-01-01T10:00:00Z", "" },
    { "file://" .. K2, "Kobo İki", "Yazar İki", 2, 100, "2099-01-02T10:00:00Z", "" },
  },
  isaretler = {
    { "b1", "file://" .. K1, "file://" .. K1 .. "#(1)ch1.xhtml", "ch1.xhtml#point(/1/4)", "Deniz sakin, rüzgâr hafifti.", "", "2026-11-01T09:00:00Z", 0.2, "highlight" },
    { "b2", "file://" .. K1, "file://" .. K1 .. "#(1)ch1.xhtml", "ch1.xhtml#point(/1/6)", "fırtına geldi", "Önemli an", "2026-11-01T09:05:00Z", 0.8, "note" },
    { "b3", "file://" .. K1, "file://" .. K1 .. "#(1)ch9.xhtml", "ch9.xhtml#point(/1/8)", "Kitapta olmayan bir cümle", "", "2026-11-01T09:06:00Z", 0.9, "highlight" },
    { "b4", "file://" .. K2, "file://" .. K2 .. "#(1)ch1.xhtml", "ch1.xhtml#point(/1/2)", "ilk adımı burada başlar", "", "2026-11-02T09:00:00Z", 0.1, "highlight" },
  },
  raflar = { { "Yaz okumaları", "Yaz okumaları" } },
  raf_icerik = { { "Yaz okumaları", "file://" .. K1 } },
}
local sq3_eski = package.loaded["lua-ljsqlite3/init"]
package.loaded["lua-ljsqlite3/init"] = { open = function()
  local conn = {}
  function conn:prepare(sql)
    local st, satirlar = { i = 0 }, nil
    local tablo = sql:match("PRAGMA table_info%((%w+)%)")
    function st:bind(...) self.baglar = { ... }; return self end
    function st:step()
      if not satirlar then
        satirlar = {}
        local bag = self.baglar and self.baglar[1]
        if tablo then for _, c in ipairs(KOBO.kolonlar[tablo] or {}) do satirlar[#satirlar + 1] = { 0, c } end
        elseif sql:find("FROM content", 1, true) then for _, k in ipairs(KOBO.kitaplar) do if not bag or bag == k[1] then satirlar[#satirlar + 1] = k end end
        elseif sql:find("FROM Bookmark", 1, true) then for _, b in ipairs(KOBO.isaretler) do if not bag or bag == b[2] then satirlar[#satirlar + 1] = b end end
        elseif sql:find("FROM ShelfContent", 1, true) then satirlar = KOBO.raf_icerik
        elseif sql:find("FROM Shelf", 1, true) then satirlar = KOBO.raflar end
      end
      self.i = self.i + 1
      return satirlar[self.i]
    end
    function st:close() end
    return st
  end
  function conn:close() end
  return conn
end }
-- Tek bölümlük sahte kitap: findAllText metinde arar, konumlar karakter sırası
local function sahteBelge(metin)
  local d = { konum = 0 }
  local function xp(i) return "/body/DocFragment[1]/body/p/text()." .. i end
  local function ofs(x) return tonumber(tostring(x):match("%.(%d+)$")) or 0 end
  function d:getPageCount() return 10 end
  function d:isXPointerInDocument(x) return x == "/body/DocFragment[1]" end
  function d:getDocumentFileContent(yol)
    if yol == "META-INF/container.xml" then return '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>' end
    if yol == "OEBPS/content.opf" then return '<package><manifest><item id="c1" href="ch1.xhtml"/></manifest><spine><itemref idref="c1"/></spine></package>' end
  end
  -- crengine findText: bulunduğu yerden ileri arar, ilk eşleşmeden ~2 sayfa sonra durur
  function d:gotoXPointer(x) self.konum = ofs(x) end
  function d:findText(desen)
    SAHTE_ARAMA.hizli = SAHTE_ARAMA.hizli + 1
    local hits, i, sinir = {}, self.konum + 1, nil
    while true do
      local a, b = metin:find(desen, i, true)
      if not a or (sinir and a > sinir) then break end
      hits[#hits + 1] = { start = xp(a - 1), ["end"] = xp(b) }
      sinir = sinir or (b + 40)
      i = b + 1
    end
    if #hits == 0 then return nil end
    return hits, #hits
  end
  function d:getPageFromXPointer(x) return 1 + math.floor(ofs(x) / 20) end
  function d:getPageXPointer(pg) return xp((pg - 1) * 20) end
  function d:findAllText(desen)
    SAHTE_ARAMA.tam = SAHTE_ARAMA.tam + 1
    local hits, i = {}, 1
    while true do
      local a, b = metin:find(desen, i, true)
      if not a then break end
      hits[#hits + 1] = { start = xp(a - 1), ["end"] = xp(b) }
      i = b + 1
    end
    return hits
  end
  function d:getTextFromXPointers(a, b) return metin:sub(ofs(a) + 1, ofs(b)) end
  function d:compareXPointers(a, b) local x, y = ofs(a), ofs(b); return x < y and 1 or (x == y and 0 or -1) end
  function d:getToc() return {} end
  function d:getEPubCFIRangeFromXPointers() return nil end
  function d:setupDefaultView() end
  function d:requestDomVersion() end
  function d:loadDocument() return true end
  function d:render() end
  function d:close() end
  return d
end
rawset(_G, "KOBO_BELGE", function() return sahteBelge(METIN) end)
rawset(_G, "SAHTE_ARAMA", { hizli = 0, tam = 0 })
FS["/tmp"] = FS["/tmp"] or {}
local function birTur() -- şu an bekleyen zamanlanmış işleri bir kez çalıştır
  local n = #zamanlanan
  for _ = 1, n do local f = table.remove(zamanlanan, 1); if f then f() end end
end
package.preload["apps/reader/modules/readerannotation"] = function() return {} end

kontrol(fmMetinleri(fm):find("Kobo Senkron", 1, true) ~= nil, "Kobo veritabanı varsa 1000Kitap menüsünde Kobo Senkron")
local km = fm:koboMenusu()
local km_metin = {}
for _, o in ipairs(km) do km_metin[#km_metin + 1] = o.text end
kontrol(table.concat(km_metin, "|") == "Şimdi senkronize et|Kobo vurgularını 1000Kitap'a gönder|Gönderilenleri 1000Kitap'la karşılaştır|Kobo'da notlu kitaplar|Koleksiyonlar|Ayarlar|Hakkında",
  "Kobo alt menüsü (dosya tarayıcısı): " .. table.concat(km_metin, "|"))

-- Dosya tarayıcısından tam senkron: listeler ve ilerleme hemen, notlar arka planda
ALT.bekle = true
local alt_bas = ALT.sayi
fm:onKoboSyncNow()
local ilk = son("InfoMessage")
kontrol(ilk and ilk.text:find("2 kitabın okuma ilerlemesi Kobo'dan güncellendi.", 1, true)
  and ilk.text:find("Kobo listeleri: 3 kitap eklendi", 1, true)
  and ilk.text:find("Kobo notları arka planda aktarılıyor: 2 kitap, 4 not.", 1, true) and ilk.timeout,
  "listeler/ilerleme hemen; notlar arka planda (ekran kilitlenmiyor): " .. (ilk and ilk.text:gsub("\n", " / ") or "yok"))
kontrol(Plugin.Kobo.arkaCalisiyor() and ALT.sayi == alt_bas, "sıraya alındı, kitap henüz açılmadı")
birTur()
kontrol(ALT.sayi == alt_bas + 1, "ilk kitap ayrı bir süreçte açıldı")
local dm = Plugin.Kobo.arkaDurumMetni() or ""
kontrol(dm:find("Kobo notları aktarılıyor · %75", 1, true) and dm:find("1 / 2 kitap: Kobo Kitap", 1, true)
  and dm:find("3 / 3 not arandı", 1, true) and dm:find("Toplam: 0 sn", 1, true),
  "durum: yüzde notlara göre, kitap ve not sırası: " .. dm:gsub("\n", " / "))
fm:onKoboSyncNow()
local durum_d = son("ButtonDialog")
kontrol(durum_d.title:find("Kobo notları aktarılıyor", 1, true) and durum_d.buttons[1][1].text == "Durdur",
  "sürerken yeniden başlatmak yerine durumu ve Durdur'u gösterdi")
local kmd = fm:koboMenusu()
kontrol(kmd[1].text_func() == "Kobo aktarımı sürüyor · %75" and kmd[3].text == "Kobo vurgularını 1000Kitap'a gönder",
  "Kobo menüsünde ilerleme")
fm:ekranAc()
local ekr0
for i = #gosterilen, 1, -1 do if gosterilen[i].covers_fullscreen and gosterilen[i].veri then ekr0 = gosterilen[i]; break end end
local function bul0(w, metin, gor)
  gor = gor or {}
  if type(w) ~= "table" or gor[w] then return nil end
  gor[w] = true
  if w._tur == "ButtonTable" then for _, st in ipairs(w.buttons) do for _, b in ipairs(st) do if b.text == metin then return b end end end end
  for _, c in ipairs(w) do local b = bul0(c, metin, gor); if b then return b end end
end
kontrol(ekr0 and bul0(ekr0, "Kobo aktarımı %75 ›"), "1000Kitap ekranında ilerleme")
ekr0:onClose()
ALT.bekle = false
calistir()
local ozet = son("InfoMessage")
kontrol(ozet and ozet.text:find("Kobo notları aktarıldı", 1, true) and ozet.text:find("2 kitaba 2 vurgu ve 1 not eklendi.", 1, true)
  and ozet.text:find("1 not/vurgu eşleşmedi", 1, true) and ozet.text:find("Süre: 0 sn", 1, true) and not Plugin.Kobo.arkaCalisiyor(),
  "bitince özet: " .. (ozet and ozet.text:gsub("\n", " / ") or "yok"))
local hiz_log
for _, l in ipairs(loglar) do if l:find("Kobo: Kobo Kitap: açılış", 1, true) then hiz_log = l end end
local hizli_n, tam_n = (hiz_log or ""):match("(%d+) hızlı / (%d+) tam arama")
kontrol(tonumber(hizli_n) and tonumber(hizli_n) >= 2 and tonumber(tam_n) >= 1,
  "Kobo'nun bölümünden arandı; yalnızca bölümü bilinmeyen not bütün kitapta arandı: " .. tostring(hiz_log))
local y1 = YAN_DOSYALAR[K1]
local ann1 = y1 and y1.annotations or {}
kontrol(#ann1 == 2 and ann1[1].text == "Deniz sakin, rüzgâr hafifti." and ann1[2].note == "Önemli an"
  and ann1[1].kobo_id == "b1" and ann1[2].kobo_id == "b2" and y1.annotations_externally_modified == true,
  "vurgu ve not kitabın yan dosyasına eklendi, Kobo'dan geldiği işaretli")
kontrol(Plugin.yuzde(1, 3) == "%33" and Plugin.yuzde(0, 0) == "%0" and Plugin.yuzde(5, 5) == "%100", "yüzde yazımı")
kontrol(ann1[1].kobo_oran and ann1[1].kobo_oran > 0 and ann1[1].kobo_oran < 1, "Kobo vurgusunun kitaptaki yeri kaydedildi")
kontrol(y1.kobosync_imported and y1.kobosync_imported.b1 and y1.kobosync_imported.b2 and y1.kobosync_failed and y1.kobosync_failed.b3,
  "aktarılan ve bulunamayan Kobo kayıtları eski eklentiyle aynı anahtarlarda")
kontrol(YAN_DOSYALAR[K2] and #YAN_DOSYALAR[K2].annotations == 1, "ikinci kitaba da eklendi")
kontrol(y1.percent_finished == 0.42 and y1.summary and y1.summary.status == "reading" and y1.last_percent == 0.42,
  "okuma ilerlemesi Kobo'dan geldi")
kontrol(YAN_DOSYALAR[K2].summary.status == "complete" and YAN_DOSYALAR[K2].percent_finished == 1, "Kobo'da bitmiş kitap KOReader'da da bitti")
kontrol(RC.coll["Yaz okumaları"] and RC.coll["Yaz okumaları"][K1] and RC.coll["Kobo vurgu ve notları"]
  and RC.coll["Kobo vurgu ve notları"][K1] and RC.coll["Kobo vurgu ve notları"][K2], "Kobo listesi ve notlu kitaplar koleksiyonu")
-- İkinci senkron: aynı notlar tekrar eklenmez
local alt_once = ALT.sayi
fm:onKoboSyncNow(); calistir()
kontrol(#YAN_DOSYALAR[K1].annotations == 2 and #YAN_DOSYALAR[K2].annotations == 1 and ALT.sayi == alt_once,
  "ikinci senkronda tekrar eklenmedi, kitap bile açılmadı")
kontrol(son("InfoMessage").text == "Kobo senkron: her şey güncel.", "her şey güncel dedi")
-- Kobo'da listeden çıkarılınca KOReader'da da çıkar
KOBO.raf_icerik = {}
fm:onKoboSyncNow()
kontrol(RC.coll["Yaz okumaları"] == nil, "Kobo'da boşalan liste KOReader'dan da kalktı")

-- Kobo'da notlu kitaplar listesi
fm:koboRapor()
local rap = son("Menu")
local rap_s = {}
for _, it in ipairs(rap.item_table) do rap_s[#rap_s + 1] = it.text .. (it.mandatory and (" [" .. it.mandatory .. "]") or "") end
kontrol(rap and rap.title == "Kobo'da notlu kitaplar" and table.concat(rap_s, " | ")
  == "2 kitap · 3 vurgu · 1 not · 0 yer imi | Kobo Kitap [2 vurgu · 1 not !] | Kobo İki [1 vurgu ✓]", "notlu kitaplar listesi: " .. table.concat(rap_s, " | "))
rap.onMenuHold(rap, rap.item_table[2])
kontrol(son("TextViewer").text:find("(!) «Kitapta olmayan bir cümle»", 1, true), "bulunamayan not işaretli gösterildi")

-- Okuyucu: kitap açılınca yeni Kobo notu eklenir
KOBO.isaretler[#KOBO.isaretler + 1] = { "b5", "file://" .. K2, "file://" .. K2 .. "#(1)ch1.xhtml", "ch1.xhtml#point(/1/9)", "her şey değişti", "", "2026-11-03T09:00:00Z", 0.95, "highlight" }
local kui = yeniOkuyucu(K2, { title = "Kobo İki", authors = "Yazar İki" }, 10, {})
for ad, f in pairs(sahteBelge(METIN)) do kui.document[ad] = f end
kui.document.file = K2
local olaylar = {}
kui.handleEvent = function(_, ev) olaylar[#olaylar + 1] = ev end
kui.annotation.addItem = function(this, item) table.insert(this.annotations, item); return #this.annotations end
kui.doc_settings = docSettings({ kobosync_imported = { b4 = true } })
local kp = Plugin:new{ ui = kui }
kui.binkitap = kp
local RUI = require("apps/reader/readerui")
RUI.instance = kui
kp:onReaderReady(); calistir()
RUI.instance = nil
local ka = kui.annotation.annotations
kontrol(#ka == 1 and ka[1].text == "her şey değişti" and ka[1].kobo_id == "b5" and kui.doc_settings.data.kobosync_imported.b5,
  "açık kitaba yeni Kobo vurgusu eklendi (eskisi tekrar eklenmedi)")
kontrol(olaylar[1] and olaylar[1].ad == "AnnotationsModified", "KOReader'a vurgu eklendiği bildirildi")
local km2 = {}
for _, o in ipairs(kp:koboMenusu()) do km2[#km2 + 1] = o.text end
kontrol(table.concat(km2, "|"):find("Bu kitabın Kobo notlarını aktar", 1, true), "okuyucuda bu kitabın notlarını aktar")

-- Kobo'dan gelen vurgu renk kuralıyla 1000Kitap'a kendiliğinden gitmez
local pann = okuyucu_ui.annotation.annotations
local alinti_once = #alintilar
pann[#pann + 1] = { datetime = "2099-01-01 10:00:00", drawer = "lighten", color = "yellow", text = "Kobo'dan gelen sarı", kobo_id = "x9", page = "/body/DocFragment[10]/body/p[1]/text().0" }
pann[#pann + 1] = { datetime = "2099-01-01 10:00:01", drawer = "lighten", color = "yellow", text = "KOReader'da yapılan sarı", page = "/body/DocFragment[11]/body/p[1]/text().0" }
p:onAnnotationsModified(); calistir()
local giden = {}
for i = alinti_once + 1, #alintilar do giden[#giden + 1] = alintilar[i].soz end
kontrol(#giden == 1 and giden[1] == "KOReader'da yapılan sarı", "renk kuralı Kobo vurgusunu atladı: " .. table.concat(giden, ", "))

-- Kobo'dan gelenleri tek tuşla gönder (dosya tarayıcısı: bütün kitaplar)
local KU = require("binkitap_kobo_util")
local esl = fm.settings:readSetting("eslesmeler") or {}
esl[K1] = { id = "9001", adi = "Kobo Kitap", basili_sayfa = 300 }
esl[K2] = { id = "9002", adi = "Kobo İki", basili_sayfa = 200, otomatik = true }
fm.settings:saveSetting("eslesmeler", esl)
-- eski eklentinin aktardığı (işaretsiz) bir vurgu: Kobo kaydının tarihiyle tanınmalı
KOBO.isaretler[#KOBO.isaretler + 1] = { "b6", "file://" .. K1, "file://" .. K1 .. "#(1)ch1.xhtml", "ch1.xhtml#point(/1/1)", "Uzun bir yolculuğun ilk adımı", "", "2026-11-04T09:00:00Z", 0.01, "highlight" }
table.insert(YAN_DOSYALAR[K1].annotations, { datetime = KU.toKoreaderDateTime("2026-11-04T09:00:00Z"), drawer = "lighten", color = "yellow",
  text = "Uzun bir yolculuğun ilk adımı", page = "/body/DocFragment[1]/body/p/text().0" })
table.insert(YAN_DOSYALAR[K1].annotations, { datetime = KU.toKoreaderDateTime("2026-11-04T09:00:00Z"), drawer = "lighten", color = "red",
  text = "KOReader'da aynı saniyede başka bir şey", page = "/body/DocFragment[1]/body/p/text().5" })
YAN_DOSYALAR[K1].kobosync_imported.b6 = true
fm:koboVurgulariniGonder()
local gd = son("ButtonDialog")
kontrol(gd and gd.title:find("Kobo'dan gelen ve henüz gönderilmemiş 3 vurgu var (1 kitap)", 1, true)
  and gd.title:find("1 kitabın eşleşmesi doğrulanmadığı için dahil değil", 1, true)
  and gd.buttons[1][1].text == "Herkese açık gönder" and gd.buttons[2][1].text == "Kitap kitap seç",
  "tek tuş: bütün Kobo vurguları için tek soru: " .. (gd and gd.title:gsub("\n", " / ") or "yok"))
local a_once = #alintilar
gd.buttons[1][1].callback(); calistir()
local gidenler = {}
for i = a_once + 1, #alintilar do gidenler[#gidenler + 1] = alintilar[i].soz .. "@" .. tostring(alintilar[i].sayfa) end
local gh = table.concat(gidenler, " | ")
kontrol(#gidenler == 3 and gh:find("Deniz sakin, rüzgâr hafifti.@61", 1, true) and gh:find("fırtına geldi@", 1, true)
  and gh:find("Uzun bir yolculuğun ilk adımı@", 1, true) and not gh:find("aynı saniyede", 1, true),
  "Kobo vurguları sayfa numarasıyla gitti, eski aktarım da tanındı, KOReader vurgusu karışmadı: " .. gh)
local not_giden
for i = a_once + 1, #alintilar do if alintilar[i].soz == "fırtına geldi" then not_giden = alintilar[i] end end
kontrol(not_giden and not_giden.ekbilgi == "Önemli an" and tostring(not_giden.kitapid) == "9001", "Kobo notu alıntının notu olarak gitti")
fm:koboVurgulariniGonder()
local m2 = son("Menu")
local m2_satir = {}
for _, it in ipairs(m2 and m2.item_table or {}) do if it.mandatory then m2_satir[#m2_satir + 1] = it.text .. " {" .. it.mandatory .. "}" end end
kontrol(m2 and m2.title == "Kobo vurguları — kitaplar" and table.concat(m2_satir, " | ") == "☐ Kobo İki {1 vurgu · eşleşme doğrulanmadı}",
  "gönderilenler tekrar sorulmadı; doğrulanmamış eşleşme seçili gelmeden listede: " .. table.concat(m2_satir, " | "))
require("ui/uimanager"):close(m2)

-- Okurken: bu kitabın Kobo vurguları
kui.annotation.annotations[#kui.annotation.annotations + 1] = { datetime = "2026-11-05 10:00:00", drawer = "lighten", color = "yellow", text = "Kendi vurgum", page = "/body/DocFragment[1]/body/p/text().3" }
kp:topluGonder()
local tg = son("ButtonDialog")
kontrol(tg.buttons[#tg.buttons - 1][1].text == "Yalnızca Kobo'dan gelenler (1)" and tg.buttons[#tg.buttons][1].text == "Vazgeç",
  "vurguları gönder penceresinde Kobo'dan gelenler ayrı düğme")
tg.buttons[#tg.buttons - 1][1].callback()
local kd = son("ButtonDialog")
kontrol(kd.title:find("“Kobo İki” kitabında Kobo'dan gelen 1 vurgu 1000Kitap'a gönderilsin mi?", 1, true), "okurken tek soru: " .. kd.title:gsub("\n", " / "))
local n_once = #notlar
dugme(kd, "Gizli gönder").callback(); calistir()
kontrol(#notlar == n_once + 1 and notlar[#notlar]["not"]:find("her şey değişti", 1, true), "gizli gönderildi (yalnızca Kobo'dan gelen)")
kp:koboVurgulariniGonder()
kontrol(son("InfoMessage").text == "Bu kitapta 1000Kitap'a gönderilmemiş Kobo vurgusu yok.", "ikinci kez gönderilecek yok")
fm.kobo:showQuickDialog()
kontrol(son("ButtonDialog").buttons[2][1].text == "Kobo vurgularını 1000Kitap'a gönder", "Kobo hızlı menüsünde gönder")

-- 1000Kitap ekranında Kobo satırı ve SimpleUI düğmesi
fm:ekranAc(); calistir()
local ekr
for i = #gosterilen, 1, -1 do if gosterilen[i].covers_fullscreen and gosterilen[i].veri then ekr = gosterilen[i]; break end end
local function bul(w, metin, gor)
  gor = gor or {}
  if type(w) ~= "table" or gor[w] then return nil end
  gor[w] = true
  if w._tur == "ButtonTable" then for _, st in ipairs(w.buttons) do for _, b in ipairs(st) do if b.text == metin then return b end end end end
  for _, c in ipairs(w) do local b = bul(c, metin, gor); if b then return b end end
end
kontrol(ekr and bul(ekr, "Kobo'dan aktar") and bul(ekr, "Kobo notları ›") and bul(ekr, "Kobo vurgularını 1000Kitap'a gönder"), "1000Kitap ekranında Kobo düğmeleri")
local ok_c = pcall(function() ekr:paintTo(nil, 0, 0) end)
kontrol(ok_c, "Kobo satırıyla ekran çizilebiliyor")
bul(ekr, "Kobo notları ›").callback()
kontrol(son("Menu").title == "Kobo'da notlu kitaplar", "ekrandan Kobo notları")
ekr:onClose()
local kayit = {}
package.preload["features/sui_quickactions"] = function() return { register = function(d) kayit[d.id] = d end } end
fm:simpleUIKaydet()
kontrol(kayit.kobosync and kayit.kobosync.label == "Kobo" and kayit.kobosync.icon:match("/kobo%.svg$") and kayit.binkitap_ekran.icon:match("/1000kitap%.svg$"),
  "SimpleUI'de eski Kobo düğmesiyle aynı kimlik, kendi simgesi")
kayit.kobosync.execute({ fm = { binkitap = fm } })
kontrol(son("ButtonDialog").title == "Kobo Senkron", "SimpleUI Kobo düğmesi hızlı menüyü açtı")
package.preload["features/sui_quickactions"] = nil
package.loaded["features/sui_quickactions"] = nil
kontrol(io.open("binkitap.koplugin/kobo.svg", "rb") ~= nil, "Kobo simgesi eklentinin kök klasöründe")

-- Arka plan aktarımını durdur: bitenler kalır, kalanlar sonra sürer
KOBO.isaretler[#KOBO.isaretler + 1] = { "b7", "file://" .. K1, "file://" .. K1 .. "#(1)ch1.xhtml", "ch1.xhtml#point(/1/5)", "Sonra fırtına geldi", "", "2026-11-06T09:00:00Z", 0.7, "highlight" }
local k1_once = #YAN_DOSYALAR[K1].annotations
ALT.bekle = true
local durd_once = ALT.durdurulan
fm:onKoboSyncNow()
birTur()
kontrol(Plugin.Kobo.arkaCalisiyor(), "yeni Kobo notu için arka plan başladı")
fm.kobo:arkaDurumGoster()
dugme(son("ButtonDialog"), "Durdur").callback()
local dz = son("InfoMessage")
kontrol(not Plugin.Kobo.arkaCalisiyor() and ALT.durdurulan == durd_once + 1 and dz.text:find("Aktarımı durdurdun", 1, true)
  and #YAN_DOSYALAR[K1].annotations == k1_once, "durduruldu: süreç kapatıldı, yarım kalan kitaba bir şey yazılmadı")
ALT.bekle = false
calistir()
fm:onKoboSyncNow(); calistir()
local son_ann = YAN_DOSYALAR[K1].annotations[#YAN_DOSYALAR[K1].annotations]
kontrol(#YAN_DOSYALAR[K1].annotations == k1_once + 1 and son_ann.kobo_id == "b7" and son("InfoMessage").text:find("Kobo notları aktarıldı", 1, true),
  "bir sonraki taramada kaldığı yerden sürdü: " .. son("InfoMessage").text:gsub("\n", " / "))

-- Gönderildi görünen ama 1000Kitap'ta olmayanları bul (yalnızca okur)
local yanit_eski = YANIT["okurlar/okurCekV2"]
local profil_istek = {}
YANIT["okurlar/okurCekV2"] = function(r)
  profil_istek[#profil_istek + 1] = r.q
  return { _sonuc = { hasMore = false, liste = {
    { turu = "sozler", alt = { sozler = { kitapid = "9001", sozParse = { parse = { "Deniz sakin, rüzgâr hafifti." } } } } },
  } }, bilgi = 1 }
end
local g1 = YAN_DOSYALAR[K1].binkitap_gonderilen
local anah = {}
for _, a in ipairs(YAN_DOSYALAR[K1].annotations) do if a.kobo_id or a.text == "Uzun bir yolculuğun ilk adımı" then anah[a.kobo_id or "b6"] = fm:vurguAnahtari(a) end end
kontrol(g1[anah.b1] == "acik" and g1[anah.b2] == "acik", "gönderilirken herkese açık olduğu kaydedildi")
g1[anah.b6] = "gizli" -- gizli gönderilen: alıntılarda görünmez, dokunulmamalı
fm.kullanici_adi = "okur"
fm:koboKarsilastir()
local kb = son("ConfirmBox")
kontrol(kb and kb.text:find("1 kitapta \"gönderildi\" işaretli 2 Kobo vurgusu, 1000Kitap'taki bütün alıntılarınla", 1, true) and kb.text:find("Yalnızca okur", 1, true),
  "karşılaştırmadan önce ne yapacağını söyledi: " .. (kb and kb.text:gsub("\n", " / ") or "yok"))
kb.ok_callback(); calistir()
local kd2 = son("ButtonDialog")
g1 = YAN_DOSYALAR[K1].binkitap_gonderilen
kontrol(kd2.title:find("1000Kitap'taki 1 alıntınla karşılaştırıldı: 1 Kobo vurgusu orada yok (1 kitap).", 1, true) and g1[anah.b2] == "acik"
  and profil_istek[1] and profil_istek[1].kitapId == "" and profil_istek[1].id == "okur",
  "kitap süzgecine güvenmeden bütün alıntılar okundu; önce sayıyı gösterdi, onaylamadan hiçbir şeyi değiştirmedi: " .. kd2.title:gsub("\n", " / "))
dugme(kd2, "İşaretle ve gönder").callback()
g1 = YAN_DOSYALAR[K1].binkitap_gonderilen
kontrol(g1[anah.b1] == "acik" and g1[anah.b2] == nil and g1[anah.b6] == "gizli",
  "sitede olmayanın işareti kalktı, sitedekine ve gizliye dokunulmadı")
kontrol(son("ButtonDialog").title:find("henüz gönderilmemiş 2 vurgu var (1 kitap)", 1, true), "yeniden gönderilebilir olanlar tek tuşla gönderilecekler arasında")
g1[anah.b2] = "acik"
-- alıntı başka kitap kimliğiyle gelse de (1000Kitap'ın kayıtları farklı olabilir) metni varsa gönderilmiş sayılır;
-- birden çok sayfa okunur
YANIT["okurlar/okurCekV2"] = function(r)
  local sf = tonumber(r.q.sayfa) or 1
  local metin = sf == 1 and "Deniz sakin, rüzgâr hafifti." or "“Fırtına geldi”"
  return { _sonuc = { hasMore = sf < 2, sayfa = sf, kume = 1, z = 1, liste = {
    { turu = "sozler", alt = { sozler = { kitapid = sf == 1 and "9001" or "777", sozParse = { parse = { metin } } } } },
  } }, bilgi = 1 }
end
fm:koboKarsilastir(); son("ConfirmBox").ok_callback(); calistir()
kontrol(son("InfoMessage").text:find("1000Kitap'taki 2 alıntınla karşılaştırıldı: gönderildi görünen bütün Kobo vurguları orada var.", 1, true),
  "bütün sayfalar okundu; kitap kimliği farklı olsa da metin eşleşti")
-- yarıda kalırsa hiçbir şeye dokunma
local hata_sayfasi = 0
YANIT["okurlar/okurCekV2"] = function(r)
  hata_sayfasi = hata_sayfasi + 1
  if hata_sayfasi == 2 then return { hata = 1, hataTuru = 2, hataMesaji = "Bir sorun oluştu.", alertMesaji = "" } end
  return { _sonuc = { hasMore = true, sayfa = hata_sayfasi, kume = 1, z = 1, liste = {} }, bilgi = 1 }
end
fm:koboKarsilastir(); son("ConfirmBox").ok_callback(); calistir()
kontrol(son("InfoMessage").text:find("Karşılaştırma yapılmadı, hiçbir şey değişmedi.", 1, true)
  and YAN_DOSYALAR[K1].binkitap_gonderilen[anah.b2] == "acik", "okuma yarıda kalınca işaretlere dokunmadı")
-- çok sayfa: sınıra gelirse yine dokunma
local cap_eski, sayfa_n = Plugin.KARSILASTIR_EN_FAZLA_SAYFA, 0
Plugin.KARSILASTIR_EN_FAZLA_SAYFA = 20
YANIT["okurlar/okurCekV2"] = function(r)
  sayfa_n = sayfa_n + 1
  return { _sonuc = { hasMore = true, sayfa = sayfa_n, kume = 1, z = 1, liste = {} }, bilgi = 1 }
end
fm:koboKarsilastir(); son("ConfirmBox").ok_callback(); calistir()
kontrol(sayfa_n == 20 and son("InfoMessage").text:find("Karşılaştırma yapılmadı, hiçbir şey değişmedi.", 1, true)
  and YAN_DOSYALAR[K1].binkitap_gonderilen[anah.b2] == "acik", "hepsi okunamazsa işaretlere dokunmadı (çift gönderim olmasın)")
Plugin.KARSILASTIR_EN_FAZLA_SAYFA = cap_eski
YANIT["okurlar/okurCekV2"] = yanit_eski

-- Eski Kobo Senkron eklentisi hâlâ açıksa iş onun; 1000Kitap kapatmayı önerir
local eski = { cagri = {} }
for _, ad in ipairs({ "runScan", "showReport", "showQuickDialog" }) do eski[ad] = function() eski.cagri[#eski.cagri + 1] = ad end end
eski.getMenuItems = function() return { { text = "ESKİ: Şimdi senkronize et", callback = function() end } } end
fm_ui.kobosync = eski
kontrol(fm:onKoboSyncNow() == nil and fm:onKoboSyncMenu() == nil, "hareket olayı eski eklentiye bırakıldı")
fm:koboSimdi(); fm:koboRapor(); fm:koboHizliMenu()
kontrol(table.concat(eski.cagri, ",") == "runScan,showReport,showQuickDialog", "1000Kitap düğmeleri eski eklentiyi çalıştırdı")
local alt_e = ALT.sayi
local bilgi_e = #TRAPPER.bilgi
fm.kobo:autoScan(); calistir()
kontrol(ALT.sayi == alt_e and #TRAPPER.bilgi == bilgi_e, "eski eklenti açıkken kendiliğinden tarama yok")
local em = fm:koboMenusu()
kontrol(em[1].text == "Eski Kobo Senkron eklentisini kapat" and em[2].text == "ESKİ: Şimdi senkronize et", "menüde eskisini kapatma ve onun menüsü")
fm:eskiKoboUyarisi()
local uy = son("ButtonDialog")
kontrol(uy.title:find("Kobo Senkron artık 1000Kitap'ın içinde", 1, true), "eski eklenti için uyarı")
dugme(uy, "Eski eklentiyi kapat").callback()
kontrol(G_reader_settings:readSetting("plugins_disabled").kobosync == true and son("Restart").text:find("Eski Kobo Senkron eklentisi kapatıldı", 1, true),
  "eski eklenti kapatıldı, yeniden başlatma istendi")
local n_uy = #gosterilen
fm:eskiKoboUyarisi()
kontrol(#gosterilen == n_uy, "aynı oturumda bir daha sormadı")
fm_ui.kobosync = nil
G_reader_settings:delSetting("plugins_disabled")

package.loaded["lua-ljsqlite3/init"] = sq3_eski
rawset(_G, "KOBO_BELGE", false)
DOSYALAR[DB] = nil
end)()

;(function()
print("48) 1000Kitap'ın günlük alıntı sınırı: silinmez, yarın gider")
local eski_h = YANIT["alintilar/alintiEkle"]
local kabul, denenen = 2, 0
YANIT["alintilar/alintiEkle"] = function(r)
  denenen = denenen + 1
  if kabul <= 0 then
    return { hata = 1, hataTuru = 2, hataMesaji = "Sıkı okur olarak 1 günde en fazla 500 alıntı paylaşabilirsiniz.", alertMesaji = "" }
  end
  kabul = kabul - 1
  return eski_h(r)
end
fm.settings:delSetting("gunluk_sinir")
local k = {}
for i = 1, 4 do k[#k + 1] = { tur = "alinti", kitap_id = "24319", kitap_adi = "Walden", soz = "Sınır alıntısı " .. i, sayfa = "1" } end
k[#k + 1] = { tur = "ozel_not", kitap_id = "24319", kitap_adi = "Walden", metin = "Gizli not", anahtar = "abc" }
fm.settings:saveSetting("kuyruk", k)
local a_once, n_once = #alintilar, #notlar
fm:kuyruguGonder(false); calistir()
local kalan = fm:kuyruk()
kontrol(#alintilar == a_once + 2 and denenen == 3 and #kalan == 2 and kalan[1].soz == "Sınır alıntısı 3" and kalan[2].soz == "Sınır alıntısı 4",
  "sınıra takılan alıntı silinmedi, kalanlar sırada; sınırdan sonra hiç denenmedi")
kontrol(#notlar == n_once + 1, "sınır alıntılar içindi: gizli not yine gitti")
local mesaj = son("InfoMessage") and son("InfoMessage").text or ""
kontrol(mesaj:find("günlük sınırı doldu: 2 alıntı sırada bekliyor, yarın kendiliğinden gönderilir. Hiçbiri silinmedi.", 1, true), "ne olduğunu söyledi: " .. mesaj:gsub("\n", " / "))
fm:kuyruguGonder(false); calistir()
kontrol(denenen == 3 and #fm:kuyruk() == 2, "aynı gün tekrar denenmedi")
kontrol(fm:bekleyenlerMenuOgesi().text_func() == "Bekleyen gönderiler: 2 (günlük sınır, yarın)", "menüde yarın gideceği yazıyor")
kontrol(fm:uykuOncesiGonder() == 0 and denenen == 3, "uykuya geçerken de denenmedi")
-- ertesi gün
fm.settings:saveSetting("gunluk_sinir", { tarih = "2000-01-01", turler = { alinti = true } })
kabul = 10
fm:kuyruguGonder(false); calistir()
kontrol(#fm:kuyruk() == 0 and denenen == 5 and alintilar[#alintilar].soz == "Sınır alıntısı 4", "ertesi gün bekleyenler gönderildi")
YANIT["alintilar/alintiEkle"] = eski_h
end)()

;(function()
print("49) Yinelenen alıntıları temizle")
local function oge(id, kitapid, soz)
  return { turu = "sozler", id = id, alt = { sozler = { kitapid = kitapid, sozParse = { parse = { soz } } } } }
end
local profil = {
  oge("105", "9001", "Aynı alıntı."), oge("104", "9001", "“aynı  alıntı”"), oge("103", "9002", "Aynı alıntı."),
  oge("102", "9001", "Aynı alıntı"), oge("101", "9001", "Başka bir alıntı"), oge("abc", "9003", "X"), oge("def", "9003", "X"),
}
local SAYFA = 3
local eski_okur, eski_kaldir = YANIT["okurlar/okurCekV2"], YANIT["alintilar/alintiKaldir"]
local okuma_hatasi, yanlis_sil = nil, false
YANIT["okurlar/okurCekV2"] = function(r)
  assert(r.q.bolum == "alintilar" and r.q.kitapId == "", "Alıntılar bölümü, süzgeçsiz")
  if okuma_hatasi then return okuma_hatasi end
  local sf = tonumber(r.q.sayfa) or 1
  local liste = {}
  for i = (sf - 1) * SAYFA + 1, math.min(#profil, sf * SAYFA) do liste[#liste + 1] = profil[i] end
  return { _sonuc = { hasMore = sf * SAYFA < #profil, sayfa = sf, kume = 1, z = 1, liste = liste }, bilgi = 1 }
end
local silinen_ist = {}
YANIT["alintilar/alintiKaldir"] = function(r)
  if not kimlikli(r) then return giris_hatasi() end
  assert(r.method == "GET", "silme GET")
  silinen_ist[#silinen_ist + 1] = r.q.id
  local hedef = yanlis_sil and "102" or r.q.id -- yanlış_sil: sunucu başka alıntıyı silerse
  for i, o in ipairs(profil) do if o.id == hedef then table.remove(profil, i); return { _sonuc = {}, bilgi = 1 } end end
  return { hata = 1, hataTuru = 2, hataMesaji = "Alıntı bulunamadı.", alertMesaji = "" }
end

-- saf gruplama
local G = Plugin.yinelenenleriBul({
  { id = "7", kitap_id = "1", soz = "Bir" }, { id = "5", kitap_id = "1", soz = "bir!" },
  { id = "x", kitap_id = "2", soz = "İki", zaman = 10 }, { id = "y", kitap_id = "2", soz = "iki", zaman = 10 },
  { id = "p", kitap_id = "3", soz = "Üç", zaman = 20 }, { id = "q", kitap_id = "3", soz = "üç", zaman = 30 },
  { id = "9", kitap_id = "", soz = "Kitapsız" }, { id = "8", kitap_id = "", soz = "Kitapsız" },
})
kontrol(#G == 2 and G[1].kalan.id == "5" and G[1].silinecek[1].id == "7" and G[2].kalan.id == "p" and G[2].silinecek[1].id == "q",
  "gruplama: ilk gönderilen (küçük kimlik / erken zaman) kalır; eşit zamanlı ve kitapsız gruplara dokunulmaz")

fm.kullanici_adi = "okur"
fm:yinelenenAlintilar()
local kb = son("ConfirmBox")
kontrol(kb and kb.text:find("sormadan hiçbir şey silinmez", 1, true), "önce ne yapacağını söyledi")
kb.ok_callback(); calistir()
local d = son("ButtonDialog")
kontrol(d and d.title:find("Profilindeki 7 alıntı okundu. 1 kitapta 2 yinelenen alıntı var", 1, true)
  and d.title:find("1 grupta hangisinin önce gönderildiği anlaşılamadı", 1, true) and #silinen_ist == 0,
  "okudu, saydı, sormadan silmedi: " .. (d and d.title:gsub("\n", " / ") or "yok"))
dugme(d, "Listeyi gör").callback()
kontrol(son("TextViewer").text:find("3 kopya, 2 silinecek", 1, true), "liste gösterildi")
dugme(d, "Sil (2)").callback(); calistir()
local kalanlar = {}
for _, o in ipairs(profil) do kalanlar[#kalanlar + 1] = o.id end
kontrol(table.concat(silinen_ist, ",") == "104,105" and table.concat(kalanlar, ",") == "103,102,101,abc,def"
  and son("InfoMessage").text:find("2 yinelenen alıntı silindi.", 1, true),
  "yenileri silindi, ilk gönderilen ve diğer kitaptaki kaldı: " .. table.concat(kalanlar, ","))
local son_kaldir = sonIstek("alintilar/alintiKaldir")
kontrol(son_kaldir and son_kaldir.headers["1-oturum-kodu"] and son_kaldir.method == "GET", "sitenin silme çağrısı, oturumla")

-- sunucu başka alıntıyı silerse: ilk silmeden sonra durur
profil = { oge("205", "9001", "Tekrar"), oge("204", "9001", "Tekrar"), oge("102", "9001", "Tekrar") }
silinen_ist, yanlis_sil = {}, true
fm:yinelenenAlintilar(); son("ConfirmBox").ok_callback(); calistir()
dugme(son("ButtonDialog"), "Sil (2)").callback(); calistir()
kontrol(#silinen_ist == 1 and son("InfoMessage").text:find("beklendiği gibi çalışmadı; güvenlik için durdum", 1, true),
  "doğrulama tutmayınca başka hiçbir şey silmedi")
yanlis_sil = false

-- okurken 1000Kitap "çok fazla istek" derse hiçbir şey silinmez
profil = { oge("305", "9001", "Yine"), oge("304", "9001", "Yine") }
silinen_ist, okuma_hatasi = {}, 429
fm:yinelenenAlintilar(); son("ConfirmBox").ok_callback(); calistir()
kontrol(#silinen_ist == 0 and son("InfoMessage").text:find("Alıntılar okunamadı", 1, true)
  and son("InfoMessage").text:find("Hiçbir şey silinmedi", 1, true), "429'da okuma durdu, hiçbir şey silinmedi")
okuma_hatasi = nil
YANIT["okurlar/okurCekV2"], YANIT["alintilar/alintiKaldir"] = eski_okur, eski_kaldir
end)()

;(function()
print("50) Yeniden okuma: eski Okudum bozulmaz, yeni okuma başlar")
local k = p:kitapBilgisi()
local id = k.id
p.settings:saveSetting("kuyruk", {})
p.settings:delSetting("yeniden_okuma"); p.settings:delSetting("yeniden_okuma_red"); p.settings:delSetting("yeniden_okunan")
p.ORTAK.yeniden_sorulan = nil
local function gonder() p:kuyruguGonder(true); calistir() end
local function tarihliMi() local ok = okuma_tarihi[id] == false and YENI_OKUMA[id] == 1; YENI_OKUMA[id] = nil; return ok end
-- Kendiliğinden Okuyorum (kitap açılınca): sorar, sormadan dokunmaz
durum[id] = 1; okuma_tarihi[id] = nil
k.okudum_islendi = true; k.bitis_reddedildi = true; k.yeniden_okuma = nil; p:kitapKaydetAyar(k)
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2, otomatik = true })
gonder()
local d = son("ButtonDialog")
kontrol(durum[id] == 1 and okuma_tarihi[id] == nil and #p:kuyruk() == 0, "sormadan dokunmadı, iş sıradan çıktı")
kontrol(d and d.title:find("Yeniden mi okuyorsun", 1, true) and d.title:find(k.adi, 1, true), "yeniden mi okuyorsun diye sordu")
local n = #gosterilen
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2, otomatik = true })
gonder()
kontrol(#gosterilen == n and durum[id] == 1, "aynı oturumda ikinci kez sormadı")
dugme(d, "Yeniden okuyorum").callback(); calistir()
kontrol(durum[id] == 2 and tarihliMi(), "yeni okuma sitedeki gibi yeniOkuma=1 ile başladı (düz durum değişikliğiyle değil)")
local k2 = p:kitapBilgisi()
kontrol(not k2.okudum_islendi and not k2.bitis_reddedildi and k2.yeniden_okuma, "açık kitapta bitiş ekranı bu okuma için yeniden açıldı")
-- "Hayır, sadece bakıyorum": 30 gün sorulmaz
durum[id] = 1; okuma_tarihi[id] = nil; p.ORTAK.yeniden_sorulan = nil
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2, otomatik = true })
gonder()
dugme(son("ButtonDialog"), "Hayır").callback(); calistir()
p.ORTAK.yeniden_sorulan = nil
n = #gosterilen
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2, otomatik = true })
gonder()
kontrol(#gosterilen == n and durum[id] == 1 and okuma_tarihi[id] == nil, "\"Hayır\" hatırlandı, bir daha sormadı")
local red = p.settings:readSetting("yeniden_okuma_red")
red[tostring(id)] = os.time() - 31 * 24 * 3600; p.settings:saveSetting("yeniden_okuma_red", red)
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2, otomatik = true })
gonder()
kontrol(#gosterilen > n and son("ButtonDialog").title:find("Yeniden mi okuyorsun", 1, true), "30 gün sonra yine sordu")
dugme(son("ButtonDialog"), "Sonra sor").callback(); calistir()
-- Elle Okuyorum: sormadan yeni okuma (eski Okudum'u Okuyorum'a çevirmez)
durum[id] = 1; okuma_tarihi[id] = nil
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2 })
p:kuyruguGonder(false); calistir()
kontrol(durum[id] == 2 and tarihliMi(), "elle Okuyorum yeni okuma açtı")
kontrol(son("InfoMessage") and son("InfoMessage").text:find("yeni okuma başladı", 1, true), "bildirimde yeni okuma yazdı: " .. tostring(son("InfoMessage") and son("InfoMessage").text))
local r = p.settings:readSetting("yeniden_okuma_red") or {}
kontrol(r[tostring(id)] == nil, "elle başlatınca \"Hayır\" kaydı silindi")
-- Kendiliğinden Yarım bıraktım / Okuyacağım Okudum'u bozmaz
for _, hedef in ipairs({ 3, 0 }) do
  durum[id] = 1; okuma_tarihi[id] = nil
  p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = hedef, otomatik = true })
  gonder()
  kontrol(durum[id] == 1 and okuma_tarihi[id] == nil, "kendiliğinden " .. hedef .. " Okudum'u bozmadı")
end
-- Ayar: sormadan başlat
p.settings:saveSetting("yeniden_okuma", "otomatik"); p.ORTAK.yeniden_sorulan = nil
durum[id] = 1; okuma_tarihi[id] = nil; n = #gosterilen
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2, otomatik = true })
gonder()
kontrol(durum[id] == 2 and tarihliMi() and not (son("ButtonDialog") and son("ButtonDialog").title:find("Yeniden mi", 1, true) and #gosterilen > n),
  "ayar açıkken sormadan yeni okuma başladı")
-- Bitirince kapanışta giden ilerleme yeniden okuma sayılmaz
p.settings:delSetting("okudum_gonderilen")
local function ilerlemeDene(oge, ad)
  durum[id] = 1; okuma_tarihi[id] = nil; sayfa2[id] = 0
  p:siraya(oge); gonder()
  kontrol(durum[id] == 1 and okuma_tarihi[id] == nil and sayfa2[id] == 0, ad)
end
ilerlemeDene({ tur = "ilerleme", kitap_id = id, kitap_adi = k.adi, yuzde = 0.97, basili_sayfa = k.basili_sayfa },
  "kitabın sonundaki ilerleme yeni okuma açmadı")
ilerlemeDene({ tur = "ilerleme", kitap_id = id, kitap_adi = k.adi, yuzde = 0.3, basili_sayfa = k.basili_sayfa, otomatik_eslesme = true },
  "doğrulanmamış eşleşmede yeni okuma açmadı")
p:okudumKaydet(id)
ilerlemeDene({ tur = "ilerleme", kitap_id = id, kitap_adi = k.adi, yuzde = 0.3, basili_sayfa = k.basili_sayfa },
  "eklenti az önce Okudum yaptıysa yeni okuma açmadı")
local og = p.settings:readSetting("okudum_gonderilen")
og[tostring(id)] = os.time() - 8 * 24 * 3600; og["eski"] = os.time() - 9 * 24 * 3600
p.settings:saveSetting("okudum_gonderilen", og)
p:okudumKaydet("baska")
kontrol(p.settings:readSetting("okudum_gonderilen")["eski"] == nil, "eski Okudum kayıtları temizlendi")
-- İlerleme gelirse de (okunuyor demek) yeni okuma açılıp sayfa yazılır
durum[id] = 1; okuma_tarihi[id] = nil; sayfa2[id] = 0
p:siraya({ tur = "ilerleme", kitap_id = id, kitap_adi = k.adi, yuzde = 0.3, basili_sayfa = k.basili_sayfa })
gonder()
kontrol(durum[id] == 2 and tarihliMi() and (sayfa2[id] or 0) > 0, "ilerlemede yeni okuma açıldı ve sayfa gönderildi")
-- Ayar: dokunma
p.settings:saveSetting("yeniden_okuma", "hayir"); p.ORTAK.yeniden_sorulan = nil
durum[id] = 1; okuma_tarihi[id] = nil; n = #gosterilen
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2, otomatik = true })
gonder()
kontrol(durum[id] == 1 and okuma_tarihi[id] == nil and #gosterilen == n, "\"Dokunma\"da hiçbir şey yapmadı")
-- Varsayılan (sor): ilerleme sorar, sayfayı göndermez
p.settings:delSetting("yeniden_okuma"); p.ORTAK.yeniden_sorulan = nil
p.settings:delSetting("yeniden_okuma_red")
durum[id] = 1; okuma_tarihi[id] = nil; sayfa2[id] = 0
p:siraya({ tur = "ilerleme", kitap_id = id, kitap_adi = k.adi, yuzde = 0.3, basili_sayfa = k.basili_sayfa })
gonder()
kontrol(durum[id] == 1 and sayfa2[id] == 0 and son("ButtonDialog").title:find("Yeniden mi okuyorsun", 1, true), "ilerlemede sordu, sayfayı Okudum'a yazmadı")
dugme(son("ButtonDialog"), "Sonra sor").callback(); calistir()
-- Site yeni okumayı açmazsa hata olarak görünür
local eski = YANIT["kitaplar/kitapOku"]
YANIT["kitaplar/kitapOku"] = function(r) return { _sonuc = { durum = true }, bilgi = 1 } end
p.settings:delSetting("hata_gunlugu")
durum[id] = 1
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2 })
p:kuyruguGonder(false); calistir()
YANIT["kitaplar/kitapOku"] = eski
kontrol(durum[id] == 1 and p:hataGunluguMetni():find("yeni okumayı başlatmadı", 1, true), "açılmayan yeni okuma hata olarak kaydedildi")
p.settings:delSetting("hata_gunlugu")
-- Başka dosyada (sonradan açılınca) bitiş ekranı bayrağı sıfırlanır
local f = { id = id, adi = k.adi, okudum_islendi = true, bitis_reddedildi = true, yeniden_okuma = 1 }
p:yenidenOkumaAcilis(f)
kontrol(not f.okudum_islendi and not f.bitis_reddedildi and f.yeniden_okuma > 1, "başka dosyada yeniden okuma uygulandı")
f.okudum_islendi = true
p:yenidenOkumaAcilis(f)
kontrol(f.okudum_islendi == true, "yeniden okuma bitince bayrak bir daha sıfırlanmadı")
-- Yeni okuma bitince düz Okudum gider (yeni okumayı kapatır) ve zamanı kaydedilir
p.settings:delSetting("okudum_gonderilen")
durum[id] = 2; okuma_tarihi[id] = nil
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 1 })
gonder()
local og2 = p.settings:readSetting("okudum_gonderilen")
kontrol(durum[id] == 1 and okuma_tarihi[id] == false and og2 and og2[tostring(id)], "ikinci okuma Okudum ile kapandı, zamanı kaydedildi")
-- 3. ve 4. okuma: her yeniden okuma bir okuma daha ekler, bitiş ekranı her seferinde yine açılır
p.settings:delSetting("okudum_gonderilen"); p.ORTAK.yeniden_sorulan = nil
YENI_OKUMA[id] = nil
for tur = 3, 4 do
  durum[id] = 1
  local kk = p:kitapBilgisi(); kk.okudum_islendi = true; p:kitapKaydetAyar(kk)
  p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 2, elle = true })
  gonder()
  kontrol(durum[id] == 2 and YENI_OKUMA[id] == tur - 2 and not p:kitapBilgisi().okudum_islendi,
    tur .. ". okuma başladı, bitiş ekranı yine açık")
  p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 1, elle = true })
  gonder()
  kontrol(durum[id] == 1 and YENI_OKUMA[id] == tur - 2, tur .. ". okuma Okudum ile kapandı (yeni okuma açmadan)")
  p.settings:delSetting("okudum_gonderilen")
end
YENI_OKUMA[id] = nil
-- Zaten Okudum olan kitabı yeniden bitirince: yeni okuma olarak eklemeyi sorar
durum[id] = 1; p.ORTAK.yeniden_sorulan = nil
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 1, elle = true })
gonder()
local bd = son("ButtonDialog")
kontrol(durum[id] == 1 and YENI_OKUMA[id] == nil and bd and bd.title:find("zaten \"Okudum\"", 1, true)
  and bd.title:find("3., 4.", 1, true), "bitirince yeni okuma olarak eklemeyi sordu")
dugme(bd, "Yeni okuma olarak ekle").callback(); calistir()
kontrol(durum[id] == 1 and YENI_OKUMA[id] == 1 and p:yeniOkudum(id), "Okudum yeni okuma olarak eklendi (yeniOkuma=1, durum=1)")
YENI_OKUMA[id] = nil
-- Az önce Okudum yaptıysa ya da toplu aktarımdaysa sormaz
p.ORTAK.yeniden_sorulan = nil; n = #gosterilen
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 1, elle = true })
gonder()
kontrol(#gosterilen == n and YENI_OKUMA[id] == nil, "az önce Okudum yapılmışsa sormadı")
p.settings:delSetting("okudum_gonderilen"); p.ORTAK.yeniden_sorulan = nil; n = #gosterilen
p:siraya({ tur = "durum", kitap_id = id, kitap_adi = k.adi, durum = 1, tarih_bas = os.time() - 86400, tarih_bit = os.time() })
gonder()
kontrol(#gosterilen == n and YENI_OKUMA[id] == nil and durum[id] == 1, "toplu aktarımda Okudum olana dokunmadı, sormadı")
-- Menü
local mn = p:yenidenOkumaMenusu()
kontrol(mn.text_func():find("sor", 1, true) and #mn.sub_item_table == 3, "ayar menüsü")
mn.sub_item_table[2].callback()
kontrol(p:yenidenOkumaAyari() == "otomatik", "menüden ayar değişti")
p.settings:delSetting("yeniden_okuma")
durum[id] = 2
p.settings:saveSetting("kuyruk", {})
end)()

;(function()
print("51) Okuyorum: %2 ya da 20 basılı sayfa okuyunca")
local ORT = Plugin.ORTAK
local esl = fm.settings:readSetting("eslesmeler") or {}
local function ac(yol, id, basili, toplam)
  esl[yol] = { id = id, adi = "Kitap " .. id, basili_sayfa = basili }
  fm.settings:saveSetting("eslesmeler", esl)
  durum[id] = nil
  local ui = yeniOkuyucu(yol, { title = "Kitap " .. id, authors = "" }, toplam)
  local pl = Plugin:new{ ui = ui }
  pl:onReaderReady(); calistir()
  return pl, ui
end
local function oku(pl, ui, n)
  for _ = 1, n do ui.sayfa = ui.sayfa + 1; pl:onPageUpdate(ui.sayfa) end
  ORT.son_etkilesim = nil
  calistir()
end
fm.settings:delSetting("okuyorum_zamani"); fm.settings:delSetting("acilista_okuyorum")
kontrol(fm:okuyorumZamani() == "okuyunca", "varsayılan: okuyunca")
-- Uzun kitapta 20 basılı sayfa %2'den önce gelir: 2000 ekran sayfası, 1200 basılı sayfa
local pl, ui = ac("/kobo/Uzun.epub", "5001", 1200, 2000)
kontrol(durum["5001"] == nil, "açılınca gönderilmedi")
oku(pl, ui, 33)
kontrol(durum["5001"] == nil, "19,8 basılı sayfada henüz değil")
oku(pl, ui, 1)
kontrol(durum["5001"] == 2, "20 basılı sayfada Okuyorum oldu (%1,7)")
-- Okuma kapanışta kaydedilir, sonraki açılışta sürer
pl, ui = ac("/kobo/Iki.epub", "5002", 300, 500)
oku(pl, ui, 6); pl:araVer()
kontrol(durum["5002"] == nil and ui.doc_settings.data.binkitap.okunan_sayfa == 6, "6 sayfa kaydedildi, henüz gönderilmedi")
local pl2 = Plugin:new{ ui = ui }
pl2:onReaderReady(); calistir()
oku(pl2, ui, 3)
kontrol(durum["5002"] == nil, "toplam 9 sayfa (%1,8): henüz değil")
oku(pl2, ui, 1)
kontrol(durum["5002"] == 2, "iki oturumda toplam %2 okununca Okuyorum oldu")
-- Geri gitmek ve atlamak sayılmaz
pl, ui = ac("/kobo/Uc.epub", "5003", 300, 500)
ui.sayfa = 300; pl:onPageUpdate(300); ui.sayfa = 100; pl:onPageUpdate(100)
for _ = 1, 5 do ui.sayfa = ui.sayfa - 1; pl:onPageUpdate(ui.sayfa) end
ORT.son_etkilesim = nil; calistir()
kontrol(durum["5003"] == nil and (pl._okunan or 0) == 0, "atlama ve geri gitme sayılmadı")
-- Ayar: açılınca
fm.settings:saveSetting("okuyorum_zamani", "acilis")
pl, ui = ac("/kobo/Dort.epub", "5004", 300, 500)
kontrol(durum["5004"] == 2, "\"Açılınca\" ayarında hemen Okuyorum")
-- Ayar: hiçbir zaman (eski ayar kapalıysa da)
fm.settings:delSetting("okuyorum_zamani"); fm.settings:saveSetting("acilista_okuyorum", false)
kontrol(fm:okuyorumZamani() == "hic", "eski \"açılınca Okuyorum\" kapalıysa hiçbir zaman")
pl, ui = ac("/kobo/Bes.epub", "5005", 300, 500)
oku(pl, ui, 50)
kontrol(durum["5005"] == nil, "\"Hiçbir zaman\" ayarında okuyunca da gönderilmedi")
fm.settings:delSetting("acilista_okuyorum")
-- Okudum olan kitapta eşik geçilince yeniden okuma sorulur
pl, ui = ac("/kobo/Alti.epub", "5006", 300, 500)
durum["5006"] = 1; ORT.yeniden_sorulan = nil; fm.settings:delSetting("yeniden_okuma_red")
oku(pl, ui, 10)
local sd = son("ButtonDialog")
kontrol(durum["5006"] == 1 and sd and sd.title:find("Yeniden mi okuyorsun", 1, true) and sd.title:find("Kitap 5006", 1, true),
  "Okudum olan kitapta %2 okuyunca yeniden okuma soruldu")
dugme(sd, "Sonra sor").callback(); calistir()
-- Menü
local mn = fm:okuyorumZamaniMenusu()
kontrol(mn.text_func():find("%2 ya da 20 sayfa okuyunca", 1, true) and #mn.sub_item_table == 3, "ayar menüsü: " .. mn.text_func())
mn.sub_item_table[3].callback()
kontrol(fm:okuyorumZamani() == "hic", "menüden değişti")
fm.settings:delSetting("okuyorum_zamani")
fm.settings:saveSetting("kuyruk", {})
end)()

;(function()
print("52) Hız modu: otomatik işler kapalı, elle eşitle, ayarlar korunur")
local ORT = Plugin.ORTAK
local ayar_once = {}
for _, a in ipairs({ "uykuda_gonder", "otomatik_wifi", "durum_ters", "hedef_bildirimi", "guncelleme_oto", "ilerleme_modu" }) do
  ayar_once[a] = fm.settings:readSetting(a)
end
fm.settings:saveSetting("ilerleme_modu", "yuzde10")
fm.settings:saveSetting("kuyruk", {})
-- Aç
local mm = fm:modMenusu()
mm.sub_item_table[2].callback()
kontrol(fm:hizModu() and p:hizModu() and mm.text_func() == "Mod: Hız modu", "hız modu açıldı (tüm örneklerde)")
kontrol(son("InfoMessage").text:find("Hız modu açık", 1, true) and son("InfoMessage").text:find("Bekleyen gönderiler", 1, true), "ne değiştiği ve nasıl gönderileceği söylendi")
kontrol(fm.settings:readSetting("ilerleme_modu") == "yuzde10" and fm:ilerlemeModu() == "kapaninca", "ayar değişmedi; %10 yerine kapanışta")
kontrol(mm.sub_item_table[2].checked_func() and not mm.sub_item_table[1].checked_func(), "menüde işaretli")
-- Otomatik gönderim yok, sıra bekler
local once_ist = #istekler
p:siraya({ tur = "puan", kitap_id = "24319", kitap_adi = "Walden", puan = 8 })
p:arkaPlanGonder(true); p:bekleyenleriSurdur(0); p:yavasGonder(); calistir()
kontrol(#p:kuyruk() == 1 and #istekler == once_ist and ORT.arka_plan == nil, "arka planda, Wi-Fi gelince ve yavaş gönderim yok")
kontrol(p:uykuOncesiGonder() == 0 and #p:kuyruk() == 1, "uykuya geçerken gönderilmedi")
p:onNetworkConnected(); calistir()
kontrol(#p:kuyruk() == 1 and #istekler == once_ist, "Wi-Fi bağlanınca da gönderilmedi, güncelleme denetlenmedi")
local bo = p:bekleyenlerMenuOgesi()
kontrol(bo.text_func() == "Bekleyen gönderiler: 1 (hız modu: dokun, gönder)", "menüde elle gönder: " .. bo.text_func())
-- Elle eşitleme çalışır
bo.callback(); calistir()
kontrol(#p:kuyruk() == 0 and puan["24319"] == 8, "dokununca gönderildi")
-- Açılışta ağ ve Kobo işi yok
local s_ac = #istekler
local oui = yeniOkuyucu("/kobo/Hiz/Isbnli.epub", { title = "Hızlı", authors = "", identifiers = "isbn:978-975-07-5892-8" }, 300)
local op = Plugin:new{ ui = oui }
op:onReaderReady(); calistir()
kontrol(oui.doc_settings.data.binkitap == nil and #istekler == s_ac, "ISBN'li kitap açılınca kendiliğinden aranmadı (elle eşleştirilir)")
kontrol(not op.kobo or op.kobo:hizModu(), "Kobo tarafı hız modunu görüyor")
-- Toplu iş: arka plana değil, elle gönderime bırakılır
p:sirayiGonder(40)
kontrol(son("InfoMessage").text:find("Hız modu açık", 1, true), "toplu işte elle gönderim söylendi")
-- Hareketle kapat: Normal mod, ayarlar olduğu gibi
p:onBinKitapHizModu(); calistir()
kontrol(not fm:hizModu() and fm:ilerlemeModu() == "yuzde10", "hareketle normal moda döndü, %10 ayarı geri geldi")
kontrol(son("InfoMessage") and son("InfoMessage").text:find("Normal mod", 1, true), "normal mod bildirildi")
p:onBinKitapHizModu()
kontrol(fm:hizModu(), "hareketle yeniden açıldı")
fm:modMenusu().sub_item_table[1].callback(); calistir()
kontrol(not fm:hizModu(), "menüden normal moda döndü")
for a, v in pairs(ayar_once) do fm.settings:saveSetting(a, v) end
fm.settings:saveSetting("kuyruk", {})
end)()

;(function()
print("53) Hayalet modu: kendiliğinden hiçbir şey gitmez, elle yapılan gider")
local k = p:kitapBilgisi()
local id = tostring(k.id)
p.settings:saveSetting("kuyruk", {})
p.settings:delSetting("hayalet_kitaplar"); p.settings:delSetting("hayalet_kitap_bitti")
p.settings:delSetting("hayalet_modu"); p.settings:delSetting("hayalet_bitti")
-- Açmadan önce sırada kendiliğinden bir iş ve elle bir iş var
p:siraya({ tur = "ilerleme", kitap_id = k.id, kitap_adi = k.adi, yuzde = 0.5, basili_sayfa = k.basili_sayfa })
p:siraya({ tur = "puan", kitap_id = k.id, kitap_adi = k.adi, puan = 7 })
local ho
for _, o in ipairs(p:menuOgeleri()) do if o.text == "Bu kitap için hayalet modu" then ho = o end end
kontrol(ho and ho.enabled_func() and not ho.checked_func(), "okurken menüde bu kitap için hayalet modu")
ho.callback()
kontrol(ho.checked_func() and p:hayaletKitap(id) and not p:hayaletGenel(), "bu kitap için açıldı")
kontrol(#p:kuyruk() == 1 and p:kuyruk()[1].tur == "puan", "kendiliğinden iş sıradan çıktı, elle puan kaldı")
kontrol(son("InfoMessage").text:find("hayalet modu açık", 1, true) and son("InfoMessage").text:find("1 kendiliğinden iş silindi", 1, true), "bildirildi")
kontrol(p:menuOgeleri()[2].text_func():find(" · hayalet", 1, true), "kitap satırında hayalet yazıyor")
-- Kendiliğinden olanlar sıraya girmez
p:otomatikDurum(k, 1)
p:ilerlemeSirala(k)
p.settings:makeTrue("seans_kaydi"); p.seans = { toplam = 9999, son = os.time() }
kontrol(p:seansBitir() == false, "seans kaydedilmedi")
p.settings:delSetting("seans_kaydi")
kontrol(#p:kuyruk() == 1, "durum ve sayfa sıraya girmedi")
local ann = okuyucu_ui.annotation.annotations
local simdi = os.time()
ann[#ann + 1] = { datetime = os.date("%Y-%m-%d %H:%M:%S", simdi + 5), drawer = "lighten", color = "yellow", text = "hayalet sarı", page = "/body/DocFragment[10]/body/p[1]/text().0" }
kontrol(p:renkTaramasi() == 0 and #p:kuyruk() == 1, "renkli vurgu kendiliğinden gitmedi")
local k2 = p:kitapBilgisi(); k2.okudum_islendi = nil; p:kitapKaydetAyar(k2)
local n = #gosterilen
p:bitisEkrani(); calistir()
kontrol(#gosterilen == n, "bitiş ekranı açılmadı")
-- Açılmadan önce sıraya girmiş kendiliğinden iş gönderimde de düşer; elle olan gider
durum[id] = 0
p:topluSiraya({ { tur = "durum", kitap_id = k.id, kitap_adi = k.adi, durum = 2, otomatik = true } })
p:kuyruguGonder(true); calistir()
kontrol(durum[id] == 0 and puan[id] == 7 and #p:kuyruk() == 0, "kendiliğinden durum gitmedi, elle puan gitti")
-- Elle durum gider
p:durumIstegi(2); calistir()
kontrol(durum[id] == 2, "elle Okuyorum gitti")
-- Toplu işlemde atlanır
local esl = fm.settings:readSetting("eslesmeler") or {}
esl["/kobo/Hayalet.epub"] = { id = k.id, adi = k.adi }
esl["/kobo/Normal.epub"] = { id = "5007", adi = "Normal Kitap" }
fm.settings:saveSetting("eslesmeler", esl)
durum["5007"] = nil; durum[id] = 2
fm:topluDurumEkle({ "/kobo/Hayalet.epub", "/kobo/Normal.epub" }, 1); calistir()
fm:kuyruguGonder(true); calistir()
kontrol(durum["5007"] == 1 and durum[id] == 2, "toplu Okudum'da hayalet kitap atlandı")
-- Dosya menüsünden kapat
fm:dosyaMenusu("/kobo/Hayalet.epub")
local dm = son("ButtonDialog")
kontrol(dm.title:find("hayalet modu", 1, true), "dosya menüsünde hayalet görünüyor")
dugme(dm, "Hayalet modunu kapat").callback()
kontrol(not p:hayaletKitap(id), "dosya menüsünden kapandı")
-- Hayaletteyken yapılan renkli vurgu kapanınca da kendiliğinden gitmez; sonrakiler gider
local bitti = p.settings:readSetting("hayalet_kitap_bitti")[id]
bitti = os.date("%Y-%m-%d %H:%M:%S", simdi + 10)
local hb = p.settings:readSetting("hayalet_kitap_bitti"); hb[id] = bitti; p.settings:saveSetting("hayalet_kitap_bitti", hb)
kontrol(p:renkTaramasi() == 0, "hayaletteyken yapılan vurgu sonradan da gitmedi")
ann[#ann + 1] = { datetime = os.date("%Y-%m-%d %H:%M:%S", simdi + 20), drawer = "lighten", color = "yellow", text = "sonraki sarı", page = "/body/DocFragment[11]/body/p[1]/text().0" }
kontrol(p:renkTaramasi() == 1 and p:kuyruk()[#p:kuyruk()].soz == "sonraki sarı", "hayaletten sonraki vurgu gitti")
p.settings:saveSetting("kuyruk", {})
-- Genel hayalet modu: Mod menüsünden ve hareketle
local mm = fm:modMenusu()
local go = mm.sub_item_table[3]
kontrol(go.text == "Hayalet modu (tüm kitaplar)" and not go.checked_func(), "Mod menüsünde genel hayalet")
go.callback()
kontrol(fm:hayaletGenel() and p:hayaletMi("5007") and mm.text_func():find(" · hayalet", 1, true), "genel hayalet açık: " .. mm.text_func())
durum["5007"] = 0
fm:otomatikDurum({ id = "5007", adi = "Normal Kitap" }, 2)
kontrol(#p:kuyruk() == 0, "genel hayalette kendiliğinden durum sıraya girmedi")
p:onBinKitapHayaletModu()
kontrol(not fm:hayaletGenel() and p.settings:readSetting("hayalet_bitti"), "hareketle kapandı, zamanı kaydedildi")
p:onBinKitapHayaletModu(); p:onBinKitapHayaletModu()
kontrol(not fm:hayaletGenel(), "hareketle aç/kapat")
for _, a in ipairs({ "hayalet_kitaplar", "hayalet_kitap_bitti", "hayalet_modu", "hayalet_bitti" }) do p.settings:delSetting(a) end
esl["/kobo/Hayalet.epub"] = nil; esl["/kobo/Normal.epub"] = nil
fm.settings:saveSetting("eslesmeler", esl)
p.settings:saveSetting("kuyruk", {})
end)()

print("20) Menüler hatasız kuruluyor")
local ok1, m1 = pcall(function() return p:menuOgeleri() end)
local ok2, m2 = pcall(function() return fm:menuOgeleri() end)
local ok3, m3 = pcall(function() return p:ayarlarMenusu() end)
kontrol(ok1 and ok2 and ok3, "menüler kuruldu " .. tostring(m1) .. tostring(m2) .. tostring(m3))
local metinler = {}
local function gez(t) for _, o in ipairs(t) do
  local ok, m = pcall(function() return o.text_func and o.text_func() or o.text end)
  if not ok then metinler[#metinler + 1] = "HATA:" .. tostring(m) else metinler[#metinler + 1] = m end
  if o.sub_item_table then gez(o.sub_item_table) end
  if o.sub_item_table_func then gez(o.sub_item_table_func()) end
end end
gez(m1); gez(m2)
local hata_var = false
for _, m in ipairs(metinler) do if tostring(m):find("^HATA") then hata_var = true; print("   " .. m) end end
kontrol(not hata_var, #metinler .. " menü öğesi metni sorunsuz")
print("   Okuyucu menüsü: " .. table.concat((function() local t = {} for _, o in ipairs(m1) do t[#t + 1] = o.text_func and o.text_func() or o.text end return t end)(), " | "))
print("   Dosya tarayıcısı menüsü: " .. table.concat((function() local t = {} for _, o in ipairs(m2) do t[#t + 1] = o.text_func and o.text_func() or o.text end return t end)(), " | "))

print(("\n%d hata"):format(hatalar))
if #loglar > 0 then print("log: " .. table.concat(loglar, " | ")) end
os.exit(hatalar == 0 and 0 or 1)
