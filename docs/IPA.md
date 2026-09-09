# IPA'ya Enjeksiyon (Sideload) Kılavuzu

Jailbreak'siz bir IPA'nın içine iGameGod gömme rehberi. Bulgulara dayanır,
tahmine değil (bkz. aşağıdaki "Neden bu dosyalar").

## Kısa cevap

IPA'ya **iki şeyi** koyun:

| # | Dosya (paketteki yeri) | IPA'daki hedefi | Ne işe yarar |
|---|---|---|---|
| 1 | `Library/MobileSubstrate/DynamicLibraries/iGameGodLoader.dylib` | `Payload/Uygulama.app/Frameworks/iGameGodLoader.dylib` | **Enjekte edilen loader** — `LC_LOAD_DYLIB` ile ana binary'ye bağlanır |
| 2 | `Library/Frameworks/iGameGod.framework/` (klasörün tamamı) | `Payload/Uygulama.app/Frameworks/iGameGod.framework/` | Motor — loader bunu çalışma anında bulup yükler |

> `Applications/iGameGod.app/SharedFrameworks/libloader.dylib` ile
> `iGameGodLoader.dylib` **bayt-bayt aynı dosyadır** (SHA256 eşleşti).
> Hangisini kopyalarsanız kopyalayın fark etmez.

Dosyaları repo'dan alma: `make extract` sonrası `build/extract/...` altında
yukarıdaki yollarda bulunurlar. (Cihazda kurulu paketten de alınabilir.)

## Neden bu dosyalar? (kanıtlar)

- Loader'ın kimliği `@rpath/libloader.dylib`, framework'ün kimliği
  `@rpath/iGameGod.framework/iGameGod` — ikisi de gömülü kullanıma uygun.
- Loader, framework'e `LC_LOAD_DYLIB` ile **bağlı değil**; onu çalışma
  anında kendi buluyor (`dlopen` tarzı). Loader dizgilerinde geçen yollar:
  `/Library/Frameworks/iGameGod/`, `Frameworks/iGameGod.framework` ve
  `"Loaded embedded iGameGod.framework via signer fallback for ..."` —
  yani uygulama içine gömülü framework **resmen desteklenen** bir yol.
- `iGSpoof.dylib` doğrudan `/Library/Frameworks/CydiaSubstrate.framework`'e
  bağlı → yalnızca jailbreak'te çalışır, IPA'ya uygun değil.

## Enjekte EDİLMEYECEKLER

| Dosya | Neden değil |
|---|---|
| `iGSpoof.dylib` | CydiaSubstrate'ye mutlak yolla bağlı (jailbreak-only) |
| `bfdecrypttweak.dylib` | Substrate tweak'i; IPA şifre çözme için jailbreak'li cihazda kullanılır, hedef IPA'ya gömülmez |
| `usr/local/bin/cmnd` | Setuid root yardımcısı (komut satırı aracı); enjekte edilemez |
| `libkrw.0.dylib`, `libkernrw.0.dylib` | Kernel R/W yardımcıları; hedef uygulamaya değil, iGameGod.app'e ait |
| `bin/flexdecrypt`, `bin/fouldecrypt*` | IPA şifre çözme araçları (jailbreak'li cihazda, hedef IPA'ya gömülmez) |

## Adım adım

Önkoşul: **decrypted (şifresi çözülmüş)** bir IPA. Kendi cihazınızdaki
uygulamayı jailbreak'li tarafta çözün (paketteki `bfdecrypt`/`flexdecrypt`
bunun içindir) ya da zaten decrypted bir kopya kullanın.

```bash
# 0) IPA'yı açın
unzip Oyun.ipa -d ipa && APP=$(echo ipa/Payload/*.app) && BIN=$(basename "$APP" .app)

# 1) Framework + loader'ı gömün
cp -R build/extract/Library/Frameworks/iGameGod.framework "$APP/Frameworks/"
cp build/extract/Library/MobileSubstrate/DynamicLibraries/iGameGodLoader.dylib \
   "$APP/Frameworks/"

# 2) Ana binary'ye yükleme komutu ekleyin (araçlardan biri)
insert_dylib --inplace @executable_path/Frameworks/iGameGodLoader.dylib \
  "$APP/$BIN" --strip-codesig
# alternatifler: optool, ytool

# 3) Kontrol: yeni LC_LOAD_DYLIB görünmeli
otool -L "$APP/$BIN" | grep -i gamegod

# 4) İmzalayın (tüm gömülü binary'ler + ana binary + framework)
codesign -f -s - --deep "$APP"              # ad-hoc (test)
# dağıtım için: kendi sertifikanız + entitlements (get-task-allow önerilir)

# 5) Paketleyip kurun
cd ipa && zip -qr ../Oyun-iGG.ipa Payload && cd ..
# Sideloadly / AltStore / ESign / TrollStore ile kurun
```

`--strip-codesig` (veya `ldid -S` sonrası yeniden imza): ana binary'nin eski
imzası, yeni `LC_LOAD_DYLIB` ile geçersiz kalır; yeniden imzalamak şarttır.

## İmza / entitlement notları

- Overlay uygulamanın **kendi process'inde** çalışır; kendi belleğini okumak
  için özel yetki gerekmez. Yine de `get-task-allow` entitlement'ı önerilir
  (geliştirme profilleri bunu zaten içerir; hata ayıklama ve task erişimini
  rahatlatır).
- Framework klasörünün **tamamını** kopyalayın (binary + `Info.plist` +
  `Assets.car`); yalnızca binary yetmez.
- iOS 17+ sideload kısıtlarında JIT gerektiren bazı bellek özellikleri
  çalışmayabilir; temel arama/düzenleme overlay'i etkilenmez.

## Doğrulama

Uygulamayı açın; overlay düğmesi görünmelidir. Emin olmak için cihaz
günlüğünde loader satırını arayın:

```
Loaded embedded iGameGod.framework via signer fallback for ...
```

Bu satır varsa framework gömülü olarak yüklenmiş demektir.

## Sınırlamalar

- Loader, yapılandırmayı `/var/mobile/Library/iGameGod/config.plist`
  yolunda arar (jailbreak yolu). Sandbox'lı uygulamada bu dosya yoktur;
  loader gömülü-yedek mantığıyla devam eder, ancak bazı seçimler
  (uygulama listesi vb.) sideload'da farklı davranabilir.
- Root gerektiren özellikler (`cmnd` yardımcısı, kernel R/W varyantları)
  jailbreak'sizde çalışmaz.
- Uygulama güncellenince IPA'ya yeniden enjekte etmek gerekir.
- TrollStore ile kurulan uygulamalar ("CoreTrust dışı" imza) aynı adımları
  izler; imza adımı TrollStore'un yardımcısıyla yapılabilir.

## Kullanım notu

Yalnızca sahibi olduğunuz / üzerinde işlem yapma hakkınız bulunan
uygulamalara enjekte edin; decrypted IPA'ları kendi cihazınızdan üretin.
