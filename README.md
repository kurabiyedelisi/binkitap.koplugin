# 1000Kitap için KOReader eklentisi

Kobo'da (ya da KOReader çalışan herhangi bir e-okuyucuda) okuduğun kitabı 1000Kitap hesabınla senkron tutar: okuma durumun, alıntıların, puanın, kitaplığın ve iletilerin, kitabı bırakmadan 1000Kitap'a gider.

> Bu eklenti 1000Kitap'ın resmi bir ürünü değildir. Sitenin kendi kullandığı bağlantılarla çalışır; 1000Kitap tarafında bir değişiklik olursa eklentinin de güncellenmesi gerekebilir.

**Sürüm:** 1.3.6 · **Gerekenler:** KOReader 2024.07 ya da daha yenisi, bir 1000Kitap hesabı

## Neler yapar

- **Tek bakışta 1000Kitap ekranı.** Okuduğun kitap, yıllık hedefin, Okuyacaklarım rafı (kapaklarla), son alıntın ve bekleyen işler tek ekranda.
- **Kitabını tanır.** ISBN'den ya da Calibre'de eklediğin `1000kitap:<id>` etiketinden doğru baskıyı sormadan bulur. Bulamazsa yayınevleriyle birlikte seçenek sunar.
- **Alıntılarını gönderir.** Metni seç, "1000Kitap'a gönder"e dokun. Sayfa numarası basılı baskıya göre hesaplanır. İstersen gizli paylaşırsın; o zaman yalnızca sen görürsün.
- **Renge göre kendiliğinden gönderir.** Örneğin sarı vurgular herkese açık alıntı, mavi vurgular gizli alıntı olarak gider.
- **İleti yazdırır.** Alıntı olmayan kendi yazını 1000Kitap'ta ileti olarak paylaşabilirsin, okuduğun kitabı etiketleyerek.
- **Geçmişini aktarır.** KOReader'da daha önce bitirdiğin kitapları okuma tarihleriyle 1000Kitap'ta "Okudum" yapar, istersen o kitaplardaki vurguları da gönderir.
- **Okuma durumunu iki yönlü takip eder.** Kitabı açınca "Okuyorum" yapar. Kitap bitince tek ekranda "Okudum", puan ve kısa inceleme alır. 1000Kitap'ta değiştirdiğin durum da KOReader'a yansıyabilir.
- **Bütün kütüphaneni eşleştirir.** Kobo'daki kitapları 1000Kitap'taki karşılıklarıyla eşleştirir, emin olamadıklarını sana sorar.
- **1000Kitap kitaplığını yönetir.** Kobo'daki kitapları kitaplığına seçerek ekler, seçtiklerini çıkarır.
- **Okuyacaklar listeni doldurur.** Kobo'daki kitaplarından seçerek ya da 1000Kitap'ta arayarak "Okuyacağım" listene ekler.
- **Keşfetmene yardım eder.** Ne okusam?, sitenin kitap listeleri (sana özel öneriler, son 7 günün en çok okunanları…), Okuyacaklarım koleksiyonu, popüler alıntılar ve incelemeler, okuma hedefi var. Listelerde her kitabın 1000Kitap puanı görünür. "Okudum"dan sonra hedefinde nerede olduğunu söyler. Uyku ekranında kendi alıntılarından birini ve hedef ilerlemeni gösterebilir.
- **Kobo'nun kendi okuyucusundaki notlarını getirir (Kobo Senkron).** Kobo okuyucusunda yaptığın vurgular, notlar ve yer imleri KOReader'a gelir. Okuma ilerlemesi eşleşir, Kobo listelerin KOReader koleksiyonu olur.
- **İnternet olmadan da çalışır.** Wi-Fi kapalıyken yaptıkların sıraya girer, bağlanınca gönderilir.
- **Kendini günceller.** Yeni sürüm çıktığında neler değiştiğiyle birlikte sorar, onay verirsen kurar.

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

1. **Okuduklarını aktar:** Hesabını bağladığında eklenti bir kez sorar: "KOReader'da bitirdiğin kitapları bulup 1000Kitap'ta Okudum yapayım mı?" **Bul** dersen listeyi gösterir, seçtiklerini aktarır, sonra vurgularını göndermek isteyip istemediğini sorar.
2. **Kütüphaneni eşleştir:** Dosya tarayıcısında **Araçlar → 1000Kitap → Kütüphaneyi eşleştir.** Okuma durumlarına dokunmaz.
3. **Emin olunamayanları gözden geçir:** Her kitap için doğru baskıyı seç. Çok kitap varsa "Tek adaylıları otomatik onayla" ya da "Hepsini ilk adayla onayla" ile hızlıca geç.
4. **İstersen renk ata:** **Ayarlar → Renkle otomatik gönderim.**
5. **Okumaya başla.** Gerisi kendiliğinden olur.

## Kullanım

### 1000Kitap ekranı

Ekrana ulaşmanın en kolay yolları:

- **SimpleUI kullanıyorsan:** SimpleUI ayarlarında Gezinme çubuğu (Navigation Bar) sekmelerinden birini ya da Ana ekrandaki Hızlı İşlemler (Quick Actions) modülünü düzenle, listeden **1000Kitap**'ı seç. Aynı listede **Ne okusam?**, **Okuyacaklara ekle** ve **Kitap listeleri** de var; Hızlı Ayarlar çubuğuna da eklenebilirler. Simgeyi ve adı SimpleUI'den değiştirebilirsin.
- **KOReader menüsü:** ana sekmede (☰) **1000Kitap ekranı**; ya da **Araçlar → 1000Kitap → 1000Kitap ekranı**.
- **Hareket:** KOReader'ın hareket ayarlarında bir köşeye dokunmayı ya da kaydırmayı **1000Kitap: ekranı aç** eylemine bağla.

| Bölüm | Okurken | Dosya tarayıcısında |
| --- | --- | --- |
| Kitap | Şu an okuduğun: kapak, durum, sayfa, yüzde, 1000Kitap puanı; **Vurgular**, **İleti yaz**, **Puan ver**, **Bitirdim**, **Kitap bilgisi**, **Alıntılar**, **İncelemeler**, **Durum** | Son okuduğun; **Devam et** |
| Hedef | Bu yılın hedefi, kaç kitap kaldığı; dokununca hedef menüsü | Aynı |
| Okuyacaklarım | 4 kitaplık raf (Kobo'nda olanlar önce, kapaklarıyla); dokununca açılır. **Ne okusam?**, **Tümü**, **Listeler** | Aynı |
| Son alıntın | Gönderdiğin son alıntı | Aynı |
| Kütüphane | — | Okuyacaklarıma ekle, Okuduklarımı aktar, Durumları al, Kütüphaneyi eşleştir, Kitaplığım, İleti yaz |
| Alt satır | Bekleyen işler (dokununca gönderir), seçim bekleyen kitaplar ya da hata günlüğü, **Menü**, **Yenile** | Aynı |

**Menü** eklentinin bütün özelliklerini ve ayarlarını ekrandan çıkmadan açar: alt menülere girilir, **‹ Geri** ile dönülür; açık/kapalı ayarlar ☑/☐ ile görünür ve değiştirince hemen güncellenir.

Ekran hafızadaki bilgilerle hemen açılır, kendi başına internete çıkmaz; yalnızca hedef bilgisi eskiyse ve Wi-Fi açıksa onu tazeler. **Yenile** hedefi ve Okuyacaklar listesini yeniden getirir. Ekran sığmazsa önce son alıntı gizlenir, sonra kütüphane kısayolları tek satıra iner, en son raf kapakları gizlenir. Kapatmak için sağ üstteki çarpıya dokun ya da aşağı kaydır.

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

- **Alıntı:** Metni seç → **1000Kitap'a gönder.** Metni, sayfayı ve notu düzeltebilir; konu ve yorum izni seçebilirsin.
- **Gizli alıntı:** Alıntı penceresinde **Gizli yap**'a dokun. Gizli alıntıları 1000Kitap'ta yalnızca sen görürsün: kitabın sayfasında özel notların arasında durur, profilinde ve akışta görünmez. Hep gizli paylaşmak istersen **Ayarlar → Alıntıları varsayılan olarak gizli paylaş**'ı aç. Toplu gönderimde, vurgu aktarımında ve renk ayarlarında da gizli seçeneği var.
- **Bu kitabın vurgularını gönder:** Hepsini ya da seçtiklerini, herkese açık ya da gizli gönderir. Daha önce gönderilen vurgu tekrar gitmez.
- **Okuma durumu:** Kitabı açınca "Okuyorum" olur. KOReader'da kitabı Bitti, Beklemede ya da Okunuyor yaparsan 1000Kitap'a da yansır.
- **Yeniden okuma:** 1000Kitap'ta **Okudum** olan bir kitabı yeniden okumaya başlayınca eski okuman bozulmaz; 1000Kitap'ta **yeni bir okuma** (2. okuma gibi) başlar. Kitabı açınca ya da sayfan gönderilirken bir kez "Yeniden mi okuyorsun?" diye sorar; **Hayır, sadece bakıyorum** dersen o kitap için 30 gün sormaz. Menüden elle **Okuyorum** seçersen sormadan yeni okuma açılır. Yeni okumanın sonunda bitiş ekranı yine çıkar. KOReader'da durum değişince (Beklemede, Okunacak) Okudum olan kitaba kendiliğinden dokunulmaz. Sormasın istersen: **Ayarlar → Okunmuş kitabı yeniden açınca** (Sor / Sormadan yeni okuma başlat / Dokunma).
- **Ters yön:** Durumu 1000Kitap'ta (sitede ya da telefonda) değiştirdiysen, kitabı Kobo'da açınca KOReader'daki durumu da değiştirmeyi önerir: Okudum → Bitti, Yarım bıraktım → Beklemede, Okuyorum → Okunuyor. Kapatmak için: **Ayarlar → 1000Kitap'taki değişiklikleri KOReader'a yansıt.**
- **Bitiş ekranı:** Kitap bitince "Okudum", 1–10 puan ve inceleme tek ekranda.
- **Okuma ilerlemesi ve seanslar:** Kaçıncı sayfada olduğunu ve okuma süreni gönderir. Ayar hiç seçilmediyse ilk kitap açılışında bir kez sorulur: kitabı kapatınca / uykuya geçince, her %10'da bir ya da gönderme (sonradan: **Ayarlar → Okuma ilerlemesi**). Sayfa yalnızca 1000Kitap'ta **Okuyorum** olan kitaba yazılır; okuman başka bir baskıdaysa o okumaya yazılır. Gönderilmezse sebebi **Hata günlüğü**'nde görünür.
  1000Kitap'ta "Okuduğun sayfa sayısını güncellerken yeni bir gönderi paylaşılsın mı?" ayarı açıksa her güncelleme herkese açık bir gönderi olur; istemiyorsan o ayarı sitede kapat.
- **Sayfamı şimdi gönder:** Okurken menüde (ve 1000Kitap ekranında **Durum**'da). Sayfanı hemen gönderir ve sonucu söyler; kitap 1000Kitap'ta Okuyorum değilse önce Okuyorum yapmayı önerir. **Okudum** olan kitapta sorar: **Yeniden okuyorum** (eski okuman durur, bugünden başlayan yeni bir okuma açılır) ya da **Okudum yanlış** (durum Okuyorum'a çevrilir). Kendiliğinden giden ilerleme Okudum olan kitaba sayfa yazmaz; yeniden okuyup okumadığını sorar (yukarıya bak).

### Okuduklarını aktar

**Araçlar → 1000Kitap → Okuduklarımı aktar.** Eklentiyi kurup hesabını bağladığında bir kez kendiliğinden de sorar.

Kitaplar okuma tarihleriyle kaydedilir: başlangıç ve bitiş KOReader'ın okuma istatistiklerinden alınır; istatistik yoksa KOReader'da "Bitti" işaretlediğin gün kullanılır. Böylece geçmiş yıllarda okuduğun kitaplar bu yılın hedefine sayılmaz. Listede her kitabın yanında bitiş tarihi görünür. 1000Kitap'ta zaten açık bir okuması olan kitap (Okuyorum ya da Yarım bıraktım) tarihsiz "Okudum" yapılır ki ikinci bir okuma kaydı açılmasın. Tarih göndermek istemezsen: **Ayarlar → Okuduklarımı aktarırken okuma tarihlerini de gönder.**

1. KOReader'da "Bitti" olarak işaretlenmiş kitapların bulunur. Kitaplar açılmaz, bilgiler KOReader'ın kendi kayıtlarından okunur.
2. Liste açılır: "Bitti" olanlar seçili gelir. Sonuna kadar okunmuş ama "Bitti" işaretlenmemiş olanlar da listede durur, ama seçili gelmez. Yarım bıraktıkların listede çıkmaz.
3. Seçtiklerin 1000Kitap'ta **Okudum** olur. Eşleşmemiş olanlar önce 1000Kitap'ta aranır.
4. Ardından vurgusu olan kitaplar listelenir; hangilerinin vurgularını göndereceğini seçersin, hiçbirini seçmeden kapatabilirsin. Vurgular herkese açık ya da gizli alıntı olarak gider; sayfa numaraları basılı baskıya göre hesaplanır.

Daha önce gönderilmiş vurgular tekrar gönderilmez.

### Durumları 1000Kitap'tan al

**Araçlar → 1000Kitap → Durumları 1000Kitap'tan al.** Okuduklarını aktar'ın tersi: 1000Kitap'ta "Okudum" ya da "Yarım bıraktım" yaptığın kitapları KOReader'da da işaretler.

1. Eşleşmiş kitapların 1000Kitap'taki durumlarına birer saniye arayla bakılır; ilerleme ekranda görünür, dokununca durur. Son 6 saatte bakılmış kitaplar yeniden sorulmaz, böylece durdurup devam ettirmek hızlıdır.
2. KOReader'dakinden farklı olanlar listelenir. KOReader'da hiç durumu olmayanlar ve 1000Kitap'ta sonradan değişenler seçili gelir. KOReader'da "Okunuyor" olup 1000Kitap'ta "Okudum" olanlar listede durur ama seçili gelmez (yeniden okuyor olabilirsin); kitabın yüzde kaçının okunduğu yanında yazar.
3. KOReader'da "Bitti" ya da "Beklemede" olan bir kitaba, 1000Kitap'ta sonradan değişmediyse dokunulmaz.

Bu işaretlemeler 1000Kitap'a geri gönderilmez.

### Okuyacaklar listesi

**Araçlar → 1000Kitap → Okuyacaklarıma ekle.** Dosya tarayıcısına bağlı değildir; SimpleUI gibi farklı arayüzlerde de çalışır.

- **Kobo'daki kitaplarımdan seç:** Bütün kitapların, alt klasörler dahil, listelenir. **Listede ara…** ile adına göre süzersin, istediklerini işaretleyip eklersin. Eşleşmemiş kitaplar önce 1000Kitap'ta aranır.
- **1000Kitap'ta ara:** Kobo'da olmayan, örneğin basılı bir kitabı arayıp listene eklersin.
- Dosya tarayıcısında **Seç** ile kitap işaretlediysen onlar da ayrı bir seçenek olarak çıkar.
- Tek kitap için: dosyaya uzun bas → **1000Kitap → Okuyacağım**, ya da okurken **Okuma durumunu ayarla → Okuyacağım.**

Okuduğun ya da okumakta olduğun kitaplar "Okuyacağım"a çevrilmez.

### İleti yazma

**Araçlar → 1000Kitap → İleti yaz.** Başlık isteğe bağlı. Okurken açarsan okuduğun kitap iletiye etiketlenir, istersen kaldırırsın. Konu ve yorum izni seçebilirsin.

Yazdığın metin taslak olarak saklanır: pencereyi kapatsan da, 1000Kitap iletiyi reddetse de kaybolmaz; "İleti yaz"ı açınca kaldığın yerden devam edersin.

### 1000Kitap kitaplığım

- **Kobo'daki kitapları kitaplığa ekle:** Eşleşmiş kitaplarından kitaplığında olmayanları listeler; işaretlediklerin eklenir. Başka bir baskısı zaten kitaplığında olan kitap listede çıkmaz.
- Yüzlerce kitap seçebilirsin: seçtiklerin sıraya alınır ve arka planda, okumanı bölmeden yavaş yavaş gönderilir (ayrıntı: "Kısayollar ve çevrimdışı kullanım").
- **Kitaplığımdan çıkar:** Kitaplığının tamamını listeler; Kobo'da olanlar işaretlidir. Basılı kitapların da bu listededir; sadece işaretlediklerin, onay verdikten sonra çıkarılır.
- **Eşleşen kitapları kitaplığıma ekle** (Ayarlar, varsayılan kapalı): Eşleşen kitap kitaplığına da eklenir. Toplu onaylananlar ancak sen doğrulayınca eklenir.

### Keşif

- **Kitap bilgisi:** 1000Kitap puanı, okunma ve alıntı sayıları, senin durumun, takip ettiklerinden okuyanlar.
- **Popüler alıntılar:** Okuduğun kitabın en çok beğenilen alıntıları.
- **Kitap listeleri:** Sitenin Kitaplar sekmesindeki listeler: Sana özel öneriler (okuduklarının dışında), Son 7 günün en çok okunanları, Son 6 ayda ve Son 5 yılda çıkan en çok okunanlar, Yeni çıkanlar, En çok okunanlar, En iyiler, Romanlar ve **Konulara göre** (Edebiyat, Tarih, İslam, Siyaset, Aşk, Eğitim, Fantastik, Felsefe, Toplum, Kültür, Kişisel Gelişim, Bilim–Teknoloji–Mühendislik, Sanat, Psikoloji, Macera–Aksiyon, Ekonomi–Emek–İş dünyası, Sosyoloji, Bilimkurgu, Polisiye, Tasavvuf). Her kitabın puanı, 1000Kitap'taki durumun ve Kobo'nda olup olmadığı (✓) görünür; listenin sonunda **Daha fazla göster…** ile sonraki sayfa gelir. Kitaba dokununca **Kobo'da aç** ya da **Okuyacaklarıma ekle**. 1000Kitap ekranındaki **Listeler** düğmesi de buraya açılır.
- **Popüler incelemeler:** Okuduğun kitabın en çok beğenilen incelemeleri; yazanın adı, verdiği puan, beğeni ve yorum sayısıyla. Uzun incelemelerin devamı için 1000Kitap bağlantısı yazar.
- **1000Kitap puanı:** Arama sonuçlarında, baskı seçiminde, Okuyacaklarım ve Ne okusam? listelerinde, kitaplığında her kitabın yanında "★ 7,8" gibi görünür.
- **Ne okusam?:** Okuyacaklarım listenden rastgele 10 kitap; Kobo'nda olanlar dokununca açılır.
- **Okuyacaklarım koleksiyonu:** Listedeki ve Kobo'nda bulunan kitapları "1000Kitap – Okuyacaklarım" koleksiyonunda toplar.
- **Okuma hedefi:** Bu yılın hedefini gösterir ya da belirlersin. Bir kitap "Okudum" olunca kısa bir bildirimle hedefinde nerede olduğunu söyler ("50 kitaptan 23'ü; 27 kitap kaldı, yıl sonuna 6 hafta var"). Kapatmak için: **Ayarlar → "Okudum"dan sonra hedef ilerlemesini göster.**
- **Uyku ekranı** (Ayarlar): **Alıntılarımdan biri** kendi alıntılarından birini, **Okuma hedefi ilerlemesi** "2026 hedefi: 23 / 50 kitap" satırını uyku ekranında gösterir. İkisi birlikte de açılabilir; ikisini de kapatınca eski uyku ekranı mesajın geri gelir.

### Kobo Senkron

Kobo'nun kendi okuyucusunda (Nickel) yaptıklarını KOReader'a aktarır. Önceden ayrı bir eklentiydi (`kobosync.koplugin`), artık 1000Kitap'ın içinde. Yalnızca Kobo cihazında görünür.

- **Vurgular ve notlar** KOReader'da gerçek vurgu ve not olur. Vurgulanan metin kitapta aranarak yerleştirilir; aynı ifade birkaç kez geçiyorsa Kobo'nun kaydettiği bölüm ve konum kullanılır.
- **Kobo yer imleri** (köşe kıvırma) KOReader'da yer imi olur. Kitapta tam yeri bulunamayan bir vurgu, yaklaşık konumuna not içeren yer imi olarak eklenir; hiçbir not kaybolmaz.
- **Okuma ilerlemesi** ve "bitti" durumu aktarılır; kitabı en son hangi okuyucuda okuduysan o geçerli olur. Açık kitapta Kobo'da daha ileride kaldıysan oraya gitmeyi önerir.
- **Kobo listelerin** KOReader koleksiyonu olur. Kobo'da vurgu yaptığın bütün kitaplar "Kobo vurgu ve notları" koleksiyonunda toplanır.
- **Kendiliğinden çalışır:** Dosya tarayıcısı açılınca Kobo'da bir şey değiştiyse tarar; kitap açılınca o kitabın yeni notlarını ekler. Ekrana dokunursan durur, kalanlar kitabı açınca eklenir.
- **Nereden:** **1000Kitap → Kobo Senkron** (Şimdi senkronize et, Kobo'da notlu kitaplar, Koleksiyonlar, Ayarlar). 1000Kitap ekranının Kütüphane bölümünde **Kobo'dan aktar** ve **Kobo notları**. SimpleUI'de **Kobo** düğmesi.
- Aktarım tek yönlüdür (Kobo → KOReader); Kobo'nun veritabanına hiçbir şey yazılmaz. Bir kez aktarılan not, KOReader'da silsen de tekrar eklenmez. Kobo'da ve KOReader'da aynı dosya okunmalıdır; Kobo mağazasından alınmış şifreli kitaplar ve kalemle yapılan çizimler aktarılamaz.
- **Kobo vurgularını tek tuşla 1000Kitap'a gönder.** 1000Kitap ekranında **Kobo vurgularını 1000Kitap'a gönder**, ayrıca Kobo Senkron menüsünde ve Kobo hızlı menüsünde. Okurken o kitabın, dosya tarayıcısında bütün kitapların Kobo'dan gelen ve henüz gönderilmemiş vurgularını gönderir; herkese açık mı gizli mi diye bir kez sorar. Eşleşmesi doğrulanmamış kitaplar yanlış kitaba gitmesin diye dahil edilmez, **Kitap kitap seç**'ten eklenebilir. Bir kez gönderilen vurgu tekrar gönderilmez.
- **Gönderilenleri 1000Kitap'la karşılaştır** (Kobo Senkron menüsünde): gönderildi görünen ama 1000Kitap'taki alıntılarında olmayan Kobo vurgularını bulur (ör. 1.3.3'ten önce günlük sınıra takılıp reddedilenler), sayısını gösterir; onaylarsan yeniden gönderilebilir yapar. Yalnızca okur. 1000Kitap kitaba göre süzmeyi her zaman yapamadığı için profilindeki bütün alıntıları bir kez okur (çoksa birkaç dakika sürer); tırnak, noktalama ve büyük/küçük harf farklarını yok sayar. Okuma yarıda kalırsa (bağlantı, Durdur) hiçbir şeye dokunmaz. Bunun için Ayarlar'da 1000Kitap kullanıcı adının girili olması gerekir.
- Kobo'dan gelen vurgular renk kuralıyla **kendiliğinden** gönderilmez, renk kuralına uysalar bile; yukarıdaki düğmeyle ya da okurken **Bu kitabın vurgularını gönder → Yalnızca Kobo'dan gelenler** ile gönderilir.
- **Arka planda çalışır.** Listeler ve okuma ilerlemesi hemen aktarılır; notlar için kitaplar arka planda birer birer açılıp taranır, sen bu sırada okumaya devam edersin. Ne kadarının bittiği (yüzde, hangi kitap, kaç not) Kobo menüsünün ve 1000Kitap ekranındaki Kobo düğmesinin üstünde görünür; dokununca ayrıntı ve **Durdur** çıkar. Bitince kısa bir özet gelir. Durdurursan bitenler kaydedilir, kalanlar bir sonraki taramada sürer. Açtığın kitabın yeni Kobo notları da arka planda eklenir.
- **Hızlı arama.** Her not, Kobo'nun kaydettiği bölümde, bulunduğu yerin biraz öncesinden aranır; ancak orada bulunamazsa bütün kitapta aranır. İlk aktarım (yüzlerce notlu eski kitaplar) yine biraz sürebilir; sonrakilerde yalnızca yeni notlar aranır.
- **Eski Kobo Senkron eklentisini kullanıyorduysan:** ayarların, aktarılmış notların, hareketlerin ve SimpleUI'deki Kobo düğmen aynen çalışır. Eski eklenti hâlâ açıksa, ikisi aynı işi yapmasın diye Kobo işlerini o yapar ve 1000Kitap onu kapatmayı önerir. Kapatınca `koreader/plugins/kobosync.koplugin` klasörünü silebilirsin.

### Yinelenen alıntıları temizle

**Araçlar → 1000Kitap → Yinelenen alıntıları temizle.** Profilindeki Alıntılar bölümünü baştan sona okur. Aynı kitapta metni aynı olan alıntılardan (boşluk, noktalama, tırnak ve büyük/küçük harf farkı gözetilmez) **ilk gönderileni bırakır**, sonrakileri silinmek üzere sayar. Silmeden önce kaç tane olduğunu ve listesini gösterir, onay ister; silmek geri alınamaz.

- Hangisinin önce gönderildiği anlaşılamayan gruplara, tek kopyası olan alıntılara ve kitabı bilinmeyen alıntılara dokunmaz.
- Yavaş çalışır (sayfalar arası 1,5 sn, silmeler arası 4 sn). Okuma yarıda kalırsa ya da 1000Kitap "çok fazla istek" derse hiçbir şey silmez; silerken bir hata olursa durur.
- İlk silmeden sonra listeyi yeniden okuyup silinenin gittiğini, kalanın durduğunu doğrular; tutmazsa başka hiçbir şeyi silmez.
- Ayarlar'da 1000Kitap kullanıcı adının girili olması gerekir.

### Kısayollar ve çevrimdışı kullanım

- Wi-Fi kapalıyken yaptığın her şey sıraya girer.
- **Toplu işler arka planda gider.** Bir seferde 5'ten fazla iş sıraya girerse (kitaplığa toplu ekleme, toplu "Okudum", vurgu aktarımı gibi) ekran meşgul edilmez: işler birer birer, birkaç saniye arayla gönderilir; sayfa yeni çevrildiyse biraz beklenir. Wi-Fi giderse durur, gelince ya da KOReader yeniden açılınca kaldığı yerden sürer. Bitince kısa bir özet görünür.
- **Bekleyen gönderiler** menüde kaç iş kaldığını ve arka planda gönderim sürüyorsa bunu gösterir. Dokununca beklemeden hepsini hemen gönderir, basılı tutunca sırayı temizler.
- **Uykuya geçerken gönderim:** Cihaz uykuya geçerken Wi-Fi açıksa sıradaki birkaç iş (en fazla 5, en fazla 8 saniye) hemen gönderilir. Kalanlar cihaz uyanınca ya da Wi-Fi bağlanınca sürer. **Ayarlar → Uykuya geçerken bekleyenleri gönder** ile kapatılabilir.
- **İhtiyaç anında Wi-Fi** açıksa kitabı kapattığında Wi-Fi'yi açar, gönderir, kapatır.
- KOReader'ın hareket ayarlarında beş eylem var: **1000Kitap: ekranı aç**, **1000Kitap: bekleyenleri gönder**, **1000Kitap: Okuyacaklarıma ekle**, **1000Kitap: ileti yaz**, **1000Kitap: ne okusam?** Kobo için üç eylem daha: **Kobo: şimdi senkronize et**, **Kobo senkron menüsü**, **Kobo'da notlu kitaplar**.

## Güncelleme

**Araçlar → 1000Kitap → Ayarlar → Güncellemeleri denetle.** Yeni sürüm varsa yeniliklerin kısa bir özetiyle sorar; onaylarsan indirir ve KOReader'ı yeniden başlatmanı ister. Yeniden başlattıktan sonra neler değiştiği bir kez gösterilir; sonradan **Ayarlar → Bu sürümde neler var** ile tekrar bakabilirsin. "Haftada bir kendiliğinden denetle" açıksa Wi-Fi bağlandığında haftada bir bakar, sormadan hiçbir şey kurmaz.

Güncellemede hesap bilgilerin, ayarların ve bekleyen gönderilerin korunur. Dosyalar kurulmadan önce denetlenir; bir sorun olursa mevcut sürüm olduğu gibi kalır. Önceki sürüm eklenti klasöründeki `.yedek` klasöründe durur.

0.2.2 ve önceki sürümlerden 0.2.3 ya da sonrasına bir kez elle geçmen gerekir.

## Sorun giderme

| Belirti | Çözüm |
| --- | --- |
| "Giriş yapınız" uyarısı | Oturumun kapanmış. Kodları yeniden al ve `ayar.lua`'yı güncelle. Bekleyen gönderilerin kaybolmaz. |
| Ne okusam, koleksiyon ya da uyku ekranı çalışmıyor | `ayar.lua`'ya ya da **Hesap bilgileri**'ne kullanıcı adını ekle. |
| Kitap yanlış baskıyla eşleşmiş | Okurken **Baskıyı değiştir**, ya da dosyaya uzun bas → **Eşleşmeyi değiştir.** |
| Toplu işler hemen gitmiyor | Bilerek böyle: arka planda yavaş yavaş gönderilir. Acelen varsa **Bekleyen gönderiler**'e dokun. |
| Kütüphane eşleştirmesi yavaş | Bilerek böyle: cihazı kilitlememek için kitaplar arasında bekler. İstediğin an durdurup sonra devam edebilirsin. |
| Kaçıncı sayfada olduğum 1000Kitap'ta güncellenmiyor | Okurken menüden **Sayfamı şimdi gönder**: ya gönderir ya da neden gönderemediğini söyler. Kendiliğinden gitmesi için **Ayarlar → Okuma ilerlemesi**'ni aç. Kitap 1000Kitap'ta **Okuyorum** olmalı. |
| Güncelleme "eksik indi" ya da "tam inmedi" diye yarıda kaldı | Eklentin değişmedi, eski sürüm çalışmaya devam eder. Birkaç dakika bekleyip tekrar dene. 1.2.3 ve sonrasında yayından hemen sonra da sorunsuz iner. |
| "Sıkı okur olarak 1 günde en fazla 500 alıntı paylaşabilirsiniz" | 1000Kitap'ın günlük sınırı. Kalan alıntılar sırada bekler ve ertesi gün kendiliğinden gider (1.3.3'ten beri; öncekiler için Kobo Senkron → Gönderilenleri 1000Kitap'la karşılaştır). |
| Gönderiler gitmiyor | Wi-Fi'yi aç ya da **Bekleyen gönderiler**'e dokun. Sebebini **Ayarlar → Hata günlüğü**'nde görebilirsin. |
| Bir şey ters gitti, ne olduğunu anlamadım | **Ayarlar → Hata günlüğü → Göster.** Son 50 hata tarih, işlem ve sebebiyle durur; aynı hata art arda gelirse tek satırda sayılır. Sorun bildirirken buradakini yazman yeterli. |
| Okuyacaklar listesi uzun sürüyor | Liste sayfa sayfa gelir; kaç kitabın geldiği ekranda görünür, dokununca durur. Liste 12 saat hatırlanır. |

## Gizlilik

- Hesap kodların yalnızca Kobo'ndaki `ayar.lua` dosyasında ve eklentinin ayarlarında durur, 1000Kitap dışında hiçbir yere gönderilmez. Bu kodlar hesabının anahtarıdır, kimseyle paylaşma.
- Eklenti, güncelleme denetimi dışında yalnızca 1000Kitap'la konuşur. Güncelleme denetimi bu depodaki sürüm ve sürüm notu dosyalarını okur.
- Kobo Senkron yalnızca Kobo'nun kendi veritabanını okur; ona hiçbir şey yazmaz ve bu bilgileri hiçbir yere göndermez.
- Hata günlüğü yalnızca Kobo'nda durur; hiçbir yere gönderilmez ve hesap kodlarını içermez.
- 1000Kitap'ta senin eklediğin hiçbir şeyi kendiliğinden silmez. Kitaplığından bir kitap ancak sen seçip onaylarsan çıkarılır; tek istisna, eşleşmeyi değiştirdiğinde eklentinin kendi eklediği eski baskıdır.
