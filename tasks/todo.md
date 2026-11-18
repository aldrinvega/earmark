# Todo: Earmark — Phases 0–1 (pipeline + read-along spike)

> From [plan.md](plan.md). Later phases are added after their module specs are approved.
> Local test command: `ios/test-local.sh` (swift.org toolchain). CI: `.github/workflows/ios.yml` on `macos-26`.

## Phase 0 — Pipeline

## Task 1: Package skeleton and local tests

**Description:** Create the repo layout and the `EarmarkKit` Swift package with the `Models` target, a test target and
`EarmarkTestSupport`, plus `ios/test-local.sh`. The SwiftData `Store` target is gated by `EARMARK_NO_SWIFTDATA`, as in
Glasswing. `git init` locally (no remote yet).

**Acceptance criteria:**
- [x] `ios/test-local.sh` runs and passes one real test (e.g. `SentenceID` round-trips through its string form)
- [x] Layout matches SPEC.md "Project Structure"; `.gitignore` excludes `*.xcodeproj`, `build/`, `.build/`, `.DS_Store`

**Verification:**
- [x] Tests pass: `ios/test-local.sh` — 6 tests in `SentenceIDTests` passed (2026-11-14, Swift 6.4.2)
- [x] Manual check: `git status` shows only the intended files
- [x] Extra: the `Store` placeholder also builds locally without the gate (`swift build --target Store`)

**Dependencies:** None

**Files likely touched:** `ios/EarmarkKit/Package.swift`, `ios/EarmarkKit/Sources/Models/SentenceID.swift`,
`ios/EarmarkKit/Tests/ModelsTests/SentenceIDTests.swift`, `ios/test-local.sh`, `.gitignore`

**Estimated scope:** Small

## Task 2: XcodeGen project and placeholder app

**Description:** Add `ios/project.yml` (iOS 26, iPhone, portrait, Swift 6, bundle id `local.earmark`,
`UIBackgroundModes: audio`) and a placeholder app: `EarmarkApp` + `RootView` showing the app name on a glass card,
an app icon and the accent colour.

**Acceptance criteria:**
- [x] `project.yml` declares the app, a unit-test host and a UI-test target, and depends on the local package
- [x] Info.plist keys are generated from `project.yml`, except `UIBackgroundModes: audio`, which has no
      `INFOPLIST_KEY_` setting and lives in a 1-key partial `ios/Support/Info.plist` merged in (Glasswing's pattern)

**Verification:**
- [ ] Build succeeds: on CI in Task 3 (`xcodegen generate` + `xcodebuild archive`) — **still open**
- [x] Local checks (2026-11-14): `project.yml` parses (Ruby YAML; 3 targets, test scheme), `plutil -lint` OK, asset
      JSON valid, icon 1024×1024 opaque, `ios/test-local.sh` still green
- [x] Manual check: same settings as Glasswing's current `project.yml` (minus MPVKit, plus test targets)

Also added: `ios/tools/make-icon.swift` (regenerates the placeholder icon), `EarmarkTests/RootViewTests.swift`,
`EarmarkUITests/LaunchSmokeTests.swift`.

**Dependencies:** Task 1

**Files likely touched:** `ios/project.yml`, `ios/Earmark/App/EarmarkApp.swift`, `ios/Earmark/App/RootView.swift`,
`ios/Earmark/Assets.xcassets/`

**Estimated scope:** Small

## Task 3: CI workflow, public GitHub repo, first `.ipa`

**Description:** Add `.github/workflows/ios.yml` with two jobs, copied from Glasswing's: package tests, and
generate → archive unsigned → zip `Earmark-<sha>.ipa` → upload artifact (14 days). Runs only on `ios/**` changes.
**Confirm with the owner, then** create the repo `aldrinvega/earmark` and push. (Owner chose **public** on
2026-11-18: private macOS minutes on the free plan were used up; public repos build free.)

**Acceptance criteria:**
- [x] A push to `main` produces a green run and an `Earmark-ipa` artifact
- [x] The repo is public, and no secrets, certificates, private hostnames or ports are in it or in the logs
      (scanned before the first push; older commits still contain internal tailnet-only port numbers)

**Verification:** (2026-11-18, run 44211392526 at df4b6e9, first try)
- [x] `gh run list --workflow ios.yml --limit 1` shows success — jobs `test` and `app` green
- [x] Package tests on CI: 7 tests in 2 suites incl. the SwiftData `StoreSchemaTests`
- [x] iPhone SE (3rd gen) simulator created on iOS 26.5; `LaunchSmokeTests` passed; `** TEST SUCCEEDED **`,
      `** ARCHIVE SUCCEEDED **`
- [x] `gh run download <id> -n Earmark-ipa` gives `Earmark-df4b6e9.ipa` (490 KB) with `Payload/Earmark.app`;
      Info.plist: `local.earmark`, display name Earmark, min iOS 26.0, `UIBackgroundModes` audio
- [x] Manual check (owner): installs with SideStore and opens on the iPhone SE (2026-11-18, `tasks/app-log.md`)

**Dependencies:** Task 2

**Files likely touched:** `.github/workflows/ios.yml`, `tasks/app-log.md`

**Estimated scope:** Small

### Checkpoint A — blank app on the phone
- [x] Owner installed `Earmark-<sha>.ipa` and it opened (noted in `tasks/app-log.md`)
- [x] Local and CI tests green

## Phase 1 — Read-along spike

## Task 4: Aligner on value types (local)

**Description:** In `ReadAlongCore`, write the aligner: input = transcript words with start/end times + sentences
(ID + text); output = `AlignmentMap` (sentence → start/end, unaligned sentences marked). Normalise words (case,
punctuation, curly quotes, numbers), match with gaps allowed, re-anchor on long exact runs. Lookup helpers
`sentence(at:)` and `startTime(of:)`.

**Acceptance criteria:**
- [x] Perfect transcript → every sentence start exact
- [x] Noisy transcript (10% words substituted, 5% dropped, an extra intro sentence) → ≥95% of starts within 0.5 s
      — made stricter: 200 sentences, ±0.2 s jitter, paraphrase, 4 seeds → 97.5 / 97.5 / 99.5 / 97.5 %
- [x] A missing paragraph in the audio is marked unaligned without shifting the sentences after it

**Verification:** (2026-11-18)
- [x] Tests pass: `ios/test-local.sh` — 26 ReadAlongCore tests in 6 suites + 6 SentenceID tests
- [x] Crew review: review-4 NO-GO (crash on overlapping anchors, lucky-seed test, untested fallback, start-only
      lookup, spellings) → fixed → review-5 NO-GO (band regression after long insertion, whitespace merges, years)
      → fixed → review-6 **GO**. Fuzz: 623 seeded runs, no crash. 10k words: 0.13 s anchored, 2.5 s worst fallback.

**Follow-ups (non-blocking, from review-6) — do before relying on the no-anchor fallback:**
- [ ] Fallback band is capped at ~50M cells (~55 MB peak). On a repetitive chapter with no unique 4-grams, a long
      insertion near the start (or > ~5,000 words) loses accuracy (e.g. 490/600 exact). Fix: split full unanchored
      segments recursively (Hirschberg / book midpoint); add insertion-at-start/end and 6,000-word tests.
- [ ] Book `to-day` vs transcript words `to`, `day` starts 0.4 s late: group adjacent transcript words into one
      token when the book has a merged hyphen token; add the cross test.

**Dependencies:** Task 1

**Files likely touched:** `ReadAlongCore/Aligner.swift`, `ReadAlongCore/AlignmentMap.swift`,
`ReadAlongCore/TextNormalizer.swift`, `Tests/ReadAlongCoreTests/AlignerTests.swift`

**Estimated scope:** Medium

## Task 5: Sentence splitting with stable IDs (local)

**Description:** In `EPUBCore`, turn one XHTML chapter into paragraphs and sentences with IDs
`<spine>.<paragraph>.<sentence>`, using `XMLParser` and `NLTokenizer(.sentence)`. Handles "Mr." / "Mrs.", quotes and
dashes in 19th-century text.

**Acceptance criteria:**
- [x] The same input always gives the same IDs (checked twice in one test run) — plus a golden test pinning the
      exact 9 IDs and texts of the P&P excerpt; tokenizer language pinned to English
- [x] "Mr. Bennet" and "Mrs. Bennet" don't split sentences; dialogue in quotes stays with its sentence
- [x] Output text matches the source characters (only whitespace normalised), so the reader can find each sentence
      (UTF-16 ranges, tested with emoji and combining marks)

**Verification:** (2026-11-18)
- [x] Tests pass: `ios/test-local.sh` — 51 EPUBCore tests in 7 suites (+ 26 ReadAlongCore, 6 SentenceID)
- [x] Crew review: review-7 NO-GO (10 findings: abbreviation false joins, noterefs, ID stability, soft hyphens/ZWSP,
      inline elements, ruby, straight quotes, CDATA, UTF-16 tests, error position) → fixed → review-9 NO-GO (word-count
      gate split "St. James's", initials, ellipsis, noteref ate words, weak test) → fixed → review-11 **GO**.

**Follow-ups (non-blocking, from review-11):**
- [ ] Add titles (mr, mrs, ms, dr, prof, miss, sir, lady, lord, capt, col, gen) to the sentence-opener stoplist so
      "…Baker St. Mrs. Hudson opened the door." splits; test it; document that "…St. Holmes was waiting." (a proper
      noun after a sentence-final St.) stays one sentence by design.
- [ ] Noteref markers: accept only valid Roman numerals as letter markers (keep "civil"/"vivid"), allow `1a`/`n1`.
- [ ] A kept (non-marker) noteref loses its inner spaces (`the<a …> house </a>early` → `thehouseearly`): append the
      raw buffer.

**Dependencies:** Task 1

**Files likely touched:** `EPUBCore/SentenceSplitter.swift`, `EPUBCore/XHTMLText.swift`,
`Tests/EPUBCoreTests/SentenceSplitterTests.swift`, a small inline XHTML fixture

**Estimated scope:** Medium

## Task 6: Public-domain fixture chapter (needs your OK to download)

**Description:** Ask first (file, source, size). Then add *Pride and Prejudice* ch. 3: Gutenberg XHTML text and a
~3-minute LibriVox audio clip (AAC, ~2 MB), plus `expected-starts.json` with hand-checked start times for every
sentence in the clip.

**Acceptance criteria:**
- [x] Fixture files are public domain, with their source and licence in `EarmarkTestSupport/Fixtures/README.md`
      (owner OK'd the download 2026-11-18; Gutenberg #1342 via the PGLAF mirror; LibriVox version 4, Elizabeth Klett)
- [ ] ~~`expected-starts.json` covers every sentence in the clip~~ **Changed:** `pp-ch3-expected-starts.json` lists the
      **8** of ~21 sentence starts that can be trusted without listening (long pause + steady 2.7–3.7 words/s between
      neighbours). This narrator pauses as long at commas as at full stops, so a pause-only fit was wrong inside
      paragraphs (5–8 words/s); those starts are left out rather than guessed. The Task 8 GO metric uses these 8.

**Verification:** (2026-11-18)
- [x] Tests pass: `ChapterFixtureTests` (84 sentences, no edition artefacts, 8 starts are real IDs in order, clip is an
      MP4) — full `ios/test-local.sh`: 35 ReadAlongCore + 6 SentenceID + 54 EPUBCore tests
- [ ] Manual check (owner): listen to `pp-ch3-clip.m4a` at 0:14.9 "NOT all that Mrs. Bennet", 1:04.8 "If I can but
      see", 1:39.9 "An invitation to dinner", 2:12.4 "Lady Lucas quieted her fears", 2:47.5 "Mr. Bingley was
      good-looking" — each should start within ½ s.
- Fixed on the way: `Fixtures.url` looked in the bundle root; on macOS resources are in `Contents/Resources`.

**Follow-ups found while preparing the fixture (EPUBCore, real-EPUB markup):**
- [ ] Drop-cap images (`<img alt="N"/>` + "OT all…") should contribute their `alt` letter without a space.
- [ ] Page-number markers (`<span class="pagenum">`, `epub:type="pagebreak"`) must be skipped, not read as text.
- [ ] Illustration captions inside the text flow, and paragraphs split around an illustration.

**Dependencies:** Task 5

**Files likely touched:** `EarmarkTestSupport/Fixtures/pp-ch3.xhtml`, `pp-ch3-clip.m4a`, `expected-starts.json`,
`README.md`

**Estimated scope:** Small

## Task 7: Transcriber protocol and on-device adapters

**Description:** `Transcribing` protocol in `ReadAlongCore` (audio URL → words with times). Two app-side adapters:
`SpeechTranscriber` (iOS 26 `SpeechAnalyzer`) and `SFSpeechRecognizer` with `requiresOnDeviceRecognition`,
picked at runtime by availability. Speech-recognition permission string in `project.yml`.

**Acceptance criteria:**
- [ ] A fake transcriber in tests drives the aligner end to end
- [ ] Both adapters compile on CI. Neither sends audio off the device (on-device flags asserted)

**Verification:**
- [ ] Tests pass: `ios/test-local.sh`; CI archive green

**Dependencies:** Tasks 3, 4

**Files likely touched:** `ReadAlongCore/Transcribing.swift`, `ios/Earmark/Diagnostics/SpeechAnalyzerTranscriber.swift`,
`ios/Earmark/Diagnostics/LegacySpeechTranscriber.swift`, `ios/project.yml`

**Estimated scope:** Medium

## Task 8: Diagnostics screen and on-phone run

**Description:** Settings → Diagnostics → "Align test chapter". It runs the bundled clip through each available
transcriber and the aligner, then shows: engine used, processing seconds per audio minute, % of starts within 0.5 s
of `expected-starts.json`, and a play button that highlights the text live. The owner runs it on the iPhone SE.

**Acceptance criteria:**
- [x] The screen shows all four numbers for each available engine, and never hangs (cancel button, timeout)
      — `AlignTestModel` tests: perfect engine GO, failing engine doesn't stop the next, drift scored, cancel, timeout
- [x] Live playback highlights the current sentence from the computed `AlignmentMap` (best engine's map)
- [ ] Results are recorded in `tasks/spike-log.md` — waiting for the owner's run

**Verification:** (2026-11-18, CI run 44234656826 at a8678af: 103 package tests, UI tests, archive all green)
- [x] UI smoke on CI: the Diagnostics screen opens in the simulator (`DiagnosticsSmokeTests`)
- [x] `Earmark-a8678af.ipa` bundles the Fixtures folder and the speech-permission text
- [ ] Manual check (owner): the run on the phone, numbers copied into the log

**Follow-up:** the heading "Chapter III." normalises to "chapter iii" while narrators say "chapter three"; the
unmatched "three" can pull the next sentence's start ~0.4 s early. Add Roman-numeral headings to TextNormalizer.

**Dependencies:** Tasks 6, 7

**Files likely touched:** `ios/Earmark/Diagnostics/AlignTestView.swift`, `AppFeatures/AlignTestModel.swift`,
`Tests/AppFeaturesTests/AlignTestModelTests.swift`, `tasks/spike-log.md`

**Estimated scope:** Medium

### Checkpoint B — GO / NO-GO
- [ ] ≥90% of sentence starts within 0.5 s on the fixture (best engine)
- [ ] ≤30 s of processing per minute of audio, phone not hot
- [ ] Decision written in `tasks/spike-log.md`; NO-GO → choose the Mac fallback or chapter-level follow mode with the owner

## Later phases (detailed after each module spec is approved)
- [ ] Phase 2: `SPEC-abs-client.md`, `SPEC-ebook-source.md`, `SPEC-library.md` → build (parallel sessions possible)
- [ ] Phase 3: `SPEC-app-shell.md`, `SPEC-player.md` → first real build (checkpoint D)
- [ ] Phase 4: `SPEC-epub-reader.md`
- [ ] Phase 5: `SPEC-read-along.md` (checkpoint E)
- [ ] Phase 6: `SPEC-recap.md`
- [ ] Phase 7: `SPEC-downloads.md` (checkpoint F)
