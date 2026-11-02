# Contributing

Thanks for helping make Runwright better.

## Getting started

```sh
swift build
swift test
swift run Runwright
```

No runner installed? Turn on **Demo** in the title bar.

## Making a change

1. Open an issue first for anything bigger than a small fix, so we can agree on the approach.
2. Branch from `main` and keep each pull request to one change.
3. Add or update tests in `Tests/` for parsing, store or config logic.
4. Make sure `swift test` passes.
5. Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:` …).

## Style

- UI uses the `SlateDesign` tokens and components. Don't hard-code colours or sizes.
- Keep `RunwrightCore` free of SwiftUI so it stays testable.
- Never write tokens or secrets to disk or logs.

By contributing you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
