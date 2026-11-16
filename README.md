# Ada

MacBook çentiğinde yaşayan, Liquid Glass görünümlü bir yardımcı ve Claude tabanlı asistan.
*A notch companion for MacBook with a Liquid Glass look and a Claude-powered assistant. The interface is currently Turkish only.*

Fareyle çentiğin üstüne gelince açılır; müzik, takvim, hava durumu, araçlar ve Mac'inizi sizin yerinize yöneten bir asistan sunar.

## Özellikler

**Ana sekme**
- Spotify ve Apple Music: kapak, ilerleme çubuğu, oynatma kontrolleri, karışık çalma, zamanlı şarkı sözleri
- Takvim ve anımsatıcılar; görüntülü toplantılar için "Katıl" düğmesi
- Konuma göre hava durumu

**Kapalı çentikte canlı göstergeler**
- Çalan parça, zamanlayıcının kalan süresi, bir saat içindeki toplantıya geri sayım
- Ses ve parlaklık tuşlarında macOS göstergesi yerine çentik göstergesi
- XDR ekranlarda %100'ün üstünde ekstra (HDR) parlaklık
- Şarja takma/çıkarma ve Bluetooth cihazı bağlanma bildirimleri

**Araçlar**
- Zamanlayıcı ve Pomodoro, pano geçmişi, hızlı not, işlemci/bellek/ağ
- Hızlı işlemler: görünüm, uyanık tut, ekran alıntısı, sessiz, renk seçici, ekranı uyut, ses çıkışı seçimi
- Dosya rafı (sürükle-bırak, AirDrop), uygulama başlatıcı, ayna

**Asistan (Claude)**
- Yazılı sohbet, bas-konuş dikte ve eller serbest sesli sohbet modu; `⌥ Boşluk` kısayolu
- Yapabildikleri: etkinlik ve anımsatıcı ekleme, müzik, ses, parlaklık, karanlık mod, Wi‑Fi, ses çıkışı,
  uygulama açma/kapama, pencere yerleştirme, seçili metni okuma, dosya arama, zamanlayıcı ve Pomodoro,
  pano, not, Kestirmeler, web araması, Ada'nın kendi ayarları
- Kalıcı hafıza ve özel talimatlar
- İsteğe bağlı: ekrana bakma ve AppleScript çalıştırma (her betik için onay ister)

**Ayarlar**
- Her modül tek tek açılıp kapatılabilir
- Cam saydamlığı, boyut, köşe yuvarlaklığı, vurgu rengi ve davranış ayarları

## Gereksinimler

- macOS 14 veya üzeri (Liquid Glass görünümü macOS 26 ve üzerinde; eski sürümlerde bulanık cam kullanılır)
- Derlemek için Xcode ya da Xcode Komut Satırı Araçları (`xcode-select --install`)
- Asistan için bir [Anthropic API anahtarı](https://console.anthropic.com/) (asistan dışındaki her şey anahtarsız çalışır)

Çentiksiz Mac'lerde ve harici ekranlarda ekranın üst ortasında küçük bir hap olarak görünür.

## Kurulum

```bash
git clone https://github.com/yigitunalresmi/ada-notch.git
cd ada-notch
./build.sh run
```

Betik uygulamayı derler, `build/Ada.app` paketini oluşturur, imzalar ve başlatır. Anahtar Zinciri'nizde bir
"Apple Development" sertifikası varsa onunla, yoksa yerel (ad-hoc) imzayla imzalar. Ad-hoc imzada macOS,
her yeniden derlemeden sonra izinleri yeniden sorabilir.

Hazır derlenmiş, Apple tarafından onaylanmış (notarized) bir sürüm henüz yok; uygulamayı kaynaktan derlemeniz gerekir.

İlk açılışta ayarlar penceresi açılır. Sonrasında menü çubuğundaki ✦ simgesinden ya da açık çentiğin
sağ üstündeki dişliden ulaşabilirsiniz.

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
| Ekran Kaydı | Ekran alıntısı ve (açarsanız) asistanın ekrana bakması |

## Gizlilik

Ada'nın kendi sunucusu, hesabı ya da telemetrisi yoktur. Dışarıya yalnızca şunlar gider:

- **api.anthropic.com** — asistanla konuşmalarınız, kullandığı araçların sonuçları ve kayıtlı hafıza.
  API anahtarınız yalnızca Mac'inizin Anahtar Zinciri'nde saklanır.
- **api.open-meteo.com** — hava durumu için yaklaşık (1 km'ye yuvarlanmış) konumunuz.
- **lrclib.net** — şarkı sözleri için çalan parçanın ve sanatçının adı.
- **Spotify CDN** — çalan parçanın kapak görseli.

Hava durumu, şarkı sözleri ve asistan Ayarlar › Modüller'den kapatılabilir.

## Bilinen sınırlar

- Arayüz yalnızca Türkçe.
- Parlaklık okuma/ayarlama ve ekstra parlaklık, Apple'ın belgelenmemiş `DisplayServices` çerçevesini ve
  ekranın gama tablosunu kullanır; bir macOS güncellemesiyle bozulabilir. Ekstra parlaklık pili daha hızlı
  tüketir ve Night Shift / True Tone ile birlikte renk tonunu geçici olarak sabitleyebilir.
- Ses göstergesi, Erişilebilirlik izni verilmeden macOS'in kendi göstergesini gizleyemez.
- Müzik bilgisi AppleScript ile okunur; yalnızca Spotify ve Apple Music desteklenir.
- Bildirimlerin çentikte gösterilmesi ve yakındaki cihazlarla paylaşım yoktur.

## Geliştirme

Swift Package Manager ile yazılmış tek hedefli bir AppKit + SwiftUI uygulamasıdır; dış bağımlılığı yoktur.

```bash
./build.sh        # yalnızca derle ve paketle
./build.sh run    # derle, paketle, çalışan kopyayı kapatıp yeniden başlat
```

Uygulamayı `build/Ada.app` üzerinden (çift tıklayarak ya da `open` ile) başlatın. İkiliyi doğrudan
terminalden çalıştırırsanız macOS gizlilik denetimi uygulamayı kapatır.

Kaynak dosyalar `Sources/Ada` altındadır: `NotchWindow.swift` (pencere ve fare takibi), `NotchViews.swift`
(çentik arayüzü), `Assistant.swift` ve `AssistantTools.swift` (Claude istemcisi ve araçlar), `MediaKeys.swift`
(tuş yakalama ve ekstra parlaklık), diğerleri modül başına birer dosyadır.

## Lisans

[MIT](LICENSE)
