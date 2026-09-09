# Changelog

Tüm önemli değişiklikler bu dosyada tutulur. Sürüm biçimi: `<upstream>-<revizyon>`
(`0.8.9.2-1` = upstream 0.8.9.2'nin 1. paketlenmiş revizyonu).

## [Unreleased]

### Eklenen
- CI `tweak` işi sağlamlaştırıldı: kırılgan `install-theos` betiği yerine
  `git clone` ile kurulum (yamalı-SDK indirme adımı atlandı); rootful ve
  rootless derlemeler ayrı adımlara bölündü.
- GitHub Actions workflow (`.github/workflows/build.yml`): her push/PR'de
  `make all` + `make repo` + artifact yükleme; macOS + Theos ile companion
  tweak derlemesi (rootful + rootless); `v*` tag'lerinde otomatik Release.
- Companion tweak'e StartApp reklam engelleme (3 katman: görünüm bastırma,
  interstitial/splash sunum engelleme, reklam ağı istek engelleme) —
  `tweak` 0.2.0. Varsayılan açık; `BlockAds`/`BlockAdNetwork`/`LogAdClasses`
  tercihleriyle yönetilir. Binary'ye dokunulmaz.
- `docs/ANALIZ.md` §11-12: StartApp SDK bulguları + derleme ortamı izleri
  (Rust crate'leri, GHA runner yolları).

## [0.8.9.2-1] - 2026-09-09

### Eklenen
- Proje iskeleti: `scripts/` (extract/package/verify/bump-version/make-repo),
  `packaging/control/`, `tests/`, `tweak/`, `docs/`.
- Kurulum scriptlerine zaman damgalı yedekleme:
  `/var/mobile/Library/iGameGod/backups/preinst-<tarih>/` altında saklanır,
  son 5 yedek tutulur, eskiler budanır.
- Kurulum günlüğü: `/var/mobile/Library/iGameGod/install.log`.
- Rootless desteği: `package.sh --rootless` ile `/var/jb` önekli varyant
  (`iphoneos-arm64`) üretimi; kurulum scriptleri `/var/jb`'yi otomatik tespit eder.
- Mock-kök testleri (`tests/test-packaging.sh`): preinst/postinst/prerm/postrm,
  rootful + rootless senaryoları, Linux'ta çalışır.
- Bütünlük doğrulama (`scripts/verify.sh`): dosya listesi + SHA256 manifest
  karşılaştırması, control alanı kontrolleri, symlink ve izin denetimleri.
- Sürüm yönetimi (`scripts/bump-version.sh` + `VERSION` dosyası).
- APT repo üretici (`scripts/make-repo.sh`): Packages/Release/index.html.
- Örnek companion tweak şablonu (`tweak/`): Theos/Logos, gerçek header
  metotlarına dayanan 3 örnek hook + açma/kapama anahtarı.
- Türkçe dokümantasyon: `docs/ANALIZ.md`, `docs/OZELLIKLER.md`,
  `docs/GELISTIRME.md`.

### Değişen
- `preinst`: `/tmp`'ye tek-slot yedek yerine kalıcı, zaman damgalı yedek dizini.
- `postinst`: eksik komutlar (`killall`, `uicache`) artık korumalı çağrılıyor;
  `cmnd` setuid adımı dosya yoksa kurulumu bozmayıp günlüğe yazıyor.
- `prerm`: önceden boştu; şimdi kaldırma/yükseltme öncesi `iGameGod`
  işlemini zarifçe durduruyor.
- `postrm`: `purge` durumunda günlük + yedekleri temizliyor, kullanıcı
  verisini (filtre seçimleri) koruyor.
