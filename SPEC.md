# Spec: Earmark — listen and read in sync, for iOS

> Working name "Earmark" (rename freely). Status: **APPROVED 2026-11-13** (open questions settled with the
> recommended defaults, see the end of this file).
> Design: https://claude.ai/artifact/J5xqR44DUmykXFKF2pfUsG (Library, Recap, Now Playing, Read-along, Chapters,
> Sign-in, Sources, Settings).
> Build approach copied from Glasswing (`~/Projects/glasswing`, github.com/aldrinvega/glasswing): Swift package
> tested locally with the swift.org toolchain, app built only on GitHub's `macos-26` runner, unsigned `.ipa`
> sideloaded with SideStore.

## Objective

A personal, sideloaded iOS app that plays audiobooks from the owner's **Audiobookshelf** server and shows the
matching **ebook** at the same time. The sentence being narrated is highlighted, and tapping any sentence jumps the
audio to it. After a few days away, a **"Previously on…"** card recaps where you stopped.

Everything comes from the owner's Mac over the tailnet:

| Service on the Mac | Tailnet address (already served) | Gives the app |
|---|---|---|
| Audiobookshelf 2.37.2 | `https://<mac>.ts.net:<port>` | audiobooks, covers, chapters, listening progress, bookmarks |
| Pocket Book Studio | `https://<mac>.ts.net:<port>` | EPUB list (`GET /api/books`), original EPUBs (`GET /source/<id>`), upload (`POST /api/upload`) |

**User:** one person (the owner), on an **iPhone SE (3rd generation), iOS 27** (375×667 pt, Home button), with the
Mac on the same tailnet.

**Success looks like:** sign in once → Library shows the Audiobookshelf books → open *Pride and Prejudice* →
it plays, the matching EPUB opens in Read mode with the current sentence highlighted and following the voice →
tap a later sentence and the audio jumps there → close the app, come back 4 days later → a recap card appears and
Resume continues 15 s before where you stopped. Progress also shows up in the Audiobookshelf web app.

### User stories
1. I enter my Audiobookshelf address, username and password once. The app also finds Pocket Book Studio on the same
   Mac without a second sign-in.
2. Library shows my books with cover, progress and whether an ebook is available. A "Continue" card shows the
   current book.
3. I play a book with skip back 15 s / forward 30 s, speed, sleep timer (incl. end of chapter), chapters, and
   Lock Screen / Control Center / AirPods controls. It keeps playing in the background.
4. Listening progress syncs with Audiobookshelf (both ways), so the web app and the phone agree.
5. If an ebook matches, I switch to Read: full-screen text, the narrated sentence highlighted (and the word, when
   word timings exist), auto-scroll that follows the voice, and the player shrunk to a glass pill.
6. I tap any sentence and the audio jumps there. If I scroll ahead, a "Back to narrator" chip brings me back.
7. I open a Chapters sheet that shows each chapter's length and how far I am in each.
8. When I resume after N days (default 3), a "Previously on…" card shows where I stopped, without spoilers.
9. In Sources, I see which books have an ebook. For a book without one, I add an EPUB from the phone, which
   uploads it to Pocket Book Studio.
10. With the Mac off, downloaded books still play and read, and online screens say "Mac unreachable" instead of
    spinning.

## Capability map (Phase 0 — please review first)

| Module id | Responsibility | Depends on |
|---|---|---|
| `abs-client` | Swift client for the Audiobookshelf API: login and token refresh, libraries, items, chapters, cover, play sessions, progress sync. API notes in `docs/abs-api.md` | — |
| `ebook-source` | Pocket Book Studio client: list EPUBs, download, upload, and match EPUB ↔ audiobook by title and author (with manual override) | — |
| `library` | On-device store (SwiftData): books, ebook link, local progress, recap state, downloads index, alignment cache index | — |
| `app-shell` | XcodeGen project, composition root, tab bar with mini-player accessory, sign-in flow, Settings, theme, CI `.ipa` | abs-client, ebook-source, library |
| `player` | AVPlayer playback of Audiobookshelf tracks, chapters, speed, sleep timer, background audio, Now Playing / remote commands, sync loop | abs-client, library |
| `epub-reader` | Unpack the EPUB, split it into chapters and sentences with stable IDs, render in a `WKWebView` with the book's own CSS, themes (Paper/Sepia/Night), sentence highlight and tap events | ebook-source, library |
| `read-along` | Text ↔ audio alignment: on-device speech-to-text with word timestamps, matched against the EPUB sentences; sentence/word highlight, tap-to-seek, follow / back-to-narrator; per-chapter alignment cache | player, epub-reader |
| `recap` | "Previously on…": spoiler-safe summary of where you stopped (last scene, people met so far), shown after N days away; Resume rewinds 15 s | read-along, library |
| `downloads` | Offline audio and EPUB through a background `URLSession`, storage management, Wi-Fi-only setting | player, epub-reader |

**Build order:** `abs-client` + `ebook-source` + `library` → `app-shell` → `player` (first build on the phone) →
`epub-reader` → `read-along` (starts with a feasibility spike) → `recap` → `downloads`.

Each module gets its own `SPEC-<module-id>.md` before it is built, as in Glasswing. This file is the shared
contract: stack, commands, structure, style, tests, boundaries.

## Tech Stack

| Area | Choice |
|---|---|
| App | Swift 6, SwiftUI, **iOS 26 minimum** (runs on the owner's iOS 27), iPhone only, portrait. Liquid Glass from system APIs: `TabView` + `.tabViewBottomAccessory` (mini-player), `.glassEffect()`, `GlassEffectContainer`, `.buttonStyle(.glass)` |
| Local data | SwiftData, one store, versioned schema (`SchemaV1`) |
| Audio | AVFoundation (`AVPlayer` / `AVQueuePlayer` over the play session's track URLs, auth header), `AVAudioSession(.playback, .spokenAudio)`, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, `UIBackgroundModes: audio` |
| Ebook | EPUB unpacked with **ZIPFoundation** (the only new dependency, ask first), XHTML parsed with Foundation's `XMLParser`, rendered in `WKWebView` with injected CSS/JS for highlight and tap |
| Sentence splitting | `NaturalLanguage` (`NLTokenizer(unit: .sentence)`), on device |
| Alignment | `Speech` on device (`SpeechAnalyzer`/`SpeechTranscriber` on iOS 26+, falling back to `SFSpeechRecognizer` with `requiresOnDeviceRecognition`) for word timestamps, then sequence alignment against the EPUB text. **Spike first** (Open Question 2) |
| Recap | v1 has no AI: the last passage heard before stopping + people found with `NLTagger(.nameType)` up to that point. Apple's on-device Foundation Models need Apple Intelligence, which the iPhone SE (3rd gen) doesn't have (Open Question 3) |
| Images | `AsyncImage` + on-disk `URLCache` for covers |
| Transport | HTTPS over Tailscale (the owner's existing `tailscale serve` entries), JSON; Audiobookshelf bearer token in the Keychain |
| Project generation | Committed `ios/project.yml` → **XcodeGen on CI only** (same as Glasswing; no Xcode on the Mac) |
| Distribution | Unsigned `.ipa` from CI → signed and installed with **SideStore** using the owner's Apple ID |

No backend of our own: both servers already exist. The app changes nothing on the Mac except through Pocket Book
Studio's existing upload endpoint.

## Commands

The Mac (Ryzen x86 Hackintosh) can't run current Xcode, so app builds and simulator tests run only on GitHub's
`macos-26` runner (Xcode 26.6). Local work stays in the Swift package with the swift.org toolchain.

```
# Local (this Mac, swift.org toolchain; SwiftData target skipped like in Glasswing)
ios/test-local.sh                                   # = EARMARK_NO_SWIFTDATA=1 swift test in ios/EarmarkKit
ios/test-local.sh --filter ReadAlongCoreTests       # one test target

# CI only (macos-26, Xcode 26.6) — .github/workflows/ios.yml
swift test --package-path ios/EarmarkKit            # all package tests incl. SwiftData Store
xcodegen generate --spec ios/project.yml
xcodebuild test -project ios/Earmark.xcodeproj -scheme Earmark \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)'
xcodebuild archive -project ios/Earmark.xcodeproj -scheme Earmark -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$RUNNER_TEMP/Earmark.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
# → zip Payload/Earmark.app as Earmark-<shortsha>.ipa, uploaded as a 14-day artifact

# Get a build
gh run list --workflow ios.yml --limit 5
gh run download <run-id> -n Earmark-ipa             # then open in SideStore

# Contract checks against the real servers (manual, needs the tailnet)
ios/smoke-servers.sh                                # Audiobookshelf /status + login + one item; Pocket Book Studio /api/books
```

## Project Structure

```
~/Projects/earmark/                    (public GitHub repo aldrinvega/earmark)
├── SPEC.md                            → this file (capability map = index of module specs)
├── SPEC-<module-id>.md                → one per module, written before that module is built
├── docs/
│   ├── abs-api.md                     → Audiobookshelf endpoints we use, checked against 2.37.2 (source of truth for abs-client)
│   ├── pbs-api.md                     → Pocket Book Studio endpoints we use
│   └── screenshots/                   → simulator screenshots vs the design canvas
├── tasks/                             → <module>-plan.md, <module>-todo.md, <module>-log.md (as in Glasswing)
├── .github/workflows/ios.yml          → package tests + simulator tests + unsigned .ipa
└── ios/
    ├── project.yml                    → XcodeGen spec (app, unit-test host, UI tests); .xcodeproj not committed
    ├── test-local.sh                  → local package tests (swift.org toolchain)
    ├── smoke-servers.sh               → manual live checks against the Mac
    ├── Earmark/                       → app target: SwiftUI views only
    │   ├── App/                       → EarmarkApp.swift (composition root), RootView
    │   ├── Library/ NowPlaying/ Reader/ Chapters/ Recap/ Sources/ Settings/ Setup/
    │   ├── Components/                → glass pill, chips, cover view, theme
    │   └── Reader/Web/                → reader.css, reader.js (highlight, tap → sentence id, scroll)
    ├── EarmarkUITests/                → smoke test in stub-server mode
    └── EarmarkKit/                    → Swift package
        ├── Sources/
        │   ├── Models/                → value types shared by everything (Book, Chapter, SentenceID, Progress…)
        │   ├── ABSClient/             → Audiobookshelf API client, CredentialStore (Keychain)
        │   ├── EbookSource/           → Pocket Book Studio client + EbookMatcher
        │   ├── EPUBCore/              → unzip, OPF/spine/TOC, XHTML → sentences with stable IDs
        │   ├── ReadAlongCore/         → alignment algorithm, AlignmentMap, position ↔ sentence lookup
        │   ├── PlaybackCore/          → sync policy, sleep timer, resume/rewind rules (no AVFoundation)
        │   ├── RecapCore/             → recap builder (passage + people), "days away" policy
        │   ├── Store/                 → SwiftData SchemaV1 (Xcode-only, skipped locally)
        │   ├── AppFeatures/           → @Observable view models, testable without Xcode
        │   └── EarmarkTestSupport/    → recorded server responses, a public-domain EPUB + audio clip fixtures
        └── Tests/                     → one test target per source target
```

Rule from Glasswing: anything with a branch or a user-facing string lives in a package target with a test.
SwiftUI views stay thin. AVFoundation, Speech and WebKit calls sit behind small protocols, so the logic around them
is testable with `swift test`.

## Code Style

```swift
// AppFeatures/ReaderModel.swift — logic and strings live here, tested with swift test
@Observable @MainActor
final class ReaderModel {
    private(set) var currentSentence: SentenceID?
    private(set) var isFollowingNarrator = true
    private let player: PlaybackControlling
    private let alignment: AlignmentMap

    init(player: PlaybackControlling, alignment: AlignmentMap) {
        self.player = player
        self.alignment = alignment
    }

    var showsBackToNarrator: Bool { !isFollowingNarrator }

    func playbackTimeChanged(_ time: TimeInterval) {
        currentSentence = alignment.sentence(at: time)
    }

    func userTapped(_ sentence: SentenceID) {
        guard let start = alignment.startTime(of: sentence) else { return }
        player.seek(to: start)
        isFollowingNarrator = true
    }

    func userScrolledAway() { isFollowingNarrator = false }
}

// Earmark/Reader/ReaderPill.swift — a thin view, system glass, never hand-made blur
struct ReaderPill: View {
    @Environment(PlayerModel.self) private var player
    var body: some View {
        HStack(spacing: 4) {
            CoverThumb(book: player.book).frame(width: 44, height: 44)
            PlaybackProgressLabel(model: player)
            Spacer(minLength: 0)
            SkipButton(seconds: -15)
            PlayPauseButton()
            SkipButton(seconds: 30)
        }
        .padding(.horizontal, 10)
        .frame(height: 64)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
```

Conventions (same as Glasswing): Swift API Design Guidelines, one type per file, no force-unwraps outside tests,
Swift 6 strict concurrency, `@MainActor` view models. Clients are `actor`s or `Sendable` structs. Errors are a typed
enum per client and mapped to user-facing text in `AppFeatures`. Layouts are checked at **375×667** first (the
owner's phone), then at larger sizes. The design canvas is drawn at 390×844 and is a reference, not a pixel spec.
Commit subjects start with the module id (`player: sleep timer at end of chapter`).

## Testing Strategy

| Level | What | Where / tool |
|---|---|---|
| Unit (local + CI) | API decoding from recorded responses, token refresh, EPUB ↔ book matching, EPUB parsing (spine, TOC, sentence IDs stay the same across runs), alignment algorithm on fixture transcripts, position ↔ sentence lookup, sync and resume policy, sleep timer, recap builder | `EarmarkKit/Tests`, Swift Testing |
| Store (CI) | SwiftData schema, progress conflict rules (newest wins, by server `lastUpdate`) | `StoreTests` on `macos-26` |
| Alignment quality (local + CI) | A public-domain chapter (LibriVox audio + Gutenberg text) with hand-checked sentence starts; report the share of sentences whose start is within 0.5 s | `ReadAlongCoreTests` + fixture |
| UI smoke (CI) | Launch with `-EarmarkStubServers` (stub `URLProtocol` over recorded fixtures) → sign in → Library → play → Read → tap a sentence → seek happens | `EarmarkUITests`, iPhone SE (3rd gen) simulator |
| Live smoke (manual) | `ios/smoke-servers.sh` against the Mac; on-phone checklist (background audio, Lock Screen, AirPods, Mac off) | `tasks/*-log.md` |
| Visual | Simulator screenshots of each canvas screen at 375×667, with Reduce Transparency and Dynamic Type XL | `docs/screenshots/` |

Coverage target: ≥80% on `ABSClient`, `EbookSource`, `EPUBCore`, `ReadAlongCore`, `PlaybackCore`, `RecapCore`.
UI code is covered by the smoke path instead of a percentage. Stub-server code is compiled out of Release builds.

## Boundaries

- **Always:** keep the Audiobookshelf token only in the Keychain; read the server's progress before writing it, and
  never move it backwards without the user choosing to; keep `docs/abs-api.md` and `docs/pbs-api.md` updated before
  changing a client; run `ios/test-local.sh` before every commit; respect Reduce Motion, Reduce Transparency and
  Dynamic Type; fit 375×667; keep downloaded books and the Library usable with the Mac off.
- **Ask first:** adding any dependency (ZIPFoundation is proposed here); changing anything on the Mac (Audiobookshelf
  settings, Pocket Book Studio code, any of the owner's `tailscale serve` entries); sending book text or
  audio to any outside service (e.g. a cloud AI for recaps); changing the SwiftData schema after the first install.
  **The repo is public** (owner's decision 2026-11-18, so GitHub-hosted macOS builds are free): anything committed is
  world-readable, so the "Never" list below is enforced before every push, and server recordings are scrubbed.
- **Never:** commit tokens, passwords, signing certificates or Apple ID details; put them in the `.ipa` or CI logs;
  commit audiobooks, EPUBs or anything copyrighted (test fixtures are public domain only); expose the Mac beyond the
  tailnet; touch Glasswing or `~/Projects/aniyomi-retro` (reference only); ship to the App Store.

## Success Criteria

1. Every push to `ios/**` produces a downloadable unsigned `Earmark-<sha>.ipa`, with package and simulator tests green.
2. The owner installs it with SideStore and signs in with a username and password. Library shows the Audiobookshelf
   books within 3 s on the tailnet. A wrong password and an unreachable Mac each show their own message.
3. Playback starts within 2 s of pressing Play, keeps going with the screen locked, and responds to Lock Screen and
   AirPods controls. Skip, speed, chapters and the sleep timer (incl. end of chapter) work.
4. Progress is sent to Audiobookshelf at least every 15 s, on pause and on going to the background. A position set
   in the Audiobookshelf web app shows up on the phone the next time the book opens.
5. A book with a matching EPUB in Pocket Book Studio shows "Ebook" and opens in Read mode, using the book's own fonts
   and styles, in Paper, Sepia and Night themes.
6. On the fixture chapter, ≥90% of sentence highlights start within 0.5 s of the narration. On a real book, the
   highlight stays on the spoken sentence while listening for 10 minutes (owner check).
7. Tapping a sentence seeks to it within 0.5 s. Scrolling away shows "Back to narrator", which returns to the current
   sentence.
8. After ≥3 days away (setting), opening the book shows the recap before playback. It contains nothing past the
   stop point. Resume starts 15 s earlier.
9. A downloaded book plays and reads in airplane mode. Library opens in under 1 s with the Mac off.
10. All 8 canvas screens exist in the app with system Liquid Glass and stay readable with Reduce Transparency on.

## Open Questions

**Settled 2026-11-13 ("approve as is"), using the recommendations below:** name **Earmark**; alignment **on the
iPhone**, decided for good by the `read-along` spike (Mac fallback only with approval); recap v1 **without AI**;
**ZIPFoundation** approved as the one new dependency; **automatic title + author matching** with a manual "choose
ebook" fallback; a `aldrinvega/earmark` repo — **changed 2026-11-18 to public**, because the free plan's private
macOS minutes were used up; spec location
`~/Projects/earmark`.

1. **App name** — keep "Earmark" or pick another? (It sets the bundle id `local.earmark` and the repo name.)
2. **Where alignment runs.** Recommendation: **on the iPhone**, chapter by chapter just ahead of playback, cached so
   it happens once per book. Risk: battery and heat on an iPhone SE, and speech-to-text accuracy on old-style prose.
   Fallback: run it on the Mac (e.g. whisper.cpp next to Pocket Book Studio) and fetch the result, which means
   changing Pocket Book Studio. The `read-along` spec starts with a one-chapter spike on your phone to decide.
3. **Recap without Apple Intelligence.** Your iPhone SE can't run Apple's on-device AI. v1 recap = the passage you
   last heard + the people met so far (no AI, works offline). A written summary like the one in the design would need
   an AI model: on the Mac (slow on this CPU) or a cloud API (sends book text off your machines). OK to ship v1
   without the written summary?
4. **EPUB rendering.** Recommendation: our own `WKWebView` renderer + ZIPFoundation (full control over the highlight
   and tap). Alternative: Readium Swift Toolkit (more complete EPUB support, much larger, harder to control).
   Approve ZIPFoundation?
5. **Matching EPUBs to audiobooks.** Pocket Book Studio stores originals by random ID with title and author from
   `/api/books`. Is automatic title + author matching (with a manual "choose ebook" fallback) enough, or should
   Pocket Book Studio also record the Audiobookshelf item ID when you upload?
6. **Repo** — create a private `aldrinvega/earmark` on GitHub (needed for the macOS CI runners), same as Glasswing?
7. **Spec location** — `/Volumes/Storage` is not mounted, so this spec is in `~/Projects/earmark` (where Glasswing
   also lives). OK?
