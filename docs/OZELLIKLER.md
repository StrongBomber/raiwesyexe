# Eklenen Özellikler

Upstream 0.8.9.2'ye göre bu repo (`0.8.9.2-1`) neleri değiştirir/ekler.

## F1. Zaman damgalı kalıcı yedekler (preinst/postinst)

- Orijinal: filtreler `/tmp`'ye tek slot kopyalanırdı (reboot'ta kaybolur,
  üst üste kurulumda ezilir).
- Yeni: her kurulumda
  `/var/mobile/Library/iGameGod/backups/preinst-<YYYYmmdd-HHMMSS>/`
  altına `iGameGodLoader.plist`, `bfdecrypttweak.plist`, `iGSpoof.plist`
  yedeklenir; son **5** yedek tutulur, eskiler budanır.
- `postinst` **en son** yedekten geri yükler; yedek yoksa temiz kurulum
  kabul edip sessizce geçer.

## F2. Kurulum günlüğü

- Tüm adımlar `/var/mobile/Library/iGameGod/install.log`'a yazılır.
- Örnek:
  ```
  [preinst 20260909-184500] yedeklendi: bfdecrypttweak.plist
  [postinst 20260909-184502] geri yüklendi: .../bfdecrypttweak.plist
  ```
- `purge` ile günlük + yedekler silinir; kullanıcı filtreleri korunur.

## F3. Rootless (/var/jb) desteği

- `make package-rootless` → `com.gamegod.igg_<ver>_iphoneos-arm64.deb`:
  `Applications/`, `Library/`, `usr/` → `var/jb/...` altına taşınır,
  `Architecture: iphoneos-arm64` yazılır, loader symlink hedefi
  `../../../../mobile/Library/iGameGod/substrate.plist` olarak düzeltilir.
- Kurulum scriptleri `/var/jb/Library/MobileSubstrate` varsa rootless
  öneki otomatik kullanır (`IGG_PREFIX` ile ezilebilir).
- ⚠️ **Bilinen sınırlama / test notu:** loader binary'si içinde mutlak
  `/Library/...` yolları geçiyor (bkz. ANALIZ.md §8). Rootless
  jailbreak'lerde substrate yolları ElleKit tarafından yönetilir; bu varyant
  cihazda denenmeden "çalışır" kabul edilmemelidir. Test: kur → iGameGod'u
  aç → uygulama seç → hedef uygulamada overlay'in belirdiğini doğrula.

## F4. Sağlamlaştırılmış kurulum scriptleri

- `killall`/`uicache` yoksa kurulum patlamaz (korumalı çağrı + günlük notu).
- `cmnd` setuid adımı dosya yoksa hata yerine uyarı yazar.
- `prerm` artık boş değil: kaldırma/yükseltme öncesi `iGameGod` işlemini
  zarifçe durdurur (asılı overlay'i önler).
- `set -u` + her kritik adımda günlük; scriptler `bash -n` ile denetlenir.

## F5. Test edilebilirlik (mock-kök)

- Scriptler `IGG_ROOT` önekiyle **Linux/macOS'ta** test edilebilir:
  `tests/test-packaging.sh` rootful + rootless tam kurulum döngüsünü
  (yedekle → yükselt → geri yükle → kaldır → purge) sahte kökte koşar.
- `make test` ile çalışır; cihaz gerekmez.

## F6. Bütünlük doğrulama

- `scripts/verify.sh`: derlenen deb'lerin `data` içeriğini upstream ile
  **SHA256 manifest** düzeyinde karşılaştırır (rootful birebir aynı olmalı),
  control alanlarını, dosya kiplerini (control 644, scriptler 755),
  symlink hedeflerini ve script sözdizimini denetler.

## F7. Sürüm + repo otomasyonu

- `VERSION` tek doğruluk kaynağı; `scripts/bump-version.sh` sürümü
  `control` + `CHANGELOG.md` ile eşzamanlı yükseltir.
- `scripts/make-repo.sh` Sileo/Zebra/Cydia uyumlu APT deposu üretir:
  `Packages[.gz|.bz2|.xz]`, `Release`, `index.html` (derin bağlantılarla).

## F8. Companion tweak şablonu (`tweak/`)

- Kapalı kaynak binary'ye dokunmadan özellik ekleme deseni: Theos/Logos
  ile `com.gamegod.igg` içine enjekte olan örnek tweak.
- 3 güvenli örnek hook (`Tweak.x`): overlay gösterim günlüğü, dokunuş
  sayacı, yüzen buton kancası + `Enabled` kapatma anahtarı.
- Derleme macOS + Theos gerektirir (bkz. `tweak/README.md`).

## F9. Reklam engelleme (companion tweak, v0.3.0)

- Bulgu: framework'e StartApp (start.io) SDK statik bağlı — banner,
  interstitial ve splash reklamlar (`docs/ANALIZ.md` §11). Araç
  açılışlarındaki (bellek tarayıcı, disassembler...) interstitial'lar
  ayrı pencerede de sunulabildiğinden pencere katmanı eklendi.
- Yöntem: binary'ye yama YOK; tweak 5 katman uygular:
  1. reklam görünümlerini pencereye eklenirken gizleme + kaldırma,
  2. interstitial/splash `present` sunumlarını atlama (completion çağırılır),
  3. reklam pencerelerini (`UIWindow` + kök VC adı) gizli tutma,
  4. StartApp/reklam sunucularına giden ağ isteklerini "çevrimdışı"
     hatasıyla düşürme,
  5. `WKWebView` reklam istekleri/HTML'lerini düşürme.
- Güvenlik: adı `GameGod` içeren sınıflar asla engellenmez; 37 anahtar
  kelimenin hiçbiri iGameGod'un 138 sınıfı ve yaygın UIKit sınıflarıyla
  çakışmaz (denetimden geçti); her engelleme günlüğe yazılır; bastırma
  adımları `@try/@catch` ile sarılıdır (tweak kaynaklı crash olmaz).
- Tercihler (`com.example.iggcompanion.plist`): `Enabled`, `BlockAds`
  (katman 1+2+2b), `BlockAdNetwork` (katman 3+3b), `LogAdClasses`
  (tümü varsayılan açık).
- Oyun içindeki overlay reklamları için filtre, oyun bundle kimlikleriyle
  genişletilebilir (bkz. `tweak/README.md`).
- ⚠️ Cihazda test edilmedi: kurulum sonrası günlükleri izleyin; crash
  durumunda katmanları tek tek kapatıp daraltın (`tweak/README.md`
  "Crash olursa"); CI yalnızca derlenebilirliği kanıtlar.
- Kapsam dışı: attribution/ölçümleme SDK'ları (görünür reklam yok) ve
  delege-tabanlı ağ istekleri.

## F10. Otomatik derleme (CI)

- `.github/workflows/build.yml`: her push/PR'de Ubuntu'da `make all` +
  `make repo` koşar; `.deb`'ler ve APT deposu artifact olarak yüklenir.
- macOS işi Theos ile companion tweak'i derler (rootful + rootless).
- `v*` tag'lerinde 4 `.deb` otomatik GitHub Release'e eklenir.

## F11. Tüm-bir-arada deb (companion gömülü)

- `scripts/bundle-companion.sh`: CI'da derlenen companion `.deb`'indeki
  dylib+plist'i ana pakete gömer; tek kurulumla reklamsız deneyim.
- Çıktı: `com.gamegod.igg_<ver>+companion<tweakver>_<arch>.deb`
  (örn. `0.8.9.2-1+companion0.3.0`), rootful + rootless varyantları.
- `verify.sh` bundled paketleri özel denetler: upstream içeriği birebir
  + yalnızca 2 bilinen dosya (Mach-O dylib, geçerli plist).
- CI `birlestir` işi otomatik üretir (`igg-debs-bundled` artifact'i);
  `make bundle` ile yerelde de çalışır (tweak `.deb`'leri `build/dl/` altında).
- APT deposuna girerse sürümü yüksek olduğundan yükseltme olarak sunulur.
