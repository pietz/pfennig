# Releasing Pfennig for macOS

Pfennig will initially be distributed outside the Mac App Store as a Developer ID signed and Apple-notarized ZIP. Release credentials remain in the local macOS Keychain and are never passed through environment files or committed to the repository.

## One-time setup

Install a valid `Developer ID Application` certificate and store notarization credentials:

```sh
xcrun notarytool store-credentials "ziffer-notary" \
  --apple-id "YOUR_APPLE_ACCOUNT_EMAIL" \
  --team-id "34MWWCL4H2"
```

Use an app-specific Apple Account password when prompted. The resulting Keychain item is referenced only by the local profile name `ziffer-notary`. That name predates the rename and is kept so the existing local credentials keep working; set `NOTARY_PROFILE` to use a differently named profile.

## Build and notarize

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Start from the exact clean commit that will be tagged.
3. Run the tests and release pipeline:

```sh
scripts/test.sh
scripts/release.sh --notarize
```

The script:

- creates a Release archive with Hardened Runtime
- signs it with the Developer ID Application identity
- verifies the code signature
- submits a temporary ZIP to Apple and waits for `Accepted`
- staples and validates the notarization ticket
- runs a Gatekeeper assessment
- creates `dist/Pfennig-<version>-macOS.zip` with the app, GPLv3 license, privacy notice, and its SHA-256 file

Use `scripts/release.sh --build-only` to test release signing without contacting Apple's notarization service. Override `TEAM_ID`, `SIGNING_IDENTITY`, or `NOTARY_PROFILE` in the environment when another authorized maintainer performs a release.

## Publish

Publishing is a separate, deliberate step. After verifying the final ZIP on a clean macOS user account:

1. Tag the exact release commit as `v<version>`.
2. Create a GitHub Release from that tag.
3. Attach the notarized ZIP and `.sha256` file from `dist/`.
4. Include concise release notes and known limitations.

The repository source archive generated for the tag provides the corresponding GPLv3 source for that binary. Never upload the temporary notarization ZIP or `notary-result.json`.
