# PaperComp

Native iPad app for reading and annotating research PDFs with Apple Pencil, plus
“circle/box to search” answers from an on-device [llama.cpp](https://github.com/ggml-org/llama.cpp)
model or optional GPT (bring your own OpenAI API key).

## Requirements

- macOS with **Xcode 26.3**
- **XcodeGen 2.45.4** (`brew install xcodegen`)
- **iOS 18+** (iPad)
- For the documented test command: iOS Simulator
  `FAD01B61-CF3A-4C70-8F35-CDE45E789D8B` (iPad Pro 13" M4)

## Quick start (simulator)

```sh
xcodegen generate
xcodebuild -scheme PaperComp \
  -destination 'platform=iOS Simulator,id=FAD01B61-CF3A-4C70-8F35-CDE45E789D8B' \
  -parallel-testing-enabled NO \
  build test
```

Simulator builds do **not** need `Vendor/llama.xcframework`. Local-LLM code
compiles and degrades cleanly when the framework is absent (`#if canImport(llama)`).
On-device model download/run requires a device build with the framework (below).

## Device builds and llama.cpp

1. Set your Apple Development Team in `project.yml` (`DEVELOPMENT_TEAM`) or in
   Xcode signing settings. Change `PRODUCT_BUNDLE_IDENTIFIER` values if
   `com.elijah.papercomp` is not available on your team.
2. Download the llama.cpp iOS xcframework matching `Vendor/LLAMA_VERSION`
   (currently `b11174`) from the
   [llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases)
   asset `llama-bNNNNN-xcframework.zip`.
3. Unzip so the tree is `Vendor/llama.xcframework/` (device arm64 slice used by
   `project.yml` and `Scripts/embed-llama-device.sh`).
4. Generate, then build for a physical iPad:

```sh
xcodegen generate
xcodebuild -scheme PaperComp -destination 'platform=iOS,id=<YOUR_DEVICE_ID>' build
```

The embed script runs only for `iphoneos` and is a no-op on simulator.

## GPT (optional)

Paste your own OpenAI API key in Settings → GPT. No key ships in the app; the
key is stored in the Keychain on that device only. Without a key, search stays
on-device (when a model is available).

## Layout

| Path | Role |
|------|------|
| `PaperComp/` | App shell, library, PDF reader, PencilKit, SwiftData |
| `PaperCompSearch/` | Search UI, OpenAI client, lookups, citations |
| `PaperCompLocal/` | On-device llama.cpp runner, retrieval, model catalog |
| `PaperCompTests/`, `*/Tests/`, `PaperCompUITests/` | Tests |
| `site/` | Privacy and support HTML (also bundled into the app) |
| `Scripts/embed-llama-device.sh` | Embed/sign llama.framework on device builds |
| `Vendor/LLAMA_VERSION` | Pinned llama.cpp release tag |

Edit `project.yml`, then run `xcodegen generate`. Do not hand-edit the generated
`.xcodeproj`.

## License and trademarks

Source code is licensed under the **Apache License 2.0** — see `LICENSE` and
`NOTICE`.

Apache-2.0 does **not** grant rights to the PaperComp name, logos, or other
trademarks/branding. You may use the source under the license; you may not imply
endorsement or reuse the PaperComp marks without permission.

Third-party attributions (bundled CC BY 4.0 sample paper, llama.cpp MIT,
downloadable model licenses) are in `THIRD_PARTY_NOTICES`.

## Security

See `SECURITY.md`. Never commit API keys, `.env` files, or provisioning secrets.
