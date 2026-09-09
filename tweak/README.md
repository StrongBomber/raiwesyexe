# IGGCompanion — Örnek Companion Tweak + Reklam Engelleme

iGameGod'a MobileSubstrate üzerinden davranış ekleyen, Theos/Logos tabanlı
tweak. Binary'ye dokunmaz; yalnızca doğrulanmış genel metotları ve çalışma-anı
sınıf adlarını kullanır (`Tweak.x` içindeki yorumlara bakın).

> NOT: Bu kod yazarın cihazında test edilmedi. Kurduktan sonra önce
> "Test etme" bölümündeki günlükleri izleyin; sorun görürseniz
> `Enabled = NO` ile susturun (aşağıda).

## Gereksinimler (derleme makinesi)

- macOS + Xcode Command Line Tools
- [Theos](https://theos.dev/) (`$THEOS` ortam değişkeni tanımlı olmalı)
- iOS SDK (Xcode ile gelir)

> Not: Bu dizindeki kod Linux'ta **derlenemez** (iOS SDK gerekir).
> `make package` bu repo kökündeki paketleme hedefidir; tweak'i derlemek için
> macOS'ta bu dizine girip `make package` çalıştırın. CI (`macos-latest`)
> her push'ta derleyip `.deb`'leri artifact olarak yükler.

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
3. iGameGod uygulamasını açın; tweak varsayılan olarak yalnızca
   `com.gamegod.igg` içine enjekte olur (`IGGCompanion.plist` filtresi).

Günlükleri izleme (cihazda, `ldid`li bir terminal veya Xcode):

```bash
log show --predicate 'process == "iGameGod"' --last 5m | grep IGGCompanion
```

## Tercihler

`/var/mobile/Library/Preferences/com.example.iggcompanion.plist`:

| Anahtar | Varsayılan | Etki |
|---|---|---|
| `Enabled` | YES | Ana anahtar; NO ise tweak tamamen susar |
| `BlockAds` | YES | Katman 1+2: görünüm + interstitial/splash sunum engelleme |
| `BlockAdNetwork` | YES | Katman 3: reklam ağı isteklerini düşürme |
| `LogAdClasses` | YES | Açılışta reklam sınıfı taramasını günlüğe yazma |

Örnek (reklam engellemeyi kapatıp örnek hook'ları tutma):

```
{ Enabled = YES; BlockAds = NO; BlockAdNetwork = NO; }
```

## Reklam engelleme (nasıl çalışır)

Pakette StartApp (start.io) SDK statik bağlı bulundu (banner +
interstitial + splash; bkz. `../docs/ANALIZ.md` §11). Üç katman:

1. **Görünüm bastırma:** sınıf adı reklam anahtarıyla eşleşen `UIView`,
   pencereye eklenirken gizlenir + sıfırlanır + kaldırılır.
2. **Sunum engelleme:** reklam view controller `present` edilmek
   istenirse sunum atlanır (`completion` çağırılır, kilitlenme olmaz);
   ekrana başka yolla gelmiş reklam VC'leri anında kapatılır.
3. **Ağ engelleme:** StartApp/reklam sunucularına (`startapp*`,
   `start.io`, `doubleclick`, `googlesyndication`) giden istekler
   "çevrimdışı" hatasıyla düşürülür (SDK uçak-modu gibi susar).

Güvenlik tasarımı:

- Sınıf adında `GameGod` geçenler (Swift'te `iGameGod.X`) **asla**
  engellenmez — uygulamanın kendi arayüzü korunur.
- 37 anahtar kelimenin hiçbiri iGameGod'un 138 sınıfı ve yaygın UIKit
  sınıflarıyla çakışmıyor (denetimden geçti).
- Her engelleme günlüğe yazılır (`reklam engellendi (#N): ...`); ilk 25
  tek tek, sonrası her 50'de bir özetlenir.

Sınırlamalar:

- Tweak, reklam SDK sınıflarının **adlarına** dayanır; StartApp SDK'sı
  büyük sürümde sınıf adlarını değiştirirse anahtar listesi
  güncellenmelidir (günlükteki `reklam sinifi adayi` satırları yol gösterir).
- Delege-tabanlı (`completionHandler`'sız) ağ istekleri kapsanmaz.
- Attribution/ölçümleme SDK'ları (örn. Adjust izleri) bilerek
  kapsanmadı: görünür reklam göstermezler.

## Oyunlardaki overlay reklamları

Varsayılan filtre yalnızca iGameGod uygulamasını hedefler. Oyun içinde
açılan overlay'de de reklam görürseniz, kurulu filtreyi genişletin:

```bash
# cihazda: /Library/MobileSubstrate/DynamicLibraries/IGGCompanion.plist
# (rootless: /var/jb/Library/.../IGGCompanion.plist)
# Filter -> Bundles dizisine oyunun bundle kimliğini ekleyin, örn.:
#   com.oyunyapimcisi.oyunadi
killall -9 SpringBoard  # veya respring
```

Dar filtreyle başlayın (tek oyun); günlüğü temiz görürseniz genişletin.

## Yeni anahtar ekleme

1. Cihazdaki günlükte `reklam sinifi adayi:` satırlarından sınıf adını bulun.
2. Kısa ve ayırt edici bir parçayı `Tweak.x` → `kIGGAdKeywords`'e ekleyin.
3. Çakışma denetimini çalıştırın (repo kökünde, `make extract` sonrası):

```bash
H=build/extract/Library/Frameworks/iGameGod.framework/Headers/iGameGod-Swift.h
grep "@interface" "$H" | grep -F "YENI-ANAHTAR" || echo "temiz: çakışma yok"
```

Çıktı boş ("temiz") değilse o anahtarı kullanmayın.

## Test etme

1. Tweak'i kurun, iGameGod'u açın; `IGGCompanion` günlüklerini izleyin:
   `yuklendi (...)` + `reklam sinifi taramasi bitti (...)` görmelisiniz.
2. Reklam çıkan ekranlara gidin; `reklam engellendi (#N)` satırlarını ve
   reklamların görünmediğini doğrulayın.
3. Uygulamanın normal ekranlarında (araçlar, ayarlar) bozulma olmadığını
   kontrol edin. Bozulma varsa ilgili katmanı tercihlerden kapatıp
   günlüğü not edin.

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
