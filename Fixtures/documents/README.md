# Synthetic Test Documents

All documents in this directory are **entirely fictional**: company names, VAT
IDs, IBANs, invoice numbers, and street addresses are invented. Cities are
real; streets are not. None of the counterparties represent real businesses.

Each fixture is a folder `<nn>-<slug>/` containing:

- `document.pdf` or `document.jpg` - the synthetic source document
- `expected.json` - ground truth matching the extraction schema in
  `concept.md` §13 (`documentType`, `direction`, `title`, `counterparty`,
  `invoice`, `taxComponents`, `taxTreatmentHint`, `lineItems`, `paymentInfo`,
  `missingFields`). `counterparty.name` is the short trade name and `title`
  the short German ledger phrase the prompt asks for.

Regenerate everything with:

```sh
uv run Fixtures/generator/generate.py
```

The business recipient on every expense document is:

```
Mara Beispiel, Freelance Software Development, Musterstraße 12, 10115 Berlin, USt-IdNr. DE999999999
```

## Fixtures

| # | Folder | What it tests |
|---|---|---|
| 01 | `01-irish-saas-reverse-charge` | EU SaaS subscription from Ireland, EUR 71.39, explicit "VAT reverse charged" note, service period Aug 2026. Exercises §13b **reverseCharge** on an expense with a stated service period but no discrete `serviceDate` (`missingFields`). |
| 02 | `02-german-hosting-monthly` | German hosting invoice, 19% VAT, net 40.00, monthly recurring, IBAN + SEPA-Lastschrift hint. Exercises plain **domesticVAT** with direct-debit payment info. |
| 03 | `03-office-supplies-kassenbon` | Narrow thermal-receipt-style till receipt (Kassenbon), gross 23.80 with one 19% and one 7% item, no invoice number, no customer address. Exercises **Kleinbetragsrechnung** (§33 UStDV) relaxation and mixed tax rates on a single small receipt. |
| 04 | `04-bahn-ticket-mixed-vat` | Deutsche-Bahn-style train ticket (A6 layout) with a 7% fare component and a 19% seat-reservation component. Exercises mixed `taxComponents` on domestic transport. |
| 05 | `05-hotel-invoice-lodging-breakfast` | Hotel invoice with 7% lodging and 19% breakfast, explicit stay dates (`servicePeriodStart/End`). Exercises the classic hotel VAT split. |
| 06 | `06-us-software-usd-reverse-charge` | US software vendor invoice in USD 1,000.00, no VAT shown, explicitly states no EUR equivalent. Exercises foreign-currency **reverseCharge** (§13b applies to third-country digital services too). |
| 07 | `07-uk-consultancy-gbp-reverse-charge` | UK (third-country) consultancy invoice in GBP with a stated EUR equivalent and an explicit reverse-charge note. Exercises **reverseCharge** on a foreign-currency document (§16 Abs. 6 UStG). |
| 08 | `08-hardware-laptop-asset-candidate` | German laptop purchase, net 1,850.00 + 19% VAT. Exercises the **GWG asset threshold** (net > 800 EUR in a hardware category, category `hardware_equipment`); the asset flag is Swift's decision, not the model's. |
| 09 | `09-hardware-monitor-small` | German monitor purchase, net 299.00 + 19% VAT, same vendor as #08. Exercises a hardware purchase **below** the GWG threshold (`hardware_small`) for contrast with #08. |
| 10 | `10-income-invoice-domestic-gmbh` | Outgoing invoice from Mara Beispiel to a German GmbH client, net 4,500.00 + 19% VAT, invoice number `RE-2026-0042`. Exercises a plain **income / domesticVAT** transaction. |
| 11 | `11-income-invoice-france-reverse-charge` | Outgoing invoice from Mara Beispiel to a French SARL with a valid EU VAT ID, no VAT charged, reverse-charge note. Exercises **income reverseCharge** (EU B2B service, Art. 44 MwStSystRL). |
| 12 | `12-credit-note-hosting` | Gutschrift (credit note) from the vendor in #02, -40.00 net, explicitly referencing invoice `NH-100234`. Exercises `documentType: creditNote` with negative amounts and a cross-document reference. |
| 13 | `13-telecom-deposit-line` | Telecom invoice with a 19% usage-charge component and a 0% "Kaution/Vorschuss" (deposit) line. Exercises `taxComponentKind: deposit` alongside `standard`. |
| 14 | `14-cafe-receipt-photo` | JPEG "photographed" café receipt (slight rotation, blur, and pixel noise), gross 18.50 with mixed 7%/19% items, paid cash. Exercises image-based (non-PDF) receipt ingestion and mixed rates on a Kleinbetrag receipt with no invoice number. |

## Regeneration

The generator lives in `Fixtures/generator/generate.py` (PEP 723 inline
script metadata; dependencies: `reportlab`, `Pillow`). It is deterministic
except for fixture 14's pixel noise, which uses a fixed random seed.

```sh
uv run Fixtures/generator/generate.py
```
