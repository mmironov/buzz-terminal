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

    /// Standing in for `participants/{id}/merch/order`.
    private var merch: [ParticipantID: MerchOrder]

    /// Standing in for `participants/{id}/merch/freeShirt`.
    private var freeShirts: [ParticipantID: FreeShirt]

    /// Standing in for `participants/{id}/sessions/booked` — the one extra class
    /// somebody has bought.
    private var sessions: [ParticipantID: SessionSale] = [:]

    /// Chips that have been replaced. They keep pointing at their owner in the
    /// roster's history; what they no longer do is resolve.
    private var invalidated: Set<BraceletID> = []

    init(
        roster: [Participant] = SampleData.roster,
        menu: [Drink] = SampleData.drinks,
        merch: [ParticipantID: MerchOrder] = SampleData.merchOrders,
        freeShirts: [ParticipantID: FreeShirt] = SampleData.freeShirts,
        latency: Duration = .milliseconds(180)
    ) {
        self.roster = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
        self.menu = menu
        self.merch = merch
        self.freeShirts = freeShirts
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

    /// The fixtures keep no session. A sign-in here is two taps and a password
    /// nobody checks, so restoring one would only hide the screen this path
    /// exists to exercise.
    func restoreSession() async -> StaffRole? { nil }

    // MARK: Connectivity

    /// Nothing to monitor and nothing to disconnect: the fixtures are in this
    /// process. The offline banner on this path stays whatever the debug toggle
    /// last set it to, which is what the design prototype did.
    func startMonitoringConnectivity() async {}
    func setNetworkEnabled(_ enabled: Bool) async {}

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

    func checkedIn() async throws -> [Participant] {
        await simulateNetwork()
        return roster.values
            .filter { !$0.isAwaitingCheckIn }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: Bracelets

    func participant(withBracelet bracelet: BraceletID) async throws -> Participant? {
        await simulateNetwork()
        // A replaced wristband stops resolving, exactly as it does on the real
        // backend — so the "no longer valid" screen is reachable from fixtures.
        if invalidated.contains(bracelet) { throw TerminalError.braceletInvalidated }
        return participant(pairedTo: bracelet)
    }

    func createEveningTicket(
        _ pass: DoorPass,
        evening: Evening,
        draft: DoorSaleDraft,
        bracelet: BraceletID
    ) async throws -> Participant {
        await simulateNetwork()
        guard participant(pairedTo: bracelet) == nil else { throw TerminalError.braceletAlreadyPaired }

        // Firestore would collide on `create` and retry; here the dictionary is
        // the whole world, so the next free number is simply the highest plus one.
        let highest = roster.values
            .filter { $0.evening == evening }
            .compactMap(\.eveningNumber)
            .max() ?? 0

        let ticket = Participant.eveningTicket(
            pass,
            evening: evening,
            number: highest + 1,
            draft: draft,
            bracelet: bracelet
        )
        guard roster[ticket.id] == nil else { throw TerminalError.eveningSequenceExhausted }
        roster[ticket.id] = ticket
        return ticket
    }

    func createDoorPass(
        _ pass: DoorPass,
        draft: DoorSaleDraft,
        bracelet: BraceletID
    ) async throws -> Participant {
        await simulateNetwork()
        guard participant(pairedTo: bracelet) == nil else { throw TerminalError.braceletAlreadyPaired }

        let highest = roster.values.compactMap(\.doorNumber).max() ?? 0
        let buyer = Participant.doorPass(
            pass,
            number: highest + 1,
            draft: draft,
            bracelet: bracelet
        )
        guard roster[buyer.id] == nil else { throw TerminalError.doorSequenceExhausted }
        roster[buyer.id] = buyer
        // The email goes unrecorded, like the payment method on a top-up: this
        // fixture keeps people, not subcollections, and half a store is worse
        // than none.
        return buyer
    }

    func replaceBracelet(
        _ fresh: BraceletID,
        for participant: Participant,
        reason: String,
        fee: Money?,
        method: PaymentMethod?
    ) async throws -> Participant {
        await simulateNetwork()
        guard var updated = roster[participant.id] else { throw TerminalError.unknownAccount }
        guard let old = updated.braceletId else { throw TerminalError.braceletNotAssigned }
        guard self.participant(pairedTo: fresh) == nil else { throw TerminalError.braceletAlreadyPaired }

        invalidated.insert(old)
        updated.braceletId = fresh
        roster[updated.id] = updated
        return updated
    }

    /// The fixtures charge a euro, which is what the festival settled on. A
    /// number here rather than nil so the waive path is not the only one the
    /// previews and the simulator can reach.
    func replacementFee() async throws -> Money? {
        await simulateNetwork()
        return Money(euros: 1)
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

    func braceletColours() async throws -> [BraceletColour] {
        await simulateNetwork()
        return SampleData.braceletColours
    }

    func doorPasses() async throws -> [DoorPass] {
        await simulateNetwork()
        return SampleData.doorPasses
    }

    // MARK: Merch

    func merchOrder(for participant: Participant) async throws -> MerchOrder? {
        await simulateNetwork()
        return merch[participant.id]
    }

    func freeShirt(for participant: Participant) async throws -> FreeShirt? {
        await simulateNetwork()
        return freeShirts[participant.id]
    }

    func setFreeShirt(
        size: String?,
        colour: String?,
        handedOver: Bool,
        for participant: Participant
    ) async throws -> FreeShirt {
        await simulateNetwork()
        guard var shirt = freeShirts[participant.id], shirt.entitled else {
            throw TerminalError.noFreeShirt
        }
        shirt.size = size
        shirt.colour = colour
        shirt.collectedAt = handedOver ? .now : nil
        shirt.collectedBy = handedOver ? "fixture-staff" : nil
        freeShirts[participant.id] = shirt
        return shirt
    }

    func specialSessions() async throws -> [SpecialSession] {
        await simulateNetwork()
        return SampleData.specialSessions
    }

    func sessionSale(for participant: Participant) async throws -> SessionSale? {
        await simulateNetwork()
        return sessions[participant.id]
    }

    func sellSession(
        _ session: SpecialSession,
        method: PaymentMethod,
        to participant: Participant
    ) async throws -> SessionSale {
        await simulateNetwork()
        // One class each: the rules refuse a second write to the same document,
        // and so does the fixture — selling a second class to the same person is
        // the mistake worth reproducing.
        guard sessions[participant.id] == nil else {
            throw TerminalError.sessionNotSold
        }
        let sale = SessionSale(
            sessionId: session.id,
            name: session.name,
            price: session.price,
            method: method,
            soldAt: .now,
            soldBy: "fixture-staff"
        )
        sessions[participant.id] = sale
        return sale
    }

    func setMerchCollected(_ collected: Bool, for participant: Participant) async throws -> MerchOrder {
        await simulateNetwork()
        guard var order = merch[participant.id], order.hasSomethingToCollect else {
            throw TerminalError.noMerchOrdered
        }
        order.collectedAt = collected ? .now : nil
        order.collectedBy = collected ? "fixture-staff" : nil
        merch[participant.id] = order
        return order
    }

    func topUp(bracelet: BraceletID, amount: Money, method: PaymentMethod) async throws -> Participant {
        await simulateNetwork()
        guard var participant = participant(pairedTo: bracelet) else { throw TerminalError.braceletNotAssigned }
        guard !participant.isBlocked else { throw TerminalError.braceletBlocked }
        // `method` goes unrecorded: this fixture keeps balances, not a ledger,
        // and inventing half a ledger here would be a second source of truth for
        // the screens to disagree with.
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
