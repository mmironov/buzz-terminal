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

    /// The whole roster, keyed the way Firestore keys it.
    private var roster: [ParticipantID: Participant]
    private let menu: [Drink]
    private let latency: Duration

    init(
        roster: [Participant] = SampleData.roster,
        menu: [Drink] = SampleData.drinks,
        latency: Duration = .milliseconds(180)
    ) {
        self.roster = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
        self.menu = menu
        self.latency = latency
    }

    /// Reverse lookup, standing in for the `bracelets/{chipUid}` collection.
    private func participant(pairedTo bracelet: BraceletID) -> Participant? {
        roster.values.first { $0.braceletId == bracelet }
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

    func awaitingCheckIn() async throws -> [Participant] {
        await simulateNetwork()
        return roster.values
            .filter(\.isAwaitingCheckIn)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: Bracelets

    func participant(withBracelet bracelet: BraceletID) async throws -> Participant? {
        await simulateNetwork()
        return participant(pairedTo: bracelet)
    }

    func createEveningTicket(evening: Evening, bracelet: BraceletID) async throws -> Participant {
        await simulateNetwork()
        guard participant(pairedTo: bracelet) == nil else { throw TerminalError.braceletAlreadyPaired }

        // Firestore would collide on `create` and retry; here the dictionary is
        // the whole world, so the next free number is simply the highest plus one.
        let highest = roster.values
            .filter { $0.evening == evening }
            .compactMap(\.eveningNumber)
            .max() ?? 0

        let ticket = Participant.eveningTicket(
            evening: evening,
            number: highest + 1,
            bracelet: bracelet
        )
        guard roster[ticket.id] == nil else { throw TerminalError.eveningSequenceExhausted }
        roster[ticket.id] = ticket
        return ticket
    }

    func assignBracelet(_ bracelet: BraceletID, to participant: Participant) async throws -> Participant {
        await simulateNetwork()
        guard var updated = roster[participant.id] else { throw TerminalError.unknownAccount }
        guard updated.isAwaitingCheckIn else { throw TerminalError.braceletAlreadyPaired }
        guard self.participant(pairedTo: bracelet) == nil else { throw TerminalError.braceletAlreadyPaired }
        updated.braceletId = bracelet
        updated.checkedInAt = .now
        roster[updated.id] = updated
        return updated
    }

    func topUp(bracelet: BraceletID, amount: Money) async throws -> Participant {
        await simulateNetwork()
        guard var participant = participant(pairedTo: bracelet) else { throw TerminalError.braceletNotAssigned }
        guard !participant.isBlocked else { throw TerminalError.braceletBlocked }
        participant.balance += amount
        roster[participant.id] = participant
        return participant
    }

    func charge(bracelet: BraceletID, lines: [CartLine]) async throws -> Participant {
        await simulateNetwork()
        guard var participant = participant(pairedTo: bracelet) else { throw TerminalError.braceletNotAssigned }
        guard !participant.isBlocked else { throw TerminalError.braceletBlocked }
        let total = lines.reduce(Money.zero) { $0 + $1.total }
        // Re-check server side. The client already ran `PaymentDecision`, but a
        // second terminal may have spent the money in between.
        guard participant.balance >= total else {
            throw TerminalError.insufficientFunds(balance: participant.balance, required: total)
        }
        participant.balance -= total
        roster[participant.id] = participant
        return participant
    }
}
