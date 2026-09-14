# Security policy

## Reporting a vulnerability

Please do not disclose security vulnerabilities in a public issue. Use GitHub's **Report a vulnerability** action on the repository's Security page to open a private report with the maintainer.

Include affected versions, reproduction steps, impact, and any suggested mitigation. Do not include real bookkeeping documents, API keys, passwords, or other personal data.

The maintainer will acknowledge the report, investigate it, and coordinate disclosure and a fix where appropriate. There is currently no paid bug-bounty program.

## Supported versions

Pfennig is pre-1.0. Security fixes are made on the latest release and `main`; older builds are not maintained separately.

## Scope

Relevant reports include unintended disclosure or corruption of local bookkeeping data, unsafe handling of imported documents, Keychain credential exposure, unauthorized network transmission, and release-signing or update-channel vulnerabilities.

Bookkeeping or tax-correctness questions without a security impact should be filed as ordinary issues.
