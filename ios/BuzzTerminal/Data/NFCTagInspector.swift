#if DEBUG && canImport(CoreNFC)
import CoreNFC
import Foundation

// ═══════════════════════════════════════════════════════════════════════════
//  A diagnostic, not a feature. DEBUG-only.
//
//  Answers "what is actually on this bracelet?" — the chip's identity, its NDEF
//  contents if it has any, and its first pages of memory. Useful for two
//  questions the festival genuinely has: what did the vendor actually ship, and
//  is there anything on the tag worth reading besides its UID.
//
//  Everything here is best-effort. A tag that refuses a command gets a line
//  saying so rather than aborting the report: the point is to learn what the chip
//  supports, and a refusal is information.
// ═══════════════════════════════════════════════════════════════════════════

enum NFCTagInspector {

    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    /// Scan one tag and describe it.
    static func inspect() async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let inspection = Inspection(continuation: continuation)
            inspection.begin()
        }
    }
}

private final class Inspection: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String], Error>?
    private var selfRetain: Inspection?

    init(continuation: CheckedContinuation<[String], Error>) {
        self.continuation = continuation
        super.init()
    }

    func begin() {
        guard let session = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: self,
            queue: DispatchQueue(label: "fest.swingbuzz.nfc.inspect")
        ) else {
            finish(.failure(BraceletReadError.sessionFailed("Could not start the NFC reader.")))
            return
        }
        selfRetain = self
        session.alertMessage = "Hold the bracelet to the top of the phone."
        session.begin()
    }

    private func finish(_ result: Result<[String], Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        selfRetain = nil
        pending.resume(with: result)
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        if code == .readerSessionInvalidationErrorUserCanceled
            || code == .readerSessionInvalidationErrorSessionTimeout {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(BraceletReadError.sessionFailed(error.localizedDescription)))
        }
    }

    /// Held on `self` rather than captured by the Task below. `NFCTag` and
    /// `NFCTagReaderSession` are not `Sendable`, so a closure capturing them
    /// directly is rejected under Swift 6 — and rightly, since it would be crossing
    /// an isolation boundary. This class is `@unchecked Sendable` on the strength of
    /// everything arriving on one serial queue, which is what makes holding them
    /// here honest rather than a way around the compiler.
    private var connectedTag: NFCTag?
    private var activeSession: NFCTagReaderSession?

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { session.restartPolling(); return }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                session.invalidate(errorMessage: "Could not connect.")
                self.finish(.failure(BraceletReadError.sessionFailed(error.localizedDescription)))
                return
            }
            self.connectedTag = tag
            self.activeSession = session
            Task { await self.runInspection() }
        }
    }

    private func runInspection() async {
        guard let tag = connectedTag, let session = activeSession else { return }
        let report = await describe(tag)
        session.alertMessage = "Read."
        session.invalidate()
        connectedTag = nil
        activeSession = nil
        finish(.success(report))
    }

    // MARK: - The report

    private func describe(_ tag: NFCTag) async -> [String] {
        var lines: [String] = []

        // ── Identity ───────────────────────────────────────────────────────
        if let uid = tag.braceletIdentifier {
            lines.append("UID          \(uid.hexColons)")
            lines.append("UID length   \(uid.count) bytes")
            // The first byte is the manufacturer id from ISO/IEC 7816-6. 0x04 is
            // NXP, who make the NTAG and MIFARE families; anything else means the
            // chip is not what a spec sheet quoting "NTAG213" would imply.
            if let first = uid.first {
                lines.append("Manufacturer 0x\(byte: first) \(first == 0x04 ? "(NXP)" : "(not NXP)")")
            }
        } else {
            lines.append("UID          none reported")
        }

        guard case .miFare(let mifare) = tag else {
            lines.append("")
            lines.append("Not an ISO14443-3 MIFARE tag, so no further detail.")
            return lines
        }

        lines.append("Family       \(mifare.mifareFamily.label)")
        // Optional, and empty on most tags: historical bytes come from the ATS,
        // which an Ultralight-class chip does not return.
        if let historical = mifare.historicalBytes, !historical.isEmpty {
            lines.append("Historical   \(historical.hexColons)")
        }

        // ── GET_VERSION ────────────────────────────────────────────────────
        // 0x60 on an NTAG21x returns 8 bytes naming the exact product and its
        // storage size. A clone often refuses it, or answers with something that
        // does not decode — which is itself the answer to "what did we buy?".
        lines.append("")
        switch await send(mifare, [0x60]) {
        case .success(let data) where data.count >= 8:
            lines.append("GET_VERSION  \(data.hexColons)")
            lines.append("  vendor     0x\(byte: data[1]) \(data[1] == 0x04 ? "(NXP)" : "(not NXP)")")
            lines.append("  product    type 0x\(byte: data[2]) subtype 0x\(byte: data[3])")
            lines.append("  version    \(data[4]).\(data[5])")
            lines.append("  storage    \(storageDescription(data[6]))")
        case .success(let data):
            lines.append("GET_VERSION  short answer: \(data.hexColons)")
        case .failure(let error):
            lines.append("GET_VERSION  refused — \(error.localizedDescription)")
            lines.append("  A tag that will not answer 0x60 is usually not a genuine NTAG21x.")
        }

        // ── NDEF ───────────────────────────────────────────────────────────
        // A MIFARE tag is also an NFCNDEFTag, so this needs no second session.
        lines.append("")
        let status = await queryNDEF(mifare)
        lines.append("NDEF         \(status.description)")
        if status.readable {
            lines.append(contentsOf: await readNDEF(mifare))
        }

        // ── Raw memory ─────────────────────────────────────────────────────
        // READ (0x30) returns 16 bytes — four pages — from the page given. Page 0
        // is the UID and lock bytes, page 3 is the capability container, and user
        // memory starts at page 4. Anything the vendor programmed will be here.
        lines.append("")
        for page in [UInt8(0x00), 0x04, 0x08] {
            switch await send(mifare, [0x30, page]) {
            case .success(let data):
                lines.append("Pages \(String(format: "%02d", page))–\(String(format: "%02d", page + 3))  \(data.hexColons)")
                lines.append("            as text  \(data.printable)")
            case .failure(let error):
                lines.append("Pages \(String(format: "%02d", page))–\(String(format: "%02d", page + 3))  refused — \(error.localizedDescription)")
            }
        }

        return lines
    }

    private func storageDescription(_ byte: UInt8) -> String {
        // NTAG21x encodes user memory in the storage-size byte.
        switch byte {
        case 0x0F: "NTAG213 — 144 bytes of user memory"
        case 0x11: "NTAG215 — 504 bytes"
        case 0x13: "NTAG216 — 888 bytes"
        default: "0x\(String(format: "%02X", byte)) — not an NTAG21x size"
        }
    }

    // MARK: - Awaitable wrappers over the callback API

    private func send(_ tag: NFCMiFareTag, _ bytes: [UInt8]) async -> Result<Data, Error> {
        await withCheckedContinuation { continuation in
            tag.sendMiFareCommand(commandPacket: Data(bytes)) { data, error in
                continuation.resume(returning: error.map { .failure($0) } ?? .success(data))
            }
        }
    }

    private struct NDEFStatus {
        var description: String
        var readable: Bool
    }

    private func queryNDEF(_ tag: NFCNDEFTag) async -> NDEFStatus {
        await withCheckedContinuation { continuation in
            tag.queryNDEFStatus { status, capacity, error in
                if let error {
                    continuation.resume(returning: .init(
                        description: "not available — \(error.localizedDescription)",
                        readable: false
                    ))
                    return
                }
                switch status {
                case .readWrite:
                    continuation.resume(returning: .init(
                        description: "read/write, capacity \(capacity) bytes", readable: true))
                case .readOnly:
                    continuation.resume(returning: .init(
                        description: "read-only, capacity \(capacity) bytes", readable: true))
                case .notSupported:
                    continuation.resume(returning: .init(
                        description: "not supported — the tag is not NDEF-formatted", readable: false))
                @unknown default:
                    continuation.resume(returning: .init(description: "unknown status", readable: false))
                }
            }
        }
    }

    /// Returns already-formatted lines rather than the message.
    ///
    /// `NFCNDEFMessage` is not `Sendable`, so resuming a continuation with one is
    /// rejected — the records are read and rendered inside the callback, and only
    /// strings cross the boundary.
    private func readNDEF(_ tag: NFCNDEFTag) async -> [String] {
        await withCheckedContinuation { continuation in
            tag.readNDEF { message, error in
                guard let message else {
                    let reason = error?.localizedDescription ?? "no message returned"
                    continuation.resume(returning: ["  could not read — \(reason)"])
                    return
                }
                guard !message.records.isEmpty else {
                    continuation.resume(returning: ["  no records — formatted but empty"])
                    return
                }
                var lines: [String] = []
                for (index, record) in message.records.enumerated() {
                    lines.append("  record \(index + 1)")
                    lines.append("    format   \(record.typeNameFormat.label)")
                    lines.append("    type     \(record.type.printable)")
                    if !record.identifier.isEmpty {
                        lines.append("    id       \(record.identifier.printable)")
                    }
                    lines.append("    payload  \(record.payload.count) bytes")
                    lines.append("    as text  \(record.payload.printable)")
                }
                continuation.resume(returning: lines)
            }
        }
    }
}

// MARK: - Formatting

private extension Data {
    /// `04:B4:2F:11` — the same shape the app uses for a bracelet id.
    var hexColons: String {
        map { String(format: "%02X", Int($0)) }.joined(separator: ":")
    }

    /// Printable ASCII, with everything else as `.` — enough to spot a URL or a
    /// serial the vendor wrote, without pretending unknown bytes are text.
    var printable: String {
        let text = map { byte in
            (byte >= 0x20 && byte < 0x7F) ? String(UnicodeScalar(byte)) : "."
        }.joined()
        return text.isEmpty ? "(empty)" : text
    }
}

private extension String.StringInterpolation {
    mutating func appendInterpolation(byte: UInt8) {
        appendLiteral(String(format: "%02X", Int(byte)))
    }
}

private extension NFCMiFareFamily {
    var label: String {
        switch self {
        case .ultralight: "MIFARE Ultralight / NTAG21x"
        case .plus: "MIFARE Plus"
        case .desfire: "MIFARE DESFire"
        case .unknown: "unknown"
        @unknown default: "unrecognised"
        }
    }
}

private extension NFCTypeNameFormat {
    var label: String {
        switch self {
        case .empty: "empty"
        case .nfcWellKnown: "NFC well-known (text, URI, …)"
        case .media: "MIME media"
        case .absoluteURI: "absolute URI"
        case .nfcExternal: "external type"
        case .unknown: "unknown"
        case .unchanged: "unchanged (chunked)"
        @unknown default: "unrecognised"
        }
    }
}

#endif
