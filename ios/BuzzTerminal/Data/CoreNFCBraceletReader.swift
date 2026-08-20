#if canImport(CoreNFC)
import CoreNFC
import Foundation
import OSLog

// ═══════════════════════════════════════════════════════════════════════════
//  The real bracelet reader.
//
//  Core NFC exists only on a physical iPhone 7 or later, and only with the
//  `com.apple.developer.nfc.readersession.formats` entitlement. Everything here
//  is behind `NFCTagReaderSession.readingAvailable`, so a Simulator build still
//  compiles and still runs — it just falls back to `SimulatedBraceletReader`.
//
//  One thing worth knowing before reading further: **iOS draws its own scan
//  sheet.** Starting a tag session presents a system modal saying "Ready to
//  Scan", and it cannot be suppressed or restyled. So the app's own Modernist
//  scan overlay is what the operator sees *before* the session begins, and the
//  system sheet covers it during the read. `alertMessage` is the only copy we
//  control there, which is why it carries the instruction.
// ═══════════════════════════════════════════════════════════════════════════

struct CoreNFCBraceletReader: BraceletReader {

    /// False on a Simulator, on an iPhone 6 or earlier, and if the entitlement is
    /// missing — in which case the app must not offer a scan it cannot perform.
    var isHardwareBacked: Bool { NFCTagReaderSession.readingAvailable }

    /// Empty: a real reader has nothing to fake.
    var simulatedOptions: [SimulatedBracelet] { [] }

    /// What the system sheet says while it waits for a chip.
    var prompt: String = "Hold the bracelet to the top of the phone."

    func read(selection: BraceletID?) async throws -> BraceletID {
        // `selection` is the fixture the operator tapped in the prototype panel.
        // A hardware reader ignores it by contract: the chip decides, not the UI.
        guard isHardwareBacked else { throw BraceletReadError.unsupportedDevice }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let scan = NFCScan(continuation: continuation, prompt: prompt)
                scan.begin()
            }
        } onCancel: {
            // Cancelling the Task (operator taps the app's own Cancel) cannot
            // reach into the session from here — `NFCScan` invalidates itself when
            // the system sheet closes, and the continuation resumes with
            // CancellationError either way. Kept explicit so the cancellation path
            // is visible rather than implied.
        }
    }
}

enum BraceletReadError: Error, LocalizedError, Equatable {
    case unsupportedDevice
    case unreadableTag
    case sessionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            "This device cannot read bracelets."
        case .unreadableTag:
            // A chip type Core NFC surfaces without a UID, or a tag that moved
            // before the handshake finished.
            "That chip could not be read. Try again, holding it still."
        case .sessionFailed(let detail):
            detail
        }
    }
}

// MARK: - Session lifecycle

/// One scan, start to finish.
///
/// A class rather than a struct because `NFCTagReaderSessionDelegate` is an
/// Objective-C protocol, and because the continuation must be resumed exactly
/// once from whichever delegate callback arrives first.
///
/// `@unchecked Sendable` is the honest label here rather than a shrug. The
/// delegate callbacks all arrive on the one serial queue this object creates, and
/// the single piece of mutable state — the continuation — is guarded by a lock
/// that also enforces the resume-once rule. An actor cannot be used: the delegate
/// conformance is synchronous and non-isolated.
private final class NFCScan: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {

    private static let log = Logger(subsystem: "fest.swingbuzz.BuzzTerminal", category: "nfc")

    private let lock = NSLock()
    private var continuation: CheckedContinuation<BraceletID, Error>?
    private var session: NFCTagReaderSession?
    /// The session holds its delegate weakly, so without this the scan would be
    /// deallocated the moment `read` returns to the continuation and no callback
    /// would ever arrive. Cleared on resume, which breaks the cycle.
    private var selfRetain: NFCScan?
    private let prompt: String

    init(continuation: CheckedContinuation<BraceletID, Error>, prompt: String) {
        self.continuation = continuation
        self.prompt = prompt
        super.init()
    }

    func begin() {
        // .iso14443 covers NTAG21x and MIFARE, which is what wristbands and
        // contactless cards are. Polling for formats we cannot use would let the
        // sheet claim a tag and then fail on it.
        guard let session = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: self,
            queue: DispatchQueue(label: "fest.swingbuzz.nfc")
        ) else {
            finish(.failure(BraceletReadError.sessionFailed("Could not start the NFC reader.")))
            return
        }
        self.session = session
        self.selfRetain = self
        session.alertMessage = prompt
        session.begin()
    }

    /// Resume the continuation, exactly once, and let go of everything.
    private func finish(_ result: Result<BraceletID, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()

        guard let pending else { return }   // a second callback after the first
        selfRetain = nil
        pending.resume(with: result)
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        Self.log.debug("NFC session active")
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.restartPolling()
            return
        }

        // Connecting confirms the tag is really there and still in range. The UID
        // is available on detection, but a tag that has already moved away will
        // fail here — better than pairing a bracelet from a read that half
        // happened.
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }

            if let error {
                Self.log.error("connect failed: \(error.localizedDescription, privacy: .public)")
                session.invalidate(errorMessage: "Could not read that chip.")
                self.finish(.failure(BraceletReadError.unreadableTag))
                return
            }

            guard let identifier = tag.braceletIdentifier else {
                session.invalidate(errorMessage: "That chip is not a bracelet.")
                self.finish(.failure(BraceletReadError.unreadableTag))
                return
            }

            guard let bracelet = BraceletID(nfcIdentifier: identifier) else {
                session.invalidate(errorMessage: "That chip has no readable id.")
                self.finish(.failure(BraceletReadError.unreadableTag))
                return
            }

            Self.log.info("read chip \(bracelet.rawValue, privacy: .public)")
            session.alertMessage = "Bracelet read."
            session.invalidate()
            
            self.finish(.success(bracelet))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Every ending arrives here, including the ones that already resolved —
        // `finish` ignores those. The two that matter are the operator closing the
        // sheet and the 60-second timeout, both of which are cancellations rather
        // than faults: nothing went wrong, the scan just did not happen.
        let code = (error as? NFCReaderError)?.code
        switch code {
        case .readerSessionInvalidationErrorUserCanceled,
             .readerSessionInvalidationErrorSessionTimeout:
            finish(.failure(CancellationError()))
        default:
            Self.log.error("session invalidated: \(error.localizedDescription, privacy: .public)")
            finish(.failure(BraceletReadError.sessionFailed(error.localizedDescription)))
        }
    }
}

// MARK: - Tag → identifier

extension NFCTag {

    /// The tag's UID, whatever kind of tag it is.
    ///
    /// No `default` case, on purpose: a tag family added by a future iOS should
    /// break this build rather than silently start returning nil, because the
    /// symptom would be bracelets that stop scanning with no error to explain it.
    /// `@unknown default` is how Swift allows that while still compiling against a
    /// newer SDK — it catches only cases that did not exist at compile time.
    ///
    /// FeliCa has no `identifier` at all; it identifies cards by IDm, a different
    /// concept. It is reachable here because polling `.iso14443` does not stop an
    /// unusual card from answering, so it returns nil rather than being ignored.
    var braceletIdentifier: Data? {
        switch self {
        case .miFare(let tag):
            // NTAG213/215/216 and MIFARE — what a festival wristband is.
            tag.identifier
        case .iso7816(let tag):
            // Contactless smart cards. Not expected, but they carry a UID and
            // there is no reason to refuse one.
            tag.identifier
        case .iso15693(let tag):
            tag.identifier
        case .feliCa:
            nil
        @unknown default:
            nil
        }
    }
}

#endif
