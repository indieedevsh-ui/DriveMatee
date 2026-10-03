# DriveMate

**AI-powered in-car companion for iOS** · **Asystent AI do jazdy na iOS**

Landscape car-dashboard app with Apple Maps navigation, hands-free Polish voice control, music, and rear-camera clips — designed so you can keep your eyes on the road.

Aplikacja w układzie poziomym (kokpit samochodowy) z nawigacją Apple Maps, sterowaniem głosowym po polsku, muzyką i nagrywaniem klipów z kamery tylnej — tak, by ręce i wzrok zostawały przy kierownicy.

---

## Table of contents · Spis treści

- [English](#english)
- [Polski](#polski)

---

<a id="english"></a>

# English

## What is DriveMate?

DriveMate is an **in-car iOS app** that turns your iPhone into a driver-focused dashboard. Instead of juggling Maps, Music, and a voice assistant as separate apps, DriveMate brings them into **one landscape cockpit** with a dedicated AI assistant — **Drive Mate** — that understands natural Polish (and typed commands) while you drive.

It is built for real driving moments: picking a destination, asking about traffic, finding food nearby, ending a trip, and recording a short rear-camera clip — without deep menu diving.

## Problems it solves

| Problem | How DriveMate helps |
| --- | --- |
| **Phone UI is not built for driving** | Landscape, large controls, liquid-glass cockpit layout meant for glanceable use in the car. |
| **Too many apps while driving** | Navigation, voice AI, music, and clip recording live in one place. |
| **Voice assistants that don’t “do” the car** | Drive Mate can start routes, check traffic, look up street/place context, and offer nearby restaurants — with real MapKit effects, not just chat. |
| **Rigid “destination then start” voice flows** | Say only the destination and Drive Mate asks where you start — *or* say start + destination in one natural sentence. |
| **AI that invents map answers** | When something isn’t supported, Drive Mate says so clearly instead of guessing ETA, places, or routes. |
| **Hands leaving the wheel for small tasks** | Wake-style listening during navigation (**Hey Drive**), optional temporary **Drive** text pill, and voice confirm/cancel for restaurant offers. |
| **Losing context after a detour** | If you divert to a restaurant mid-trip, the interrupted destination can come back as a lime “resume” pill on the idle screen. |
| **End of trip with nowhere to park** | Trip summary can suggest nearby parking after you finish a route. |

## Who is it for?

- Drivers who want a **single car-oriented screen** on iPhone  
- People who prefer **Polish voice commands** while driving  
- Builders / testers interested in **MapKit + on-device Foundation Models** in a real product shape  
- Anyone exploring safer, more focused in-car UX than stock phone home screens

## Core features

### Drive (main screen)
- **Where do you wanna go?** — destination search, recent places, start confirmation  
- **Apple Maps** navigation with traffic-aware routing and turn guidance tiles  
- Animated route reveal and driver-centric map following  
- Speed badge, recenter, end route, trip summary  
- Optional music bar during an active trip  

### Drive Mate (voice & AI)
- Polish speech recognition (ASR)  
- Natural-language understanding (CoreLM / Foundation Models when available) with a **local Polish intent router** as fallback  
- Supported intents: **navigate**, **traffic**, **street info**, **nearby food**  
- Flexible navigation phrasing, for example:
  - *“Rynek Dębnicki”* → asks: start from your location or another place?  
  - *“Start from my location and take me to X”* → starts routing immediately  
- During navigation: continuous **Hey Drive** wake listening + temporary **Drive** button to type a request  
- Restaurant flow: offer popup (Apple Maps snapshot) → confirm/cancel by tap or voice → optional second AI confirm → route  

### Recorder
- Rear-camera oriented clip capture for moments on the road  
- Local clip storage for later review  

### Settings
- Appearance and playback-related preferences (e.g. music volume, auto-mute while the assistant speaks)  

## How a typical trip looks

1. Open **Drive** in landscape.  
2. Pick a destination (search, recent, voice, or interrupted-route pill).  
3. Confirm start (your GPS location or a custom place) — or say both in one voice request.  
4. Follow the map + turn tile; talk to Drive Mate if you need traffic, food, or a change.  
5. End the route → see a short summary and optional parking ideas.  

## Tech stack

| Area | Technology |
| --- | --- |
| UI | SwiftUI, landscape car dashboard, liquid glass styling |
| Maps & routing | MapKit (`MKMapView`, `MKDirections`, `MKLocalSearch`, snapshots) |
| Voice | Speech framework (PL ASR), AVSpeechSynthesizer |
| AI | Apple Foundation Models (structured CoreLM + tools + chat), local PL intent parser |
| Media | AVFoundation (music playback, camera clips) |
| Location | CoreLocation |

## Project structure (high level)

```text
DriveMate/
├── Views/
│   ├── Drive/          # Map, idle setup, guidance, AI chrome, trip end
│   ├── Recorder/       # Clip capture UI
│   └── Settings/       # Preferences
├── Services/           # Navigation, voice, AI, music, camera, parking, food
├── Models/             # Tabs, media models
└── Theme/              # Shared visual language
```

## Requirements

- macOS with **Xcode** (modern iOS SDK; the project targets a current iOS release)  
- **iPhone** recommended for location, speech, and camera (Simulator is limited)  
- Permissions typically needed: **Location**, **Microphone**, **Speech Recognition**, **Camera** (recorder)  
- **Apple Intelligence / Foundation Models** optional — local command routing still works when the model is unavailable  
- Accept the in-app **navigation disclaimer / EULA** before routing  

## Getting started

1. Clone this repository.  
2. Open `DriveMate.xcodeproj` in Xcode.  
3. Select your development team / signing.  
4. Build & run on a physical iPhone when possible.  
5. Grant location and microphone/speech permissions when prompted.  
6. Start on the **Drive** tab and try a destination or *Hey Drive*.  

```bash
git clone https://github.com/<your-account>/DriveMate.git
cd DriveMate
open DriveMate.xcodeproj
```

## Privacy & Apple Maps

- Location, microphone, speech, and camera data are used **on-device** for navigation, voice commands, and recording.  
- Place search, routing, traffic hints, and map imagery come from **Apple Maps / MapKit**.  
- The app includes Map Data / attribution surfaces where Apple’s guidelines require showing map context with Apple Maps content.  
- Do not commit secrets or private API keys; keep personal plist/config out of public forks if needed.

## Status

Active product prototype. Features and AI behavior continue to evolve (voice understanding, in-car flows, and polish).

## Contributing

Issues and pull requests are welcome. Please describe the driving scenario you tested (idle vs navigating, voice vs typed) and the device/OS version.

## License

Add your preferred license here (e.g. MIT) before publishing widely.

---

<a id="polski"></a>

# Polski

## Czym jest DriveMate?

DriveMate to **aplikacja samochodowa na iOS**, która zamienia iPhone’a w kokpit dla kierowcy. Zamiast skakać między Mapami, Muzyką i asystentem głosowym, wszystko jest w **jednym poziomym dashboardzie** z dedykowanym AI — **Drive Mate** — który rozumie naturalny polski (oraz komendy wpisane) podczas jazdy.

Aplikacja jest zaprojektowana pod realne sytuacje: wybór celu, pytanie o korki, znalezienie jedzenia w pobliżu, zakończenie trasy czy krótki klip z kamery tylnej — bez grzebania w menu.

## Jakie problemy rozwiązuje?

| Problem | Jak pomaga DriveMate |
| --- | --- |
| **Interfejs telefonu nie jest od jazdy** | Układ poziomy, duże elementy, „liquid glass” kokpit — szybki rzut oka, mniej kombinowania. |
| **Za dużo aplikacji za kierownicą** | Nawigacja, AI głosowe, muzyka i nagrywanie klipów w jednym miejscu. |
| **Asystent, który tylko „gada”, a nie prowadzi** | Drive Mate realnie startuje trasy, sprawdza ruch, daje kontekst ulicy/miejsca i proponuje restauracje — przez MapKit, nie tylko czatem. |
| **Sztywny flow „najpierw cel, potem start”** | Możesz podać sam cel (wtedy AI dopyta skąd jedziesz) **albo** w jednej wypowiedzi podać start i cel. |
| **AI zgadujące mapę** | Gdy czegoś nie umie — mówi wprost, zamiast zmyślać ETA, miejsca czy trasy. |
| **Odrywanie rąk od kierownicy** | Nasłuch **Hey Drive** w trakcie nawigacji, tymczasowa pastylka **Drive** do wpisania prośby, głosowe zatwierdź/anuluj przy ofercie restauracji. |
| **Utrata kontekstu po zjeździe z trasy** | Po objazdzie do restauracji przerwany cel może wrócić jako limonkowa pastylka „wznów” na ekranie startowym. |
| **Koniec trasy i problem z parkingiem** | Po zakończeniu trasy podsumowanie może zaproponować pobliskie parkingi. |

## Dla kogo?

- Kierowców, którzy chcą **jeden ekran pod auto** na iPhonie  
- Osób wolących **polskie komendy głosowe** w trasie  
- Twórców / testerów ciekawych **MapKit + on-device Foundation Models** w kształcie produktu  
- Każdego, kto szuka bezpieczniejszego UX w aucie niż standardowy ekran główny telefonu  

## Główne funkcje

### Drive (główny ekran)
- **Where you wanna go?** — wyszukiwanie celu, ostatnie miejsca, potwierdzenie startu  
- Nawigacja **Apple Maps** z ruchem drogowym i kafelkiem skrętu  
- Animowane rysowanie trasy i śledzenie pozycji kierowcy  
- Prędkość, recenter, zakończenie trasy, podsumowanie przejazdu  
- Pasek muzyki podczas aktywnej nawigacji  

### Drive Mate (głos i AI)
- Rozpoznawanie mowy po polsku (ASR)  
- Rozumienie języka naturalnego (CoreLM / Foundation Models, gdy dostępne) + **lokalny router intencji PL** jako awaryjna ścieżka  
- Intencje: **nawigacja**, **korki**, **info o ulicy**, **jedzenie w pobliżu**  
- Elastyczne formuły nawigacji, np.:
  - *„Rynek Dębnicki”* → pytanie: z Twojej lokalizacji czy z innego miejsca?  
  - *„Zaczynam z swojej lokalizacji i chcę dotrzeć do X”* → od razu trasa  
- W nawigacji: ciągłe nasłuchiwanie **Hey Drive** + tymczasowy przycisk **Drive** do wpisania prośby  
- Flow restauracji: popup (snapshot Apple Maps) → zatwierdź/anuluj dotykiem lub głosem → opcjonalne drugie potwierdzenie AI → trasa  

### Recorder
- Nagrywanie klipów z perspektywy kamery tylnej  
- Lokalne przechowywanie nagrań  

### Ustawienia
- Wygląd i preferencje odtwarzania (np. głośność muzyki, wyciszanie gdy mówi asystent)  

## Jak wygląda typowa jazda?

1. Otwórz **Drive** w orientacji poziomej.  
2. Wybierz cel (wyszukiwanie, recently, głos albo pastylka przerwanej trasy).  
3. Potwierdź start (GPS lub inne miejsce) — albo powiedz start i cel naraz.  
4. Jedź według mapy i kafelka skrętu; wołaj Drive Mate przy korkach, jedzeniu lub zmianie planu.  
5. Zakończ trasę → krótkie podsumowanie i opcjonalne parkingi.  

## Stack technologiczny

| Obszar | Technologie |
| --- | --- |
| UI | SwiftUI, landscape car dashboard, stylistyka liquid glass |
| Mapy i trasy | MapKit (`MKMapView`, `MKDirections`, `MKLocalSearch`, snapshoty) |
| Głos | Speech (ASR PL), AVSpeechSynthesizer |
| AI | Apple Foundation Models (CoreLM + tools + czat), lokalny parser intencji PL |
| Media | AVFoundation (muzyka, klipy z kamery) |
| Lokalizacja | CoreLocation |

## Struktura projektu (skrót)

```text
DriveMate/
├── Views/
│   ├── Drive/          # Mapa, idle, guidance, AI, koniec trasy
│   ├── Recorder/       # UI nagrywania
│   └── Settings/       # Preferencje
├── Services/           # Nawigacja, głos, AI, muzyka, kamera, parking, jedzenie
├── Models/             # Zakładki, modele mediów
└── Theme/              # Wspólny język wizualny
```

## Wymagania

- macOS z **Xcode** (współczesny iOS SDK)  
- **iPhone** zalecany (lokalizacja, mowa, kamera; Simulator ma ograniczenia)  
- Uprawnienia: **Lokalizacja**, **Mikrofon**, **Rozpoznawanie mowy**, **Kamera** (recorder)  
- **Apple Intelligence / Foundation Models** opcjonalnie — lokalny router działa też bez modelu  
- Przed nawigacją zaakceptuj **disclaimer / EULA** w aplikacji  

## Start

1. Sklonuj repozytorium.  
2. Otwórz `DriveMate.xcodeproj` w Xcode.  
3. Ustaw signing / development team.  
4. Zbuduj i uruchom najlepiej na fizycznym iPhonie.  
5. Nadaj uprawnienia lokalizacji i mikrofonu/mowy.  
6. Wejdź w zakładkę **Drive** i wypróbuj cel albo *Hey Drive*.  

```bash
git clone https://github.com/<twoje-konto>/DriveMate.git
cd DriveMate
open DriveMate.xcodeproj
```

## Prywatność i Apple Maps

- Lokalizacja, mikrofon, mowa i kamera są używane **na urządzeniu** do nawigacji, komend głosowych i nagrywania.  
- Wyszukiwanie miejsc, trasy, wskazówki ruchu i mapa pochodzą z **Apple Maps / MapKit**.  
- Aplikacja pokazuje Map Data / atrybucję tam, gdzie wymagają tego wytyczne Apple.  
- Nie commituj sekretów ani prywatnych kluczy; w publicznych forkach uważaj na lokalne pliki konfiguracyjne.

## Status

Aktywny prototyp produktowy. Funkcje i zachowanie AI nadal się rozwijają (rozumienie głosu, flow w aucie, dopracowanie UX).

## Współpraca

Issue’y i PR-y mile widziane. Opisz scenariusz jazdy (idle vs nawigacja, głos vs tekst) oraz urządzenie i wersję systemu.

## Licencja

Dodaj wybraną licencję (np. MIT) przed szerszą publikacją.

---

<p align="center">
  <b>DriveMate</b> — fewer glances at the phone, more focus on the road.<br/>
  <b>DriveMate</b> — mniej patrzenia w telefon, więcej uwagi na drodze.
</p>
