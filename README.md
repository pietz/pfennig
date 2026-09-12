# Ziffer

Native macOS bookkeeping for German freelancers. Local-first: everything lives
in one archive folder with an SQLite database and the original documents.

The binding specification is [`concept.md`](concept.md). This repository
currently implements milestones M0-M2: repository foundation, local app shell
and the complete database schema.

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
verschieben" feature will build on. Debug builds seed three sample
transactions into a freshly created archive.

## Tests

`scripts/test.sh` covers `Money` parsing and rounding, `LocalDate`, the stable
raw values of every stored enum, database migration and seeding, the derived
`v_transaction_status` view, statement-line deduplication, the archive layout
and the schema documentation in `docs/schema.md`.
