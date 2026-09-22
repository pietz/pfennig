# Pfennig: Working Principles

## Orientation

Pfennig is a native, local macOS bookkeeping app for one German freelancer or sole proprietor using EÜR and Ist-Versteuerung, with regular VAT or Kleinunternehmer status. It prepares UStVA XML and EÜR values; the user checks and submits them outside the app. No multi-user or multi-client mode, no cloud sync.

- Read `.memory/MEMORY.md` at session start for owner decisions, scope boundaries and their reasons.
- `docs/status.md` records completed work; `docs/backlog.md` and GitHub issues hold priorities and open questions. An issue is not an implementation mandate.
- `Sources/Core` owns accounting, persistence and tax calculations. `Sources/Agent` owns the model client, instructions and tool loop. `App` owns native UI and app coordination. Tests live in `Tests`.
- Keep this file about durable principles and conventions. Put changing status in the status file, decisions in memory and unfinished work in the backlog, not here.

## Design principles

- **Agent first.** Document understanding, classification, matching and splitting belong to the agent. Swift owns file handling, the schema, exact money arithmetic, tax rules, SQL authorization, validation and change logging. Do not add document-specific parsers or matching engines alongside the agent.
- **Small by choice.** Build only the agreed scope. Prefer manual correction of rare cases over extra rules, options, fallbacks or abstractions. Do not prepare for hypothetical extensions. State unsupported cases rather than inventing behavior.
- **Keep the prompt short.** Revise or combine existing instructions before adding another rule. Do not turn the system prompt into a catalogue of edge cases.
- **One booking per document.** Positions and payments are JSON lists in the booking, not separate entities. Separately depreciated assets are the exception: each needs its own purchase booking. Category and private share apply to the whole booking; mixed documents use the dominant category. Category keys are permanent.
- **Immediate writes, human review.** Agent changes are saved immediately, logged and marked unreviewed; the user confirms in the inspector, not on a separate review page. No automation levels or protection rules for previously edited bookings.
- **Native and quiet.** Use standard SwiftUI and AppKit behavior, a table with inspector and the standard settings window. Keep inspector sections flat and visible. Do not introduce parallel mock interfaces or custom interaction systems for native controls.
- **Exact accounting.** Totals remain in EUR cents. A paid EUR amount takes precedence over reference conversion. Preserve exact original-currency amounts; no currency-specific precision rules, FX gain/loss accounting or revaluation.
- **Evidence for tax behavior.** Use official primary sources and record what was verified. Distinguish calculation tests from a successful ELSTER import. No direct submission, manufacturer registration or ERiC integration.

## Conventions and workflow

- The owner decides goals and consequential boundaries. Own ordinary implementation choices and keep the work moving, one topic at a time. Before a structural change, explain its true size and agree on a bounded plan. Stop if the work grows beyond that scope.
- Fit changes into the existing design. If a piece needs restructuring to fit cleanly, propose that restructuring separately rather than layering around the mismatch.
- Work directly unless the owner requests delegation. Before committing, take a separate review pass for correctness, overbuilding and unnecessary complexity.
- Use English for infrastructure, UI plumbing, agent mechanics and generic helpers. Keep German accounting/persisted models, their stored properties and raw values, SQL names, and storage/tool JSON keys. Naming-only refactors must preserve rendered UI and agent-facing wording. `LocalDate` stores JJJJ-MM-TT.
- Before committing, run `swiftformat App Sources Tests`. For code changes, run `scripts/test.sh` and build with `scripts/build.sh`; add targeted verification in proportion to risk. Do not commit generated `Package.resolved` origin-hash churn when dependency pins are unchanged.
- Commit completed, tested and reviewed steps. Push only on the owner's command. Preserve unrelated worktree changes.
- Keep messages short. Never use em dashes in text you write.

## Data and operational boundaries

- **One schema before 1.0:** edit the single schema definition, with no migrations or backward-compatibility layer. An approved schema change requires a coordinated development-archive rebuild, after quitting the development app and making a timestamped backup under `~/Library/Application Support/Pfennig-Dev/Backups/`.
- **Development stays separate:** Debug builds run as `Pfennig Dev.app` from the project and use `~/Library/Application Support/Pfennig-Dev/`. `/Applications/Pfennig.app` is the official release and uses `~/Library/Application Support/Pfennig/`. Never reset or copy the release archive for development. A schema change affecting release data needs a separately approved preservation plan.
- **Protect secrets and private records:** never access `.env` files or read, extract, display or export API keys, signing private keys or notarization passwords. Never turn the owner's private bank exports or receipts into fixtures or commit them.
- **Release only with authorization:** read `docs/releasing.md` and use `scripts/release.sh --notarize`. Explicit release authorization permits that script to use existing Keychain credentials without exposing them. Credential setup and access-control changes remain owner-only; the owner handles macOS confirmation dialogs. Publication, push and replacement of the installed app require explicit owner commands. Updates must preserve app data.
- **Legacy is not a foundation:** the `legacy-2026-09-14` tag may be consulted only for the originally approved reusable pieces: Money, LocalDate, UStVA calculation and 2026 Kennzahlen, EÜR lines, XML exporter, category list, Responses client, Keychain access and PDF preview. Do not inspect the rest or reintroduce its structure.
