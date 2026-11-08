#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["reportlab>=4.2,<5"]
# ///
"""Create non-booking and malformed PDF controls for the intake eval."""

from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.pdfgen.canvas import Canvas


out = Path(__file__).resolve().parents[1] / "controls"
out.mkdir(exist_ok=True)

blank = Canvas(str(out / "37-blank.pdf"), pagesize=A4, invariant=1)
blank.showPage()
blank.save()

letter = Canvas(str(out / "38-event-invitation.pdf"), pagesize=A4, invariant=1)
letter.setFont("Helvetica-Bold", 17)
letter.drawString(54, 760, "Einladung zum Designgespräch")
letter.setFont("Helvetica", 11)
letter.drawString(54, 716, "Wir laden Sie am 25. September 2026 zu einem kostenlosen Gespräch ein.")
letter.drawString(54, 691, "Ort: Hafenforum Hamburg, Konferenzraum 2.")
letter.drawString(54, 666, "Eine Anmeldung ist nicht erforderlich.")
letter.showPage()
letter.save()

(out / "39-empty.pdf").write_bytes(b"")
(out / "40-invalid.pdf").write_bytes(b"This is not a PDF file.\n")
