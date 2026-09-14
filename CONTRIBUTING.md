# Contributing to Pfennig

Pfennig welcomes focused bug fixes, tests, documentation, and features that fit its German, local-first bookkeeping scope.

Before starting substantial work, open or comment on a GitHub issue so the product behavior can be agreed before implementation. The principles in [`AGENTS.md`](AGENTS.md) and the detailed rules in [`concept.md`](concept.md) guide scope decisions.

## Development setup

Requirements and bootstrap instructions are in the [`README`](README.md).

```sh
scripts/bootstrap.sh
scripts/test.sh
scripts/build.sh
```

Run SwiftFormat on Swift files you change and ensure `git diff --check` passes. Do not include real invoices, personal bookkeeping data, API keys, `.env` files, or credentials in commits or test fixtures.

## Pull requests

Keep changes small and coherent. A pull request should explain:

- the user problem it solves
- the chosen behavior and important scope exclusions
- how it was verified
- whether it changes stored data, tax behavior, AI prompts, or data sent to an external service

Add deterministic tests for bookkeeping and tax rules. AI extraction tests must use synthetic documents and recorded responses; live API access must remain optional.

## Tax-related changes

Use current official German primary sources for consequential rules and link them in the pull request. Prefer a few explicit rules for common cases. Unsupported or ambiguous cases should remain reviewable rather than being guessed.

## License

By contributing, you agree that your contribution is licensed under the GNU General Public License, version 3.
