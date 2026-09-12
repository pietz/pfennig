# Ziffer

Native macOS bookkeeping for German freelancers. Local-first: everything lives
in one archive folder with an SQLite database and the original documents.

The binding specification is [`concept.md`](concept.md). This repository
currently implements milestones M0-M3: repository foundation, local app shell,
the complete database schema and manual bookkeeping (create and edit
transactions with allocations, tax components, tax assessment, documents and
payments).

## Requirements

- macOS 15 or newer, Xcode 26 (Swift 6.2)
- Homebrew, for [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting started

```sh
scripts/bootstrap.sh   # installs xcodegen (and swiftformat), resolves packages, generates Ziffer.xcodeproj
scripts/build.sh       # builds Ziffer.app into build/Build/Products/Debug
scripts/run.sh         # builds and launches the app
scripts/test.sh        # runs the Swift Testing suites of all packages
scripts/lint.sh        # formats sources with swiftformat, if installed
```

Everything works from the terminal; Xcode is only needed for signing or
notarisation edge cases. `Ziffer.xcodeproj` is generated from `project.yml` and
is not checked in - re-run `scripts/bootstrap.sh` (or `xcodegen generate`)
after changing the project definition.

## Layout

```text
App/         SwiftUI app target (onboarding, sidebar, transaction table, inspector)
Sources/     SwiftPM modules: Domain, Database, DocumentStore, StatementImport,
             ImportPipeline, AI, Validation, Tax, Analysis, Export
Tests/       Swift Testing suites
docs/        schema.md and further documentation
scripts/     bootstrap, build, run, test, lint
project.yml  XcodeGen definition of the app target
```

Dependencies flow downward only: the app depends on the packages, the packages
on `Domain`; `Tax` and `Validation` have neither network nor database access
(spec section 22).

## The archive folder

On first launch the app creates the archive folder at
`~/Library/Application Support/Ziffer`:

```text
Ziffer/
├── bookkeeping.sqlite
├── Documents/
├── Exports/
├── Backups/
├── archive.json
└── README.txt
```

There is no folder picker; the location is fixed. `ArchiveLocator` can still
open an arbitrary path, which the test suite uses and a later "Archiv
verschieben" feature will build on. Debug builds seed four sample
transactions into a freshly created archive.

## Tests

`scripts/test.sh` covers `Money` parsing and rounding, `LocalDate`, the stable
raw values of every stored enum, database migration and seeding, the derived
`v_transaction_status` view, statement-line deduplication, the archive layout,
the schema documentation in `docs/schema.md`, and the manual bookkeeping write
path: save/reload round trip, provenance and audit on manual edits, the
manual-override protection of spec 17.15, partial payments, document
deduplication, derived tax points and blocked hard validations.
