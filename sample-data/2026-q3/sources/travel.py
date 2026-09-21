# /// script
# requires-python = ">=3.13"
# dependencies = ["reportlab>=4.0"]
# ///
"""Generate the six fictional Q3 2026 travel documents for Pfennig Dev."""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
import json
from pathlib import Path
from typing import Iterable

from reportlab.lib import colors
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen.canvas import Canvas
from reportlab.lib.units import mm


DATASET = Path(__file__).resolve().parent.parent
OUTPUT = DATASET / "reise"
MANIFEST = Path(__file__).resolve().parent / "travel.json"

INK = HexColor("#1F2933")
MUTED = HexColor("#64707D")
PAPER = HexColor("#FBFAF7")
BLUE = HexColor("#1B4D73")
PALE_BLUE = HexColor("#E8F0F5")
TEAL = HexColor("#176B68")
PALE_TEAL = HexColor("#E8F3F0")
AMBER = HexColor("#C66B2D")
PALE_AMBER = HexColor("#FFF1E4")
PLUM = HexColor("#5B3F5F")
PALE_PLUM = HexColor("#F1EAF2")
TICKET_BLUE = HexColor("#0E4A7A")

STUDIO = [
    "Studio Linden · Design & Web",
    "Einzelunternehmen Mara Winter",
    "Musterufer 18 · 20457 Hamburg · Deutschland",
    "hallo@studio-linden.example",
    "USt-ID: DE000000000 (ungültiger Demo-Platzhalter)",
]
HOTEL_NAME = "Lumenhof Hotel München"
HOTEL_ADDRESS = "Sonnenbogen 12 · 80331 München"


@dataclass(frozen=True)
class Position:
    label: str
    net: int
    rate: int

    @property
    def tax(self) -> int:
        return tax_cents(self.net, self.rate)

    @property
    def gross(self) -> int:
        return self.net + self.tax


def tax_cents(net: int, rate: int) -> int:
    """Calculate tax in cents with decimal half-up rounding."""
    value = Decimal(net) * Decimal(rate) / Decimal(100)
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def money(cents: int, symbol: str = "€") -> str:
    sign = "-" if cents < 0 else ""
    absolute = abs(cents)
    euros, remainder = divmod(absolute, 100)
    return f"{sign}{euros:,}".replace(",", ".") + f",{remainder:02d} {symbol}"


def pos_dict(position: Position) -> dict[str, int]:
    return {
        "netto": position.net,
        "steuersatz": position.rate,
        "steuer": position.tax,
    }


def make_entry(
    filename: str,
    datum: str,
    partner: str,
    positions: Iterable[Position],
    payment_date: str,
    scenario: str,
) -> dict:
    position_list = list(positions)
    gross = sum(position.gross for position in position_list)
    return {
        "filename": filename,
        "datum": datum,
        "gegenpartei": partner,
        "richtung": "ausgabe",
        "waehrung": "EUR",
        "positionen": [pos_dict(position) for position in position_list],
        "brutto": gross,
        "zahlungen": [{"datum": payment_date, "betrag": gross}],
        "scenario": scenario,
    }


def new_canvas(path: Path, width: float, height: float, title: str) -> Canvas:
    canvas = Canvas(str(path), pagesize=(width, height), pageCompression=1)
    canvas.setTitle(title)
    canvas.setAuthor("Pfennig Dev · Fiktive Beispieldaten")
    canvas.setSubject("Fiktiver Musterbeleg · Nicht zur Zahlung")
    return canvas


def draw_footer(canvas: Canvas, width: float, y: float = 17, color=MUTED) -> None:
    canvas.setFillColor(color)
    canvas.setFont("Helvetica", 6.7)
    canvas.drawCentredString(width / 2, y, "Fiktiver Musterbeleg · Nicht zur Zahlung")


def draw_lines(canvas: Canvas, lines: Iterable[str], x: float, y: float, leading: float = 12, size: float = 8.5, color=INK) -> float:
    canvas.setFillColor(color)
    canvas.setFont("Helvetica", size)
    for line in lines:
        canvas.drawString(x, y, line)
        y -= leading
    return y


def draw_right(canvas: Canvas, text: str, x: float, y: float, size: float = 8.5, color=INK, font: str = "Helvetica") -> None:
    canvas.setFillColor(color)
    canvas.setFont(font, size)
    canvas.drawRightString(x, y, text)


def draw_center(canvas: Canvas, text: str, x: float, y: float, size: float = 8.5, color=INK, font: str = "Helvetica") -> None:
    canvas.setFillColor(color)
    canvas.setFont(font, size)
    canvas.drawCentredString(x, y, text)


def wrap_text(text: str, font: str, size: float, max_width: float) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if stringWidth(candidate, font, size) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_wrapped(canvas: Canvas, text: str, x: float, y: float, width: float, size: float = 8.5, leading: float = 11, color=INK, font: str = "Helvetica") -> float:
    canvas.setFillColor(color)
    canvas.setFont(font, size)
    for line in wrap_text(text, font, size, width):
        canvas.drawString(x, y, line)
        y -= leading
    return y


def rule(canvas: Canvas, x1: float, y: float, x2: float, color=HexColor("#D7DDE2"), width: float = 0.7) -> None:
    canvas.setStrokeColor(color)
    canvas.setLineWidth(width)
    canvas.line(x1, y, x2, y)


def draw_studio_block(canvas: Canvas, x: float, y: float, size: float = 8.4, leading: float = 11, color=INK) -> float:
    return draw_lines(canvas, STUDIO, x, y, leading=leading, size=size, color=color)


def draw_table_header(canvas: Canvas, x: float, y: float, columns: list[tuple[str, float]], width: float, fill=PALE_BLUE, text_color=BLUE) -> None:
    height = 22
    canvas.setFillColor(fill)
    canvas.roundRect(x, y - height + 5, width, height, 4, fill=1, stroke=0)
    canvas.setFillColor(text_color)
    canvas.setFont("Helvetica-Bold", 7.3)
    for label, position in columns:
        canvas.drawString(x + position, y - 9, label)


def draw_amount_row(canvas: Canvas, x: float, y: float, label: str, net: int, rate: int, right: float, size: float = 8.5) -> float:
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", size)
    canvas.drawString(x, y, label)
    canvas.setFont("Helvetica", size - 0.2)
    draw_right(canvas, money(net), right - 112, y, size=size - 0.2)
    draw_right(canvas, f"{rate} %", right - 70, y, size=size - 0.2)
    draw_right(canvas, money(net + tax_cents(net, rate)), right, y, size=size - 0.2)
    return y - 20


def draw_tax_summary(canvas: Canvas, x: float, y: float, width: float, positions: list[Position], accent=BLUE) -> float:
    canvas.setFillColor(HexColor("#F4F6F7"))
    canvas.roundRect(x, y - 100, width, 100, 7, fill=1, stroke=0)
    canvas.setFont("Helvetica-Bold", 8)
    canvas.setFillColor(accent)
    canvas.drawString(x + 14, y - 18, "STEUERÜBERSICHT")
    y -= 38
    net_total = sum(p.net for p in positions)
    tax_by_rate: dict[int, int] = {}
    for position in positions:
        tax_by_rate[position.rate] = tax_by_rate.get(position.rate, 0) + position.tax
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8.2)
    canvas.drawString(x + 14, y, "Netto")
    draw_right(canvas, money(net_total), x + width - 14, y, size=8.2)
    y -= 15
    for rate, tax in sorted(tax_by_rate.items()):
        canvas.drawString(x + 14, y, f"USt {rate} %")
        draw_right(canvas, money(tax), x + width - 14, y, size=8.2)
        y -= 15
    rule(canvas, x + 14, y + 4, x + width - 14, color=HexColor("#CDD5DA"))
    canvas.setFont("Helvetica-Bold", 9.5)
    canvas.drawString(x + 14, y - 11, "Gesamt")
    draw_right(canvas, money(net_total + sum(tax_by_rate.values())), x + width - 14, y - 11, size=9.5, color=accent)
    return y - 30


def create_flight(path: Path) -> None:
    width, height = A4
    canvas = new_canvas(path, width, height, "Rechnung ML-2026-0914-07")
    canvas.setFillColor(BLUE)
    canvas.rect(0, height - 106, width, 106, fill=1, stroke=0)
    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica-Bold", 20)
    canvas.drawString(44, height - 43, "MUSTER / AIR")
    canvas.setFont("Helvetica", 8.2)
    canvas.drawString(45, height - 62, "Muster-Luftverkehr AG · muster-luftverkehr.example")
    canvas.setFont("Helvetica-Bold", 25)
    canvas.drawRightString(width - 44, height - 48, "RECHNUNG")
    canvas.setFont("Helvetica", 8)
    canvas.drawRightString(width - 44, height - 67, "ML-2026-0914-07")

    y = height - 143
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica-Bold", 7.5)
    canvas.drawString(45, y, "RECHNUNGSEMPFÄNGER")
    draw_studio_block(canvas, 45, y - 18, size=8.4)
    draw_right(canvas, "Rechnungsdatum", width - 45, y, size=7.5, color=MUTED)
    draw_right(canvas, "07.09.2026", width - 45, y - 16, size=9, color=INK)
    draw_right(canvas, "Zahlungsstatus", width - 45, y - 42, size=7.5, color=MUTED)
    draw_right(canvas, "Bezahlt am 08.09.2026", width - 45, y - 58, size=9, color=TEAL)

    y -= 121
    canvas.setFillColor(PALE_BLUE)
    canvas.roundRect(45, y - 116, width - 90, 116, 8, fill=1, stroke=0)
    canvas.setFillColor(BLUE)
    canvas.setFont("Helvetica-Bold", 9)
    canvas.drawString(61, y - 23, "REISEÜBERSICHT")
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(INK)
    canvas.drawString(61, y - 45, "14.09.2026")
    canvas.setFont("Helvetica-Bold", 15)
    canvas.drawString(130, y - 46, "HAM")
    canvas.setFont("Helvetica", 8)
    canvas.drawString(176, y - 43, "07:10  ·  MusterAir 714")
    canvas.setFont("Helvetica-Bold", 15)
    canvas.drawString(329, y - 46, "MUC")
    canvas.setFont("Helvetica", 8)
    canvas.drawString(374, y - 43, "08:25")
    rule(canvas, 61, y - 58, width - 61, color=HexColor("#B9CEDD"))
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(61, y - 79, "16.09.2026")
    canvas.setFont("Helvetica-Bold", 15)
    canvas.drawString(130, y - 80, "MUC")
    canvas.setFont("Helvetica", 8)
    canvas.drawString(176, y - 77, "18:20  ·  MusterAir 715")
    canvas.setFont("Helvetica-Bold", 15)
    canvas.drawString(329, y - 80, "HAM")
    canvas.setFont("Helvetica", 8)
    canvas.drawString(374, y - 77, "19:35")
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 7.5)
    canvas.drawString(61, y - 101, "Inländische Personenbeförderung · Hin- und Rückflug · 1 Reisende")

    y -= 148
    draw_table_header(canvas, 45, y, [("LEISTUNG", 14), ("NETTO", 330), ("SATZ", 408), ("BRUTTO", 454)], width - 90)
    y -= 35
    position = Position("Hin- und Rückflug Hamburg – München", 23800, 19)
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8.8)
    canvas.drawString(59, y, position.label)
    canvas.setFont("Helvetica", 7.8)
    canvas.setFillColor(MUTED)
    canvas.drawString(59, y - 13, "14.09. Hinflug · 16.09. Rückflug · Tarif Economy")
    draw_right(canvas, money(position.net), width - 45 - 112, y, size=8.5)
    draw_right(canvas, "19 %", width - 45 - 70, y, size=8.5)
    draw_right(canvas, money(position.gross), width - 45, y, size=8.5)
    rule(canvas, 45, y - 31, width - 45)

    y -= 66
    draw_tax_summary(canvas, width - 250, y, 205, [position], accent=BLUE)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 7.6)
    canvas.drawString(45, 151, "Zahlung vor Abflug · Kartenreferenz DEMO-0809 · Keine Bankverbindung")
    canvas.drawString(45, 134, "Ausgestellt für die Geschäftsreise zum Workshop bei Isarblick Innenräume am 15.09.2026.")
    draw_footer(canvas, width)
    canvas.save()


def receipt_header(canvas: Canvas, width: float, title: str, subtitle: str, accent=INK) -> float:
    draw_center(canvas, title, width / 2, 470, size=13, color=accent, font="Courier-Bold")
    draw_center(canvas, subtitle, width / 2, 448, size=7.5, color=accent, font="Courier")
    rule(canvas, 19, 430, width - 19, color=accent, width=0.8)
    return 411


def receipt_line(canvas: Canvas, y: float, label: str, value: str, width: float, size: float = 8.2, bold: bool = False) -> float:
    font = "Courier-Bold" if bold else "Courier"
    canvas.setFillColor(INK)
    canvas.setFont(font, size)
    canvas.drawString(19, y, label)
    draw_right(canvas, value, width - 19, y, size=size, color=INK, font=font)
    return y - 16


def create_taxi(path: Path) -> None:
    width, height = 80 * mm, 166 * mm
    canvas = new_canvas(path, width, height, "Taxiquittung NS-140926-0848")
    canvas.setFillColor(PAPER)
    canvas.rect(0, 0, width, height, fill=1, stroke=0)
    canvas.setFillColor(AMBER)
    canvas.rect(0, height - 7, width, 7, fill=1, stroke=0)
    y = height - 25
    draw_center(canvas, "NORDSTERN MOBILITÄT", width / 2, y, size=11.2, color=INK, font="Courier-Bold")
    y -= 15
    draw_center(canvas, "nordstern-mobil.example", width / 2, y, size=7.2, color=MUTED, font="Courier")
    y -= 18
    rule(canvas, 19, y, width - 19, color=AMBER)
    y -= 19
    draw_center(canvas, "TAXIQUITTUNG", width / 2, y, size=12, color=AMBER, font="Courier-Bold")
    y -= 23
    y = receipt_line(canvas, y, "Beleg", "NS-140926-0848", width, size=7.4)
    y = receipt_line(canvas, y, "Datum", "14.09.2026 08:48", width, size=7.4)
    y = receipt_line(canvas, y, "Fahrzeug", "Demo-Taxi 17", width, size=7.4)
    y -= 4
    canvas.setFillColor(PALE_AMBER)
    canvas.roundRect(14, y - 58, width - 28, 58, 4, fill=1, stroke=0)
    y -= 18
    canvas.setFillColor(AMBER)
    canvas.setFont("Courier-Bold", 7.4)
    canvas.drawString(22, y, "STRECKE")
    y -= 13
    canvas.setFillColor(INK)
    canvas.setFont("Courier", 7.15)
    canvas.drawString(22, y, "Flughafen München Terminal 2")
    y -= 12
    canvas.drawString(22, y, "nach Lumenhof Hotel München")
    y -= 12
    canvas.drawString(22, y, "52,4 km · über 50 km")
    y -= 29
    rule(canvas, 19, y, width - 19, color=HexColor("#D9C1A9"))
    y -= 20
    position = Position("Fahrtpreis inkl. Flughafenzuschlag", 13200, 19)
    y = receipt_line(canvas, y, "Fahrpreis netto", money(position.net), width, size=7.9)
    y = receipt_line(canvas, y, "USt 19 %", money(position.tax), width, size=7.9)
    y -= 4
    canvas.setFillColor(AMBER)
    canvas.setFont("Courier-Bold", 10)
    canvas.drawString(19, y, "GESAMT")
    draw_right(canvas, money(position.gross), width - 19, y, size=10, color=AMBER, font="Courier-Bold")
    y -= 23
    y = receipt_line(canvas, y, "Zahlung", "Karte · bezahlt", width, size=7.6)
    y = receipt_line(canvas, y, "Fahrgast", "Mara Winter", width, size=7.6)
    y -= 6
    draw_wrapped(canvas, "Auftraggeber: Studio Linden · Design & Web", 19, y, width - 38, size=7.2, leading=9, color=MUTED, font="Courier")
    y -= 24
    draw_wrapped(canvas, "Aussteller: Nordstern Mobilität GmbH · nordstern-mobil.example · USt-ID DE00 000 001 (ungültiger Demo-Platzhalter)", 19, y, width - 38, size=6.3, leading=8, color=MUTED, font="Courier")
    draw_footer(canvas, width, y=13, color=MUTED)
    canvas.save()


def create_hotel(path: Path) -> None:
    width, height = A4
    canvas = new_canvas(path, width, height, "Hotelrechnung LH-2026-0916-028")
    canvas.setFillColor(TEAL)
    canvas.rect(0, height - 118, width, 118, fill=1, stroke=0)
    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica-Bold", 19)
    canvas.drawString(45, height - 45, "LUMENHOF")
    canvas.setFont("Helvetica", 8.3)
    canvas.drawString(46, height - 65, "Hotel München · lumenhof.example")
    canvas.setFont("Helvetica-Bold", 23)
    canvas.drawRightString(width - 45, height - 51, "HOTELRECHNUNG")
    canvas.setFont("Helvetica", 8)
    canvas.drawRightString(width - 45, height - 72, "LH-2026-0916-028")
    y = height - 151
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica-Bold", 7.6)
    canvas.drawString(45, y, "GAST / RECHNUNGSEMPFÄNGER")
    canvas.setFillColor(INK)
    y = draw_lines(canvas, ["Mara Winter", "Studio Linden · Design & Web", "Musterufer 18 · 20457 Hamburg"], 45, y - 18, leading=12, size=8.7)
    draw_right(canvas, "Rechnungsdatum", width - 45, height - 151, size=7.5, color=MUTED)
    draw_right(canvas, "16.09.2026", width - 45, height - 167, size=9, color=INK)
    draw_right(canvas, "Aufenthalt", width - 45, height - 193, size=7.5, color=MUTED)
    draw_right(canvas, "14.09. bis 16.09.2026", width - 45, height - 209, size=9, color=INK)
    draw_right(canvas, "Zahlungsstatus", width - 45, height - 235, size=7.5, color=MUTED)
    draw_right(canvas, "Bezahlt bei Abreise · 16.09.2026", width - 45, height - 251, size=8.5, color=TEAL)

    y = height - 289
    canvas.setFillColor(PALE_TEAL)
    canvas.roundRect(45, y - 56, width - 90, 56, 8, fill=1, stroke=0)
    canvas.setFillColor(TEAL)
    canvas.setFont("Helvetica-Bold", 8.5)
    canvas.drawString(61, y - 20, HOTEL_NAME)
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(61, y - 37, HOTEL_ADDRESS + " · Deutschland")
    canvas.drawRightString(width - 61, y - 28, "Zimmer 406 · 1 Person")

    y -= 94
    columns = [("LEISTUNG", 14), ("ZEITRAUM", 267), ("NETTO", 386), ("SATZ", 445), ("BRUTTO", 490)]
    draw_table_header(canvas, 45, y, columns, width - 90, fill=PALE_TEAL, text_color=TEAL)
    y -= 36
    room = Position("Einzelzimmer · 2 Nächte", 27600, 7)
    breakfast_food = Position("Frühstück Speisen · 2 x 11,00 €", 2200, 7)
    breakfast_drinks = Position("Frühstück Getränke · 2 x 5,00 €", 1000, 19)
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8.5)
    canvas.drawString(59, y, room.label)
    canvas.setFont("Helvetica", 7.6)
    canvas.setFillColor(MUTED)
    canvas.drawString(312, y, "14.–16.09.2026")
    draw_right(canvas, money(room.net), width - 45 - 112, y, size=8.4)
    draw_right(canvas, "7 %", width - 45 - 70, y, size=8.4)
    draw_right(canvas, money(room.gross), width - 45, y, size=8.4)
    y -= 25
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8.5)
    canvas.drawString(59, y, breakfast_food.label)
    canvas.setFont("Helvetica", 7.6)
    canvas.setFillColor(MUTED)
    canvas.drawString(312, y, "15.–16.09.2026")
    draw_right(canvas, money(breakfast_food.net), width - 45 - 112, y, size=8.4)
    draw_right(canvas, "7 %", width - 45 - 70, y, size=8.4)
    draw_right(canvas, money(breakfast_food.gross), width - 45, y, size=8.4)
    y -= 25
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8.5)
    canvas.drawString(59, y, breakfast_drinks.label)
    canvas.setFont("Helvetica", 7.6)
    canvas.setFillColor(MUTED)
    canvas.drawString(312, y, "15.–16.09.2026")
    draw_right(canvas, money(breakfast_drinks.net), width - 45 - 112, y, size=8.4)
    draw_right(canvas, "19 %", width - 45 - 70, y, size=8.4)
    draw_right(canvas, money(breakfast_drinks.gross), width - 45, y, size=8.4)
    rule(canvas, 45, y - 29, width - 45)
    y -= 65
    draw_tax_summary(canvas, width - 250, y, 205, [room, breakfast_food, breakfast_drinks], accent=TEAL)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 7.6)
    canvas.drawString(45, 150, "Frühstück ist auf der Rechnung getrennt von der Übernachtung ausgewiesen.")
    canvas.drawString(45, 134, "Aussteller: Lumenhof Hotel München · lumenhof.example · USt-ID DE00 000 002 (ungültiger Demo-Platzhalter)")
    draw_footer(canvas, width)
    canvas.save()


def create_restaurant(path: Path) -> None:
    width, height = 80 * mm, 232 * mm
    canvas = new_canvas(path, width, height, "Bewirtungsbeleg WP-150926-1942")
    canvas.setFillColor(HexColor("#FCF7EF"))
    canvas.rect(0, 0, width, height, fill=1, stroke=0)
    canvas.setFillColor(PLUM)
    canvas.rect(0, height - 8, width, 8, fill=1, stroke=0)
    y = height - 28
    draw_center(canvas, "WANDELPUNKT KÜCHE", width / 2, y, size=13, color=PLUM, font="Courier-Bold")
    y -= 16
    draw_center(canvas, "Wandelpunkt Küche · wandelpunkt.example", width / 2, y, size=6.8, color=MUTED, font="Courier")
    y -= 13
    draw_center(canvas, "Isarbogen 7 · 80331 München", width / 2, y, size=7.2, color=MUTED, font="Courier")
    y -= 18
    rule(canvas, 19, y, width - 19, color=PLUM)
    y -= 21
    draw_center(canvas, "BEWIRTUNGSBELEG", width / 2, y, size=11.2, color=PLUM, font="Courier-Bold")
    y -= 23
    y = receipt_line(canvas, y, "Beleg", "WP-150926-1942", width, size=7.3)
    y = receipt_line(canvas, y, "Datum / Uhr", "15.09.2026 19:42", width, size=7.3)
    y = receipt_line(canvas, y, "Tisch", "12", width, size=7.3)
    y -= 5
    rule(canvas, 19, y, width - 19, color=HexColor("#D8C9D9"))
    y -= 19
    food = Position("Speisen · 2 Personen", 5400, 7)
    drinks = Position("Getränke · Wasser / Saft", 1400, 19)
    y = receipt_line(canvas, y, food.label, money(food.gross), width, size=7.8)
    y = receipt_line(canvas, y, drinks.label, money(drinks.gross), width, size=7.8)
    y -= 2
    rule(canvas, 19, y, width - 19, color=HexColor("#D8C9D9"))
    y -= 19
    y = receipt_line(canvas, y, "Netto Speisen / 7 %", money(food.net), width, size=7.3)
    y = receipt_line(canvas, y, "USt Speisen", money(food.tax), width, size=7.3)
    y = receipt_line(canvas, y, "Netto Getränke / 19 %", money(drinks.net), width, size=7.3)
    y = receipt_line(canvas, y, "USt Getränke", money(drinks.tax), width, size=7.3)
    y -= 3
    canvas.setFillColor(PLUM)
    canvas.setFont("Courier-Bold", 10)
    canvas.drawString(19, y, "GESAMT")
    draw_right(canvas, money(food.gross + drinks.gross), width - 19, y, size=10, color=PLUM, font="Courier-Bold")
    y -= 18
    draw_center(canvas, "Trinkgeld: nicht enthalten", width / 2, y, size=7.4, color=MUTED, font="Courier")
    y -= 26
    canvas.setFillColor(PALE_PLUM)
    canvas.roundRect(14, y - 132, width - 28, 132, 5, fill=1, stroke=0)
    y -= 19
    canvas.setFillColor(PLUM)
    canvas.setFont("Courier-Bold", 7.5)
    canvas.drawString(22, y, "BEWIRTUNGSVERMERK")
    y -= 17
    canvas.setFillColor(INK)
    canvas.setFont("Courier-Bold", 7.1)
    canvas.drawString(22, y, "Teilnehmende")
    y -= 13
    canvas.setFont("Courier", 7.1)
    canvas.drawString(22, y, "Mara Winter")
    y -= 12
    canvas.drawString(22, y, "Jonas Berg (Kunde)")
    y -= 17
    canvas.setFont("Courier-Bold", 7.1)
    canvas.drawString(22, y, "Anlass")
    y -= 13
    y = draw_wrapped(canvas, "Projektgespräch zum Kundenworkshop und zur Website-Phase", 22, y, width - 44, size=7.1, leading=10, color=INK, font="Courier")
    y -= 8
    canvas.setFont("Courier", 6.8)
    canvas.drawString(22, y, "Geschäftlicher Austausch in München")
    y -= 24
    draw_wrapped(canvas, "Aussteller: Wandelpunkt Küche · USt-ID DE00 000 003 (ungültiger Demo-Platzhalter)", 19, y, width - 38, size=6.2, leading=8, color=MUTED, font="Courier")
    draw_footer(canvas, width, y=13, color=MUTED)
    canvas.save()


def ticket_base(path: Path, title: str, subtitle: str, accent, height: float) -> Canvas:
    width = 80 * mm
    canvas = new_canvas(path, width, height, title)
    canvas.setFillColor(colors.white)
    canvas.rect(0, 0, width, height, fill=1, stroke=0)
    canvas.setFillColor(accent)
    canvas.rect(0, height - 52, width, 52, fill=1, stroke=0)
    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica-Bold", 12)
    canvas.drawString(19, height - 25, title)
    canvas.setFont("Helvetica", 7)
    canvas.drawString(19, height - 39, subtitle)
    return canvas


def draw_barcode(canvas: Canvas, x: float, y: float, width: float, height: float, seed: str, color=INK) -> None:
    canvas.setFillColor(color)
    cursor = x
    for index, char in enumerate(seed):
        value = (ord(char) * (index + 3)) % 5 + 1
        bar = 0.7 + value * 0.45
        gap = 0.8 + ((ord(char) + index) % 3) * 0.35
        if cursor + bar > x + width:
            break
        canvas.rect(cursor, y, bar, height, fill=1, stroke=0)
        cursor += bar + gap


def create_local_ticket(path: Path) -> None:
    width, height = 80 * mm, 154 * mm
    canvas = ticket_base(path, "ISARMOBIL", "Einzelfahrt · isarmobil.example", TICKET_BLUE, height)
    y = height - 79
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica-Bold", 11)
    canvas.drawString(19, y, "15.09.2026")
    draw_right(canvas, "10:06", width - 19, y, size=11, color=TICKET_BLUE, font="Helvetica-Bold")
    y -= 25
    canvas.setFont("Helvetica-Bold", 9)
    canvas.drawString(19, y, "Hotel Lumenhof")
    y -= 16
    canvas.setFont("Helvetica", 8.4)
    canvas.drawString(19, y, "nach Isarblick Innenräume")
    y -= 24
    canvas.setFillColor(PALE_BLUE)
    canvas.roundRect(14, y - 56, width - 28, 56, 6, fill=1, stroke=0)
    canvas.setFillColor(TICKET_BLUE)
    canvas.setFont("Helvetica-Bold", 7.4)
    canvas.drawString(22, y - 18, "FAHRGAST")
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(22, y - 33, "Mara Winter · Studio Linden · Design & Web")
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 6.7)
    canvas.drawString(22, y - 47, "Tarif: Einzelfahrt Innenstadt · bezahlt")
    y -= 84
    position = Position("Einzelfahrt", 935, 7)
    rule(canvas, 19, y, width - 19, color=HexColor("#C8D7E3"))
    y -= 21
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(19, y, "Netto")
    draw_right(canvas, money(position.net), width - 19, y, size=8)
    y -= 15
    canvas.drawString(19, y, "USt 7 %")
    draw_right(canvas, money(position.tax), width - 19, y, size=8)
    y -= 23
    canvas.setFillColor(TICKET_BLUE)
    canvas.setFont("Helvetica-Bold", 10)
    canvas.drawString(19, y, "GESAMT")
    draw_right(canvas, money(position.gross), width - 19, y, size=10, color=TICKET_BLUE, font="Helvetica-Bold")
    y -= 31
    draw_barcode(canvas, 19, y, width - 38, 31, "IM1509261006MW", color=TICKET_BLUE)
    y -= 14
    draw_center(canvas, "IM-150926-1006-07", width / 2, y, size=6.6, color=MUTED)
    y -= 21
    draw_wrapped(canvas, "Aussteller: IsarMobil Verkehrsbetriebe GmbH · USt-ID DE00 000 004 (ungültiger Demo-Platzhalter)", 19, y, width - 38, size=6.3, leading=8, color=MUTED)
    draw_footer(canvas, width, y=13)
    canvas.save()


def create_airport_ticket(path: Path) -> None:
    width, height = 80 * mm, 160 * mm
    canvas = ticket_base(path, "MORGENSTERN", "S-Bahn-Ticket · morgenstern-schiene.example", TEAL, height)
    y = height - 79
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica-Bold", 11)
    canvas.drawString(19, y, "16.09.2026")
    draw_right(canvas, "15:24", width - 19, y, size=11, color=TEAL, font="Helvetica-Bold")
    y -= 24
    canvas.setFont("Helvetica-Bold", 9)
    canvas.drawString(19, y, "München Zentrum")
    y -= 16
    canvas.setFont("Helvetica", 8.4)
    canvas.drawString(19, y, "zum Flughafen München")
    y -= 24
    canvas.setFillColor(PALE_TEAL)
    canvas.roundRect(14, y - 57, width - 28, 57, 6, fill=1, stroke=0)
    canvas.setFillColor(TEAL)
    canvas.setFont("Helvetica-Bold", 7.4)
    canvas.drawString(22, y - 18, "REISEHINWEIS")
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 7.8)
    canvas.drawString(22, y - 33, "Ankunft Flughafen ca. 16:06")
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 6.7)
    canvas.drawString(22, y - 47, "Anschluss: Rückflug 18:20 nach Hamburg")
    y -= 85
    position = Position("S-Bahn-Einzelfahrt", 1250, 7)
    rule(canvas, 19, y, width - 19, color=HexColor("#C1D8D4"))
    y -= 21
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(19, y, "Netto")
    draw_right(canvas, money(position.net), width - 19, y, size=8)
    y -= 15
    canvas.drawString(19, y, "USt 7 %")
    draw_right(canvas, money(position.tax), width - 19, y, size=8)
    y -= 23
    canvas.setFillColor(TEAL)
    canvas.setFont("Helvetica-Bold", 10)
    canvas.drawString(19, y, "GESAMT")
    draw_right(canvas, money(position.gross), width - 19, y, size=10, color=TEAL, font="Helvetica-Bold")
    y -= 31
    draw_barcode(canvas, 19, y, width - 38, 31, "MS1609261524MW", color=TEAL)
    y -= 14
    draw_center(canvas, "MS-160926-1524-09", width / 2, y, size=6.6, color=MUTED)
    y -= 22
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(INK)
    canvas.drawString(19, y, "Fahrgast: Mara Winter")
    y -= 13
    draw_wrapped(canvas, "Auftraggeber: Studio Linden · Design & Web", 19, y, width - 38, size=6.6, leading=8, color=MUTED)
    y -= 17
    draw_wrapped(canvas, "Aussteller: Morgenstern Schiene GmbH · USt-ID DE00 000 005 (ungültiger Demo-Platzhalter)", 19, y, width - 38, size=6.3, leading=8, color=MUTED)
    draw_footer(canvas, width, y=13)
    canvas.save()


def build_manifest() -> list[dict]:
    return [
        make_entry(
            "15-flugrechnung-hamburg-muenchen.pdf",
            "2026-09-07",
            "Muster-Luftverkehr AG",
            [Position("Hin- und Rückflug Hamburg – München", 23800, 19)],
            "2026-09-08",
            "Flug HAM–MUC am 14.09.2026 um 07:10 und Rückflug MUC–HAM am 16.09.2026 um 18:20; Rechnung vor Abflug, bezahlt.",
        ),
        make_entry(
            "16-taxiquittung-flughafen-hotel.pdf",
            "2026-09-14",
            "Nordstern Mobilität GmbH",
            [Position("Fahrt Flughafen München – Lumenhof Hotel, 52,4 km", 13200, 19)],
            "2026-09-14",
            "Airport taxi am 14.09.2026 um 08:48, Strecke ausdrücklich über 50 km, bezahlt.",
        ),
        make_entry(
            "17-hotelrechnung-lumenhof-muenchen.pdf",
            "2026-09-16",
            HOTEL_NAME,
            [
                Position("Einzelzimmer · 2 Nächte", 27600, 7),
                Position("Frühstück Speisen · 2 x 11,00 €", 2200, 7),
                Position("Frühstück Getränke · 2 x 5,00 €", 1000, 19),
            ],
            "2026-09-16",
            "Aufenthalt 14.–16.09.2026; Zimmer sowie Frühstücksspeisen und -getränke getrennt ausgewiesen, Zahlung bei Abreise.",
        ),
        make_entry(
            "18-bewirtungsbeleg-wandelpunkt-kueche.pdf",
            "2026-09-15",
            "Wandelpunkt Küche",
            [
                Position("Speisen · 2 Personen", 5400, 7),
                Position("Getränke · Wasser / Saft", 1400, 19),
            ],
            "2026-09-15",
            "Geschäftliches Abendessen am 15.09.2026; Mara Winter und Jonas Berg (Kunde), Anlass Projektgespräch zum Kundenworkshop und zur Website-Phase, kein Trinkgeld.",
        ),
        make_entry(
            "19-nahverkehrsticket-hotel-workshop.pdf",
            "2026-09-15",
            "IsarMobil Verkehrsbetriebe GmbH",
            [Position("Einzelfahrt Hotel Lumenhof – Isarblick Innenräume", 935, 7)],
            "2026-09-15",
            "Nahverkehrsticket am 15.09.2026 um 10:06 vom Hotel zum Kundenworkshop, bezahlt.",
        ),
        make_entry(
            "20-s-bahn-ticket-zum-flughafen.pdf",
            "2026-09-16",
            "Morgenstern Schiene GmbH",
            [Position("S-Bahn-Einzelfahrt München Zentrum – Flughafen", 1250, 7)],
            "2026-09-16",
            "S-Bahn-Ticket am 16.09.2026 um 15:24 zum Flughafen für den Rückflug um 18:20, bezahlt.",
        ),
    ]


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # The generator owns only these six PDFs in the travel directory.
    creators = [
        ("15-flugrechnung-hamburg-muenchen.pdf", create_flight),
        ("16-taxiquittung-flughafen-hotel.pdf", create_taxi),
        ("17-hotelrechnung-lumenhof-muenchen.pdf", create_hotel),
        ("18-bewirtungsbeleg-wandelpunkt-kueche.pdf", create_restaurant),
        ("19-nahverkehrsticket-hotel-workshop.pdf", create_local_ticket),
        ("20-s-bahn-ticket-zum-flughafen.pdf", create_airport_ticket),
    ]
    for filename, creator in creators:
        creator(OUTPUT / filename)
    with MANIFEST.open("w", encoding="utf-8") as file:
        json.dump(build_manifest(), file, ensure_ascii=False, indent=2)
        file.write("\n")
    print(f"Generated {len(creators)} PDFs in {OUTPUT}")
    print(f"Wrote manifest to {MANIFEST}")


if __name__ == "__main__":
    main()
