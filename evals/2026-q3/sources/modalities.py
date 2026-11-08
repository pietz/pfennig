#!/usr/bin/env -S uv run --python 3.13
"""Render two existing receipts as images and create one HTML invoice."""

from pathlib import Path
from subprocess import run


root = Path(__file__).resolve().parents[1]
out = root / "modalities"
out.mkdir(exist_ok=True)

run([
    "pdftoppm", "-f", "1", "-singlefile", "-r", "110", "-png",
    str(root / "einkauf/09-papier-punkt-kassenbon-2026-08-04.pdf"),
    str(out / "41-paper-receipt"),
], check=True)
run([
    "pdftoppm", "-f", "1", "-singlefile", "-r", "135", "-jpeg",
    str(root / "reise/17-hotelrechnung-lumenhof-muenchen.pdf"),
    str(out / "42-hotel-scan"),
], check=True)

(out / "43-moorwinkel-software.html").write_text("""<!doctype html>
<html lang="de"><meta charset="utf-8"><title>Rechnung MI-260923-043</title>
<body><header><h1>Moorwinkel IT GmbH</h1><p>Deichstraße 8, 20459 Hamburg<br>
kontakt@moorwinkel.example</p></header>
<main><h2>Rechnung MI-260923-043</h2><p>23.09.2026</p>
<p>Rechnung an: Mara Winter, Studio Linden, Kaistraße 18, 20457 Hamburg</p>
<table><tr><th>Leistung</th><th>Netto</th><th>USt 19 %</th><th>Brutto</th></tr>
<tr><td>Zeichenprogramm Pro, September 2026</td><td>50,00 EUR</td>
<td>9,50 EUR</td><td>59,50 EUR</td></tr></table>
<p>Gesamtbetrag: 59,50 EUR</p><p>Per Karte bezahlt am 23.09.2026: 59,50 EUR</p>
</main></body></html>
""", encoding="utf-8")
