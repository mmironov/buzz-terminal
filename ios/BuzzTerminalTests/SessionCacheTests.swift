import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  Staying signed in.
//
//  The cache exists for one case: a cold launch, no network, and a token too
//  old to read. Without it the terminal falls back to a sign-in screen that
//  cannot sign anybody in offline either — a till locked by a dead access point.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Session cache")
struct SessionCacheTests {

    /// Its own defaults domain per test, so these never touch the simulator's
    /// real preferences or each other.
    private func cache(_ name: String = UUID().uuidString) -> (SessionCache, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        return (SessionCache(defaults: defaults), defaults)
    }

    @Test("Nothing is remembered until a sign-in succeeds")
    func startsEmpty() {
        let (store, _) = cache()
        #expect(store.role(for: "uid-1") == nil)
    }

    @Test("A role survives, per account")
    func remembersPerAccount() {
        let (store, _) = cache()
        store.remember(.reception, for: "uid-1")
        store.remember(.bar, for: "uid-2")
        #expect(store.role(for: "uid-1") == .reception)
        #expect(store.role(for: "uid-2") == .bar)
        // A phone that has never been signed in as this account knows nothing
        // about it, rather than inheriting whatever the last one was.
        #expect(store.role(for: "uid-3") == nil)
    }

    @Test("THE ONE THAT MATTERS: signing out forgets, so it stays signed out")
    func signOutForgets() {
        // Otherwise the next launch with no network would restore the session
        // somebody deliberately ended — the one case where surviving is wrong.
        let (store, _) = cache()
        store.remember(.bar, for: "uid-1")
        store.forget(uid: "uid-1")
        #expect(store.role(for: "uid-1") == nil)
    }

    @Test("Forgetting one account leaves the others alone")
    func forgetIsNarrow() {
        let (store, _) = cache()
        store.remember(.reception, for: "uid-1")
        store.remember(.bar, for: "uid-2")
        store.forget(uid: "uid-1")
        #expect(store.role(for: "uid-2") == .bar)
    }

    @Test("A role written by an older build, or by hand, is read or ignored safely")
    func toleratesJunk() {
        let (store, defaults) = cache()
        defaults.set(["uid-1": "admin", "uid-2": "sysadmin", "uid-3": ""], forKey: "sb.session.roleByUid")
        // `admin` is what an organiser's claim says, and it means reception at a
        // terminal — the same mapping `StaffRole(claim:)` applies everywhere else.
        #expect(store.role(for: "uid-1") == .reception)
        // Anything unrecognised is nobody. Guessing here would be guessing at
        // what somebody may do with money.
        #expect(store.role(for: "uid-2") == nil)
        #expect(store.role(for: "uid-3") == nil)
    }

    @Test("A re-sign-in as a different role overwrites the old one")
    func rolesAreNotStacked() {
        let (store, _) = cache()
        store.remember(.reception, for: "uid-1")
        store.remember(.bar, for: "uid-1")
        #expect(store.role(for: "uid-1") == .bar)
    }
}
