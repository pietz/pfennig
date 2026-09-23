# Independent QA notes

## Final 28-document set

- Verified with the absolute-path command below on 2026-09-21.
- Result: pass for 26 booking PDFs plus two bank PDFs. Booking manifests contain 9 outgoing, 7 purchases, 4 equipment/services, and 6 travel records. All 28 PDFs are unique, one page, nonempty in text extraction, cent-arithmetic consistent, date-valid through 2026-09-21, and free of em-dash and missing-glyph markers.
- The two bank extracts contain exactly seven positive incoming transactions. They match the seven positive settled `zahlungen` in `outgoing.json` one-for-one by date, amount, counterparty, invoice filename, usage text, and reference. The split is four transactions in July/August totaling 7,973.00 EUR and three in September totaling 3,868.20 EUR, including the 2026-09-21 payment for invoice 04.
- `zahlungen_nach_rechnungsimport` is empty for the seven paid outgoing invoices and for unpaid invoice 03; the negative refund for invoice 05 remains represented there. The seven paid outgoing PDFs contain no paid-status note. The bank PDFs are explicitly filtered incoming extracts and state that expenses, refunds, and balances are excluded. Bank documents are not counted as new bookings.
- Travel gross total is 868.88 EUR. The hotel total is 330.76 EUR with room at 7 %, breakfast food at 7 %, and breakfast drinks at 19 %.
- Visual samples from each layout family showed no clipping or overlap. The cancellation names `SL-2026-071` and the PDF itself link the August partial cancellation to the July invoice. The two Isarblick phase PDFs remain separate.
- The RC check is direction-aware: outgoing Austrian income may show German rate 0 and tax 0; incoming RC expenses must show self-assessed rate 19 % or 7 % and tax 0.

```sh
uv run --python 3.13 /Users/pietz/Private/pfennig/sample-data/2026-q3/sources/verify.py /Users/pietz/Private/pfennig/sample-data/2026-q3
```

## Tax note review

The cited official sources support the travel rates used here:

- UStG section 12: 19 % standard; 7 % for qualifying passenger transport and short-term lodging; restaurant and catering services at 7 % except drinks.
- BMF letter dated 2025-12-22: the restaurant and catering change applies to turnover from 2026-01-01 and excludes drinks. It also gives a 30 % drinks allocation for certain bundled offers, which is not needed because this sample invoice itemizes the components.
- UStAE consolidated 2026-06-02, section 12.16 paragraphs 8 and 12: hotel extras such as breakfast are subject to the separation rule rather than automatically inheriting the room rate. The sample itemizes room, breakfast food, and breakfast drinks.

## Scope boundary

The check covers document structure and manifest consistency only. It does not claim agent import accuracy, tax advice, or database behavior. The app was not modified.
