// IGGCompanion — iGameGod için companion tweak (Theos/Logos).
// v0.2.0: örnek hook'lar + StartApp reklam engelleme.
//
// REKLAM ENGELLEME TASARIMI
// Pakette StartApp (start.io) SDK statik bağlı bulundu (bkz. docs/ANALIZ.md
// §11): banner + interstitial + splash. SDK sınıfları header'da yok; ancak
// çalışma anında ObjC runtime'da adlarıyla görünürler. Bu dosya binary'ye
// DOKUNMAZ; bunun yerine 3 savunma katmanı uygular:
//   Katman 1: reklam görünümleri pencereye eklenirken gizle + kaldır.
//   Katman 2: interstitial/splash 'present' edilmek istendiğinde sunumu atla.
//   Katman 3: StartApp/reklam sunucularına giden ağ isteklerini düşür.
// Güvenlik: sınıf adı "GameGod" içerenler ASLA engellenmez; tüm katmanlar
// tercihlerden kapatılabilir; her engelleme günlüğe yazılır.
// NOT: bu kod yazarın cihazında test edilmedi; önce günlükleri izleyin
// (tweak/README.md "Test etme").
//
// Örnek hook'lar, paketin dağıttığı genel header'da (iGameGod-Swift.h)
// doğrulanan metotlara dayanır:
//   +[GameGod showGameGod]
//   -[GameGodWindow sendEvent:]
//   -[HoverButtonViewController viewDidAppear:]
//
// Derleme (macOS + Theos):  make package
// Rootless:                 THEOS_PACKAGE_SCHEME=rootless make package

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// --- Minimal ileri bildirimler (header'ın tamamını gömmek yerine) ---
@interface GameGod : NSObject
+ (void)embedGameGod;
+ (void)showGameGod;
@end

@interface GameGodWindow : UIWindow
@end

@interface HoverButtonViewController : UIViewController
@end

// --- Tercihler (/var/mobile/Library/Preferences/com.example.iggcompanion.plist) ---
//   Enabled        (varsayılan YES): ana anahtar, NO ise her şey susar.
//   BlockAds       (varsayılan YES): Katman 1+2 (görünüm + sunum engelleme).
//   BlockAdNetwork (varsayılan YES): Katman 3 (reklam ağı istek engelleme).
//   LogAdClasses   (varsayılan YES): açılışta reklam sınıfı taraması günlüğü.
static NSString * const kIGGPrefsPath =
    @"/var/mobile/Library/Preferences/com.example.iggcompanion.plist";

static NSDictionary *IGGPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kIGGPrefsPath];
}

static BOOL IGGPrefBool(NSString *key, BOOL fallback) {
    NSNumber *v = IGGPrefs()[key];
    return v ? [v boolValue] : fallback;
}

static BOOL IGGEnabled(void)    { return IGGPrefBool(@"Enabled", YES); }
static BOOL IGGBlockAds(void)   { return IGGPrefBool(@"BlockAds", YES); }
static BOOL IGGBlockAdNet(void) { return IGGPrefBool(@"BlockAdNetwork", YES); }
static BOOL IGGLogAdCls(void)   { return IGGPrefBool(@"LogAdClasses", YES); }

static NSUInteger _iggTouchCount = 0;
static NSUInteger _iggAdsBlocked = 0;

#define IGGLog(fmt, ...) NSLog(@"[IGGCompanion] " fmt, ##__VA_ARGS__)

// --- Reklam sınıfı anahtarları ---
// DENETİM: bu listedeki HİÇBİR anahtar, iGameGod'un 138 sınıfında ve yaygın
// UIKit sınıflarında geçmiyor (37/37 temiz). Yeni anahtar eklemeden ÖNCE aynı
// denetimi tekrarlayın (komut: tweak/README.md "Yeni anahtar ekleme").
static NSString * const kIGGAdKeywords[] = {
    @"StartApp", @"STA",
    @"BannerAd", @"InterstitialAd", @"SplashAd",
    @"AdMob", @"GADBanner", @"GADInterstitial", @"GADNative", @"GADAppOpen",
    @"STAStartApp", @"STABanner", @"STAInterstitial", @"STASplash",
    @"FBAd", @"FBNative", @"MPAd", @"MPInterstitial",
    @"ALAd", @"ALInterstitial", @"ISInterstitial", @"ISBanner",
    @"UnityAds", @"Vungle", @"AppLovin", @"IronSource",
    @"InMobi", @"Mintegral", @"Pangle", @"Chartboost",
    @"Tapjoy", @"AdColony", @"Fyber", @"Ogury", @"HyprMX", @"Smaato", @"Criteo",
};
static const NSUInteger kIGGAdKeywordCount =
    sizeof(kIGGAdKeywords) / sizeof(kIGGAdKeywords[0]);

// Sınıf + 4 üst sınıflık zincirde reklam izi arar.
// "GameGod" içeren sınıflar (Swift'te "iGameGod.X" biçiminde görünür)
// ASLA reklam sayılmaz — iGameGod'un kendi arayüzü korunur.
static BOOL IGGClassIsAdLike(Class cls) {
    int depth = 0;
    for (Class c = cls; c != nil && depth < 4; c = class_getSuperclass(c), depth++) {
        NSString *name = NSStringFromClass(c);
        if ([name containsString:@"GameGod"]) return NO;
        for (NSUInteger i = 0; i < kIGGAdKeywordCount; i++) {
            if ([name containsString:kIGGAdKeywords[i]]) return YES;
        }
    }
    return NO;
}

static void IGGNoteBlocked(NSString *what, id obj) {
    _iggAdsBlocked++;
    if (_iggAdsBlocked <= 25 || _iggAdsBlocked % 50 == 0) {
        IGGLog(@"reklam engellendi (#%lu): %@ <%@: %p>",
               (unsigned long)_iggAdsBlocked, what, NSStringFromClass([obj class]), obj);
    }
}

// Açılışta yüklü TÜM sınıfları tarar, reklam benzerlerini günlüğe yazar.
// Teşhis amaçlıdır; hiçbir şeyi değiştirmez.
static void IGGEnumerateAdClasses(void) {
    if (!IGGLogAdCls()) return;
    int total = objc_getClassList(NULL, 0);
    if (total <= 0) return;
    Class *list = (Class *)malloc(sizeof(Class) * (size_t)total);
    if (!list) return;
    total = objc_getClassList(list, total);
    NSUInteger found = 0;
    for (int i = 0; i < total && found < 40; i++) {
        if (IGGClassIsAdLike(list[i])) {
            IGGLog(@"reklam sinifi adayi: %@", NSStringFromClass(list[i]));
            found++;
        }
    }
    IGGLog(@"reklam sinifi taramasi bitti (%lu aday, %d sinif tarandi)",
           (unsigned long)found, total);
    free(list);
}

// --- Reklam ağı sunucuları (Katman 3) ---
static BOOL IGGURLIsAdServer(NSURL *url) {
    NSString *host = [[url host] lowercaseString];
    if (host.length == 0) return NO;
    static NSString * const adHosts[] = {
        @"startapp", @"start.io", @"doubleclick", @"googlesyndication",
    };
    for (NSUInteger i = 0; i < sizeof(adHosts) / sizeof(adHosts[0]); i++) {
        if ([host containsString:adHosts[i]]) return YES;
    }
    return NO;
}

static BOOL IGGRequestIsAd(NSURLRequest *request) {
    return request != nil && IGGURLIsAdServer([request URL]);
}

// Örnek 1: iGameGod overlay'i her gösterildiğinde günlük kaydı.
%hook GameGod

+ (void)showGameGod {
    %orig;
    if (!IGGEnabled()) return;
    IGGLog(@"overlay gösterildi (companion aktif)");
}

%end

// Örnek 2: overlay penceresindeki dokunuşları say; her 50'de bir günlüğe yaz.
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
%hook HoverButtonViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!IGGEnabled()) return;
    IGGLog(@"yüzen buton göründü: %@", NSStringFromClass([self class]));
}

%end

// Katman 1: reklam görünümleri pencereye eklenirken gizle + sıfırla + kaldır.
// (Pencereden AYRILMA olayları atlanır; kaldırma kendini tekrar tetiklemez
// çünkü ikinci çağrıda self.window == nil olur.)
%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (!IGGEnabled() || !IGGBlockAds()) return;
    if (self.window == nil) return;
    if (!IGGClassIsAdLike([self class])) return;
    IGGNoteBlocked(@"gorunum", self);
    self.hidden = YES;
    self.frame = CGRectZero;
    [self removeFromSuperview];
}

%end

// Katman 2: interstitial/splash 'present' edilmek istendiğinde sunumu atla
// (completion çağırılır, çağıran taraf kilitlenmez). Başka yolla ekrana
// gelmiş reklam VC'leri görünür görünmez kapatılır.
%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)animated
                   completion:(void (^)(void))completion {
    if (IGGEnabled() && IGGBlockAds() && viewControllerToPresent != nil &&
        IGGClassIsAdLike([viewControllerToPresent class])) {
        IGGNoteBlocked(@"sunum", viewControllerToPresent);
        if (completion) completion();
        return;
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!IGGEnabled() || !IGGBlockAds()) return;
    if (!IGGClassIsAdLike([self class])) return;
    IGGNoteBlocked(@"acik-reklam-vc", self);
    [self dismissViewControllerAnimated:NO completion:nil];
}

%end

// Katman 3: reklam ağı isteklerini "çevrimdışı" hatasıyla düşür.
// (SDK uçak-modu davranışı gösterir: sessizce vazgeçer.)
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable,
                                                         NSURLResponse * _Nullable,
                                                         NSError * _Nullable))completionHandler {
    if (IGGEnabled() && IGGBlockAdNet() && IGGRequestIsAd(request)) {
        IGGNoteBlocked(@"ag-istek", [request URL]);
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:nil];
            completionHandler(nil, nil, err);
        }
        return nil;
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData * _Nullable,
                                                     NSURLResponse * _Nullable,
                                                     NSError * _Nullable))completionHandler {
    if (IGGEnabled() && IGGBlockAdNet() && IGGURLIsAdServer(url)) {
        IGGNoteBlocked(@"ag-istek", url);
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:nil];
            completionHandler(nil, nil, err);
        }
        return nil;
    }
    return %orig;
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL * _Nullable,
                                                                 NSURLResponse * _Nullable,
                                                                 NSError * _Nullable))completionHandler {
    if (IGGEnabled() && IGGBlockAdNet() && IGGRequestIsAd(request)) {
        IGGNoteBlocked(@"ag-indirme", [request URL]);
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:nil];
            completionHandler(nil, nil, err);
        }
        return nil;
    }
    return %orig;
}

- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSURL * _Nullable,
                                                             NSURLResponse * _Nullable,
                                                             NSError * _Nullable))completionHandler {
    if (IGGEnabled() && IGGBlockAdNet() && IGGURLIsAdServer(url)) {
        IGGNoteBlocked(@"ag-indirme", url);
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:nil];
            completionHandler(nil, nil, err);
        }
        return nil;
    }
    return %orig;
}

%end

%ctor {
    IGGLog(@"yuklendi (Enabled=%@ BlockAds=%@ BlockAdNetwork=%@)",
           IGGEnabled() ? @"YES" : @"NO",
           IGGBlockAds() ? @"YES" : @"NO",
           IGGBlockAdNet() ? @"YES" : @"NO");
    if (IGGEnabled()) IGGEnumerateAdClasses();
}
