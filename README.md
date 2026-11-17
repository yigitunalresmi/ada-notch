# Ada

MacBook çentiğinde yaşayan, Liquid Glass görünümlü bir yardımcı ve Claude tabanlı asistan.
*A notch companion for MacBook with a Liquid Glass look and a Claude-powered assistant. Turkish and English interface — [English summary below](#english).*

Fareyle çentiğin üstüne gelince açılır; müzik, takvim, hava durumu, araçlar ve Mac'inizi sizin yerinize yöneten bir asistan sunar.

## Özellikler

**Ana sekme**
- Spotify ve Apple Music: kapak, ilerleme çubuğu, oynatma kontrolleri, karışık çalma, zamanlı şarkı sözleri
- Takvim ve anımsatıcılar; görüntülü toplantılar için "Katıl" düğmesi
- Konuma göre hava durumu; tıklayınca saatlik tahmin
- Piyasa takibi: seçtiğiniz kripto fiyatları (isteğe bağlı)

**Kapalı çentikte canlı göstergeler**
- Çalan parça, zamanlayıcının kalan süresi, bir saat içindeki toplantıya geri sayım
- Ses ve parlaklık tuşlarında macOS göstergesi yerine çentik göstergesi
- XDR ekranlarda %100'ün üstünde ekstra (HDR) parlaklık
- Şarja takma/çıkarma (adaptör gücüyle) ve Bluetooth cihazı bağlanma bildirimleri; kulaklık pil düzeyi
- Bir uygulama kamerayı ya da mikrofonu kullanırken nokta göstergesi
- İnternet kesildi / geri geldi / ağ değişti bildirimleri, Caps Lock göstergesi
- İndirilenler klasöründeki süren indirmeler (isteğe bağlı)

**Gelişmiş (varsayılan kapalı, ek izin ister)**
- Odak modu göstergesi ve gelen bildirimleri çentikte gösterme — Tam Disk Erişimi ister
- Gerçek ses görselleştirici — sistem sesini dinleme izni ister; ses kaydedilmez
- Kilit ekranında görünme — deneysel

**Araçlar**
- Zamanlayıcı ve Pomodoro, pano geçmişi, hızlı not, işlemci/bellek/ağ
- Hızlı işlemler: görünüm, uyanık tut, ekran alıntısı, sessiz, renk seçici, ekranı uyut, ses çıkışı seçimi
- Dosya rafı (sürükle-bırak, AirDrop; isteğe bağlı olarak yeni ekran görüntüleri kendiliğinden eklenir), uygulama başlatıcı, ayna

**Asistan (Claude)**
- Yazılı sohbet, bas-konuş dikte ve eller serbest sesli sohbet modu; `⌥ Boşluk` kısayolu
- Yapabildikleri: etkinlik ve anımsatıcı ekleme, müzik, ses, parlaklık, karanlık mod, Wi‑Fi, ses çıkışı,
  uygulama açma/kapama, pencere yerleştirme, seçili metni okuma, dosya arama, zamanlayıcı ve Pomodoro,
  pano, not, Kestirmeler, web araması, Ada'nın kendi ayarları
- Kalıcı hafıza ve özel talimatlar
- `⌥⇧ Boşluk`: herhangi bir uygulamada seçili metni asistana gönderir (özetle, çevir, yazımı düzelt, açıkla, yanıt yaz)
- İsteğe bağlı: ekrana bakma ve AppleScript çalıştırma (her betik için onay ister)

**Görünüm ve ekran**
- Animasyonlar: sekme geçişleri, kayan sekme seçimi, düğme tepkileri, asistan yanıtlarında yazı efekti,
  düşünürken kenar ışıltısı, zamanlayıcı bitince konfeti (Ayarlar'dan azaltılabilir)
- Beş tema: Aurora (hareketli renk bulutları), Neon (dönen ışıklı kenar), Gradyan, Cam, Siyah
- Tema renkleri, hazır renk paletleri, cam saydamlığı, boyut, köşe yuvarlaklığı, vurgu rengi
- Ekran iyileştirme: renk sıcaklığı, kontrast ve en düşük parlaklığın altına inen ek karartma

**Ayarlar**
- Her modül tek tek açılıp kapatılabilir
- Türkçe ve İngilizce arayüz (Ayarlar › Genel › Dil)

## Gereksinimler

- macOS 14 veya üzeri (Liquid Glass görünümü macOS 26 ve üzerinde; eski sürümlerde bulanık cam kullanılır)
- Apple Silicon ya da Intel Mac
- Yalnızca kaynaktan derlemek için: Xcode ya da Xcode Komut Satırı Araçları (`xcode-select --install`)
- Asistan için bir [Anthropic API anahtarı](https://console.anthropic.com/) (asistan dışındaki her şey anahtarsız çalışır)

Çentiksiz Mac'lerde ve harici ekranlarda ekranın üst ortasında küçük bir hap olarak görünür.

## Kurulum

### 1. Sürükle-bırak (en kolay)

1. [Son sürümden](https://github.com/yigitunalresmi/ada-notch/releases/latest) **Ada.dmg** dosyasını indirin.
2. Açın ve **Ada**'yı **Applications** klasörüne sürükleyin.
3. Uygulamalar'dan Ada'yı açın.

Ada henüz Apple tarafından onaylı (notarized) değil. İlk açılışta macOS "geliştiricisi doğrulanamadı" derse:
**Sistem Ayarları › Gizlilik ve Güvenlik** bölümünün altındaki **"Yine de Aç"** düğmesine basın. Bu yalnızca ilk
açılışta gerekir.

### 2. Tek komut

Terminal'e yapıştırın; son sürümü indirir, Uygulamalar'a kurar ve açar (macOS uyarısı çıkmaz):

```bash
curl -fsSL https://raw.githubusercontent.com/yigitunalresmi/ada-notch/main/install.sh | bash
```

### 3. Kaynaktan derleme

```bash
git clone https://github.com/yigitunalresmi/ada-notch.git
cd ada-notch
./build.sh run
```

Betik uygulamayı derler, `build/Ada.app` paketini oluşturur, imzalar ve başlatır. Anahtar Zinciri'nizde bir
"Apple Development" sertifikası varsa onunla, yoksa yerel (ad-hoc) imzayla imzalar.

İlk açılışta ayarlar penceresi açılır. Sonrasında menü çubuğundaki ✦ simgesinden ya da açık çentiğin
sağ üstündeki dişliden ulaşabilirsiniz.

## Güncelleme

Ada yeni sürümleri kendisi denetler (açılışta ve altı saatte bir) ve çentikte bildirir. Ayarlar › Güncellemeler'deki
"Şimdi güncelle" düğmesi:

- **Hazır sürümde** (DMG ya da tek komutla kurulum): yeni sürümü GitHub'dan indirir, imzasını doğrular, eskisinin
  yerine koyar ve Ada'yı yeniden başlatır.
- **Kaynaktan derlenmiş kopyada:** depoyu çeker, Mac'inizde yeniden derler ve yeniden başlatır. Derlediğiniz
  klasörü silmeyin.

Otomatik kurulum isteğe bağlıdır ve kapalı gelir.

Tüm sürümler ve değişiklik notları: [Releases](https://github.com/yigitunalresmi/ada-notch/releases).

Hazır sürümler yerel (ad-hoc) imzalıdır. Bu yüzden macOS, her güncellemeden sonra Erişilebilirlik gibi bazı izinleri
yeniden isteyebilir.

## İzinler

Ada yalnızca açtığınız modüllerin ihtiyaç duyduğu izinleri ister:

| İzin | Ne için |
|---|---|
| Erişilebilirlik | Ses/parlaklık tuşlarını yakalama, pencere yerleştirme, seçili metni okuma |
| Otomasyon (Spotify, Music, System Events) | Müzik kontrolü, karanlık mod |
| Takvim, Anımsatıcılar | Ana sekme ve asistan |
| Konum | Hava durumu |
| Bluetooth | Bağlanma bildirimleri |
| Kamera | Ayna |
| Mikrofon, Konuşma Tanıma | Sesli komut ve sesli sohbet |
| İndirilenler klasörü | İndirme takibi (varsayılan kapalı) |
| Tam Disk Erişimi | Odak modu ve bildirimler (varsayılan kapalı) |
| Sistem Sesi Kaydı | Gerçek ses görselleştirici (varsayılan kapalı) |
| Ekran Kaydı | Ekran alıntısı ve (açarsanız) asistanın ekrana bakması |

## Gizlilik

Ada'nın kendi sunucusu, hesabı ya da telemetrisi yoktur. Dışarıya yalnızca şunlar gider:

- **api.anthropic.com** — asistanla konuşmalarınız, kullandığı araçların sonuçları ve kayıtlı hafıza.
  API anahtarınız yalnızca Mac'inizin Anahtar Zinciri'nde saklanır.
- **api.open-meteo.com** — hava durumu için yaklaşık (1 km'ye yuvarlanmış) konumunuz.
- **lrclib.net** — şarkı sözleri için çalan parçanın ve sanatçının adı.
- **Spotify CDN** — çalan parçanın kapak görseli.
- **api.binance.com** — yalnızca Piyasa takibi açıksa, seçtiğiniz sembollerin fiyatı (kişisel veri gönderilmez).

Hava durumu, şarkı sözleri ve asistan Ayarlar › Modüller'den kapatılabilir.

## Bilinen sınırlar

- Ekran iyileştirme ve ekstra parlaklık ekranın gama tablosunu değiştirir; Night Shift / True Tone ile birlikte
  kullanıldığında renk tonu beklenenden farklı olabilir. Ada kapanınca ekran normale döner.
- Parlaklık okuma/ayarlama ve ekstra parlaklık, Apple'ın belgelenmemiş `DisplayServices` çerçevesini ve
  ekranın gama tablosunu kullanır; bir macOS güncellemesiyle bozulabilir. Ekstra parlaklık pili daha hızlı
  tüketir ve Night Shift / True Tone ile birlikte renk tonunu geçici olarak sabitleyebilir.
- Ses göstergesi, Erişilebilirlik izni verilmeden macOS'in kendi göstergesini gizleyemez.
- Müzik bilgisi AppleScript ile okunur; yalnızca Spotify ve Apple Music desteklenir.
- "Gelişmiş" modüller macOS'in belgelenmemiş dosyalarına ve arayüzlerine dayanır: Odak modu ve bildirimler
  sistemin kendi veritabanlarını okur, kilit ekranı özel bir SkyLight arayüzü kullanır. Bir macOS güncellemesiyle
  çalışmayı bırakabilirler. Zamanlanmış (otomatik açılan) Odak modları algılanmayabilir.
- Yakındaki cihazlarla paylaşım yoktur.

## Geliştirme

Swift Package Manager ile yazılmış tek hedefli bir AppKit + SwiftUI uygulamasıdır; dış bağımlılığı yoktur.

```bash
./build.sh            # yalnızca derle ve paketle
./build.sh run        # derle, paketle, çalışan kopyayı kapatıp yeniden başlat
./release.sh          # dağıtım için dist/Ada.dmg ve dist/Ada.zip üret (Apple Silicon + Intel)
./release.sh publish  # paketleri üret ve GitHub Releases'te yayımla
```

`release.sh`, Anahtar Zinciri'nde bir "Developer ID Application" sertifikası ve `ada-notary` adlı bir notarytool
profili bulursa paketi o kimlikle imzalar ve Apple onayına gönderir; bulamazsa yerel imza kullanır.

Uygulamayı `build/Ada.app` üzerinden (çift tıklayarak ya da `open` ile) başlatın. İkiliyi doğrudan
terminalden çalıştırırsanız macOS gizlilik denetimi uygulamayı kapatır.

Kaynak dosyalar `Sources/Ada` altındadır: `NotchWindow.swift` (pencere ve fare takibi), `NotchViews.swift`
(çentik arayüzü ve temalar), `Assistant.swift` ve `AssistantTools.swift` (Claude istemcisi ve araçlar), `MediaKeys.swift`
(tuş yakalama ve ekstra parlaklık), diğerleri modül başına birer dosyadır.

Arayüz metinleri kodda Türkçedir ve `L("…")` ile sarılır; İngilizce karşılıkları
`Resources/en.lproj/Localizable.strings` dosyasındadır. Yeni bir metin eklerken oraya da bir satır ekleyin.

## English

Ada lives in your MacBook's notch. Hover over the notch and it opens into a glass panel with music, calendar,
weather, tools and an assistant that can operate your Mac for you.

- **Home:** Spotify / Apple Music controls with synced lyrics, calendar, reminders, weather
- **Closed notch:** now playing, timer, meeting countdown, volume/brightness indicator, extra HDR brightness on XDR
  displays, charging and Bluetooth alerts (with headphone battery), camera/microphone-in-use dots, network and
  Caps Lock alerts, downloads in progress
- **Tools:** timer and Pomodoro, clipboard history, quick note, system stats, quick actions (appearance, keep
  awake, capture, mute, color picker, sleep display, audio output), file shelf with AirDrop, app launcher, mirror
- **Assistant (Claude):** text, push-to-talk and hands-free voice chat; manages calendar, reminders, music, volume,
  brightness, dark mode, Wi‑Fi, apps, windows, files, timers, Shortcuts and Ada's own settings; persistent memory
- **Advanced (off by default):** Focus mode indicator and notifications in the notch (Full Disk Access), a real
  audio visualizer (system audio permission; nothing is recorded), and showing on the lock screen (experimental).
  These rely on undocumented macOS files and interfaces and may break with a macOS update.
- **Look:** five themes (Aurora, Neon, Gradient, Glass, Black), custom colors, glass clarity, size, display tuning
  (warmth, contrast, extra dimming)

**Requirements:** macOS 14 or later (Liquid Glass on macOS 26+), Apple Silicon or Intel, and an
[Anthropic API key](https://console.anthropic.com/) for the assistant only.

**Install:**

- **Drag and drop:** download **Ada.dmg** from the [latest release](https://github.com/yigitunalresmi/ada-notch/releases/latest),
  open it and drag Ada to Applications. Ada is not notarized yet: if macOS says the developer cannot be verified,
  press **Open Anyway** in System Settings › Privacy & Security (first launch only).
- **One command** (no macOS warning):

  ```bash
  curl -fsSL https://raw.githubusercontent.com/yigitunalresmi/ada-notch/main/install.sh | bash
  ```
- **From source:** `git clone https://github.com/yigitunalresmi/ada-notch.git && cd ada-notch && ./build.sh run`

Ada checks for new versions itself and updates from Settings › Updates. It follows your system language (English
or Turkish); change it in Settings › General › Language.

**Privacy:** no servers, accounts or telemetry of its own. Data leaves your Mac only for the features you use:
assistant conversations to api.anthropic.com (your key stays in the Keychain), an approximate location to
api.open-meteo.com for weather, and track/artist names to lrclib.net for lyrics.

## Lisans

[MIT](LICENSE)
