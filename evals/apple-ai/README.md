# Apple native AI experiments

Standalone experiments, separate from Pfennig's booking workflow. The runnable probes, scoring script and research records live here for bounded native-model evaluation. Apple is not an app provider: no native model option, FoundationModels dependency or Apple adapter is included in `App`, `Sources` or the normal Swift package targets.

The probes import the existing Core and Agent libraries for exact money, SQL validation and shared instructions. They operate only on the public fictional `evals/2026-q3` corpus and disposable repositories. They do not open the development/release archives, request an API key or call OpenAI. Model inference is on-device; these probes do not use Private Cloud Compute.

The small historical API checks are preserved separately under `capabilities/`: `SDKProbe.swift` checks availability/schema and only typechecks its inference helper; `RequiredExitProbe.swift` typechecks the dynamic tool-mode exit pattern. `PCCProbe.swift` is the separate, manual fictional cloud-access probe that failed during research. The receipt build script never compiles or runs it. Compile checks use `xcrun swiftc -parse-as-library -target arm64-apple-macosx27.0`; use `-typecheck` for the exit-profile file. Their retained logs are under ignored `results/capability-probes/`.

## Run a probe

Requires an Apple Silicon Mac, macOS 27, Xcode 27/Swift 6.4 and an available Apple Intelligence model. The build script builds the existing libraries and compiles the standalone executable outside the app targets:

```sh
evals/apple-ai/build.sh
/tmp/pfennig-apple-ai-probe extract ocr-lines-core-units 17 evals/apple-ai/results/hotel-check
```

Run from the repository root. Choose a fresh output directory each time; the runner refuses existing directories so it cannot overwrite evidence. Every probe records its facts/errors, tool calls, actual saved rows, tokens and timing in `result.json`, with the supplied text and instructions beside it. A zero process exit means the diagnostic completed, not that extraction passed: inspect `mismatches` and `error`.

| Command kind and mode | Purpose |
| --- | --- |
| `extract vision` | Direct image/PDF-page attachment, guided decimal-string facts |
| `extract ocr` | Generic Vision text OCR, same fact structure |
| `extract ocr-lines-facts-clean` | Row-preserving OCR, German date components and integer cents |
| `extract ocr-lines-core-units` | Row OCR, euro/cent components, tax derived by existing Core |
| `extract ocr-lines-staged` | Printed summary plus a focused net-line call for mixed VAT; selected in the four-configuration experiment |
| `extract ocr-lines-printed` | Typed printed-summary diagnostic; predecessor with unreliable VAT-group nets |
| `extract ocr-lines-summary` | Summary-instruction diagnostic using the original decimal-string schema |
| `extract document-core-units` | Native document/table recognition with the same Core-based facts |
| `extract ocr-lines-strict` | Regex-guide runtime capability diagnostic |
| `workflow allowed` | Short bookkeeping instructions and raw SQL with ordinary tool calling |
| `workflow guided-allowed` | Narrow typed mutation tools with candidate booking rows supplied |

For typed mutations, use case `s7-chat-private-share` or `s1-scan-for-booked-hotel`. The other recorded workflow modes use persistent `.required`; they intentionally preserve that earlier diagnostic configuration. Apple requires an exit condition for required mode, so those runs can reach the disposable 12-call cap even after a correct write. They do not measure successful whole-agent completion. See the capability report for the documented dynamic-profile exit pattern.

Extraction schemas have different limitations. In particular, the euro/cent variant covers only positive EUR amounts and integer VAT rates. Core-derived tax is not evidence that the model read the document's tax correctly. The scanner, matching tasks and any full workflow need their own checks; do not select a different schema per document and report the combined result as one general importer.

## Compare the fixed fact pilot

The scoring script compares the same seven factual checks on native outputs and stored Luna bookings: date, issuer, receipt number, net, tax, gross and VAT groups. It performs no model call and verifies the saved Luna fixture/truth hashes. Without an experiment manifest, it preserves the original protocol: cases 09, 17 and 42, three native repeats each, in one fixed `ocr-lines-core-units` configuration:

```sh
python3 evals/apple-ai/compare-facts.py \
  evals/apple-ai/results/apple-consistent-facts-20261012-103238 \
  evals/results/exp-exp7-dates-public/report.json
```

Saved Apple evidence is copied locally under `results/`; generated outputs remain ignored by Git. On another machine, run the probes again or restore those synthetic result folders. The historical Luna report remains in the ordinary eval result directory. Greedy repeats show observed repeatability on the same input, not independent evidence from new documents.

## Run a declared extraction experiment

The small wrapper records the complete case/repeat plan before inference, saves a source snapshot, source/binary/truth/file hashes and system information, and retains failures and logs. Runs are sequential with a 180-second process limit; it never calls a cloud provider. Use fresh output folders:

```sh
python3 evals/apple-ai/run-experiment.py ocr-lines-staged \
  evals/apple-ai/results/new-declared-run \
  --cases 09,17,42 --repeats 3 --purpose 'Describe the frozen hypothesis before inference'
python3 evals/apple-ai/compare-facts.py \
  evals/apple-ai/results/new-declared-run \
  evals/results/exp-exp7-dates-public/report.json
```

`--ocr-from RESULTS` reuses each case's first saved OCR text for a paired configuration. Missing runs remain failures in the planned denominator; mixed/unplanned results are rejected. Outgoing bookings store customers rather than document issuers, so the comparator reports their six comparable facts separately and excludes them from the seven-check expense headline. Reconciliation findings are diagnostics only and never repair generated facts.

`ocr-lines-staged` asks for required printed summary fields, supports signed summary/group amounts, and uses integer VAT rates. Its second-stage net-line schema remains positive-EUR-only. A correct single-rate credit does not validate mixed-rate credits. Missing required facts, noninteger rates, foreign currencies, abstention and the booking workflow need separate evidence.

Offline checks:

```sh
python3 -m unittest discover -s evals/apple-ai -p 'test_*.py'
/tmp/pfennig-apple-ai-probe --self-test
```

## Recorded findings

The later four-configuration experiment improved the original development cases from 3/9 to 9/9, but regressed on reserved expense cases from 6/12 to 3/12. It does not validate a general native importer. See the [complete attempt log and paired results](reports/apple-five-experiments-20261012.md). The following table records the earlier pilot:

| Measurement | Native Apple | Historical Luna/high |
| --- | ---: | ---: |
| Whole-agent eight-case pilot | 1/8, only the negative control | 7/8 matched saved repetition |
| One fixed extraction pipeline, three document forms | 3/9 complete fact results | 6/6 complete fact results |
| Same seven factual checks | 48/63 | 42/42 |

The three forms represent two underlying transactions: a receipt and a hotel invoice as PDF/scan. The full-agent and extraction rows measure different tasks. Luna's results are saved 2026-09-25 runs, not a current endpoint benchmark. Two per-document extraction variants and two typed tools achieved 3/3 controlled successes, but no reliable universal pipeline was established.

- [Four configurations and frozen paired validation](reports/apple-five-experiments-20261012.md)
- [Measured feasibility and controls](reports/apple-intelligence-feasibility-20261012.md)
- [Whole-agent pilot and comparison](reports/apple-intelligence-evaluation-20261012.md)
- [Verified Apple APIs and capability probes](reports/apple-intelligence-capabilities-20261012.md)
- [Benchmark investigation](reports/benchmark-investigation-20261012.md)

The earlier app-integrated prototype is preserved at commit `9a18eda` on branch `experiment/apple-intelligence`. Its Apple adapter, settings and full-agent eval changes were never merged into main. That archived revision explains the whole-agent measurements; the standalone probes here measure components and do not reproduce the production inbox/chat/rollback lifecycle. Revisit app integration only after a consistent, broader benchmark provides adequate evidence.

Original isolation verification before the later extraction experiments: all 256 normal project tests and the app build pass. The standalone receipt and typed private-share probes run successfully from main, existing output directories are rejected without changing saved evidence, the comparison script reproduces the recorded scores and correctly fails a missing saved booking, and the three historical API probes typecheck. No app archive or paid API was used.
