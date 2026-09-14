# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "reportlab>=4.2",
#     "pillow>=10.4",
# ]
# ///
"""
Synthetic test document generator for Pfennig.

Generates fictional, format-valid invoices/receipts (PDF and one JPEG) plus
matching expected.json extraction ground truth files under
Fixtures/documents/<nn>-<slug>/.

Run with:
    uv run Fixtures/generator/generate.py

Everything here is fictional: company names, VAT IDs, IBANs, invoice
numbers, addresses (street level). Cities are real, streets are invented.
"""

from __future__ import annotations

import json
import random
import textwrap
from dataclasses import dataclass, field
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas as pdfcanvas

from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
DOCS_DIR = HERE.parent / "documents"

FONT_REGULAR = "Helvetica"
FONT_BOLD = "Helvetica-Bold"
MONO_REGULAR = "Courier"
MONO_BOLD = "Courier-Bold"

PIL_MONO_PATH = "/System/Library/Fonts/Supplemental/Courier New.ttf"
PIL_MONO_BOLD_PATH = "/System/Library/Fonts/Supplemental/Courier New Bold.ttf"


# ---------------------------------------------------------------------------
# Shared A4 invoice drawing helpers
# ---------------------------------------------------------------------------

PAGE_W, PAGE_H = A4
MARGIN_L = 22 * mm
MARGIN_R = 22 * mm
MARGIN_TOP = 22 * mm


def new_canvas(path: Path) -> pdfcanvas.Canvas:
    return pdfcanvas.Canvas(str(path), pagesize=A4)


def text(c, x, y, s, font=FONT_REGULAR, size=10, fill=(0, 0, 0)):
    c.setFont(font, size)
    c.setFillColorRGB(*[v / 255 for v in fill])
    c.drawString(x, y, s)


def text_right(c, x, y, s, font=FONT_REGULAR, size=10, fill=(0, 0, 0)):
    c.setFont(font, size)
    c.setFillColorRGB(*[v / 255 for v in fill])
    c.drawRightString(x, y, s)


def hline(c, x1, x2, y, width=0.6, color=(0, 0, 0)):
    c.setLineWidth(width)
    c.setStrokeColorRGB(*[v / 255 for v in color])
    c.line(x1, y, x2, y)


def wrapped_block(c, lines: list[str], x, y, font=FONT_REGULAR, size=9.5, leading=12.5):
    cy = y
    for ln in lines:
        text(c, x, cy, ln, font=font, size=size)
        cy -= leading
    return cy


@dataclass
class Party:
    name: str
    street: str
    postal_code: str
    city: str
    country: str = "Deutschland"
    country_code: str = "DE"
    vat_id: str | None = None
    extra: list[str] = field(default_factory=list)

    def lines(self) -> list[str]:
        out = [self.name, self.street, f"{self.postal_code} {self.city}"]
        if self.country_code != "DE":
            out.append(self.country)
        if self.vat_id:
            out.append(f"USt-IdNr.: {self.vat_id}")
        out.extend(self.extra)
        return out


MARA = Party(
    name="Mara Beispiel",
    street="Musterstraße 12",
    postal_code="10115",
    city="Berlin",
    country_code="DE",
    vat_id="DE999999999",
    extra=["Freelance Software Development"],
)
MARA_IBAN = "DE00500105170123456789"


def draw_invoice_header(
    c,
    *,
    vendor: Party,
    recipient: Party,
    doc_title: str,
    invoice_number: str | None,
    invoice_date: str,
    meta_lines: list[str],
    lang: str = "de",
):
    y = PAGE_H - MARGIN_TOP

    # Vendor block (top-left, small)
    text(c, MARGIN_L, y, vendor.name, font=FONT_BOLD, size=11)
    y2 = y - 13
    for ln in [vendor.street, f"{vendor.postal_code} {vendor.city}"] + (
        [vendor.country] if vendor.country_code != "DE" else []
    ):
        text(c, MARGIN_L, y2, ln, size=9)
        y2 -= 11.5
    if vendor.vat_id:
        text(c, MARGIN_L, y2, f"USt-IdNr.: {vendor.vat_id}", size=9)
        y2 -= 11.5

    # Document title + number (top-right)
    text_right(c, PAGE_W - MARGIN_R, y, doc_title, font=FONT_BOLD, size=16)
    ry = y - 20
    if invoice_number:
        label = "Rechnungsnr." if lang == "de" else "Invoice no."
        text_right(c, PAGE_W - MARGIN_R, ry, f"{label}: {invoice_number}", size=9.5)
        ry -= 13
    date_label = "Rechnungsdatum" if lang == "de" else "Invoice date"
    text_right(c, PAGE_W - MARGIN_R, ry, f"{date_label}: {invoice_date}", size=9.5)
    ry -= 13
    for ln in meta_lines:
        text_right(c, PAGE_W - MARGIN_R, ry, ln, size=9.5)
        ry -= 13

    # Recipient block
    rec_y = y - 70
    text(c, MARGIN_L, rec_y, "Rechnungsempfänger" if lang == "de" else "Bill to", size=8.5, fill=(90, 90, 90))
    rec_y -= 12
    for ln in recipient.lines():
        text(c, MARGIN_L, rec_y, ln, size=9.5)
        rec_y -= 12

    body_top = min(ry, rec_y) - 20
    return body_top


def draw_items_table(
    c,
    top_y,
    items: list[dict],
    *,
    lang: str = "de",
    currency: str = "EUR",
):
    """items: list of {description, net, rate, tax, gross}"""
    x_desc = MARGIN_L
    x_rate = PAGE_W - MARGIN_R - 150
    x_net = PAGE_W - MARGIN_R - 105
    x_tax = PAGE_W - MARGIN_R - 55
    x_gross = PAGE_W - MARGIN_R

    y = top_y
    hdr = ["Beschreibung", "USt.", "Netto", "USt.-Betr.", "Brutto"] if lang == "de" else [
        "Description", "VAT", "Net", "Tax", "Gross"
    ]
    text(c, x_desc, y, hdr[0], font=FONT_BOLD, size=9)
    text_right(c, x_rate + 25, y, hdr[1], font=FONT_BOLD, size=9)
    text_right(c, x_net, y, hdr[2], font=FONT_BOLD, size=9)
    text_right(c, x_tax, y, hdr[3], font=FONT_BOLD, size=9)
    text_right(c, x_gross, y, hdr[4], font=FONT_BOLD, size=9)
    y -= 6
    hline(c, MARGIN_L, PAGE_W - MARGIN_R, y)
    y -= 14

    cur_sym = currency + " "
    for it in items:
        desc_lines = textwrap.wrap(it["description"], width=48) or [""]
        text(c, x_desc, y, desc_lines[0], size=9.5)
        text_right(c, x_rate + 25, y, f'{it["rate"]}%', size=9.5)
        text_right(c, x_net, y, f'{cur_sym}{it["net"]}', size=9.5)
        text_right(c, x_tax, y, f'{cur_sym}{it["tax"]}', size=9.5)
        text_right(c, x_gross, y, f'{cur_sym}{it["gross"]}', size=9.5)
        y -= 13
        for extra_line in desc_lines[1:]:
            text(c, x_desc, y, extra_line, size=9.5)
            y -= 13

    y -= 4
    hline(c, MARGIN_L, PAGE_W - MARGIN_R, y)
    y -= 16
    return y


def draw_totals(c, top_y, *, net: str, tax: str, gross: str, currency="EUR", lang="de", tax_note: str | None = None):
    x_label = PAGE_W - MARGIN_R - 105
    x_val = PAGE_W - MARGIN_R
    y = top_y
    labels = ("Zwischensumme", "Gesamt USt.", "Gesamtbetrag") if lang == "de" else ("Subtotal", "Total VAT", "Total amount")
    text_right(c, x_label, y, labels[0], size=9.5)
    text_right(c, x_val, y, f"{currency} {net}", size=9.5)
    y -= 14
    text_right(c, x_label, y, labels[1], size=9.5)
    text_right(c, x_val, y, f"{currency} {tax}", size=9.5)
    y -= 4
    hline(c, x_label - 10, x_val, y)
    y -= 14
    text_right(c, x_label, y, labels[2], font=FONT_BOLD, size=11)
    text_right(c, x_val, y, f"{currency} {gross}", font=FONT_BOLD, size=11)
    y -= 22
    if tax_note:
        for ln in textwrap.wrap(tax_note, width=95):
            text(c, MARGIN_L, y, ln, size=8.5, fill=(60, 60, 60))
            y -= 11
    return y


def draw_footer(c, y, lines: list[str]):
    for ln in lines:
        for wrapped in (textwrap.wrap(ln, width=110) or [""]):
            text(c, MARGIN_L, y, wrapped, size=8.5, fill=(70, 70, 70))
            y -= 11
    return y


# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------


def build_01_irish_saas(out_dir: Path):
    vendor = Party(
        name="CloudForge Software Ireland Limited",
        street="14 Harbour Quay",
        postal_code="D02 XY45",
        city="Dublin",
        country="Ireland",
        country_code="IE",
        vat_id="IE1234567X",
    )
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=vendor,
        recipient=MARA,
        doc_title="INVOICE",
        invoice_number="CF-2026-08931",
        invoice_date="2026-08-31",
        meta_lines=["Service period: Aug 1-31, 2026"],
        lang="en",
    )
    items = [
        {"description": "CloudForge Suite - Team plan (5 seats)", "rate": "0", "net": "71.39", "tax": "0.00", "gross": "71.39"},
    ]
    y = draw_items_table(c, body_top, items, lang="en")
    y = draw_totals(
        c, y, net="71.39", tax="0.00", gross="71.39", lang="en",
        tax_note="VAT reverse charged. Customer is liable for VAT under Article 196 of Council Directive 2006/112/EC.",
    )
    draw_footer(c, y, [
        f"Customer VAT ID: {MARA.vat_id}",
        "Payment method: credit card on file. Thank you for your business.",
        "CloudForge Software Ireland Limited - Registered in Ireland No. 774411",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "IE",
            "vatId": "IE1234567X",
            "street": "14 Harbour Quay",
            "postalCode": "D02 XY45",
            "city": "Dublin",
        },
        "invoice": {
            "invoiceNumber": "CF-2026-08931",
            "invoiceDate": "2026-08-31",
            "serviceDate": None,
            "servicePeriodStart": "2026-08-01",
            "servicePeriodEnd": "2026-08-31",
            "currency": "EUR",
            "netAmount": "71.39",
            "taxAmount": "0.00",
            "grossAmount": "71.39",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "0", "netAmount": "71.39", "taxAmount": "0.00", "kind": "reverseChargeNote"}
        ],
        "taxTreatmentHint": {
            "treatment": "reverseCharge",
        },
        "lineItems": [
            {"description": "CloudForge Suite - Team plan (5 seats)", "netAmount": "71.39", "categoryHint": "software_subscriptions", "assetCandidate": False}
        ],
        "paymentInfo": {"paymentMethodHint": "card", "paidIndicator": "paid", "paymentDate": None, "iban": None, "reference": "CF-2026-08931"},
        "missingFields": ["serviceDate"],
    }
    return expected


def build_02_german_hosting(out_dir: Path):
    vendor = Party(
        name="NordServe Hosting GmbH",
        street="Speicherstraße 8",
        postal_code="20457",
        city="Hamburg",
        vat_id="DE123456789",
    )
    iban = "DE00200105170234567890"
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=vendor,
        recipient=MARA,
        doc_title="RECHNUNG",
        invoice_number="NH-100234",
        invoice_date="2026-09-01",
        meta_lines=["Leistungszeitraum: 01.08.2026 - 31.08.2026"],
    )
    items = [
        {"description": "Hosting-Paket Business M, monatlich", "rate": "19", "net": "40.00", "tax": "7.60", "gross": "47.60"},
    ]
    y = draw_items_table(c, body_top, items)
    y = draw_totals(c, y, net="40.00", tax="7.60", gross="47.60")
    draw_footer(c, y, [
        f"Zahlungsart: SEPA-Lastschrift. Gläubiger-ID: DE98ZZZ00000123456, Mandatsreferenz: NH-MARA-0042",
        f"IBAN: {iban}  BIC: NORDDEHHXXX",
        "Der Betrag wird ca. 5 Werktage nach Rechnungsdatum eingezogen.",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "DE",
            "vatId": "DE123456789",
            "street": "Speicherstraße 8",
            "postalCode": "20457",
            "city": "Hamburg",
        },
        "invoice": {
            "invoiceNumber": "NH-100234",
            "invoiceDate": "2026-09-01",
            "serviceDate": None,
            "servicePeriodStart": "2026-08-01",
            "servicePeriodEnd": "2026-08-31",
            "currency": "EUR",
            "netAmount": "40.00",
            "taxAmount": "7.60",
            "grossAmount": "47.60",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "19", "netAmount": "40.00", "taxAmount": "7.60", "kind": "standard"}
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Hosting-Paket Business M, monatlich", "netAmount": "40.00", "categoryHint": "hosting_cloud", "assetCandidate": False}
        ],
        "paymentInfo": {
            "paymentMethodHint": "directDebit",
            "paidIndicator": "paid",
            "paymentDate": "2026-09-06",
            "iban": iban,
            "reference": "NH-100234",
        },
        "missingFields": [],
    }
    return expected


def build_03_office_supplies_kassenbon(out_dir: Path):
    vendor = Party(
        name="Schreibwaren Müller e.K.",
        street="Kastanienallee 51",
        postal_code="10435",
        city="Berlin",
        vat_id=None,
    )
    width = 80 * mm
    height = 150 * mm
    path = out_dir / "document.pdf"
    c = pdfcanvas.Canvas(str(path), pagesize=(width, height))
    cx = width / 2
    y = height - 10 * mm

    def center(s, size=9, font=MONO_REGULAR):
        c.setFont(font, size)
        c.drawCentredString(cx, y, s)

    center(vendor.name, size=10, font=MONO_BOLD)
    y -= 12
    center(vendor.street)
    y -= 11
    center(f"{vendor.postal_code} {vendor.city}")
    y -= 16
    c.setFont(MONO_REGULAR, 9)
    c.drawString(6 * mm, y, "-" * 32)
    y -= 14

    def row(desc, amount):
        nonlocal y
        c.setFont(MONO_REGULAR, 9)
        c.drawString(6 * mm, y, desc)
        c.drawRightString(width - 6 * mm, y, amount)
        y -= 12.5

    row("Kugelschreiber-Set", "11,90 A")
    row("Notizbuch A5", "11,90 B")
    y -= 4
    c.drawString(6 * mm, y, "-" * 32)
    y -= 14
    c.setFont(MONO_BOLD, 10)
    c.drawString(6 * mm, y, "SUMME")
    c.drawRightString(width - 6 * mm, y, "EUR 23,80")
    y -= 18
    c.setFont(MONO_REGULAR, 8)
    c.drawString(6 * mm, y, "A = 19% USt      10,00 + 1,90")
    y -= 11
    c.drawString(6 * mm, y, "B =  7% USt      11,12 + 0,78")
    y -= 18
    c.drawString(6 * mm, y, "Zahlung: BAR")
    y -= 11
    c.drawString(6 * mm, y, "14.07.2026  16:42  Bon-Nr. 004821")
    y -= 16
    center("Kleinbetragsrechnung gem. §33 UStDV", size=8)
    y -= 11
    center("Vielen Dank für Ihren Einkauf!", size=8)
    c.save()

    expected = {
        "documentType": "receipt",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "DE",
            "vatId": None,
            "street": "Kastanienallee 51",
            "postalCode": "10435",
            "city": "Berlin",
        },
        "invoice": {
            "invoiceNumber": None,
            "invoiceDate": "2026-07-14",
            "serviceDate": "2026-07-14",
            "servicePeriodStart": None,
            "servicePeriodEnd": None,
            "currency": "EUR",
            "netAmount": "21.12",
            "taxAmount": "2.68",
            "grossAmount": "23.80",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "19", "netAmount": "10.00", "taxAmount": "1.90", "kind": "standard"},
            {"rate": "7", "netAmount": "11.12", "taxAmount": "0.78", "kind": "reduced"},
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Kugelschreiber-Set", "netAmount": "10.00", "categoryHint": "office_supplies", "assetCandidate": False},
            {"description": "Notizbuch A5", "netAmount": "11.12", "categoryHint": "office_supplies", "assetCandidate": False},
        ],
        "paymentInfo": {"paymentMethodHint": "cash", "paidIndicator": "paid", "paymentDate": "2026-07-14", "iban": None, "reference": None},
        "missingFields": ["invoiceNumber"],
    }
    return expected


def build_04_bahn_ticket(out_dir: Path):
    vendor = Party(
        name="Bahn Express AG",
        street="Gleisallee 1",
        postal_code="60329",
        city="Frankfurt am Main",
        vat_id="DE223456789",
    )
    width, height = 105 * mm, 148 * mm  # A6 ticket
    path = out_dir / "document.pdf"
    c = pdfcanvas.Canvas(str(path), pagesize=(width, height))
    y = height - 10 * mm
    text(c, 8 * mm, y, "FAHRAUSWEIS", font=FONT_BOLD, size=14)
    y -= 16
    text(c, 8 * mm, y, vendor.name, size=8.5)
    y -= 20
    text(c, 8 * mm, y, "Berlin Hbf  ->  München Hbf", font=FONT_BOLD, size=10)
    y -= 13
    text(c, 8 * mm, y, "03.06.2026  08:12 - 12:47", size=9)
    y -= 13
    text(c, 8 * mm, y, "2. Klasse, 1 Erwachsener", size=9)
    y -= 18
    hline(c, 8 * mm, width - 8 * mm, y)
    y -= 14
    text(c, 8 * mm, y, "Fahrkarte (Fernverkehr)", size=9)
    text_right(c, width - 8 * mm, y, "EUR 84,90", size=9)
    y -= 13
    text(c, 8 * mm, y, "Sitzplatzreservierung", size=9)
    text_right(c, width - 8 * mm, y, "EUR 10,00", size=9)
    y -= 12
    hline(c, 8 * mm, width - 8 * mm, y)
    y -= 14
    text(c, 8 * mm, y, "Gesamtpreis", font=FONT_BOLD, size=10)
    text_right(c, width - 8 * mm, y, "EUR 94,90", font=FONT_BOLD, size=10)
    y -= 20
    text(c, 8 * mm, y, "davon 7% USt: EUR 5,55 (Fahrkarte)", size=8)
    y -= 11
    text(c, 8 * mm, y, "davon 19% USt: EUR 1,60 (Reservierung)", size=8)
    y -= 18
    text(c, 8 * mm, y, "Auftragsnummer: BE-778812345", size=8.5)
    y -= 12
    text(c, 8 * mm, y, "Zahlung: Kreditkarte", size=8.5)
    y -= 12
    text(c, 8 * mm, y, f"USt-IdNr.: {vendor.vat_id}", size=7.5, fill=(90, 90, 90))
    c.save()

    expected = {
        "documentType": "receipt",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "DE",
            "vatId": "DE223456789",
            "street": "Gleisallee 1",
            "postalCode": "60329",
            "city": "Frankfurt am Main",
        },
        "invoice": {
            "invoiceNumber": "BE-778812345",
            "invoiceDate": "2026-06-03",
            "serviceDate": "2026-06-03",
            "servicePeriodStart": None,
            "servicePeriodEnd": None,
            "currency": "EUR",
            "netAmount": "87.75",
            "taxAmount": "7.15",
            "grossAmount": "94.90",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "7", "netAmount": "79.35", "taxAmount": "5.55", "kind": "reduced"},
            {"rate": "19", "netAmount": "8.40", "taxAmount": "1.60", "kind": "standard"},
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Fahrkarte 2. Klasse Berlin Hbf - München Hbf", "netAmount": "79.35", "categoryHint": "travel_transport", "assetCandidate": False},
            {"description": "Sitzplatzreservierung", "netAmount": "8.40", "categoryHint": "travel_transport", "assetCandidate": False},
        ],
        "paymentInfo": {"paymentMethodHint": "card", "paidIndicator": "paid", "paymentDate": "2026-06-03", "iban": None, "reference": "BE-778812345"},
        "missingFields": [],
    }
    return expected


def build_05_hotel(out_dir: Path):
    vendor = Party(
        name="Hotel Am Stadtpark GmbH",
        street="Parkring 22",
        postal_code="80331",
        city="München",
        vat_id="DE334455667",
    )
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=vendor,
        recipient=MARA,
        doc_title="RECHNUNG",
        invoice_number="HSP-2026-4471",
        invoice_date="2026-05-12",
        meta_lines=["Aufenthalt: 10.05.2026 - 12.05.2026"],
    )
    items = [
        {"description": "Übernachtung Doppelzimmer zur Einzelnutzung, 2 Nächte", "rate": "7", "net": "180.00", "tax": "12.60", "gross": "192.60"},
        {"description": "Frühstücksbuffet, 2x", "rate": "19", "net": "30.00", "tax": "5.70", "gross": "35.70"},
    ]
    y = draw_items_table(c, body_top, items)
    y = draw_totals(c, y, net="210.00", tax="18.30", gross="228.30")
    draw_footer(c, y, [
        "Zahlung erfolgte per Kreditkarte bei Abreise.",
        "Vielen Dank für Ihren Aufenthalt im Hotel Am Stadtpark.",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "DE",
            "vatId": "DE334455667",
            "street": "Parkring 22",
            "postalCode": "80331",
            "city": "München",
        },
        "invoice": {
            "invoiceNumber": "HSP-2026-4471",
            "invoiceDate": "2026-05-12",
            "serviceDate": None,
            "servicePeriodStart": "2026-05-10",
            "servicePeriodEnd": "2026-05-12",
            "currency": "EUR",
            "netAmount": "210.00",
            "taxAmount": "18.30",
            "grossAmount": "228.30",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "7", "netAmount": "180.00", "taxAmount": "12.60", "kind": "reduced"},
            {"rate": "19", "netAmount": "30.00", "taxAmount": "5.70", "kind": "standard"},
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Übernachtung Doppelzimmer zur Einzelnutzung, 2 Nächte", "netAmount": "180.00", "categoryHint": "travel_lodging", "assetCandidate": False},
            {"description": "Frühstücksbuffet, 2x", "netAmount": "30.00", "categoryHint": "meals_entertainment", "assetCandidate": False},
        ],
        "paymentInfo": {"paymentMethodHint": "card", "paidIndicator": "paid", "paymentDate": "2026-05-12", "iban": None, "reference": "HSP-2026-4471"},
        "missingFields": [],
    }
    return expected


def build_06_us_software(out_dir: Path):
    vendor = Party(
        name="Bright Peak Software Inc.",
        street="880 Beacon Hill Ave",
        postal_code="CA 94107",
        city="San Francisco",
        country="United States",
        country_code="US",
        vat_id=None,
    )
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=vendor,
        recipient=MARA,
        doc_title="INVOICE",
        invoice_number="BP-INV-20264471",
        invoice_date="2026-07-15",
        meta_lines=["Currency: USD"],
        lang="en",
    )
    items = [
        {"description": "Annual Enterprise License - DevTools Suite", "rate": "0", "net": "1,000.00", "tax": "0.00", "gross": "1,000.00"},
    ]
    y = draw_items_table(c, body_top, items, lang="en", currency="USD")
    y = draw_totals(c, y, net="1,000.00", tax="0.00", gross="1,000.00", currency="USD", lang="en", tax_note="No VAT/sales tax applies. No EUR equivalent is stated on this invoice.")
    draw_footer(c, y, [
        "Bright Peak Software Inc., Delaware, USA. Tax ID (EIN): 87-1234567 (not a VAT ID).",
        "Paid by credit card on 2026-07-15.",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "US",
            "vatId": None,
            "street": "880 Beacon Hill Ave",
            "postalCode": "CA 94107",
            "city": "San Francisco",
        },
        "invoice": {
            "invoiceNumber": "BP-INV-20264471",
            "invoiceDate": "2026-07-15",
            "serviceDate": None,
            "servicePeriodStart": None,
            "servicePeriodEnd": None,
            "currency": "USD",
            "netAmount": "1000.00",
            "taxAmount": "0.00",
            "grossAmount": "1000.00",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "0", "netAmount": "1000.00", "taxAmount": "0.00", "kind": "zero"}
        ],
        "taxTreatmentHint": {
            "treatment": "reverseCharge",
        },
        "lineItems": [
            {"description": "Annual Enterprise License - DevTools Suite", "netAmount": "1000.00", "categoryHint": "software_subscriptions", "assetCandidate": False}
        ],
        "paymentInfo": {"paymentMethodHint": "card", "paidIndicator": "paid", "paymentDate": "2026-07-15", "iban": None, "reference": "BP-INV-20264471"},
        "missingFields": ["statedEurEquivalent"],
    }
    return expected


def build_07_uk_consultancy(out_dir: Path):
    vendor = Party(
        name="Thornfield Consulting Ltd",
        street="19 Lancer Row",
        postal_code="EC2A 4NE",
        city="London",
        country="United Kingdom",
        country_code="GB",
        vat_id="GB123456789",
    )
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=vendor,
        recipient=MARA,
        doc_title="INVOICE",
        invoice_number="TC-2026-0187",
        invoice_date="2026-04-22",
        meta_lines=["Currency: GBP", "EUR equivalent: EUR 988.50 (rate 1.1629)"],
        lang="en",
    )
    items = [
        {"description": "Strategy Consulting - Q2 2026 Engagement", "rate": "0", "net": "850.00", "tax": "0.00", "gross": "850.00"},
    ]
    y = draw_items_table(c, body_top, items, lang="en", currency="GBP")
    y = draw_totals(c, y, net="850.00", tax="0.00", gross="850.00", currency="GBP", lang="en", tax_note="Reverse charge: VAT to be accounted for by the recipient (Art. 196 Directive 2006/112/EC).")
    draw_footer(c, y, [
        f"Supplier VAT No.: {vendor.vat_id}",
        f"Customer VAT ID: {MARA.vat_id}",
        "Payment due within 30 days by bank transfer.",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "GB",
            "vatId": "GB123456789",
            "street": "19 Lancer Row",
            "postalCode": "EC2A 4NE",
            "city": "London",
        },
        "invoice": {
            "invoiceNumber": "TC-2026-0187",
            "invoiceDate": "2026-04-22",
            "serviceDate": None,
            "servicePeriodStart": None,
            "servicePeriodEnd": None,
            "currency": "GBP",
            "netAmount": "850.00",
            "taxAmount": "0.00",
            "grossAmount": "850.00",
            "statedEurEquivalent": "988.50",
        },
        "taxComponents": [
            {"rate": "0", "netAmount": "850.00", "taxAmount": "0.00", "kind": "reverseChargeNote"}
        ],
        "taxTreatmentHint": {
            "treatment": "reverseCharge",
        },
        "lineItems": [
            {"description": "Strategy Consulting - Q2 2026 Engagement", "netAmount": "850.00", "categoryHint": "professional_services", "assetCandidate": False}
        ],
        "paymentInfo": {"paymentMethodHint": "bankTransfer", "paidIndicator": "unpaid", "paymentDate": None, "iban": None, "reference": "TC-2026-0187"},
        "missingFields": [],
    }
    return expected


BYTEWERK = Party(
    name="ByteWerk Computer GmbH",
    street="Ringstraße 77",
    postal_code="50667",
    city="Köln",
    vat_id="DE445566778",
)
BYTEWERK_IBAN = "DE00370400440532013000"


def build_08_laptop(out_dir: Path):
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=BYTEWERK,
        recipient=MARA,
        doc_title="RECHNUNG",
        invoice_number="BW-2026-33210",
        invoice_date="2026-03-05",
        meta_lines=[],
    )
    items = [
        {"description": "Notebook ProBook X15 (16GB RAM / 1TB SSD)", "rate": "19", "net": "1.850,00", "tax": "351,50", "gross": "2.201,50"},
    ]
    y = draw_items_table(c, body_top, items)
    y = draw_totals(c, y, net="1.850,00", tax="351,50", gross="2.201,50")
    draw_footer(c, y, [
        f"IBAN: {BYTEWERK_IBAN}  BIC: COBADEFFXXX",
        "Zahlbar innerhalb von 14 Tagen ohne Abzug.",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "expense",
        "counterparty": {
            "name": BYTEWERK.name,
            "countryCode": "DE",
            "vatId": "DE445566778",
            "street": "Ringstraße 77",
            "postalCode": "50667",
            "city": "Köln",
        },
        "invoice": {
            "invoiceNumber": "BW-2026-33210",
            "invoiceDate": "2026-03-05",
            "serviceDate": "2026-03-05",
            "servicePeriodStart": None,
            "servicePeriodEnd": None,
            "currency": "EUR",
            "netAmount": "1850.00",
            "taxAmount": "351.50",
            "grossAmount": "2201.50",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "19", "netAmount": "1850.00", "taxAmount": "351.50", "kind": "standard"}
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Notebook ProBook X15 (16GB RAM / 1TB SSD)", "netAmount": "1850.00", "categoryHint": "hardware_equipment", "assetCandidate": True}
        ],
        "paymentInfo": {"paymentMethodHint": "bankTransfer", "paidIndicator": "paid", "paymentDate": "2026-03-06", "iban": BYTEWERK_IBAN, "reference": "BW-2026-33210"},
        "missingFields": [],
    }
    return expected


def build_09_monitor(out_dir: Path):
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=BYTEWERK,
        recipient=MARA,
        doc_title="RECHNUNG",
        invoice_number="BW-2026-33450",
        invoice_date="2026-03-20",
        meta_lines=[],
    )
    items = [
        {"description": "Monitor UltraView 27\" 4K", "rate": "19", "net": "299,00", "tax": "56,81", "gross": "355,81"},
    ]
    y = draw_items_table(c, body_top, items)
    y = draw_totals(c, y, net="299,00", tax="56,81", gross="355,81")
    draw_footer(c, y, [
        f"IBAN: {BYTEWERK_IBAN}  BIC: COBADEFFXXX",
        "Zahlbar innerhalb von 14 Tagen ohne Abzug.",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "expense",
        "counterparty": {
            "name": BYTEWERK.name,
            "countryCode": "DE",
            "vatId": "DE445566778",
            "street": "Ringstraße 77",
            "postalCode": "50667",
            "city": "Köln",
        },
        "invoice": {
            "invoiceNumber": "BW-2026-33450",
            "invoiceDate": "2026-03-20",
            "serviceDate": "2026-03-20",
            "servicePeriodStart": None,
            "servicePeriodEnd": None,
            "currency": "EUR",
            "netAmount": "299.00",
            "taxAmount": "56.81",
            "grossAmount": "355.81",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "19", "netAmount": "299.00", "taxAmount": "56.81", "kind": "standard"}
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Monitor UltraView 27\" 4K", "netAmount": "299.00", "categoryHint": "hardware_small", "assetCandidate": False}
        ],
        "paymentInfo": {"paymentMethodHint": "bankTransfer", "paidIndicator": "paid", "paymentDate": "2026-03-21", "iban": BYTEWERK_IBAN, "reference": "BW-2026-33450"},
        "missingFields": [],
    }
    return expected


def build_10_income_domestic(out_dir: Path):
    client = Party(
        name="Nordlicht Systeme GmbH",
        street="Werftallee 5",
        postal_code="28217",
        city="Bremen",
        vat_id="DE556677889",
    )
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=MARA,
        recipient=client,
        doc_title="RECHNUNG",
        invoice_number="RE-2026-0042",
        invoice_date="2026-08-15",
        meta_lines=["Leistungszeitraum: August 2026"],
    )
    items = [
        {"description": "Softwareentwicklung - Projekt Aurora, August 2026", "rate": "19", "net": "4.500,00", "tax": "855,00", "gross": "5.355,00"},
    ]
    y = draw_items_table(c, body_top, items)
    y = draw_totals(c, y, net="4.500,00", tax="855,00", gross="5.355,00")
    draw_footer(c, y, [
        f"IBAN: {MARA_IBAN}  BIC: DEUTDEFFXXX",
        "Zahlbar innerhalb von 14 Tagen ohne Abzug.",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "income",
        "counterparty": {
            "name": client.name,
            "countryCode": "DE",
            "vatId": "DE556677889",
            "street": "Werftallee 5",
            "postalCode": "28217",
            "city": "Bremen",
        },
        "invoice": {
            "invoiceNumber": "RE-2026-0042",
            "invoiceDate": "2026-08-15",
            "serviceDate": None,
            "servicePeriodStart": "2026-08-01",
            "servicePeriodEnd": "2026-08-31",
            "currency": "EUR",
            "netAmount": "4500.00",
            "taxAmount": "855.00",
            "grossAmount": "5355.00",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "19", "netAmount": "4500.00", "taxAmount": "855.00", "kind": "standard"}
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Softwareentwicklung - Projekt Aurora, August 2026", "netAmount": "4500.00", "categoryHint": "revenue_services", "assetCandidate": False}
        ],
        "paymentInfo": {"paymentMethodHint": "bankTransfer", "paidIndicator": "unpaid", "paymentDate": None, "iban": MARA_IBAN, "reference": "RE-2026-0042"},
        "missingFields": [],
    }
    return expected


def build_11_income_france(out_dir: Path):
    client = Party(
        name="Lumière Digitale SARL",
        street="12 Rue des Tisserands",
        postal_code="69002",
        city="Lyon",
        country="France",
        country_code="FR",
        vat_id="FR12345678901",
    )
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=MARA,
        recipient=client,
        doc_title="RECHNUNG / INVOICE",
        invoice_number="RE-2026-0043",
        invoice_date="2026-08-28",
        meta_lines=["Leistungszeitraum: August 2026"],
    )
    items = [
        {"description": "Backend-Entwicklung - Projekt Icarus", "rate": "0", "net": "3.200,00", "tax": "0,00", "gross": "3.200,00"},
    ]
    y = draw_items_table(c, body_top, items)
    y = draw_totals(c, y, net="3.200,00", tax="0,00", gross="3.200,00", tax_note="Steuerschuldnerschaft des Leistungsempfängers (Reverse Charge) gem. Art. 44 MwStSystRL / Art. 196.")
    draw_footer(c, y, [
        f"Kunden-USt-IdNr.: {client.vat_id}",
        f"IBAN: {MARA_IBAN}  BIC: DEUTDEFFXXX",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "income",
        "counterparty": {
            "name": client.name,
            "countryCode": "FR",
            "vatId": "FR12345678901",
            "street": "12 Rue des Tisserands",
            "postalCode": "69002",
            "city": "Lyon",
        },
        "invoice": {
            "invoiceNumber": "RE-2026-0043",
            "invoiceDate": "2026-08-28",
            "serviceDate": None,
            "servicePeriodStart": "2026-08-01",
            "servicePeriodEnd": "2026-08-31",
            "currency": "EUR",
            "netAmount": "3200.00",
            "taxAmount": "0.00",
            "grossAmount": "3200.00",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "0", "netAmount": "3200.00", "taxAmount": "0.00", "kind": "reverseChargeNote"}
        ],
        "taxTreatmentHint": {
            "treatment": "reverseCharge",
        },
        "lineItems": [
            {"description": "Backend-Entwicklung - Projekt Icarus", "netAmount": "3200.00", "categoryHint": "revenue_services", "assetCandidate": False}
        ],
        "paymentInfo": {"paymentMethodHint": "bankTransfer", "paidIndicator": "unpaid", "paymentDate": None, "iban": MARA_IBAN, "reference": "RE-2026-0043"},
        "missingFields": [],
    }
    return expected


def build_12_credit_note(out_dir: Path):
    vendor = Party(
        name="NordServe Hosting GmbH",
        street="Speicherstraße 8",
        postal_code="20457",
        city="Hamburg",
        vat_id="DE123456789",
    )
    iban = "DE00200105170234567890"
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=vendor,
        recipient=MARA,
        doc_title="GUTSCHRIFT",
        invoice_number="NH-CN-100256",
        invoice_date="2026-09-05",
        meta_lines=["Bezug: Rechnung NH-100234 vom 01.09.2026"],
    )
    items = [
        {"description": "Erstattung wegen Serviceausfall (Rechnung NH-100234)", "rate": "19", "net": "-40,00", "tax": "-7,60", "gross": "-47,60"},
    ]
    y = draw_items_table(c, body_top, items)
    y = draw_totals(c, y, net="-40,00", tax="-7,60", gross="-47,60")
    draw_footer(c, y, [
        f"Der Betrag wird auf IBAN {iban} zurücküberwiesen.",
        "Diese Gutschrift mindert die ursprüngliche Rechnung NH-100234.",
    ])
    c.save()

    expected = {
        "documentType": "creditNote",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "DE",
            "vatId": "DE123456789",
            "street": "Speicherstraße 8",
            "postalCode": "20457",
            "city": "Hamburg",
        },
        "invoice": {
            "invoiceNumber": "NH-CN-100256",
            "invoiceDate": "2026-09-05",
            "serviceDate": None,
            "servicePeriodStart": None,
            "servicePeriodEnd": None,
            "currency": "EUR",
            "netAmount": "-40.00",
            "taxAmount": "-7.60",
            "grossAmount": "-47.60",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "19", "netAmount": "-40.00", "taxAmount": "-7.60", "kind": "standard"}
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Erstattung wegen Serviceausfall (Rechnung NH-100234)", "netAmount": "-40.00", "categoryHint": "hosting_cloud", "assetCandidate": False}
        ],
        "paymentInfo": {"paymentMethodHint": "bankTransfer", "paidIndicator": "paid", "paymentDate": "2026-09-10", "iban": iban, "reference": "NH-100234"},
        "missingFields": [],
    }
    return expected


def build_13_telecom(out_dir: Path):
    vendor = Party(
        name="TeleWelle Kommunikation GmbH",
        street="Sendeturmweg 3",
        postal_code="70173",
        city="Stuttgart",
        vat_id="DE667788990",
    )
    iban = "DE00600501010067788990"
    path = out_dir / "document.pdf"
    c = new_canvas(path)
    body_top = draw_invoice_header(
        c,
        vendor=vendor,
        recipient=MARA,
        doc_title="RECHNUNG",
        invoice_number="TW-2026-88123",
        invoice_date="2026-02-10",
        meta_lines=["Abrechnungsmonat: Februar 2026"],
    )
    items = [
        {"description": "Mobilfunk-Flatrate Business", "rate": "19", "net": "55,00", "tax": "10,45", "gross": "65,45"},
        {"description": "Kaution neues Endgerät (Vorschuss, erstattungsfähig)", "rate": "0", "net": "100,00", "tax": "0,00", "gross": "100,00"},
    ]
    y = draw_items_table(c, body_top, items)
    y = draw_totals(c, y, net="155,00", tax="10,45", gross="165,45")
    draw_footer(c, y, [
        f"IBAN: {iban}  BIC: SOLADEST600",
        "Zahlung erfolgt per SEPA-Lastschrift.",
    ])
    c.save()

    expected = {
        "documentType": "invoice",
        "direction": "expense",
        "counterparty": {
            "name": vendor.name,
            "countryCode": "DE",
            "vatId": "DE667788990",
            "street": "Sendeturmweg 3",
            "postalCode": "70173",
            "city": "Stuttgart",
        },
        "invoice": {
            "invoiceNumber": "TW-2026-88123",
            "invoiceDate": "2026-02-10",
            "serviceDate": None,
            "servicePeriodStart": "2026-02-01",
            "servicePeriodEnd": "2026-02-28",
            "currency": "EUR",
            "netAmount": "155.00",
            "taxAmount": "10.45",
            "grossAmount": "165.45",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "19", "netAmount": "55.00", "taxAmount": "10.45", "kind": "standard"},
            {"rate": "0", "netAmount": "100.00", "taxAmount": "0.00", "kind": "deposit"},
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Mobilfunk-Flatrate Business", "netAmount": "55.00", "categoryHint": "telecom", "assetCandidate": False},
            {"description": "Kaution neues Endgerät (Vorschuss, erstattungsfähig)", "netAmount": "100.00", "categoryHint": "telecom", "assetCandidate": False},
        ],
        "paymentInfo": {"paymentMethodHint": "directDebit", "paidIndicator": "paid", "paymentDate": "2026-02-12", "iban": iban, "reference": "TW-2026-88123"},
        "missingFields": [],
    }
    return expected


def build_14_cafe_photo(out_dir: Path):
    width, height = 620, 1500
    img = Image.new("RGB", (width, height), (250, 248, 244))
    draw = ImageDraw.Draw(img)
    try:
        font_reg = ImageFont.truetype(PIL_MONO_PATH, 22)
        font_bold = ImageFont.truetype(PIL_MONO_BOLD_PATH, 26)
        font_small = ImageFont.truetype(PIL_MONO_PATH, 18)
    except OSError:
        font_reg = font_bold = font_small = ImageFont.load_default()

    y = 40
    def center(s, font, fill=(20, 20, 20)):
        nonlocal y
        bbox = draw.textbbox((0, 0), s, font=font)
        w = bbox[2] - bbox[0]
        draw.text(((width - w) / 2, y), s, font=font, fill=fill)
        y += (bbox[3] - bbox[1]) + 14

    def left_right(left_s, right_s, font):
        nonlocal y
        draw.text((30, y), left_s, font=font, fill=(20, 20, 20))
        bbox = draw.textbbox((0, 0), right_s, font=font)
        w = bbox[2] - bbox[0]
        draw.text((width - 30 - w, y), right_s, font=font, fill=(20, 20, 20))
        y += (bbox[3] - bbox[1]) + 16

    def rule():
        nonlocal y
        draw.line([(30, y), (width - 30, y)], fill=(120, 120, 120), width=2)
        y += 20

    center("CAFE SONNENBLICK", font_bold)
    center("Karl-Liebknecht-Str. 44", font_small)
    center("04107 Leipzig", font_small)
    y += 10
    rule()
    left_right("Cappuccino", "4,20 A", font_reg)
    left_right("Kuchenstueck", "4,80 A", font_reg)
    left_right("Sandwich to go", "9,50 B", font_reg)
    rule()
    left_right("SUMME", "EUR 18,50", font_bold)
    y += 6
    left_right("A=19% USt", "7,56 + 1,44", font_small)
    left_right("B= 7% USt", "8,88 + 0,62", font_small)
    y += 10
    left_right("Zahlung", "BAR", font_reg)
    left_right("Datum", "18.06.2026 09:14", font_reg)
    y += 20
    center("Bon-Nr. 002214", font_small)
    center("Danke fuer Ihren Besuch!", font_small)

    # Slight rotation + noise for a "photographed receipt" look.
    img = img.rotate(-2.6, expand=True, fillcolor=(235, 233, 228))
    img = img.filter(ImageFilter.GaussianBlur(0.4))

    random.seed(14)
    pixels = img.load()
    w, h = img.size
    for _ in range(int(w * h * 0.02)):
        px = random.randint(0, w - 1)
        py = random.randint(0, h - 1)
        r, g, b = pixels[px, py]
        n = random.randint(-14, 14)
        pixels[px, py] = (
            max(0, min(255, r + n)),
            max(0, min(255, g + n)),
            max(0, min(255, b + n)),
        )

    path = out_dir / "document.jpg"
    img.save(path, "JPEG", quality=82)

    expected = {
        "documentType": "receipt",
        "direction": "expense",
        "counterparty": {
            "name": "Cafe Sonnenblick",
            "countryCode": "DE",
            "vatId": None,
            "street": "Karl-Liebknecht-Str. 44",
            "postalCode": "04107",
            "city": "Leipzig",
        },
        "invoice": {
            "invoiceNumber": None,
            "invoiceDate": "2026-06-18",
            "serviceDate": "2026-06-18",
            "servicePeriodStart": None,
            "servicePeriodEnd": None,
            "currency": "EUR",
            "netAmount": "16.44",
            "taxAmount": "2.06",
            "grossAmount": "18.50",
            "statedEurEquivalent": None,
        },
        "taxComponents": [
            {"rate": "19", "netAmount": "7.56", "taxAmount": "1.44", "kind": "standard"},
            {"rate": "7", "netAmount": "8.88", "taxAmount": "0.62", "kind": "reduced"},
        ],
        "taxTreatmentHint": {
            "treatment": "domesticVAT",
        },
        "lineItems": [
            {"description": "Cappuccino", "netAmount": "3.53", "categoryHint": "meals_entertainment", "assetCandidate": False},
            {"description": "Kuchenstueck", "netAmount": "4.03", "categoryHint": "meals_entertainment", "assetCandidate": False},
            {"description": "Sandwich to go", "netAmount": "8.88", "categoryHint": "meals_entertainment", "assetCandidate": False},
        ],
        "paymentInfo": {"paymentMethodHint": "cash", "paidIndicator": "paid", "paymentDate": "2026-06-18", "iban": None, "reference": None},
        "missingFields": ["invoiceNumber"],
    }
    return expected


FIXTURES = [
    ("01-irish-saas-reverse-charge", build_01_irish_saas),
    ("02-german-hosting-monthly", build_02_german_hosting),
    ("03-office-supplies-kassenbon", build_03_office_supplies_kassenbon),
    ("04-bahn-ticket-mixed-vat", build_04_bahn_ticket),
    ("05-hotel-invoice-lodging-breakfast", build_05_hotel),
    ("06-us-software-usd-reverse-charge", build_06_us_software),
    ("07-uk-consultancy-gbp-reverse-charge", build_07_uk_consultancy),
    ("08-hardware-laptop-asset-candidate", build_08_laptop),
    ("09-hardware-monitor-small", build_09_monitor),
    ("10-income-invoice-domestic-gmbh", build_10_income_domestic),
    ("11-income-invoice-france-reverse-charge", build_11_income_france),
    ("12-credit-note-hosting", build_12_credit_note),
    ("13-telecom-deposit-line", build_13_telecom),
    ("14-cafe-receipt-photo", build_14_cafe_photo),
]


def main():
    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    for slug, builder in FIXTURES:
        out_dir = DOCS_DIR / slug
        out_dir.mkdir(parents=True, exist_ok=True)
        expected = builder(out_dir)
        (out_dir / "expected.json").write_text(
            json.dumps(expected, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        print(f"generated {slug}")


if __name__ == "__main__":
    main()
