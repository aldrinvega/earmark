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
