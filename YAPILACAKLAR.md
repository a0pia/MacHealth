# Cleaner — macOS Temizlik Uygulaması · Yapılacaklar

CleanMyMac benzeri, sistemdeki gereksiz verileri bulup **önce gösteren, sonra kullanıcı onayıyla temizleyen** yerel bir macOS uygulaması.

---

## 1. Teknoloji Kararları

| Konu | Öneri | Not |
|---|---|---|
| Dil / UI | **Swift 6 + SwiftUI** (yerel macOS) | Hızlı, hafif, sistem API'lerine doğrudan erişim |
| Hedef sistem | macOS 14+ (senin makinen: macOS 26.5) | |
| Derleme | **Swift Package Manager** + `.app` paketleyen bir script | Makinede tam Xcode yok, sadece Command Line Tools var. Xcode kurarsan `.xcodeproj`'a geçebiliriz |
| Dağıtım | Şimdilik sadece kendi bilgisayarın (imzasız / ad-hoc imza) | App Store'a uygun değil (sandbox temizlik işini engeller) |
| Silme yöntemi | Varsayılan olarak **Çöp Kutusu'na taşıma** | Kalıcı silme ayrı ve açık bir seçenek olur |

---

## 2. Özellikler (Modüller)

### 2.1 Akıllı Tarama (Ana Ekran / Dashboard)
- [x] Tek tuşla tüm modülleri tarayan "Tara" butonu
- [x] Disk doluluk özeti (toplam / kullanılan / boş) — grafik
- [x] RAM kullanım özeti
- [x] Bulunan temizlenebilir toplam boyut (ör. "12,4 GB temizlenebilir")
- [x] Modül kartları: her biri bulduğu boyutu gösterir, tıklayınca detaya gider

### 2.2 Sistem Çöpü (Gereksiz Dosyalar)
- [x] Kullanıcı önbellekleri — `~/Library/Caches`
- [x] Uygulama logları — `~/Library/Logs`
- [x] Geçici dosyalar — `$TMPDIR`
- [x] Xcode artıkları — `DerivedData`, `Archives`, eski simülatörler, `iOS DeviceSupport`
- [x] Geliştirici önbellekleri — `npm`, `yarn`, `pip`, `Homebrew`, `CocoaPods`, `Gradle`
- [x] Tarayıcı önbellekleri — Safari, Chrome, Firefox, Arc vb.
- [x] Bozuk / yarım indirmeler (`.crdownload`, `.part`, `.download`)
- [x] Çöp Kutusu boyutu ve boşaltma
- [x] Her kalem için: yol, boyut, son değişiklik tarihi, onay kutusu

### 2.3 Uygulama Kaldırıcı (Uninstaller)
- [x] `/Applications` ve `~/Applications` içindeki uygulamaları listele (ikon, isim, boyut, son kullanım)
- [x] Uygulama seçilince **artık dosyalarını** bul (bundle ID ve isimle eşleştirerek):
  - `~/Library/Application Support/<app>`
  - `~/Library/Preferences/<bundle-id>.plist`
  - `~/Library/Caches/<bundle-id>`
  - `~/Library/Containers`, `Group Containers`
  - `~/Library/Saved Application State`
  - `~/Library/LaunchAgents`
  - `~/Library/HTTPStorages`, `WebKit`, `Cookies`
- [x] Uygulama + artıkları birlikte kaldırma
- [x] **Sahipsiz artıklar**: silinmiş uygulamalardan geriye kalan dosyaları bulma
- [x] Sistem uygulamalarını (Safari, Mail vb.) korumaya alma
- [x] **Sürükle-bırak ile kaldırma** — uygulamayı pencereye bırak, artıklarıyla birlikte listelensin
- [x] **Kullanılmayan uygulamalar** — X aydır açılmamış olanlar (son kullanım tarihi Spotlight metadata'dan)
- [x] **Uygulama sıfırlama** — uygulamayı silmeden ayar + önbelleğini temizleyip ilk kurulum haline getirme
- [ ] **Güncelleme kontrolü** — Sparkle / App Store / Homebrew uygulamalarının güncelliği
- [ ] **Homebrew yönetimi** — `brew cleanup`, `brew autoremove`, eski sürümler, kullanılmayan paketler
- [ ] **Dil dosyaları** — uygulamalardaki kullanılmayan `.lproj` klasörleri (imzalı uygulamaları bozabileceği için sadece bilgi / uyarıyla)

### 2.4 Büyük ve Eski Dosyalar
- [x] Belirlenen boyutun üstündeki dosyalar (varsayılan > 100 MB)
- [x] Uzun süredir açılmamış dosyalar (ör. > 1 yıl)
- [ ] Tür, boyut ve tarihe göre filtreleme / sıralama
- [x] Finder'da göster / Quick Look ile önizleme
- [x] **İndirilenler temizliği** — kurulmuş `.dmg` / `.pkg`, eski `.zip`, X günden eski indirmeler
- [x] **iOS / iPadOS yedekleri** — `~/Library/Application Support/MobileSync/Backup` (cihaz adı + tarih ile listeleme)
- [x] **Eski macOS yükleyicileri** ve yarım kalmış sistem güncellemeleri
- [x] **Time Machine yerel anlık görüntüleri** — `tmutil listlocalsnapshots` ile listeleme ve silme

### 2.4b Disk Haritası
- [x] Seçilen disk/klasörün **treemap** veya **sunburst (halka)** görünümü
- [x] Klasöre tıklayınca içine inme, üst klasöre geri dönme (breadcrumb)
- [x] Hover'da boyut + yol, sağ tıkla "Finder'da göster / Çöp'e taşı"
- [x] Tema renkleri: sarı vurgu en büyük kalemler, gri tonlar geri kalanı

### 2.5 Boş Klasörler & Gereksiz Klasörler
- [x] Seçilen dizinlerde boş klasörleri bulma (sadece `.DS_Store` içerenler de "boş" sayılır)
- [x] `node_modules`, `.venv`, `build`, `target`, `Pods` gibi yeniden üretilebilir klasörleri bulma (geliştirici modu)
- [x] **Kopya dosya bulucu** — önce boyut, sonra kısmi hash, sonra tam hash (SHA-256) ile hızlı eşleştirme
- [ ] **Benzer fotoğraflar** *(henüz yok)* — neredeyse aynı kareler ve seri çekimler (Vision framework ile görsel benzerlik)
- [x] Kopya gruplarında "hangisini tut" otomatik önerisi (en eski / en yüksek çözünürlük / belirli klasördeki)

### 2.6 Bellek (RAM) Temizliği
- [x] Anlık RAM kullanımı: aktif / kablolu / sıkıştırılmış / önbellek
- [x] En çok RAM kullanan işlemlerin listesi (ve kapatma seçeneği)
- [x] "Belleği boşalt" — `purge` komutu (yönetici şifresi ister)
- [x] **Bellek baskısı** göstergesi (yeşil / sarı / kırmızı) — macOS'un asıl ölçütü budur
- [x] **Swap kullanımı** — swap büyükse sistem diske yazıyor demektir, asıl yavaşlık sebebi
- [ ] Yanıt vermeyen (donmuş) uygulamaları tespit etme *(şimdilik: her işlem için "Zorla kapat" var, otomatik donma tespiti yok)*

> **Dürüst not:** macOS belleği zaten kendisi yönetir; "RAM temizleme" etkisi genelde kısa sürelidir. Asıl fayda, çok bellek tüketen uygulamaları görüp kapatmaktır. Bunu arayüzde de dürüstçe göstermeyi öneriyorum.

### 2.7 Hızlandırma (Mac'i hızlandır)
Mac'i yavaşlatan şeyleri bulup tek ekranda gösterir, her biri için "düzelt" butonu sunar.

- [x] **Başlangıç öğeleri** — Login Items, `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`; aç/kapat, kimin eklediği, imzalı mı
- [x] **Arka plan işlemleri** — LaunchAgents/Daemons listesi ile birlikte (updater'lar, senkronizasyon araçları)
- [x] **Ağır işlemler** — son 5 dakikada en çok CPU / enerji kullananlar
- [x] **Disk boş alanı kontrolü** — boş alan %10–15'in altındaysa uyarı (az boş alan swap'ı ve sistemi yavaşlatır)
- [ ] **Tarayıcı yükü** — açık sekme sayısı ve eklenti listesi (Chrome/Safari)
- [x] **Spotlight indeksini yeniden oluşturma** — arama yavaş/bozuksa
- [x] **DNS önbelleğini temizleme**
- ~~**Bakım betikleri** — `periodic`~~ — macOS 26'da `periodic` komutu yok, kapsam dışı
- [x] **Launch Services veritabanını onarma** — "Birlikte Aç" menüsü bozuk/çift kayıtlıysa
- [x] **Font önbelleği temizliği** — `atsutil databases -remove`
- [x] **Görsel efektleri azaltma** — Saydamlığı/Hareketi azalt ayarlarına kısayol (eski Mac'lerde fark eder)
- [x] **Termal durum** — Mac ısınıp yavaşlıyor mu (thermal state API)
- [x] **Sağlık puanı** — tüm bu kontrollerden çıkan tek bir "Mac sağlığı: 78/100" skoru ve öneri listesi

### 2.8 Sistem İzleme & Menü Çubuğu
- [x] Canlı CPU, RAM, disk, ağ kullanımı (küçük grafikler)
- [x] Pil sağlığı — döngü sayısı, maksimum kapasite %, şarj durumu
- [ ] Sıcaklık (mümkünse)
- [x] **Menü çubuğu göstergesi** — disk/RAM özeti, tek tıkla tarama, ana pencereyi açma

### 2.9 Gizlilik
- [ ] **Tarayıcı verileri** — geçmiş, çerezler, form verileri; tarayıcı bazında seçilebilir (tarayıcı kapalıyken)
- [ ] **Son kullanılanlar listeleri** — Finder ve uygulamaların "son açılanlar" kayıtları
- [ ] **İzin denetimi** — kamera, mikrofon, ekran kaydı, Tam Disk Erişimi, Erişilebilirlik izni olan uygulamalar (TCC; değiştirmek için Sistem Ayarları'na yönlendirme)

### 2.10 Otomasyon & Konfor
- [ ] **Zamanlanmış tarama** — günlük/haftalık; sonuç bildirimi ("3,2 GB temizlenebilir")
- [x] **Disk dolu uyarısı** — boş alan eşiğin altına inince bildirim
- [x] **Temizlik geçmişi** — ne zaman ne kadar yer açıldı, grafik (temanın grafik stiliyle)
- [x] **Geri al** — son temizlikte Çöp'e taşınan dosyaları tek tuşla orijinal yerlerine geri yükleme

---

## 3. Güvenlik Kuralları (kesin)

- [x] **Hiçbir şey kullanıcı onayı olmadan silinmez** — önce liste, sonra onay
- [x] Varsayılan silme = Çöp Kutusu (geri alınabilir)
- [x] Koruma listesi (beyaz liste): `/System`, `/usr`, `/bin`, `~/Documents`, `~/Desktop`, iCloud, Fotoğraflar kütüphanesi vb. asla taranmaz/silinmez
- [x] Kullanıcı kendi "dokunma" listesini ekleyebilir (Ayarlar › Dokunma listesi)
- [x] Çalışan uygulamaların önbelleği silinmeden önce uyarı
- [x] Her temizlik işlemi bir log dosyasına yazılır (ne silindi, ne zaman, kaç byte)
- [x] **Tam Disk Erişimi** izni gerekiyorsa kullanıcıya nasıl açacağı adım adım gösterilir

---

## 4. Tema (tema.jpg referansı)

Referans: açık, "kağıt" tonlu, yumuşak köşeli, hap (pill) şeklinde butonlar; koyu bir çerçeve; vurgu rengi olarak neon sarı-yeşil.

### 4.1 Renk Paleti (görselden ölçüldü)

| Token | Renk | Kullanım |
|---|---|---|
| `frame` | `#585856` | Pencerenin koyu dış çerçevesi / kenar çubuğu |
| `canvas` | `#DFDFD7` | Ana içerik zemini (sıcak açık gri) |
| `surface` | `#EFF0EB` | Kartlar |
| `surfaceRaised` | `#FFFFFF` | Aktif sekme, beyaz hap butonlar, alt bar |
| `pillMuted` | `#E9EAE5` | Pasif filtre hapları |
| `ink` | `#1F2220` | Ana metin, koyu yuvarlak butonlar |
| `inkDark` | `#272D2D` | Koyu hap / koyu seçili bölge |
| `inkMuted` | `#8A8C8B` | İkincil metin, gri haplar |
| `accent` | `#F3FC49` | Vurgu: ana "Tara/Temizle" butonu, rozetler, grafik dolgusu |
| `danger` | `#E5534B` (tahmini) | Grafikteki ince kırmızı çizgi → uyarılar |
| `success` | `#7BC67E` (tahmini) | Grafikteki yeşil çizgi → "temiz" durumu |

### 4.2 Biçim Dili
- [x] Kartlar: büyük köşe yarıçapı (~24–28 pt), gölgesiz veya çok hafif gölge
- [x] Butonlar: tam yuvarlak hap (capsule); aktif olan beyaz, pasifler gri
- [x] Yuvarlak ikon butonları (kapat `×`, `+`, filtre) — beyaz veya koyu daire
- [x] Sarı daire rozetler (görseldeki takvim ikonları gibi) → modül ikonları / bildirim sayıları
- [x] İnce bağlantı çizgileri (görseldeki zaman çizelgesi) → tarama ilerleme akışında kullanılabilir
- [x] Sol üstte büyük başlık (ör. "Akıllı Tarama"), üstte sekme hapları
- [x] Altta beyaz, yüzen hap şeklinde bir durum/aksiyon barı (görseldeki alt zaman çizelgesi gibi) → "12,4 GB seçildi · Temizle"
- [x] Tipografi: ince/regular ağırlıkta, geometrik sans-serif (SF Pro Display Light/Regular yeterli); büyük sayılar ince, birimler küçük (`89 bpm` stili → `12,4 GB`)
- [ ] Koyu mod: çerçeve/zemin tonları ters çevrilir, sarı vurgu aynı kalır *(sonraki aşama)*

### 4.3 Ekran Taslağı

```
┌──────────────────────────────────────────────────────────────┐
│ (×)  Akıllı Tarama      [Tarama] [Çöp] [Uygulamalar] [Büyük] [RAM] │  ← koyu çerçeve + haplar
│ ┌──────────────────────────────────────────────────────────┐ │
│ │  Disk          Kullanılan     Boş         RAM            │ │
│ │  Macintosh HD  412 / 512 GB   100 GB      11,2 / 16 GB   │ │
│ │                                                          │ │
│ │  (●)──────────────(●)───────────────(●)──────────── (+)  │ │  ← sarı rozetli akış
│ │  ┌────────────┐  ┌────────────┐  ┌────────────┐          │ │
│ │  │ Sistem Çöpü│  │ Uygulama   │  │ Büyük      │          │ │
│ │  │   4,2 GB   │  │ Artıkları  │  │ Dosyalar   │          │ │
│ │  │ ▁▃▅▇▅▃▁   │  │   1,8 GB   │  │   6,4 GB   │          │ │
│ │  └────────────┘  └────────────┘  └────────────┘          │ │
│ │ ╭──────────────────────────────────────────────────────╮ │ │
│ │ │ 12,4 GB temizlenebilir              [ ● Temizle ]    │ │ │  ← beyaz alt bar, sarı buton
│ │ ╰──────────────────────────────────────────────────────╯ │ │
│ └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## 5. Proje Yapısı (öneri)

```
cleaner/
├── Package.swift
├── Sources/Cleaner/
│   ├── App/            CleanerApp.swift, AppState
│   ├── Theme/          Colors, Typography, PillButton, Card, Badge
│   ├── Core/           FileScanner, SizeCalculator, TrashService, SafetyGuard, Logger
│   ├── Modules/
│   │   ├── SmartScan/
│   │   ├── SystemJunk/
│   │   ├── Uninstaller/
│   │   ├── LargeFiles/
│   │   ├── EmptyFolders/
│   │   ├── Duplicates/
│   │   ├── DiskMap/
│   │   ├── Memory/
│   │   ├── SpeedUp/
│   │   ├── Monitor/      (+ MenuBar)
│   │   ├── Privacy/
│   │   └── History/      (geçmiş + geri al)
│   └── Views/          Ortak bileşenler
├── scripts/build-app.sh   → Cleaner.app üretir
└── YAPILACAKLAR.md
```

---

## 6. Yol Haritası (aşamalar)

> **v0.4.0 (10 Ekim 2026):** Performans düzeltmesi (boşta işlemci %75–100 → ~%0: süs animasyonları Core Animation'a taşındı,
> sonsuz yerleşim döngüsü giderildi, pahalı değerler önbelleğe alındı), dar pencerede düzen (Mac Sağlığı, Hızlandır, durum hapları),
> "Diskini neler dolduruyor?" (uygulama verileri + büyük klasörler; WhatsApp ~60 GB görünür), uygulamalarda veri boyutu,
> grup klasörü eşleştirme düzeltmesi, Disk Haritası'nda görünür silme butonları, büyük uygulama verilerinin otomatik seçilmemesi,
> ikon önbelleği yenileme.

> **v0.3.0 (10 Ekim 2026):** Mac Sağlığı bölümü (pil sağlığı/döngü/sıcaklık + geçmiş, güvenlik duvarı/FileVault/Gatekeeper/SIP/
> otomatik güncelleme, SMART, Düşük Güç Modu, güncelleme denetimi, genel sağlık puanı), **Tek tıkla optimize** (tek şifreyle),
> süpürge logosu (`logo.png`, 1024 px) + menü çubuğu süpürge simgesi, Disk Haritası düzeltmeleri (çift tıklama, ilerleme,
> iptal, "Bu klasör nedir?" kutuları), koyu modda okunmayan menü paneli düzeltmesi.

> **Durum (10 Ekim 2026):** Sürüm 1 tamamlandı, Sürüm 2'nin büyük kısmı eklendi (v0.2.0) — `./scripts/build-app.sh` ile `build/Cleaner.app` üretilir.
>
> **v0.2.0'da gelenler:** sol kenar çubuğu menü (Ana Sayfa, bölümler, ⌘1–9, Esc = ana sayfa, ⌘[ = geri), yeni logo + ikon,
> canlı sıvı disk göstergesi, radar tarama animasyonu, konfetili kutlama, geçiş animasyonları, "Silersen ne olur?" bilgi kutuları
> ve risk rozetleri, silmeden önce temizlik özeti, uygulama kategorileri (Gerekli / Ara sıra / Gereksiz olabilir) + tür filtresi,
> uygulama sıfırlama, Kopya Dosyalar, Klasörler (boş + node_modules vb.), menü çubuğu paneli, disk dolu bildirimi, Ayarlar ekranı,
> başlangıç servislerinin sahibi olan uygulama ve kapatılınca ne olacağı bilgisi.

**Sürüm 1 — Yer aç + hızlandır (çekirdek)** ✅
1. **Temel** — proje iskeleti, tema bileşenleri, ana pencere, `.app` paketleme scripti
2. **Tarama motoru** — paralel dosya tarayıcı, boyut hesaplama, güvenlik koruması, Çöp'e taşıma, işlem logu
3. **Sistem Çöpü** modülü
4. **Büyük & Eski Dosyalar** + İndirilenler, iOS yedekleri, TM anlık görüntüleri
5. **Disk Haritası**
6. **Uygulama Kaldırıcı** (+ sürükle-bırak, kullanılmayan uygulamalar)
7. **Hızlandırma** — başlangıç öğeleri, ağır işlemler, bakım araçları, sağlık puanı
8. **Bellek** modülü (bellek baskısı, swap, ağır işlemler)
9. **Geri al** + temizlik geçmişi
10. **Akıllı Tarama** dashboard'u (tüm modülleri birleştirir)

**Sürüm 2 — Derinleştirme** (büyük kısmı v0.2.0'da)
11. Boş klasörler + kopya dosyalar + benzer fotoğraflar
12. Uygulama sıfırlama, güncelleme kontrolü, Homebrew yönetimi, dil dosyaları
13. Sistem izleme + menü çubuğu göstergesi + pil sağlığı

**Sürüm 3 — Konfor**
14. Gizlilik modülü
15. Zamanlanmış tarama + bildirimler + disk dolu uyarısı
16. Cilalama — animasyonlar, koyu mod, ayarlar ekranı

---

## 7. Konuşmamız Gereken Sorular

1. **Arayüz dili:** Türkçe mi, İngilizce mi, yoksa ikisi birden mi?
2. **Kapsam:** Yukarıdaki modüllerin hepsi mi, yoksa önce bir çekirdek set mi (öneri: Sistem Çöpü + Uygulama Kaldırıcı + Büyük Dosyalar)?
3. **Geliştirici temizliği** (Xcode, node_modules, Homebrew…) senin için önemli mi?
4. **Xcode** kurmayı düşünüyor musun, yoksa Command Line Tools ile mi devam edelim?
5. Tema için **koyu mod** ilk sürümde şart mı?
6. "Hafıza" derken **disk alanı** mı (depolama), **RAM** mi, yoksa ikisi de mi? Mac şu an hangi durumda yavaşlıyor (açılışta, çok uygulama açıkken, her zaman)?

~~Mail ekleri~~ — istenmedi, kapsam dışı.

---

## 8. Çalıştırma

```bash
./scripts/build-app.sh          # build/Cleaner.app üretir (release, ad-hoc imzalı)
open build/Cleaner.app

swift build && .build/debug/Cleaner --report      # tarama sonuçlarını terminale yazar, hiçbir şey silmez
.build/debug/Cleaner --snapshot <klasör>          # her ekranı PNG olarak çizer (tasarım kontrolü)
```

İlk açılışta **Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi** listesine `build/Cleaner.app`'i eklemek, Çöp Kutusu / Safari / iOS yedekleri gibi korumalı klasörlerin de taranmasını sağlar.
