// IGGCompanion — iGameGod için companion tweak (Theos/Logos).
// v0.3.0: örnek hook'lar + StartApp reklam engelleme (5 katman).
//
// REKLAM ENGELLEME TASARIMI
// Pakette StartApp (start.io) SDK statik bağlı bulundu (bkz. docs/ANALIZ.md
// §11): banner + interstitial + splash. Araç açılışlarında (bellek tarayıcı,
// disassembler vb.) gösterilen interstitial'lar ayrı bir UIWindow içinde de
// sunulabildiği için pencere katmanı da kapsanır. Binary'ye DOKUNULMAZ;
// bunun yerine 5 savunma katmanı uygulanır:
//   Katman 1: reklam görünümleri pencereye eklenirken gizle + kaldır.
//   Katman 2: interstitial/splash 'present' edilmek istendiğinde sunumu atla.
//   Katman 2b: reklam pencereleri (UIWindow) anahtar yapılmak/gösterilmek
//             istendiğinde gizli tut.
//   Katman 3: StartApp/reklam sunucularına giden ağ isteklerini düşür.
//   Katman 3b: WKWebView içindeki reklam istekleri/HTML'lerini düşür.
// Güvenlik: sınıf adı "GameGod" içerenler ASLA engellenmez; tüm katmanlar
// tercihlerden kapatılabilir; her engelleme günlüğe yazılır; bastırma
// adımları @try/@catch ile sarılıdır (tweak'in kendisi crash'e yol açmaz).
// NOT: bu kod yazarın cihazında test edilmedi; önce günlükleri izleyin
// (tweak/README.md "Test etme" ve "Crash olursa").
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

@interface WKWebView : UIView
- (id)loadRequest:(NSURLRequest *)request;
- (id)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL;
@end

// --- Tercihler (/var/mobile/Library/Preferences/com.example.iggcompanion.plist) ---
//   Enabled        (varsayılan YES): ana anahtar, NO ise her şey susar.
//   BlockAds       (varsayılan YES): Katman 1+2+2b (görünüm + sunum + pencere).
//   BlockAdNetwork (varsayılan YES): Katman 3+3b (ağ + webview engelleme).
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

// Pencere + kök view controller zincirine bakarak reklam penceresi tespiti.
static BOOL IGGWindowIsAdLike(UIWindow *window) {
    if (window == nil) return NO;
    if (IGGClassIsAdLike([window class])) return YES;
    UIViewController *root = [window rootViewController];
    if (root != nil && IGGClassIsAdLike([root class])) return YES;
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

// --- Reklam ağı sunucuları (Katman 3/3b) ---
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

static BOOL IGGHTMLIsAd(NSString *html) {
    if (html == nil || html.length == 0 || html.length > 2000000) return NO;
    NSString *low = [html lowercaseString];
    return [low containsString:@"startapp"] ||
           [low containsString:@"doubleclick"] ||
           [low containsString:@"googlesyndication"];
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
    @try {
        self.hidden = YES;
        self.frame = CGRectZero;
        [self removeFromSuperview];
    } @catch (NSException *exception) {
        IGGLog(@"gorunum kaldirilamadi: %@", exception);
    }
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
        if (completion) {
            @try {
                completion();
            } @catch (NSException *exception) {
                IGGLog(@"sunum completion hatasi: %@", exception);
            }
        }
        return;
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!IGGEnabled() || !IGGBlockAds()) return;
    if (!IGGClassIsAdLike([self class])) return;
    IGGNoteBlocked(@"acik-reklam-vc", self);
    @try {
        [self dismissViewControllerAnimated:NO completion:nil];
    } @catch (NSException *exception) {
        IGGLog(@"kapatma hatasi: %@", exception);
    }
}

%end

// Katman 2b: reklam pencereleri anahtar yapılmak/gösterilmek istendiğinde
// gizli tut. Araç açılışlarındaki interstitial'ların tipik sunum yoludur.
// (GameGodWindow dahil iGameGod pencereleri guard sayesinde etkilenmez.)
%hook UIWindow

- (void)makeKeyAndVisible {
    if (IGGEnabled() && IGGBlockAds() && IGGWindowIsAdLike(self)) {
        IGGNoteBlocked(@"pencere", self);
        self.hidden = YES;
        return;
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && IGGEnabled() && IGGBlockAds() && IGGWindowIsAdLike(self)) {
        IGGNoteBlocked(@"pencere-goster", self);
        %orig(YES);
        return;
    }
    %orig;
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
            @try {
                completionHandler(nil, nil, err);
            } @catch (NSException *exception) {
                IGGLog(@"ag completion hatasi: %@", exception);
            }
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
            @try {
                completionHandler(nil, nil, err);
            } @catch (NSException *exception) {
                IGGLog(@"ag completion hatasi: %@", exception);
            }
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
            @try {
                completionHandler(nil, nil, err);
            } @catch (NSException *exception) {
                IGGLog(@"ag completion hatasi: %@", exception);
            }
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
            @try {
                completionHandler(nil, nil, err);
            } @catch (NSException *exception) {
                IGGLog(@"ag completion hatasi: %@", exception);
            }
        }
        return nil;
    }
    return %orig;
}

%end

// Katman 3b: WKWebView reklam istekleri/HTML'lerini düşür.
// (NSURLSession hook'ları WKWebView'in kendi ağ yığınını kapsamaz.)
// WebKit bağlı değilse bu hook sessizce etkisizdir (Logos uyarı verir).
%hook WKWebView

- (id)loadRequest:(NSURLRequest *)request {
    if (IGGEnabled() && IGGBlockAdNet() && IGGRequestIsAd(request)) {
        IGGNoteBlocked(@"webview-istek", [request URL]);
        return nil;
    }
    return %orig;
}

- (id)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL {
    if (IGGEnabled() && IGGBlockAdNet() &&
        (IGGURLIsAdServer(baseURL) || IGGHTMLIsAd(string))) {
        IGGNoteBlocked(@"webview-html", baseURL);
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
