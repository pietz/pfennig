# Siri AI in macOS 27.3: renewed investigation

Research date: 2026-11-08. Documentation review and existing experiment review, with no new model inference. Production remains OpenAI-only.

## Assessment

Apple's new Siri integration is a credible new experiment for bookkeeping performed through Siri. It does not establish an interchangeable model backend for Pfennig's existing import and chat. For keeping that experience without a user API key, Private Cloud Compute (PCC) is the more direct Apple candidate, conditional on access, distribution and measured quality. The on-device model remains unproven for general bookkeeping.

Do not repeat the October tuning campaign simply because Siri has new APIs. First establish what changed in the actual model or execution route, then measure the relevant route separately.

## What the announcement changes

The November 3 announcement opens custom actions and content to Siri through App Intents, adds app skills for complex tasks and expands entity discovery. This is a developer preview, with customer availability and App Store submissions planned later; usage terms are still developing. Its published language list does not include German. The stated EU restriction covers iOS, iPadOS and watchOS, not macOS. These are Siri constraints, not evidence that Foundation Models cannot process German. [Apple announcement](https://developer.apple.com/news/?id=gdk2umrf)

Apps expose operations as `ToolIntent`s. `GenerableEntity` lets Siri fill structured arguments directly. An app could therefore expose booking lookup and validated mutation operations and let Siri orchestrate them. Pfennig currently has no App Intents or Spotlight integration. This would introduce an additional system entry point rather than just replace a request URL. [Custom actions and content](https://developer.apple.com/documentation/appintents/bringing-custom-actions-and-content-to-siri)

An app skill is a bundled Markdown instruction file describing how tools fit together and explaining domain rules. This could guide receipt lookup, reading and creation of an unreviewed booking, while reusing Core validation and exact money arithmetic. Skills cannot enforce an action sequence, so accounting invariants still belong in code. [App skills](https://developer.apple.com/documentation/appintents/orchestrating-complex-actions-with-app-skills)

The documented Siri entry point is a person's request to Siri, including foreground context or naming a background app. The documentation does not establish a general inference API that Pfennig can call from its existing inbox or chat. Automated scripted conversations exist in Siri Evaluations for testing; that is not evidence of a production inference service. Preview testing requires a development-signed build or internal TestFlight distribution; external TestFlight and App Store builds do not receive the preview functionality. [Preview availability](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview), [Siri Evaluations](https://developer.apple.com/documentation/sirievaluations)

One immediate Mac caveat: the 27.3 beta release notes say Spotlight cannot find third-party app entities unless they conform to a schema. Do not assume arbitrary bookkeeping entities are discoverable despite the broader announcement. Verify lookup on the exact beta build. [macOS 27.3 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27_3-release-notes)

## Earlier results already tested macOS 27

The October 12 experiments ran on macOS 27.0.1 with Xcode/SDK 27. They were not merely tests of the older macOS 26 text model. They included native image attachments and rendered PDF pages, OCR variants, guided output and tool-calling controls. See the [capability record](apple-intelligence-capabilities-20261012.md).

- The whole-agent pilot passed only its negative control, 1 of 8 cases, against 7 of 8 in the matched historical Luna repetition. Missing tool calls, nonexistent SQL columns and incorrect document facts were distinct failures.
- A later staged extraction configuration passed all 9 repeated development runs, but only 3 of 12 reserved expense runs. The unchanged baseline had passed 6 of those 12. Repeated runs are correlated; this was four reserved transactions, not twelve independent documents.
- Concrete errors included reading 29.96 as 29.06 and 49.98 as 49.08, and inventing totals. Successful structured output did not establish accounting accuracy.
- Typed private-share and receipt-link tools worked in narrow controls with candidate rows supplied. That supports a typed-tool experiment, not autonomous matching or complete import parity.
- PCC advertised availability and a 32K context, but its first tiny inference failed with error 1046. Its cause was not established. No successful PCC bookkeeping benchmark exists.

Sources: [whole-agent pilot](apple-intelligence-evaluation-20261012.md), [paired extraction experiment](apple-five-experiments-20261012.md), [controlled components and PCC attempt](apple-intelligence-feasibility-20261012.md). Saved evidence directories are ignored and may not exist on this machine; these numbers are historical report findings, not freshly reproduced inference.

Apple's Foundation Models updates page dates the newer local model, image support, dynamic profiles and PCC access to June 2026. Neither that page nor the reviewed 27.3 release notes establishes another local-model quality upgrade in 27.3. This is an evidence gap, not proof that model assets are unchanged. Query actual capabilities and rerun fixed controls on a future test device. [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)

## Which route could remove the API-key requirement?

**On-device Foundation Models:** Fits the offline aim, but the earlier reliability failures remain relevant. A new OS version alone is insufficient evidence to adopt it. Measure actual context capacity rather than assuming a documentation default: October's runtime reported 8,192 tokens, while the current PCC comparison page still lists 4K for local models.

**PCC through Foundation Models:** Fits direct in-app inference and handles authentication without user API keys. Apple documents stronger reasoning, 32K context and daily quotas, with higher access through iCloud+. A multi-call bookkeeping run needs quota and interruption testing. It requires networking. [PCC API](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)

PCC eligibility requires App Store Small Business Program membership, fewer than two million first-time App Store downloads and an assigned entitlement. Production distribution is through the App Store; TestFlight and ad hoc testing are supported. Pfennig currently uses Developer ID, notarized downloads and Sparkle, so PCC is not established for its existing distribution channel. App Store distribution is a consequential product decision, not part of this investigation. [PCC eligibility](https://developer.apple.com/private-cloud-compute/)

**Siri tool intents and skills:** Could let users perform supported bookkeeping tasks without entering a third-party API key. This is a different interaction model whose document handling, lookup, German requests, reliability and shipping conditions need evidence. Do not assume it runs locally, has unlimited usage or exposes the same model as PCC.

**Third-party models through Foundation Models:** A shared Swift interface does not itself remove provider credentials, billing or backend responsibility. This is API integration convenience, not evidence of an Apple-funded replacement. [Framework overview](https://developer.apple.com/foundation-models-framework/)

## Recommended bounded follow-up

Keep the current application unchanged. When a suitable test machine is available:

1. Record macOS/Xcode build, hardware, locale, Apple Intelligence readiness, model availability and measured context. Reuse public fictional fixtures and disposable archives only. Establish successful trivial inference before attempting any PCC benchmark; account or entitlement setup remains an owner decision.
2. For the local model, rerun the frozen baseline and staged extraction configurations on exactly the previous development and reserved cases, with failures retained. Compare saved OCR separately from fresh document preprocessing to identify whether any improvement comes from the model or Vision. No further tuning on those cases before comparison.
3. For Siri, first propose a separate disposable test app with only booking lookup and one typed mutation, reusing Core validation. Supply fictional records and a short app skill. Test paraphrases, ambiguous matches and actual saved effects, not just Siri's reply. Check German interaction and Mac entity lookup explicitly. Only after this works, test whether Siri can deliver the necessary PDF/image evidence and create a correct unreviewed booking without Pfennig calling OpenAI. Successful invocation of the existing OpenAI importer would prove only integration, not replacement.
4. For PCC, after authorized access is working, measure document facts and multi-step bookkeeping through the same validation boundary, including cancellation, quota exhaustion, retry and duplicate prevention. Successful local or Siri tests do not substitute for these results.
5. A promising component must pass broader unfamiliar documents and complete import/chat scenarios before a production integration proposal. Check tax treatment, payments, exact amounts, credits, foreign currency, duplicates, history and write ownership. Compare against a clearly identified Luna baseline and preserve model/build provenance.

Siri integration needs a separately agreed implementation scope because it adds an execution path. PCC needs an explicit distribution decision if quality proves adequate. Neither is authorized for production by this research request.

## Verification in this session

This host reports macOS 15.8.1 and macOS SDK 26.2. It cannot execute the macOS 27.3 experiments. All eight existing offline Apple fact-scoring tests pass. No model calls, credentials, private archives, OS installation, app integration or release were needed. Apple documentation Markdown was fetched directly when the public documentation pages returned JavaScript shells. Documentation and bookkeeping-use terms should be rechecked before shipping.
