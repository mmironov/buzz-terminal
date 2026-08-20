#if DEBUG && canImport(CoreNFC)
import CoreNFC
import Foundation
import OSLog

// ═══════════════════════════════════════════════════════════════════════════
//  Reads chip after chip from one session, for auditing a box of wristbands.
//
//  Different shape from `BraceletReader` on purpose. That protocol reads one
//  bracelet and returns it, which is what every operator flow wants. This yields
//  a stream, because a session per bracelet would put Apple's scan sheet up 200
//  times for a box of 200.
//
//  Two session facts drive the design:
//    * `restartPolling()` keeps the same session — and the same sheet — alive for
//      the next tag, so an operator can work through a pile without tapping.
//    * a session dies after about 60 seconds regardless, so this starts a fresh
//      one automatically rather than making that the operator's problem.
// ═══════════════════════════════════════════════════════════════════════════

final class NFCBatchAuditor: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {

    private static let log = Logger(subsystem: "fest.swingbuzz.BuzzTerminal", category: "nfc.audit")

    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    private let lock = NSLock()
    private var continuation: AsyncStream<BraceletID>.Continuation?
    private var session: NFCTagReaderSession?
    /// Set when the operator stops, so an expiring session is not replaced.
    private var stopped = false

    /// Every chip read, until `stop()` or the operator closes the sheet.
    func chips() -> AsyncStream<BraceletID> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            stopped = false
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
            beginSession()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let session = self.session
        self.session = nil
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        session?.invalidate()
        continuation?.finish()
    }

    private func beginSession() {
        guard let session = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: self,
            queue: DispatchQueue(label: "fest.swingbuzz.nfc.audit")
        ) else {
            stop()
            return
        }
        lock.lock()
        self.session = session
        lock.unlock()
        session.alertMessage = "Hold each bracelet to the top of the phone."
        session.begin()
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        defer {
            // Straight back to polling, so the sheet stays up for the next chip.
            session.restartPolling()
        }
        guard let tag = tags.first,
              let identifier = tag.braceletIdentifier,
              let bracelet = BraceletID(nfcIdentifier: identifier)
        else { return }

        // No `connect` here, unlike the pairing reader. This is a census, not a
        // transaction: the UID arrives with detection, and a chip whose handshake
        // would fail still counts as a chip that exists in the box. Connecting
        // would also slow the pass down for no gain.
        Self.log.debug("audit read \(bracelet.rawValue, privacy: .public)")
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(bracelet)
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code

        lock.lock()
        let stopped = self.stopped
        lock.unlock()
        guard !stopped else { return }

        switch code {
        case .readerSessionInvalidationErrorSessionTimeout:
            // The 60-second ceiling, reached while there are still bracelets in the
            // box. Start another session rather than ending the audit — an operator
            // working through a pile should not have to notice this.
            Self.log.debug("session timed out; starting another")
            beginSession()
        case .readerSessionInvalidationErrorUserCanceled:
            stop()
        default:
            Self.log.error("audit session ended: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }
}
#endif
