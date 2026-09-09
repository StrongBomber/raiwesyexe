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
  `/Library/...` dizgileri geçiyor (bkz. ANALIZ.md §8). Rootless
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
