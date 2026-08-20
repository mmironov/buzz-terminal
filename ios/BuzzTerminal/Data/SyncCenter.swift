import Foundation
import OSLog
import SwiftUI

/// The app's view of what has been queued, acknowledged and refused.
///
/// `@MainActor` because the UI reads it every frame, which also makes it `Sendable`
/// and so safe to hand to the repository actor.
///
/// Failures are persisted, and that is the whole point of this type existing rather
/// than a couple of properties on `AppModel`. A refused charge is money that went
/// missing; it has to survive the app being force-quit, the phone dying, and the
/// shift changing.
@MainActor
@Observable
final class SyncCenter {

    private static let log = Logger(subsystem: "fest.swingbuzz.BuzzTerminal", category: "sync")
    private static let storageKey = "fest.swingbuzz.failedWrites"

    private(set) var state = SyncState()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFailures()
    }

    // MARK: - Queue

    func enqueued() {
        state.enqueued()
    }

    func acknowledged() {
        state.acknowledged()
    }

    func failed(_ write: FailedWrite) {
        state.failed(write)
        saveFailures()
        // Logged as well as stored: if the phone is later unavailable, a sysdiagnose
        // still carries the record.
        Self.log.error("""
            write refused: \(write.kind.rawValue, privacy: .public) \
            \(write.amount.description, privacy: .public) \
            participant \(write.participantId, privacy: .public) \
            tx \(write.transactionId, privacy: .public) — \
            \(write.reason, privacy: .public)
            """)
    }

    func settle(_ id: UUID) {
        state.settle(id)
        saveFailures()
    }

    func setOffline(_ offline: Bool) {
        guard state.isOffline != offline else { return }
        state.isOffline = offline
        Self.log.notice("connectivity: \(offline ? "offline" : "online", privacy: .public)")
    }

    #if DEBUG
    /// Put the banner into a given state, for screenshots and previews. Does not
    /// touch the persisted failure list — a fake banner must never be mistaken for
    /// a record of real missing money.
    func simulate(offline: Bool, pending: Int = 0) {
        state.isOffline = offline
        for _ in 0..<pending { state.enqueued() }
    }
    #endif

    // MARK: - Persistence

    private func loadFailures() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([FailedWrite].self, from: data)
            state.replaceFailures(decoded)
            let unsettled = decoded.filter { !$0.settled }.count
            if unsettled > 0 {
                Self.log.error("\(unsettled, privacy: .public) unsettled failed write(s) carried over from a previous run")
            }
        } catch {
            // Deliberately not cleared: a decode failure means something is wrong
            // with the format, and throwing away the only record of missing money
            // to tidy up would be the worst possible response.
            Self.log.error("could not decode failed writes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveFailures() {
        do {
            defaults.set(try JSONEncoder().encode(state.failures), forKey: Self.storageKey)
        } catch {
            Self.log.error("could not persist failed writes: \(error.localizedDescription, privacy: .public)")
        }
    }
}
