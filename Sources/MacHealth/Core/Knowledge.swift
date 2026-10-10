import Foundation

/// "Bunu silersen ne olur?" bilgisi.
struct Insight: Sendable {
    enum Risk: Int, Sendable, Comparable {
        case safe, low, caution
        static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .safe: "Güvenli"
            case .low: "Düşük risk"
            case .caution: "Dikkat"
            }
        }
    }

    let what: String
    let consequences: [String]
    let risk: Risk
}

/// Gruplar ve bilinen dosyalar için açıklamalar.
enum Knowledge {
    static func group(_ id: String) -> Insight? { groups[id] }

    /// Belirli bir öğe için daha özel bilgi (yoksa nil).
    static func item(_ item: CleanItem) -> Insight? {
        let hay = (item.name + " " + item.url.path).lowercased()
        return items.first { keys, _ in keys.contains { hay.contains($0) } }?.1
    }

    /// Verisi çok yer kaplayan bilinen uygulamalar için "nasıl küçültürsün" bilgisi.
    static func appData(bundleID: String?, name: String, dataSize: Int64) -> Insight? {
        let id = bundleID?.lowercased() ?? ""
        let known: [(String, String, [String])] = [
            ("net.whatsapp", "WhatsApp'ın sohbet veritabanı ve sohbetlerde gelen fotoğraf, video ve belgeler.",
             ["WhatsApp › Ayarlar › Depolama ve Veriler › Depolamayı Yönet'ten büyük videoları ve iletilmiş medyayı sil.",
              "Sohbet bazında \"Medyayı temizle\" ile o sohbetin tüm medyasını kaldırabilirsin; mesajlar kalır.",
              "Buradaki dosyaları elle silmek WhatsApp'ı bozabilir."]),
            ("ru.keepcoder.telegram", "Telegram'ın indirilmiş medya önbelleği.",
             ["Telegram › Ayarlar › Veri ve Depolama › Depolama Kullanımı › Önbelleği Temizle.",
              "Medya bulutta durduğu için tekrar açınca yeniden indirilir."]),
            ("org.telegram", "Telegram'ın indirilmiş medya önbelleği.",
             ["Telegram › Ayarlar › Gelişmiş › Depolamayı Yönet › Tümünü Temizle."]),
            ("com.spotify", "Spotify şarkı önbelleği ve çevrimdışı indirmeler.",
             ["Spotify › Ayarlar › Depolama › Önbelleği temizle.", "Çevrimdışı indirmeleri istemiyorsan indirilen listelerde indirmeyi kapat."]),
            ("com.tinyspeck.slack", "Slack önbelleği ve indirilen dosyalar.",
             ["Slack › Yardım › Sorun Giderme › Önbelleği Temizle ve Yeniden Başlat."]),
            ("com.docker", "Docker imajları, konteynerler ve sanal disk.",
             ["Terminalde `docker system prune -a` kullanılmayan imajları siler.", "Docker Desktop › Troubleshoot › Clean / Purge data."]),
            ("com.google.android.studio", "Android Studio ayarları, önbellekleri ve dizinleri.",
             ["File › Invalidate Caches ile önbelleği temizle.", "SDK Manager'dan kullanmadığın emülatör imajlarını kaldır."]),
        ]
        if let k = known.first(where: { id.hasPrefix($0.0) }) {
            return Insight(what: k.1 + " Şu an \(Format.bytes(dataSize)).", consequences: k.2, risk: .low)
        }
        guard dataSize > 1024 * 1024 * 1024 else { return nil }
        return Insight(what: "\(name) Library'de \(Format.bytes(dataSize)) veri tutuyor.",
                       consequences: ["Önce uygulamanın kendi ayarlarında \"önbellek\", \"depolama\" ya da \"indirilenler\" bölümüne bak.",
                                      "Uygulamayı artık kullanmıyorsan kaldırmak bu verileri de temizler."], risk: .low)
    }

    /// Disk Haritası'nda bilinen klasörler için "Bu klasör nedir?" bilgisi.
    static func folder(_ url: URL) -> (insight: Insight, action: Module?)? {
        let p = url.path.replacingOccurrences(of: SafetyGuard.home.path, with: "~")
        // Liste özelden genele sıralı; ilk eşleşen kazanır.
        return folders.first { p.hasSuffix($0.0) }?.1
    }

    private static let folders: [(String, (insight: Insight, action: Module?))] = [
        ("group.net.whatsapp.WhatsApp.shared", (Insight(
            what: "WhatsApp'ın sohbet veritabanı ve sohbetlerde gelen fotoğraf, video, ses ve belgeler.",
            consequences: [
                "Buradan elle silmek WhatsApp'ı bozabilir; bunun yerine WhatsApp › Ayarlar › Depolama ve Veriler › Depolamayı Yönet'i kullan.",
                "Orada büyük videoları ve iletilmiş medyayı sohbet bazında güvenle silebilirsin.",
                "Telefondaki sohbetlerin etkilenmez.",
            ], risk: .caution), nil)),
        ("~/Library/Group Containers", (Insight(
            what: "Aynı geliştiricinin uygulamalarının (ör. uygulama + widget) paylaştığı veriler.",
            consequences: ["Uygulamaların asıl verileri burada durur; elle silmek yerine ilgili uygulamanın kendi ayarlarını kullan."], risk: .caution), nil)),
        ("~/Library/Android/sdk/system-images", (Insight(
            what: "Android emülatörü için indirilmiş sistem imajları (her Android sürümü birkaç GB).",
            consequences: ["Kullanmadığın sürümleri Android Studio › Settings › SDK Manager'dan kaldırabilirsin.",
                           "Kullandığın emülatörün imajını silersen emülatör açılmaz."], risk: .low), nil)),
        ("~/Library/Android/sdk/ndk", (Insight(
            what: "Android NDK sürümleri (C/C++ derleme araçları).",
            consequences: ["Projelerinin kullanmadığı eski NDK sürümlerini SDK Manager'dan kaldırabilirsin."], risk: .low), nil)),
        ("~/Library/Android", (Insight(
            what: "Android SDK: derleme araçları, platformlar ve emülatör imajları.",
            consequences: ["Android geliştirme yapıyorsan gereklidir. Yer açmak için SDK Manager'dan eski sürümleri kaldır."], risk: .caution), nil)),
        ("~/.android", (Insight(
            what: "Android emülatörlerinin (AVD) sanal diskleri ve ayarları.",
            consequences: ["Kullanmadığın emülatörleri Android Studio › Device Manager'dan silebilirsin."], risk: .low), nil)),
        ("~/Library/Caches", (Insight(
            what: "Uygulama önbellekleri.",
            consequences: ["Güvenle temizlenebilir; Sistem Çöpü bölümü bunu sizin için yapar."], risk: .safe), .junk)),
        ("~/Library/Developer", (Insight(
            what: "Xcode derleme dosyaları, simülatörler ve cihaz destek dosyaları.",
            consequences: ["DerivedData ve önbellekler Sistem Çöpü'nden temizlenebilir."], risk: .low), .junk)),
        ("~/.gradle", (Insight(
            what: "Gradle'ın indirdiği Java/Android bağımlılıkları.",
            consequences: ["Sistem Çöpü › Geliştirici önbellekleri'nden temizlenebilir; projeler ilk derlemede yeniden indirir."], risk: .safe), .junk)),
        ("~/.npm", (Insight(
            what: "npm paket önbelleği.",
            consequences: ["Sistem Çöpü › Geliştirici önbellekleri'nden güvenle temizlenebilir."], risk: .safe), .junk)),
        ("~/Library/Application Support/MobileSync", (Insight(
            what: "iPhone / iPad yerel yedekleri.",
            consequences: ["Büyük Dosyalar › iPhone / iPad yedekleri'nden yönetebilirsin."], risk: .caution), .largeFiles)),
        ("~/Library/Containers", (Insight(
            what: "Sandbox'lı (App Store) uygulamaların kendi verileri.",
            consequences: ["macOS bu klasörleri korur; uygulamayı kaldırmak için Uygulamalar bölümünü kullan."], risk: .caution), .uninstaller)),
        ("~/Library/Application Support", (Insight(
            what: "Uygulamaların ayarları, veritabanları ve indirdiği içerikler.",
            consequences: ["Silinmiş uygulamaların kalıntıları Uygulamalar › Sahipsiz artıklar'da listelenir."], risk: .caution), .uninstaller)),
        ("~/Library/Mail", (Insight(
            what: "Mail uygulamasının e-postaları ve ekleri.",
            consequences: ["Elle silme; Mail'in kendi ayarlarından yönet."], risk: .caution), nil)),
        ("~/Downloads", (Insight(
            what: "İndirilen dosyalar.",
            consequences: ["Kurulum dosyaları ve eski indirmeler Büyük Dosyalar bölümünde listelenir."], risk: .low), .largeFiles)),
        ("~/Library", (Insight(
            what: "Uygulamaların ayarları, önbellekleri ve verileri. macOS'un çalışması için gereklidir.",
            consequences: ["İçinden elle bir şey silmek uygulamaları bozabilir.",
                           "Güvenli temizlik için Sistem Çöpü ve Uygulamalar bölümlerini kullan."], risk: .caution), .junk)),
    ]

    private static let groups: [String: Insight] = [
        "userCaches": Insight(
            what: "Uygulamaların daha hızlı açılmak için sakladığı geçici veriler: küçük resimler, indirilmiş içerik, derlenmiş kod.",
            consequences: [
                "Uygulamalar bir sonraki açılışta biraz yavaş açılabilir.",
                "Önbellek, uygulama kullanıldıkça kendiliğinden yeniden oluşur.",
                "Belgelerin, ayarların ve hesap girişlerin etkilenmez.",
            ], risk: .safe),
        "browser": Insight(
            what: "Tarayıcıların ziyaret ettiğin sitelerden sakladığı resim, betik ve sayfa parçaları.",
            consequences: [
                "Siteler ilk ziyarette biraz daha yavaş yüklenir.",
                "Geçmiş, şifreler, yer imleri ve çerezler SİLİNMEZ; oturumların açık kalır.",
                "Tarayıcı açıksa önce kapatman önerilir.",
            ], risk: .safe),
        "logs": Insight(
            what: "Uygulamaların çalışırken tuttuğu kayıtlar ve çökme raporları.",
            consequences: [
                "Hata kayıtları silinir; şu an bir sorunu çözmeye çalışıyorsan saklamak isteyebilirsin.",
                "Uygulamaların çalışması etkilenmez.",
            ], risk: .safe),
        "temp": Insight(
            what: "Uygulamaların işlem sırasında oluşturup bazen silmeyi unuttuğu geçici dosyalar.",
            consequences: [
                "Sadece 3 günden eski dosyalar silinir; kullanımdaki yeni dosyalar korunur.",
                "Çalışan uygulamalar etkilenmez.",
            ], risk: .safe),
        "xcode": Insight(
            what: "Xcode'un derleme ara dosyaları, cihaz destek dosyaları ve arşivleri.",
            consequences: [
                "DerivedData silinirse projeler bir sonraki derlemede baştan derlenir (ilk derleme uzun sürer).",
                "Cihaz destek dosyaları, cihaz tekrar bağlandığında yeniden hazırlanır.",
                "Archives silinirse yayımlanmış eski sürümlerin arşivleri kaybolur.",
            ], risk: .low),
        "dev": Insight(
            what: "npm, Gradle, Homebrew, pip gibi araçların indirdiği paketlerin yerel kopyaları.",
            consequences: [
                "Paketler bir sonraki kurulumda internetten yeniden indirilir.",
                "İlk `npm install` / Gradle derlemesi bir kereliğine daha uzun sürer.",
                "Projelerin, kaynak kodun ve kurulu programlar etkilenmez.",
            ], risk: .safe),
        "broken": Insight(
            what: "Tarayıcıda yarıda kesilmiş ya da başarısız olmuş indirmeler.",
            consequences: ["Yarım dosyalar silinir; bu indirmeler devam ettirilemez.", "Tamamlanmış indirmeler etkilenmez."],
            risk: .safe),
        "trash": Insight(
            what: "Daha önce Çöp Kutusu'na attığın dosyalar.",
            consequences: ["Dosyalar KALICI olarak silinir.", "Bu işlem geri alınamaz; Geçmiş ekranından da geri gelmez."],
            risk: .caution),
        "large": Insight(
            what: "Ana klasöründeki büyük dosyalar: videolar, disk görüntüleri, arşivler, sanal makineler.",
            consequences: [
                "Bunlar senin kişisel dosyaların olabilir. Emin değilsen önce Önizle ile bak.",
                "Çöp Kutusu'na taşınır; boşaltana kadar geri alabilirsin.",
                "Bir uygulama veya proje bu dosyayı kullanıyorsa çalışmayabilir.",
            ], risk: .caution),
        "old": Insight(
            what: "Bir yıldan uzun süredir açılmamış 10 MB üzeri dosyalar.",
            consequences: [
                "Uzun süredir açılmamış olmaları önemsiz oldukları anlamına gelmez (ör. arşiv belgeler, fotoğraflar).",
                "Çöp Kutusu'na taşınır; geri alınabilir.",
            ], risk: .caution),
        "installers": Insight(
            what: "İndirilenler klasöründeki .dmg / .pkg kurulum dosyaları.",
            consequences: [
                "Kurulu uygulamalar ÇALIŞMAYA DEVAM EDER; sadece kurulum dosyası silinir.",
                "Uygulamayı yeniden kurmak istersen tekrar indirmen gerekir.",
            ], risk: .safe),
        "oldDownloads": Insight(
            what: "İndirilenler klasöründe 30 günden uzun süredir duran dosyalar.",
            consequences: ["Belge, fotoğraf veya fatura gibi önemli dosyalar olabilir; tek tek gözden geçir."],
            risk: .caution),
        "iosBackups": Insight(
            what: "iPhone / iPad'in bu Mac'e Finder ile alınmış yerel yedekleri.",
            consequences: [
                "Bu yedek silinirse cihazını bu yedekten geri yükleyemezsin.",
                "iCloud yedekleri etkilenmez.",
                "Cihazın iCloud'a yedekleniyorsa genelde güvenle silinebilir.",
            ], risk: .caution),
        "macInstallers": Insight(
            what: "Eski macOS sürümlerinin kurulum uygulamaları.",
            consequences: ["Mevcut sistemin etkilenmez.", "Gerekirse App Store'dan tekrar indirilebilir."],
            risk: .safe),
        "orphans": Insight(
            what: "Artık yüklü olmayan uygulamaların Library'de bıraktığı ayar, önbellek ve veri dosyaları.",
            consequences: [
                "Uygulamayı ileride yeniden kurarsan ayarların sıfırdan başlar.",
                "Oyun veya emülatör kayıtları (save dosyaları) burada olabilir.",
            ], risk: .low),
        "duplicates": Insight(
            what: "İçeriği birebir aynı olan dosyalar (aynı boyut ve aynı SHA-256 özeti).",
            consequences: [
                "Her gruptan en az bir kopya mutlaka korunur.",
                "Bir uygulama ya da proje belirli bir kopyanın yerini kullanıyorsa bağlantı kopabilir.",
            ], risk: .low),
        "emptyFolders": Insight(
            what: "İçinde hiçbir dosya olmayan klasörler (sadece .DS_Store içerenler de dahil).",
            consequences: ["Klasörler silinir; bazı uygulamalar ihtiyaç duyarsa kendisi yeniden oluşturur."],
            risk: .safe),
        "devFolders": Insight(
            what: "node_modules, .venv, Pods, build gibi yeniden üretilebilen proje klasörleri.",
            consequences: [
                "Projeyi tekrar çalıştırmadan önce `npm install`, `pip install`, `pod install` vb. gerekir.",
                "Kaynak kodun ve proje dosyaların etkilenmez.",
            ], risk: .low),
        "uninstall": Insight(
            what: "Uygulama paketi ve Library'deki ayar, önbellek, destek dosyaları.",
            consequences: [
                "Uygulama ve seçili dosyaları Çöp Kutusu'na taşınır; Geçmiş'ten geri alınabilir.",
                "Uygulamayla oluşturduğun belgeler (Belgeler, Masaüstü) silinmez.",
                "Ücretli uygulamalarda yeniden kurarken lisans/hesap girişi gerekebilir.",
            ], risk: .low),
        "reset": Insight(
            what: "Uygulamanın ayarları, oturumları ve önbelleği; uygulamanın kendisi kalır.",
            consequences: [
                "Uygulama ilk kurulduğu gibi açılır: ayarlar ve giriş bilgileri sıfırlanır.",
                "Bozulan / çöken bir uygulamayı düzeltmenin pratik yoludur.",
            ], risk: .low),
    ]

    private static let items: [([String], Insight)] = [
        (["spotify"], Insight(what: "Spotify'ın şarkı önbelleği ve çevrimdışı indirmeleri.",
                              consequences: ["Çevrimdışı indirdiğin şarkılar silinir, tekrar indirmen gerekir.", "Hesabın ve çalma listelerin etkilenmez."], risk: .caution)),
        (["gradle"], Insight(what: "Gradle'ın indirdiği Java/Android bağımlılıkları.",
                             consequences: ["Android/Java projeleri ilk derlemede bağımlılıkları yeniden indirir (birkaç GB olabilir).", "Projelerin etkilenmez."], risk: .safe)),
        (["homebrew"], Insight(what: "Homebrew'un indirdiği paket arşivleri.",
                               consequences: ["Kurulu programlar etkilenmez; sadece indirme arşivleri silinir."], risk: .safe)),
        (["/.npm", " npm"], Insight(what: "npm paket önbelleği.",
                                    consequences: ["Paketler bir sonraki kurulumda yeniden indirilir.", "Projeler ve node_modules etkilenmez."], risk: .safe)),
        (["playwright"], Insight(what: "Playwright'ın test için indirdiği tarayıcılar.",
                                 consequences: ["Testleri çalıştırmadan önce `npx playwright install` gerekir."], risk: .safe)),
        (["huggingface", "hugging face"], Insight(what: "İndirilmiş yapay zekâ modelleri.",
                                                  consequences: ["Modeller tekrar indirilir; boyutları onlarca GB olabilir."], risk: .caution)),
        (["archives"], Insight(what: "Xcode ile yayımlanmış uygulama arşivleri (.xcarchive).",
                               consequences: ["Eski sürümlerin çökme raporlarını çözümlemek için gereken dSYM dosyaları kaybolur."], risk: .caution)),
        (["deriveddata"], Insight(what: "Xcode derleme ara dosyaları.",
                                  consequences: ["Projeler bir sonraki derlemede baştan derlenir."], risk: .safe)),
        (["devicesupport"], Insight(what: "Bağlanan cihazlar için Xcode'un hazırladığı sembol dosyaları.",
                                    consequences: ["Cihaz tekrar bağlandığında yeniden hazırlanır (birkaç dakika)."], risk: .safe)),
        (["brave", "chrome", "edge", "firefox", "safari", "arc"], Insight(
            what: "Tarayıcı önbelleği.",
            consequences: ["Siteler ilk açılışta biraz yavaş yüklenir.", "Şifreler, geçmiş ve oturumlar silinmez.", "Tarayıcı açıksa önce kapat."], risk: .safe)),
        (["mumu", "bluestacks", "emulator"], Insight(what: "Android emülatörü verileri: sanal disk, kurulu oyunlar ve kayıtlar.",
                                                     consequences: ["Emülatördeki oyun kayıtları ve kurulu uygulamalar silinir."], risk: .low)),
        (["node_modules"], Insight(what: "Projenin npm bağımlılıkları.",
                                   consequences: ["Projeyi çalıştırmadan önce `npm install` gerekir."], risk: .safe)),
        ([".venv", "/venv"], Insight(what: "Python sanal ortamı.",
                                     consequences: ["Projeyi çalıştırmadan önce ortamı yeniden kurman gerekir (`pip install -r requirements.txt`)."], risk: .low)),
    ]
}
