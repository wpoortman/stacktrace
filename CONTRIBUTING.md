# Contributing to Stacktrace

Thanks for your interest in improving Stacktrace! This is a small, focused
macOS app — contributions that keep it simple, fast, and pleasant to use are
very welcome.

## Ways to contribute

- **Report a bug** — open an issue with steps to reproduce, what you expected,
  what happened, your macOS version, and a screenshot if it's a UI problem.
- **Suggest a feature** — open an issue describing the problem you're trying to
  solve, not just the solution. The app aims to stay lightweight, so smaller,
  well-scoped ideas are easier to land.
- **Send a pull request** — fixes, polish, and focused features.

If a change is large or changes the app's direction, please open an issue to
discuss it first so we don't both waste effort.

## Development setup

Requirements:

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

Get building:

```bash
git clone https://github.com/wpoortman/stacktrace.git
cd stacktrace
open Stacktrace.xcodeproj      # then press ⌘R
```

The Xcode project is **generated from `project.yml`** by XcodeGen. If you add,
remove, or move files, or change build settings, regenerate it and commit the
result:

```bash
xcodegen generate
```

Source lives in `Stacktrace/`:

- `Models/` — data store (JSON persistence), entry model, helpers, services
- `Views/` — SwiftUI views, including `Settings/`
- `PDF/` — report HTML builder and PDF generator

## Pull request guidelines

1. Fork the repo and create a branch off `main`
   (e.g. `fix/export-filename`, `feat/weekly-goal`).
2. Keep PRs focused — one logical change per PR.
3. Make sure it builds cleanly with no new warnings:
   ```bash
   xcodebuild -project Stacktrace.xcodeproj -scheme Stacktrace \
     -configuration Debug build
   ```
4. Run the app and verify the change behaves as described.
5. **Run the tests** (see below) — they must pass.
6. Write a clear PR description: what changed, why, and how you tested it.
   Include before/after screenshots for any UI change.

## Tests

Unit tests cover the core logic (data store, routines, report builders,
licensing, scheduling). Run them locally:

```bash
xcodegen generate
xcodebuild test -project Stacktrace.xcodeproj -scheme Stacktrace \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO
```

The same suite runs automatically on every push and pull request via GitHub
Actions (`.github/workflows/ci.yml`). Add tests under `StacktraceTests/` for
any logic you change.

## Code style

- Match the surrounding code — naming, spacing, and idioms.
- Plain SwiftUI + Swift standard library; avoid adding dependencies.
- Prefer small, readable views and value types. Keep persistence going through
  `DataStore`.
- No force-unwraps in code paths that can realistically fail; handle errors
  gracefully.
- Comment the *why* when something is non-obvious, not the *what*.

## Data & privacy

Stacktrace is local-first. Don't add code that sends user content anywhere
except features the user explicitly opts into (the optional OpenAI enhancement).
Never commit secrets, API keys, or local absolute paths.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
