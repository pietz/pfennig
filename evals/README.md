# Document intake evaluation

This eval runs the same `FileIntake` and agent tool loop as Pfennig Dev against a temporary, isolated archive for each document. It never writes to the development or release archive. The public Q3 corpus has 37 fictional booking inputs and six controls. The optional private Q3 corpus references 16 real PDFs on this Mac, giving 53 inputs that could create a booking in total. Two public cases repeat a transaction in another file format to measure format sensitivity.

## Datasets

- `2026-q3/ground-truth.json` contains the expected fields for the public PDFs, two rendered receipt images, and an HTML invoice. The files, their generators and source manifests live beside it. Two bank statements, a blank PDF, an unrelated invitation, and empty and invalid files are negative controls.
- `private/q3-2026.json` references the real PDFs in `~/Desktop/Q3-2026-Invoices`. This file, private source PDFs and all eval results are ignored by Git. Do not copy real documents into the repository or commit their extracted values.
- A null field in the private truth means the document does not settle it. These fields are omitted from scoring. `label_uncertainties` records the reason. The public cases set `strict_nulls`: a null optional field must stay empty, and amounts, shares, positions and payments must be given. `accepted_arts`, `accepted_receipt_numbers`, `accepted_due_dates`, `accepted_counterparties`, `accepted_countries`, `accepted_categories` and `accepted_rates` list documented alternatives; a null in `accepted_due_dates`, `accepted_receipt_numbers` or `accepted_countries` accepts an empty field. A payment with a null `betrag` stands for an EUR amount no document states, such as a card charge in USD; the booking's payments must then add up to its gross amount. `accepted_no_booking` permits refusal when the document may belong to another business. Validation rejects unknown keys, unknown enum and category values, invalid dates and decimals not written like `19` or `21.92`.

Both truth sets were checked against the documents. The real set includes foreign-currency invoices without a EUR debit or exchange rate, vendor VAT language that warrants review, and purchases whose business use cannot be established from the document. The eval reports only the supported fields for those cases; it does not certify the underlying tax treatment.

## Run

From the project root, validate both truth files without API use:

```sh
swift run PfennigEval --validate-only
swift run PfennigEval --validate-only --root "$HOME/Desktop/Q3-2026-Invoices" --truth evals/private/q3-2026.json
```

Live runs read `OPENAI_API_KEY` from the environment or from an ignored `.env` in the project root (`OPENAI_API_KEY=...`), never from the app's Keychain entry. Run a small, paid pilot:

```sh
swift run PfennigEval --model gpt-5.6-luna --effort medium --cases 04,07,09,29,37,39
```

For a full public sweep replace `--cases ...` with `--all`; for the real corpus add the private `--root` and `--truth` arguments above. Other app models are `gpt-6-luna`, `gpt-5.6-terra` and `gpt-5.6-sol`. Effort values are `none`, `low`, `medium`, `high`, `xhigh`, and `max`. `--repeats 2` reruns each case in a fresh archive. `--jobs 20` runs up to 20 cases at once, each in its own archive. `--rules path/to/rules.txt` substitutes the app's short agent rules while retaining its tool and schema instructions. `--output path` selects a report directory; the default is under ignored `evals/results/`.

If a reviewed truth label changes, score a saved run again without another API call:

```sh
swift run PfennigEval --rescore evals/results/RUN/report.json
```

Add the private `--root` and `--truth` options when rescoring a real-document run. The command checks source file hashes and writes a separate scored report plus a truth snapshot beside the original, or into `--output`.

Each document reaches the model under the neutral name `dokument.<ext>`, so a descriptive file name cannot answer what the document should. Each run snapshots its truth file and saves the report after every case. The report records the model, effort, truth and rule hashes, the rendered prompt and its hash, source file hashes, tokens, time, outcome, field mismatches, bookings, and agent traces. It reports total pass rate and a separate pass rate for cases that reached the agent. Empty and invalid PDF controls pass only when the agent declines to book or the API rejects the input with 400/422; API rejection is excluded from agent accuracy, and network and authentication errors fail. Compare pass rates by case and field across configurations. The first pilot should include controls and both easy and difficult bookings before a full sweep. A live run calls the OpenAI API.

Regenerate the synthetic PDFs with the six scripts in `2026-q3/sources/` (`outgoing.py`, `purchases.py`, `equipment-services.py`, `travel.py`, `bank.py`, `extra.py`) plus `controls.py`; then run `modalities.py` for the image and HTML cases. Run `verify.py` for the original 28-document accounting checks. The PDFs themselves carry no marker that instructs the agent to reject them. Keep the source directory outside any drag-and-drop import.
