#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["reportlab>=4.2,<5"]
# ///
"""Generate eight independent Q3 2026 invoices and their amount manifest."""
from __future__ import annotations

import json
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen.canvas import Canvas


ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "extra"
MANIFEST = Path(__file__).with_suffix(".json")
W, H = A4
INK = colors.HexColor("#24303C")
GRAY = colors.HexColor("#667481")
WHITE = colors.white


def euro(cents: int) -> str:
    return f"{cents // 100:,}".replace(",", ".") + f",{cents % 100:02d} EUR"


def line(c: Canvas, x: float, y: float, value: str, size=9, color=INK, bold=False, right=False) -> None:
    c.setFillColor(color)
    c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
    (c.drawRightString if right else c.drawString)(x, y, value)


def rule(c: Canvas, y: float) -> None:
    c.setStrokeColor(colors.HexColor("#CDD6DE"))
    c.setLineWidth(.7)
    c.line(43, y, W - 43, y)


CASES = [
    dict(filename="29-veldlicht-eu-display.pdf", supplier="Veldlicht Handel B.V.", city="Utrecht, Niederlande", recipient="Mara Winter | Studio Linden", title="Rechnung", number="VH-260714-029", date="14.07.2026", item="LED-Farbdisplay 27 Zoll, 1 Stück", detail="Versand aus Utrecht nach Hamburg am 14.07.2026", net=28800, tax=0, rate="0 %", booking_rate="19", total=28800, payment="Kartenzahlung am 16.07.2026: 288,00 EUR", note="Innergemeinschaftliche Lieferung an DE000000000. Keine niederländische Umsatzsteuer berechnet.", style="catalog", scenario="eu_goods_acquisition_paid", expected=dict(richtung="ausgabe", art="rechnung", datum="2026-07-14", belegnummer="VH-260714-029", gegenpartei_name="Veldlicht Handel B.V.", gegenpartei_land="NL", kategorie="hardware", steuerbehandlung="innergemeinschaftlicher_erwerb", netto_cents=28800, steuer_cents=0, brutto_cents=28800, zahlungen=[dict(datum="2026-07-16", betrag=28800)])),
    dict(filename="30-slatepeak-cloud-service.pdf", supplier="Slatepeak Systems Inc.", city="Portland, Oregon, USA", recipient="Studio Linden | Mara Winter", title="INVOICE", number="SS-2026-0806-030", date="06.08.2026", item="Cloud development workspace, August 2026", detail="Business subscription, supplied electronically", net=6400, tax=0, rate="0 %", booking_rate="19", total=6400, payment="Corporate card charged 07.08.2026: 64.00 EUR", note="B2B service to customer in Germany. No US sales tax charged. Reverse charge by recipient.", style="digital", scenario="us_b2b_service_reverse_charge_paid", expected=dict(accepted_categories=["hosting"], richtung="ausgabe", art="rechnung", datum="2026-08-06", belegnummer="SS-2026-0806-030", gegenpartei_name="Slatepeak Systems Inc.", gegenpartei_land="US", kategorie="software", steuerbehandlung="reverse_charge", netto_cents=6400, steuer_cents=0, brutto_cents=6400, zahlungen=[dict(datum="2026-08-07", betrag=6400)])),
    dict(filename="31-seitenstrom-fachbuch.pdf", supplier="Seitenstrom Buchhandlung GmbH", city="Hamburg, Deutschland", recipient="Mara Winter | Studio Linden", title="Kassenbeleg", number="SB-260812-031", date="12.08.2026", item="Fachbuch: Barrierefreie Webgestaltung", detail="1 Buch, gedruckte Ausgabe", net=2800, tax=196, rate="7 %", total=2996, payment="EC-Karte 12.08.2026: 29,96 EUR", note="Umsatzsteuer 7 % auf gedrucktes Buch.", style="receipt", scenario="professional_print_book_7_percent", expected=dict(richtung="ausgabe", art="beleg", datum="2026-08-12", belegnummer="SB-260812-031", gegenpartei_name="Seitenstrom Buchhandlung GmbH", gegenpartei_land="DE", kategorie="fortbildung", steuerbehandlung="inland", netto_cents=2800, steuer_cents=196, brutto_cents=2996, zahlungen=[dict(datum="2026-08-12", betrag=2996)])),
    dict(filename="32-werftkontor-coworking.pdf", supplier="Werftkontor Räume GmbH", city="Hamburg, Deutschland", recipient="Studio Linden | Mara Winter", title="Rechnung", number="WK-260901-032", date="01.09.2026", item="Fester Arbeitsplatz, September 2026", detail="Coworking-Mitgliedschaft inklusive Besprechungsraum", net=24000, tax=4560, rate="19 %", total=28560, payment="Lastschrift am 03.09.2026: 285,60 EUR", note="Leistungszeitraum 01.09. bis 30.09.2026.", style="letter", scenario="coworking_workspace_paid", expected=dict(richtung="ausgabe", art="rechnung", datum="2026-09-01", belegnummer="WK-260901-032", gegenpartei_name="Werftkontor Räume GmbH", gegenpartei_land="DE", kategorie="miete", steuerbehandlung="inland", netto_cents=24000, steuer_cents=4560, brutto_cents=28560, zahlungen=[dict(datum="2026-09-03", betrag=28560)])),
    dict(filename="33-sl-license-stadtfaden.pdf", supplier="Studio Linden | Mara Winter", city="Hamburg, Deutschland", recipient="Stadtfaden Verlag GmbH | Berlin, Deutschland", title="RECHNUNG", number="SL-2026-096", date="08.09.2026", item="Nutzungsrecht Illustrationsserie Stadtlinien", detail="Nicht ausschließlich, digitale Nutzung für 12 Monate", net=150000, tax=28500, rate="19 %", total=178500, payment="Zahlungseingang am 18.09.2026: 1.785,00 EUR", note="Leistungszeitraum 08.09.2026 bis 07.09.2027.", style="studio", scenario="domestic_license_revenue_paid", expected=dict(richtung="einnahme", art="rechnung", datum="2026-09-08", belegnummer="SL-2026-096", gegenpartei_name="Stadtfaden Verlag GmbH", gegenpartei_land="DE", kategorie="umsatz_lizenzen", steuerbehandlung="inland", netto_cents=150000, steuer_cents=28500, brutto_cents=178500, zahlungen=[dict(datum="2026-09-18", betrag=178500)])),
    dict(filename="34-sl-partial-payment-holzlinie.pdf", supplier="Studio Linden | Mara Winter", city="Hamburg, Deutschland", recipient="Holzlinie Möbel GmbH | Bremen, Deutschland", title="RECHNUNG", number="SL-2026-097", date="16.09.2026", item="Konzept und Gestaltung Produktseite", detail="Abnahme 15.09.2026", net=200000, tax=38000, rate="19 %", total=238000, payment="Teilzahlung eingegangen 20.09.2026: 800,00 EUR", note="Restbetrag 1.580,00 EUR offen. Zahlungsziel 30.09.2026.", style="studio", scenario="domestic_service_income_part_paid", expected=dict(richtung="einnahme", art="rechnung", datum="2026-09-16", belegnummer="SL-2026-097", faelligkeit="2026-09-30", gegenpartei_name="Holzlinie Möbel GmbH", gegenpartei_land="DE", kategorie="umsatz_dienstleistung", steuerbehandlung="inland", netto_cents=200000, steuer_cents=38000, brutto_cents=238000, zahlungen=[dict(datum="2026-09-20", betrag=80000)])),
    dict(filename="35-eichenrat-advisory.pdf", supplier="Eichenrat Steuerberatung", city="Hamburg, Deutschland", recipient="Mara Winter | Studio Linden", title="Rechnung", number="ER-260919-035", date="19.09.2026", item="Beratung zur EÜR-Organisation", detail="2 Stunden am 18.09.2026", net=32000, tax=6080, rate="19 %", total=38080, payment="Noch nicht bezahlt. Fällig am 03.10.2026.", note="Bitte Rechnungsnummer als Verwendungszweck angeben.", style="letter", scenario="professional_advice_unpaid", expected=dict(richtung="ausgabe", art="rechnung", datum="2026-09-19", belegnummer="ER-260919-035", faelligkeit="2026-10-03", gegenpartei_name="Eichenrat Steuerberatung", gegenpartei_land="DE", kategorie="beratung", steuerbehandlung="inland", netto_cents=32000, steuer_cents=6080, brutto_cents=38080, zahlungen=[])),
    dict(filename="36-signalwerk-drawing-tablet.pdf", supplier="Signalwerk Technik GmbH", city="Hannover, Deutschland", recipient="Mara Winter | Studio Linden", title="Rechnung", number="ST-260922-036", date="22.09.2026", item="Grafiktablett S1", detail="1 Stück, inklusive Stift und USB-Kabel", net=12900, tax=2451, rate="19 %", total=15351, payment="Kreditkarte 22.09.2026: 153,51 EUR", note="Lieferung am 22.09.2026.", style="catalog", scenario="low_value_hardware_accessory_paid", expected=dict(richtung="ausgabe", art="rechnung", datum="2026-09-22", belegnummer="ST-260922-036", gegenpartei_name="Signalwerk Technik GmbH", gegenpartei_land="DE", kategorie="hardware", steuerbehandlung="inland", netto_cents=12900, steuer_cents=2451, brutto_cents=15351, zahlungen=[dict(datum="2026-09-22", betrag=15351)])),
]


def draw(case: dict, path: Path) -> None:
    style = case["style"]
    c = Canvas(str(path), pagesize=A4, invariant=1)
    c.setTitle(f'{case["title"]} {case["number"]}')
    c.setAuthor(case["supplier"])
    accent = {"catalog": "#155E75", "digital": "#513BA5", "receipt": "#303E33", "letter": "#3C6257", "studio": "#284962"}[style]
    accent = colors.HexColor(accent)
    if style == "receipt":
        c.setFillColor(colors.HexColor("#F5F4ED")); c.roundRect(120, 39, W - 240, H - 78, 9, fill=1, stroke=0)
        left, right = 147, W - 147
        c.setFillColor(accent); c.rect(120, H - 146, W - 240, 107, fill=1, stroke=0)
        line(c, left, H - 84, "SEITENSTROM", 19, WHITE, True)
        line(c, left, H - 107, "BUCHHANDLUNG", 10, WHITE, True)
        y = H - 181
        for value in [case["supplier"], "Hamburg | Deutschland", case["title"], f'Beleg {case["number"]}', f'Datum {case["date"]}']:
            line(c, left, y, value, 10, INK, value == case["title"]); y -= 24
        c.setStrokeColor(GRAY); c.line(left, y - 4, right, y - 4)
        y -= 35
        line(c, left, y, case["item"], 9, INK, True)
        line(c, left, y - 20, case["detail"], 8, GRAY)
        y -= 73
        for label, amount in [("Netto", case["net"]), ("USt 7 %", case["tax"]), ("SUMME", case["total"])]:
            line(c, left, y, label, 10, INK, label == "SUMME")
            line(c, right, y, euro(amount), 10, INK, label == "SUMME", True)
            y -= 25
        line(c, left, y - 22, case["payment"], 8.5)
        line(c, left, y - 43, case["note"], 8)
    else:
        c.setFillColor(accent); c.rect(0, H - 137, W, 137, fill=1, stroke=0)
        brand = case["supplier"].split(" | ")[0]
        line(c, 44, H - 58, brand.upper(), 20 if len(brand) < 27 else 16, WHITE, True)
        line(c, 44, H - 83, case["city"], 9, WHITE)
        line(c, W - 44, H - 59, case["title"], 16, WHITE, True, True)
        line(c, W - 44, H - 82, case["number"], 9, WHITE, False, True)
        line(c, 44, H - 185, "AN", 8, GRAY, True)
        line(c, 44, H - 207, case["recipient"], 10, INK, True)
        line(c, W - 44, H - 185, "DATUM", 8, GRAY, True, True)
        line(c, W - 44, H - 207, case["date"], 10, INK, False, True)
        if style == "catalog":
            c.setFillColor(colors.HexColor("#EAF2F5")); c.roundRect(43, H - 442, W - 86, 171, 8, fill=1, stroke=0)
            line(c, 58, H - 303, "ARTIKEL", 8, accent, True)
            line(c, 58, H - 339, case["item"], 14, INK, True)
            line(c, 58, H - 360, case["detail"], 9, GRAY)
        elif style == "digital":
            c.setFillColor(colors.HexColor("#F1EFF9")); c.roundRect(43, H - 440, W - 86, 165, 9, fill=1, stroke=0)
            line(c, 60, H - 307, "SUBSCRIPTION", 9, accent, True)
            line(c, 60, H - 343, case["item"], 14, INK, True)
            line(c, 60, H - 367, case["detail"], 9, GRAY)
        else:
            line(c, 44, H - 292, "LEISTUNG", 8, accent, True)
            rule(c, H - 304)
            line(c, 44, H - 334, case["item"], 12, INK, True)
            line(c, 44, H - 354, case["detail"], 9, GRAY)
        rule(c, H - 478)
        line(c, 44, H - 504, "Nettobetrag", 10)
        line(c, W - 44, H - 504, euro(case["net"]), 10, INK, False, True)
        line(c, 44, H - 532, f'Umsatzsteuer {case["rate"]}', 10)
        line(c, W - 44, H - 532, euro(case["tax"]), 10, INK, False, True)
        c.setFillColor(accent); c.roundRect(43, H - 605, W - 86, 50, 6, fill=1, stroke=0)
        line(c, 58, H - 584, "GESAMTBETRAG", 11, WHITE, True)
        line(c, W - 58, H - 584, euro(case["total"]), 12, WHITE, True, True)
        line(c, 44, H - 648, case["payment"], 9, INK, True)
        line(c, 44, H - 671, case["note"], 8.5, GRAY)
        rule(c, 58)
        line(c, 44, 41, case["supplier"], 8, GRAY)
    c.save()


def build() -> None:
    OUT.mkdir(exist_ok=True)
    for case in CASES:
        assert case["net"] + case["tax"] == case["total"]
        assert case["expected"]["brutto_cents"] == case["total"]
        draw(case, OUT / case["filename"])
    records = []
    for case in CASES:
        expected = {
            "faelligkeit": None,
            "privatanteil_prozent": 0,
            "nutzungsdauer_jahre": None,
            "waehrung": None,
            "originalbetrag": None,
            **case["expected"],
            "positionen_nach_satz": [
                {"steuersatz": case.get("booking_rate", case["rate"].split()[0]), "netto_cents": case["net"], "steuer_cents": case["tax"]}
            ],
        }
        records.append({"filename": case["filename"], "scenario": case["scenario"], "expected": expected})
    MANIFEST.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
