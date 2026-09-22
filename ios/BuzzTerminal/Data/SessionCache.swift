import Foundation

/// The last role this device signed in with, remembered per account.
///
/// **Not a security decision, and it must never become one.** Authority lives in
/// the `role` custom claim that `firestore.rules` reads off the token; this is
/// only which screens to draw. A device that lied to itself here would get a
/// reception home screen and a `PERMISSION_DENIED` on the first write.
///
/// It exists for one case, and it is a case a festival actually produces: the app
/// is launched with no network and a token older than an hour. Firebase cannot
/// refresh an expired token offline, so the claim is unreadable — and without
/// this the terminal would drop to a sign-in screen that cannot authenticate
/// offline either. Staff would be locked out of a till by a dead access point.
/// `@unchecked Sendable` because `UserDefaults` is not marked `Sendable` and is
/// in fact thread-safe — Apple documents it as safe to use from any thread. The
/// alternative, an actor, would make three trivial reads `await`-ing across a
/// hop for no benefit.
struct SessionCache: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "sb.session.roleByUid"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func role(for uid: String) -> StaffRole? {
        guard let stored = defaults.dictionary(forKey: Self.key) as? [String: String],
              let raw = stored[uid]
        else { return nil }
        return StaffRole(claim: raw)
    }

    func remember(_ role: StaffRole, for uid: String) {
        var stored = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        // `rawValue`, which `StaffRole(claim:)` reads back — an organiser's
        // `admin` claim has already collapsed to `.reception` by the time it
        // reaches here, which is what the rules grant them anyway.
        stored[uid] = role.rawValue
        defaults.set(stored, forKey: Self.key)
    }

    /// Forget one account. Called on sign-out, so "log out" means logged out —
    /// including on the next launch with no network.
    func forget(uid: String) {
        guard var stored = defaults.dictionary(forKey: Self.key) as? [String: String] else { return }
        stored[uid] = nil
        defaults.set(stored, forKey: Self.key)
    }
}
