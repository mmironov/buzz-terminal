import Foundation

/// Iteration-1 backend: the prototype's fixture data, held in memory.
///
/// An `actor` rather than a class, which gives two things for free:
///   • its mutable state is safe to touch from anywhere without locks, and
///   • callers *must* `await`, so the call sites already look exactly like the
///     Firebase ones will.
///
/// The artificial `latency` makes the UI's loading states real enough to notice
/// during development. Set it to zero in tests.
actor InMemoryTerminalRepository: TerminalRepository {

    private var participants: [BraceletID: Participant]
    private var waiting: [WaitingGuest]
    private let menu: [Drink]
    private let latency: Duration

    init(
        participants: [BraceletID: Participant] = SampleData.participants,
        waiting: [WaitingGuest] = SampleData.waitingGuests,
        menu: [Drink] = SampleData.drinks,
        latency: Duration = .milliseconds(180)
    ) {
        self.participants = participants
        self.waiting = waiting
        self.menu = menu
        self.latency = latency
    }

    private func simulateNetwork() async {
        guard latency > .zero else { return }
        try? await Task.sleep(for: latency)
    }

    // MARK: Auth

    /// Mirrors the prototype: any address starting `reception` or `bar` is
    /// accepted and the password is ignored. Real credential checking is
    /// iteration 2's job — see `README.md`.
    func signIn(email: String, password: String) async throws -> StaffRole {
        await simulateNetwork()
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if address.hasPrefix("reception") { return .reception }
        if address.hasPrefix("bar") { return .bar }
        throw TerminalError.unknownAccount
    }

    func signOut() async {
        await simulateNetwork()
    }

    // MARK: Catalogue

    func drinks() async throws -> [Drink] {
        await simulateNetwork()
        return menu
    }

    func waitingGuests() async throws -> [WaitingGuest] {
        await simulateNetwork()
        return waiting
    }

    // MARK: Bracelets

    func participant(withBracelet bracelet: BraceletID) async throws -> Participant? {
        await simulateNetwork()
        return participants[bracelet]
    }

    func assignBracelet(_ bracelet: BraceletID, to guest: WaitingGuest) async throws -> Participant {
        await simulateNetwork()
        let participant = Participant(
            id: bracelet,
            name: guest.name,
            pass: guest.pass,
            balance: .zero,
            checkedInAt: "now"
        )
        participants[bracelet] = participant
        waiting.removeAll { $0.id == guest.id }
        return participant
    }

    func topUp(bracelet: BraceletID, amount: Money) async throws -> Participant {
        await simulateNetwork()
        guard var participant = participants[bracelet] else { throw TerminalError.braceletNotAssigned }
        guard !participant.isBlocked else { throw TerminalError.braceletBlocked }
        participant.balance += amount
        participants[bracelet] = participant
        return participant
    }

    func charge(bracelet: BraceletID, lines: [CartLine]) async throws -> Participant {
        await simulateNetwork()
        guard var participant = participants[bracelet] else { throw TerminalError.braceletNotAssigned }
        guard !participant.isBlocked else { throw TerminalError.braceletBlocked }
        let total = lines.reduce(Money.zero) { $0 + $1.total }
        // Re-check server side. The client already ran `PaymentDecision`, but a
        // second terminal may have spent the money in between.
        guard participant.balance >= total else {
            throw TerminalError.insufficientFunds(balance: participant.balance, required: total)
        }
        participant.balance -= total
        participants[bracelet] = participant
        return participant
    }
}
