# raiwesyexe — iGameGod Paketleme + Geliştirme Projesi

Upstream iGameGod 0.8.9.2 `.deb`'ini açan, **yeni özelliklerle** yeniden
derleyen ve doğrulayan açık geliştirme iskeleti. Kapalı kaynak binary'lere
dokunulmaz; tüm yenilikler kurulum scriptlerinde, paketleme araçlarında ve
örnek bir companion tweak şablonundadır.

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
- ✅ SHA256 manifest doğrulama (`make verify`) + mock-kök testleri (`make test`)
- 🗞️ Sürüm otomasyonu (`bump-version.sh`) + APT repo üretici (`make repo`)
- 🧩 Theos/Logos companion tweak şablonu (`tweak/`)

Detay: [`docs/OZELLIKLER.md`](docs/OZELLIKLER.md) · Analiz raporu:
[`docs/ANALIZ.md`](docs/ANALIZ.md) · Kılavuz: [`docs/GELISTIRME.md`](docs/GELISTIRME.md)

## Proje yapısı

```
upstream/            orijinal .deb (değiştirilmez)
packaging/control/   control + yeni kurulum scriptleri
scripts/             extract / package / verify / bump-version / make-repo
tests/               mock-kök paketleme testleri (cihaz gerekmez)
tweak/               örnek companion tweak (Theos, macOS'ta derlenir)
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
amaçlıdır. Rootless varyantı cihazda test edilmeden dağıtılmamalıdır.
