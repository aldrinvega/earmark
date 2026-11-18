# Plan: Earmark (whole project)

> Implements [SPEC.md](../SPEC.md) (approved 2026-11-13). Status: **APPROVED 2026-11-14.**
> Detailed tasks for Phases 0–1 are in [todo.md](todo.md). Later phases get their own
> `SPEC-<module>.md` → `<module>-plan.md` → `<module>-todo.md` when they start, as in Glasswing.

## Approach: prove the two risks first, then build the app around them

1. **Pipeline risk.** There is no Xcode on the Mac, so nothing counts until CI turns the code into an `.ipa` that
   SideStore installs on the iPhone SE. Phase 0 makes an empty app reach the phone.
2. **Read-along risk.** Everything special about the app depends on lining up the narration with the EPUB text on
   an iPhone SE. Phase 1 is a spike that measures this on the real phone with one public-domain chapter, before any
   library, player or reader work. If it fails, we switch to the Mac fallback (with your approval) before anything
   else is built on top.

The rest of the project is ordinary work on known APIs (Audiobookshelf, AVFoundation, WKWebView), so it follows the
spec's build order.

```
Phase 0  Pipeline            package + local tests → XcodeGen app → CI .ipa → installed on the iPhone
   ── checkpoint A: blank Earmark app launches on your phone ──
Phase 1  Read-along spike    aligner (local tests) + sentence IDs + fixtures → Diagnostics screen on the phone
   ── checkpoint B: GO / NO-GO for on-phone alignment ──
Phase 2  Foundations         abs-client · ebook-source · library      (independent; can run in parallel)
   ── checkpoint C: smoke-servers.sh green against the Mac; store tests green on CI ──
Phase 3  First real build    app-shell (sign-in, tabs, settings) + player (play, sync, Lock Screen)
   ── checkpoint D: you listen to a real book on the phone, progress shows in the web app ──
Phase 4  Reader              epub-reader (EPUB → sentences → WKWebView, themes, Chapters sheet)
Phase 5  Read-along          alignment pipeline + cache, highlight, tap-to-seek, follow / back to narrator
   ── checkpoint E: listen-and-read works on a real book for 10 minutes ──
Phase 6  Recap               "Previously on…" card, days-away rule, resume −15 s
Phase 7  Downloads           offline audio + EPUB, storage, Wi-Fi only, Mac-off behaviour
   ── checkpoint F: every SPEC success criterion checked off with evidence ──
```

## Architecture decisions (from the spec, made concrete)

- **One Swift package, `EarmarkKit`, holds every rule.** The app target is SwiftUI views plus thin adapters for
  AVFoundation, Speech and WebKit. Each adapter implements a protocol from the package (`PlaybackControlling`,
  `Transcribing`, `ReaderBridge`), so the logic is tested locally with `swift test` and on CI.
- **Sentence IDs are the shared key** between the reader, the aligner, the recap and progress:
  `<spine index>.<paragraph index>.<sentence index>`, computed the same way every time from the EPUB. Built in
  Phase 1, because both the spike and the reader depend on it.
- **Alignment output is one JSON file per chapter** (`AlignmentMap`: sentence ID → start/end seconds, optional word
  times), cached in Application Support and keyed by book ID + audio file checksum. The reader only ever asks
  "which sentence is at time t?" and "when does sentence s start?".
- **Audiobookshelf is the source of truth for progress.** Local progress is a cache. Conflicts go to the newest
  `lastUpdate`, and the app never moves the server position backwards without asking.
- **Stub servers for UI tests**: a `URLProtocol` that serves recorded Audiobookshelf / Pocket Book Studio
  responses, turned on with `-EarmarkStubServers` and compiled out of Release (same pattern as Glasswing).

## Dependencies & ordering

- Phase 1 needs Phase 0 only for its last task (the Diagnostics screen on the phone). Tasks 4–6 are local.
- Phase 2's three modules don't depend on each other. Each one is a good **separate session** (own spec, own
  files: `ABSClient/`, `EbookSource/`, `Store/`). They meet in Phase 3.
- `epub-reader` (Phase 4) reuses Phase 1's `SentenceSplitter`. `read-along` (Phase 5) reuses the aligner and the
  Diagnostics transcriber adapter.
- `docs/abs-api.md` and `docs/pbs-api.md` are written at the start of Phase 2, **before** the clients, from real
  responses of your servers (recorded into fixtures, with tokens and personal data removed).

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| On-device speech-to-text is too slow or too hot on an iPhone SE | Read-along can't keep up | Phase 1 measures it first. Process chapters ahead of playback, only while playing or charging. Fallback: whisper.cpp on the Mac (ask first) |
| `SpeechTranscriber` (iOS 26) isn't available on the SE's A15 chip | Need the older API | The adapter falls back to `SFSpeechRecognizer` with on-device recognition; the spike tests both |
| Speech-to-text misses 19th-century words and names | Highlights drift | Aligner matches on normalised words with gaps allowed, and re-anchors on long exact runs; quality measured on the fixture |
| Audiobook narration differs from the EPUB (intros, footnotes, abridged) | Unmatched stretches | Aligner marks those sentences "unaligned"; the reader then follows by chapter, not by sentence |
| Audiobookshelf API changes between versions | Client breaks | Pin behaviour to 2.37.2 in `docs/abs-api.md`; `smoke-servers.sh` checks the real server |
| SideStore 7-day re-signing (free Apple ID) | App stops opening weekly | Same as Glasswing; noted in the log, not solved in code |
| GitHub free macOS minutes run out | Slow builds | iOS workflow runs only on `ios/**` changes, with cancel-in-progress (Glasswing's setup) |

## Verification checkpoints

- **A (after Task 3):** you install `Earmark-<sha>.ipa` with SideStore and it opens to the placeholder screen.
- **B (after Task 8):** the Diagnostics run on your phone, logged in `tasks/spike-log.md`. **GO** if: ≥90% of
  sentence starts within 0.5 s on the fixture chapter, and one minute of audio is processed in ≤30 s without the
  phone getting hot. Otherwise **NO-GO** → we decide together between the Mac fallback and a simpler
  chapter-level follow mode.
- **C:** `ios/smoke-servers.sh` green against your Mac; all package tests green locally and on CI.
- **D:** you play a real book on the phone with the screen locked, and the position appears in the Audiobookshelf
  web app.
- **E:** listen-and-read for 10 minutes on a real book with no visible drift; tap-to-seek works.
- **F:** every item in SPEC.md "Success Criteria" checked off with evidence (CI run links, screenshots, log notes).

## Open questions for this plan

1. **Fixture chapter.** Proposed: *Pride and Prejudice* chapter 3, audio from LibriVox and text from Project
   Gutenberg (both public domain), trimmed to about 3 minutes (~2 MB) and bundled in the app only for Diagnostics.
   I'll ask before downloading anything (file, source, size).
2. **GitHub repo.** Resolved 2026-11-18: `aldrinvega/earmark` is **public**, because the free plan's private
   macOS minutes ran out and public repos build free.
