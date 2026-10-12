# Apple local evaluation, 2026-10-12

Historical measurements from the archived `experiment/apple-intelligence` checkout, retained on 2026-10-12. The normal app has no Apple provider. See the [isolated eval README](../README.md) for current standalone commands; full-agent commands below require the archived integration revision.

The current Apple prototype passes **1/8 cases (12.5%)**, versus **7/8 (87.5%)** for the same case IDs and repetition 1 in the saved Luna/high report: an observed **75 percentage point gap**. Apple's only pass is the negative control. It completes **0/7 positive booking, lookup or correction tasks**, creates no bookings and changes no existing booking. Keep this integration experimental; it is not suitable as Pfennig's default in its current form.

## Scope and comparability

This was one sequential pass through eight public fictional cases, with the existing isolated-archive runner, current scoring and no source changes. Native report: [report.json](../results/apple-native-eight-ready-20261012/report.json). All eight cases are agent-evaluable; these are live quality failures, not the earlier `modelNotReady` infrastructure failures. No additional accuracy repetitions or full-corpus run followed the broad failures. No paid OpenAI call, credential access, private corpus or real app archive was used.

The comparator is the saved `gpt-6-luna`/high report generated on 2026-09-25, restricted to exactly these eight IDs and repetition 1: [selected historical report](../results/apple-native-eight-ready-20261012/historical-luna-high-selected-repetition1.json). Its original remains `/Users/pietz/Private/pfennig/evals/results/exp-exp7-dates-public/report.json`, unchanged. Both saved Luna repetitions across these IDs score 15/16; the lookup case fails repetition 1 and passes repetition 2. The primary comparison uses only repetition 1, matching Apple's sample size.

All selected fixture hashes and the ground-truth hash match. Both prompts pin the bookkeeping date to **2026-09-24**. The historical report records a rules override, but comparing its saved public prompt with the current native prompt shows **only one extra blank line after the rules**. There is no substantive instruction difference in these saved prompts, and the referenced override file was not accessed.

This is still a historical comparison, not a fresh measurement of today's Luna endpoint. Inference dates/provider model snapshots differ, as do the adapters: native PDF pages are rendered images, whereas Responses receives original PDFs; native visible-history replay/tool wrappers also differ. Historical system load and concurrency are not controlled. The findings describe this Apple integration, not every possible application of Apple's model.

## Results

| Case | Apple result and latency | Historical Luna repetition 1 | Observed native behavior |
| --- | --- | --- | --- |
| 03, unpaid outgoing invoice | Fail, 9.43 s | Pass, 9.30 s | Reads the EUR 4,522 total but calls the outgoing invoice an expense, invents 23.11.2023 instead of 21.09.2026, and uses the wrong counterparty/category/tax treatment. No tools or booking. |
| 07, paid USD software invoice | Fail, 10.15 s | Pass, 31.67 s | Reads USD 86.40 and EUR 79.92, but changes the date and supplier country and never books. The EUR amount is explicitly documented as the card debit, so no currency lookup was required. |
| 09, ordinary receipt | Fail, 11.63 s | Pass, 8.08 s | Reads the receipt number and EUR 29.39 total, but reverses 04.08 to 08.04, misidentifies the counterparty/category and prints malformed SQL as prose. No tool call; claims it was booked. |
| 17, hotel PDF with mixed VAT | Fail, 13.83 s | Pass, 10.89 s | Invents three bookings with a 2020 date and unrelated small amounts rather than the single EUR 330.76 transaction with 7%/19% positions. No tools or booking. |
| 38, invitation control | Pass, 5.07 s | Pass, 1.77 s | Correctly identifies an invitation without a receipt/payment and creates nothing. The expected import `noBooking` failure is a passing negative control. |
| 42, scanned hotel invoice | Fail, 10.60 s | Pass, 12.90 s | Invents EUR 3,216, an October date, hospitality category and depreciation, then claims booking ID 101 was created. No tools or booking. |
| s1, scan for an already booked hotel | Fail, 35.99 s | Fail, 8.10 s | Makes four invalid INSERT calls, performs no lookup and leaves the seed booking's original receipt list unchanged. Claims success. Historical Luna also fails this repetition, by creating a duplicate booking instead of attaching the scan. |
| s7, German chat private-share correction | Fail, 4.20 s | Pass, 5.16 s | Makes no SELECT or UPDATE, asks for details already in the archive and says 50% corresponds to 0%. The seed booking remains at 0%, instead of the requested 50%. The chat turn itself completes without an exception. |

Five expected new transactions are entirely missing; neither of the two seeded tasks is completed. The seeded bookings' correct existing amounts/categories do not count as successful native extraction. Fluent German text and some correctly read receipt fields do not translate into reliable accounting or tool use. The scanned invoice and mixed-VAT PDF both fail materially.

## Tools, errors and safety

Only the lookup case invokes tools: four `sql` calls, with **zero successful writes**. Two calls use nonexistent columns (`noten`, then `gewuerk`); two have incomplete SQL syntax. SQLTool rejects all four before any booking is saved. There are no SELECT calls and no currency-tool calls. The paid USD fixture therefore does not establish native reference-rate lookup capability.

Six positive imports finish with `noBooking`; the invitation has the same expected outcome, and the chat correction fails only its final private-share check. There is no observed availability, context-overflow, guardrail-refusal or tool-budget error in this pilot. The shared import completion gate prevents false-success prose from becoming a successful import. Cases 09, 42 and s1 explicitly claim a saved booking despite no successful write. Safety prevented persistence here; it did not make the answers accurate. These malformed attempts do not test whether Core would catch every plausible but factually wrong valid booking.

The preceding isolated case-09 probe had three rejected SQL calls and took 42.64 s; this pass of the same case makes no tool calls and takes 11.63 s. That establishes behavior variability, not an additional representative accuracy estimate. Its separate report is `evals/results/apple-native-first-ready-20261012/report.json`.

## Reported usage and latency

| Metric, eight selected runs | Apple local | Historical Luna/high, repetition 1 |
| --- | ---: | ---: |
| Passes | 1/8 | 7/8 |
| Positive tasks completed | 0/7 | 6/7 |
| Mean run latency | 12.61 s | 10.98 s |
| Median run latency | 10.38 s | 8.70 s |
| Sum of per-case durations | 100.91 s | 87.87 s |
| Reported input tokens | 18,851 | 70,534 |
| Reported output tokens | 1,768 | 7,848 |
| Mean reported input/output tokens | 2,356 / 221 | 8,817 / 981 |

Native mean latency is 1.63 s higher in these recorded runs, but it performs virtually none of the requested database work. These numbers cannot establish a speed/throughput advantage. Provider tokenization, image input and framework versus cumulative Responses/tool-loop accounting differ, so the token counts are not equivalent cost or context measurements.

## Evidence and reproduction

Machine-readable derived metrics, matched-file checks and per-case tool errors are in [comparison.json](../results/apple-native-eight-ready-20261012/comparison.json). The unchanged existing comparison command produced [comparison.txt](../results/apple-native-eight-ready-20261012/comparison.txt). Native visible tool/message traces are in that same result directory. No provider reasoning was included in the derived comparison.

Native prompt SHA-256: `4690b6ae357b3965f3ed01b992be94e44388425150fcb6ef6515bcf721eb0fa6`. Historical prompt: `fe390c704ffce64996e33786a0947df1ac91cfdca8e5034f954c449495f697f6`. Shared truth: `631350547a87083546e16538cc7bac1aa30b8fcc505b6a13b5a468bfd683cef3`. Implementation revision: `c571ad9`. Native report generated at `2026-10-12T06:01:54Z`.

```sh
.build/arm64-apple-macosx/debug/PfennigEval \
  --root /Users/pietz/Private/pfennig/evals/2026-q3 \
  --truth /Users/pietz/Private/pfennig/evals/2026-q3/ground-truth.json \
  --model apple-on-device \
  --cases 03,07,09,17,38,42,s1-scan-for-booked-hotel,s7-chat-private-share \
  --jobs 1 --output evals/results/apple-native-eight-ready-20261012

.build/arm64-apple-macosx/debug/PfennigEval --compare \
  evals/results/apple-native-eight-ready-20261012/historical-luna-high-selected-repetition1.json \
  evals/results/apple-native-eight-ready-20261012/report.json
```

The output directory already exists; choose a new one for any authorized future run. The evaluation log is `/tmp/pfennig-apple-eight-ready-eval.log`. No source, existing experiment/status document, app setting, real archive, installed app, commit or push changed during this evaluation task.
