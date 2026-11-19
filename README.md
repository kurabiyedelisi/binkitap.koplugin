# 1000Kitap eklentisi (KOReader) — v0.2.3

Okuduğun kitapları, alıntılarını ve okuma ilerlemeni KOReader'dan 1000Kitap hesabına gönderir.
Resmi bir eklenti değildir. 1000Kitap'ın web sitesinin kullandığı iç API ile çalışır; site
değişirse eklentinin de güncellenmesi gerekebilir. Kullanılan uç noktalar `binkitap_api.lua`
dosyasının başında listelenmiştir.

## İndirme

Bu sayfadaki yeşil **Code → Download ZIP** düğmesiyle depoyu indir ve aç. İçindeki
`binkitap.koplugin` klasörü eklentinin kendisidir; Kobo'ya sadece onu kopyala.

## Kurulum

1. Kobo'yu USB ile bilgisayara bağla.
2. `binkitap.koplugin` klasörünü Kobo'daki `.adds/koreader/plugins/` klasörüne kopyala.
   (`.adds` gizli bir klasördür; Mac'te Finder'da `Cmd+Shift+.` ile görünür olur.)
3. Aşağıdaki adımlarla `ayar.lua` dosyasını oluştur ve aynı klasöre koy.
4. Kobo'yu güvenli çıkar, KOReader'ı yeniden başlat.
5. **Araçlar (anahtar simgesi) → 1000Kitap → Ayarlar → Bağlantıyı test et.**

KOReader 2024.07 ya da daha yeni bir sürüm gerekir.

## Hesap kodlarını alma

Eklenti şifreni kullanmaz; tarayıcındaki 1000Kitap oturumunun kodlarını kullanır.

1. Bilgisayarda Chrome'la 1000kitap.com'a giriş yap.
2. `F12` (Mac'te `Cmd+Option+J`) ile **Console** sekmesini aç.
3. Aşağıdaki satırı yapıştırıp Enter'a bas. Chrome yapıştırmaya izin vermezse önce
   `allow pasting` yaz, Enter'a bas, sonra tekrar yapıştır.

```
(()=>{const c=n=>decodeURIComponent((document.cookie.match(new RegExp('(?:^|; )'+n+'=([^;]*)'))||[])[1]||'');const p=[...document.querySelectorAll('a')].find(a=>a.textContent.trim()==='Profil');const k=p?p.getAttribute('href').replace(/^\//,''):'';copy(`return {\n    oturum_kodu = "${c('oturumkodube')}",\n    cihaz_kodu = "${c('cik-v2be')}",\n    kullanici_adi = "${k}",\n}\n`);return 'ayar.lua içeriği panoya kopyalandı'+(k?'':' (kullanıcı adı bulunamadı, elle ekle)')})()
```

4. Eklenti klasöründe `ayar.lua` adında bir dosya oluştur ve panodakini içine yapıştır.

Kodları Kobo'da da girebilirsin: **1000Kitap → Ayarlar → Hesap bilgileri.**

**Dikkat:**
- Bu kodlar hesabının anahtarıdır, kimseyle paylaşma.
- Tarayıcıda 1000Kitap'tan **çıkış yaparsan** bu oturum kapanır. Kobo'ya ayrı bir oturum
  vermek için gizli pencerede giriş yap, kodları oradan al, pencereyi çıkış yapmadan kapat.
- Oturum kapanırsa eklenti uyarır; bekleyen gönderiler kaybolmaz.

## Özellikler

### Eşleştirme
- **ISBN ile otomatik eşleştirme.** Kitapta ISBN varsa sormadan doğru baskıyla eşleşir.
- **Calibre etiketi.** Calibre'de kitaba `1000kitap:24319` gibi bir tanımlayıcı eklersen eşleşme kesin olur.
- **Aramada yayınevi.** Sonuçlar "Walden — Henry David Thoreau · Zeplin Kitap, 2019" gibi görünür.
- **Baskıyı değiştir.** Doğru baskıyı seçince sayfa numaraları daha isabetli olur.
- **Kütüphaneyi eşleştir.** Kobo'daki tüm kitapları tarar; ISBN'i ya da başlığı ve yazarı birebir
  tutanları kendisi eşleştirir, emin olamadıklarını sonda sorar. Okuma durumlarını değiştirmez.
  Durdurulabilir, kaldığı yerden devam eder.
- **Atlananlar.** Gözden geçirirken "Atla" dediğin kitaplar ayrı bir listede durur. Oradan
  "Şimdi eşleştir" ya da "Tekrar taramaya al" diyebilirsin; "Hepsini tekrar taramaya al" listeyi boşaltır.
- **Dosyaya uzun basınca "1000Kitap".** Kitabı açmadan eşleştir, Okuyacağım/Okuyorum/Okudum/Yarım bıraktım,
  Kitaplığa ekle/Kitaplıktan çıkar.
- **Toplu "Okuyacağım".** Dosya tarayıcısında "Seç" ile kitap seç (ya da klasörden işaretle);
  okuduğun ya da okumakta olduğun kitaplara dokunulmaz.

### 1000Kitap kitaplığım
- **Kobo'daki kitapları kitaplığa ekle.** Eşleşmiş kitaplarından 1000Kitap kitaplığında olmayanları
  listeler; işaretlediklerin eklenir. Aynı kitabın başka bir baskısı zaten kitaplığındaysa listede çıkmaz.
- **Kitaplığımdan çıkar.** 1000Kitap kitaplığının tamamını listeler (Kobo'da olanlar işaretli);
  sadece seçtiklerin, onay verdikten sonra çıkarılır. Basılı kitapların da bu listede olabilir.
- **Tek kitap:** okurken menüden ya da dosyaya uzun basınca "Kitaplığa ekle / Kitaplıktan çıkar".
- **Eşleşen kitapları kitaplığıma ekle** (Ayarlar, varsayılan kapalı): bir kitap eşleşince kitaplığa da
  eklenir. Eşleşmeyi değiştirirsen eklentinin eklediği eski baskı çıkarılır; senin önceden
  kitaplığında olan bir kitaba dokunulmaz.

### Okurken
- **Vurgu menüsü → "1000Kitap'a gönder".** Metni, sayfayı, notu düzenle; konu ve yorum izni seç
  ya da **özel not** olarak gönder (profilinde görünmez).
- **Renkle otomatik gönderim.** Ayarlar'dan her renge bir iş ver: herkese açık alıntı, özel not
  ya da gönderme. Bir rengi açmadan önce o renkle yaptığın vurgular gönderilmez.
- **Bu kitabın vurgularını gönder.** "Hepsini gönder" ya da "Seçerek gönder"; aynı vurgu iki kez gitmez.
- **Otomatik "Okuyorum".** Eşleşince/açılınca; daha önce okuduğun kitaplara dokunmaz.
- **KOReader durumunu yansıtma.** Bitti → Okudum, Beklemede → Yarım bıraktım, Okunuyor → Okuyorum.
- **Bitiş ekranı.** Kitap bitince "Okudum", 1–10 puan ve kısa inceleme tek ekranda.
- **Okuma ilerlemesi** (varsayılan kapalı): kitabı kapatınca ya da her %10'da.
- **Okuma seansları / günlük seri** (varsayılan kapalı): okuduğun süre ve sayfa.
  1 dakikadan kısa seanslar gönderilmez; bir sayfada 5 dakikadan uzun kalınan süre sayılmaz.

> İlerleme ve seanslar varsayılan olarak kapalı, çünkü 1000Kitap'ta "Okuduğun sayfa sayısını
> güncellerken yeni bir gönderi paylaşılsın mı?" ayarı açıksa her güncelleme herkese açık bir
> gönderi oluşturur. Açmadan önce o ayarı sitede kapatmanı öneririm.

### Keşif
- **Kitap bilgisi:** 1000Kitap puanı, okunma/beğeni/alıntı sayıları, senin durumun, takip ettiklerinden okuyanlar.
- **Popüler alıntılar:** okuduğun kitabın en beğenilen alıntıları.
- **Ne okusam?:** Okuyacaklarım listenden rastgele 10 kitap; Kobo'nda olanlar ✓ ile işaretli ve dokununca açılır.
- **Okuyacaklarım koleksiyonu:** listedeki ve Kobo'nda bulunan kitapları "1000Kitap – Okuyacaklarım"
  koleksiyonuna ekler, artık listede olmayanları çıkarır.
- **Okuma hedefi:** bu yılın hedefini göster ya da belirle.
- **Uyku ekranında alıntılarım:** kendi alıntılarından rastgele biri uyku ekranında görünür;
  kapatınca eski uyku ekranı mesajın geri gelir.

### Kolaylıklar
- **Çevrimdışı sıra:** Wi-Fi kapalıysa her şey sıraya girer, bağlanınca gönderilir.
- **İhtiyaç anında Wi-Fi:** kitabı kapatınca sırada bir şey varsa Wi-Fi'yi açar, gönderir, kapatır.
- **Hareketler:** KOReader'ın hareket yöneticisinde (dişli simgesi → Dokunma ve hareketler)
  "1000Kitap: bekleyenleri gönder" ve "1000Kitap: ne okusam?" eylemleri var.
- **Otomatik durum değişikliklerinde onay** (isteğe bağlı).

## Menü

**Araçlar → 1000Kitap** (kitap açıkken):
Kitap · Baskıyı değiştir · Okuma durumunu ayarla · Puan ver · Bu kitabın vurgularını gönder ·
Kitap bilgisi · Popüler alıntılar · Kütüphaneyi eşleştir · Emin olunamayanları gözden geçir ·
Atlananlar · 1000Kitap kitaplığım · Ne okusam? · Okuyacaklarım koleksiyonunu güncelle · Okuma hedefi · Bekleyen gönderiler · Ayarlar

Dosya tarayıcısında ayrıca **Kitapları "Okuyacağım" olarak ekle** vardır.
**Bekleyen gönderiler**'e dokununca hemen gönderir; basılı tutunca sırayı temizler.

## Bilinen sınırlar

- KOReader'ın "Tüm notları dışa aktar" menüsüne 1000Kitap eklenemedi: KOReader dışarıdan hedef
  eklemeye resmi bir yol sunmuyor. Aynı işi "Bu kitabın vurgularını gönder" yapıyor.
- Okuma hedefinde "şimdiye kadar okunan" sayısı, 1000Kitap'ın yanıtında bulunursa gösterilir.
- Kitap başlığı ve yazar dosyada hiç yoksa kütüphane eşleştirmesi dosya adına bakar.

## Güncelleme

0.2.3'ten itibaren eklenti kendini bu depodan güncelleyebilir:
**Araçlar → 1000Kitap → Ayarlar → Güncellemeleri denetle.** Yeni sürüm varsa sorar, onay verirsen
indirir ve KOReader'ı yeniden başlatmanı ister. "Haftada bir kendiliğinden denetle" açıksa (varsayılan)
Wi-Fi bağlandığında haftada bir bakar; sormadan hiçbir şey kurmaz.

- `ayar.lua`, eklenti ayarların ve bekleyen gönderilerin korunur.
- Dosyalar önce denetlenir (boyut, Lua sözdizimi); bir sorun olursa eski sürüm olduğu gibi kalır.
- Önceki sürüm eklenti klasöründeki `.yedek` klasöründe durur.
- 0.2.2 ve öncesinden geçerken bir kez elle kurman gerekir.

## Geliştirme

Testler KOReader'ı ve 1000Kitap'ı taklit eden sahte bir ortamda çalışır; gerçek hesaba istek gitmez.

```
texlua test/sozdizimi.lua binkitap.koplugin/*.lua
texlua test/uctan_uca.lua
```

`ayar.lua` `.gitignore`'dadır; hesap kodlarını asla depoya ekleme.
