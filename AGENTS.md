# Pfennig: Principles for Agents

## Where we are

Pfennig is being rebuilt. The specification for the rebuild is `docs/specs/pfennig-neu.md`; it was decided topic by topic with the owner on 2026-09-14 and is binding. Read it first, completely. It is short on purpose.

The previous codebase is archived as the git tag `legacy-2026-09-14`. It is a quarry, not a foundation: copy and adapt the pieces the spec names (Money, LocalDate, UStVA calculation and 2026 Kennzahlen, EÜR lines, XML exporter, category list, Responses client, Keychain access, PDF preview) and do not look at the rest. Do not reintroduce its structure, its tables, or its abstractions. `docs/status.md` records what exists in the new codebase and what is next; keep it current.

## Product in one paragraph

A local macOS app for German freelancers with EÜR and Ist-Versteuerung, regular VAT or Kleinunternehmer. The user drops documents on the window. An AI agent reads each file and writes bookings into a SQLite database through a single `sql` tool, inside guardrails written in Swift. The user sees one table with an inspector, confirms new bookings, and exports UStVA XML and EÜR values. The app does not look like an AI product; it is a quiet table with an agent behind it.

## Rules that hold

- **The agent is the first solution.** When a document must be understood, classified, matched or split, the agent does it. Swift does what the agent cannot or must not: hashing and moving files, the schema, money arithmetic, tax rules, authorizing SQL, validating written rows, diffing for the activity log, export.
- **Simple and solid.** Build only what the spec says. No checks, abstractions, options or fallbacks for cases the spec does not name. No preparation for later extensions. If a case is not covered, leave it uncovered and say so; do not invent a rule for it.
- **One document, one row.** Positions and payments are JSON lists inside the booking. Five tables: `buchungen`, `dateien`, `aktivitaeten`, `anfragen`, `einstellungen`. Schema, columns and values are German; the schema text is what the agent reads.
- **No automation level, no protection rules.** Every agent booking is written immediately and marked unreviewed; the user confirms it in the inspector. The activity log shows every change.
- **Native macOS.** Standard SwiftUI and AppKit behavior. One window: table, inspector with flat always-visible sections, toolbar. Settings in the standard settings window. No sidebar, no start page, no review page.
- **Pre-release schema rule.** Exactly one schema definition and no migrations until the first public release. When a decision changes the schema, edit the definition and recreate the development archive once, with a backup in `~/Library/Application Support/Pfennig/Backups/`.
- **Tax scope.** Ist-Versteuerung only. UStVA prepared as XML for the Mein ELSTER upload, EÜR values as CSV. No submission, no ELSTER manufacturer registration, no ERiC. Use official primary sources for tax rules and say when something is unverified.

## Working with the owner

- Discuss one topic at a time and keep messages short. Decisions on goals belong to the owner; ordinary implementation choices belong to the agent and are not reopened.
- Do not start implementation work without an approved plan. If a step grows beyond what was agreed, stop and report before continuing.
- After every implementation step, an independent review checks for overbuilding and unnecessary complexity before the step counts as done.
- Commit when a step is built, tested and reviewed. Push only on the owner's command.
- Run `swiftformat App Sources Tests` before committing. Build with `scripts/build.sh`. Agents do not launch the app; the owner tests it.
- Never access or act on `.env` files, API keys, signing private keys or notarization passwords. Never turn the owner's private bank exports or receipts into fixtures or commit them.
- Never use em dashes in anything written.
