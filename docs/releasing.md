# Releasing Pfennig for macOS

Pfennig will initially be distributed outside the Mac App Store as a Developer ID signed and Apple-notarized ZIP. Release credentials remain in the local macOS Keychain and are never passed through environment files or committed to the repository.

After explicit owner authorization for a release, an agent may run `scripts/release.sh --notarize` using the existing Keychain setup. Key generation and credential setup remain owner-only; agents must not extract or display secrets or change Keychain access controls. The owner handles any macOS confirmation dialog. Publishing, pushing, and replacing the installed app still require explicit owner authorization.

## One-time setup

Install a valid `Developer ID Application` certificate and store notarization credentials:

```sh
xcrun notarytool store-credentials "ziffer-notary" \
  --apple-id "YOUR_APPLE_ACCOUNT_EMAIL" \
  --team-id "34MWWCL4H2"
```

Use an app-specific Apple Account password when prompted. The resulting Keychain item is referenced only by the local profile name `ziffer-notary`. That name predates the rename and is kept so the existing local credentials keep working; set `NOTARY_PROFILE` to use a differently named profile.

### Sparkle signing key

Pfennig uses Sparkle 2 with Ed25519 archive and appcast signatures. Generate the key once on the owner’s Mac with the official tool from the Sparkle package artifact:

```sh
/path/to/Sparkle/bin/generate_keys
```

The tool stores the private key in the macOS Keychain and prints the public key. Only that printed public key belongs in `App/Info.plist` as `SUPublicEDKey`; never commit or pass the private key through a file or environment variable. The current checkout has the owner-provided public key embedded.

The Sparkle tools are in Xcode’s package artifact directory, next to the framework. Set `SPARKLE_BIN` to that directory when creating a release, for example:

```sh
export SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/<project>/SourcePackages/artifacts/sparkle/Sparkle/bin"
```

## Build and notarize

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; the marketing version identifies the release and the build number must increase monotonically.
2. Start from the exact clean commit that will be tagged.
3. Run the tests and release pipeline:

```sh
scripts/test.sh
scripts/release.sh --notarize
```

The script:

- creates a Release archive with Hardened Runtime and the Developer ID Application identity
- exports that archive with `xcodebuild -exportArchive` using `method = developer-id`; this is the supported Sparkle workflow that signs its helper code for distribution
- verifies the exported app and the four Sparkle helper executables for the expected Developer ID team and secure timestamps before creating the upload ZIP
- submits a temporary ZIP to Apple and waits for `Accepted`; on an invalid result, it downloads Apple’s JSON diagnostic to `dist/notary-log.json` using the returned submission ID
- staples and validates the notarization ticket
- runs a Gatekeeper assessment
- creates `dist/Pfennig-<version>-macOS.zip` with the app, GPLv3 license, privacy notice, and its SHA-256 file
- creates the app-only `dist/Pfennig-<version>-macOS-update.zip` from that same exported app, which is the Sparkle update archive
- runs Sparkle’s official `generate_appcast` using the owner’s Keychain key and writes the signed `dist/appcast.xml` plus checksums; delta updates are disabled

Use `scripts/release.sh --build-only` to test release signing without contacting Apple’s notarization service. This mode does not create a publishable Sparkle feed. `--notarize` requires `SPARKLE_BIN`, the embedded public key, the Developer ID identity, and the existing notarization profile. Override `TEAM_ID`, `SIGNING_IDENTITY`, or `NOTARY_PROFILE` in the environment when another authorized maintainer performs a release.

## First Sparkle-enabled release

The already installed `v0.1.0` predates Sparkle and cannot update itself. For the first update-capable installation, the owner runs the notarized release once, publishes its assets, and replaces the app in `/Applications` manually:

```sh
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' -print -quit)"
test -x "$SPARKLE_BIN/generate_appcast"
export SPARKLE_BIN
scripts/release.sh --notarize
```

For this first handoff, the expected outputs are `dist/Pfennig-0.2.0-macOS.zip`, `dist/Pfennig-0.2.0-macOS-update.zip`, and `dist/appcast.xml`, each with its matching checksum. Then publish the `v0.2.0` GitHub Release as described below and replace `/Applications/Pfennig.app` with the notarized distribution ZIP. Do not install the Debug build or the signed-unnotarized archive. From the next version onward, Sparkle handles the standard check, download and consented installation.

## Publish

Publishing is a separate, deliberate step. After verifying the final ZIP on a clean macOS user account:

1. Tag the exact release commit as `v<version>`.
2. Create a GitHub Release from that tag.
3. Attach the notarized distribution ZIP, the app-only `-update.zip`, `appcast.xml`, and all corresponding `.sha256` files from `dist/`.
4. Include concise release notes and known limitations.

The app’s feed is `https://github.com/pietz/pfennig/releases/latest/download/appcast.xml`. It remains unavailable until `appcast.xml` is attached to a published latest GitHub Release. Do not publish the feed or release from this script; publishing is an explicit owner action. A concrete GitHub CLI shape is:

```sh
VERSION=0.2.0
RELEASE_NOTES=/path/to/release-notes.md # owner-prepared release notes

gh release create "v$VERSION" \
  "dist/Pfennig-$VERSION-macOS.zip" \
  "dist/Pfennig-$VERSION-macOS.zip.sha256" \
  "dist/Pfennig-$VERSION-macOS-update.zip" \
  "dist/Pfennig-$VERSION-macOS-update.zip.sha256" \
  dist/appcast.xml dist/appcast.xml.sha256 \
  --verify-tag --latest \
  --title "Pfennig $VERSION" --notes-file "$RELEASE_NOTES"
```

Do not reset or replace the app’s existing data when installing an update. The update asset is app-only; the distribution ZIP is the owner’s manual first-install/replacement asset.

The repository source archive generated for the tag provides the corresponding GPLv3 source for that binary. Never upload the temporary notarization ZIP, `notary-result.json`, or the temporary `sparkle-updates/` directory.
