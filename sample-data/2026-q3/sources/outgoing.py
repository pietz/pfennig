# /// script
# requires-python = ">=3.13"
# dependencies = ["reportlab>=4.2,<5"]
# ///

from decimal import Decimal, ROUND_HALF_UP
import json
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas


DATA_DIR = Path(__file__).resolve().parents[1]
OUT_DIR = DATA_DIR / "ausgang"
MANIFEST_PATH = DATA_DIR / "sources" / "outgoing.json"
PAGE_WIDTH, PAGE_HEIGHT = A4
INK = HexColor("#172234")
MUTED = HexColor("#617084")
ACCENT = HexColor("#2B7A78")
PALE_ACCENT = HexColor("#EAF4F2")
PALE_BLUE = HexColor("#F2F5F9")
RULE = HexColor("#D9E0E8")
WHITE = colors.white


def euro(cents: int) -> str:
    sign = "-" if cents < 0 else ""
    absolute = abs(cents)
    whole = f"{absolute // 100:,}".replace(",", ".")
    return f"{sign}{whole},{absolute % 100:02d} €"


def tax_for(netto: int, rate: int) -> int:
    value = Decimal(netto) * Decimal(rate) / Decimal(100)
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def german_date(value: str) -> str:
    year, month, day = value.split("-")
    return f"{day}.{month}.{year}"


def wrap_lines(text: str, font_name: str, font_size: float, width: float) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if current and stringWidth(candidate, font_name, font_size) > width:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines or [""]


def draw_wrapped(c: canvas.Canvas, text: str, x: float, y: float, width: float, font_name: str, font_size: float, leading: float, color=INK) -> float:
    c.setFont(font_name, font_size)
    c.setFillColor(color)
    lines = wrap_lines(text, font_name, font_size, width)
    for line in lines:
        c.drawString(x, y, line)
        y -= leading
    return y


def draw_right_wrapped(c: canvas.Canvas, text: str, right: float, y: float, width: float, font_name: str, font_size: float, leading: float, color=INK) -> float:
    c.setFont(font_name, font_size)
    c.setFillColor(color)
    lines = wrap_lines(text, font_name, font_size, width)
    for line in lines:
        c.drawRightString(right, y, line)
        y -= leading
    return y


def draw_label(c: canvas.Canvas, text: str, x: float, y: float, color=MUTED) -> None:
    c.setFillColor(color)
    c.setFont("Helvetica-Bold", 7.2)
    c.drawString(x, y, text.upper())


def draw_invoice(doc: dict) -> None:
    path = OUT_DIR / doc["filename"]
    pdf = canvas.Canvas(str(path), pagesize=A4, pageCompression=1, invariant=1)
    pdf.setTitle(doc["title"] + " " + doc["invoice_number"])
    pdf.setAuthor("Studio Linden · Design & Web")
    pdf.setSubject("Fiktiver Musterbeleg · Nicht zur Zahlung")

    for item in doc["items"]:
        item["steuer"] = tax_for(item["netto"], item["steuersatz"])
        item["brutto"] = item["netto"] + item["steuer"]

    netto_total = sum(item["netto"] for item in doc["items"])
    tax_total = sum(item["steuer"] for item in doc["items"])
    brutto_total = netto_total + tax_total
    assert netto_total == doc["netto_total"]
    assert tax_total == doc["tax_total"]
    assert brutto_total == doc["brutto"]

    margin = 46
    content_width = PAGE_WIDTH - 2 * margin

    # Header: a compact editorial wordmark and the complete fictional sender identity.
    pdf.setFillColor(ACCENT)
    pdf.roundRect(margin, PAGE_HEIGHT - 95, 8, 48, 4, fill=1, stroke=0)
    pdf.setFillColor(INK)
    pdf.setFont("Helvetica-Bold", 16)
    pdf.drawString(margin + 18, PAGE_HEIGHT - 58, "STUDIO LINDEN")
    pdf.setFillColor(ACCENT)
    pdf.setFont("Helvetica", 8.5)
    pdf.drawString(margin + 19, PAGE_HEIGHT - 76, "Design & Web")

    sender_x = 214
    sender_y = PAGE_HEIGHT - 51
    pdf.setFillColor(MUTED)
    pdf.setFont("Helvetica", 7.2)
    pdf.drawString(sender_x, sender_y, "Einzelunternehmen Mara Winter")
    pdf.drawString(sender_x, sender_y - 11, "Musterufer 18 · 20457 Hamburg · Deutschland")
    pdf.drawString(sender_x, sender_y - 22, "hallo@studio-linden.example")
    pdf.setFont("Helvetica", 6.8)
    pdf.drawString(sender_x, sender_y - 33, "USt-ID (Demo, ungültig): DE000000000")

    pdf.setFillColor(INK)
    pdf.setFont("Helvetica-Bold", 7.5)
    pdf.drawRightString(PAGE_WIDTH - margin, PAGE_HEIGHT - 50, doc["direction_label"])
    pdf.setFillColor(MUTED)
    pdf.setFont("Helvetica", 7.2)
    pdf.drawRightString(PAGE_WIDTH - margin, PAGE_HEIGHT - 63, "Q3 / 2026")

    # Recipient and document metadata card.
    card_top = PAGE_HEIGHT - 115
    card_height = 100
    card_bottom = card_top - card_height
    pdf.setFillColor(PALE_BLUE)
    pdf.roundRect(margin, card_bottom, content_width, card_height, 8, fill=1, stroke=0)
    pdf.setStrokeColor(RULE)
    pdf.line(334, card_bottom + 14, 334, card_top - 14)

    draw_label(pdf, "Rechnung an", margin + 16, card_top - 19)
    recipient_y = card_top - 39
    pdf.setFillColor(INK)
    pdf.setFont("Helvetica-Bold", 10)
    pdf.drawString(margin + 16, recipient_y, doc["recipient"][0])
    pdf.setFillColor(INK)
    pdf.setFont("Helvetica", 8.5)
    recipient_y -= 14
    for line in doc["recipient"][1:]:
        pdf.drawString(margin + 16, recipient_y, line)
        recipient_y -= 12

    meta_x = 352
    draw_label(pdf, "Rechnungsdaten", meta_x, card_top - 19)
    meta_y = card_top - 37
    pdf.setFont("Helvetica", 7.7)
    for label, value in doc["metadata"]:
        pdf.setFillColor(MUTED)
        pdf.drawString(meta_x, meta_y, label)
        pdf.setFillColor(INK)
        pdf.setFont("Helvetica-Bold", 7.7)
        pdf.drawRightString(PAGE_WIDTH - margin - 16, meta_y, value)
        pdf.setFont("Helvetica", 7.7)
        meta_y -= 14

    # Title and compact description.
    title_y = card_bottom - 40
    pdf.setFillColor(INK)
    pdf.setFont("Helvetica-Bold", 22)
    pdf.drawString(margin, title_y, doc["title"])
    pdf.setFillColor(ACCENT)
    pdf.setFont("Helvetica", 9.3)
    pdf.drawString(margin, title_y - 18, doc["subtitle"])
    pdf.setStrokeColor(RULE)
    pdf.line(margin, title_y - 31, PAGE_WIDTH - margin, title_y - 31)

    # Item table.
    table_top = title_y - 52
    col_widths = [194, 43, 72, 58, 65, 71]
    col_x = [margin]
    for width in col_widths[:-1]:
        col_x.append(col_x[-1] + width)
    header_height = 25
    row_height = 36
    table_bottom = table_top - header_height - row_height * len(doc["items"])
    pdf.setFillColor(INK)
    pdf.roundRect(margin, table_top - header_height, content_width, header_height, 5, fill=1, stroke=0)
    headers = ["Leistung", "Menge", "Netto", "Satz", "Steuer", "Brutto"]
    pdf.setFillColor(WHITE)
    pdf.setFont("Helvetica-Bold", 7.2)
    for index, header in enumerate(headers):
        x = col_x[index] + 9
        if index >= 2:
            pdf.drawRightString(col_x[index] + col_widths[index] - 8, table_top - 16, header)
        else:
            pdf.drawString(x, table_top - 16, header)

    for index, item in enumerate(doc["items"]):
        row_top = table_top - header_height - index * row_height
        row_bottom = row_top - row_height
        if index % 2 == 0:
            pdf.setFillColor(HexColor("#FAFBFC"))
            pdf.rect(margin, row_bottom, content_width, row_height, fill=1, stroke=0)
        pdf.setStrokeColor(RULE)
        pdf.line(margin, row_bottom, PAGE_WIDTH - margin, row_bottom)

        description_lines = wrap_lines(item["description"], "Helvetica", 8.1, col_widths[0] - 18)
        pdf.setFillColor(INK)
        pdf.setFont("Helvetica", 8.1)
        pdf.drawString(margin + 9, row_top - 15, description_lines[0])
        if len(description_lines) > 1:
            pdf.setFillColor(MUTED)
            pdf.setFont("Helvetica", 7.2)
            pdf.drawString(margin + 9, row_top - 27, description_lines[1])

        values = [
            item["menge"],
            euro(item["netto"]),
            f"{item['steuersatz']} %" if item["steuersatz"] else "-",
            euro(item["steuer"]),
            euro(item["brutto"]),
        ]
        for value_index, value in enumerate(values, start=1):
            right = col_x[value_index] + col_widths[value_index] - 8
            pdf.setFillColor(INK)
            pdf.setFont("Helvetica", 7.8)
            pdf.drawRightString(right, row_top - 20, value)

    # Totals box.
    totals_top = table_bottom - 14
    totals_height = 70
    totals_bottom = totals_top - totals_height
    pdf.setFillColor(PALE_ACCENT if doc["reverse_charge"] else PALE_BLUE)
    pdf.roundRect(margin, totals_bottom, content_width, totals_height, 7, fill=1, stroke=0)
    pdf.setFillColor(MUTED)
    pdf.setFont("Helvetica", 8)
    label_net = "Netto-Stornobetrag" if doc["is_cancellation"] else "Netto"
    label_total = "Erstattungsbetrag" if doc["is_cancellation"] else "Rechnungsbetrag"
    pdf.drawString(margin + 16, totals_top - 19, label_net)
    pdf.drawRightString(PAGE_WIDTH - margin - 16, totals_top - 19, euro(netto_total))
    pdf.drawString(margin + 16, totals_top - 35, "Umsatzsteuer 19 %" if not doc["reverse_charge"] else "Umsatzsteuer")
    pdf.drawRightString(PAGE_WIDTH - margin - 16, totals_top - 35, euro(tax_total))
    pdf.setStrokeColor(RULE)
    pdf.line(margin + 16, totals_top - 43, PAGE_WIDTH - margin - 16, totals_top - 43)
    pdf.setFillColor(INK)
    pdf.setFont("Helvetica-Bold", 11.5)
    pdf.drawString(margin + 16, totals_top - 60, label_total)
    pdf.drawRightString(PAGE_WIDTH - margin - 16, totals_top - 60, euro(brutto_total))

    # Notes box with legal/accounting context, kept separate from the payment status.
    notes_top = totals_bottom - 13
    note_lines: list[str] = []
    for note in doc["notes"]:
        note_lines.extend(wrap_lines(note, "Helvetica", 8.1, content_width - 32))
    notes_height = 31 + 11 * len(note_lines)
    notes_bottom = notes_top - notes_height
    pdf.setFillColor(WHITE)
    pdf.setStrokeColor(RULE)
    pdf.roundRect(margin, notes_bottom, content_width, notes_height, 7, fill=1, stroke=1)
    draw_label(pdf, "Hinweise", margin + 16, notes_top - 17)
    note_y = notes_top - 34
    pdf.setFillColor(INK)
    pdf.setFont("Helvetica", 8.1)
    for line in note_lines:
        pdf.drawString(margin + 16, note_y, line)
        note_y -= 11

    # Payment status panel.
    payment_top = notes_bottom - 12
    payment_height = 49
    payment_bottom = payment_top - payment_height
    pdf.setFillColor(PALE_ACCENT)
    pdf.roundRect(margin, payment_bottom, content_width, payment_height, 7, fill=1, stroke=0)
    draw_label(pdf, "Zahlungsstand", margin + 16, payment_top - 17, ACCENT)
    pdf.setFillColor(INK)
    pdf.setFont("Helvetica-Bold", 9)
    pdf.drawString(margin + 16, payment_top - 35, doc["payment_status"])

    # Footer and quiet sample marker.
    pdf.setStrokeColor(RULE)
    pdf.line(margin, 43, PAGE_WIDTH - margin, 43)
    pdf.setFillColor(MUTED)
    pdf.setFont("Helvetica", 6.8)
    pdf.drawString(margin, 29, "Studio Linden · Mara Winter · Musterufer 18 · 20457 Hamburg")
    pdf.drawRightString(PAGE_WIDTH - margin, 29, "Fiktiver Musterbeleg · Nicht zur Zahlung")
    pdf.showPage()
    pdf.save()


documents = [
    {
        "filename": "01_2026-07-17_SL-2026-071_elbbogen-keramik.pdf",
        "title": "Rechnung",
        "direction_label": "AUSGANGSRECHNUNG",
        "invoice_number": "SL-2026-071",
        "date": "2026-07-17",
        "recipient": [
            "Elbbogen Keramik",
            "z. Hd. Johanna Reimers",
            "Große Bergstraße 126",
            "22767 Hamburg",
            "Deutschland",
        ],
        "metadata": [
            ("Rechnungsnummer", "SL-2026-071"),
            ("Rechnungsdatum", "17.07.2026"),
            ("Leistungszeitraum", "01.07. bis 17.07.2026"),
        ],
        "subtitle": "Markenauftritt für Elbbogen Keramik",
        "items": [
            {"description": "Markenstrategie und visuelle Leitidee", "menge": "1 Paket", "netto": 120000, "steuersatz": 19},
            {"description": "Gestaltung der Basiselemente und Übergabe", "menge": "1 Paket", "netto": 80000, "steuersatz": 19},
            {"description": "Zusätzliche Markenanwendungsrunde", "menge": "1 Paket", "netto": 40000, "steuersatz": 19},
        ],
        "netto_total": 240000,
        "tax_total": 45600,
        "brutto": 285600,
        "reverse_charge": False,
        "is_cancellation": False,
        "notes": [
            "Die Leistung wurde im Juli 2026 erbracht und mit 19 % deutscher Umsatzsteuer abgerechnet.",
        ],
        "payment_status": "Zahlbar bis 31.07.2026",
        "manifest_scenario": "Markenauftritt für Elbbogen Keramik; Zielzahlung im Juli.",
        "payment_manifest": [{"datum": "2026-07-28", "betrag": 285600}],
        "payment_after_import": [],
    },
    {
        "filename": "02_2026-08-20_SL-2026-082_isarblick-phase-1.pdf",
        "title": "Rechnung",
        "direction_label": "AUSGANGSRECHNUNG",
        "invoice_number": "SL-2026-082",
        "date": "2026-08-20",
        "recipient": [
            "Isarblick Innenräume",
            "z. Hd. Jonas Berg",
            "Lindwurmstraße 88",
            "80337 München",
            "Deutschland",
        ],
        "metadata": [
            ("Rechnungsnummer", "SL-2026-082"),
            ("Rechnungsdatum", "20.08.2026"),
            ("Leistungszeitraum", "03.08. bis 20.08.2026"),
        ],
        "subtitle": "Website-Projektphase 1 · Konzept und UI",
        "items": [
            {"description": "Website-Konzept und Seitenstruktur, Phase 1", "menge": "1 Phase", "netto": 210000, "steuersatz": 19},
            {"description": "UI-Entwurf und Komponenten, Phase 1", "menge": "1 Phase", "netto": 110000, "steuersatz": 19},
        ],
        "netto_total": 320000,
        "tax_total": 60800,
        "brutto": 380800,
        "reverse_charge": False,
        "is_cancellation": False,
        "notes": [
            "Eigenständige abgeschlossene Teilleistung; keine Vorauszahlung.",
            "Die spätere Projektphase wird separat abgerechnet und ist nicht Bestandteil dieser Rechnung.",
        ],
        "payment_status": "Zahlbar bis 03.09.2026",
        "manifest_scenario": "Abgeschlossene erste Website-Projektphase für Isarblick Innenräume, München; eigenständige Teilleistung ohne Vorauszahlung, Zielzahlung im August.",
        "payment_manifest": [{"datum": "2026-08-31", "betrag": 380800}],
        "payment_after_import": [],
    },
    {
        "filename": "03_2026-09-21_SL-2026-093_isarblick-phase-2.pdf",
        "title": "Rechnung",
        "direction_label": "AUSGANGSRECHNUNG",
        "invoice_number": "SL-2026-093",
        "date": "2026-09-21",
        "recipient": [
            "Isarblick Innenräume",
            "z. Hd. Jonas Berg",
            "Lindwurmstraße 88",
            "80337 München",
            "Deutschland",
        ],
        "metadata": [
            ("Rechnungsnummer", "SL-2026-093"),
            ("Rechnungsdatum", "21.09.2026"),
            ("Leistungszeitraum", "15.09. bis 21.09.2026"),
        ],
        "subtitle": "Website-Projektphase 2 · Umsetzung und Übergabe",
        "items": [
            {"description": "Website-Umsetzung und responsive Komponenten, Phase 2", "menge": "1 Phase", "netto": 250000, "steuersatz": 19},
            {"description": "Content-Integration und Übergabe, Phase 2", "menge": "1 Phase", "netto": 130000, "steuersatz": 19},
        ],
        "netto_total": 380000,
        "tax_total": 72200,
        "brutto": 452200,
        "reverse_charge": False,
        "is_cancellation": False,
        "notes": [
            "Nur Phase 2 abgerechnet. Phase 1 wurde mit Rechnung SL-2026-082 vom 20.08.2026 abgerechnet.",
            "Die erste Projektphase wird hier nicht erneut summiert. Leistungsbesprechung beim Kundenworkshop am 15.09.2026 in München.",
        ],
        "payment_status": "Offen am Datenstand 21.09.2026 · fällig am 05.10.2026",
        "manifest_scenario": "Abgeschlossene zweite Website-Projektphase für denselben Münchner Kunden; nur Phase 2 abgerechnet, am Datenstand 21.09. offen, Fälligkeit nach dem Datenstand.",
        "payment_manifest": [],
        "payment_after_import": [],
    },
    {
        "filename": "04_2026-09-18_SL-2026-094_alpenfokus.pdf",
        "title": "Rechnung",
        "direction_label": "AUSGANGSRECHNUNG",
        "invoice_number": "SL-2026-094",
        "date": "2026-09-18",
        "recipient": [
            "Alpenfokus Bürogestaltung",
            "z. Hd. Nora Leitner",
            "Mariahilfer Straße 44/5",
            "1070 Wien",
            "Österreich",
        ],
        "metadata": [
            ("Rechnungsnummer", "SL-2026-094"),
            ("Rechnungsdatum", "18.09.2026"),
            ("Leistungszeitraum", "07.09. bis 18.09.2026"),
        ],
        "subtitle": "Designleistung für Bürogestaltung",
        "items": [
            {"description": "Designsystem für Büroplanung", "menge": "1 Paket", "netto": 115000, "steuersatz": 0},
            {"description": "Präsentationsvorlage und Übergabe", "menge": "1 Paket", "netto": 60000, "steuersatz": 0},
        ],
        "netto_total": 175000,
        "tax_total": 0,
        "brutto": 175000,
        "reverse_charge": True,
        "is_cancellation": False,
        "notes": [
            "Steuerschuldnerschaft des Leistungsempfängers (Reverse Charge). Keine deutsche Umsatzsteuer ausgewiesen.",
            "USt-ID des Leistungsempfängers: ATU00000000 (Demo, ungültig). Die Kennung ist ein ausdrücklich ungültiger Musterplatzhalter.",
        ],
        "payment_status": "Zahlbar bis 02.10.2026",
        "manifest_scenario": "Designleistung an Alpenfokus Bürogestaltung, Österreich; B2B Reverse Charge, Zielzahlung im September.",
        "payment_manifest": [{"datum": "2026-09-21", "betrag": 175000}],
        "payment_after_import": [],
    },
    {
        "filename": "05_2026-08-10_SL-2026-081_elbbogen-teil-storno.pdf",
        "title": "Teil-Stornorechnung",
        "direction_label": "AUSGANG · STORNO",
        "invoice_number": "SL-2026-081",
        "date": "2026-08-10",
        "recipient": [
            "Elbbogen Keramik",
            "z. Hd. Johanna Reimers",
            "Große Bergstraße 126",
            "22767 Hamburg",
            "Deutschland",
        ],
        "metadata": [
            ("Stornonummer", "SL-2026-081"),
            ("Stornodatum", "10.08.2026"),
            ("Bezug", "SL-2026-071 vom 17.07.2026"),
        ],
        "subtitle": "Teil-Storno zur Markenrechnung SL-2026-071",
        "items": [
            {"description": "Nicht realisierte Markenanwendungsrunde, Teil-Storno zu SL-2026-071", "menge": "1 Position", "netto": -40000, "steuersatz": 19},
        ],
        "netto_total": -40000,
        "tax_total": -7600,
        "brutto": -47600,
        "reverse_charge": False,
        "is_cancellation": True,
        "notes": [
            "Teil-Storno zur Rechnung SL-2026-071 vom 17.07.2026; storniert wird ausschließlich die dort ausgewiesene zusätzliche Markenanwendungsrunde.",
            "Diese Teil-Stornorechnung ist keine Gutschrift im Sinne einer Abrechnung durch den Leistungsempfänger.",
        ],
        "payment_status": "Erstattet am 18.08.2026 · Rückzahlung an Elbbogen Keramik 476,00 €",
        "manifest_scenario": "Teil-Stornorechnung zur Juli-Markenrechnung SL-2026-071; negative Beträge für eine Position, tatsächliche Erstattung im August, keine Gutschrift durch den Leistungsempfänger.",
        "payment_manifest": [{"datum": "2026-08-18", "betrag": -47600}],
        "payment_after_import": [{"datum": "2026-08-18", "betrag": -47600}],
    },
    {
        "filename": "21_2026-07-24_SL-2026-072_nordkante-maintenance-july.pdf",
        "title": "Rechnung",
        "direction_label": "AUSGANGSRECHNUNG",
        "invoice_number": "SL-2026-072",
        "date": "2026-07-24",
        "recipient": [
            "Nordkante Verlag GmbH",
            "z. Hd. Maja Krüger",
            "Poolstraße 8",
            "20355 Hamburg",
            "Deutschland",
        ],
        "metadata": [
            ("Rechnungsnummer", "SL-2026-072"),
            ("Rechnungsdatum", "24.07.2026"),
            ("Leistungszeitraum", "01.07. bis 24.07.2026"),
        ],
        "subtitle": "Website-Wartung · Juli 2026",
        "items": [
            {"description": "Technische Pflege und Sicherheitsupdates, Juli", "menge": "1 Monat", "netto": 58000, "steuersatz": 19},
            {"description": "Performance-Check und Kurzreport", "menge": "1 Paket", "netto": 24000, "steuersatz": 19},
        ],
        "netto_total": 82000,
        "tax_total": 15580,
        "brutto": 97580,
        "reverse_charge": False,
        "is_cancellation": False,
        "notes": [
            "Website-Wartung für den laufenden Monatsbetrieb einschließlich technischer Pflege und Kurzreport.",
        ],
        "payment_status": "Zahlbar bis 07.08.2026",
        "manifest_scenario": "Website-Wartung für Nordkante Verlag GmbH im Juli; Zielzahlung Anfang August.",
        "payment_manifest": [{"datum": "2026-08-05", "betrag": 97580}],
        "payment_after_import": [],
    },
    {
        "filename": "22_2026-08-24_SL-2026-083_nordkante-maintenance-august.pdf",
        "title": "Rechnung",
        "direction_label": "AUSGANGSRECHNUNG",
        "invoice_number": "SL-2026-083",
        "date": "2026-08-24",
        "recipient": [
            "Nordkante Verlag GmbH",
            "z. Hd. Maja Krüger",
            "Poolstraße 8",
            "20355 Hamburg",
            "Deutschland",
        ],
        "metadata": [
            ("Rechnungsnummer", "SL-2026-083"),
            ("Rechnungsdatum", "24.08.2026"),
            ("Leistungszeitraum", "01.08. bis 24.08.2026"),
        ],
        "subtitle": "Website-Wartung · August 2026",
        "items": [
            {"description": "Technische Pflege und Sicherheitsupdates, August", "menge": "1 Monat", "netto": 62000, "steuersatz": 19},
            {"description": "Inhaltsanpassungen und Barrierecheck", "menge": "1 Paket", "netto": 28000, "steuersatz": 19},
        ],
        "netto_total": 90000,
        "tax_total": 17100,
        "brutto": 107100,
        "reverse_charge": False,
        "is_cancellation": False,
        "notes": [
            "Website-Wartung für den laufenden Monatsbetrieb einschließlich Inhaltsanpassungen und Barrierecheck.",
        ],
        "payment_status": "Zahlbar bis 10.09.2026",
        "manifest_scenario": "Website-Wartung für denselben deutschen Kunden im August; Zielzahlung im September.",
        "payment_manifest": [{"datum": "2026-09-11", "betrag": 107100}],
        "payment_after_import": [],
    },
    {
        "filename": "23_2026-09-18_SL-2026-095_nordkante-maintenance-september.pdf",
        "title": "Rechnung",
        "direction_label": "AUSGANGSRECHNUNG",
        "invoice_number": "SL-2026-095",
        "date": "2026-09-18",
        "recipient": [
            "Nordkante Verlag GmbH",
            "z. Hd. Maja Krüger",
            "Poolstraße 8",
            "20355 Hamburg",
            "Deutschland",
        ],
        "metadata": [
            ("Rechnungsnummer", "SL-2026-095"),
            ("Rechnungsdatum", "18.09.2026"),
            ("Leistungszeitraum", "01.09. bis 18.09.2026"),
        ],
        "subtitle": "Website-Wartung · September 2026",
        "items": [
            {"description": "Technische Pflege und Sicherheitsupdates, September", "menge": "1 Monat", "netto": 60000, "steuersatz": 19},
            {"description": "Backup-Prüfung und Release-Begleitung", "menge": "1 Paket", "netto": 28000, "steuersatz": 19},
        ],
        "netto_total": 88000,
        "tax_total": 16720,
        "brutto": 104720,
        "reverse_charge": False,
        "is_cancellation": False,
        "notes": [
            "Website-Wartung für den laufenden Monatsbetrieb einschließlich Backup-Prüfung und Release-Begleitung.",
        ],
        "payment_status": "Zahlbar bis 02.10.2026",
        "manifest_scenario": "Website-Wartung für denselben deutschen Kunden im September; Zielzahlung bis 20.09.2026.",
        "payment_manifest": [{"datum": "2026-09-20", "betrag": 104720}],
        "payment_after_import": [],
    },
    {
        "filename": "24_2026-08-28_SL-2026-084_kiesel-kante-design.pdf",
        "title": "Rechnung",
        "direction_label": "AUSGANGSRECHNUNG",
        "invoice_number": "SL-2026-084",
        "date": "2026-08-28",
        "recipient": [
            "Kiesel & Kante GmbH",
            "z. Hd. Lea Mertens",
            "Eppendorfer Weg 72",
            "20259 Hamburg",
            "Deutschland",
        ],
        "metadata": [
            ("Rechnungsnummer", "SL-2026-084"),
            ("Rechnungsdatum", "28.08.2026"),
            ("Leistungszeitraum", "24.08. bis 28.08.2026"),
        ],
        "subtitle": "Kleine Designleistung · digitale Einladung",
        "items": [
            {"description": "Gestaltung einer digitalen Einladung", "menge": "1 Projekt", "netto": 28000, "steuersatz": 19},
        ],
        "netto_total": 28000,
        "tax_total": 5320,
        "brutto": 33320,
        "reverse_charge": False,
        "is_cancellation": False,
        "notes": [
            "Einzelne abgeschlossene Designleistung für die digitale Einladung.",
        ],
        "payment_status": "Zahlbar bis 11.09.2026",
        "manifest_scenario": "Kleine eigenständige Designleistung für Kiesel & Kante GmbH; Zielzahlung im August.",
        "payment_manifest": [{"datum": "2026-08-29", "betrag": 33320}],
        "payment_after_import": [],
    },
]


OUT_DIR.mkdir(parents=True, exist_ok=True)
MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
for document in documents:
    draw_invoice(document)

manifest = []
for document in documents:
    manifest.append(
        {
            "filename": document["filename"],
            "datum": document["date"],
            "gegenpartei": document["recipient"][0],
            "richtung": "Ausgang",
            "waehrung": "EUR",
            "positionen": [
                {
                    "netto": item["netto"],
                    "steuersatz": item["steuersatz"],
                    "steuer": item["steuer"],
                }
                for item in document["items"]
            ],
            "brutto": document["brutto"],
            "zahlungen": document["payment_manifest"],
            "zahlungen_nach_rechnungsimport": document["payment_after_import"],
            "scenario": document["manifest_scenario"],
        }
    )

MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generated {len(documents)} PDFs in {OUT_DIR}")
print(f"Generated manifest {MANIFEST_PATH}")
