# AI providers: bounded architecture proposal

Update 2026-11-09: The owner approved the smaller Responses-based implementation. OpenAI and OpenRouter now share the existing client, with separate credentials/settings and editable model identifiers. Chat configuration is stored inside the existing JSON transcript, without a neutral transcript redesign or schema change. The broader proposal below remains advisory; direct Anthropic and Apple integration are future work.

2026-11-08. Owner direction: support Apple's official AI APIs early, alongside OpenAI, and investigate Anthropic and OpenRouter. This document proposes the implementation boundary; it does not authorize a structural refactor, archive conversion or provider rollout.

## Recommendation

Keep one bookkeeping workflow with a small provider-session boundary. Support explicit Apple, OpenAI, Anthropic and OpenRouter choices. Apple local and PCC are model/execution choices within the Apple integration. Keep operating-system integration behind that boundary so a later public system provider API can fit without changing accounting code.

Use Apple's Foundation Models framework for the Apple adapter. Do not yet make it mandatory for all providers: Pfennig supports macOS 15, whereas its third-party model interface requires macOS 27. First validate it against the actual file, transcript and tool lifecycle before choosing it as a universal runtime. Supporting the Apple adapter early is compatible with requiring evidence before offering its models for general bookkeeping.

## What already exists

Apple's framework supports a `LanguageModel` protocol, local and PCC models, tools, images and dynamic profiles. Providers can supply Swift adapters. This is a public integration surface today; it is not evidence of a system-wide registry that automatically discovers and pays for all of a user's AI providers. [Apple framework](https://developer.apple.com/foundation-models-framework/)

Anthropic publishes `ClaudeForFoundationModels`, including tool calling and persisted provider metadata. It requires macOS/Xcode 27. Its authentication options include API keys and app-attested developer billing; these are different product models. Investigating this package could save adapter work on newer Macs, but it does not demonstrate that our PDF workflow and user-owned-key setup work unchanged. [Anthropic adapter](https://github.com/anthropics/ClaudeForFoundationModels)

OpenRouter offers a stateless Responses endpoint, full-history replay and tool calling. It is worth testing reuse of the existing Responses transport and codec, with separate provider configuration. Compatibility must be verified for attachments, reasoning continuation and errors rather than inferred from the endpoint name. [Responses](https://openrouter.ai/docs/api_reference/responses/overview), [tools](https://openrouter.ai/docs/api_reference/responses/tool-calling), [reasoning](https://openrouter.ai/docs/api_reference/responses/reasoning)

Direct Anthropic uses Messages content blocks and supports PDFs. Thinking blocks accompanying tool calls must be replayed intact. Direct OpenAI similarly retains provider-specific reasoning state for stateless continuation. A common interface must preserve these differences. [Anthropic PDFs](https://platform.claude.com/docs/en/build-with-claude/pdf-support), [thinking](https://platform.claude.com/docs/en/build-with-claude/thinking), [OpenAI reasoning](https://developers.openai.com/api/docs/guides/reasoning)

## The actual refactor boundary

Current coupling is concentrated in `Sources/Agent/AgentRun.swift`, `Conversation.swift`, `Responses.swift`, key acquisition in `FileIntake.swift`/`Chat.swift`, and `AISettings` plus its settings UI. Conversation storage currently contains OpenAI wire items, not a neutral chat transcript. This makes the change medium-sized, despite having only four provider choices.

The proposed separation is:

- **AgentRun:** shared instructions, request lifecycle, import success criteria, cancellation and ownership of writes. One tool executor owns SQL validation, conversion, the call budget, changed-row tracking and rollback information.
- **Provider session:** takes instructions, file references and conversation state; obtains model responses and returns text, usage, tool requests and continuation state. HTTP adapters perform their wire-level exchange. Apple's session may invoke the shared tool executor through its native tool callbacks. Do not force Apple into a one-HTTP-response abstraction or duplicate accounting behavior inside adapters.
- **Stored conversation:** a small display/file representation plus opaque continuation data tagged with its provider and model. Keep attachment bytes out of stored transcripts. Preserve provider state exactly; do not translate encrypted reasoning or signatures between services. Provider/model choice stays fixed for an existing conversation initially. New selections apply to new conversations and future imports.
- **Provider configuration:** provider identity, model identifier and only that model's relevant options. Separate Keychain credentials per service. Existing `einstellungen` entries can hold provider preferences; no dedicated provider-account tables are needed. Do not make all providers inherit OpenAI's effort values or priority flag.

This is a proposed replacement for the present coupling, not another conversation system layered alongside it. Storage implementation and treatment of existing chats need a bounded preservation plan before code changes. No schema or archive changes are made by this proposal.

## Keep the user experience small

One provider picker in KI-Zugang, then model and supported options. Apple shows availability and the selected local/cloud model rather than a key field. Other providers use their own key. Connection checking should test the selected provider/model's basic access; it does not certify bookkeeping quality.

Start with a short tested model list, not OpenRouter's entire catalogue or dynamic capability discovery. Verify tools, image/PDF handling, reasoning continuation and context behavior for each supported configuration. Generic PDF rendering or OCR can be provider preprocessing; document-specific accounting parsers remain outside scope.

For OpenRouter, explicitly configure document handling and upstream routing. It can send PDFs natively or introduce a separate parser, with a default OCR fallback when native input is unavailable. Proposed initial support uses native-capable models and explicit native PDF processing. Require requested parameters, identify the upstream route and retain provenance in diagnostics. These are implementation requirements to verify, not promises that every model behaves identically. [PDF handling](https://openrouter.ai/docs/guides/overview/multimodal/pdfs), [routing](https://openrouter.ai/docs/guides/routing/provider-selection)

Keep each run on its chosen service. Automatic switching from local to cloud, cross-provider retries, task-based routing and cross-provider conversation conversion are unnecessary for this first version. Provider-specific retries must still preserve the existing write lifecycle.

## Suggested sequence and acceptance

1. Extract the provider-session boundary using OpenAI alone. Preserve existing behavior and verify stateless reasoning replay, attachments, successful imports, cancelled/failed runs and reopened chats. Resolve existing-chat preservation before altering persisted content.
2. Add OpenRouter through a tested Responses configuration, and direct Anthropic through Messages. Exercise at least one complete model-tool-model exchange, file input and persisted chat continuation for each. Use synthetic transport tests first; paid inference is a separate explicit experiment.
3. In parallel with that product sequence, investigate Apple's framework in the existing isolated eval area on an SDK/OS 27 machine. Test a native session calling the shared executor, reopening its transcript and reading the same fictional documents. A provider boundary is ready for Apple only if these checks work, not merely because an empty adapter compiles. Compare Anthropic's Apple adapter against the direct Messages route before adding a second implementation for the same service.
4. Offer Apple local/PCC only for capabilities established by the benchmark, with clear availability. PCC access and App Store distribution remain owner decisions. Siri App Intents are a separate optional entry point and are not required for official in-app model access.

The first bounded implementation should be step 1 only, with OpenAI remaining the sole enabled provider. It touches Agent, settings and conversation handling, not the accounting engine. Agree on that scope and the chat preservation approach before starting. The later provider adapters should exercise the same contracts and evaluation corpus, without a routing engine, plugin framework, server or new accounting abstractions.

## Verification

Reviewed the current provider settings, transport, file intake, chat storage and tool loop, plus current primary documentation. This is an architecture proposal, not a compiled prototype or a quality benchmark. The research host cannot execute macOS 27 APIs. No credentials, model calls, private archives or production source changes were used.
