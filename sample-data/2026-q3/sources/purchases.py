#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["reportlab>=4.0,<5"]
# ///
"""Generate the fictional Q3 2026 purchase documents, entries 6 through 10, 25 and 26.

This file is intentionally self-contained. It writes the five PDFs owned by this
writer and their small JSON manifest. It does not import Pfennig or any app code.
"""

from __future__ import annotations

import json
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any

from reportlab.lib import colors
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4, A5, landscape
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parents[1]
PDF_DIR = ROOT / "einkauf"
MANIFEST_PATH = ROOT / "sources" / "purchases.json"

PROFILE = {
    "name": "Mara Winter",
    "studio": "Studio Linden · Design & Web",
    "legal": "Einzelunternehmen Mara Winter",
    "address": "Musterufer 18, 20457 Hamburg, Deutschland",
    "email": "hallo@studio-linden.example",
    "ustid": "DE000000000 (ungültiger Demo-Platzhalter)",
}


def cents(value: str) -> int:
    """Convert a decimal major-unit amount to integer cents without binary floats."""
    return int((Decimal(value) * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def tax_for(net: int, rate: int) -> int:
    return int((Decimal(net) * Decimal(rate) / Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def eur_short(amount: int) -> str:
    sign = "-" if amount < 0 else ""
    absolute = abs(amount)
    euros, remainder = divmod(absolute, 100)
    return f"{sign}{euros:,}".replace(",", ".") + f",{remainder:02d} EUR"


def usd(value: str) -> str:
    return f"{Decimal(value):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".") + " USD"


def date_de(value: str) -> str:
    year, month, day = value.split("-")
    return f"{day}.{month}.{year}"


def rgb(hex_value: str) -> colors.Color:
    return HexColor(hex_value)


def text(c: canvas.Canvas, x: float, y: float, value: str, font: str = "Helvetica", size: float = 9, color: colors.Color = colors.black) -> None:
    c.setFillColor(color)
    c.setFont(font, size)
    c.drawString(x, y, value)


def right_text(c: canvas.Canvas, x: float, y: float, value: str, font: str = "Helvetica", size: float = 9, color: colors.Color = colors.black) -> None:
    c.setFillColor(color)
    c.setFont(font, size)
    c.drawRightString(x, y, value)


def centered_text(c: canvas.Canvas, x: float, y: float, value: str, font: str = "Helvetica", size: float = 9, color: colors.Color = colors.black) -> None:
    c.setFillColor(color)
    c.setFont(font, size)
    c.drawCentredString(x, y, value)


def rule(c: canvas.Canvas, x1: float, y: float, x2: float, color: colors.Color = colors.lightgrey, width: float = 0.6) -> None:
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.line(x1, y, x2, y)


def footer(c: canvas.Canvas, width: float, label: str = "Fiktiver Musterbeleg · Nicht zur Zahlung") -> None:
    rule(c, 28, 42, width - 28, rgb("#D7D7D7"), 0.5)
    centered_text(c, width / 2, 27, label, "Helvetica", 7.2, rgb("#777777"))


def draw_summary_box(c: canvas.Canvas, x: float, y: float, width: float, net: int, tax: int, gross: int, tax_label: str = "Umsatzsteuer 19 %") -> None:
    c.setFillColor(rgb("#F5F6F7"))
    c.roundRect(x, y, width, 94, 7, fill=1, stroke=0)
    text(c, x + 15, y + 70, "NETTO", "Helvetica-Bold", 7.5, rgb("#6A6F76"))
    right_text(c, x + width - 15, y + 70, eur_short(net), "Helvetica", 9, rgb("#23262A"))
    text(c, x + 15, y + 48, tax_label.upper(), "Helvetica-Bold", 7.5, rgb("#6A6F76"))
    right_text(c, x + width - 15, y + 48, eur_short(tax), "Helvetica", 9, rgb("#23262A"))
    rule(c, x + 15, y + 35, x + width - 15, rgb("#D6D9DC"), 0.5)
    text(c, x + 15, y + 14, "GESAMT", "Helvetica-Bold", 8.5, rgb("#23262A"))
    right_text(c, x + width - 15, y + 14, eur_short(gross), "Helvetica-Bold", 12, rgb("#111111"))


def make_software(path: Path) -> None:
    width, height = A4
    c = canvas.Canvas(str(path), pagesize=A4)
    c.setTitle("Klarquell Studio Software - Rechnung KQS-260708-184")
    c.setAuthor("Klarquell Studio Software Ltd. · fictional sample")

    ink = rgb("#1E2040")
    violet = rgb("#6557D9")
    lemon = rgb("#E5F17C")
    pale = rgb("#F3F2FC")

    c.setFillColor(ink)
    c.rect(0, height - 174, width, 174, fill=1, stroke=0)
    c.setFillColor(lemon)
    c.rect(0, height - 181, width, 7, fill=1, stroke=0)
    text(c, 48, height - 63, "KLARQUELL", "Helvetica-Bold", 22, colors.white)
    text(c, 49, height - 84, "studio software / dublin", "Courier", 8.5, lemon)
    text(c, 48, height - 127, "STUDIO PRO", "Helvetica-Bold", 29, colors.white)
    text(c, 48, height - 149, "subscription invoice", "Helvetica-Oblique", 10, rgb("#D3D1F8"))
    right_text(c, width - 48, height - 57, "INVOICE", "Courier-Bold", 9, lemon)
    right_text(c, width - 48, height - 83, "KQS-260708-184", "Courier-Bold", 10, colors.white)
    right_text(c, width - 48, height - 103, "08 JUL 2026", "Courier", 9, rgb("#D3D1F8"))

    text(c, 48, height - 226, "FROM", "Courier-Bold", 8, violet)
    text(c, 48, height - 244, "Klarquell Studio Software Ltd.", "Helvetica-Bold", 10, ink)
    text(c, 48, height - 258, "14 Fern Quay / Dublin D02 X000 / Ireland", "Helvetica", 8.5, rgb("#4E5060"))
    text(c, 48, height - 271, "billing@klarquell.example", "Helvetica", 8.5, rgb("#4E5060"))
    text(c, 48, height - 284, "VAT ID: IE0000000D · invalid demo placeholder", "Helvetica", 7.4, rgb("#777A87"))

    text(c, 342, height - 226, "BILL TO", "Courier-Bold", 8, violet)
    text(c, 342, height - 244, PROFILE["studio"], "Helvetica-Bold", 9.5, ink)
    text(c, 342, height - 258, PROFILE["legal"], "Helvetica", 8.5, rgb("#4E5060"))
    text(c, 342, height - 271, "Musterufer 18", "Helvetica", 8.5, rgb("#4E5060"))
    text(c, 342, height - 284, "20457 Hamburg, Deutschland", "Helvetica", 8.5, rgb("#4E5060"))
    text(c, 342, height - 297, PROFILE["email"], "Helvetica", 7.6, rgb("#4E5060"))
    text(c, 342, height - 310, "USt-ID: DE000000000 · invalid demo placeholder", "Helvetica", 7.2, rgb("#777A87"))

    y = height - 342
    c.setFillColor(pale)
    c.roundRect(48, y - 74, width - 96, 74, 6, fill=1, stroke=0)
    text(c, 65, y - 23, "SERVICE", "Courier-Bold", 7.5, violet)
    text(c, 65, y - 43, "Klarquell Studio Pro", "Helvetica-Bold", 11, ink)
    text(c, 65, y - 59, "Monatszugang · 01.07.2026 - 31.07.2026", "Helvetica", 8.7, rgb("#4E5060"))
    right_text(c, width - 65, y - 43, "1 × 42,00 EUR", "Courier-Bold", 10, ink)
    right_text(c, width - 65, y - 59, "NET", "Courier", 7.5, rgb("#66697A"))

    net, tax, gross = 4200, 0, 4200
    draw_summary_box(c, 318, height - 532, width - 366, net, tax, gross, "Umsatzsteuer 0 %")
    c.setFillColor(lemon)
    c.roundRect(48, height - 502, 242, 64, 7, fill=1, stroke=0)
    text(c, 65, height - 462, "REVERSE CHARGE", "Courier-Bold", 8.2, ink)
    text(c, 65, height - 480, "VAT not charged. Customer accounts for", "Helvetica", 8.2, ink)
    text(c, 65, height - 493, "VAT under Section 13b German VAT Act.", "Helvetica", 8.2, ink)

    text(c, 48, height - 588, "PAYMENT", "Courier-Bold", 8, violet)
    text(c, 48, height - 606, "Paid by bank transfer on 10.07.2026 · 42,00 EUR", "Helvetica", 9.2, ink)
    text(c, 48, height - 631, "Thank you for using a fictional service in this sample dataset.", "Helvetica-Oblique", 8.4, rgb("#66697A"))
    footer(c, width)
    c.save()


def make_us_tool(path: Path) -> None:
    width, height = A4
    c = canvas.Canvas(str(path), pagesize=A4)
    c.setTitle("Northstar Dev Tools - Invoice NST-2026-08-20-4421")
    c.setAuthor("Northstar Dev Tools Inc. · fictional sample")

    navy = rgb("#10242B")
    green = rgb("#31D38A")
    pale = rgb("#EEF6F2")
    grey = rgb("#5D6A70")
    line = rgb("#CBD8D3")

    c.setFillColor(navy)
    c.rect(0, height - 174, width, 174, fill=1, stroke=0)
    c.setFillColor(green)
    c.rect(0, height - 180, width, 6, fill=1, stroke=0)
    text(c, 48, height - 58, "NORTHSTAR // DEV TOOLS", "Courier-Bold", 18, colors.white)
    text(c, 49, height - 80, "billing export / us-west", "Courier", 8.5, green)
    text(c, 48, height - 126, "INVOICE", "Courier-Bold", 27, colors.white)
    right_text(c, width - 48, height - 59, "NST-2026-08-20-4421", "Courier-Bold", 10, green)
    right_text(c, width - 48, height - 82, "ISSUED 2026-08-20", "Courier", 8.8, colors.white)
    right_text(c, width - 48, height - 101, "USD / NET 14", "Courier", 8.8, rgb("#B9CEC5"))

    text(c, 48, height - 226, "VENDOR", "Courier-Bold", 8, green)
    text(c, 48, height - 244, "Northstar Dev Tools Inc.", "Courier-Bold", 10, navy)
    text(c, 48, height - 258, "500 Market Loop / Portland, OR 97035 / USA", "Courier", 8.2, grey)
    text(c, 48, height - 271, "billing@northstar.example", "Courier", 8.2, grey)
    text(c, 48, height - 284, "US tax ID: DEMO-0000000 · invalid demo placeholder", "Courier", 7.3, grey)

    text(c, 353, height - 226, "CUSTOMER", "Courier-Bold", 8, green)
    text(c, 353, height - 244, PROFILE["studio"], "Courier-Bold", 8.7, navy)
    text(c, 353, height - 258, PROFILE["legal"], "Courier", 8.0, grey)
    text(c, 353, height - 271, "Musterufer 18", "Courier", 8.0, grey)
    text(c, 353, height - 284, "20457 Hamburg, Deutschland", "Courier", 8.0, grey)
    text(c, 353, height - 297, PROFILE["email"], "Courier", 7.0, grey)
    text(c, 353, height - 310, "DE000000000 · invalid demo placeholder", "Courier", 6.8, grey)

    y = height - 335
    c.setFillColor(pale)
    c.roundRect(48, y - 138, width - 96, 138, 4, fill=1, stroke=0)
    text(c, 65, y - 25, "LINE ITEMS", "Courier-Bold", 8, navy)
    text(c, 65, y - 49, "ITEM", "Courier-Bold", 7.5, grey)
    right_text(c, 402, y - 49, "QTY", "Courier-Bold", 7.5, grey)
    right_text(c, width - 65, y - 49, "AMOUNT USD", "Courier-Bold", 7.5, grey)
    rule(c, 65, y - 58, width - 65, line, 0.6)
    text(c, 65, y - 84, "ForgeLint Team License / AUG 2026", "Courier", 8.7, navy)
    right_text(c, 402, y - 84, "1", "Courier", 8.7, navy)
    right_text(c, width - 65, y - 84, "64.00", "Courier", 8.7, navy)
    text(c, 65, y - 109, "Build Cache 500 GB / AUG 2026", "Courier", 8.7, navy)
    right_text(c, 402, y - 109, "1", "Courier", 8.7, navy)
    right_text(c, width - 65, y - 109, "22.40", "Courier", 8.7, navy)
    rule(c, 65, y - 120, width - 65, line, 0.6)
    text(c, 65, y - 133, "US sales tax", "Courier", 8, grey)
    right_text(c, width - 65, y - 133, "0.00", "Courier", 8, navy)

    # Original currency total and the actual card debit are intentionally separate.
    total_y = height - 568
    c.setFillColor(navy)
    c.roundRect(48, total_y - 106, width - 96, 106, 5, fill=1, stroke=0)
    text(c, 66, total_y - 29, "ORIGINAL TOTAL", "Courier-Bold", 8, green)
    text(c, 66, total_y - 51, "86.40 USD", "Courier-Bold", 19, colors.white)
    text(c, 66, total_y - 75, "No US sales tax charged", "Courier", 8.5, rgb("#B9CEC5"))
    right_text(c, width - 66, total_y - 29, "CARD DEBIT", "Courier-Bold", 8, green)
    right_text(c, width - 66, total_y - 52, "79,92 EUR", "Courier-Bold", 19, colors.white)
    right_text(c, width - 66, total_y - 76, "2026-08-21 · actual amount", "Courier", 8.5, rgb("#B9CEC5"))

    c.setFillColor(green)
    c.roundRect(48, height - 713, width - 96, 53, 4, fill=1, stroke=0)
    text(c, 65, height - 682, "REVERSE CHARGE / § 13b UStG", "Courier-Bold", 8.8, navy)
    text(c, 65, height - 699, "Customer accounts for German VAT. Invoice contains no VAT amount.", "Courier", 8.2, navy)
    text(c, 65, height - 711, "EUR bookkeeping amount: 86.40 USD × 0.925 = 79.92 EUR", "Courier", 8.2, navy)
    footer(c, width)
    c.save()


def make_hosting(path: Path) -> None:
    width, height = A4
    c = canvas.Canvas(str(path), pagesize=A4)
    c.setTitle("Hafenblick Hosting GmbH - Rechnung HBH-2026-0715-089")
    c.setAuthor("Hafenblick Hosting GmbH · fictional sample")

    blue = rgb("#195A88")
    cyan = rgb("#36C6D7")
    pale = rgb("#EDF6F8")
    slate = rgb("#42515C")
    light_line = rgb("#C8DDE2")

    c.setFillColor(blue)
    c.rect(0, 0, 118, height, fill=1, stroke=0)
    c.setFillColor(cyan)
    c.rect(0, height - 16, 118, 16, fill=1, stroke=0)
    c.saveState()
    c.translate(55, 130)
    c.rotate(90)
    text(c, 0, 0, "HAFENBLICK HOSTING", "Helvetica-Bold", 19, colors.white)
    text(c, 0, -20, "secure web infrastructure", "Helvetica", 8.5, rgb("#BDEDF0"))
    c.restoreState()
    text(c, 37, 62, "HBH / 2026", "Courier-Bold", 8, rgb("#BDEDF0"))
    text(c, 10, 47, "support@hafenblick.example", "Courier", 5.4, rgb("#BDEDF0"))

    x = 153
    text(c, x, height - 76, "RECHNUNG", "Helvetica-Bold", 28, blue)
    text(c, x, height - 99, "Hosting und Domainverwaltung", "Helvetica", 10.5, slate)
    right_text(c, width - 46, height - 73, "HBH-2026-0715-089", "Courier-Bold", 9, blue)
    right_text(c, width - 46, height - 91, "15.07.2026", "Courier", 8.5, slate)
    right_text(c, width - 46, height - 107, "Kundennummer SL-20457", "Courier", 8, slate)

    text(c, x, height - 154, "ANBIETER", "Helvetica-Bold", 7.8, cyan)
    text(c, x, height - 170, "Hafenblick Hosting GmbH", "Helvetica-Bold", 9.5, blue)
    text(c, x, height - 184, "Speicherwerder 7 · 20457 Hamburg", "Helvetica", 8.3, slate)
    text(c, x, height - 197, "rechnung@hafenblick.example", "Helvetica", 8.3, slate)
    text(c, x, height - 210, "USt-ID DE000000001 · ungültiger Demo-Platzhalter", "Helvetica", 7.2, slate)

    text(c, 375, height - 154, "RECHNUNGSEMPFÄNGER", "Helvetica-Bold", 7.8, cyan)
    text(c, 375, height - 170, PROFILE["studio"], "Helvetica-Bold", 8.7, blue)
    text(c, 375, height - 184, PROFILE["legal"], "Helvetica", 8.1, slate)
    text(c, 375, height - 197, "Musterufer 18", "Helvetica", 8.1, slate)
    text(c, 375, height - 210, "20457 Hamburg, Deutschland", "Helvetica", 8.1, slate)
    text(c, 375, height - 223, PROFILE["email"], "Helvetica", 7.3, slate)
    text(c, 375, height - 236, "DE000000000 · ungültiger Demo-Platzhalter", "Helvetica", 6.8, slate)

    table_top = height - 267
    c.setFillColor(pale)
    c.roundRect(x, table_top - 181, width - x - 46, 181, 7, fill=1, stroke=0)
    text(c, x + 17, table_top - 27, "LEISTUNG", "Helvetica-Bold", 7.7, blue)
    text(c, x + 17, table_top - 43, "ZEITRAUM", "Helvetica-Bold", 7.7, blue)
    right_text(c, width - 63, table_top - 35, "NETTO", "Helvetica-Bold", 7.7, blue)
    rule(c, x + 17, table_top - 55, width - 63, light_line, 0.7)
    text(c, x + 17, table_top - 83, "Managed Webhosting / Linden-Plan", "Helvetica-Bold", 9.5, slate)
    text(c, x + 17, table_top - 99, "01.07.2026 - 31.07.2026", "Helvetica", 8.4, slate)
    right_text(c, width - 63, table_top - 91, "28,00 EUR", "Courier", 9.2, blue)
    text(c, x + 17, table_top - 132, "Domainverwaltung / studio-linden.example", "Helvetica-Bold", 9.5, slate)
    text(c, x + 17, table_top - 148, "01.07.2026 - 31.07.2026", "Helvetica", 8.4, slate)
    right_text(c, width - 63, table_top - 140, "6,00 EUR", "Courier", 9.2, blue)
    rule(c, x + 17, table_top - 158, width - 63, light_line, 0.7)
    text(c, x + 17, table_top - 173, "Vertragsmonat Juli 2026", "Helvetica-Oblique", 7.5, slate)

    net, tax, gross = 3400, 646, 4046
    box_y = height - 552
    c.setStrokeColor(light_line)
    c.setLineWidth(0.8)
    c.roundRect(x, box_y - 107, width - x - 46, 107, 7, fill=0, stroke=1)
    text(c, x + 17, box_y - 27, "NETTO", "Helvetica-Bold", 7.5, slate)
    right_text(c, width - 63, box_y - 27, "34,00 EUR", "Courier", 9.2, slate)
    text(c, x + 17, box_y - 49, "UMSATZSTEUER 19 %", "Helvetica-Bold", 7.5, slate)
    right_text(c, width - 63, box_y - 49, "6,46 EUR", "Courier", 9.2, slate)
    rule(c, x + 17, box_y - 62, width - 63, light_line, 0.6)
    text(c, x + 17, box_y - 86, "ZU ZAHLEN", "Helvetica-Bold", 9, blue)
    right_text(c, width - 63, box_y - 86, "40,46 EUR", "Courier-Bold", 13, blue)

    c.setFillColor(cyan)
    c.roundRect(x, height - 700, width - x - 46, 47, 7, fill=1, stroke=0)
    text(c, x + 17, height - 680, "ZAHLUNG ERHALTEN", "Helvetica-Bold", 8, blue)
    text(c, x + 17, height - 696, "Kartenzahlung am 18.07.2026 · Vielen Dank.", "Helvetica", 8.5, blue)
    footer(c, width)
    c.save()


def make_receipt(path: Path) -> None:
    width, height = 80 * mm, 235 * mm
    c = canvas.Canvas(str(path), pagesize=(width, height))
    c.setTitle("Papier und Punkt Fachhandel - Kassenbon PP-040826")
    c.setAuthor("Papier & Punkt Fachhandel · fictional sample")

    ink = rgb("#242424")
    muted = rgb("#666666")
    coral = rgb("#D95E4B")
    c.setFillColor(colors.white)
    c.rect(0, 0, width, height, fill=1, stroke=0)
    centered_text(c, width / 2, height - 34, "PAPIER & PUNKT", "Courier-Bold", 13, ink)
    centered_text(c, width / 2, height - 48, "FACHHANDEL FÜR BÜROBEDARF", "Courier", 6.8, muted)
    centered_text(c, width / 2, height - 65, "Stiftgasse 12 · 20095 Hamburg", "Courier", 7, ink)
    centered_text(c, width / 2, height - 77, "kasse@papierpunkt.example", "Courier", 6.8, muted)
    rule(c, 19, height - 94, width - 19, ink, 0.7)

    text(c, 19, height - 111, "KASSENBON", "Courier-Bold", 8, coral)
    right_text(c, width - 19, height - 111, "PP-040826", "Courier", 7.5, ink)
    text(c, 19, height - 126, "04.08.2026  16:42", "Courier", 7.5, ink)
    text(c, 19, height - 141, "Kasse 02 · Beleg 08426", "Courier", 7.2, muted)
    centered_text(c, width / 2, height - 153, "KUNDE: Studio Linden · Design & Web", "Courier", 6.5, ink)
    centered_text(c, width / 2, height - 165, "Einzelunternehmen Mara Winter", "Courier", 6.4, ink)
    centered_text(c, width / 2, height - 177, "Musterufer 18 · 20457 Hamburg", "Courier", 6.4, ink)
    centered_text(c, width / 2, height - 189, "Deutschland · hallo@studio-linden.example", "Courier", 5.7, muted)
    rule(c, 19, height - 202, width - 19, ink, 0.7)

    y = height - 222
    text(c, 19, y, "ARTIKEL", "Courier-Bold", 6.8, muted)
    right_text(c, width - 19, y, "BRUTTO", "Courier-Bold", 6.8, muted)
    y -= 17
    text(c, 19, y, "2 x DRUCKERPAPIER A4", "Courier", 7.4, ink)
    right_text(c, width - 19, y, "16,42", "Courier", 7.4, ink)
    text(c, 30, y - 11, "Recycling 80 g/m2", "Courier", 6.7, muted)
    y -= 31
    text(c, 19, y, "2 x NOTIZBLOCK A5", "Courier", 7.4, ink)
    right_text(c, width - 19, y, "7,62", "Courier", 7.4, ink)
    text(c, 30, y - 11, "kariert, 80 Blatt", "Courier", 6.7, muted)
    y -= 31
    text(c, 19, y, "3 x GELSTIFT SCHWARZ", "Courier", 7.4, ink)
    right_text(c, width - 19, y, "5,35", "Courier", 7.4, ink)
    text(c, 30, y - 11, "0,5 mm", "Courier", 6.7, muted)
    y -= 24
    rule(c, 19, y, width - 19, ink, 0.7)
    y -= 20
    text(c, 19, y, "NETTO", "Courier", 7.6, muted)
    right_text(c, width - 19, y, "24,70 EUR", "Courier", 7.6, ink)
    y -= 15
    text(c, 19, y, "MWST 19 %", "Courier", 7.6, muted)
    right_text(c, width - 19, y, "4,69 EUR", "Courier", 7.6, ink)
    y -= 22
    c.setFillColor(coral)
    c.roundRect(16, y - 27, width - 32, 34, 2, fill=1, stroke=0)
    text(c, 25, y - 7, "GESAMT", "Courier-Bold", 9, colors.white)
    right_text(c, width - 25, y - 7, "29,39 EUR", "Courier-Bold", 11, colors.white)
    y -= 49
    centered_text(c, width / 2, y, "ZAHLUNG: KARTE · 04.08.2026", "Courier", 7.2, ink)
    centered_text(c, width / 2, y - 16, "USt-ID DE000000003 · ungültiger Demo-Platzhalter", "Courier", 5.9, muted)
    centered_text(c, width / 2, y - 31, "Vielen Dank für Ihren Einkauf.", "Courier", 7.2, ink)
    footer(c, width, "Fiktiver Musterbeleg · Nicht zur Zahlung")
    c.save()


def make_print_shop(path: Path) -> None:
    width, height = A5
    c = canvas.Canvas(str(path), pagesize=A5)
    c.setTitle("Druckwerk Nord OHG - Rechnung DN-26-0907-311")
    c.setAuthor("Druckwerk Nord OHG · fictional sample")

    cream = rgb("#F7F0E5")
    wine = rgb("#8C2448")
    orange = rgb("#E47B3A")
    ink = rgb("#2E2828")
    muted = rgb("#756B67")
    light = rgb("#E8D9D0")

    c.setFillColor(cream)
    c.rect(0, 0, width, height, fill=1, stroke=0)
    c.setFillColor(wine)
    c.rect(0, 0, 72, height, fill=1, stroke=0)
    c.saveState()
    c.translate(36, 44)
    c.rotate(90)
    text(c, 0, 0, "DRUCKWERK NORD", "Times-Bold", 17, cream)
    text(c, 0, -18, "PRINT / PAPER / FORM", "Courier", 7, rgb("#F3C9A9"))
    c.restoreState()
    c.setFillColor(orange)
    c.circle(36, height - 43, 13, fill=1, stroke=0)
    centered_text(c, 36, height - 46, "DN", "Helvetica-Bold", 8, cream)

    x = 96
    text(c, x, height - 55, "RECHNUNG", "Times-Bold", 27, wine)
    text(c, x, height - 76, "Portfolio-Karten / Studio Linden", "Times-Italic", 10, muted)
    right_text(c, width - 28, height - 49, "DN-26-0907-311", "Courier-Bold", 8, wine)
    right_text(c, width - 28, height - 64, "07. September 2026", "Courier", 7.8, muted)

    rule(c, x, height - 108, width - 28, light, 1)
    text(c, x, height - 132, "VON", "Courier-Bold", 7.3, orange)
    text(c, x, height - 148, "Druckwerk Nord OHG", "Times-Bold", 9.4, ink)
    text(c, x, height - 162, "Hafenstraße 71 · 22767 Hamburg", "Times-Roman", 8.1, muted)
    text(c, x, height - 175, "rechnung@druckwerk-nord.example", "Times-Roman", 8.1, muted)
    text(c, x, height - 188, "USt-ID DE000000002 · ungültiger Demo-Platzhalter", "Times-Roman", 6.8, muted)

    text(c, 282, height - 132, "AN", "Courier-Bold", 7.3, orange)
    text(c, 282, height - 148, PROFILE["studio"], "Times-Bold", 8.4, ink)
    text(c, 282, height - 162, PROFILE["legal"], "Times-Roman", 7.6, muted)
    text(c, 282, height - 175, "Musterufer 18", "Times-Roman", 7.6, muted)
    text(c, 282, height - 188, "20457 Hamburg, Deutschland", "Times-Roman", 7.1, muted)
    text(c, 282, height - 201, PROFILE["email"], "Times-Roman", 6.2, muted)
    text(c, 282, height - 214, "DE000000000 · ungültiger Demo-Platzhalter", "Times-Roman", 6.3, muted)

    top = height - 231
    c.setFillColor(colors.white)
    c.roundRect(x, top - 161, width - x - 28, 161, 5, fill=1, stroke=0)
    text(c, x + 14, top - 23, "AUSFÜHRUNG", "Courier-Bold", 7.2, wine)
    text(c, x + 14, top - 39, "DETAIL", "Courier-Bold", 7.2, muted)
    right_text(c, width - 42, top - 39, "NETTO", "Courier-Bold", 7.2, muted)
    rule(c, x + 14, top - 49, width - 42, light, 0.7)
    text(c, x + 14, top - 72, "Portfolio-Karten, 350 g/m2", "Times-Bold", 9, ink)
    text(c, x + 14, top - 87, "100 Stück · matt · 4/4-farbig", "Times-Roman", 8, muted)
    right_text(c, width - 42, top - 79, "42,00 EUR", "Courier", 8.6, ink)
    text(c, x + 14, top - 108, "Datencheck und Druckfreigabe", "Times-Bold", 9, ink)
    text(c, x + 14, top - 123, "finaler PDF-Check", "Times-Roman", 8, muted)
    right_text(c, width - 42, top - 115, "12,00 EUR", "Courier", 8.6, ink)
    text(c, x + 14, top - 143, "Abholung im Atelier", "Times-Bold", 9, ink)
    right_text(c, width - 42, top - 143, "6,00 EUR", "Courier", 8.6, ink)

    c.setFillColor(rgb("#F0D2D9"))
    c.roundRect(x, 114, width - x - 28, 80, 5, fill=1, stroke=0)
    text(c, x + 14, 175, "SUMME", "Courier-Bold", 7.4, wine)
    text(c, x + 14, 157, "Netto", "Times-Roman", 8.5, ink)
    right_text(c, width - 42, 157, "60,00 EUR", "Courier", 8.7, ink)
    text(c, x + 14, 143, "Umsatzsteuer 19 %", "Times-Roman", 8.5, ink)
    right_text(c, width - 42, 143, "11,40 EUR", "Courier", 8.7, ink)
    right_text(c, width - 42, 122, "71,40 EUR", "Courier-Bold", 13, wine)
    text(c, x + 14, 124, "ZU ZAHLEN", "Courier-Bold", 7.6, wine)

    c.setFillColor(orange)
    c.roundRect(x, 78, width - x - 28, 28, 4, fill=1, stroke=0)
    centered_text(c, x + (width - x - 28) / 2, 88, "BEZAHLT · Karte 10.09.2026", "Courier-Bold", 8, cream)
    footer(c, width)
    c.save()


def make_domain(path: Path) -> None:
    width, height = landscape(A4)
    c = canvas.Canvas(str(path), pagesize=(width, height))
    c.setTitle("Wellenfeld Domainservice - Rechnung WF-260703-25")
    c.setAuthor("Wellenfeld Domainservice GmbH · fictional sample")

    navy = rgb("#172B3A")
    orange = rgb("#F28A45")
    mint = rgb("#D9F1E7")
    pale = rgb("#F5F7F6")
    muted = rgb("#52616B")
    line = rgb("#C7D5D1")

    c.setFillColor(pale)
    c.rect(0, 0, width, height, fill=1, stroke=0)
    c.setFillColor(navy)
    c.rect(0, height - 143, width, 143, fill=1, stroke=0)
    c.setFillColor(orange)
    c.rect(0, height - 151, width, 8, fill=1, stroke=0)
    text(c, 52, height - 54, "WELLENFELD", "Helvetica-Bold", 20, colors.white)
    text(c, 54, height - 76, "DOMAIN SERVICE / HAMBURG", "Courier", 8, mint)
    text(c, 52, height - 116, "DOMAIN RENEWAL", "Helvetica-Bold", 27, colors.white)
    right_text(c, width - 52, height - 52, "RECHNUNG WF-260703-25", "Courier-Bold", 9, orange)
    right_text(c, width - 52, height - 72, "03.07.2026", "Courier", 8.5, colors.white)
    right_text(c, width - 52, height - 91, "Fälligkeit: sofort", "Courier", 8.5, mint)

    text(c, 52, height - 188, "ANBIETER", "Helvetica-Bold", 7.8, orange)
    text(c, 52, height - 205, "Wellenfeld Domainservice GmbH", "Helvetica-Bold", 9.5, navy)
    text(c, 52, height - 219, "Kaimauer 9 · 22767 Hamburg · Deutschland", "Helvetica", 8.2, muted)
    text(c, 52, height - 232, "abrechnung@wellenfeld.example", "Helvetica", 8.2, muted)
    text(c, 52, height - 245, "USt-ID DE000000004 · ungültiger Demo-Platzhalter", "Helvetica", 7.1, muted)

    text(c, 472, height - 188, "RECHNUNGSEMPFÄNGER", "Helvetica-Bold", 7.8, orange)
    text(c, 472, height - 205, PROFILE["studio"], "Helvetica-Bold", 9.2, navy)
    text(c, 472, height - 219, PROFILE["legal"], "Helvetica", 8.2, muted)
    text(c, 472, height - 232, "Musterufer 18 · 20457 Hamburg, Deutschland", "Helvetica", 8.2, muted)
    text(c, 472, height - 245, PROFILE["email"], "Helvetica", 7.5, muted)
    text(c, 472, height - 258, "DE000000000 · ungültiger Demo-Platzhalter", "Helvetica", 6.9, muted)

    c.setFillColor(mint)
    c.roundRect(52, 245, width - 104, 78, 8, fill=1, stroke=0)
    text(c, 71, 298, "DOMAIN", "Courier-Bold", 7.7, orange)
    text(c, 71, 271, "studio-linden.example", "Helvetica-Bold", 19, navy)
    text(c, 71, 254, "Verlängerung der Domainverwaltung", "Helvetica", 8.2, muted)
    text(c, 465, 298, "LAUFZEIT", "Courier-Bold", 7.7, orange)
    text(c, 465, 274, "01.08.2026 - 31.07.2027", "Courier-Bold", 10, navy)
    text(c, 465, 254, "12 Monate · automatische Erneuerung aus", "Helvetica", 7.8, muted)

    text(c, 52, 211, "LEISTUNG", "Helvetica-Bold", 7.8, orange)
    right_text(c, 540, 211, "BETRAG", "Helvetica-Bold", 7.8, orange)
    rule(c, 52, 201, width - 52, line, 0.7)
    text(c, 52, 178, "Domainverwaltung / studio-linden.example", "Helvetica-Bold", 9.5, navy)
    text(c, 52, 163, "Jahresverlängerung · Laufzeit 01.08.2026 - 31.07.2027", "Helvetica", 8.1, muted)
    right_text(c, 540, 171, "18,00 EUR", "Courier", 9.3, navy)
    rule(c, 52, 145, width - 52, line, 0.7)

    c.setFillColor(colors.white)
    c.roundRect(573, 91, 216, 99, 7, fill=1, stroke=0)
    text(c, 591, 168, "NETTO", "Helvetica-Bold", 7.4, muted)
    right_text(c, 771, 168, "18,00 EUR", "Courier", 9, navy)
    text(c, 591, 146, "UMSATZSTEUER 19 %", "Helvetica-Bold", 7.4, muted)
    right_text(c, 771, 146, "3,42 EUR", "Courier", 9, navy)
    rule(c, 591, 133, 771, line, 0.6)
    text(c, 591, 108, "GESAMT", "Helvetica-Bold", 8.6, navy)
    right_text(c, 771, 108, "21,42 EUR", "Courier-Bold", 12, orange)

    c.setFillColor(orange)
    c.roundRect(52, 99, 455, 48, 6, fill=1, stroke=0)
    text(c, 69, 128, "ZAHLUNG ERHALTEN", "Courier-Bold", 8.1, colors.white)
    text(c, 69, 111, "Überweisung am 05.07.2026 · 21,42 EUR", "Helvetica", 8.7, colors.white)
    footer(c, width)
    c.save()


def make_insurance(path: Path) -> None:
    width, height = A4
    c = canvas.Canvas(str(path), pagesize=A4)
    c.setTitle("Sicherpfad Berufsschutz - Beitragsrechnung SP-260701-26")
    c.setAuthor("Sicherpfad Berufsschutz AG · fictional sample")

    green = rgb("#28463E")
    red = rgb("#B44642")
    pale = rgb("#F1F2ED")
    cream = rgb("#FBFAF5")
    muted = rgb("#5C6661")
    line = rgb("#CCD3CC")

    c.setFillColor(cream)
    c.rect(0, 0, width, height, fill=1, stroke=0)
    c.setFillColor(pale)
    c.rect(0, 0, 144, height, fill=1, stroke=0)
    c.setFillColor(green)
    c.rect(0, height - 126, width, 126, fill=1, stroke=0)
    c.setFillColor(red)
    c.rect(0, height - 134, width, 8, fill=1, stroke=0)

    text(c, 43, height - 64, "SICHERPFAD", "Times-Bold", 19, colors.white)
    text(c, 44, height - 85, "BERUFSSCHUTZ", "Times-Italic", 10, rgb("#DCE8DF"))
    text(c, 43, 95, "BERUFSHAFTPFLICHT", "Courier-Bold", 7.5, green)
    text(c, 43, 78, "Jahresbeitrag", "Times-Roman", 8.5, muted)
    text(c, 43, 59, "01.07.2026", "Courier-Bold", 8.5, green)
    text(c, 43, 46, "bis 30.06.2027", "Courier", 8, muted)
    text(c, 43, 27, "POLICE SP-26-00426", "Courier", 6.8, muted)

    text(c, 178, height - 57, "BEITRAGSRECHNUNG", "Times-Bold", 25, colors.white)
    text(c, 178, height - 81, "Berufshaftpflicht für selbstständige Kreativleistungen", "Times-Italic", 9.5, rgb("#DCE8DF"))
    right_text(c, width - 45, height - 57, "SP-260701-26", "Courier-Bold", 9, colors.white)
    right_text(c, width - 45, height - 78, "01.07.2026", "Courier", 8.5, rgb("#DCE8DF"))

    text(c, 178, height - 169, "VERSICHERER", "Helvetica-Bold", 7.8, red)
    text(c, 178, height - 187, "Sicherpfad Berufsschutz AG", "Times-Bold", 10, green)
    text(c, 178, height - 202, "Rathaustor 6 · 60311 Frankfurt am Main", "Times-Roman", 8.2, muted)
    text(c, 178, height - 215, "service@sicherpfad.example", "Times-Roman", 8.2, muted)
    text(c, 178, height - 228, "Steuernummer DEMO-0000000 · ungültiger Demo-Platzhalter", "Times-Roman", 7.1, muted)

    text(c, 399, height - 169, "VERSICHERUNGSNEHMERIN", "Helvetica-Bold", 7.8, red)
    text(c, 399, height - 187, PROFILE["studio"], "Times-Bold", 9.2, green)
    text(c, 399, height - 201, PROFILE["legal"], "Times-Roman", 8.2, muted)
    text(c, 399, height - 214, "Musterufer 18 · 20457 Hamburg, Deutschland", "Times-Roman", 8.2, muted)
    text(c, 399, height - 227, PROFILE["email"], "Times-Roman", 7.4, muted)
    text(c, 399, height - 240, "DE000000000 · ungültiger Demo-Platzhalter", "Times-Roman", 6.8, muted)

    top = height - 287
    c.setFillColor(colors.white)
    c.roundRect(178, top - 155, width - 223, 155, 5, fill=1, stroke=0)
    text(c, 196, top - 26, "BEITRAG", "Courier-Bold", 7.6, red)
    text(c, 196, top - 47, "Berufshaftpflicht · Jahreszeitraum 01.07.2026 - 30.06.2027", "Times-Bold", 9.4, green)
    rule(c, 196, top - 61, width - 63, line, 0.7)
    text(c, 196, top - 87, "Versicherungsbeitrag", "Times-Roman", 9, muted)
    right_text(c, width - 63, top - 87, "480,00 EUR", "Courier", 9.3, green)
    text(c, 196, top - 112, "Versicherungssteuer 19 %", "Times-Roman", 9, muted)
    right_text(c, width - 63, top - 112, "91,20 EUR", "Courier", 9.3, green)
    text(c, 196, top - 128, "keine Umsatzsteuer", "Times-Italic", 7.8, red)
    rule(c, 196, top - 137, width - 63, line, 0.7)
    text(c, 196, top - 145, "JAHRESBEITRAG / ZAHLBETRAG", "Courier-Bold", 8.2, green)
    right_text(c, width - 63, top - 145, "571,20 EUR", "Courier-Bold", 12, red)

    c.setFillColor(rgb("#F7E4E1"))
    c.roundRect(178, 194, width - 223, 68, 6, fill=1, stroke=0)
    text(c, 196, 239, "STEUERHINWEIS", "Courier-Bold", 7.8, red)
    text(c, 196, 222, "Die Versicherungssteuer ist keine Umsatzsteuer.", "Times-Bold", 9, green)
    text(c, 196, 207, "Umsatzsteuer: 0,00 EUR · steuerfrei · kein Vorsteuerbetrag.", "Times-Roman", 8.3, muted)

    c.setFillColor(green)
    c.roundRect(178, 126, width - 223, 43, 6, fill=1, stroke=0)
    text(c, 196, 151, "BEZAHLT", "Courier-Bold", 8.3, colors.white)
    text(c, 196, 135, "Überweisung am 01.07.2026 · 571,20 EUR", "Helvetica", 8.7, colors.white)
    footer(c, width)
    c.save()


RECORDS: list[dict[str, Any]] = [
    {
        "filename": "06-klarquell-studio-pro-2026-07-08.pdf",
        "datum": "2026-07-08",
        "gegenpartei": "Klarquell Studio Software Ltd.",
        "richtung": "ausgabe",
        "waehrung": "EUR",
        "positionen": [{"netto": 4200, "steuersatz": 19, "steuer": 0}],
        "brutto": 4200,
        "zahlungen": [{"datum": "2026-07-10", "betrag": 4200}],
        "scenario": "Irischer Designsoftware-Abobezug, Reverse Charge nach § 13b UStG, im Juli bezahlt.",
        "steuerbehandlung": "reverse_charge",
    },
    {
        "filename": "07-northstar-dev-tools-2026-08-20.pdf",
        "datum": "2026-08-20",
        "gegenpartei": "Northstar Dev Tools Inc.",
        "richtung": "ausgabe",
        "waehrung": "USD",
        "originalbetrag": "86.40",
        "originalwaehrung": "USD",
        "originalpositionen": [
            {"beschreibung": "ForgeLint Team License / AUG 2026", "betrag": "64.00"},
            {"beschreibung": "Build Cache 500 GB / AUG 2026", "betrag": "22.40"},
        ],
        "originalsumme": "86.40 USD",
        "karteneinzug": {"datum": "2026-08-21", "betrag": 7992, "waehrung": "EUR"},
        "umrechnungsrelation": "86.40 USD × 0.925 = 79.92 EUR",
        "positionen": [{"netto": 7992, "steuersatz": 19, "steuer": 0}],
        "brutto": 7992,
        "zahlungen": [{"datum": "2026-08-21", "betrag": 7992}],
        "scenario": "US-Entwicklerwerkzeug ohne US-Umsatzsteuer, Reverse Charge, tatsächlicher EUR-Karteneinzug am 21.08.2026.",
        "steuerbehandlung": "reverse_charge",
    },
    {
        "filename": "08-hafenblick-hosting-2026-07-15.pdf",
        "datum": "2026-07-15",
        "gegenpartei": "Hafenblick Hosting GmbH",
        "richtung": "ausgabe",
        "waehrung": "EUR",
        "positionen": [
            {"netto": 2800, "steuersatz": 19, "steuer": 532},
            {"netto": 600, "steuersatz": 19, "steuer": 114},
        ],
        "brutto": 4046,
        "zahlungen": [{"datum": "2026-07-18", "betrag": 4046}],
        "scenario": "Deutscher Hosting- und Domainbezug mit 19 % Umsatzsteuer, im Juli bezahlt.",
        "steuerbehandlung": "inland",
    },
    {
        "filename": "09-papier-punkt-kassenbon-2026-08-04.pdf",
        "datum": "2026-08-04",
        "gegenpartei": "Papier & Punkt Fachhandel",
        "richtung": "ausgabe",
        "waehrung": "EUR",
        "positionen": [{"netto": 2470, "steuersatz": 19, "steuer": 469}],
        "brutto": 2939,
        "zahlungen": [{"datum": "2026-08-04", "betrag": 2939}],
        "scenario": "Schmaler deutscher Kassenbon für Büromaterial und Druckerpapier, 19 % Umsatzsteuer, bezahlt.",
        "steuerbehandlung": "inland",
    },
    {
        "filename": "10-druckwerk-nord-portfolio-karten-2026-09-07.pdf",
        "datum": "2026-09-07",
        "gegenpartei": "Druckwerk Nord OHG",
        "richtung": "ausgabe",
        "waehrung": "EUR",
        "positionen": [
            {"netto": 4200, "steuersatz": 19, "steuer": 798},
            {"netto": 1200, "steuersatz": 19, "steuer": 228},
            {"netto": 600, "steuersatz": 19, "steuer": 114},
        ],
        "brutto": 7140,
        "zahlungen": [{"datum": "2026-09-10", "betrag": 7140}],
        "scenario": "Deutsche Druckerei für Portfolio-Karten mit 19 % Umsatzsteuer, im September bezahlt.",
        "steuerbehandlung": "inland",
    },
    {
        "filename": "25-wellenfeld-domain-renewal-2026-07-03.pdf",
        "datum": "2026-07-03",
        "gegenpartei": "Wellenfeld Domainservice GmbH",
        "richtung": "ausgabe",
        "waehrung": "EUR",
        "positionen": [{"netto": 1800, "steuersatz": 19, "steuer": 342}],
        "brutto": 2142,
        "zahlungen": [{"datum": "2026-07-05", "betrag": 2142}],
        "scenario": "Deutscher Domainprovider, Jahresverlängerung im Juli, 19 % Umsatzsteuer, bezahlt.",
        "steuerbehandlung": "inland",
    },
    {
        "filename": "26-sicherpfad-berufsschutz-2026-07-01.pdf",
        "datum": "2026-07-01",
        "gegenpartei": "Sicherpfad Berufsschutz AG",
        "richtung": "ausgabe",
        "waehrung": "EUR",
        "positionen": [{"netto": 57120, "steuersatz": 0, "steuer": 0}],
        "brutto": 57120,
        "zahlungen": [{"datum": "2026-07-01", "betrag": 57120}],
        "scenario": "Jahresbeitrag Berufshaftpflicht Juli 2026 bis Juni 2027, Versicherungssteuer 19 % klar als Nicht-Umsatzsteuer, steuerfrei gebucht, im Juli bezahlt.",
        "steuerbehandlung": "steuerfrei",
    },
]


def manifest_record(record: dict[str, Any]) -> dict[str, Any]:
    keys = [
        "filename", "datum", "gegenpartei", "richtung", "waehrung", "originalbetrag",
        "originalwaehrung", "originalpositionen", "originalsumme", "karteneinzug",
        "umrechnungsrelation", "positionen", "brutto", "zahlungen", "scenario",
    ]
    return {key: record[key] for key in keys if key in record}


def validate_records() -> None:
    owned_prefixes = ("06-", "07-", "08-", "09-", "10-", "25-", "26-")
    for record in RECORDS:
        assert record["filename"].startswith(owned_prefixes)
        assert "2026-07-01" <= record["datum"] <= "2026-09-21"
        net = sum(position["netto"] for position in record["positionen"])
        tax = sum(position["steuer"] for position in record["positionen"])
        assert net + tax == record["brutto"], record["filename"]
        for position in record["positionen"]:
            if record["steuerbehandlung"] == "reverse_charge" or position["steuersatz"] == 0:
                assert position["steuer"] == 0
            else:
                assert position["steuer"] == tax_for(position["netto"], position["steuersatz"])
        if record["steuerbehandlung"] == "reverse_charge":
            assert all(position["steuersatz"] in (19,) and position["steuer"] == 0 for position in record["positionen"])
        if record["steuerbehandlung"] == "steuerfrei":
            assert all(position["steuersatz"] == 0 and position["steuer"] == 0 for position in record["positionen"])
        assert sum(payment["betrag"] for payment in record["zahlungen"]) == record["brutto"]
    usd_record = RECORDS[1]
    assert cents(usd_record["originalbetrag"]) == 8640
    assert Decimal(usd_record["originalbetrag"]) * Decimal("0.925") == Decimal("79.92")
    assert usd_record["karteneinzug"]["betrag"] == usd_record["brutto"]


def main() -> None:
    validate_records()
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    makers = {
        RECORDS[0]["filename"]: make_software,
        RECORDS[1]["filename"]: make_us_tool,
        RECORDS[2]["filename"]: make_hosting,
        RECORDS[3]["filename"]: make_receipt,
        RECORDS[4]["filename"]: make_print_shop,
        RECORDS[5]["filename"]: make_domain,
        RECORDS[6]["filename"]: make_insurance,
    }
    for record in RECORDS:
        makers[record["filename"]](PDF_DIR / record["filename"])
    MANIFEST_PATH.write_text(
        json.dumps([manifest_record(record) for record in RECORDS], ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Generated {len(RECORDS)} PDFs in {PDF_DIR}")
    print(f"Wrote manifest {MANIFEST_PATH}")


if __name__ == "__main__":
    main()
