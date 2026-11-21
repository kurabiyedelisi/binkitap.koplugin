-- 1000Kitap eklentisi: sürüm notları ("Bu sürümde neler var").
-- En yeni sürüm en üstte. Yalnızca veri: güncelleme penceresi bu dosyayı GitHub'dan
-- indirip boş bir ortamda okur, bu yüzden burada kod çalıştırılmaz.
return {
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
