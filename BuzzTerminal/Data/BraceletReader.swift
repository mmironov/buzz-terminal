import Foundation

/// Reads a bracelet's NFC chip.
///
/// Split out behind a protocol for a practical reason: Core NFC does not exist
/// on the Simulator and requires a paid-team entitlement plus a physical device.
/// Keeping the reader abstract means the whole app is developable and testable
/// on a Mac, and iteration 3 adds a `CoreNFCBraceletReader` without touching a
/// single view.
protocol BraceletReader: Sendable {
    /// Whether this device can actually read a chip. Drives whether the design's
    /// prototype-only "simulate a bracelet" panel is offered.
    var isHardwareBacked: Bool { get }

    /// Bracelets the operator can pick from when there is no hardware.
    /// Empty on a real reader.
    var simulatedOptions: [SimulatedBracelet] { get }

    /// Wait for a chip and return its id.
    ///
    /// - Parameter selection: which fixture bracelet the operator tapped in the
    ///   prototype panel. A hardware reader ignores this and waits for a real
    ///   chip instead.
    /// - Throws: `CancellationError` if the operator cancels the scan sheet.
    func read(selection: BraceletID?) async throws -> BraceletID
}

/// The reader used until Core NFC lands: the operator taps one of the four
/// fixture bracelets and a short delay stands in for the chip handshake.
struct SimulatedBraceletReader: BraceletReader {
    var isHardwareBacked: Bool { false }
    var simulatedOptions: [SimulatedBracelet] { SampleData.simulatedBracelets }

    /// The handshake delay, matching the prototype's 950 ms.
    var readDuration: Duration = .milliseconds(950)

    func read(selection: BraceletID?) async throws -> BraceletID {
        guard let selection else { throw CancellationError() }
        try await Task.sleep(for: readDuration)
        return selection
    }
}
