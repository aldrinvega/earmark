# Read-along spike log (Phase 1, Checkpoint B)

## Run 1 — 2026-11-18, iPhone SE (3rd gen), build `a8678af` — invalid (adapter bugs), not a verdict

Screenshots from the owner, Diagnostics → Align test chapter:

| Engine | Result |
|---|---|
| SpeechAnalyzer (on-device) | Failed: "On-device speech recognition is not available on this iPhone." |
| SFSpeechRecognizer (on-device) | 4 words heard · 2.3 s per audio minute · 0 of 8 starts within 0.5 s → NO-GO |

Screen verdict: NO-GO. **Not accepted as the spike result**, because both numbers come from bugs in the adapters:

1. **SFSpeechRecognizer stopped at the first pause.** 4 words ≈ the preamble's first phrase ("Chapter three of
   Pride…", first pause at 2.8 s). `SFSpeechURLRecognitionRequest` endpoints on a pause, and the adapter resumed on
   the first final result. So the 2.3 s/min and 0/8 measure a 3-second transcription, not alignment.
   Fix: feed the file through `SFSpeechAudioBufferRecognitionRequest` (no endpointing until `endAudio()`), collect
   the segments of every final result, and finish only after the audio has ended.
2. **SpeechAnalyzer's failure reason is ambiguous.** `.unavailableOnDevice` is thrown for three different causes
   (model unsupported for en-US on this device, model download request refused, engine unavailable).
   Fix: report the exact cause, so run 2 tells us whether the iPhone SE (A15) can use `SpeechTranscriber` at all.
   If it can't, the next candidate is iOS 26's `DictationTranscriber` (same SpeechAnalyzer pipeline, broader device
   support) — to be added only after run 2 confirms the cause.
3. Diagnostics now shows the first words each engine heard, so a cut-off like this is visible immediately.

Decision: fix and re-run (run 2) before any GO / NO-GO call.

## Run 2 — 2026-11-18, iPhone SE (3rd gen), build `d5e7634` — both engines work; verdict pending detail

| Engine | Words | Heard | s per audio min | Starts within 0.5 s | Worst error |
|---|---|---|---|---|---|
| SpeechAnalyzer (iOS 26, on-device) | 509 | 0.1–180.0 s | **1.4** | 7 of 8 (87.5%) | 4.34 s |
| SFSpeechRecognizer (on-device, buffer-fed) | 508 | 0.2–179.9 s | **2.3** | 7 of 8 (87.5%) | 1.30 s |

- Run-1 fixes confirmed: the buffer-fed legacy recognizer heard the whole clip; SpeechAnalyzer runs on the A15 with
  the model installed (no download error).
- Speed is far inside the limit (≤ 30 s per audio minute): ~20× margin. The phone was not reported as getting warm.
- Live highlight followed the narration (38.7 s → 0.1.1 "They attacked him…", consistent with the speaking rate).
- Screen verdict NO-GO only because 7/8 = 87.5% < 90%. With 8 reference points one miss decides it, and both engines
  missed exactly one. Suspect: the reference itself — `0.1.0` = 14.90 s may be the start of a spoken "Chapter Three"
  heading after the preamble, not of "NOT all that…" (SFSpeechRecognizer's worst error, 1.30 s, fits that).
- Next: Diagnostics shows expected vs measured per reference and copies a full report (all heard words with times),
  so the miss can be attributed (reference vs aligner) before the GO / NO-GO call.
