-- 1000Kitap eklentisi: sürüm notları ("Bu sürümde neler var").
-- En yeni sürüm en üstte. Yalnızca veri: güncelleme penceresi bu dosyayı GitHub'dan
-- indirip boş bir ortamda okur, bu yüzden burada kod çalıştırılmaz.
return {
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
