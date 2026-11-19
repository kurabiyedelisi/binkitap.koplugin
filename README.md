# 1000Kitap için KOReader eklentisi

Kobo'da (ya da KOReader çalışan herhangi bir e-okuyucuda) okuduğun kitabı 1000Kitap hesabınla senkron tutar: okuma durumun, alıntıların, puanın, kitaplığın ve iletilerin, kitabı bırakmadan 1000Kitap'a gider.

> Bu eklenti 1000Kitap'ın resmi bir ürünü değildir. Sitenin kendi kullandığı bağlantılarla çalışır; 1000Kitap tarafında bir değişiklik olursa eklentinin de güncellenmesi gerekebilir.

**Sürüm:** 0.2.4 · **Gerekenler:** KOReader 2024.07 ya da daha yenisi, bir 1000Kitap hesabı

## Neler yapar

- **Kitabını tanır.** ISBN'den ya da Calibre'de eklediğin `1000kitap:<id>` etiketinden doğru baskıyı sormadan bulur. Bulamazsa yayınevleriyle birlikte seçenek sunar.
- **Alıntılarını gönderir.** Metni seç, "1000Kitap'a gönder"e dokun. Sayfa numarası basılı baskıya göre hesaplanır. İstersen özel not olarak da gönderebilirsin.
- **Renge göre kendiliğinden gönderir.** Örneğin sarı vurgular herkese açık alıntı, mavi vurgular özel not olarak gider.
- **İleti yazdırır.** Alıntı olmayan kendi yazını 1000Kitap'ta ileti olarak paylaşabilirsin, okuduğun kitabı etiketleyerek.
- **Okuma durumunu takip eder.** Kitabı açınca "Okuyorum" yapar. Kitap bitince tek ekranda "Okudum", puan ve kısa inceleme alır.
- **Bütün kütüphaneni eşleştirir.** Kobo'daki kitapları 1000Kitap'taki karşılıklarıyla eşleştirir, emin olamadıklarını sana sorar.
- **1000Kitap kitaplığını yönetir.** Kobo'daki kitapları kitaplığına seçerek ekler, seçtiklerini çıkarır.
- **Keşfetmene yardım eder.** Ne okusam?, Okuyacaklarım koleksiyonu, popüler alıntılar, okuma hedefi var. Uyku ekranında kendi alıntılarından birini gösterebilir.
- **İnternet olmadan da çalışır.** Wi-Fi kapalıyken yaptıkların sıraya girer, bağlanınca gönderilir.
- **Kendini günceller.** Yeni sürüm çıktığında sorar, onay verirsen kurar.

## Kurulum

1. Bu sayfadaki yeşil **Code → Download ZIP** düğmesiyle indir ve zip'i aç.
2. Kobo'yu USB ile bilgisayara bağla.
3. İçinden çıkan `binkitap.koplugin` klasörünü Kobo'daki `.adds/koreader/plugins/` klasörüne kopyala.
   `.adds` gizli bir klasördür; Mac'te Finder'da `Cmd+Shift+.` ile görünür olur.
4. Aşağıdaki adımlarla hesabını bağla.
5. Kobo'yu güvenli çıkar ve KOReader'ı yeniden başlat.

## Hesabını bağlama

Eklenti şifreni istemez; tarayıcındaki 1000Kitap oturumunu kullanır. Bunu bir kez yaparsın.

1. Bilgisayarda Chrome'la 1000kitap.com'a giriş yap.
2. `F12` (Mac'te `Cmd+Option+J`) ile **Console** sekmesini aç.
3. Aşağıdaki satırı yapıştırıp Enter'a bas. Chrome yapıştırmaya izin vermezse önce `allow pasting` yazıp Enter'a bas, sonra tekrar yapıştır.

   ```js
   (()=>{const c=n=>decodeURIComponent((document.cookie.match(new RegExp('(?:^|; )'+n+'=([^;]*)'))||[])[1]||'');const p=[...document.querySelectorAll('a')].find(a=>a.textContent.trim()==='Profil');const k=p?p.getAttribute('href').replace(/^\//,''):'';copy(`return {\n    oturum_kodu = "${c('oturumkodube')}",\n    cihaz_kodu = "${c('cik-v2be')}",\n    kullanici_adi = "${k}",\n}\n`);return 'ayar.lua içeriği panoya kopyalandı'+(k?'':' (kullanıcı adı bulunamadı, elle ekle)')})()
   ```

4. Kobo'daki `binkitap.koplugin` klasöründe `ayar.lua` adlı bir dosya oluştur ve panodakini içine yapıştır.

Kodları Kobo'da da girebilirsin: **Araçlar → 1000Kitap → Ayarlar → Hesap bilgileri.** Doğru girdiğini **Bağlantıyı test et** ile kontrol et.

Tarayıcıda 1000Kitap'tan çıkış yaparsan bu oturum kapanır ve eklenti "giriş yapınız" uyarısı verir. Bunu önlemek için kodları gizli bir pencerede giriş yaparak al, pencereyi çıkış yapmadan kapat.

## İlk adımlar

1. **Kütüphaneni eşleştir:** Dosya tarayıcısında **Araçlar → 1000Kitap → Kütüphaneyi eşleştir.** Okuma durumlarına dokunmaz.
2. **Emin olunamayanları gözden geçir:** Her kitap için doğru baskıyı seç. Çok kitap varsa "Tek adaylıları otomatik onayla" ya da "Hepsini ilk adayla onayla" ile hızlıca geç.
3. **İstersen renk ata:** **Ayarlar → Renkle otomatik gönderim.**
4. **Okumaya başla.** Gerisi kendiliğinden olur.

## Kullanım

### Eşleştirme

| Nerede | Ne yapar |
| --- | --- |
| Kitabı açınca | ISBN ya da Calibre etiketi varsa sormadan eşleşir; yoksa arama açılır. |
| Okurken: **Baskıyı değiştir** | Sayfa numaralarının doğru çıkması için okuduğun baskıyı seçersin. |
| **Kütüphaneyi eşleştir** | Kobo'daki eşleşmemiş kitapları tarar. Cihazı yormamak için kitapları açmaz, 20 kitapta bir kısa mola verir. Dokununca durur; sonra kaldığı yerden devam eder. |
| **Emin olunamayanları gözden geçir** | Tek tek seç, atla ya da toplu onayla. |
| **Atlananlar** | Atladığın kitaplar burada durur; sonradan eşleştirebilir ya da tekrar taramaya alabilirsin. |
| Dosyaya uzun bas → **1000Kitap** | Kitabı açmadan eşleştirir; durum ve kitaplık düğmeleri de burada. |

**Toplu onaylanan kitaplar** "otomatik, onaylanmadı" diye işaretlenir. Böyle bir kitabı açtığında eklenti eşleşmenin yanlış olabileceğini hatırlatır; **Doğru**, **Baskıyı değiştir** ya da **Başka kitap ara** diyebilirsin. Sen doğrulayana kadar o kitap için durum, ilerleme ve renkli vurgular kendiliğinden gönderilmez.

### Okurken

- **Alıntı:** Metni seç → **1000Kitap'a gönder.** Metni, sayfayı ve notu düzeltebilir; konu ve yorum izni seçebilir ya da özel not yapabilirsin.
- **Bu kitabın vurgularını gönder:** Hepsini ya da seçtiklerini gönderir. Daha önce gönderilen vurgu tekrar gitmez.
- **Okuma durumu:** Kitabı açınca "Okuyorum" olur; daha önce okuduğun kitaba dokunulmaz. KOReader'da kitabı Bitti, Beklemede ya da Okunuyor yaparsan 1000Kitap'a da yansır.
- **Bitiş ekranı:** Kitap bitince "Okudum", 1–10 puan ve inceleme tek ekranda.
- **Okuma ilerlemesi ve seanslar** (varsayılan kapalı): Sayfanı ve okuma süreni gönderir.
  1000Kitap'ta "Okuduğun sayfa sayısını güncellerken yeni bir gönderi paylaşılsın mı?" ayarı açıksa her güncelleme herkese açık bir gönderi olur; açmadan önce o ayarı sitede kapat.

### İleti yazma

**Araçlar → 1000Kitap → İleti yaz.** Başlık isteğe bağlı. Okurken açarsan okuduğun kitap iletiye etiketlenir, istersen kaldırırsın. Konu ve yorum izni seçebilirsin.

Yazdığın metin taslak olarak saklanır: pencereyi kapatsan da, 1000Kitap iletiyi reddetse de kaybolmaz; "İleti yaz"ı açınca kaldığın yerden devam edersin.

### 1000Kitap kitaplığım

- **Kobo'daki kitapları kitaplığa ekle:** Eşleşmiş kitaplarından kitaplığında olmayanları listeler; işaretlediklerin eklenir. Başka bir baskısı zaten kitaplığında olan kitap listede çıkmaz.
- **Kitaplığımdan çıkar:** Kitaplığının tamamını listeler; Kobo'da olanlar işaretlidir. Basılı kitapların da bu listededir; sadece işaretlediklerin, onay verdikten sonra çıkarılır.
- **Eşleşen kitapları kitaplığıma ekle** (Ayarlar, varsayılan kapalı): Eşleşen kitap kitaplığına da eklenir. Toplu onaylananlar ancak sen doğrulayınca eklenir.

### Keşif

- **Kitap bilgisi:** 1000Kitap puanı, okunma ve alıntı sayıları, senin durumun, takip ettiklerinden okuyanlar.
- **Popüler alıntılar:** Okuduğun kitabın en çok beğenilen alıntıları.
- **Ne okusam?:** Okuyacaklarım listenden rastgele 10 kitap; Kobo'nda olanlar dokununca açılır.
- **Okuyacaklarım koleksiyonu:** Listedeki ve Kobo'nda bulunan kitapları "1000Kitap – Okuyacaklarım" koleksiyonunda toplar.
- **Okuma hedefi:** Bu yılın hedefini gösterir ya da belirlersin.
- **Uyku ekranında alıntılarım:** Kendi alıntılarından biri uyku ekranında görünür.

### Kısayollar ve çevrimdışı kullanım

- Wi-Fi kapalıyken yaptığın her şey sıraya girer. **Bekleyen gönderiler**'e dokununca hemen gönderir, basılı tutunca sırayı temizler.
- **İhtiyaç anında Wi-Fi** açıksa kitabı kapattığında Wi-Fi'yi açar, gönderir, kapatır.
- KOReader'ın hareket ayarlarında üç eylem var: **1000Kitap: bekleyenleri gönder**, **1000Kitap: ileti yaz**, **1000Kitap: ne okusam?**

## Güncelleme

**Araçlar → 1000Kitap → Ayarlar → Güncellemeleri denetle.** Yeni sürüm varsa sorar; onaylarsan indirir ve KOReader'ı yeniden başlatmanı ister. "Haftada bir kendiliğinden denetle" açıksa Wi-Fi bağlandığında haftada bir bakar, sormadan hiçbir şey kurmaz.

Güncellemede hesap bilgilerin, ayarların ve bekleyen gönderilerin korunur. Dosyalar kurulmadan önce denetlenir; bir sorun olursa mevcut sürüm olduğu gibi kalır. Önceki sürüm eklenti klasöründeki `.yedek` klasöründe durur.

0.2.2 ve önceki sürümlerden 0.2.3 ya da sonrasına bir kez elle geçmen gerekir.

## Sorun giderme

| Belirti | Çözüm |
| --- | --- |
| "Giriş yapınız" uyarısı | Oturumun kapanmış. Kodları yeniden al ve `ayar.lua`'yı güncelle. Bekleyen gönderilerin kaybolmaz. |
| Ne okusam, koleksiyon ya da uyku ekranı çalışmıyor | `ayar.lua`'ya ya da **Hesap bilgileri**'ne kullanıcı adını ekle. |
| Kitap yanlış baskıyla eşleşmiş | Okurken **Baskıyı değiştir**, ya da dosyaya uzun bas → **Eşleşmeyi değiştir.** |
| Kütüphane eşleştirmesi yavaş | Bilerek böyle: cihazı kilitlememek için kitaplar arasında bekler. İstediğin an durdurup sonra devam edebilirsin. |
| Gönderiler gitmiyor | Wi-Fi'yi aç ya da **Bekleyen gönderiler**'e dokun. |

## Gizlilik

- Hesap kodların yalnızca Kobo'ndaki `ayar.lua` dosyasında ve eklentinin ayarlarında durur, 1000Kitap dışında hiçbir yere gönderilmez. Bu kodlar hesabının anahtarıdır, kimseyle paylaşma.
- Eklenti, güncelleme denetimi dışında yalnızca 1000Kitap'la konuşur. Güncelleme denetimi bu depodaki sürüm dosyasını okur.
- 1000Kitap'ta senin eklediğin hiçbir şeyi kendiliğinden silmez. Kitaplığından bir kitap ancak sen seçip onaylarsan çıkarılır; tek istisna, eşleşmeyi değiştirdiğinde eklentinin kendi eklediği eski baskıdır.
