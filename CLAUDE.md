# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Earmark: a personal, sideloaded iOS 26+ app that plays audiobooks from an Audiobookshelf server and shows the matching EPUB (from "Pocket Book Studio") with the narrated sentence highlighted; tapping a sentence seeks the audio. `SPEC.md` is the approved spec (objective, capability map, boundaries); `tasks/plan.md` is the phased plan, `tasks/todo.md` the per-task checklist with verification evidence, and `tasks/spike-log.md` / `app-log.md` hold on-phone run results. The project is currently in Phase 1 (read-along alignment spike); only the Swift package plus a placeholder/Diagnostics app exist so far (no `abs-client`, `player`, etc. yet).

## Build and test

There is no Xcode on the owner's Mac (and this Windows PC has no Swift toolchain), so only the Swift package is tested locally; the app is built only on GitHub's `macos-26` runner.

```
ios/test-local.sh                               # on the Mac: swift.org toolchain, EARMARK_NO_SWIFTDATA=1 swift test in ios/EarmarkKit
ios/test-local.sh --filter ReadAlongCoreTests   # one target/suite/test (any swift test args pass through)
swift test --package-path ios/EarmarkKit        # CI: all targets incl. SwiftData Store
gh run list --workflow ios.yml --limit 5        # CI results; gh run download <id> -n Earmark-ipa for the unsigned .ipa
```

- `.github/workflows/ios.yml` (runs only when `ios/**` changes): package tests, a Release-mode aligner performance test (`EARMARK_PERF=1`, `--filter AlignerPerformanceTests`), then XcodeGen → simulator tests on iPhone SE (3rd generation) → unsigned archive → `.ipa`.
- The `.xcodeproj` is never committed; it is generated from `ios/project.yml` by XcodeGen on CI.
- The `Store` (SwiftData) target and `StoreTests` exist in `Package.swift` only when `EARMARK_NO_SWIFTDATA` is unset, because its `@Model` macros need Xcode.
- Package is Swift 6 language mode, iOS/macOS 26. Tests use Swift Testing.

## Architecture

Logic lives in the `ios/EarmarkKit` package so it is testable without Xcode; `ios/Earmark` holds only thin SwiftUI views and on-device speech/audio code. Target dependency chain:

- `Models` – shared value types (e.g. `SentenceID`), Foundation only.
- `ReadAlongCore` – text↔audio alignment on value types (normaliser, aligner, `AlignmentMap`, spoken timing); no Speech/AVFoundation.
- `EPUBCore` – one XHTML chapter → paragraphs → sentences with stable IDs, the aligner's input.
- `AppFeatures` – `@Observable @MainActor` view models and UI logic/strings (Diagnostics first), Foundation + Observation only.
- `Store` – SwiftData library store (CI-only locally); depends on `Models` only.
- `EarmarkTestSupport` – public-domain fixtures (`Fixtures/`: Pride and Prejudice ch. 3 text, audio clip, hand-checked reference sentence starts, run reports). Never shipped in the app logic, but the app bundles the Fixtures folder as a resource for the on-phone Diagnostics "Align test chapter" screen (see `project.yml`).

The app target (`ios/Earmark`) contains the real recognizers (`SpeechAnalyzerTranscriber`, `LegacySpeechTranscriber`, chosen by `DeviceTranscriberChooser`) which feed transcripts into `ReadAlongCore`; alignment quality is judged as the share of sentence starts within 0.5 s of the reference starts. Spike runs on the phone are copied from Diagnostics into fixtures/reports and replayed in tests (e.g. `RecordedSpikeRunTests`).

## Conventions

- Commit subjects start with the module id: `read-along: fix spike run 1 — ...`.
- One type per file, no force-unwraps outside tests, `@MainActor` view models, clients are `actor`s or `Sendable` structs, typed error enum per client mapped to user text in `AppFeatures`.
- Layouts are checked at 375×667 (iPhone SE 3rd gen) first. Use system glass (`.glassEffect`), never hand-made blur.
- **The repo is public.** Never commit tokens, passwords, signing material, or anything copyrighted (fixtures are public domain only); scrub recorded server responses.
- Ask before adding a dependency, changing anything on the Mac's services, sending book text/audio to outside services, or changing the SwiftData schema after first install. Don't touch `~/Projects/glasswing` or `aniyomi-retro` (reference only).
- `.crew/` holds agent working notes and `opencode.json` is an unrelated agent config; neither is app code.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for aldrinvega/earmark (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
