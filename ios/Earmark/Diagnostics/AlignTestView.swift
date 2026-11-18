import AppFeatures
import SwiftUI

/// Diagnostics → "Align test chapter" (Task 8): runs the spike on this iPhone and shows the GO / NO-GO numbers.
struct AlignTestView: View {
    @State private var model = DiagnosticsBundle.makeModel()
    @State private var player = ClipPlayer(url: DiagnosticsBundle.clipURL)
    @State private var copied = false

    var body: some View {
        List {
            if let setupError = model.setupError {
                Section {
                    Label(setupError, systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("align-setup-error")
                }
            } else {
                Section {
                    if model.isRunning {
                        Button("Cancel", role: .cancel) { model.cancel() }
                            .accessibilityIdentifier("align-cancel")
                    } else {
                        Button("Run on this iPhone") { model.start() }
                            .accessibilityIdentifier("align-run")
                    }
                } footer: {
                    Text("Transcribes 3 minutes of Pride and Prejudice, chapter 3, with each on-device engine, then "
                         + "checks \(model.sentences.isEmpty ? "the" : "\(model.sentences.count)") sentences against "
                         + "the reference starts. The first run may download Apple's speech model.")
                }
            }

            ForEach(model.runs) { run in
                Section(run.id) {
                    EngineRunRows(run: run)
                }
            }

            if let verdict = model.overallVerdict {
                Section("Result") {
                    Text(verdict.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(verdict == .go ? .green : .orange)
                        .accessibilityIdentifier("align-verdict")
                }
            }

            if model.runs.contains(where: { $0.state != .waiting && $0.state != .running }) {
                Section {
                    Button(copied ? "Copied" : "Copy full report") {
                        UIPasteboard.general.string = model.report()
                        copied = true
                    }
                    .accessibilityIdentifier("align-copy-report")
                } footer: {
                    Text("Every number, every reference start and every word each engine heard, with times. Paste it "
                         + "into the chat with Claude.")
                }
            }

            Section("Live highlight") {
                PlaybackRows(model: model, player: player)
            }
        }
        .navigationTitle("Align test chapter")
        .onDisappear {
            model.cancel()
            player.stop()
        }
    }
}

private struct EngineRunRows: View {
    let run: EngineRun

    var body: some View {
        switch run.state {
        case .waiting:
            Text("Waiting").foregroundStyle(.secondary)
        case .running:
            HStack {
                ProgressView()
                Text("Transcribing and aligning…")
            }
        case .cancelled:
            Text("Cancelled").foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon").foregroundStyle(.red)
        case .finished:
            LabeledContent("Words heard", value: "\(run.words ?? 0)")
            if let from = run.heardFrom, let until = run.heardUntil {
                LabeledContent("Heard from … to", value: String(format: "%.1f s … %.1f s", from, until))
            }
            if let preview = run.preview, !preview.isEmpty {
                Text("“\(preview) …”")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Seconds per audio minute",
                           value: String(format: "%.1f s", run.secondsPerAudioMinute ?? 0))
            if let score = run.score {
                LabeledContent("Starts within 0.5 s",
                               value: String(format: "%d of %d (%.0f%%)", score.withinTolerance, score.checked,
                                             score.fraction * 100))
                if let worst = score.worstError {
                    LabeledContent("Worst error", value: String(format: "%.2f s", worst))
                }
                ForEach(score.details, id: \.id) { check in
                    HStack {
                        Text(check.id.description).font(.caption.monospaced())
                        Spacer()
                        Text(String(format: "%.2f → ", check.expected)
                             + (check.measured.map { String(format: "%.2f", $0) } ?? "unaligned"))
                            .font(.caption.monospacedDigit())
                        Image(systemName: check.isWithinTolerance ? "checkmark" : "xmark")
                            .foregroundStyle(check.isWithinTolerance ? .green : .orange)
                            .accessibilityLabel(check.isWithinTolerance ? "within 0.5 seconds" : "missed")
                    }
                }
            }
            if let verdict = run.verdict {
                switch verdict {
                case .go:
                    Label("GO", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                case .noGo(let reasons):
                    Label("NO-GO: " + reasons.joined(separator: "; "), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct PlaybackRows: View {
    let model: AlignTestModel
    let player: ClipPlayer

    var body: some View {
        if let error = player.error {
            Label(error, systemImage: "speaker.slash")
        } else {
            HStack(spacing: 24) {
                Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
                    .accessibilityLabel("Back 15 seconds")
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.skip(15) } label: { Image(systemName: "goforward.15") }
                    .accessibilityLabel("Forward 15 seconds")
            }
            .buttonStyle(.borderless)
            .font(.title2)
            .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let time = player.currentTime
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "%.1f s", time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let sentence = model.sentence(at: time) {
                        Text(sentence.text)
                            .padding(10)
                            .background(Color.accentColor.opacity(0.18), in: .rect(cornerRadius: 10))
                        Text(sentence.id.description)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.runs.contains { $0.state == .finished }
                             ? "No sentence at this point (preamble or a gap)."
                             : "Run the test first to see the highlight follow the narration.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
