# Pfennig: Principles for Agents

## Where we are

Pfennig is a working app. The initial rebuild specification has been retired; its history remains in Git. The current code and tests describe implemented behavior, and the owner's current decisions guide changes. Do not restore older behavior merely because a historical document described it.

The previous codebase is archived as the git tag `legacy-2026-09-14`. Do not reintroduce its structure, tables, or abstractions. `docs/status.md` records development history; keep it current, but verify historical statements against the code. `docs/backlog.md` contains ideas, not implementation authorization.

## Product in one paragraph

A local macOS app for German freelancers with EÜR and Ist-Versteuerung, regular VAT or Kleinunternehmer. The user drops documents on the window. An AI agent reads each file and writes bookings into a SQLite database through a single `sql` tool, inside guardrails written in Swift. The user sees one table with an inspector, confirms new bookings, and exports UStVA XML and EÜR values. The app does not look like an AI product; it is a quiet table with an agent behind it.

## Rules that hold

- **The agent is the first solution.** When a document must be understood, classified, matched or split, the agent does it. Swift does what the agent cannot or must not: hashing and moving files, the schema, money arithmetic, tax rules, authorizing SQL, validating written rows, diffing for the activity log, export.
- **Simple and solid.** Build only the agreed scope. Add checks, abstractions, options or fallbacks only for concrete current needs. No preparation for later extensions. If a case is outside the agreed scope, leave it uncovered and say so; do not invent a rule for it.
- **Say the true size first.** When a request sounds small but changes many places or the structure, say so before planning, with the reason, and let the owner decide.
- **Fit before place.** A new piece goes where it belongs in the whole, not at the first spot that works. If it does not fit cleanly, propose the small restructuring that makes it fit, as its own step.
- **Bookings are the center.** Positions, payments and file references are JSON lists inside the booking, not separate entities. Files may support multiple bookings, including separate assets bought on one invoice. Schema, columns and values are German; the actual schema text is what the agent reads.
- **Keep the product focused.** No bank connections, invoice creation, balance-sheet accounting, payroll, chat, multiple clients or cloud sync unless the owner explicitly changes the scope. Documents are interpreted by the agent, without bank-specific parsers or rule-based matching.
- **No automation level, no protection rules.** Every agent booking is written immediately and marked unreviewed; the user confirms it in the inspector. The activity log shows every change.
- **Native macOS.** Standard SwiftUI and AppKit behavior. One window with the sidebar items „Start“ and „Buchungen“, the live ledger table, inspector with flat always-visible sections, and toolbar. The ledger uses the approved refined native treatment: compact 40-point rows, small neutral category symbols, quiet derived review statuses, and green income amounts with primary-color expenses. Settings stay in the standard settings window. No review page.
- **Pre-1.0 schema rule.** Exactly one schema definition and no migrations or backward-compatibility code before 1.0, by owner decision while they are the only user. When an approved decision changes the schema, edit the definition and recreate the development archive once, with a timestamped backup in `~/Library/Application Support/Pfennig/Backups/`. `/Applications/Pfennig.app` stays at the latest official release; development builds run from the project directory. Both currently use the same data folder, so coordinate schema resets with quitting the app and testing the matching development build.
- **Tax scope.** Ist-Versteuerung only. UStVA prepared as XML for the Mein ELSTER upload, EÜR values as CSV. No submission, no ELSTER manufacturer registration, no ERiC. Use official primary sources for tax rules and say when something is unverified.

## Working with the owner

- Discuss one topic at a time and keep messages short. Decisions on goals belong to the owner; ordinary implementation choices belong to the agent and are not reopened.
- Do not start implementation work without an approved plan. Agreement in the conversation is sufficient; no separate specification or amendment is required. If a step grows beyond what was agreed, stop and report before continuing.
- After every implementation step, an independent review checks for overbuilding and unnecessary complexity before the step counts as done.
- Commit when a step is built, tested and reviewed. Push only on the owner's command.
- Run `swiftformat App Sources Tests` before committing. Build with `scripts/build.sh`.
- Never access `.env` files or read, extract, display, or export API keys, signing private keys, or notarization passwords. The sole release-credential exception is running the standard release script under the explicit authorization described below; its tools use existing Keychain credentials without exposing them. Never turn the owner's private bank exports or receipts into fixtures or commit them.
- **Release:** Use `scripts/release.sh --notarize` for the standard release path. It performs the Developer ID export, nested Sparkle-helper preflight, notarization, app-only update ZIP, signed appcast, and checksums. Bump both the marketing version and monotonic build number. Publish the distribution ZIP, app-only update ZIP, `appcast.xml`, and every matching checksum as one GitHub Release. Sparkle updates must never reset existing app data. Key generation and credential setup remain owner-only. After the owner explicitly authorizes a release, agents may run `scripts/release.sh --notarize` using the existing Keychain identities and profiles; they must not read, extract, display, or export credential material or change Keychain access controls. If macOS requests confirmation, the owner handles it. Agents may publish or replace `/Applications/Pfennig.app` only on an explicit owner command; push remains owner-command-only. Agents may verify public signatures, checksums, and publication as part of the authorized release task.
- Never use em dashes in anything written.
- Naming convention: use English for infrastructure, UI plumbing, agent mechanics and generic helpers. Keep German persisted and accounting models, their stored properties and raw values, SQL schema names, and storage and tool JSON keys. Naming-only refactors must preserve rendered user and agent facing text, including prompts, errors and UI strings. Future wording changes remain allowed. `Core` and `LocalDate` are the English module and date type; LocalDate keeps its JJJJ-MM-TT storage encoding.
