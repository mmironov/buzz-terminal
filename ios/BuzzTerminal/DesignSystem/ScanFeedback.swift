import AVFoundation
import OSLog
import UIKit

/// Sound and haptics for a scan.
///
/// Built rather than borrowed. `AudioServicesPlaySystemSound` needs undocumented
/// numeric ids whose meaning drifts between iOS releases, and — worse for a till —
/// some of them honour the silent switch while others do not. A staff phone will be
/// on silent, so "sometimes audible" is not a behaviour worth shipping.
///
/// Two tones, chosen to be told apart across a noisy room rather than to be
/// pleasant: a rising pair for a good read, a low double buzz for one that needs
/// attention. Neither is a beep in the middle of the register where a bar's music
/// lives.
@MainActor
final class ScanFeedback {

    static let shared = ScanFeedback()

    private static let log = Logger(subsystem: "fest.swingbuzz.BuzzTerminal", category: "feedback")

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private lazy var successTone = Self.render(
        format: format,
        // A rising minor third: unambiguous as "done", and short enough that a fast
        // hand does not outrun it.
        notes: [Tone(frequency: 880, duration: 0.065), Tone(frequency: 1_318.5, duration: 0.085)]
    )

    private lazy var blockedTone = Self.render(
        format: format,
        // Falling, where success rises. Shape carries further than pitch across a
        // room, so the two are told apart before either is consciously heard —
        // which matters at a bar, where the answer is needed before the operator
        // can look up.
        //
        // Distinct from `problemTone` because the two mean different things to the
        // person holding the bracelet. Blocked is a decision an organiser made and
        // only an organiser can undo; a bad read is worth trying again.
        notes: [
            Tone(frequency: 1_046.5, duration: 0.08),
            Tone(frequency: 659.25, duration: 0.075),
            Tone(frequency: 415.3, duration: 0.16),
        ]
    )

    private lazy var problemTone = Self.render(
        format: format,
        // Low, and repeated. Longer than the success tone on purpose: the one sound
        // an operator must not miss should occupy more time than the one they will
        // hear hundreds of times.
        notes: [
            Tone(frequency: 196, duration: 0.13),
            Tone(frequency: 0, duration: 0.05),
            Tone(frequency: 165, duration: 0.2),
        ]
    )

    private var started = false

    private init() {}

    /// A chip that read cleanly and had not been seen before.
    func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        play(successTone)
    }

    /// A bracelet an organiser has frozen.
    ///
    /// Its own sound because it is its own situation: nothing is broken, the read
    /// worked, and no amount of retrying will change the answer. Somebody has to
    /// fetch an organiser. `.warning` rather than `.error` for the same reason.
    func blocked() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        play(blockedTone)
    }

    /// A duplicate, a chip nobody is paired to, not enough money, or a read that
    /// failed. One signal for all of them: the operator has to stop and look at the
    /// screen, and which of the four it is cannot be usefully conveyed by a tone.
    func problem() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        play(problemTone)
    }

    // MARK: - Engine

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        do {
            try startIfNeeded()
            // `.interrupts` rather than queueing: a fast operator scanning three
            // bracelets a second should hear the newest read, not a backlog of
            // tones describing bracelets already in the other pile.
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        } catch {
            // Audio is a courtesy here, not the feature. A phone that refuses to
            // play — a call in progress, a route change mid-scan — must not stop
            // the audit.
            Self.log.error("scan feedback unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startIfNeeded() throws {
        guard !started else { return }

        // `.playback` ignores the ring/silent switch, which is the point: a staff
        // phone lives on silent. `.mixWithOthers` keeps somebody else's music
        // playing — a till that silences the bar every time it reads a bracelet
        // would be turned off within the hour.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        started = true
    }

    // MARK: - Tone rendering

    private struct Tone {
        /// 0 means silence, for the gap inside a double buzz.
        let frequency: Double
        let duration: Double
    }

    /// Render notes into one buffer, with a short ramp on each edge.
    ///
    /// The ramp is not polish: a sine wave cut off mid-cycle produces an audible
    /// click, and a click on every scan is exactly the kind of small ugliness that
    /// makes staff stop using a tool.
    private static func render(format: AVAudioFormat, notes: [Tone]) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = notes.reduce(0.0) { $0 + $1.duration }
        let frames = AVAudioFrameCount(total * rate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames

        var index = 0
        for note in notes {
            let count = Int(note.duration * rate)
            let ramp = min(Int(0.006 * rate), count / 2)
            for offset in 0..<count where index < Int(frames) {
                var value = 0.0
                if note.frequency > 0 {
                    let phase = 2 * Double.pi * note.frequency * Double(offset) / rate
                    value = sin(phase) * 0.28
                    if offset < ramp {
                        value *= Double(offset) / Double(ramp)
                    } else if offset > count - ramp {
                        value *= Double(count - offset) / Double(ramp)
                    }
                }
                samples[index] = Float(value)
                index += 1
            }
        }
        return buffer
    }
}
