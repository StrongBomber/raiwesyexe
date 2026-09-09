# Geliştirme Kılavuzu

## Gereksinimler

| Araç | Neden | Kontrol |
|---|---|---|
| `bash`, `make`, `git` | orkestrasyon | `make help` |
| `dpkg-deb`, `ar`, `tar` | açma/derleme/doğrulama | `scripts/verify.sh` dolaylı kontrol eder |
| `xz` | `data.tar.lzma` üretimi | `xz --version` |
| `python3` | plist çözümleme, sürüm scripti | `python3 --version` |
| macOS + Theos | yalnızca `tweak/` derlemesi için | `echo $THEOS` |

## Hızlı başlangıç

```bash
git clone <repo> && cd raiwesyexe
make all        # extract -> package x2 -> verify -> test
ls build/*.deb  # iki varyant hazır
```

## Make hedefleri

| Hedef | Ne yapar |
|---|---|
| `make extract` | upstream deb'i `build/extract` + `build/control-orig` altına açar |
| `make package` | rootful deb → `build/com.gamegod.igg_<ver>_iphoneos-arm.deb` |
| `make package-rootless` | rootless deb → `build/..._iphoneos-arm64.deb` |
| `make verify` | manifest + control + kip + sözdizimi denetimi |
| `make test` | mock-kök kurulum döngüsü testleri (rootful+rootless) |
| `make repo` | APT deposu → `build/repo` |
| `make clean` | `build/`'i siler |

## Derleme seçenekleri

```bash
./scripts/package.sh --rootless --backend dpkg-deb --compress xz -o /tmp/out
```

- `--backend manual` (varsayılan): upstream ile birebir arşiv biçimi
  (`control.tar.gz` + `data.tar.lzma`, sahip `root:0`). `fakeroot` gerekmez.
- `--backend dpkg-deb`: sistem `dpkg-deb`'i; eski Cydia uyumluluğu için
  `--compress gzip`, modern kurulumlar için `xz`/`zstd` seçilebilir.
  `fakeroot` varsa sahiplik `root:0` yapılır.

## Sürüm çıkarma akışı

```bash
./scripts/bump-version.sh 0.8.9.2-2
# CHANGELOG.md'deki "(değişiklikleri buraya yazın)" satırını doldurun
make all && make repo
```

## APT deposu yayınlama (GitHub Pages örneği)

```bash
make repo
./scripts/make-repo.sh --base-url https://KULLANICI.github.io/REPO
# build/repo içeriğini gh-pages dalına / docs/ klasörüne koyun
```

Cihazda Sileo → Kaynaklar → `https://KULLANICI.github.io/REPO` ekleyin
(`build/repo/index.html` derin bağlantı düğmeleri içerir).

Not: `build/` altında `*+companion*.deb` varsa repoya da girer; sürümleri
yüksek olduğundan paket yöneticisinde yükseltme olarak sunulur.

## CI (GitHub Actions)

`.github/workflows/build.yml` her push ve PR'de çalışır:

| İş | Runner | Ne yapar |
|---|---|---|
| `paketle` | `ubuntu-latest` | `make all` + `make repo`; `igg-debs` ve `apt-repo` artifact'leri yüklenir |
| `tweak` | `macos-latest` | Theos kurar, companion tweak'i derler (rootful + rootless); `igg-tweak` artifact'i yüklenir |
| `birlestir` | `ubuntu-latest` | Tweak'i ana deb'e gömer; `igg-debs-bundled` artifact'i yüklenir |
| `release` | `ubuntu-latest` | Yalnızca `v*` tag'lerinde: 4 `.deb`'i GitHub Release'e ekler |

Release çıkarma:

```bash
git tag v0.8.9.2-1 && git push origin v0.8.9.2-1
# -> Actions 'release' işi otomatik Release oluşturur (--generate-notes ile)
```

Notlar:

- Ubuntu işi ek `apt` kurulumu gerektirmez (araçlar önyüklü gelir).
- macOS işi Theos'u `git clone` ile kurar (`brew install ldid xz` sonrası);
  `install-theos` betiğindeki yamalı-SDK indirmesi CI'da kırılgan olduğu için
  (exit 8) bilerek kullanılmaz. Tweak yalnızca genel UIKit API'leri
  kullandığından Xcode'un SDK'ları yeterlidir.
- Tweak derlemesi CI'da **kanıtlanır** (sözdizimi/mantık hataları push'ta
  yakalanır), ancak davranış testi yine de cihazda yapılmalıdır.

## Tweak geliştirme

1. `make extract` — genel header'lar:
   `build/extract/Library/Frameworks/iGameGod.framework/Headers/`
2. `tweak/Tweak.x` desenini izleyin: minimal `@interface` + `%hook` +
   `%orig` + günlük. Detay: `tweak/README.md`.
3. macOS'ta `cd tweak && make package`.
4. Reklam anahtarı eklerken çakışma denetimini unutmayın
   (`tweak/README.md` "Yeni anahtar ekleme").

## Dizin yapısı

```
.
├── .github/workflows/   # CI: otomatik derleme + release
├── upstream/            # orijinal .deb (değiştirilmez)
├── packaging/control/   # control + preinst/postinst/prerm/postrm (YENİ)
├── scripts/             # extract/package/verify/bump-version/make-repo/bundle-companion + lib.sh
├── tests/               # mock-kök paketleme testleri
├── tweak/               # Theos companion tweak (örnek hooklar + reklam engelleme)
├── docs/                # ANALIZ / OZELLIKLER / GELISTIRME / IPA
├── build/               # üretilenler (git'e girmez)
├── VERSION CHANGELOG.md Makefile README.md
```

## SSS

- **Neden `manual` backend?** Upstream arşiv biçimini (`data.tar.lzma`) ve
  `root:0` sahipliğini `fakeroot`suz birebir üretir; `verify.sh` çıktıyı
  `dpkg-deb` ile açarak geçerliliğini kanıtlar.
- **Rootful data neden birebir aynı?** Yeni özellikler yalnızca kurulum
  scriptlerinde + yeni dosyalarda; upstream binary'lere dokunulmaz.
  `verify.sh` bunu SHA256 ile garanti eder.
- **`tweak/` neden Linux'ta derlenmiyor?** iOS SDK + Theos yalnızca
  macOS'ta (resmi olarak) kurulur. CI'daki macOS işi her push'ta derler.
- **Reklam engelleme nasıl test edilir?** CI derlenebilirliği kanıtlar;
  davranış testi cihazda: `tweak/README.md` "Test etme".
