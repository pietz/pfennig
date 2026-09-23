#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["reportlab>=4.2,<5"]
# ///
"""Generate only Q3 2026 purchase entries 11-14 and their manifest."""
from __future__ import annotations

import json
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen.canvas import Canvas


SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parent
OUT = ROOT / "einkauf"
MANIFEST = SOURCE / "equipment-services.json"
W, H = A4
M = 46
DARK = colors.HexColor("#20242B")
MUTED = colors.HexColor("#69717C")
RECIPIENT = ["Studio Linden · Design & Web", "Mara Winter", "Kaistraße 18", "20457 Hamburg", "Deutschland"]


def money(value: str) -> int:
    return int((Decimal(value) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def tax(net: int) -> int:
    return int((Decimal(net) * Decimal("0.19")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def eur(cents: int) -> str:
    euros, rest = divmod(cents, 100)
    return f"{euros:,}".replace(",", ".") + f",{rest:02d} EUR"


def item(name: str, net: int, detail: str) -> dict:
    return {"name": name, "detail": detail, "net": net, "tax": tax(net)}


def record(filename: str, date: str, supplier: str, items: list[dict], payments: list[dict], scenario: str) -> dict:
    net = sum(x["net"] for x in items)
    vat = sum(x["tax"] for x in items)
    return {
        "filename": filename,
        "datum": date,
        "gegenpartei": supplier,
        "richtung": "ausgabe",
        "waehrung": "EUR",
        "positionen": [{"netto": x["net"], "steuersatz": 19, "steuer": x["tax"]} for x in items],
        "brutto": net + vat,
        "zahlungen": payments,
        "scenario": scenario,
    }


def text(c: Canvas, x: float, y: float, value: str, size: float = 9, color=DARK, bold=False, right=False, center=False) -> None:
    c.setFillColor(color)
    c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
    if right:
        c.drawRightString(x, y, value)
    elif center:
        c.drawCentredString(x, y, value)
    else:
        c.drawString(x, y, value)


def wrap(c: Canvas, x: float, y: float, value: str, width: float, size: float = 9, leading: float = 12, color=DARK) -> float:
    words, lines, current = value.split(), [], ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if stringWidth(candidate, "Helvetica", size) <= width:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    for line in lines:
        text(c, x, y, line, size, color)
        y -= leading
    return y


def recipient(c: Canvas, y: float, color=MUTED) -> None:
    text(c, M, y, "RECHNUNGSEMPFÄNGER", 7, color, True)
    for i, value in enumerate(RECIPIENT, 1):
        text(c, M, y - 16 - (i - 1) * 13, value, 9.2, DARK, i == 1)


def footer(c: Canvas, supplier: str, domain: str) -> None:
    c.setStrokeColor(colors.HexColor("#D6D9DE")); c.setLineWidth(.6); c.line(M, 37, W - M, 37)
    text(c, W - M, 23, f"{supplier} · {domain}", 7.2, MUTED, right=True)


def meta(c: Canvas, number: str, date: str, y: float, due: str | None = None) -> None:
    values = [("RECHNUNGSNUMMER", number), ("RECHNUNGSDATUM", date)]
    if due:
        values.append(("FÄLLIG", due))
    for i, (label, value) in enumerate(values):
        x = M + i * 135
        text(c, x, y, label, 7, MUTED, True); text(c, x, y - 13, value, 9, DARK, i == 0)


def totals(c: Canvas, items: list[dict], x: float, y: float, accent, label="GESAMT") -> None:
    net, vat = sum(x["net"] for x in items), sum(x["tax"] for x in items)
    c.setStrokeColor(colors.HexColor("#D6D9DE")); c.line(x, y + 11, W - M, y + 11)
    text(c, x, y - 7, "Nettobetrag", 9, MUTED); text(c, W - M, y - 7, eur(net), 9, right=True)
    text(c, x, y - 25, "Umsatzsteuer 19 %", 9, MUTED); text(c, W - M, y - 25, eur(vat), 9, right=True)
    c.setFillColor(accent); c.roundRect(x - 8, y - 66, W - M - x + 8, 29, 5, fill=1, stroke=0)
    text(c, x + 6, y - 55, label, 9, colors.white, True); text(c, W - M - 8, y - 55, eur(net + vat), 11, colors.white, True, right=True)


def new_pdf(path: Path, title: str) -> Canvas:
    c = Canvas(str(path), pagesize=A4); c.setTitle(title); c.setAuthor("Studio Linden"); return c


def mobile_pdf(path: Path, items: list[dict]) -> None:
    navy, orange, pale = colors.HexColor("#14253D"), colors.HexColor("#F59E42"), colors.HexColor("#F2F5F8")
    c = new_pdf(path, "Mobilfunkrechnung 11 - Nordlicht Mobilfunk")
    c.setFillColor(navy); c.rect(0, H - 153, W, 153, fill=1, stroke=0); c.setFillColor(orange); c.rect(0, H - 160, W, 7, fill=1, stroke=0)
    text(c, M, H - 54, "NORDLICHT", 21, colors.white, True); text(c, M, H - 76, "M O B I L F U N K", 8, colors.HexColor("#B9C7D7"), True)
    text(c, W - M, H - 58, "MONATSRECHNUNG", 17, colors.white, True, right=True); text(c, W - M, H - 81, "August 2026", 10, colors.HexColor("#C8D2DF"), right=True)
    meta(c, "NM-2026-0812-11", "12.08.2026", H - 193); recipient(c, H - 254)
    text(c, 330, H - 254, "VERTRAG", 7, MUTED, True); text(c, 330, H - 270, "Linden Mobil 70", 12, navy, True)
    text(c, 330, H - 288, "Leistungszeitraum 01.08. - 31.08.2026", 8.5, MUTED); text(c, 330, H - 302, "Rufnummer · 040 555 018 70", 8.5, MUTED)
    top = H - 360; c.setFillColor(pale); c.roundRect(M, top - 154, W - 2 * M, 154, 8, fill=1, stroke=0)
    text(c, M + 16, top - 24, "LEISTUNGSÜBERSICHT", 8, navy, True); text(c, M + 16, top - 49, "Leistung", 8, MUTED, True); text(c, W - M - 18, top - 49, "Netto", 8, MUTED, True, right=True)
    c.setStrokeColor(colors.HexColor("#D6DDE5")); c.line(M + 16, top - 57, W - M - 16, top - 57)
    y = top - 79
    for x in items:
        text(c, M + 16, y, x["name"], 9.2, navy, True); text(c, M + 16, y - 13, x["detail"], 7.7, MUTED); text(c, W - M - 18, y, eur(x["net"]), 9.2, navy, right=True); y -= 42
    text(c, M + 16, top - 145, "Alle Positionen mit 19 % deutscher Umsatzsteuer", 7.7, MUTED)
    totals(c, items, 310, H - 553, navy)
    c.setFillColor(colors.HexColor("#FFF4E6")); c.roundRect(M, H - 675, W - 2 * M, 57, 7, fill=1, stroke=0)
    text(c, M + 14, H - 640, "EIGENVERMERK ZUR NUTZUNG", 8, colors.HexColor("#A95A12"), True)
    text(c, M + 14, H - 656, "Betriebliche Nutzung 70 %, private Nutzung 30 %", 10, colors.HexColor("#513318"), True)
    text(c, W - M - 14, H - 656, "Zahlung eingegangen am 20.08.2026", 8, colors.HexColor("#A95A12"), right=True)
    footer(c, "Nordlicht Mobilfunk GmbH", "nordlicht-mobilfunk.example"); c.save()


def laptop_pdf(path: Path, items: list[dict]) -> None:
    ink, blue, orange = colors.HexColor("#17212B"), colors.HexColor("#1F6F8B"), colors.HexColor("#E8893A")
    light, gray = colors.HexColor("#F4F1EB"), colors.HexColor("#6B7280")
    c = new_pdf(path, "Rechnung 12 - Pixelkern StudioBook")
    c.setFillColor(ink); c.rect(0, H - 100, W, 100, fill=1, stroke=0); c.setFillColor(orange); c.rect(0, H - 108, W, 8, fill=1, stroke=0)
    text(c, M, H - 48, "PIXELKERN", 20, colors.white, True); text(c, M, H - 69, "COMPUTERHAUS KG", 8, colors.HexColor("#B6C2CC"), True)
    text(c, W - M, H - 49, "RECHNUNG", 18, colors.white, True, right=True); text(c, W - M, H - 70, "PK-260904-12", 9, colors.HexColor("#C9D2D8"), right=True)
    recipient(c, H - 147, gray); text(c, 332, H - 147, "RECHNUNGSDATEN", 7, gray, True); text(c, 332, H - 163, "04.09.2026", 10, ink, True)
    text(c, 332, H - 180, "Lieferung: 04.09.2026", 8.5, gray); text(c, 332, H - 194, "Zahlungsziel: sofort", 8.5, gray)
    c.setFillColor(light); c.roundRect(M, H - 447, W - 2 * M, 194, 10, fill=1, stroke=0)
    text(c, M + 18, H - 281, "ARTIKEL", 7.5, blue, True); text(c, M + 18, H - 307, "STUDIOBOOK 14 PRO", 17, ink, True)
    text(c, M + 18, H - 327, "Mobiler Arbeitsplatz · 14 Zoll · 16 GB · 512 GB SSD", 9, gray); text(c, M + 18, H - 350, "Artikel-Nr. PK-SB14-26", 8, gray)
    c.setFillColor(colors.white); c.roundRect(335, H - 416, 165, 92, 7, fill=1, stroke=0); c.setStrokeColor(blue); c.setLineWidth(2); c.roundRect(367, H - 373, 101, 35, 3, fill=0, stroke=1); c.line(357, H - 382, 478, H - 382); c.line(367, H - 387, 468, H - 387)
    text(c, 417, H - 401, "PK", 8, blue, True, center=True); text(c, 417, H - 426, "COMPUTERHARDWARE", 7, gray, True, center=True)
    top = H - 482; text(c, M, top, "LEISTUNG", 8, gray, True); text(c, 350, top, "MENGE", 8, gray, True, right=True); text(c, W - M, top, "NETTO", 8, gray, True, right=True)
    c.setStrokeColor(colors.HexColor("#C9CBCB")); c.line(M, top - 8, W - M, top - 8); y = top - 35
    for x in items:
        text(c, M, y, x["name"], 9.4, ink, True); text(c, M, y - 14, x["detail"], 7.8, gray); text(c, 350, y, "1", 9.4, ink, right=True); text(c, W - M, y, eur(x["net"]), 9.4, ink, right=True); y -= 44
    c.setStrokeColor(colors.HexColor("#C9CBCB")); c.line(M, y + 12, W - M, y + 12); totals(c, items, 320, y + 30, blue)
    c.setFillColor(colors.HexColor("#E9F2F5")); c.roundRect(M, H - 694, W - 2 * M, 40, 6, fill=1, stroke=0); text(c, M + 13, H - 670, "Zahlung erhalten am 08.09.2026 · Vielen Dank für Ihren Einkauf.", 8.4, blue, True)
    footer(c, "Pixelkern Computerhaus KG", "pixelkern-computer.example"); c.save()


def course_pdf(path: Path, items: list[dict]) -> None:
    purple, violet = colors.HexColor("#38265C"), colors.HexColor("#7656A6"); lavender = colors.HexColor("#F1ECF8"); warm = colors.HexColor("#FCF9F4"); gray = colors.HexColor("#6E6878")
    c = new_pdf(path, "Rechnung 13 - Lernwerk Nord Onlinekurs"); c.setFillColor(warm); c.rect(0, 0, W, H, fill=1, stroke=0); c.setFillColor(purple); c.rect(0, H - 166, W, 166, fill=1, stroke=0)
    c.setFillColor(violet); c.circle(W - 74, H - 50, 72, fill=1, stroke=0); c.setFillColor(colors.HexColor("#967BC1")); c.circle(W - 52, H - 96, 28, fill=1, stroke=0)
    text(c, M, H - 52, "LERNWERK NORD", 19, colors.white, True); text(c, M, H - 76, "BERUFLICHE WEITERBILDUNG", 8, colors.HexColor("#D9D0E8"), True); text(c, M, H - 119, "TEILNAHMEBESTÄTIGUNG", 11, colors.HexColor("#EEE9F4"), True); text(c, W - M, H - 119, "& RECHNUNG", 11, colors.white, True, right=True)
    recipient(c, H - 208, colors.HexColor("#81768F")); text(c, 332, H - 208, "RECHNUNG", 7, colors.HexColor("#81768F"), True); text(c, 332, H - 224, "LN-2026-0719-13", 9.5, purple, True); text(c, 332, H - 240, "19.07.2026", 9, gray); text(c, 332, H - 255, "Zahlung eingegangen 22.07.2026", 8, gray)
    c.setFillColor(lavender); c.roundRect(M, H - 420, W - 2 * M, 130, 12, fill=1, stroke=0); text(c, M + 18, H - 318, "ONLINEKURS", 7.5, violet, True); text(c, M + 18, H - 345, "Textkonzept und Tonalität für Webprojekte", 15, purple, True); text(c, M + 18, H - 369, "Live-Workshop am 16.07.2026 · 09:30 - 16:30 Uhr", 9, gray); text(c, M + 18, H - 388, "Referentin: Paula Seidel · 7 Unterrichtseinheiten", 9, gray)
    c.setFillColor(violet); c.roundRect(W - M - 112, H - 389, 94, 24, 12, fill=1, stroke=0); text(c, W - M - 65, H - 380, "BERUFLICH", 8, colors.white, True, center=True)
    text(c, M, H - 460, "LEISTUNG", 8, gray, True); text(c, W - M, H - 460, "NETTO", 8, gray, True, right=True); c.setStrokeColor(colors.HexColor("#D9D2E0")); c.line(M, H - 468, W - M, H - 468)
    x = items[0]; text(c, M, H - 498, x["name"], 9.8, purple, True); text(c, M, H - 515, x["detail"], 8, gray); text(c, W - M, H - 498, eur(x["net"]), 9.8, purple, right=True)
    text(c, M, H - 569, "INHALTE", 8, gray, True); text(c, M, H - 590, "01  Zielgruppenstimme", 8.5, purple); text(c, M + 153, H - 590, "02  Seitenstruktur", 8.5, purple); text(c, M + 306, H - 590, "03  Redaktionsleitfaden", 8.5, purple)
    totals(c, items, 320, H - 628, violet); footer(c, "Lernwerk Nord GmbH", "lernwerk-nord.example"); c.save()


def freelancer_pdf(path: Path, items: list[dict]) -> None:
    forest, sage = colors.HexColor("#24483C"), colors.HexColor("#9EB7A3"); cream = colors.HexColor("#F8F4EC"); charcoal = colors.HexColor("#252A27"); muted = colors.HexColor("#6B716C"); red = colors.HexColor("#A64B3C")
    c = new_pdf(path, "Rechnung 14 - Wortspur Freie Texte"); c.setFillColor(cream); c.rect(0, 0, W, H, fill=1, stroke=0); c.setFillColor(forest); c.rect(0, H - 116, W, 116, fill=1, stroke=0); c.setFillColor(sage); c.circle(W - 52, H - 58, 40, fill=1, stroke=0)
    text(c, M, H - 47, "wortspur", 27, colors.white, True); text(c, M, H - 72, "FREIE TEXTE · JANA FELD", 8, colors.HexColor("#D6E3D7"), True); text(c, W - M, H - 49, "RECHNUNG", 16, colors.white, True, right=True); text(c, W - M, H - 70, "WS-26-0910-14", 9, colors.HexColor("#D6E3D7"), right=True)
    recipient(c, H - 163, muted); text(c, 332, H - 163, "AUSGESTELLT AM", 7, muted, True); text(c, 332, H - 179, "10.09.2026", 10, charcoal, True); text(c, 332, H - 196, "Leistungszeitraum: 01. - 09.09.2026", 8.5, muted)
    text(c, M, H - 285, "Guten Tag Mara Winter,", 10, charcoal, True); wrap(c, M, H - 314, "hiermit berechne ich die redaktionelle Ausarbeitung der Website-Texte für Studio Linden · Design & Web.", W - 2 * M, 9.5, 14, charcoal)
    top = H - 385; c.setFillColor(colors.HexColor("#E8EFE8")); c.roundRect(M, top - 83, W - 2 * M, 83, 7, fill=1, stroke=0); text(c, M + 14, top - 23, "LEISTUNG", 7.5, forest, True); text(c, W - M - 14, top - 23, "NETTO", 7.5, forest, True, right=True); x = items[0]; text(c, M + 14, top - 48, x["name"], 9.4, charcoal, True); text(c, M + 14, top - 64, x["detail"], 8, muted); text(c, W - M - 14, top - 48, eur(x["net"]), 9.4, charcoal, right=True)
    totals(c, items, 320, H - 512, forest, "ZU ZAHLEN"); c.setFillColor(colors.HexColor("#F4DEDA")); c.roundRect(M, H - 636, W - 2 * M, 56, 7, fill=1, stroke=0); text(c, M + 14, H - 606, "OFFENER POSTEN", 8, red, True); text(c, M + 14, H - 622, "Fällig am 18.09.2026 · Zum Datenstand 21.09.2026 unbezahlt", 9.1, red, True)
    footer(c, "Wortspur Freie Texte", "wortspur-texte.example"); c.save()


def build() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    mobile = [item("Grundentgelt Mobilfunkvertrag", money("49.00"), "Linden Mobil 70 · August 2026"), item("Datenoption 20 GB", money("25.79"), "monatliche Zusatzoption")]
    laptop = [item("StudioBook 14 Pro", money("1149.00"), "Notebook · 14 Zoll · 16 GB · 512 GB SSD"), item("Einrichtung und Versand", money("50.00"), "sicherer Versand innerhalb Deutschlands")]
    course = [item("Onlinekurs Textkonzept und Tonalität", money("349.00"), "Live-Workshop · 16.07.2026 · 7 Unterrichtseinheiten")]
    freelancer = [item("Website-Texte für Studio Linden", money("780.00"), "Landingpage und Leistungsseiten · redaktionelle Ausarbeitung")]
    def paid(items: list[dict], date: str) -> list[dict]:
        return [{"datum": date, "betrag": sum(x["net"] + x["tax"] for x in items)}]
    records = [
        record("11-mobile.pdf", "2026-08-12", "Nordlicht Mobilfunk GmbH", mobile, paid(mobile, "2026-08-20"), "mobilfunk_bezahlt_privatanteil_prozent30"),
        record("12-laptop.pdf", "2026-09-04", "Pixelkern Computerhaus KG", laptop, paid(laptop, "2026-09-08"), "laptop_bezahlt_nutzungsdauer_jahre1"),
        record("13-course.pdf", "2026-07-19", "Lernwerk Nord GmbH", course, paid(course, "2026-07-22"), "onlinekurs_beruflich_bezahlt"),
        record("14-freelancer.pdf", "2026-09-10", "Wortspur Freie Texte", freelancer, [], "website-texte_unbezahlt_faellig_2026-09-18"),
    ]
    mobile_pdf(OUT / records[0]["filename"], mobile); laptop_pdf(OUT / records[1]["filename"], laptop); course_pdf(OUT / records[2]["filename"], course); freelancer_pdf(OUT / records[3]["filename"], freelancer)
    MANIFEST.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
