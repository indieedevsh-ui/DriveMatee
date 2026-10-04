# DriveMate

**AI-powered in-car companion for iOS** · **Asystent AI do jazdy na iOS**

Landscape car-dashboard app with Apple Maps navigation, hands-free Polish voice control, in-app music, rear-camera clips, and a Drive Mate assistant that actually steers the car UI — designed so you can keep your eyes on the road.

Aplikacja w układzie poziomym (kokpit samochodowy) z nawigacją Apple Maps, sterowaniem głosowym po polsku, muzyką w aplikacji, nagrywaniem klipów z kamery tylnej oraz asystentem Drive Mate, który realnie steruje UI — tak, by ręce i wzrok zostawały przy kierownicy.

**Version:** 1.0 · **Platform:** iOS 27+ · **UI:** SwiftUI (landscape)

---

## Table of contents · Spis treści

- [English](#english)
- [Polski](#polski)

---

<a id="english"></a>

# English

## What is DriveMate?

DriveMate turns your iPhone into a **driver-focused cockpit**. Navigation, voice AI, music, and rear-camera clips live in one landscape dashboard. The onboard assistant — **Drive Mate** — understands natural Polish (and typed requests) and performs real actions in the app: routes, traffic, street knowledge, food/fuel stops, music transport controls, UI chrome, and more.

It is built for real driving moments — not demo chat.

## Problems it solves

| Problem | How DriveMate helps |
| --- | --- |
| **Phone UI is not built for driving** | Landscape layout, large controls, liquid-glass cockpit meant for glanceable use. |
| **Too many apps while driving** | Navigation, voice AI, music, and clip recording in one place. |
| **Voice assistants that only talk** | Drive Mate starts routes, checks traffic, explains streets, offers food/fuel, controls music, and can hide/show UI tiles — with MapKit side effects. |
| **Rigid “destination then start” voice flows** | Say only the destination (Drive Mate asks where you start) **or** say start + destination in one sentence. Optional **Always use my location**. |
| **AI that invents map answers** | Unsupported requests get an honest refusal instead of fake ETA, places, or routes. |
| **Hands leaving the wheel** | **Hey Drive** wake listening, temporary **Drive** text pill, voice confirm/cancel for restaurant & gas offers. |
| **Losing context after a detour** | Interrupted destination is saved; say *“restore previous route”* — destination switches back from your **current GPS**, without the trip-summary screen. |
| **Speeding without a glance** | When speed exceeds the assumed urban limit (~50 km/h), Drive Mate asks you to slow down; the speed tile pulses red, then returns to green when you’re within limit. |
| **End of trip with nowhere to park** | Animated trip summary can suggest nearby parking. |

## Who is it for?

- Drivers who want a **single car-oriented screen** on iPhone  
- People who prefer **Polish voice commands** while driving  
- Builders / testers exploring **MapKit + on-device Foundation Models** in a product shape  
- Anyone after safer, more focused in-car UX than the stock phone home screen  

## Core features

### Drive (main screen)
- **Where you wanna go?** — destination search, recent places, start confirmation  
- **Apple Maps** navigation with traffic-aware routing and turn-guidance tiles  
- Animated lime **route draw** (camera follows the line) then flag at destination  
- Speed badge (green in limit / red when over), clock, recenter, end route  
- In-trip **music control bar** (manual + voice); Maps Legal pill lifts while the bar is visible  
- Drive Mate **liquid-glass avatar** (eyes + mouth) at the top when the assistant is active  

### Drive Mate (voice & AI)
- Polish ASR + TTS; music **ducks** (stays playing quietly) while Drive Mate speaks  
- CoreLM / Foundation Models when available + **local Polish intent router** fallback  
- Example intents:
  - **Navigate** (flexible start + destination)
  - **Restore interrupted route** (no summary overlay)
  - **Traffic / street info / street history** (PRG / TERYT / Wikipedia narrative — no raw codes in speech)
  - **Nearby food** & **gas stations** (voice confirm)
  - **Fuel cost** estimate (uses saved car model / consumption)
  - **Music**: pause, resume, next, previous
  - **Chrome**: show/hide speedometer, clock, Drive pill, recenter, recording indicator
  - **Speed limit** question; honest **unsupported** when out of scope
- Continuous **Hey Drive** wake listening on the Drive tab (trainable phrases in Settings)

### Trip end
- Lime **car-flag** intro with strong haptics → springy summary tiles → menu / nearby parking  

### Recorder
- Rear-camera oriented clip capture and local clip storage  

### Settings
- Appearance, music volume, **duck music while assistant speaks**  
- Always use my location, car model / fuel consumption  
- Import music, manage clips  
- Drive Mate wake-word training  

## How a typical trip looks

1. Open **Drive** in landscape (lime splash car intro).  
2. Pick a destination (search, recent, voice, or interrupted-route pill).  
3. Confirm start (GPS or another place) — or say both in one request.  
4. Watch the route draw; follow the map + turn tile.  
5. Call **Hey Drive** for traffic, food, fuel, music, or UI tweaks.  
6. End the route → flag animation → summary → optional parking.  

## Example voice lines (PL)

| You say | Drive Mate does |
| --- | --- |
| *„Rynek Dębnicki”* | Asks where to start, then routes |
| *„Z mojej lokalizacji jedź na Wawel”* | Routes immediately |
| *„Przywróć wcześniejszą trasę”* | Restores interrupted destination from current GPS |
| *„Jestem głodny”* / *„Najbliższa stacja”* | Offer card + voice confirm |
| *„Następny utwór”* / *„Pauza”* | Controls in-app music + reveals the player bar |
| *„Ukryj prędkościomierz”* | Hides the speed tile |
| *„Opowiedz historię tej ulicy”* | Narrative street card + TTS |

## Tech stack

| Area | Technology |
| --- | --- |
| UI | SwiftUI, landscape car dashboard, liquid glass |
| Maps & routing | MapKit (`MKMapView`, `MKDirections`, `MKLocalSearch`) |
| Voice | Speech (PL ASR), AVSpeechSynthesizer, custom wake spotting |
| AI | Apple Foundation Models (CoreLM + tools + chat), local PL intent parser |
| Media | AVFoundation (music, camera clips), mechanical UI click |
| Location | CoreLocation |
| Knowledge | Polish street enrichment (registers + Wikipedia narrative) |

## Project structure (high level)

```text
DriveMate/
├── DriveMate/
│   ├── Views/
│   │   ├── Drive/          # Map, idle setup, guidance, avatar, trip end
│   │   ├── Recorder/       # Clip capture UI
│   │   └── Settings/       # Preferences + Drive Mate training
│   ├── Services/           # Navigation, voice, AI, music, camera, parking, food, streets
│   ├── Models/             # Tabs, media models
│   ├── Theme/              # Palette, glass helpers, click style
│   ├── Resources/          # Sounds, assets
│   ├── ContentView.swift
│   └── MyApp.swift
└── DriveMate.xcodeproj
```

## Requirements

- macOS with **Xcode** supporting **iOS 27** SDK  
- **iPhone** strongly recommended (location, speech, haptics, camera; Simulator is limited)  
- Permissions: **Location**, **Microphone**, **Speech Recognition**, **Camera** (recorder)  
- **Apple Intelligence / Foundation Models** optional — local command routing still works  
- Accept the in-app **navigation disclaimer / EULA** before routing  
- Import audio in **Settings** to use the music player  

## Getting started

1. Clone this repository.  
2. Open `DriveMate.xcodeproj` in Xcode.  
3. Select your development team / signing.  
4. Build & run on a physical iPhone when possible.  
5. Grant location and microphone/speech permissions when prompted.  
6. Start on the **Drive** tab — try a destination or *Hey Drive*.  

```bash
git clone https://github.com/<your-account>/DriveMate.git
cd DriveMate
open DriveMate.xcodeproj
```

## Privacy & Apple Maps

- Location, microphone, speech, and camera are used **on-device** for navigation, voice, and recording.  
- Place search, routing, traffic hints, and map imagery come from **Apple Maps / MapKit**.  
- Maps · Legal attribution is shown on the navigation map (custom liquid-glass pill).  
- Do not commit secrets or private keys; keep personal config out of public forks.

## Status

Active product prototype. Voice understanding, in-car flows, and polish continue to evolve.

## Contributing

Issues and pull requests are welcome. Please describe the driving scenario you tested (idle vs navigating, voice vs typed) and the device/OS version.

## License

Add your preferred license here (e.g. MIT) before publishing widely.

---

<a id="polski"></a>

# Polski

## Czym jest DriveMate?

DriveMate zamienia iPhone’a w **kokpit dla kierowcy**. Nawigacja, AI głosowe, muzyka i klipy z kamery tylnej są w jednym poziomym dashboardzie. Asystent **Drive Mate** rozumie naturalny polski (oraz prośby wpisane) i wykonuje realne akcje w aplikacji: trasy, korki, wiedza o ulicach, jedzenie/paliwo, sterowanie muzyką, kafelki UI i więcej.

To produkt pod realną jazdę — nie sam czat.

## Jakie problemy rozwiązuje?

| Problem | Jak pomaga DriveMate |
| --- | --- |
| **Interfejs telefonu nie jest od jazdy** | Układ poziomy, duże elementy, kokpit „liquid glass”. |
| **Za dużo aplikacji za kierownicą** | Nawigacja, AI, muzyka i nagrywanie w jednym miejscu. |
| **Asystent, który tylko gada** | Drive Mate startuje trasy, sprawdza ruch, opowiada o ulicach, proponuje jedzenie/paliwo, steruje muzyką i kafelkami — przez MapKit, nie tylko tekstem. |
| **Sztywny flow cel → start** | Sam cel (AI dopyta skąd) **albo** start + cel w jednej wypowiedzi. Opcja **zawsze moja lokalizacja**. |
| **AI zgadujące mapę** | Przy braku możliwości — uczciwa odmowa zamiast zmyślonego ETA. |
| **Odrywanie rąk od kierownicy** | **Hey Drive**, pastylka **Drive**, głosowe tak/nie przy restauracji i stacji. |
| **Utrata kontekstu po zjeździe** | Przerwany cel jest zapisany; *„przywróć wcześniejszą trasę”* wraca do niego z **aktualnego GPS**, bez ekranu podsumowania. |
| **Przekroczenie prędkości** | Powyżej ok. 50 km/h Drive Mate prosi o zwolnienie; kafelek prędkości pulsuje na czerwono, potem znów jest zielony w limicie. |
| **Koniec trasy i parking** | Animowane podsumowanie może zaproponować pobliskie parkingi. |

## Dla kogo?

- Kierowców chcących **jeden ekran pod auto**  
- Osób wolących **polskie komendy głosowe**  
- Twórców / testerów **MapKit + on-device Foundation Models**  
- Każdego, kto szuka bezpieczniejszego UX w aucie  

## Główne funkcje

### Drive (główny ekran)
- **Where you wanna go?** — wyszukiwanie, ostatnie miejsca, potwierdzenie startu  
- Nawigacja **Apple Maps** z ruchem i kafelkiem skrętu  
- Animowane **rysowanie limonkowej trasy** (kamera jedzie z linią) i flaga na celu  
- Prędkościomierz (zielony / czerwony przy przekroczeniu), zegar, recenter, zakończ trasę  
- **Panel muzyki** w trasie (ręcznie + głosem); pastylka Maps Legal unosi się nad panelem  
- **Awatar Drive Mate** (liquid glass, oczy + minka) u góry, gdy asystent jest aktywny  

### Drive Mate (głos i AI)
- ASR i TTS po polsku; muzyka się **ścisza**, ale gra dalej, gdy asystent mówi  
- CoreLM / Foundation Models + **lokalny router intencji PL**  
- Przykładowe intencje:
  - **Nawigacja** (elastyczny start + cel)
  - **Przywróć przerwaną trasę** (bez podsumowania)
  - **Korki / info o ulicy / historia ulicy** (narracja bez kodów rejestrów)
  - **Jedzenie** i **stacje paliw** (potwierdzenie głosem)
  - **Koszt paliwa** (model auta / spalanie z ustawień)
  - **Muzyka**: pauza, wznowienie, następny, poprzedni
  - **Chrome UI**: pokaż/ukryj prędkościomierz, zegar, Drive, recenter, nagrywanie
  - Pytanie o **limit prędkości**; uczciwe **unsupported** poza zakresem
- Ciągłe **Hey Drive** na zakładce Drive (trening fraz w Ustawieniach)

### Koniec trasy
- Limonkowa **flaga z autkiem** + mocna haptyka → kafelki podsumowania → menu / parkingi  

### Recorder
- Klipy z kamery tylnej, lokalne przechowywanie  

### Ustawienia
- Wygląd, głośność, **ściszanie muzyki gdy mówi asystent**  
- Zawsze moja lokalizacja, model auta / spalanie  
- Import muzyki, klipy  
- Trening wake word Drive Mate  

## Jak wygląda typowa jazda?

1. Otwórz **Drive** poziomo (splash z limonkowym autem).  
2. Wybierz cel (szukaj, recently, głos albo pastylka przerwanej trasy).  
3. Potwierdź start (GPS lub inne miejsce) — albo powiedz start i cel naraz.  
4. Patrz na rysowanie trasy; jedź według mapy i kafelka skrętu.  
5. Wołaj **Hey Drive** przy korkach, jedzeniu, paliwie, muzyce lub UI.  
6. Zakończ trasę → flaga → podsumowanie → opcjonalne parkingi.  

## Przykładowe komendy

| Mówisz | Drive Mate robi |
| --- | --- |
| *„Rynek Dębnicki”* | Pyta o start, potem trasa |
| *„Z mojej lokalizacji jedź na Wawel”* | Od razu nawigacja |
| *„Przywróć wcześniejszą trasę”* | Przywraca przerwany cel z aktualnego GPS |
| *„Jestem głodny”* / *„Najbliższa stacja”* | Karta oferty + potwierdzenie głosem |
| *„Następny utwór”* / *„Pauza”* | Steruje muzyką i pokazuje panel |
| *„Ukryj prędkościomierz”* | Chowa kafelek prędkości |
| *„Opowiedz historię tej ulicy”* | Karta narracyjna + TTS |

## Stack technologiczny

| Obszar | Technologie |
| --- | --- |
| UI | SwiftUI, landscape car dashboard, liquid glass |
| Mapy i trasy | MapKit (`MKMapView`, `MKDirections`, `MKLocalSearch`) |
| Głos | Speech (ASR PL), AVSpeechSynthesizer, wake spotting |
| AI | Apple Foundation Models (CoreLM + tools + czat), lokalny parser PL |
| Media | AVFoundation (muzyka, klipy), mechaniczny klik UI |
| Lokalizacja | CoreLocation |
| Wiedza | Wzbogacanie ulic PL (rejestry + narracja Wikipedia) |

## Struktura projektu (skrót)

```text
DriveMate/
├── DriveMate/
│   ├── Views/
│   │   ├── Drive/          # Mapa, idle, guidance, awatar, koniec trasy
│   │   ├── Recorder/       # UI nagrywania
│   │   └── Settings/       # Preferencje + trening Drive Mate
│   ├── Services/           # Nawigacja, głos, AI, muzyka, kamera, parking, jedzenie, ulice
│   ├── Models/             # Zakładki, modele mediów
│   ├── Theme/              # Paleta, glass, styl klików
│   ├── Resources/          # Dźwięki, assety
│   ├── ContentView.swift
│   └── MyApp.swift
└── DriveMate.xcodeproj
```

## Wymagania

- macOS z **Xcode** pod **iOS 27**  
- **iPhone** mocno zalecany (lokalizacja, mowa, haptyka, kamera)  
- Uprawnienia: **Lokalizacja**, **Mikrofon**, **Rozpoznawanie mowy**, **Kamera**  
- **Apple Intelligence / Foundation Models** opcjonalnie — lokalny router działa bez modelu  
- Przed nawigacją zaakceptuj **disclaimer / EULA**  
- Zaimportuj muzykę w **Ustawieniach**, żeby korzystać z odtwarzacza  

## Start

1. Sklonuj repozytorium.  
2. Otwórz `DriveMate.xcodeproj` w Xcode.  
3. Ustaw signing / development team.  
4. Zbuduj i uruchom najlepiej na fizycznym iPhonie.  
5. Nadaj uprawnienia lokalizacji i mikrofonu/mowy.  
6. Wejdź w **Drive** i wypróbuj cel albo *Hey Drive*.  

```bash
git clone https://github.com/<twoje-konto>/DriveMate.git
cd DriveMate
open DriveMate.xcodeproj
```

## Prywatność i Apple Maps

- Lokalizacja, mikrofon, mowa i kamera są używane **na urządzeniu**.  
- Miejsca, trasy, ruch i mapa pochodzą z **Apple Maps / MapKit**.  
- Atrybucja Maps · Legal jest widoczna na mapie nawigacji (pastylka liquid glass).  
- Nie commituj sekretów ani prywatnych kluczy.

## Status

Aktywny prototyp produktowy. Rozumienie głosu, flow w aucie i dopracowanie UX nadal się rozwijają.

## Współpraca

Issue’y i PR-y mile widziane. Opisz scenariusz (idle vs nawigacja, głos vs tekst) oraz urządzenie i wersję systemu.

## Licencja

Dodaj wybraną licencję (np. MIT) przed szerszą publikacją.

---

<p align="center">
  <b>DriveMate</b> — fewer glances at the phone, more focus on the road.<br/>
  <b>DriveMate</b> — mniej patrzenia w telefon, więcej uwagi na drodze.
</p>
