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
YANIT["kitaplar/kitapOku"] = function(r)
  if not kimlikli(r) then return giris_hatasi() end
  durum[r.q.id] = tonumber(r.q.durum)
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
    if f then resp = encode(f(r)) else code, resp = 404, "yok" end
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
package.preload["ffi/util"] = function()
  return { template = function(s, ...) local p = { ... }; return (s:gsub("%%(%d)", function(i) return tostring(p[tonumber(i)]) end)) end }
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
package.preload["document/documentregistry"] = function()
  return { hasProvider = function(_, yol) return yol:match("%.epub$") ~= nil or yol:match("%.pdf$") ~= nil end }
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
        flush = function() YAN_DOSYALAR[yol] = d; d._yazildi = (d._yazildi or 0) + 1 end,
      }
    end,
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
kontrol(durum["359215"] == 2, "1000Kitap'ta Okuyorum yapıldı")
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
kontrol(Plugin.SURUM == "1.2.1", "sürüm _meta.lua'dan okundu: " .. tostring(Plugin.SURUM))
kontrol(G.dahaYeni("1.2.20", "1.2.9") and G.dahaYeni("1.3", "1.2.9") and not G.dahaYeni("1.2.4", "1.2.4")
  and not G.dahaYeni("1.2.3", "1.2.4"), "sürüm karşılaştırma sayıyla yapılıyor")
local ayar_ogeleri = fm:ayarlarMenusu()
local gun_oge, oto_oge
for _, o in ipairs(ayar_ogeleri) do
  if o.text and o.text:find("^Güncellemeleri denetle") then gun_oge = o end
  if o.text == "Haftada bir kendiliğinden denetle" then oto_oge = o end
end
kontrol(gun_oge and gun_oge.text == "Güncellemeleri denetle (sürüm 1.2.1)" and oto_oge and oto_oge.checked_func(),
  "ayarlarda denetle düğmesi ve varsayılan açık haftalık denetim")

local DIZ = GERCEK .. "/binkitap.koplugin"
gercek_lfs.mkdir(GERCEK); gercek_lfs.mkdir(DIZ)
local function yaz(yol, m) local h = assert(io.open(yol, "wb")); h:write(m); h:close() end
local function oku(yol) local h = io.open(yol, "rb"); if not h then return nil end; local m = h:read("*a"); h:close(); return m end
yaz(DIZ .. "/main.lua", "-- eski main\n")
yaz(DIZ .. "/_meta.lua", 'return { version = "1.2.1" }\n')
yaz(DIZ .. "/ayar.lua", 'return { oturum_kodu = "GIZLI" }\n')
fm.path = DIZ

local HAM = "https://raw.githubusercontent.com/kurabiyedelisi/binkitap.koplugin/main/binkitap.koplugin/"
local LISTE = "https://api.github.com/repos/kurabiyedelisi/binkitap.koplugin/contents/binkitap.koplugin?ref=main"
local function depoKur(surum, dosyalar, bozuk)
  GITHUB[HAM .. "_meta.lua"] = 'return { version = "' .. surum .. '" }\n'
  local liste = {}
  dosyalar["_meta.lua"] = GITHUB[HAM .. "_meta.lua"]
  local adlar = {}
  for ad in pairs(dosyalar) do adlar[#adlar + 1] = ad end
  table.sort(adlar)
  for _, ad in ipairs(adlar) do
    GITHUB[HAM .. ad] = dosyalar[ad]
    liste[#liste + 1] = { type = (bozuk and bozuk.klasor == ad) and "dir" or "file", name = ad,
      size = (bozuk and bozuk.boyut == ad) and 99999 or #dosyalar[ad], download_url = HAM .. ad }
  end
  GITHUB[LISTE] = encode(liste)
end

depoKur("1.2.1", { ["main.lua"] = "-- aynı\n" })
fm:guncellemeDenetle(false)
kontrol(son("InfoMessage").text == "En son sürümü kullanıyorsun (1.2.1).", "güncel: " .. son("InfoMessage").text)
kontrol(fm.settings:readSetting("guncelleme_son_denetim") == os.time(), "denetim zamanı kaydedildi")

GITHUB[HAM .. "_meta.lua"] = 503
fm:guncellemeDenetle(false)
kontrol(son("InfoMessage").text:find("HTTP 503", 1, true) ~= nil, "hata gösterildi: " .. son("InfoMessage").text)

depoKur("1.2.2", { ["main.lua"] = "-- yeni main\nreturn 1\n", ["binkitap_yeni.lua"] = "return {}\n", ["ayar.lua"] = "return { oturum_kodu = \"SIFIRLANDI\" }\n",
  ["binkitap_yenilikler.lua"] = 'return { { surum = "1.2.2", maddeler = { "Yeni şey bir", "Yeni şey iki" } }, { surum = "1.2.1", maddeler = { "Eski şey" } } }\n' })
fm:guncellemeDenetle(false)
local gk = son("ConfirmBox")
kontrol(gk and gk.text:find("yeni sürümü var: 1.2.2 (sendeki 1.2.1)", 1, true) ~= nil, "yeni sürüm soruldu")
kontrol(gk.text:find("Yenilikler:\n• Yeni şey bir\n• Yeni şey iki", 1, true) and not gk.text:find("Eski şey", 1, true),
  "onay penceresinde yalnızca yeni sürümün notları: " .. gk.text:gsub("\n", " / "))
gk.ok_callback()
kontrol(oku(DIZ .. "/main.lua") == "-- yeni main\nreturn 1\n" and oku(DIZ .. "/binkitap_yeni.lua") == "return {}\n"
  and oku(DIZ .. "/_meta.lua"):find("1.2.2", 1, true), "yeni dosyalar yerinde")
kontrol(oku(DIZ .. "/ayar.lua") == 'return { oturum_kodu = "GIZLI" }\n', "ayar.lua'ya dokunulmadı")
local ayar_istendi = false
for _, r in ipairs(istekler) do if r.url == HAM .. "ayar.lua" then ayar_istendi = true end end
kontrol(not ayar_istendi, "depodaki ayar.lua indirilmedi bile")
kontrol(oku(DIZ .. "/.yedek/main.lua") == "-- eski main\n", "eski sürüm .yedek'te")
kontrol(gercek_lfs.attributes(DIZ .. "/.guncelleme/main.lua", "mode") == nil, "geçici klasörde dosya kalmadı")
kontrol(son("Restart") and son("Restart").text:find("1.2.2", 1, true), "yeniden başlatma istendi")
kontrol(fm.settings:readSetting("guncelleme_kurulan") == "1.2.2", "kurulan sürüm kaydedildi")
fm:guncellemeDenetle(false)
kontrol(son("InfoMessage").text:find("1.2.2 zaten indirildi", 1, true) ~= nil, "yeniden başlatmadan önce tekrar sormuyor")

local once_main = oku(DIZ .. "/main.lua")
depoKur("1.2.3", { ["main.lua"] = "bu lua değil (\n" })
fm:guncellemeKur("1.2.3")
kontrol(son("InfoMessage").text:find("main.lua bozuk", 1, true) and oku(DIZ .. "/main.lua") == once_main,
  "bozuk dosya: hiçbir şey değişmedi")
depoKur("1.2.3", { ["main.lua"] = "return 2\n" }, { boyut = "main.lua" })
fm:guncellemeKur("1.2.3")
kontrol(son("InfoMessage").text:find("eksik indi", 1, true) and oku(DIZ .. "/main.lua") == once_main,
  "eksik indirme: hiçbir şey değişmedi")
depoKur("1.2.3", { ["main.lua"] = "return 2\n", ["resimler"] = "x" }, { klasor = "resimler" })
fm:guncellemeKur("1.2.3")
kontrol(son("InfoMessage").text:find("elle kurulmalı", 1, true) and oku(DIZ .. "/main.lua") == once_main,
  "yeni klasör içeren sürüm otomatik kurulmadı")

-- haftalık sessiz denetim
depoKur("1.2.4", { ["main.lua"] = "return 3\n" })
fm.settings:saveSetting("guncelleme_son_denetim", os.time() - 2 * 24 * 3600)
fm:onNetworkConnected(); calistir()
kontrol(son("ConfirmBox") == gk or not son("ConfirmBox").text:find("1.2.4", 1, true), "iki gün önce denetlendiyse sormadı")
fm.settings:saveSetting("guncelleme_son_denetim", os.time() - 8 * 24 * 3600)
fm:onNetworkConnected(); fm2:onNetworkConnected(); calistir()
local sorular = 0
for _, w in ipairs(gosterilen) do if w._tur == "ConfirmBox" and w.text:find("1.2.4", 1, true) then sorular = sorular + 1 end end
kontrol(sorular == 1, "bir hafta geçince bir kez sordu (iki örnek açıkken bile)")
kontrol(son("ConfirmBox").cancel_text == "Sonra", "sormadan kurmuyor")
fm.settings:saveSetting("guncelleme_son_denetim", os.time() - 8 * 24 * 3600)
GITHUB[HAM .. "_meta.lua"] = 503
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
kontrol(durum["9517"] == 2, "doğrulanınca Okuyorum gönderildi")
kontrol(kitaplikta("9517"), "doğrulanınca kitaplığa eklendi (ayar açık)")
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
local hm = p:ayarlarMenusu()[1]
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
-- Okudum: dokunmaz, sebebini söyler
durum[k.id] = 1; sayfa2[k.id] = 0
p:sayfamiGonder(); calistir()
kontrol(sayfa2[k.id] == 0 and son("InfoMessage").text:find("\"Okudum\" görünüyor", 1, true), "Okudum'a dokunmadı, sebebini söyledi")
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
