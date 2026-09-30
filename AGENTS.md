# Repository Guidelines

## Project Structure & Module Organization

PaperComp is an iPad SwiftUI app targeting iOS 18+. App shell, SwiftData models,
PDF reader, and PencilKit live in `PaperComp/`. Online search and citations are
in `PaperCompSearch/`; on-device llama.cpp, retrieval, and model management are
in `PaperCompLocal/`. Unit tests are in `PaperCompTests/` plus
`PaperCompSearch/Tests/` and `PaperCompLocal/Tests/`; UI tests are in
`PaperCompUITests/`. Static privacy/support pages are in `site/`. Device-only
llama embed helper: `Scripts/embed-llama-device.sh`. Version pin:
`Vendor/LLAMA_VERSION` (framework binary not vendored here).

Edit `project.yml`, then run `xcodegen generate`.

## Build, Test, and Development Commands

Requires Xcode 26.3 and XcodeGen 2.45.4.

```sh
xcodegen generate
xcodebuild -scheme PaperComp -destination 'platform=iOS Simulator,id=FAD01B61-CF3A-4C70-8F35-CDE45E789D8B' -parallel-testing-enabled NO build test
```

Use `-only-testing:PaperCompTests/<ClassName>` for a focused XCTest run.
Simulator builds work without `Vendor/llama.xcframework`. For device builds, add
your `DEVELOPMENT_TEAM`, adjust bundle IDs if needed, and install the xcframework
matching `Vendor/LLAMA_VERSION` (see README).

## Coding Style & Naming Conventions

Idiomatic Swift 6, four-space indentation, `UpperCamelCase` types,
`lowerCamelCase` properties and methods. Organize by feature (`Library`,
`Reader`, `Models`, `Shared`). Reuse `Theme` tokens; preserve light/dark.

## Testing Guidelines

XCTest / Swift Testing. Name files `<Feature>Tests.swift`. Prefer focused unit
tests for behavior changes, then the full simulator command above. Never call
the real OpenAI API from tests.

## Commit & Pull Request Guidelines

Concise imperative subjects (for example, `Fix page marker persistence`). PRs
should explain behavior changes, list verification commands, and include
screenshots for UI changes when useful.

## Security & Configuration

Never commit or print secrets (`.env`, Keychain values, provisioning material).
Do not add backend deploy config or release/TestFlight scripts to this tree.
Do not download or create additional simulator runtimes in automated flows.
