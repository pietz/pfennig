# Pfennig

Previously **Ziffer**. The application, build targets, bundle identifier and local archive now use the new name; an existing `Ziffer` archive folder is moved automatically on first launch.

Pfennig is a native, local-first macOS bookkeeping app for German freelancers and sole proprietors using EÜR.

> Belege ablegen. Ausnahmen prüfen. Fertig.

Pfennig keeps the bookkeeping database and original documents in an archive on your Mac. There is no Pfennig account, hosted backend, telemetry, or bank connection. Optional document extraction uses your own OpenAI API key and always creates a proposal for review.

> [!WARNING]
> Pfennig is pre-1.0 software. It supports bookkeeping workflows, not tax advice, certified tax filing, or a replacement for a Steuerberater.

## Current capabilities

- Native SwiftUI interface for macOS 15 and newer
- Manual income and expense bookkeeping
- Local SQLite archive with original documents
- PDF and image import with structured AI extraction
- Review, edit, confirm, reject, and retry workflow
- Payments, including partial payments
- German 7% and 19% VAT and mixed-rate documents
- Ist-Versteuerung tax points
- Kleinunternehmer bookkeeping under §19 UStG
- Typical foreign-service reverse charge
- Internal provenance, audit history, and manual-override protection

The intentionally narrow initial audience and product principles are documented in [`AGENTS.md`](AGENTS.md). The detailed specification is [`concept.md`](concept.md).

## Privacy

Existing bookkeeping remains fully usable offline. Pfennig sends data to OpenAI only when you explicitly import a document for AI extraction. See [`docs/privacy.md`](docs/privacy.md) for the exact data flow.

## Install

Signed and notarized builds will be published through [GitHub Releases](https://github.com/pietz/pfennig/releases). The first public binary has not been released yet.

Until then, build Pfennig from source.

## Build from source

Requirements:

- macOS 15 or newer
- Xcode 26 with the macOS SDK
- [Homebrew](https://brew.sh)

```sh
git clone https://github.com/pietz/pfennig.git
cd pfennig
scripts/bootstrap.sh
scripts/run.sh
```

Useful commands:

```sh
scripts/build.sh   # Build the macOS app
scripts/test.sh    # Run the Swift package test suites
scripts/lint.sh    # Format Swift sources, if SwiftFormat is installed
```

`Pfennig.xcodeproj` is generated from [`project.yml`](project.yml) and is intentionally not committed.

## Archive layout

On first launch, Pfennig creates its archive at `~/Library/Application Support/Pfennig`. An archive left behind by the earlier Ziffer version is moved to that location once, without copying or deleting anything:

```text
Pfennig/
├── bookkeeping.sqlite
├── Documents/
├── Exports/
├── Backups/
├── archive.json
└── README.txt
```

The OpenAI API key is stored separately in the macOS Keychain and never in this folder.

## Development

The app target lives in `App/`. Reusable modules live in `Sources/`, with Swift Testing suites in `Tests/`. `Tax` and `Validation` are deterministic and have no network or database access. The current implementation boundary and maintainer handoff are recorded in [`docs/status.md`](docs/status.md).

Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request. Current planning is in the [project handoff](docs/status.md) and [workflow specification](docs/specs/document-to-tax-workflow.md). Historical GitHub issues are preserved in a [local archive](docs/legacy-github-issues.md); new issues belong in [pietz/pfennig](https://github.com/pietz/pfennig/issues). Maintainer release steps are documented in [`docs/releasing.md`](docs/releasing.md).

Security vulnerabilities should be reported privately as described in [`SECURITY.md`](SECURITY.md).

## License

Copyright © 2026 Paul-Louis Pröve.

Pfennig is free software licensed under the [GNU General Public License, version 3](LICENSE).
