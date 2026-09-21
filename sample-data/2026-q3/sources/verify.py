#!/usr/bin/env -S uv run --python 3.13
# /// script
# requires-python = ">=3.13"
# dependencies = ["pypdf>=5,<7"]
# ///
"""Focused QA checks for the fictional Q3 2026 manifests and PDFs."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date, datetime
from collections import Counter
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Any

from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
MANIFESTS = {
    "outgoing.json": ("ausgang", 9),
    "purchases.json": ("einkauf", 7),
    "equipment-services.json": ("einkauf", 4),
    "travel.json": ("reise", 6),
}
BANK_MANIFEST = "bank.json"
DATE_MIN, DATE_MAX = date(2026, 7, 1), date(2026, 9, 21)
CENT = Decimal("0.01")
FILE_KEYS = {"datei", "dateiname", "file", "filename", "pdf", "pfad", "path"}
DATE_KEYS = {"datum", "date", "rechnungsdatum", "belegdatum", "leistungsdatum", "reisedatum"}
NET_KEYS = {"netto", "net", "nettoeuro", "nettoeur"}
TAX_KEYS = {"steuer", "umsatzsteuer", "mwst", "ust", "vat", "tax"}
GROSS_KEYS = {"brutto", "gross", "total", "gesamt", "endbetrag"}
RATE_KEYS = {"steuersatz", "ustsatz", "mwstsatz", "vatrate", "taxrate", "rate"}
PAYMENT_KEYS = {
    "zahlung", "zahlungen", "payment", "payments", "paymentstatus", "bezahlt", "paid",
    "zahlungsstatus", "zahlungsdatum", "paymentdate",
}
SCENARIO_KEYS = {"scenario", "szenario", "steuerfall", "ustfall", "taxcase", "expectedscenario"}
RC_MARKERS = ("reverse charge", "reverse_charge", "reversecharge", "§13b", "13b")
UNPAID_MARKERS = ("unbezahlt", "unpaid", "offen", "outstanding", "noch nicht")
PAID_MARKERS = ("bezahlt", "paid", "erstattet", "refunded", "beglichen")
BAD_GLYPHS = ("\ufffd", "(cid:", "\x00", "\ufffc")


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def key(value: Any) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value).casefold())


def leaves(value: Any, path: tuple[str, ...] = ()) -> list[tuple[tuple[str, ...], Any]]:
    if isinstance(value, dict):
        result: list[tuple[tuple[str, ...], Any]] = []
        for name, child in value.items():
            result.extend(leaves(child, path + (str(name),)))
        return result
    if isinstance(value, list):
        result = []
        for index, child in enumerate(value):
            result.extend(leaves(child, path + (str(index),)))
        return result
    return [(path, value)]


def records(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if not isinstance(payload, dict):
        return []
    preferred = {"items", "records", "entries", "documents", "belege", "buchungen", "data"}
    for name, value in payload.items():
        if key(name) in preferred and isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
    lists = [value for value in payload.values() if isinstance(value, list)]
    if len(lists) == 1:
        return [item for item in lists[0] if isinstance(item, dict)]
    mapped = [value for value in payload.values() if isinstance(value, dict)]
    return mapped if mapped and any(file_name(item) for item in mapped) else []


def direct(record: dict[str, Any], names: set[str]) -> Any | None:
    for name, value in record.items():
        if key(name) in names:
            return value
    for path, value in leaves(record):
        if path and key(path[-1]) in names:
            return value
    return None


def file_name(record: dict[str, Any]) -> str | None:
    value = direct(record, FILE_KEYS)
    if isinstance(value, dict):
        value = next((value.get(name) for name in ("filename", "file", "path", "pfad") if isinstance(value.get(name), str)), None)
    if isinstance(value, str) and value.lower().endswith(".pdf"):
        return value
    for _, value in leaves(record):
        if isinstance(value, str) and value.lower().endswith(".pdf"):
            return value
    return None


def euro_amount(value: Any) -> Decimal | None:
    """Manifest amounts are integer EUR cents; decimal strings are EUR values."""
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return Decimal(value) / 100
    text = str(value).strip().replace("−", "-").replace(" ", "")
    text = re.sub(r"[^0-9,.-]", "", text)
    if not text or text in {"-", ".", ","}:
        return None
    try:
        if "," in text and "." in text:
            text = text.replace(".", "").replace(",", ".") if text.rfind(",") > text.rfind(".") else text.replace(",", "")
        elif "," in text:
            text = text.replace(",", ".")
        elif re.fullmatch(r"-?\d+", text):
            return Decimal(text) / 100
        return Decimal(text)
    except InvalidOperation:
        return None


def amount(record: dict[str, Any], names: set[str]) -> Decimal | None:
    # Prefer an explicit record total, then sum line-item fields such as positionen.netto.
    for name, value in record.items():
        if key(name) in names:
            parsed = euro_amount(value)
            if parsed is not None:
                return parsed
    values = [euro_amount(value) for path, value in leaves(record) if path and key(path[-1]) in names]
    values = [value for value in values if value is not None]
    return sum(values, Decimal()) if values else None


def rate(record: dict[str, Any]) -> Decimal | None:
    value = direct(record, RATE_KEYS)
    if isinstance(value, (int, float, Decimal)):
        return Decimal(str(value))
    if value is None:
        return None
    text = re.sub(r"[^0-9,.-]", "", str(value).replace(" ", "")).replace(",", ".")
    try:
        return Decimal(text)
    except InvalidOperation:
        return None


def document_date(record: dict[str, Any]) -> date | None:
    value = direct(record, DATE_KEYS)
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    text = str(value)
    match = re.search(r"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})", text)
    if match:
        year, month, day = (int(part) for part in match.groups())
    else:
        match = re.search(r"(\d{1,2})[./-](\d{1,2})[./-](\d{4})", text)
        if not match:
            return None
        day, month, year = (int(part) for part in match.groups())
    try:
        return date(year, month, day)
    except ValueError:
        return None


def payment_state(record: dict[str, Any]) -> bool | None:
    for name, value in record.items():
        if key(name) in {"zahlungen", "payments"} and isinstance(value, list):
            return bool(value)
    values = [(path[-1], value) for path, value in leaves(record) if path and key(path[-1]) in PAYMENT_KEYS]
    for _, value in values:
        if isinstance(value, bool):
            return value
        text = str(value).casefold()
        if any(marker in text for marker in UNPAID_MARKERS):
            return False
        if any(marker in text for marker in PAID_MARKERS):
            return True
    return True if any(document_date({"datum": value}) for _, value in values) else None


def scenario(record: dict[str, Any]) -> str:
    return " ".join(
        str(value).casefold()
        for path, value in leaves(record)
        if path and key(path[-1]) in SCENARIO_KEYS
    )


def is_rc(record: dict[str, Any]) -> bool:
    return any(marker in scenario(record) for marker in RC_MARKERS) or direct(record, {"reversecharge"}) is True


def is_outgoing(record: dict[str, Any]) -> bool:
    value = direct(record, {"richtung", "direction"})
    return isinstance(value, str) and value.casefold() in {"ausgang", "outgoing", "income"}


def resolve_manifest(root: Path, name: str) -> Path | None:
    found = list(root.rglob(name))
    return sorted(found)[0] if found else None


def resolve_pdf(root: Path, directory: str, name: str) -> Path | None:
    raw = Path(name)
    candidates = [root / raw, root / directory / raw]
    existing = [path.resolve() for path in candidates if path.is_file()]
    if existing:
        return existing[0]
    matches = [path.resolve() for path in root.rglob(raw.name) if path.is_file()]
    return matches[0] if len(matches) == 1 else None


def amount_variants(value: Decimal) -> list[str]:
    value = value.quantize(CENT, rounding=ROUND_HALF_UP)
    sign, value = ("-", -value) if value < 0 else ("", value)
    whole, fraction = f"{value:.2f}".split(".")
    return [sign + f"{int(whole):,}".replace(",", ".") + "," + fraction, sign + whole + "," + fraction, sign + whole + "." + fraction]


def has_amount(text: str, value: Decimal) -> bool:
    text = re.sub(r"\s+", "", text)
    return any(re.search(rf"(?<!\d){re.escape(variant)}(?!\d)", text) for variant in amount_variants(value))


def check_pdf(report: Report, path: Path, label: str, record: dict[str, Any]) -> None:
    try:
        reader = PdfReader(str(path))
        texts = [page.extract_text() or "" for page in reader.pages]
    except Exception as exc:
        report.error(f"{label}: unreadable PDF: {exc}")
        return
    if len(texts) != 1:
        report.error(f"{label}: expected one page, found {len(texts)}")
    text = "\n".join(texts)
    for number, page_text in enumerate(texts, 1):
        if not page_text.strip():
            report.error(f"{label}: page {number} has no extractable text")
    for marker in BAD_GLYPHS:
        if marker in text:
            report.error(f"{label}: missing-glyph marker {marker!r}")
    if "—" in text:
        report.error(f"{label}: contains an em dash")
    # Documents may show net/tax by line or rate rather than repeating the
    # manifest aggregate. The gross total is the stable cross-document check.
    gross = amount(record, GROSS_KEYS)
    if gross is not None and not has_amount(text, gross):
        report.error(f"{label}: manifest gross {gross:.2f} not found in PDF text")


def check_bank_pdf(report: Report, path: Path, label: str, total_cents: int) -> None:
    try:
        reader = PdfReader(str(path))
        texts = [page.extract_text() or "" for page in reader.pages]
    except Exception as exc:
        report.error(f"{label}: unreadable PDF: {exc}")
        return
    if len(texts) != 1:
        report.error(f"{label}: expected one page, found {len(texts)}")
    text = "\n".join(texts)
    for number, page_text in enumerate(texts, 1):
        if not page_text.strip():
            report.error(f"{label}: page {number} has no extractable text")
    for marker in BAD_GLYPHS:
        if marker in text:
            report.error(f"{label}: missing-glyph marker {marker!r}")
    if "—" in text:
        report.error(f"{label}: contains an em dash")
    lowered = text.casefold()
    if "gefiltert" not in lowered or "zahlungseingänge" not in lowered:
        report.error(f"{label}: PDF is not clearly labeled as a filtered incoming-payment extract")
    if "ausgaben" not in lowered or "erstattungen" not in lowered or "kontosalden" not in lowered:
        report.error(f"{label}: filtered-extract exclusion note is missing")
    if not has_amount(text, Decimal(total_cents) / 100):
        report.error(f"{label}: displayed bank total does not equal manifest transaction sum")


def bank_transactions(record: dict[str, Any]) -> list[dict[str, Any]] | None:
    value = record.get("transaktionen")
    return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else None


def invoice_number(filename: str) -> str | None:
    match = re.search(r"SL-\d{4}-\d{3}", filename)
    return match.group(0) if match else None


def expected_bank_payments(outgoing: list[dict[str, Any]], report: Report) -> list[tuple[Any, ...]]:
    expected: list[tuple[Any, ...]] = []
    for record in outgoing:
        filename = file_name(record)
        if not filename:
            continue
        number = invoice_number(filename)
        if number is None:
            report.error(f"{filename}: no invoice number for bank reconciliation")
            continue
        payments = record.get("zahlungen", [])
        if not isinstance(payments, list):
            report.error(f"{filename}: zahlungen is not a list")
            continue
        for payment in payments:
            if not isinstance(payment, dict):
                continue
            try:
                amount_cents = int(payment["betrag"])
            except (KeyError, TypeError, ValueError):
                report.error(f"{filename}: invalid payment amount")
                continue
            if amount_cents > 0:
                expected.append((
                    payment.get("datum"), amount_cents, record.get("gegenpartei"),
                    filename, f"Zahlung Rechnung {number}", number,
                ))
    return expected


def check_bank_manifest(
    report: Report,
    root: Path,
    bank_records: list[dict[str, Any]],
    outgoing: list[dict[str, Any]],
) -> list[Path]:
    if len(bank_records) != 2:
        report.error(f"bank.json: expected 2 bank documents, found {len(bank_records)}")
    expected = expected_bank_payments(outgoing, report)
    if len(expected) != 7:
        report.error(f"outgoing.json: expected 7 positive settled payments, found {len(expected)}")
    actual: list[tuple[Any, ...]] = []
    bank_paths: list[Path] = []
    for index, record in enumerate(bank_records, 1):
        filename = file_name(record) or f"bank record #{index}"
        path = resolve_pdf(root, "bank", filename) if file_name(record) else None
        if path is None:
            report.error(f"{filename}: bank PDF missing")
        else:
            bank_paths.append(path)
        when = document_date(record)
        if when is None or not DATE_MIN <= when <= DATE_MAX:
            report.error(f"{filename}: bank statement date must be within 2026-07-01..2026-09-21")
        transactions = bank_transactions(record)
        if transactions is None:
            report.error(f"{filename}: bank transaction list missing")
            continue
        total_cents = 0
        for transaction in transactions:
            try:
                amount_cents = int(transaction["betrag"])
            except (KeyError, TypeError, ValueError):
                report.error(f"{filename}: transaction has invalid amount")
                continue
            total_cents += amount_cents
            reference = transaction.get("rechnung_datei")
            transaction_date = document_date({"datum": transaction.get("datum")})
            if amount_cents <= 0:
                report.error(f"{filename}: incoming bank transaction is not positive")
            if transaction_date is None or not DATE_MIN <= transaction_date <= DATE_MAX:
                report.error(f"{filename}: transaction date must be within 2026-07-01..2026-09-21")
            if isinstance(reference, str) and (reference.startswith("03_") or reference.startswith("05_")):
                report.error(f"{filename}: incoming extract references excluded document {reference}")
            actual.append((
                transaction.get("datum"), amount_cents, transaction.get("gegenpartei"),
                reference, transaction.get("verwendungszweck"), transaction.get("belegnummer"),
            ))
        if path is not None:
            check_bank_pdf(report, path, path.name, total_cents)
    if len(actual) != 7:
        report.error(f"bank.json: expected 7 incoming transactions, found {len(actual)}")
    if Counter(actual) != Counter(expected):
        report.error("bank transactions do not exactly match the seven positive outgoing payments")
    if len(bank_paths) != len(set(bank_paths)):
        report.error("bank.json references the same PDF more than once")
    return bank_paths


def check_record(report: Report, root: Path, directory: str, record: dict[str, Any], index: int) -> tuple[Path | None, bool, bool]:
    label = file_name(record) or f"record #{index}"
    raw_name = file_name(record)
    path = resolve_pdf(root, directory, raw_name) if raw_name else None
    if path is None:
        report.error(f"{label}: PDF filename missing or file not found")
    else:
        label = path.name
    when = document_date(record)
    if when is None:
        report.error(f"{label}: primary document date missing")
    elif not DATE_MIN <= when <= DATE_MAX:
        report.error(f"{label}: date {when} outside 2026-07-01..2026-09-21")
    net, tax, gross = amount(record, NET_KEYS), amount(record, TAX_KEYS), amount(record, GROSS_KEYS)
    if gross is None:
        report.error(f"{label}: gross amount missing")
    for name, value in (("net", net), ("tax", tax), ("gross", gross)):
        if value is not None and value.quantize(CENT) != value:
            report.error(f"{label}: {name} {value} is not cent-exact")
    if net is not None and tax is not None and gross is not None and (net + tax).quantize(CENT) != gross.quantize(CENT):
        report.error(f"{label}: net {net} + tax {tax} != gross {gross}")
    paid = payment_state(record)
    if paid is None:
        report.error(f"{label}: payment status missing or unclear")
    rc = is_rc(record)
    if rc:
        expected_rates = {Decimal("0")} if is_outgoing(record) else {Decimal("19"), Decimal("7")}
        if rate(record) not in expected_rates:
            expected = "0 for outgoing or 19/7 for incoming"
            report.error(f"{label}: reverse-charge rate is {rate(record)}, expected {expected}")
        if tax != Decimal("0.00"):
            report.error(f"{label}: reverse-charge tax is {tax}, expected 0.00")
    if path is not None:
        check_pdf(report, path, label, record)
    return path, paid is False, rc


def semantic_checks(report: Report, root: Path, outgoing: list[dict[str, Any]], travel: list[dict[str, Any]]) -> None:
    outgoing_text = [json.dumps(item, ensure_ascii=False).casefold() for item in outgoing]
    phases = [text for text in outgoing_text if "isarblick" in text]
    if len(phases) != 2:
        report.warn(f"outgoing.json: expected two Isarblick phase records, found {len(phases)}")
    if any("phase 1" in text and "phase 2" in text for text in phases):
        report.error("outgoing.json: one record mentions both Isarblick phases")
    for item, text in zip(outgoing, outgoing_text):
        filename = file_name(item) or "outgoing record"
        has_invoice_id = re.search(r"\bsl[- ]?2026[- ]?\d{3}\b", text) is not None
        if "storno" in text and not has_invoice_id and not any(word in text for word in ("referenz", "originalrechnung", "bezug", "invoice")):
            report.warn(f"{filename}: no obvious original-invoice reference")
        payments = item.get("zahlungen", [])
        after_import = item.get("zahlungen_nach_rechnungsimport")
        if not isinstance(after_import, list):
            report.error(f"{filename}: zahlungen_nach_rechnungsimport must be a list")
        if isinstance(payments, list):
            positive_payment = any(isinstance(payment, dict) and int(payment.get("betrag", 0)) > 0 for payment in payments)
            if positive_payment and after_import:
                report.error(f"{filename}: target post-import payment list must remain empty")
            if filename.startswith("05_") and after_import != payments:
                report.error(f"{filename}: refund must remain in zahlungen_nach_rechnungsimport")
            if filename.startswith("03_") and after_import:
                report.error(f"{filename}: unpaid invoice must have no post-import payment")
            if positive_payment:
                path = resolve_pdf(root, "ausgang", filename)
                if path is not None:
                    try:
                        text_pdf = "\n".join(page.extract_text() or "" for page in PdfReader(str(path)).pages).casefold()
                        if re.search(r"\bbezahlt\b|\bzahlungseingang\b|\bzahlung erhalten\b|\berstattet\b", text_pdf):
                            report.error(f"{filename}: paid outgoing invoice still contains a paid/refund note")
                    except Exception as exc:
                        report.error(f"{filename}: cannot inspect payment wording: {exc}")
    trip_dates = {document_date(item) for item in travel}
    if not {date(2026, 9, 14), date(2026, 9, 15), date(2026, 9, 16)} <= trip_dates:
        report.warn("travel.json: primary dates do not cover 14, 15, and 16 September")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=ROOT, help="full path to sample-data/2026-q3")
    root = parser.parse_args().root.resolve()
    report = Report()
    manifests: dict[str, list[dict[str, Any]]] = {}
    booking_paths: list[Path] = []
    unpaid = reverse_charge = 0

    for name, (directory, expected) in MANIFESTS.items():
        path = resolve_manifest(root, name)
        if path is None:
            report.error(f"missing manifest: {name}")
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            report.error(f"{name}: invalid JSON: {exc}")
            continue
        items = records(payload)
        manifests[name] = items
        if len(items) != expected:
            report.error(f"{name}: expected {expected} records, found {len(items)}")
        for index, item in enumerate(items, 1):
            path, is_unpaid, is_reverse_charge = check_record(report, root, directory, item, index)
            if path is not None:
                booking_paths.append(path)
            unpaid += is_unpaid
            reverse_charge += is_reverse_charge

    if len(booking_paths) != len(set(booking_paths)):
        report.error("a booking PDF is referenced more than once")
    if len(set(booking_paths)) != 26:
        report.error(f"booking manifests reference {len(set(booking_paths))} unique PDFs, expected 26")
    if sum(len(items) for name, items in manifests.items() if name in MANIFESTS) != 26:
        report.error("the four booking manifests must describe exactly 26 bookings; bank documents are not bookings")
    if unpaid != 2:
        report.error(f"found {unpaid} unpaid records, expected 2")
    if reverse_charge != 3:
        report.error(f"recognized {reverse_charge} reverse-charge records, expected 3")

    bank_path = resolve_manifest(root, BANK_MANIFEST)
    bank_paths: list[Path] = []
    if bank_path is None:
        report.error(f"missing manifest: {BANK_MANIFEST}")
    else:
        try:
            bank_payload = json.loads(bank_path.read_text(encoding="utf-8"))
            bank_records = records(bank_payload)
            manifests[BANK_MANIFEST] = bank_records
            bank_paths = check_bank_manifest(report, root, bank_records, manifests.get("outgoing.json", []))
        except Exception as exc:
            report.error(f"{BANK_MANIFEST}: invalid JSON or bank check failed: {exc}")
    if len(set(booking_paths + bank_paths)) != 28:
        report.error(f"expected 28 unique PDFs including two bank extracts, found {len(set(booking_paths + bank_paths))}")

    for directory, expected in (("ausgang", 9), ("einkauf", 11), ("reise", 6), ("bank", 2)):
        path = root / directory
        if not path.is_dir():
            report.error(f"missing PDF directory: {directory}/")
        elif len(list(path.rglob("*.pdf"))) != expected:
            report.error(f"{directory}/: expected {expected} PDFs")

    semantic_checks(report, root, manifests.get("outgoing.json", []), manifests.get("travel.json", []))
    print(f"QA root: {root}")
    if report.errors:
        print(f"FAIL: {len(report.errors)} error(s)")
        for message in report.errors:
            print(f"  - {message}")
    else:
        print("PASS: manifest, arithmetic, date, payment, tax, and PDF text checks")
    for message in report.warnings:
        print(f"WARN: {message}")
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
