// IGGCompanion — iGameGod için örnek companion tweak (Theos/Logos şablonu).
//
// Amaç: kapalı kaynak iGameGod binary'sine DOKUNMADAN, MobileSubstrate
// üzerinden yeni davranışlar eklemenin çalışan bir örneği.
//
// Hook'lar, paketin kendi dağıttığı genel header'da (iGameGod-Swift.h)
// doğrulanan metotlara dayanır — bkz. docs/ANALIZ.md "Header API özeti":
//   +[GameGod showGameGod]
//   -[GameGodWindow sendEvent:]
//   -[HoverButtonViewController viewDidAppear:]
//
// Derleme (macOS + Theos):  make package
// Rootless:                 THEOS_PACKAGE_SCHEME=rootless make package

#import <UIKit/UIKit.h>

// --- Minimal ileri bildirimler (header'ın tamamını gömmek yerine) ---
@interface GameGod : NSObject
+ (void)embedGameGod;
+ (void)showGameGod;
@end

@interface GameGodWindow : UIWindow
@end

@interface HoverButtonViewController : UIViewController
@end

// --- Açma/kapama anahtarı ---
// /var/mobile/Library/Preferences/com.example.iggcompanion.plist içinde
// { Enabled = NO } varsa tüm companion davranışları susar (güvenli çıkış).
static NSString * const kIGGPrefsPath =
    @"/var/mobile/Library/Preferences/com.example.iggcompanion.plist";

static BOOL IGGEnabled(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kIGGPrefsPath];
    NSNumber *enabled = prefs[@"Enabled"];
    return enabled ? [enabled boolValue] : YES; // varsayılan: açık
}

static NSUInteger _iggTouchCount = 0;

#define IGGLog(fmt, ...) NSLog(@"[IGGCompanion] " fmt, ##__VA_ARGS__)

// Örnek 1: iGameGod overlay'i her gösterildiğinde günlük kaydı.
// (Kendi özelliğini %orig SONRASINA ekle; %orig ÖNCESİ return etme.)
%hook GameGod

+ (void)showGameGod {
    %orig;
    if (!IGGEnabled()) return;
    IGGLog(@"overlay gösterildi (companion aktif)");
}

%end

// Örnek 2: overlay penceresindeki dokunuşları say; her 50'de bir günlüğe yaz.
// (Durumsuz, düşük maliyetli sayaç deseni.)
%hook GameGodWindow

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (!IGGEnabled()) return;
    if (event.type == UIEventTypeTouches) {
        if (++_iggTouchCount % 50 == 0) {
            IGGLog(@"overlay dokunuş sayacı: %lu", (unsigned long)_iggTouchCount);
        }
    }
}

%end

// Örnek 3: yüzen butonun görünmesi — karşılama/bilgilendirme kancası.
// (Buradan: rozet, sesli bildirim, otomatik araç açma gibi özellikler türetilebilir.)
%hook HoverButtonViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!IGGEnabled()) return;
    IGGLog(@"yüzen buton göründü: %@", NSStringFromClass([self class]));
}

%end

%ctor {
    IGGLog(@"yüklendi (Enabled=%@)", IGGEnabled() ? @"YES" : @"NO");
}
