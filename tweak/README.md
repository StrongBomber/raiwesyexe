# IGGCompanion — Örnek Companion Tweak

iGameGod'a MobileSubstrate üzerinden davranış ekleyen, Theos/Logos tabanlı
**çalışan şablon**. Binary'ye dokunmaz; yalnızca doğrulanmış genel metotları
hook'lar (`Tweak.x` içindeki yorumlara bakın).

## Gereksinimler (derleme makinesi)

- macOS + Xcode Command Line Tools
- [Theos](https://theos.dev/) (`$THEOS` ortam değişkeni tanımlı olmalı)
- iOS SDK (Xcode ile gelir)

> Not: Bu dizindeki kod Linux'ta **derlenemez** (iOS SDK gerekir).
> `make package` bu repo kökündeki paketleme hedefidir; tweak'i derlemek için
> macOS'ta bu dizine girip `make package` çalıştırın.

## Derleme

```bash
cd tweak
make package                    # rootful .deb  -> packages/
THEOS_PACKAGE_SCHEME=rootless make package   # rootless .deb
```

## Cihaza kurma

1. Üretilen `.deb`'i cihaza kopyalayın (`scp`) veya Sileo/Zebra dosya
   paylaşımıyla açın.
2. `dpkg -i com.example.iggcompanion_*.deb` (veya paket yöneticisiyle kurun).
3. iGameGod uygulamasını açın; tweak yalnızca `com.gamegod.igg` içine
   enjekte olur (`IGGCompanion.plist` filtresi).

Günlükleri izleme (cihazda, `ldid`li bir terminal veya Xcode):

```bash
log show --predicate 'process == "iGameGod"' --last 5m | grep IGGCompanion
```

## Kapatma anahtarı

Sorun yaşarsanız tweak'i kaldırmadan susturabilirsiniz:

```bash
# /var/mobile/Library/Preferences/com.example.iggcompanion.plist:
{ Enabled = NO; }
```

## Kendi özelliğinizi ekleme

1. `make extract` sonrası genel header'lar şurada:
   `build/extract/Library/Frameworks/iGameGod.framework/Headers/`
2. İlgilendiğiniz sınıfın `@interface` bloğundaki metodu bulun
   (ör. `SpeedHackToolViewController`, `MemoryEditorToolViewController`).
3. `Tweak.x`'e minimal bir `@interface` ileri bildirimi + `%hook` bloğu ekleyin.
4. Önce `%orig` + `IGGLog` ile başlayın; davranıştan emin olmadan
   orijinal akışı değiştirmeyin.

## Güvenlik notları

- Bilinmeyen metotlara körü körüne hook atmayın; güvenli mod (Safe Mode)
  döngüsüne sokabilirsiniz.
- `%orig`'i atlamak, dönüş değerini değiştirmek gibi güçlü desenleri
  küçük adımlarla ve cihazda test ederek uygulayın.
- Bundle kimliğini (`com.gamegod.igg`) değiştirmeden SpringBoard'a enjekte
  olmayın; bu şablon bilinçli olarak yalnızca iGameGod uygulamasını hedefler.
