# OpenAI Responses API — Reference Notes for Pfennig

Researched from the official docs at https://developers.openai.com/api/docs on 2026-09-12.
Scope matches concept.md sections 10, 13, 41, 42: direct HTTPS calls (no SDK) from Swift, PDF/image
extraction with strict Structured Outputs, no tool/function-calling loop in V1.

---

## 1. Endpoint, Auth, Minimal Request, File/Image Input

Source: https://developers.openai.com/api/docs/guides/text ,
https://developers.openai.com/api/reference/resources/responses/methods/create ,
https://developers.openai.com/api/docs/guides/file-inputs ,
https://developers.openai.com/api/docs/guides/images-vision

**Endpoint:** `POST https://api.openai.com/v1/responses`

**Auth header:**
```
Authorization: Bearer $OPENAI_API_KEY
Content-Type: application/json
```

**Minimal request body** (only `model` and `input` are required):
```json
{
  "model": "gpt-6-astra",
  "input": "Write a one-sentence bedtime story about a unicorn."
}
```

### PDF as inline file input

Three ways to submit a PDF: base64 inline (`file_data`), a previously uploaded file (`file_id` from
`/v1/files`), or `file_url`. For Pfennig (no server-side file storage), use inline base64:

```json
{
  "model": "gpt-6-astra",
  "input": [
    {
      "role": "user",
      "content": [
        {
          "type": "input_file",
          "filename": "invoice.pdf",
          "file_data": "data:application/pdf;base64,JVBERi0xLjQKJ...",
          "detail": "high"
        },
        { "type": "input_text", "text": "Extract the invoice fields." }
      ]
    }
  ]
}
```

For vision-capable models (gpt-4o and later, which includes all four models covered in section 4),
the API performs **dual extraction** on a PDF: it extracts the raw text layer *and* renders each page
as an image, sending both to the model. This is why PDF input costs more tokens than a plain text
file (.txt/.docx). `detail` on `input_file` controls only the rendered-page-image fidelity (`low` /
`high`; `auto` defaults to `high` on GPT-5.6+ and to `low` on older models); extracted text is always
included regardless of `detail`.

**Size/page limits (as documented by OpenAI):** each file must be < 50 MB; the combined size of all
files in one request must also be < 50 MB. No explicit maximum page count for PDFs is documented by
OpenAI — Pfennig's own ≤20-page default (concept.md 10.4) is an app-level choice, not an API limit.
Spreadsheet-type files (.xlsx/.csv when sent as a file rather than parsed locally) are capped at the
first 1,000 rows per sheet — not relevant to Pfennig's PDF/image path but worth knowing since it also
uses `input_file`.

### Image as inline data URL

```json
{
  "type": "input_image",
  "image_url": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEA...",
  "detail": "auto"
}
```

Supported formats: PNG, JPEG (`.jpeg`/`.jpg`), WEBP, and non-animated GIF — matches concept.md 10.4's
note that HEIC must be converted locally to JPEG before upload (HEIC is not accepted).
`detail` accepts `low`, `high`, `original` (best for OCR/spatially sensitive tasks), or `auto`
(default). Limits: request payload up to 512 MB total, up to 1,500 images per request, up to 30,000
"patches" per image (model-dependent internal resizing), and a model-specific max dimension between
2,048 and 65,535 px. None of these are binding for Pfennig's single-document-per-request use case.

---

## 2. Structured Outputs (`text.format`, `json_schema`, `strict: true`)

Source: https://developers.openai.com/api/docs/guides/structured-outputs

Request shape:
```json
{
  "model": "gpt-6-astra",
  "input": [
    { "role": "system", "content": "You are a helpful math tutor." },
    { "role": "user", "content": "How can I solve 8x + 7 = -23?" }
  ],
  "text": {
    "format": {
      "type": "json_schema",
      "name": "math_response",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {
          "steps": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "explanation": { "type": "string" },
                "output": { "type": "string" }
              },
              "required": ["explanation", "output"],
              "additionalProperties": false
            }
          },
          "final_answer": { "type": "string" }
        },
        "required": ["steps", "final_answer"],
        "additionalProperties": false
      }
    }
  }
}
```

**Hard rules under `strict: true`:**
- Every object's `properties` must **all** be listed in `required`. There is no concept of an
  optional key — this directly matches concept.md 10.6 ("All properties are required").
- Every object must set `"additionalProperties": false`.
- To model an optional/nullable value, keep the key in `required` but widen its `type` to include
  `null` — either `"type": ["string", "null"]` or `"anyOf": [{"type": "string"}, {"type": "null"}]`.
  Enums that must allow "absent" add `null` as a literal enum member, e.g.
  `{"type": ["string", "null"], "enum": ["violence", "sexual", "self_harm", null]}`.
- Supported keywords confirmed in examples: `type`, `properties`, `required`, `additionalProperties`,
  `items`, `enum`, `$ref`, `description`. OpenAI's own guide states structured outputs "supports much
  of JSON Schema, but some features are unavailable" without giving a single canonical list in the
  fetched page — treat any keyword not seen in an official example (e.g. `pattern`, `format`,
  `minLength`/`maxLength`, `minimum`/`maximum` on numbers) as unverified and test against the live API
  before relying on it.
- No explicit numeric limits on enum member count, nesting depth, or total schema size were stated in
  the fetched guide. Historically OpenAI has enforced a total schema size ceiling and a max nesting
  depth for strict schemas; since the exact current numbers were not present in the fetched content,
  do not hardcode assumed limits — validate empirically with the production `ExtractionSchema.swift`
  and fall back to flattening/splitting the schema if the API rejects it as too large/deep.

This confirms Pfennig's plan in concept.md 10.6 (all-required + `anyOf`-with-null for optionals) is the
correct and only supported pattern for strict Structured Outputs.

---

## 3. Reasoning Models (`reasoning.effort`, token accounting, `max_output_tokens`)

Source: https://developers.openai.com/api/docs/guides/reasoning ,
per-model pages under https://developers.openai.com/api/docs/models/

Request shape:
```json
{
  "model": "gpt-6-astra",
  "reasoning": { "effort": "low" },
  "input": [{ "role": "user", "content": "Write a bash script..." }]
}
```

**Valid `reasoning.effort` values documented:** `none`, `minimal`, `low`, `medium`, `high`, `xhigh`,
`max`. Default is `medium` for the gpt-5.6 and gpt-6 families. Per-model pages for gpt-5.6-sol,
gpt-5.6-terra, and gpt-5.6-luna explicitly list `none, low, medium (default), high, xhigh, max` as
supported; **GPT-6 Astra does not support `none`** (its page lists `low, medium, high, xhigh, max`).
The general reasoning guide separately mentions `minimal` as a value that exists on some reasoning
models — it was not listed on any of the four model-specific pages fetched, so treat "minimal" as
unsupported for this model family unless verified live.

**Token accounting:** reasoning tokens are generated but never returned in the visible output; they
still occupy context-window space and are **billed as output tokens**. The count appears in the
response under:
```json
{ "usage": { "output_tokens_details": { "reasoning_tokens": 1024 } } }
```
`max_output_tokens` caps the *total* of reasoning tokens + visible output tokens + internal
formatting tokens combined — not just the visible text. If the cap is hit before a final answer is
produced, the response comes back with `status: "incomplete"` and
`incomplete_details.reason: "max_output_tokens"` (i.e. you can pay for reasoning tokens and still get
no usable output). OpenAI's own guidance: reserve **at least 25,000 tokens** for reasoning + output
when starting out with these models, and increase from there per task complexity — a single-invoice
extraction call should budget comfortably above the token count of the JSON schema output itself.

---

## 4. Model IDs, Pricing, Context Windows, Capabilities

Source: https://developers.openai.com/api/docs/pricing ,
https://developers.openai.com/api/docs/models/gpt-6-astra ,
https://developers.openai.com/api/docs/models/gpt-5.6-sol ,
https://developers.openai.com/api/docs/models/gpt-5.6-terra ,
https://developers.openai.com/api/docs/models/gpt-5.6-luna

| Model | Model ID | Context window | Max output tokens | Vision (image) | PDF file input | Structured Outputs |
|---|---|---|---|---|---|---|
| GPT-6 Astra | `gpt-6-astra` | 1,050,000 tokens | 128,000 | Yes | Yes (vision-capable) | Yes |
| GPT-5.6 Sol | `gpt-5.6-sol` | 1,050,000 tokens | 128,000 | Yes | Yes | Yes |
| GPT-5.6 Terra | `gpt-5.6-terra` | 1,050,000 tokens | 128,000 | Yes | Yes | Yes |
| GPT-5.6 Luna | `gpt-5.6-luna` | 1,050,000 tokens | 128,000 | Yes | Yes | Yes |

All four support PDF file input because PDF parsing (text + rendered page images) requires only
"vision capability," which all four have; output modality for all four is text-only (no native image
generation).

**List pricing, standard tier, per 1M tokens** (from the official pricing page at fetch time):

| Model | Input | Output | Long-context input (>272K tokens) | Long-context output |
|---|---|---|---|---|
| `gpt-6-astra` | $10.00 | $50.00 | $20.00 | $75.00 |
| `gpt-5.6-sol` | $4.00 | $20.00 | $8.00 | $30.00 |
| `gpt-5.6-terra` | $2.00 | $12.00 | $4.00 | $18.00 |
| `gpt-5.6-luna` | $0.20 | $1.20 | $0.40 | $1.80 |

Caveat: third-party trackers (OpenRouter, CometAPI, etc.) report these same figures as *promotional*
pricing in effect since mid/late 2026 (list price before the promotion was materially higher, e.g. Sol
at $5/$30). Since Pfennig takes the user's own API key and pricing can change, do not hardcode these
numbers into UI cost estimates without a "prices as of" disclaimer and an easy way to update them; the
official pricing page above is the authoritative live source to re-check periodically, not this doc.

Knowledge cutoffs: gpt-5.6 family — February 16, 2026; gpt-6-astra — April 30, 2026.

---

## 5. Response Shape, Refusals, Incomplete Responses, Usage

Source: https://developers.openai.com/api/reference/resources/responses/methods/create

The top-level response has an `output` array, not a single message — **do not assume
`output[0].content[0].text`**; the array can contain multiple items (e.g. reasoning items followed by
a message item), and the docs explicitly warn against that assumption. Extract text by scanning
`output` for the item with `"type": "message"` and then its `content` array for
`"type": "output_text"`:

```json
{
  "output": [
    {
      "id": "msg_67b73f697ba4819183a15cc17d011509",
      "type": "message",
      "role": "assistant",
      "content": [
        { "type": "output_text", "text": "{...extracted JSON...}", "annotations": [] }
      ]
    }
  ]
}
```

**Refusals:** a content item can instead be `{"type": "refusal", "refusal": "<reason text>"}` in place
of `output_text`. Pfennig's extraction call must check for this content-item type explicitly and
surface it as a failed extraction rather than trying to JSON-parse it as the schema.

**Status / incomplete detection:** `status` is one of `in_progress`, `completed`, `incomplete`,
`failed`. When `status == "incomplete"`, `incomplete_details.reason` explains why (e.g.
`"max_output_tokens"`, or content-filter related reasons). Pfennig should treat any non-`completed`
status as "extraction did not succeed," not attempt to salvage partial JSON.

**Usage object fields:**
```json
{
  "usage": {
    "input_tokens": 123,
    "output_tokens": 456,
    "output_tokens_details": { "reasoning_tokens": 100 },
    "total_tokens": 579
  }
}
```
(`reasoning_tokens` nested under `output_tokens_details` per section 3 above, not a flat field.)

---

## 6. Errors and Rate-Limit Headers (for retry/backoff)

Source: https://developers.openai.com/api/docs/guides/error-codes ,
https://developers.openai.com/api/docs/guides/rate-limits

**Retryable (transient) errors** — back off and retry:
- `429` — "Rate limit reached for requests" (too many requests/tokens per minute)
- `429` — "Slow down" (ramped traffic more than +50% within 15 minutes at 1M+ TPM)
- `500` — generic server error
- `503` — "Model temporarily overloaded" (insufficient capacity)

**Non-retryable errors** — surface to the user, do not blindly retry:
- `401` — invalid/revoked API key, wrong org, or IP not on allowlist (all directly relevant: Pfennig
  stores a user-supplied key in Keychain per concept.md 10.5, so a bad/revoked key must produce a
  clear "check your API key" UI state, not a silent retry loop)
- `403` — country/region not supported
- `429` — "Credit balance exhausted," "Organization/project spend limit reached," "Organization usage
  limit reached" — all billing-state errors; retrying does nothing until the user acts
- `400` — bad request (e.g. invalid `service_tier`, malformed schema)

**Retry guidance:** always honor a `Retry-After` header (seconds to wait) when present; if absent, use
exponential backoff with jitter. Cap both retry count and total elapsed time. Note explicitly stated
by OpenAI: "unsuccessful requests contribute to your per-minute limit" — hammering retries can itself
worsen throttling.

**Rate-limit response headers to read for adaptive pacing:**

| Header | Meaning |
|---|---|
| `retry-after` | seconds to wait before retrying (present on 429/503) |
| `x-ratelimit-limit-requests` | request-per-window ceiling |
| `x-ratelimit-limit-tokens` | token-per-window ceiling |
| `x-ratelimit-remaining-requests` | requests left in current window |
| `x-ratelimit-remaining-tokens` | tokens left in current window |
| `x-ratelimit-reset-requests` | time until request window resets |
| `x-ratelimit-reset-tokens` | time until token window resets |
| `x-ratelimit-limit-project-tokens` / `-remaining-project-tokens` / `-reset-project-tokens` | same, scoped to the project rather than the key |

For Pfennig (single-user desktop app, one document at a time in the common case, but batch-import of
many invoices is a real scenario per concept.md 12), a simple sequential import queue that reads
`x-ratelimit-remaining-requests`/`-tokens` and throttles proactively, plus honors `Retry-After` on
429/503 with exponential backoff and jitter, is sufficient — no need for a token-bucket scheduler in
V1.

---

## 7. Data Controls (for docs/privacy.md)

Source: https://developers.openai.com/api/docs/guides/your-data

- **Training:** "data sent to the OpenAI API is not used to train or improve OpenAI models" by
  default, and has been since March 1, 2023; opting in to share data for training requires explicit,
  affirmative action by the account owner — not something Pfennig would ever trigger on the user's
  behalf.
- **Retention (abuse monitoring):** prompts/responses/derived metadata are retained up to **30 days**
  for abuse-monitoring purposes by default, unless a legal obligation requires longer.
- **Retention (application state):** the Responses/Chat Completions endpoints themselves are
  effectively stateless — no persistent storage of the conversation beyond the abuse-monitoring
  window — with narrow exceptions: audio outputs retained ~1 hour, prompt-cache artifacts up to ~24
  hours. (Pfennig does not use Assistants/threads/vector stores, whose retention rules differ and are
  not relevant here.)
- **Zero Data Retention (ZDR):** eligible/approved organizations can have customer content excluded
  even from the 30-day abuse-monitoring logs; this requires an approval process with OpenAI and is an
  org-level setting, not something the app can toggle per-request. Not attainable for individual
  users bringing their own consumer API key, so Pfennig's privacy doc should describe the *default*
  (30-day abuse-log retention, no training use) rather than assume ZDR.
- **CSAM-detection exception:** image/file inputs may be retained for CSAM detection regardless of
  the retention settings above — worth a one-line disclosure in docs/privacy.md since invoices are
  images/PDFs.
- Third-party tool integrations (MCP servers, code interpreter, etc.) have separate data-handling
  terms — not applicable, since Pfennig's V1 makes no tool calls (concept.md 10.2, 11).

**Suggested one-paragraph summary for docs/privacy.md:** "Pfennig sends document images/PDFs and
extracted-context text to OpenAI's API using your own API key. Per OpenAI's data policy, this data is
not used to train OpenAI's models and is retained by OpenAI for up to 30 days for abuse monitoring
before deletion (longer only if legally required); OpenAI may also retain image/file inputs
specifically for CSAM detection. Pfennig does not store your API key anywhere except the macOS
Keychain, and does not run any of its own servers."

---

## Sources

- https://developers.openai.com/api/docs
- https://developers.openai.com/api/docs/guides/text
- https://developers.openai.com/api/reference/resources/responses/methods/create
- https://developers.openai.com/api/docs/guides/file-inputs
- https://developers.openai.com/api/docs/guides/images-vision
- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/docs/guides/reasoning
- https://developers.openai.com/api/docs/guides/reasoning-best-practices
- https://developers.openai.com/api/docs/pricing
- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://developers.openai.com/api/docs/models/gpt-5.6-sol
- https://developers.openai.com/api/docs/models/gpt-5.6-terra
- https://developers.openai.com/api/docs/models/gpt-5.6-luna
- https://developers.openai.com/api/docs/guides/error-codes
- https://developers.openai.com/api/docs/guides/rate-limits
- https://developers.openai.com/api/docs/guides/your-data
