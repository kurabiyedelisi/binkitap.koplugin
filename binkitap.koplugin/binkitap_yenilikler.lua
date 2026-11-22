-- 1000Kitap eklentisi: sürüm notları ("Bu sürümde neler var").
-- En yeni sürüm en üstte. Yalnızca veri: güncelleme penceresi bu dosyayı GitHub'dan
-- indirip boş bir ortamda okur, bu yüzden burada kod çalıştırılmaz.
return {
    {
        surum = "1.3.7",
        maddeler = {
            "Yeniden okuma artık 1000Kitap'ın kendi \"+ → 2. okumayı ekle → Okuyorum\" isteğiyle birebir aynı şekilde başlıyor (sitede izlenip doğrulandı). Eski okuman olduğu gibi kalır, kitabın sayfasında yeni okuma ayrı görünür.",
        },
    },
    {
        surum = "1.3.6",
        maddeler = {
            "Yeniden okuma: 1000Kitap'ta \"Okudum\" olan bir kitabı yeniden okumaya başlayınca eski okuman artık bozulmuyor; 1000Kitap'ta yeni bir okuma (2. okuma gibi) başlıyor. Kitabı açınca ya da sayfan gönderilirken bir kez \"Yeniden mi okuyorsun?\" diye sorar. \"Hayır, sadece bakıyorum\" dersen o kitap için 30 gün sormaz.",
            "Menüden elle \"Okuyorum\" seçersen de eski okuma Okuyorum'a çevrilmiyor, yeni okuma açılıyor. Yeni okumanın sonunda bitiş ekranı yine çıkar.",
            "KOReader'daki durum değişince (Beklemede, Okunacak) \"Okudum\" olan kitaba kendiliğinden dokunulmuyor.",
            "Ayarlar > \"Okunmuş kitabı yeniden açınca\": Sor (önerilen), Sormadan yeni okuma başlat ya da Dokunma.",
        },
    },
    {
        surum = "1.3.5",
        maddeler = {
            "Yinelenen alıntıları temizle (1000Kitap menüsünde): profilindeki Alıntılar bölümünü okur, aynı kitapta aynı metne sahip alıntılardan ilk gönderileni bırakıp sonrakileri, sayısını ve listesini gösterip onaylarsan siler. Yavaş çalışır; 1000Kitap yoğunsa ya da bir hata olursa durur. İlk silmeden sonra doğru alıntının gittiğini kontrol eder, tutmazsa başka hiçbir şeyi silmez.",
        },
    },
    {
        surum = "1.3.4",
        maddeler = {
            "Gönderilenleri 1000Kitap'la karşılaştır artık 1000Kitap'ın kitaba göre süzmesine güvenmiyor (bazen süzemiyor): profilindeki bütün alıntıları bir kez okuyup karşılaştırıyor. Tırnak, noktalama ve büyük/küçük harf farkları yok sayılıyor. Okuma yarıda kalırsa hiçbir şey değişmiyor.",
        },
    },
    {
        surum = "1.3.3",
        maddeler = {
            "1000Kitap'ın günlük alıntı sınırına (\"1 günde en fazla 500 alıntı\") takılan alıntılar artık silinmez: sırada bekler ve ertesi gün kendiliğinden gönderilir. O gün başka alıntı denenmez, diğer işler sürer. Bekleyen gönderiler menüsünde \"günlük sınır, yarın\" yazar.",
            "Gönderilenleri 1000Kitap'la karşılaştır (Kobo Senkron menüsünde, ayrıca Kobo vurgularını gönder penceresinde): gönderildi görünen ama 1000Kitap'ta olmayan Kobo vurgularını bulur, sayısını gösterir, onaylarsan yeniden gönderilebilir yapar. Yalnızca okur, hesabına bir şey yazmaz.",
            "Bir vurgunun herkese açık mı gizli mi gönderildiği artık kaydediliyor.",
        },
    },
    {
        surum = "1.3.2",
        maddeler = {
            "Kobo notları arka planda aktarılıyor: ekran kilitlenmiyor, okumaya devam edebilirsin. Ne kadarının bittiği Kobo menüsünde ve 1000Kitap ekranında yüzde olarak görünür; bitince kısa bir özet çıkar. İstersen durdurursun; bitenler kaydedilir, kalanlar bir sonraki taramada sürer.",
            "Çok daha hızlı: her not artık bütün kitapta değil, Kobo'nun kaydettiği bölümde, bulunduğu yerin biraz öncesinden aranır. Orada bulunamazsa eskisi gibi bütün kitapta aranır.",
            "Açtığın kitabın yeni Kobo notları da arka planda eklenir; kitap açılırken beklemezsin. Arka plan işi düşük öncelikle çalışır, sayfa çevirmek yavaşlamaz.",
            "Aktarım sırasında arkada kalan \"Kobo veritabanı okunuyor\" kutusu düzeltildi.",
        },
    },
    {
        surum = "1.3.1",
        maddeler = {
            "Kobo vurgularını tek tuşla 1000Kitap'a gönder: 1000Kitap ekranında, Kobo Senkron menüsünde ve Kobo hızlı menüsünde. Okurken o kitabınkileri, dosya tarayıcısında bütün kitaplarınkileri gönderir; herkese açık mı gizli mi diye bir kez sorar. Daha önce aktarılmış Kobo vurguları da tanınır.",
            "Dosya tarayıcısından gönderilen Kobo vurgularına sayfa numarası yazılır (yeni aktarılanlarda).",
            "Aktarırken yüzde görünüyor: Kobo notları aktarılırken hangi kitapta olduğun, kaç not arandığı ve yüzde; büyük kitaplar açılırken beklemenin normal olduğu yazıyor. Okuduklarını aktar, durumları al, eşleştirme ve gönderimde de yüzde var.",
        },
    },
    {
        surum = "1.3.0",
        maddeler = {
            "Kobo Senkron artık 1000Kitap'ın içinde: Kobo'nun kendi okuyucusunda yaptığın vurgular, notlar ve yer imleri KOReader'a gelir; okuma ilerlemesi eşleşir, Kobo listelerin KOReader koleksiyonu olur. Menüde 1000Kitap → Kobo Senkron; 1000Kitap ekranında Kobo'dan aktar ve Kobo notları.",
            "Ayrı Kobo Senkron eklentisini kullanıyorduysan ayarların, aktarılmış notların, hareketlerin ve SimpleUI'deki Kobo düğmen aynen çalışır; notlar tekrar eklenmez. Eski eklenti açıksa 1000Kitap onu kapatmayı önerir.",
            "Kobo'dan gelen vurgular renk kuralıyla 1000Kitap'a kendiliğinden gönderilmez. Göndermek istediklerini Vurgular'dan seçebilirsin.",
        },
    },
    {
        surum = "1.2.3",
        maddeler = {
            "Güncelleme düzeltmesi: yeni bir sürüm yayınlandıktan hemen sonra güncellemeye basınca GitHub'ın önbelleği eski dosyaları verebiliyordu ve kurulum \"eksik indi\" diye yarıda kalıyordu. Artık dosyalar her zaman yayınlanan sürümün kendisinden indiriliyor.",
            "Bir dosya tam inmezse ne yapman gerektiği yazıyor; eski ve yeni dosyalar hiçbir zaman karışık kurulmuyor.",
        },
    },
    {
        surum = "1.2.2",
        maddeler = {
            "Sayfamı şimdi gönder artık 1000Kitap'ta Okudum olan kitapta da çalışıyor: \"Yeniden okuyorum\" dersen eski okuman durur, bugünden başlayan yeni bir okuma açılır; \"Okudum yanlış\" dersen durum Okuyorum'a çevrilir. Sonra sayfan gönderilir.",
        },
    },
    {
        surum = "1.2.1",
        maddeler = {
            "Yeni: Sayfamı şimdi gönder (okurken menüde ve 1000Kitap ekranında Durum'da). Kaçıncı sayfada olduğunu hemen 1000Kitap'a yazar ve sonucu söyler; kitap orada Okuyorum değilse önce Okuyorum yapmayı önerir.",
            "Sayfa ilerlemesi ayarı hiç seçilmediyse, kitap açınca bir kez sorulur (kitabı kapatınca / her %10'da / gönderme).",
            "Okuman 1000Kitap'ta başka bir baskıdaysa sayfa artık o okumaya yazılıyor; önceden sessizce atlanıyordu.",
            "Otomatik (henüz onaylanmamış) eşleşmelerde de sayfa gidiyor; yanlış kitaba yazılmasın diye kitabın 1000Kitap'ta Okuyorum olması şart.",
            "Sayfa gönderilmediğinde sebebi hata günlüğüne yazılıyor (ör. kitap 1000Kitap'ta Okuyorum değil).",
        },
    },
    {
        surum = "1.2.0",
        maddeler = {
            "SimpleUI kullanıyorsan: 1000Kitap, Ne okusam?, Okuyacaklara ekle ve Kitap listeleri artık SimpleUI'nin Hızlı İşlemleri arasında. Gezinme çubuğuna sekme olarak, Ana ekrandaki Hızlı İşlemler modülüne ya da Hızlı Ayarlar çubuğuna ekleyebilirsin.",
            "KOReader menüsünün ana sekmesinde (☰) doğrudan \"1000Kitap ekranı\" var.",
        },
    },
    {
        surum = "1.1.0",
        maddeler = {
            "1000Kitap ekranından artık her şey yapılabiliyor: alttaki \"Menü\" eklentinin bütün özelliklerini ve ayarlarını açar. Alt menüden \"‹ Geri\" ile dönülür, açık/kapalı ayarlar ☑/☐ ile görünür.",
            "Okurken yeni kısayollar: Kitap bilgisi, Alıntılar, İncelemeler, Durum (okuma durumu ve baskı).",
            "Dosya tarayıcısında Kütüphane bölümüne Durumları al ve İleti yaz eklendi.",
            "Hedef satırına dokununca okuma hedefi menüsü açılır.",
        },
    },
    {
        surum = "1.0.2",
        maddeler = {
            "Düzeltme: Okuyacaklarıma ekle → Kobo'dan seç listesinde uzun klasör adı olan kitaba gelince KOReader çöküyordu. Listelerde sağdaki yazı artık kısaltılıyor.",
        },
    },
    {
        surum = "1.0.1",
        maddeler = {
            "Düzeltme: 1000Kitap ekranı açılırken KOReader'ın çökmesi giderildi.",
            "Ekran çizilirken bir sorun çıkarsa artık KOReader çökmüyor: ekran kapanıyor, sebebi hata günlüğüne yazılıyor.",
        },
    },
    {
        surum = "1.0.0",
        maddeler = {
            "1.0: eklentinin ilk tam sürümü. 0.4.2'deki her şey burada; bu sürümde yeni özellik yok, yalnızca sürüm numarası 1.0 oldu.",
        },
    },
    {
        surum = "0.4.2",
        maddeler = {
            "Kitap listelerine Romanlar ve Konulara göre eklendi: Edebiyat, Tarih, İslam, Siyaset, Aşk, Eğitim, Fantastik, Felsefe, Toplum, Kültür, Kişisel Gelişim, Bilim–Teknoloji, Sanat, Psikoloji, Macera–Aksiyon, Ekonomi, Sosyoloji, Bilimkurgu, Polisiye, Tasavvuf.",
        },
    },
    {
        surum = "0.4.1",
        maddeler = {
            "Yeni: Kitap listeleri (Keşif menüsünde ve 1000Kitap ekranında \"Listeler\"). Sitenin Kitaplar sekmesindeki listeler: sana özel öneriler, son 7 günün en çok okunanları, son 6 ayda ve son 5 yılda çıkan en çok okunanlar, yeni çıkanlar, en çok okunanlar, en iyiler.",
            "Listelerde her kitabın puanı, 1000Kitap'taki durumun ve Kobo'nda olup olmadığı (✓) görünür. Dokununca Kobo'da açabilir ya da Okuyacaklarına ekleyebilirsin.",
        },
    },
    {
        surum = "0.4.0",
        maddeler = {
            "Yeni: 1000Kitap ekranı (menünün en üstünde; hareket ayarlarında \"1000Kitap: ekranı aç\"). Okuduğun kitap, yıllık hedefin, Okuyacaklarım rafı, son alıntın ve bekleyen işler tek ekranda. Dosya tarayıcısında Devam et ve kütüphane kısayolları da var.",
            "Popüler incelemeler: okurken menüde, kitabın en beğenilen incelemeleri, yazanın verdiği puanla.",
            "1000Kitap puanı listelerde görünüyor: arama sonuçları, baskılar, Okuyacaklarım, Ne okusam?, kitaplığım.",
            "Okuduklarımı aktar artık okuma tarihlerini de gönderiyor (KOReader istatistiklerinden; yoksa Bitti işaretlediğin gün). Eski kitaplar bu yılın hedefine sayılmıyor.",
        },
    },
    {
        surum = "0.3.0",
        maddeler = {
            "Bu ekran: güncellemeden sonra yenilikler bir kez gösterilir; Ayarlar → Bu sürümde neler var.",
            "Hata günlüğü: gönderilemeyen işler ve bağlantı sorunları tarihiyle saklanır (Ayarlar → Hata günlüğü).",
            "Okuyacaklar listesi sayfa sayfa geliyor: uzun listede cihaz donmuyor, dokununca duruyor.",
            "Cihaz uykuya geçerken Wi-Fi açıksa bekleyen birkaç iş hemen gönderiliyor; kalanlar uyanınca ya da Wi-Fi bağlanınca sürüyor.",
            "1000Kitap'ta (site ya da telefon) değiştirdiğin durum KOReader'a da yansıyabiliyor: kitabı açınca soruyor.",
            "Yeni: Durumları 1000Kitap'tan al. Eşleşmiş kitapların durumlarına bakıp farkları listeler; seçtiklerini KOReader'da Bitti / Beklemede / Okunuyor yapar.",
            "Bir kitap \"Okudum\" olunca yıllık okuma hedefinde nerede olduğun kısa bir bildirimle gösteriliyor.",
            "Uyku ekranında okuma hedefi ilerlemesi (Ayarlar → Uyku ekranı); alıntıyla birlikte de açılabilir.",
        },
    },
    {
        surum = "0.2.9",
        maddeler = {
            "Gizli alıntı: alıntıyı herkese açık paylaşmak yerine 1000Kitap'ta yalnızca senin gördüğün özel not olarak saklayabilirsin.",
            "Ayarlarda \"Alıntıları varsayılan olarak gizli paylaş\" seçeneği.",
        },
    },
    {
        surum = "0.2.8",
        maddeler = {
            "Toplu işler (kitaplığa ekleme, durum aktarma) arka planda, sayfa çevirmeni bölmeden yavaş yavaş gönderiliyor.",
        },
    },
    {
        surum = "0.2.7",
        maddeler = {
            "Okuduklarımı aktar: KOReader'da bitirdiğin kitapları 1000Kitap'ta \"Okudum\" yapar, vurgularını göndermeyi önerir.",
        },
    },
    {
        surum = "0.2.6",
        maddeler = {
            "Okuyacaklarıma ekle: Kobo'daki kitaplardan seçerek ya da 1000Kitap'ta arayarak; SimpleUI dahil her arayüzde çalışır.",
        },
    },
}
