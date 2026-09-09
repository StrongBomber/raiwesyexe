# raiwesyexe — iGameGod Paketleme + Geliştirme Projesi

![Derle ve Test Et](https://github.com/StrongBomber/raiwesyexe/actions/workflows/build.yml/badge.svg)

Upstream iGameGod 0.8.9.2 `.deb`'ini açan, **yeni özelliklerle** yeniden
derleyen ve doğrulayan açık geliştirme iskeleti. Kapalı kaynak binary'lere
dokunulmaz; tüm yenilikler kurulum scriptlerinde, paketleme araçlarında ve
companion tweak'tedir. Her push/PR GitHub Actions'ta otomatik derlenir ve
test edilir.

## Hızlı başlangıç

```bash
make all        # aç -> derle (rootful+rootless) -> doğrula -> test et
ls build/*.deb
```

| Çıktı | Açıklama |
|---|---|
| `build/com.gamegod.igg_<ver>_iphoneos-arm.deb` | rootful varyant |
| `build/com.gamegod.igg_<ver>_iphoneos-arm64.deb` | rootless (`/var/jb`) varyant |

## Neler eklendi?

- 🗄️ Zaman damgalı kalıcı yedekler (`backups/preinst-<tarih>/`, son 5 tutulur)
- 📝 Kurulum günlüğü (`install.log`)
- 📦 Rootless (`/var/jb`) varyantı + otomatik ortam tespiti
- 🛡️ Sağlamlaştırılmış `preinst/postinst/prerm/postrm` (korumalı çağrılar, purge temizliği)
- 🧹 StartApp reklam engelleme (companion tweak: görünüm + sunum + ağ katmanı)
- ✅ SHA256 manifest doğrulama (`make verify`) + mock-kök testleri (`make test`)
- 🗞️ Sürüm otomasyonu (`bump-version.sh`) + APT repo üretici (`make repo`)
- 🧩 Theos/Logos companion tweak şablonu (`tweak/`)
- 🤖 CI: her push'ta otomatik derleme + test, `v*` tag'inde Release

Detay: [`docs/OZELLIKLER.md`](docs/OZELLIKLER.md) · Analiz raporu:
[`docs/ANALIZ.md`](docs/ANALIZ.md) · Kılavuz: [`docs/GELISTIRME.md`](docs/GELISTIRME.md)

## Proje yapısı

```
.github/workflows/   CI: otomatik derleme + release
upstream/            orijinal .deb (değiştirilmez)
packaging/control/   control + yeni kurulum scriptleri
scripts/             extract / package / verify / bump-version / make-repo
tests/               mock-kök paketleme testleri (cihaz gerekmez)
tweak/               companion tweak: örnek hooklar + reklam engelleme (Theos)
docs/                analiz + özellikler + geliştirme kılavuzu
build/               üretilenler (git'e girmez)
```

## Komutlar

```bash
make extract            # .deb'i build/extract altına aç
make package            # rootful .deb'i yeniden derle
make package-rootless   # rootless .deb'i derle
make verify             # upstream ile birebir karşılaştır
make test               # kurulum döngüsü testleri
make repo               # Cydia/Sileo APT deposu üret
```

## Yasal not

`upstream/` altındaki iGameGod binary'si ilgili sahibine aittir ve bu repo
tarafından değiştirilmeden yeniden paketlenir. Bu repodaki özgün içerik
(scriptler, testler, dokümantasyon, tweak şablonu) eğitim/geliştirme
amaçlıdır. Rootless varyantı ve tweak cihazda test edilmeden dağıtılmamalıdır.
