# Apple native capabilities and bounded experiments, 2026-10-12

Historical measurements from the archived `experiment/apple-intelligence` checkout, retained on 2026-10-12. The normal app has no Apple provider. See the [isolated eval README](../README.md) for current standalone commands; full-agent commands below require the archived integration revision.

The eight-case pilot completes no positive bookkeeping tasks: one negative-control pass, versus seven of eight in the matched saved Luna repetition. Native input already uses **direct image Attachment and rendered PDF pages**, not generic OCR text. It is therefore premature to blame the failures only on OCR or to call direct vision the missing feature. Missing tool calls, invented SQL columns and mistaken document facts are separate failure modes. See [pilot assessment](apple-intelligence-evaluation-20261012.md).

## Verified API and environment

Read-only SDK/source review and disposable compiler/runtime probes: macOS 27.0.1 build 26A434; Xcode **27.0 build 27A266a**; active SDK **27.0**. The probe reports on-device `.available`, `contextSize == 8192`, German supported. `xcrun swiftc -parse-as-library -target arm64-apple-macosx27.0` compiles all snippets below with the active Xcode toolchain, without plugin-path workarounds. This supersedes the earlier CLT-only workaround.

Artifacts: `/tmp/pfennig-sdk27-capabilities.swift`, `/tmp/pfennig-sdk27-capabilities-compile.log` (empty, clean compile), `/tmp/pfennig-sdk27-capabilities-runtime.log`. The capability compile probe's response-producing helper was **not invoked**. It queried only availability, context, locale, tool name and generated type schema. A later separately authorized PCC probe attempted one tiny fictional request and failed immediately; details below. No private documents, credentials, app archive, account/entitlement changes or terms acceptance.

## Experiment matrix

Run the existing three cases `09`, `17`, `42` sequentially, using their public synthetic documents, pinned bookkeeping date and the current scoring. Keep conditions fixed within a comparison. One pass identifies viability; repeat only promising variants three times before a wider pilot. Do not combine every tweak into one run.

| Experiment | What it could directly improve | What it cannot establish | Evidence to retain |
| --- | --- | --- | --- |
| SQL-only short seeded task, `.allowed` versus initial `.required` with documented mode switch | Separate tool initiation failure from SQL-generation failure | Requiring a call does not require a successful SELECT/UPDATE | Tool names, SQL, refusal/validation text, actual changed fields |
| Same shared bookkeeping prompt, `.allowed` versus initial `.required` with documented mode switch, positive imports only | Require initial tool initiation before returning to normal completion | Can force the wrong tool or malformed SQL; does not guarantee persistence | Completed bookings, invented fields, successful/failed calls, tokens/time |
| Direct image versus generic Vision OCR text | Test whether explicit readable text resolves dates/amounts better than native vision | OCR loses layout and can misread digits; text extraction alone is not bookkeeping | Exact provided text/image dimensions, essential fact errors, final scoring |
| Direct labeled image plus native `OCRTool`, explicitly requested | Give model precise text evidence while retaining visual layout | Tool is still model-selected; OCR can consume tokens or distract from SQL | Whether OCR called, returned evidence, subsequent SQL and facts |
| Generic Vision document text plus table/cell evidence, case 17 only | Preserve tax labels with values after flat OCR loses columns | Detected cells still merge columns and omit row descriptions | Generic row/column text, OCR latency, model fact correctness |
| Small nested `@Generable` document facts, no SQL writes | Test factual reading independently of autonomous database work | Valid structure does not imply correct facts or agent-loop parity | Original decimal/date strings, missing/invented values, per-field checks |
| Shared prompt plus locale line, fixed sampling | Reduce locale ambiguity and establish repeatable conditions | Locale hint cannot solve reasoning/SQL failures; greedy is not an accuracy guarantee | Date interpretation, run repeats, categories, tool behavior |
| Actual prompt/tool/schema/transcript counts | Locate current context costs rather than infer from response usage | Token headroom does not prove model competence | Native counts and `contextSize`; final usage separately |
| Cancellation after a known synthetic tool side effect, reopened chat | Test operational stability once a variant actually writes successfully | A cancelled unavailable request or no-write run does not validate rollback ownership | Owned writes, request status, later user change protection, resumed evidence |

Prioritize the seeded SQL task and structured fact comparison. If SQL-only tasks fail even with a small prompt and required calls, changing image adapters will not repair that deficit. If facts become reliable but SQL does not, that supports only a narrow extraction/assistant role until a separately bounded integration experiment proves more.

## Exact compile-validated calls

### Tool initiation

```swift
let options = GenerationOptions(
    samplingMode: .greedy,
    maximumResponseTokens: 600,
    toolCallingMode: .required
)
let response = try await session.respond(to: prompt, options: options)
```

`.allowed` is default and `.disallowed` prohibits tools. **Persistent `.required` loops until a tool throws or the mode changes dynamically. It does not automatically release the requirement after one valid call.** The repeated typed 50% updates observed by the implementer under persistent required mode are consequently a configuration/termination result, not by themselves evidence of model weakness. There is no named-tool requirement in this `GenerationOptions` signature. Register only the SQL tool for a seeded SQL diagnostic; adding OCR/currency tools means any can satisfy `.required`. Keep the existing 60-call safety budget. Do not force calls for ordinary chat/negative controls indiscriminately. A SELECT alone satisfies required mode and still creates no booking. [Apple tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)

The following documented exit pattern **typechecks cleanly** in `/tmp/pfennig-required-exit-profile.swift`:

```swift
extension SessionPropertyValues {
    @SessionPropertyEntry var diagnosticToolCallCount: Int = 0
}
struct FirstCallRequiredProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.diagnosticToolCallCount) var callCount
    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            Instructions("Nutze das Werkzeug einmal und antworte danach kurz.")
            EchoTool()
        }
        .toolCallingMode(callCount < 1 ? .required : .allowed)
        .onToolCall { callCount += 1 }
    }
}
let session = LanguageModelSession(profile: FirstCallRequiredProfile())
```

Here `EchoTool` is the disposable synthetic tool defined in the probe. Do not also pass persistent `toolCallingMode: .required` as a response override. Switching to `.allowed` enables a final answer but still permits more tool calls; preserve the cap. A tool call is not necessarily a successful write. Throwing ends the request as an error, not as a successful final answer. No inference was run for this compile probe. [Required-mode termination](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct/required), [Dynamic profiles](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)

### Direct vision and native OCR

```swift
import FoundationModels
import Vision
let session = LanguageModelSession(
    tools: [OCRTool(name: "ocr", description: "Liest Text aus dem angehängten Bild.")]
)
let prompt = Prompt {
    "Lies Bild beleg09 mit ocr."
    Attachment(image).label("beleg09")
}
```

`Attachment` accepts `CGImage`, `CIImage`, `CVPixelBuffer` or `imageURL: URL`, with optional orientation. OCRTool is supplied by the `_Vision_FoundationModels` cross-import overlay; import both frameworks. Its initializer accepts optional `name` and `description`; default tool name observed is **`getText`**. Labels identify attachments, not accounting fields. Native OCR is generic document preprocessing, not a second bookkeeping parser. Raw PDF support was not established: continue generic ordered page rendering. Larger images consume more tokens/latency; changing render scale is an experimental variable, not automatic quality improvement. [Apple multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)

### Layout-aware generic Vision document recognition

`RecognizeDocumentsRequest` exists since macOS 26 and compiles/runs with the current SDK. It returns document regions with paragraphs, tables, rows and cells, and `DocumentObservation` is Codable:

```swift
var request = RecognizeDocumentsRequest()
request.textRecognitionOptions.recognitionLanguages = [
    Locale.Language(identifier: "de"), Locale.Language(identifier: "en")
]
let observations = try await request.perform(on: image)
let encoded = try JSONEncoder().encode(observations)
for observation in observations {
    let text = observation.document.text.transcript
    let paragraphs = observation.document.paragraphs
    for table in observation.document.tables {
        for row in table.rows {
            let cells = row.map { $0.content.text.transcript }
            // A cell also provides rowRange and columnRange: ClosedRange<Int>.
        }
    }
}
```

The generic case-17 probe uses the same 144 dpi PDF rendering as the prototype: one 1191×1684 page, **25.57 s cold**, one observation, 46 paragraphs and two tables. The tax-summary table pairs net **308,00**, 7% tax **20,86**, 19% tax **1,90** and gross **330,76** correctly. However, the line-item table merges amount and rate (`276,00 € 7 %`) into one cell, leaves the rate cell empty and keeps descriptions outside its rows. This can reduce lost label/value associations, but is not a verified perfect table reconstruction or accounting interpretation.

Artifacts: `/tmp/pfennig-document-layout-probe.swift`, `/tmp/pfennig-document-layout-probe.log`, `/tmp/pfennig-document-layout-case17.txt` (1,677 bytes of full text and generic column-tagged table rows), `/tmp/pfennig-document-layout-case17.json` (53,518 bytes of complete Codable observations). Prefer the small generic text evidence for one bounded extraction comparison; geometry JSON would consume unnecessary model context. Do not add invoice-specific parsing, tax calculations or table-repair heuristics. [Document recognition](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), [Document observations](https://developer.apple.com/documentation/vision/documentobservation)

### Guided factual output

```swift
@Generable struct FactLine {
    var betrag: String?
    var beschreibung: String?
}
@Generable struct DocumentFacts {
    var datum: String?
    var belegnummer: String?
    @Guide(.maximumCount(8)) var zeilen: [FactLine]
}
let response = try await session.respond(
    to: prompt, generating: DocumentFacts.self,
    options: GenerationOptions(samplingMode: .greedy, toolCallingMode: .disallowed),
    contextOptions: ContextOptions(includeSchemaInPrompt: true)
)
```

Nested structs, optional fields and array guides compile; emitted schema has optional date/receipt fields and bounded nested items. Use strings for exact printed decimal facts, with no currency conversion/arithmetic in this diagnostic. The eight-item bound is only a disposable-probe limit, not a production policy to omit longer receipts. `@Generable` constrains shape, not truth. The exact pattern guide signature is `static func pattern<Output>(_ regex: Regex<Output>) -> GenerationGuide<String>`. The implementer observed immediate `UnsupportedGuide` for all four strict date/money configurations despite successful compilation. That establishes unsupported runtime configurations, not their precise cause or universal rejection of every regex. Prefer a small integer year/month/day or original-evidence diagnostic over repeatedly retrying those failed configurations. Existing native SQL argument generation already constrains `{sql: String}` but cannot prevent nonexistent columns inside the SQL string. Do not infer that adding another `@Guide` guarantees SQL correctness. This factual-output comparison authorizes no document-specific Swift parser or unvalidated writes. [Apple guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)

### Locale, sampling and context

```swift
let instructions = "The person's locale is de_DE. Antworte auf Deutsch. " + sharedInstructions
let model = SystemLanguageModel.default
let instructionCount = try await model.tokenCount(for: Instructions(instructions))
let toolCount = try await model.tokenCount(for: tools)
let promptCount = try await model.tokenCount(for: prompt)
let schemaCount = try await model.tokenCount(for: DocumentFacts.generationSchema)
let transcriptCount = try await model.tokenCount(for: session.transcript)
let contextSize = model.contextSize
let randomOptions = GenerationOptions(
    samplingMode: .random(top: 20, seed: 123), temperature: 0.2
)
```

Apple recommends the exact English locale phrase shown, even for otherwise German prompts. Compare it as one small provider hint. Greedy removes random sampling but does not promise identical outputs across OS/model versions or solve hallucinations. Seeded `.random(top:seed:)` and `.random(probabilityThreshold:seed:)` also compile. Avoid changing both prompt and sampling when attributing an improvement. `maximumResponseTokens` can truncate useful output and make structured decoding fail; it is a verbosity guard, not a safe run budget. [Language guidance](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models), [Generation options](https://developer.apple.com/documentation/foundationmodels/generationoptions)

Count components independently for diagnosis, then use transcript count for actual combined session evidence. Do not assume independently counted fragments add exactly to the combined tokenizer result. Capture `response.usage.input.totalTokenCount` and `.output.totalTokenCount`; session `.usage` remains accessible on failure. On-device reasoning is not a verified substitute for OpenAI high effort; `ContextOptions(reasoningLevel:)` is documented for PCC, and setting it does not turn the local model into a reasoning model. [Context management](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), [PCC model options](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)

## Private Cloud Compute boundary

The first local-only probe created `PrivateCloudComputeLanguageModel()` and queried `.availability`, which reports **`.available`**. Within the owner's expanded experiment brief, a tiny fictional cloud-access probe followed. `try await model.contextSize` returns **32,768**; unlike the local synchronous property, PCC contextSize is an asynchronous throwing getter. The first actual response request, German 100,00 EUR plus 19,00 EUR with light reasoning, **fails in 0.051 s**: `FoundationModels.LanguageModelError` -1 wrapping `ModelManagerServices.ModelManagerError` **1046**. The planned guided-fact request was not attempted. No terms, account or entitlement changes followed. This establishes advertised availability/context but failed inference in the disposable CLI, not a successful or eligible signed-app backend. No documented primary-source mapping of 1046 was established; do not name entitlement, quota or server availability as its proven cause. No usage or generated content exists from the failure. Artifacts: `/tmp/pfennig-pcc-synthetic-probe.swift` and `/tmp/pfennig-pcc-synthetic-probe.log`.

Apple's published criteria remain: App Store Small Business Program enrollment, fewer than two million first-time App Store downloads and an assigned PCC entitlement. Production apps use App Store distribution; TestFlight/ad hoc testing is documented. PCC provides a larger 32K context and reasoning, automatically handles user authentication and has daily user quotas, with expanded iCloud+ access. It still uses cloud processing. No user quota figure or EU-only processing guarantee was established. [PCC eligibility](https://developer.apple.com/private-cloud-compute/), [PCC integration](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)

The failed access probe does not justify a cloud benchmark on invoice cases yet. No additional cloud attempts or entitlement/account modifications are needed for this task. Even successful PCC would answer a different capability question from a fully local replacement. Finish diagnosing native on-device facts, tool use and operational behavior before changing Pfennig's product claim or default.
