#!/usr/bin/env python3
"""Generate Drive Mate-First Look.pdf — minimalist feature presentation."""

from __future__ import annotations

from pathlib import Path

from PIL import Image as PILImage
from reportlab.lib.colors import Color, HexColor, white, black
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
OUT = ROOT / "Drive Mate-First Look.pdf"

# Widescreen 16:9
W, H = 1920, 1080

BG = HexColor("#0B0B0C")
PANEL = HexColor("#141416")
MUTED = HexColor("#8A8A90")
DIM = HexColor("#5C5C62")
LIME = HexColor("#B8FF2E")
SOFT = HexColor("#E8E8EA")
LINE = HexColor("#222226")


def register_fonts() -> dict[str, str]:
    candidates = [
        ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/SFNS.ttf"),
        ("/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"),
        ("/Library/Fonts/Arial.ttf", "/Library/Fonts/Arial Bold.ttf"),
    ]
    regular, bold = "Helvetica", "Helvetica-Bold"
    for reg_path, bold_path in candidates:
        if Path(reg_path).exists() and Path(bold_path).exists():
            try:
                pdfmetrics.registerFont(TTFont("DMSans", reg_path))
                pdfmetrics.registerFont(TTFont("DMSans-Bold", bold_path))
                return {"r": "DMSans", "b": "DMSans-Bold"}
            except Exception:
                continue
    # Helvetica fallback — try SF Pro Text
    sf = Path("/System/Library/Fonts/SFNSText.ttf")
    sfb = Path("/System/Library/Fonts/SFNSText.ttf")
    if sf.exists():
        try:
            pdfmetrics.registerFont(TTFont("DMSans", str(sf)))
            pdfmetrics.registerFont(TTFont("DMSans-Bold", str(sfb)))
            return {"r": "DMSans", "b": "DMSans-Bold"}
        except Exception:
            pass
    return {"r": regular, "b": bold}


FONTS = register_fonts()


def new_page(c: canvas.Canvas) -> None:
    c.setFillColor(BG)
    c.rect(0, 0, W, H, fill=1, stroke=0)


def footer(c: canvas.Canvas, page: int, total: int) -> None:
    c.setFillColor(DIM)
    c.setFont(FONTS["r"], 12)
    c.drawString(64, 36, "Drive Mate · First Look")
    c.drawRightString(W - 64, 36, f"{page:02d} / {total:02d}")
    c.setStrokeColor(LINE)
    c.setLineWidth(1)
    c.line(64, 56, W - 64, 56)


def accent_bar(c: canvas.Canvas, x: float, y: float, w: float = 48) -> None:
    c.setFillColor(LIME)
    c.roundRect(x, y, w, 4, 2, fill=1, stroke=0)


def draw_title(c: canvas.Canvas, text: str, x: float, y: float, size: int = 42) -> None:
    c.setFillColor(SOFT)
    c.setFont(FONTS["b"], size)
    c.drawString(x, y, text)


def draw_kicker(c: canvas.Canvas, text: str, x: float, y: float) -> None:
    c.setFillColor(LIME)
    c.setFont(FONTS["b"], 13)
    c.drawString(x, y, text.upper())


def draw_body(c: canvas.Canvas, text: str, x: float, y: float, size: int = 16, color=MUTED, leading: float = 24) -> float:
    c.setFillColor(color)
    c.setFont(FONTS["r"], size)
    for line in text.split("\n"):
        c.drawString(x, y, line)
        y -= leading
    return y


def wrap_text(text: str, font: str, size: int, max_width: float) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for w in words:
        trial = (cur + " " + w).strip()
        if pdfmetrics.stringWidth(trial, font, size) <= max_width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def draw_wrapped(
    c: canvas.Canvas,
    text: str,
    x: float,
    y: float,
    max_width: float,
    size: int = 16,
    color=MUTED,
    leading: float = 24,
    font: str | None = None,
) -> float:
    font = font or FONTS["r"]
    c.setFillColor(color)
    c.setFont(font, size)
    for line in wrap_text(text, font, size, max_width):
        c.drawString(x, y, line)
        y -= leading
    return y


def draw_bullets(
    c: canvas.Canvas,
    items: list[str],
    x: float,
    y: float,
    max_width: float,
    size: int = 15,
    leading: float = 26,
) -> float:
    for item in items:
        c.setFillColor(LIME)
        c.circle(x + 4, y + 4, 3, fill=1, stroke=0)
        lines = wrap_text(item, FONTS["r"], size, max_width - 22)
        c.setFillColor(SOFT)
        c.setFont(FONTS["r"], size)
        for i, line in enumerate(lines):
            c.drawString(x + 18, y if i == 0 else y, line)
            if i < len(lines) - 1:
                y -= leading * 0.85
        y -= leading
    return y


def fit_image(path: Path, max_w: float, max_h: float) -> tuple[ImageReader, float, float]:
    im = PILImage.open(path).convert("RGB")
    iw, ih = im.size
    scale = min(max_w / iw, max_h / ih)
    w, h = iw * scale, ih * scale
    return ImageReader(im), w, h


def draw_image_card(
    c: canvas.Canvas,
    path: Path,
    x: float,
    y: float,
    max_w: float,
    max_h: float,
    radius: float = 18,
    caption: str | None = None,
) -> float:
    """Draw image bottom-left at (x,y). Returns top of card."""
    img, w, h = fit_image(path, max_w, max_h)
    pad = 10
    card_w, card_h = w + pad * 2, h + pad * 2 + (22 if caption else 0)
    # card background
    c.setFillColor(PANEL)
    c.roundRect(x, y, card_w, card_h, radius, fill=1, stroke=0)
    c.setStrokeColor(LINE)
    c.setLineWidth(1)
    c.roundRect(x, y, card_w, card_h, radius, fill=0, stroke=1)

    # clip-ish: just draw image inset
    img_x = x + pad
    img_y = y + pad + (18 if caption else 0)
    c.drawImage(img, img_x, img_y, width=w, height=h, preserveAspectRatio=True, mask="auto")

    if caption:
        c.setFillColor(DIM)
        c.setFont(FONTS["r"], 11)
        c.drawString(x + pad, y + 8, caption)
    return y + card_h


def slide_cover(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    icon = ASSETS / "DriveMate-AppIcon.jpg"
    if icon.exists():
        img, w, h = fit_image(icon, 220, 140)
        c.drawImage(img, (W - w) / 2, H * 0.58, width=w, height=h, mask="auto")

    accent_bar(c, (W - 48) / 2, H * 0.54, 48)
    c.setFillColor(SOFT)
    c.setFont(FONTS["b"], 64)
    c.drawCentredString(W / 2, H * 0.42, "Drive Mate")
    c.setFillColor(LIME)
    c.setFont(FONTS["b"], 22)
    c.drawCentredString(W / 2, H * 0.36, "First Look")
    c.setFillColor(MUTED)
    c.setFont(FONTS["r"], 18)
    c.drawCentredString(W / 2, H * 0.28, "AI-powered in-car companion for iOS")
    c.setFillColor(DIM)
    c.setFont(FONTS["r"], 14)
    c.drawCentredString(W / 2, H * 0.22, "Nawigacja · Głos · Muzyka · Recorder · Personalizacja")
    c.setFillColor(DIM)
    c.setFont(FONTS["r"], 12)
    c.drawCentredString(W / 2, 70, "iOS 27+  ·  SwiftUI  ·  Apple Maps  ·  On-device AI")
    footer(c, page, total)


def slide_agenda(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Spis treści", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Co zobaczysz", 64, H - 170)

    sections = [
        ("01", "Produkt", "Problem, obietnica, dla kogo"),
        ("02", "Drive", "Cel, mapa, trasa, prędkość, muzyka"),
        ("03", "Drive Mate AI", "Hey Drive, intencje, awatar"),
        ("04", "Koniec trasy", "Flaga, podsumowanie, parking"),
        ("05", "Recorder", "Tylna kamera i klipy 10 s"),
        ("06", "Settings", "Dźwięk, auto, motyw, biblioteka"),
        ("07", "Personalizacja", "Historia, unikania, trening wake"),
        ("08", "Stack", "Technologia i prywatność"),
    ]
    left_x, right_x = 64, W / 2 + 20
    y0 = H - 240
    for i, (num, title, sub) in enumerate(sections):
        col = 0 if i < 4 else 1
        row = i if i < 4 else i - 4
        x = left_x if col == 0 else right_x
        y = y0 - row * 140
        c.setFillColor(PANEL)
        c.roundRect(x, y - 20, 820, 110, 16, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 20)
        c.drawString(x + 28, y + 48, num)
        c.setFillColor(SOFT)
        c.setFont(FONTS["b"], 24)
        c.drawString(x + 90, y + 48, title)
        c.setFillColor(MUTED)
        c.setFont(FONTS["r"], 15)
        c.drawString(x + 90, y + 18, sub)
    footer(c, page, total)


def slide_product(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Produkt", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "iPhone jako kokpit kierowcy", 64, H - 170)

    draw_wrapped(
        c,
        "DriveMate łączy nawigację Apple Maps, asystenta głosowego po polsku, muzykę w aplikacji "
        "i nagrywanie z tylnej kamery w jednym poziomym dashboardzie. Drive Mate nie tylko rozmawia — "
        "wykonuje realne akcje w UI.",
        64,
        H - 230,
        820,
        size=17,
        leading=26,
    )

    cards = [
        ("Problem", "Telefon nie jest zaprojektowany do jazdy — za dużo appów, za małe cele."),
        ("Rozwiązanie", "Jeden landscape screen: mapa, głos, muzyka, klipy."),
        ("Różnica", "AI steruje MapKit i kafelkami — nie jest samym chatem."),
    ]
    for i, (t, body) in enumerate(cards):
        y = 520 - i * 150
        c.setFillColor(PANEL)
        c.roundRect(64, y, 820, 130, 16, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 14)
        c.drawString(92, y + 88, t.upper())
        draw_wrapped(c, body, 92, y + 52, 760, size=15, color=SOFT, leading=22)

    img_path = ASSETS / "Screenshot_iPhone_18_Pro_10-03-2026_at_11.35.18_AM-6cd7b1fe-2da4-457c-b74d-ebf9ea5a88a3.jpg"
    if img_path.exists():
        draw_image_card(c, img_path, 960, 140, 880, 760, caption="Drive — landscape dashboard")
    footer(c, page, total)


def slide_problems(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Wartość", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Jakie problemy rozwiązuje", 64, H - 170)

    rows = [
        ("UI nie pod jazdę", "Duże cele, liquid glass, layout poziomy."),
        ("Asystent tylko gada", "Trasy, korki, jedzenie, paliwo, muzyka, chrome UI."),
        ("Sztywny flow cel→start", "Sam cel albo start+cel; opcja Always Use My Location."),
        ("Utrata kontekstu", "Przywróć przerwaną trasę z aktualnego GPS — bez summary."),
        ("Przekroczenie prędkości", "Czerwony puls prędkościomierza + TTS „zwolnij”."),
        ("Koniec trasy", "Animowana flaga → kafelki → parking w pobliżu."),
    ]
    y = H - 230
    for title, body in rows:
        c.setFillColor(PANEL)
        c.roundRect(64, y - 50, W - 128, 88, 14, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 16)
        c.drawString(92, y - 5, title)
        c.setFillColor(MUTED)
        c.setFont(FONTS["r"], 15)
        c.drawString(520, y - 5, body)
        y -= 105
    footer(c, page, total)


def slide_shell(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Architektura UI", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Trzy zakładki · jeden kokpit", 64, H - 170)

    tabs = [
        ("DRIVE MATE", "Nawigacja, asystent, muzyka, prędkość"),
        ("RECORDER", "Tylna kamera, klipy 10 s, podgląd"),
        ("SETTINGS", "Dźwięk, auto, motyw, biblioteka, trening"),
    ]
    for i, (t, d) in enumerate(tabs):
        x = 64 + i * 600
        c.setFillColor(PANEL)
        c.roundRect(x, H - 420, 560, 160, 16, fill=1, stroke=0)
        c.setFillColor(LIME if i == 0 else SOFT)
        c.setFont(FONTS["b"], 22)
        c.drawString(x + 28, H - 330, t)
        c.setFillColor(MUTED)
        c.setFont(FONTS["r"], 14)
        draw_wrapped(c, d, x + 28, H - 365, 500, size=14)

    img = ASSETS / "image-c27bca64-e17a-4677-8758-629a894b744c.png"
    if img.exists():
        draw_image_card(c, img, 64, 90, 1780, 480, caption="Sidebar + mapa + speed + music bar")
    footer(c, page, total)


def slide_destination(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Drive · Start", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Where you wanna go", 64, H - 170)

    y = draw_wrapped(
        c,
        "Ekran startowy przed nawigacją. Wyszukiwanie celu, ostatnie miejsca i potwierdzenie punktu startowego.",
        64,
        H - 230,
        780,
        size=17,
        leading=26,
    )
    draw_bullets(
        c,
        [
            "Pill „Where you wanna go” z gradientem — wejście do wyszukiwania",
            "Siatka Recently — szybki wybór ostatnich celów",
            "Potwierdzenie startu: GPS albo inna lokalizacja",
            "Opcja Always Use My Location pomija pytanie o start",
            "Przerwana trasa: pill przywrócenia bez ekranu podsumowania",
        ],
        64,
        y - 20,
        780,
    )

    img = ASSETS / "image-405516a0-333d-4833-bbc5-984b4bc4fb5e.png"
    alt = ASSETS / "image-266df732-5105-4925-ba3d-1d6caca63394.png"
    path = img if img.exists() else alt
    if path.exists():
        draw_image_card(c, path, 920, 140, 920, 780, caption="Idle setup — destination picker")
    footer(c, page, total)


def slide_navigation(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Drive · Nawigacja", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Apple Maps w kokpicie", 64, H - 170)

    draw_bullets(
        c,
        [
            "MapKit z legalnym oznaczeniem Maps · Legal (liquid-glass pill)",
            "Routing z uwzględnieniem ruchu (MKDirections)",
            "Animowane rysowanie trasy limonką — kamera podąża za linią",
            "Flaga na celu po zakończeniu rysowania",
            "Kafelki turn-by-turn podczas jazdy",
            "Recenter i zakończenie trasy jednym gestem",
            "Prawy pasek glass w landscape podczas nawigacji",
        ],
        64,
        H - 250,
        820,
    )

    img = ASSETS / "IMG_8944-a2565970-7d37-4150-8533-8bdc5fe86d96.jpg"
    if img.exists():
        draw_image_card(c, img, 960, 140, 880, 780, caption="Live map + speed + music")
    footer(c, page, total)


def slide_speed_music(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Drive · Chrome", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Prędkość i muzyka", 64, H - 170)

    # two columns
    c.setFillColor(PANEL)
    c.roundRect(64, 140, 880, 640, 18, fill=1, stroke=0)
    c.roundRect(976, 140, 880, 640, 18, fill=1, stroke=0)

    c.setFillColor(LIME)
    c.setFont(FONTS["b"], 14)
    c.drawString(96, 720, "SPEED BADGE")
    c.drawString(1008, 720, "MUSIC BAR")

    draw_bullets(
        c,
        [
            "Liquid-glass kafelek prędkości (GPS)",
            "Zielony w limicie miejskim (~50 km/h)",
            "Czerwony puls + TTS przy przekroczeniu",
            "Filtry stacjonarne — mniej fałszywych km/h",
            "Można ukryć głosowo („ukryj prędkościomierz”)",
        ],
        96,
        660,
        780,
    )
    draw_bullets(
        c,
        [
            "Duży pasek: poprzedni / play / następny",
            "Sterowanie ręczne i głosowe",
            "Duck muzyki gdy Drive Mate mówi",
            "Maps Legal podnosi się gdy pasek widoczny",
            "Biblioteka z Settings (MP3 / MP4→AAC)",
        ],
        1008,
        660,
        780,
    )
    footer(c, page, total)


def slide_avatar(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Drive Mate · Obecność", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Awatar liquid glass", 64, H - 170)

    y = draw_wrapped(
        c,
        "Gdy asystent jest aktywny, na górze mapy pojawia się buźka Drive Mate — oczy i usta w półprzezroczystej soczewce. "
        "Tryby: pełny awatar w nawigacji, same oczy przy konfiguracji głosu, glow w stylu Siri przy słuchaniu.",
        64,
        H - 230,
        820,
        size=17,
        leading=26,
    )
    draw_bullets(
        c,
        [
            "Animacje: mruganie, lekki sway, spojrzenie",
            "Poświata krawędzi ekranu przy dyktowaniu / słuchaniu",
            "Muzyka ścisza się (duck), nie zatrzymuje się",
            "Polski ASR + TTS — odpowiedzi na głos",
        ],
        64,
        y - 16,
        820,
    )

    img1 = ASSETS / "IMG_8946-6e8dea2d-7f60-4006-bcf5-79232aae6569.png"
    img2 = ASSETS / "image-5e8caaac-42ca-42b3-90c1-72ca779f1053.png"
    if img1.exists():
        draw_image_card(c, img1, 960, 420, 880, 420, caption="Awatar na mapie")
    if img2.exists():
        draw_image_card(c, img2, 960, 90, 880, 300, caption="Close-up liquid glass")
    footer(c, page, total)


def slide_voice(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Drive Mate · Głos", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Intencje, które coś robią", 64, H - 170)

    pairs = [
        ("„Rynek Dębnicki”", "Pyta skąd start, potem prowadzi"),
        ("„Z mojej lokalizacji na Wawel”", "Trasa od razu"),
        ("„Przywróć wcześniejszą trasę”", "Przywraca cel z aktualnego GPS"),
        ("„Jestem głodny” / „Najbliższa stacja”", "Karta oferty + potwierdzenie głosem"),
        ("„Następny utwór” / „Pauza”", "Steruje playerem + pokazuje pasek"),
        ("„Ukryj prędkościomierz”", "Chowa kafelek chrome"),
        ("„Opowiedz historię tej ulicy”", "Narracja + karta (bez surowych kodów)"),
        ("„Ile zapłacę za paliwo?”", "Szacunek z modelu auta / spalania"),
    ]

    y = H - 240
    for say, does in pairs:
        c.setFillColor(PANEL)
        c.roundRect(64, y - 36, W - 128, 72, 12, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 15)
        c.drawString(92, y - 8, say)
        c.setFillColor(MUTED)
        c.setFont(FONTS["r"], 15)
        c.drawRightString(W - 92, y - 8, does)
        y -= 86

    footer(c, page, total)


def slide_voice_stack(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Drive Mate · Silnik", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Jak rozumie polecenia", 64, H - 170)

    cols = [
        (
            "Wejście",
            [
                "Ciągłe słuchanie Hey Drive na zakładce Drive",
                "Polski Speech Recognition (ASR)",
                "Tekst wpisany (gdy potrzeba)",
                "Trening wymowy w Settings",
            ],
        ),
        (
            "Rozumienie",
            [
                "Apple Foundation Models / CoreLM + tools",
                "Lokalny polski intent router (fallback)",
                "Odmowa zamiast zmyślonych ETA / miejsc",
                "Pamięć wizyt i preferencji tras",
            ],
        ),
        (
            "Efekt",
            [
                "MapKitNavigationService — realne trasy",
                "Karty: jedzenie, paliwo, ulice, parking",
                "MusicPlayerService — transport + duck",
                "Chrome store — show/hide kafelków",
            ],
        ),
    ]
    for i, (title, items) in enumerate(cols):
        x = 64 + i * 600
        c.setFillColor(PANEL)
        c.roundRect(x, 140, 560, 680, 18, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 14)
        c.drawString(x + 28, 760, title.upper())
        draw_bullets(c, items, x + 28, 700, 500, size=15, leading=36)

    footer(c, page, total)


def slide_trip_end(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Drive · Koniec", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Flaga, haptics, podsumowanie", 64, H - 170)

    draw_wrapped(
        c,
        "Po dojechaniu: animowana limonkowa flaga z samochodem i mocne haptics, potem sprężyste kafelki podsumowania. "
        "Opcjonalnie — wyszukaj parking w pobliżu. Przywrócenie wcześniejszej trasy omija ten ekran.",
        64,
        H - 240,
        1000,
        size=17,
        leading=26,
    )

    steps = [
        ("01", "Car-flag", "Intro limonkowej flagi + haptic"),
        ("02", "Tiles", "Dystans, czas, kluczowe metryki"),
        ("03", "Parking", "Nearby parking z MapKit"),
        ("04", "Menu", "Powrót do idle / nowa trasa"),
    ]
    for i, (n, t, d) in enumerate(steps):
        x = 64 + i * 450
        c.setFillColor(PANEL)
        c.roundRect(x, 200, 420, 280, 16, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 18)
        c.drawString(x + 28, 420, n)
        c.setFillColor(SOFT)
        c.setFont(FONTS["b"], 22)
        c.drawString(x + 28, 360, t)
        draw_wrapped(c, d, x + 28, 310, 360, size=14)

    footer(c, page, total)


def slide_recorder(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Recorder", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Tylna kamera · klipy 10 s", 64, H - 170)

    draw_bullets(
        c,
        [
            "Podgląd zorientowany na tylną kamerę",
            "Automatyczne klipy ~10 sekund",
            "Nagrywanie tylko wideo — bez mikrofonu w ścieżce klipu",
            "Nie wycisza muzyki i nie psuje sesji audio Drive Mate",
            "Ciągłe nagrywanie może działać w tle przy przejściu na Drive",
            "Lokalne przechowywanie klipów + przegląd w Settings",
            "Włączane przełącznikiem RECORDER w ustawieniach",
        ],
        64,
        H - 250,
        900,
    )

    img = ASSETS / "image-2e94a1fe-ee8b-4ac7-be87-2d1f800a9a86.png"
    if img.exists():
        draw_image_card(c, img, 1000, 160, 840, 700, caption="Drive UI z wskaźnikiem REC")
    footer(c, page, total)


def slide_settings(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Settings", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Kontrola kokpitu", 64, H - 170)

    groups = [
        ("Dźwięk", ["Głośność muzyki (neon slider)", "Autowyciszacz — duck przy TTS"]),
        ("Nawigacja", ["Always Use My Location", "Model auta + spalanie l/100 km"]),
        ("Wygląd", ["Motyw ciemny / jasny", "Liquid-glass karty ustawień"]),
        ("Media", ["Import MP3 / MP4→AAC", "Lista klipów recordera"]),
    ]
    for i, (title, items) in enumerate(groups):
        col, row = i % 2, i // 2
        x = 64 + col * 900
        y = 520 - row * 280
        c.setFillColor(PANEL)
        c.roundRect(x, y, 860, 240, 16, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 14)
        c.drawString(x + 28, y + 190, title.upper())
        draw_bullets(c, items, x + 28, y + 140, 780, size=16, leading=32)

    footer(c, page, total)


def slide_settings_visual(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Settings · Podgląd", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "SOUND · Autowyciszacz · więcej", 64, H - 170)

    draw_wrapped(
        c,
        "Ustawienia utrzymują ten sam język wizualny co Drive: ciemne karty, limonkowe akcenty, duże przełączniki. "
        "Stąd też wejście do personalizacji Drive Mate.",
        64,
        H - 230,
        800,
        size=17,
        leading=26,
    )

    img = ASSETS / "image-f41f7816-b284-4550-8d00-a97e613455ec.png"
    if img.exists():
        draw_image_card(c, img, 900, 120, 940, 780, caption="SettingsUI — volume + auto-duck")
    footer(c, page, total)


def slide_personalization(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Personalizacja", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Drive Mate uczy się Ciebie", 64, H - 170)

    blocks = [
        (
            "Ostatnie miejsca",
            "Historia wizyt max 3 dni. Głosowo: „Weź mnie tam gdzie pojechałem 2 dni temu”.",
        ),
        (
            "Preferencje tras",
            "Gdy ≥3 razy omijasz tę samą ulicę, następnym razem prowadzi „po Twojemu”.",
        ),
        (
            "Hey Drive — trening",
            "Powiedz „Hey Drive” trzy razy. ASR zapamiętuje Twoją wymowę.",
        ),
        (
            "Usuń dane",
            "Kasuje wizyty, unikania i profil wake. Model auta zostaje w ustawieniach ogólnych.",
        ),
    ]
    for i, (t, d) in enumerate(blocks):
        y = H - 280 - i * 150
        c.setFillColor(PANEL)
        c.roundRect(64, y - 40, W - 128, 130, 16, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 16)
        c.drawString(96, y + 50, t.upper())
        draw_wrapped(c, d, 96, y + 10, W - 220, size=16, color=SOFT, leading=24)

    footer(c, page, total)


def slide_flow(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Scenariusz", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Typowa podróż", 64, H - 170)

    steps = [
        ("1", "Splash", "Limonkowy intro samochodu"),
        ("2", "Cel", "Search / Recently / głos"),
        ("3", "Start", "GPS lub inny punkt"),
        ("4", "Trasa", "Rysowanie + turn tile"),
        ("5", "Hey Drive", "Korki, jedzenie, muzyka"),
        ("6", "Meta", "Flaga → summary → parking"),
    ]
    for i, (n, t, d) in enumerate(steps):
        x = 64 + (i % 3) * 600
        y = 520 if i < 3 else 180
        c.setFillColor(PANEL)
        c.roundRect(x, y, 560, 280, 18, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 36)
        c.drawString(x + 32, y + 200, n)
        c.setFillColor(SOFT)
        c.setFont(FONTS["b"], 24)
        c.drawString(x + 32, y + 140, t)
        draw_wrapped(c, d, x + 32, y + 90, 480, size=15)
    footer(c, page, total)


def slide_tech(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Technologia", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Stack pod realną jazdę", 64, H - 170)

    rows = [
        ("UI", "SwiftUI · landscape · liquid glass"),
        ("Maps", "MapKit · MKDirections · MKLocalSearch · Legal"),
        ("Voice", "Speech PL · AVSpeechSynthesizer · wake spotting"),
        ("AI", "Foundation Models / CoreLM + lokalny intent router"),
        ("Media", "AVFoundation music · camera clips · click sound"),
        ("Location", "CoreLocation + filtry prędkości"),
        ("Knowledge", "Ulice PL · Wikipedia narrative · parking / food / fuel"),
    ]
    y = H - 240
    for left, right in rows:
        c.setFillColor(PANEL)
        c.roundRect(64, y - 28, W - 128, 68, 12, fill=1, stroke=0)
        c.setFillColor(LIME)
        c.setFont(FONTS["b"], 15)
        c.drawString(96, y - 2, left)
        c.setFillColor(SOFT)
        c.setFont(FONTS["r"], 15)
        c.drawString(280, y - 2, right)
        y -= 90
    footer(c, page, total)


def slide_privacy(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    draw_kicker(c, "Zaufanie", 64, H - 90)
    accent_bar(c, 64, H - 110)
    draw_title(c, "Prywatność i zgodność", 64, H - 170)

    points = [
        "Lokalizacja, mikrofon, speech i kamera — on-device do nawigacji, głosu i nagrania",
        "Miejsca, trasy i ruch pochodzą z Apple Maps / MapKit",
        "Atrybucja Maps · Legal widoczna na mapie nawigacji",
        "EULA / disclaimer nawigacyjny przed pierwszą trasą",
        "Brak sekretów w repo — konfiguracja osobista poza forkiem",
        "Unsupported request → uczciwa odmowa, bez zmyślonych odpowiedzi mapowych",
    ]
    draw_bullets(c, points, 64, H - 250, 1200, size=18, leading=48)

    c.setFillColor(PANEL)
    c.roundRect(64, 120, W - 128, 140, 16, fill=1, stroke=0)
    c.setFillColor(MUTED)
    c.setFont(FONTS["r"], 16)
    c.drawString(96, 190, "Wymagania: iPhone (zalecany) · Localization · Microphone · Speech · Camera")
    c.drawString(96, 155, "Apple Intelligence opcjonalne — lokalny router intencji działa bez niego.")
    footer(c, page, total)


def slide_closing(c: canvas.Canvas, page: int, total: int) -> None:
    new_page(c)
    icon = ASSETS / "DriveMate-AppIcon.jpg"
    if icon.exists():
        img, w, h = fit_image(icon, 180, 110)
        c.drawImage(img, (W - w) / 2, H * 0.55, width=w, height=h, mask="auto")

    accent_bar(c, (W - 48) / 2, H * 0.50, 48)
    c.setFillColor(SOFT)
    c.setFont(FONTS["b"], 48)
    c.drawCentredString(W / 2, H * 0.40, "Ręce na kierownicy.")
    c.setFillColor(LIME)
    c.setFont(FONTS["b"], 28)
    c.drawCentredString(W / 2, H * 0.33, "Drive Mate za Ciebie.")
    c.setFillColor(MUTED)
    c.setFont(FONTS["r"], 16)
    c.drawCentredString(W / 2, H * 0.24, "First Look · v1.0 · iOS 27+")
    c.setFillColor(DIM)
    c.setFont(FONTS["r"], 13)
    c.drawCentredString(W / 2, 90, "Drive Mate — AI-powered in-car companion")
    footer(c, page, total)


def main() -> None:
    slides = [
        slide_cover,
        slide_agenda,
        slide_product,
        slide_problems,
        slide_shell,
        slide_destination,
        slide_navigation,
        slide_speed_music,
        slide_avatar,
        slide_voice,
        slide_voice_stack,
        slide_trip_end,
        slide_recorder,
        slide_settings,
        slide_settings_visual,
        slide_personalization,
        slide_flow,
        slide_tech,
        slide_privacy,
        slide_closing,
    ]
    total = len(slides)
    c = canvas.Canvas(str(OUT), pagesize=(W, H))
    c.setTitle("Drive Mate-First Look")
    c.setAuthor("DriveMate")
    c.setSubject("Feature presentation")
    for i, fn in enumerate(slides, start=1):
        fn(c, i, total)
        c.showPage()
    c.save()
    print(f"Wrote {OUT} ({total} slides)")


if __name__ == "__main__":
    main()
