#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["reportlab>=4.2,<5"]
# ///
"""Generate the two filtered, incoming-only Kontur Bank extracts.

The source of every transaction is outgoing.json. Generation deliberately stops
until the final nine-entry outgoing manifest is available.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen.canvas import Canvas


SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parent
OUT = ROOT / "bank"
OUTGOING = SOURCE / "outgoing.json"
MANIFEST = SOURCE / "bank.json"
W, H = A4
M = 46
NAVY = colors.HexColor("#17324D")
BLUE = colors.HexColor("#2A7196")
PALE = colors.HexColor("#EEF5F8")
TEXT = colors.HexColor("#20262D")
MUTED = colors.HexColor("#66727D")


def eur(cents: int) -> str:
    whole, rest = divmod(cents, 100)
    return f"{whole:,}".replace(",", ".") + f",{rest:02d} EUR"


def tx(c: Canvas, x: float, y: float, value: str, size: float = 9, color=TEXT, bold=False, right=False) -> None:
    c.setFillColor(color)
    c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
    (c.drawRightString if right else c.drawString)(x, y, value)


def invoice_number(filename: str) -> str:
    match = re.search(r"SL-\d{4}-\d{3}", filename)
    if not match:
        raise ValueError(f"No invoice number in outgoing filename: {filename}")
    return match.group(0)


def load_transactions() -> list[dict]:
    records = json.loads(OUTGOING.read_text(encoding="utf-8"))
    if not isinstance(records, list) or len(records) != 9:
        raise RuntimeError(
            f"Waiting for final outgoing.json: expected 9 entries, found {len(records) if isinstance(records, list) else 'non-list'}"
        )
    transactions = []
    for record in records:
        filename = record["filename"]
        number = invoice_number(filename)
        for payment in record.get("zahlungen", []):
            amount = int(payment["betrag"])
            if amount <= 0:
                continue
            transactions.append({
                "datum": payment["datum"],
                "betrag": amount,
                "gegenpartei": record["gegenpartei"],
                "verwendungszweck": f"Zahlung Rechnung {number}",
                "rechnung_datei": filename,
                "belegnummer": number,
            })
    if len(transactions) != 7:
        raise RuntimeError(f"Expected 7 positive settled incoming payments, found {len(transactions)}")
    if any(t["rechnung_datei"].startswith("05_") for t in transactions):
        raise RuntimeError("Refund document 05 must not appear in incoming-only extracts")
    if any(t["rechnung_datei"].startswith("03_") for t in transactions):
        raise RuntimeError("Unpaid document 03 must not appear in incoming-only extracts")
    return sorted(transactions, key=lambda t: (t["datum"], t["rechnung_datei"]))


def split_transactions(all_transactions: list[dict]) -> tuple[list[dict], list[dict]]:
    july_august = [t for t in all_transactions if "2026-07-01" <= t["datum"] <= "2026-08-31"]
    september = [t for t in all_transactions if "2026-09-01" <= t["datum"] <= "2026-09-21"]
    if len(july_august) != 4 or len(september) != 3:
        raise RuntimeError("Positive payments must split into four July/August and three September entries")
    return july_august, september


def footer(c: Canvas) -> None:
    c.setStrokeColor(colors.HexColor("#D2DCE2")); c.setLineWidth(.6); c.line(M, 38, W - M, 38)
    tx(c, M, 23, "Fiktiver Musterbeleg · Nicht zur Zahlung", 7.2, MUTED)
    tx(c, W - M, 23, "Kontur Bank · kontur-bank.example", 7.2, MUTED, right=True)


def draw_extract(path: Path, title: str, date: str, period: str, transactions: list[dict]) -> None:
    c = Canvas(str(path), pagesize=A4)
    c.setTitle(title); c.setAuthor("Fiktive Beispieldaten Pfennig")
    c.setFillColor(NAVY); c.rect(0, H - 145, W, 145, fill=1, stroke=0)
    c.setFillColor(BLUE); c.rect(0, H - 152, W, 7, fill=1, stroke=0)
    tx(c, M, H - 52, "KONTUR BANK", 22, colors.white, True)
    tx(c, M, H - 75, "ZAHLUNGSEINGÄNGE", 8, colors.HexColor("#C8D7E2"), True)
    tx(c, W - M, H - 54, "UMSATZÜBERSICHT", 16, colors.white, True, right=True)
    tx(c, W - M, H - 77, "gefiltert: Zahlungseingänge", 9.5, colors.HexColor("#D7E2E9"), right=True)

    tx(c, M, H - 187, "KONTOINHABER", 7, MUTED, True)
    tx(c, M, H - 203, "Mara Winter · Studio Linden", 10, TEXT, True)
    tx(c, M, H - 220, "Konto-ID: DEMO-••••-2741 · keine echte Bankverbindung", 8, MUTED)
    tx(c, 350, H - 187, "AUSZUGSDATUM", 7, MUTED, True)
    tx(c, 350, H - 203, date, 10, TEXT, True)
    tx(c, 350, H - 220, f"Zeitraum: {period}", 8, MUTED)

    top = H - 263
    c.setFillColor(PALE); c.roundRect(M, top - 58, W - 2 * M, 58, 7, fill=1, stroke=0)
    tx(c, M + 15, top - 23, "Umsatzübersicht · gefiltert: Zahlungseingänge", 10, NAVY, True)
    tx(c, M + 15, top - 42, "Nur eingehende Überweisungen aus dem angegebenen Zeitraum", 8.2, MUTED)

    y = top - 94
    tx(c, M, y, "DATUM", 7.5, MUTED, True)
    tx(c, M + 82, y, "ZAHLUNG VON", 7.5, MUTED, True)
    tx(c, M + 280, y, "VERWENDUNGSZWECK", 7.5, MUTED, True)
    tx(c, W - M, y, "BETRAG", 7.5, MUTED, True, right=True)
    c.setStrokeColor(colors.HexColor("#C8D6DE")); c.line(M, y - 9, W - M, y - 9)
    y -= 37
    for transaction in transactions:
        tx(c, M, y, transaction["datum"], 9, TEXT)
        tx(c, M + 82, y, transaction["gegenpartei"], 9, TEXT, True)
        tx(c, M + 280, y, transaction["verwendungszweck"], 8.4, MUTED)
        tx(c, W - M, y, eur(transaction["betrag"]), 9.3, NAVY, True, right=True)
        tx(c, M + 82, y - 14, f"Rechnungsdatei: {transaction['rechnung_datei']}", 7.3, MUTED)
        c.setStrokeColor(colors.HexColor("#E0E7EB")); c.line(M, y - 25, W - M, y - 25)
        y -= 54

    total = sum(t["betrag"] for t in transactions)
    y -= 4
    tx(c, M + 280, y, f"{len(transactions)} Zahlungseingänge", 8.5, MUTED, True)
    c.setFillColor(BLUE); c.roundRect(350, y - 47, W - M - 350, 34, 6, fill=1, stroke=0)
    tx(c, 365, y - 34, "SUMME EINGÄNGE", 9, colors.white, True)
    tx(c, W - M - 12, y - 34, eur(total), 11, colors.white, True, right=True)

    c.setFillColor(colors.HexColor("#FFF4E5")); c.roundRect(M, 105, W - 2 * M, 54, 7, fill=1, stroke=0)
    tx(c, M + 14, 139, "HINWEIS ZUM AUSZUG", 7.5, colors.HexColor("#98631D"), True)
    tx(c, M + 14, 122, "Kein vollständiger Kontoauszug: Ausgaben, Erstattungen und Kontosalden sind nicht enthalten.", 8.2, colors.HexColor("#62451F"))
    footer(c); c.save()


def build() -> None:
    july_august, september = split_transactions(load_transactions())
    OUT.mkdir(parents=True, exist_ok=True)
    documents = [
        {
            "filename": "27_kontur-bank-zahlungseingaenge-juli-august.pdf",
            "datum": "2026-08-31",
            "period": "01.07. - 31.08.2026",
            "title": "Umsatzübersicht Juli und August 2026 - Kontur Bank",
            "transaktionen": july_august,
        },
        {
            "filename": "28_kontur-bank-zahlungseingaenge-september.pdf",
            "datum": "2026-09-21",
            "period": "01.09. - 21.09.2026",
            "title": "Umsatzübersicht September 2026 - Kontur Bank",
            "transaktionen": september,
        },
    ]
    for document in documents:
        draw_extract(OUT / document["filename"], document["title"], document["datum"], document["period"], document["transaktionen"])
    MANIFEST.write_text(json.dumps({"documents": [{k: d[k] for k in ("filename", "datum", "transaktionen")} for d in documents]}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
