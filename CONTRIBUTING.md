# Contributing

Thanks for interest in PaperComp.

## Setup

1. Install Xcode 26.3 and XcodeGen 2.45.4.
2. Clone this repository.
3. Run `xcodegen generate`.
4. Build and test on the documented simulator (see README).

Device/on-device LLM work additionally needs the llama.cpp xcframework described
in the README.

## Changes

- Prefer small, focused pull requests.
- Edit `project.yml` (not the generated Xcode project), then regenerate.
- Keep UI on the existing `Theme` tokens (light and dark).
- Add or update unit tests for behavior changes under `PaperCompTests/` or the
  module `Tests/` folders.
- Never call the real OpenAI API from tests; never commit secrets.

## Commit style

Use concise, imperative subjects (for example, `Fix page marker persistence`).

## Conduct

Be respectful. By contributing, you agree that your contributions are licensed
under the Apache License 2.0, and that NOTICE / THIRD_PARTY_NOTICES attributions
must be preserved where required.
