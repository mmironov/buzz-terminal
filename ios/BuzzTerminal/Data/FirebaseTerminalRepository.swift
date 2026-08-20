import FirebaseAuth
import FirebaseFirestore
import Foundation
import OSLog

/// The real backend.
///
/// An `actor` for two reasons. The obvious one: it caches the next evening-ticket
/// number, which is mutable state that two concurrent sales could race on. The
/// better one: `TerminalRepository` is `Sendable`, and an actor satisfies that
/// honestly rather than by an `@unchecked` promise nobody can check.
///
/// **Every money write is a batch, not two writes.** `firestore.rules` verifies a
/// balance change against the ledger entry that justifies it using `getAfter()`,
/// which only sees documents written together. Splitting them is not a style
/// choice that would work slightly worse — it is rejected. The 49 tests in
/// `backend/rules-tests/` are the specification for the shapes below.
actor FirebaseTerminalRepository: TerminalRepository {

    /// `static` so `signInFailure` can log without needing actor isolation.
    private static let log = Logger(
        subsystem: "fest.swingbuzz.BuzzTerminal",
        category: "repository"
    )

    /// How long a commit is given to reach the server before it is treated as
    /// queued rather than pending.
    ///
    /// Firestore's `commit` completion fires only on server acknowledgement, so
    /// offline it never fires at all — awaiting it would hang the till. But firing
    /// and forgetting would be worse in the common case: a write the server refuses
    /// while online must still fail in front of the operator, who can then retry
    /// before the guest has walked away. So the two race, and only a write that has
    /// genuinely gone quiet becomes somebody's reconciliation job.
    private static let commitGrace: Duration = .seconds(3)

    private let db: Firestore
    private let auth: Auth
    private let sync: SyncCenter
    /// Which physical device took the cash. Recorded on every ledger entry so a
    /// till can be reconciled at the end of the night.
    private let terminalId: String

    /// The next evening-ticket number to try, per evening.
    ///
    /// Seeded once per evening by a query, then incremented locally. The id
    /// encodes the number, so a collision with another desk surfaces as a failed
    /// `create` and we simply try the next one — see `createEveningTicket`.
    private var nextEveningNumber: [Evening: Int] = [:]

    init(
        db: Firestore = .firestore(),
        auth: Auth = .auth(),
        terminalId: String = TerminalIdentity.current,
        sync: SyncCenter
    ) {
        self.db = db
        self.auth = auth
        self.terminalId = terminalId
        self.sync = sync
    }

    // MARK: - Committing, online or not

    private enum CommitOutcome {
        /// The server said yes.
        case acknowledged
        /// Still unanswered after the grace period. Firestore's own durable queue
        /// owns it now: it survives a restart and replays on reconnect. If it is
        /// later refused, `SyncCenter` gets a `FailedWrite` — nobody is waiting to
        /// be told by then.
        case queued
    }

    /// Commit, giving the server a moment to object.
    ///
    /// `makeFailure` is only called for a write that had already been reported as
    /// queued. A write refused *while the operator is still standing there* throws
    /// instead, and is deliberately kept off the reconciliation list: they saw the
    /// error, nothing was served, and a list that fills up with problems somebody
    /// already handled is a list nobody reads.
    private func commit(
        _ batch: WriteBatch,
        makeFailure: @escaping @Sendable (Error) -> FailedWrite
    ) async throws -> CommitOutcome {
        let sync = self.sync
        await MainActor.run { sync.enqueued() }

        let race = CommitRace()

        return try await withCheckedThrowingContinuation { continuation in
            batch.commit { error in
                let alreadyQueued = race.finishFromServer()
                Task { @MainActor in
                    if let error, alreadyQueued {
                        sync.failed(makeFailure(error))
                    } else {
                        sync.acknowledged()
                    }
                }
                guard !alreadyQueued else { return }   // nobody is waiting
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: .acknowledged)
                }
            }

            Task {
                try? await Task.sleep(for: Self.commitGrace)
                if race.finishFromTimeout() {
                    continuation.resume(returning: .queued)
                }
            }
        }
    }

    // MARK: - Auth

    /// Sign in and read the staff role from the token's custom claim.
    ///
    /// The role is **not** derived from the email address. Staff use their personal
    /// addresses, and more importantly the client must not get to decide what it is
    /// allowed to do: `firestore.rules` authorises on `request.auth.token.role`,
    /// which only the Admin SDK can set. An account with no claim is refused here
    /// rather than being allowed in to fail on every read.
    func signIn(email: String, password: String) async throws -> StaffRole {
        let result: AuthDataResult
        do {
            result = try await auth.signIn(withEmail: email, password: password)
        } catch {
            throw Self.signInFailure(error)
        }

        // Force a refresh: a role granted after this device last signed in would
        // otherwise sit behind a cached token for up to an hour.
        let token = try await result.user.getIDTokenResult(forcingRefresh: true)
        guard let raw = token.claims["role"] as? String,
              let role = StaffRole(claim: raw)
        else {
            try? auth.signOut()
            throw TerminalError.noRoleAssigned
        }
        return role
    }

    func signOut() async {
        connectivity?.remove()
        connectivity = nil
        try? auth.signOut()
    }

    // MARK: - Connectivity

    private var connectivity: ListenerRegistration?

    /// Watch whether Firestore can actually be reached.
    ///
    /// Not `NWPathMonitor`: a phone can hold a perfectly good wifi association to a
    /// venue access point that routes nowhere, which is the exact failure a festival
    /// produces. `metadata.isFromCache` answers the question that matters — is this
    /// data coming from the server or from our own pocket — and it is Firestore's own
    /// opinion rather than an inference.
    ///
    /// Listens to `drinks`, which every terminal already reads, is tiny, and changes
    /// almost never. Started after sign-in because an unauthenticated listener is
    /// refused by the rules.
    func startMonitoringConnectivity() {
        guard connectivity == nil else { return }
        let sync = self.sync
        connectivity = db.collection(Fire.Collection.drinks)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                guard let snapshot else {
                    if let error {
                        Self.log.error("connectivity listener: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                let offline = snapshot.metadata.isFromCache
                Task { @MainActor in sync.setOffline(offline) }
            }
    }

    /// Cut Firestore off from the network, or restore it.
    ///
    /// The only practical way to exercise the queue without finding a dead spot:
    /// airplane mode also kills the debugger, and a venue's bad wifi cannot be
    /// summoned on demand. Firestore keeps accepting writes while disabled and
    /// replays them on enable, which is precisely the behaviour under test.
    func setNetworkEnabled(_ enabled: Bool) async {
        do {
            if enabled {
                try await db.enableNetwork()
            } else {
                try await db.disableNetwork()
            }
        } catch {
            Self.log.error("could not toggle the network: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Turn an Auth failure into something an operator can act on — and log the
    /// underlying code, which is the part that actually matters at 2am.
    ///
    /// The first version of this was `catch { throw .unknownAccount }`. It cost a
    /// packet trace to find out that a real sign-in had failed on a 400 from
    /// identitytoolkit, because the one fact worth keeping had been discarded at the
    /// point of failure. A wrong password and a dropped wifi need different
    /// reactions from whoever is standing at the desk.
    ///
    /// Wrong password and unknown email are not separated, because the server
    /// refuses to separate them: with email enumeration protection on, both arrive
    /// as `invalidCredential`.
    private static func signInFailure(_ error: Error) -> TerminalError {
        let nsError = error as NSError
        let code = AuthErrorCode(rawValue: nsError.code)

        // The numeric code, not `String(describing: code)`. `AuthErrorCode` is a
        // struct with static members rather than an enum, so describing it prints
        // the useless "FirebaseAuth.AuthErrorCode" — which is exactly what the
        // first version of this logged. 17004 is worth searching for; a type name
        // is not.
        log.error("""
            Sign-in failed: \(nsError.domain, privacy: .public) \
            \(nsError.code, privacy: .public) — \
            \(error.localizedDescription, privacy: .public)
            """)

        switch code {
        case .networkError:
            return .offline
        case .userDisabled:
            return .accountDisabled
        case .tooManyRequests:
            return .tooManyAttempts
        default:
            return .unknownAccount
        }
    }

    private func requireStaffUid() throws -> String {
        guard let uid = auth.currentUser?.uid else { throw TerminalError.unknownAccount }
        return uid
    }

    // MARK: - Catalogue

    func drinks() async throws -> [Drink] {
        let snapshot = try await db.collection(Fire.Collection.drinks)
            .whereField(Fire.Drink.isActive, isEqualTo: true)
            .order(by: Fire.Drink.sortOrder)
            .getDocuments()
        return snapshot.documents.compactMap(Drink.init(document:))
    }

    func awaitingCheckIn() async throws -> [Participant] {
        // Equality against null is a supported query, and this is the whole
        // point of `braceletId == nil` being the "awaiting" state rather than a
        // separate collection. Composite index: braceletId, nameLower.
        let snapshot = try await db.collection(Fire.Collection.participants)
            .whereField(Fire.Participant.braceletId, isEqualTo: NSNull())
            .order(by: Fire.Participant.nameLower)
            .getDocuments()
        return snapshot.documents.compactMap(Participant.init(document:))
    }

    // MARK: - Bracelets

    func participant(withBracelet bracelet: BraceletID) async throws -> Participant? {
        // Two point reads by document id — no query, no index, and both resolve
        // from the offline cache when the wifi is out. This is why the reverse
        // lookup collection exists at all.
        let lookup = try await braceletDocument(bracelet).getDocument()
        guard let participantId = lookup.data()?[Fire.Bracelet.participantId] as? String else {
            return nil
        }
        let document = try await participantDocument(ParticipantID(participantId)).getDocument()
        return Participant(document: document)
    }

    func assignBracelet(_ bracelet: BraceletID, to participant: Participant) async throws -> Participant {
        let uid = try requireStaffUid()
        let batch = db.batch()

        batch.updateData([
            Fire.Participant.braceletId: bracelet.rawValue,
            Fire.Participant.checkedInAt: FieldValue.serverTimestamp(),
            Fire.Participant.updatedAt: FieldValue.serverTimestamp(),
        ], forDocument: participantDocument(participant.id))

        // Created, never set: the rules forbid re-pointing a chip, so a bracelet
        // that already exists must fail rather than quietly move a balance.
        batch.setData([
            Fire.Bracelet.participantId: participant.id.rawValue,
            Fire.Bracelet.staffUid: uid,
            Fire.Bracelet.pairedAt: FieldValue.serverTimestamp(),
        ], forDocument: braceletDocument(bracelet))

        let name = participant.name
        let participantId = participant.id.rawValue
        let braceletValue = bracelet.rawValue
        let terminal = terminalId

        do {
            _ = try await commit(batch) { error in
                FailedWrite(
                    transactionId: "pair-\(braceletValue)",
                    kind: .checkIn,
                    participantId: participantId,
                    participantName: name,
                    braceletId: braceletValue,
                    amount: .zero,
                    attemptedAt: Date(),
                    terminalId: terminal,
                    reason: error.localizedDescription
                )
            }
        } catch {
            // The rules allow `create` on a bracelet and never `update`, so the
            // common denial here is a chip that is already paired — which is
            // precisely what a batch of wristbands with duplicated UIDs would
            // produce, on the second guest rather than the first.
            //
            // Confirmed with a read rather than inferred from the error: a denial
            // can also mean a bar account, or a token whose claim has gone stale.
            // Telling somebody at the desk "use a fresh one" when the real problem
            // is their role would send them looking in the wrong place.
            if let existing = try? await braceletDocument(bracelet).getDocument(),
               existing.exists {
                throw TerminalError.braceletAlreadyPaired
            }
            throw error
        }
        // Resolves from the local cache when offline, and Firestore's latency
        // compensation means the pending write is already reflected in it — so the
        // screen shows the guest checked in, which is what actually happened at the
        // desk.
        return try await reload(participant.id)
    }

    // MARK: - Door sales

    func createEveningTicket(evening: Evening, bracelet: BraceletID) async throws -> Participant {
        let uid = try requireStaffUid()
        var number = try await seedEveningNumber(for: evening)

        // The id encodes the number, so Firestore does the deduplication: if
        // another desk already took this one, `create` fails and we try the next.
        // Bounded, because an unbounded retry against a genuine rules violation
        // would spin forever writing nothing.
        for _ in 0..<25 {
            let ticket = Participant.eveningTicket(evening: evening, number: number, bracelet: bracelet)
            let batch = db.batch()
            batch.setData(
                ticket.eveningTicketDocument(createdBy: uid),
                forDocument: participantDocument(ticket.id)
            )
            batch.setData([
                Fire.Bracelet.participantId: ticket.id.rawValue,
                Fire.Bracelet.staffUid: uid,
                Fire.Bracelet.pairedAt: FieldValue.serverTimestamp(),
            ], forDocument: braceletDocument(bracelet))

            do {
                try await batch.commit()
                nextEveningNumber[evening] = number + 1
                return try await reload(ticket.id)
            } catch {
                // A rules rejection and a taken number are indistinguishable here:
                // both arrive as PERMISSION_DENIED, because "already exists" is
                // enforced by `allow create` failing. Advancing and retrying is
                // correct for the first and harmless for the second, which the
                // retry bound contains.
                number += 1
                nextEveningNumber[evening] = number
            }
        }
        throw TerminalError.eveningSequenceExhausted
    }

    /// One query per evening per app run, then local increments.
    ///
    /// A single-field equality query, so it needs no composite index. Reading the
    /// whole evening once beats a counter document: no extra collection, no extra
    /// rules path to secure, and no contention point.
    private func seedEveningNumber(for evening: Evening) async throws -> Int {
        if let cached = nextEveningNumber[evening] { return cached }
        let snapshot = try await db.collection(Fire.Collection.participants)
            .whereField(Fire.Participant.evening, isEqualTo: evening.rawValue)
            .getDocuments()
        let highest = snapshot.documents
            .compactMap { $0.data()[Fire.Participant.eveningNumber] as? Int }
            .max() ?? 0
        let next = highest + 1
        nextEveningNumber[evening] = next
        return next
    }

    // MARK: - Money

    func topUp(bracelet: BraceletID, amount: Money) async throws -> Participant {
        try await moveMoney(
            bracelet: bracelet,
            type: Fire.Transaction.typeTopUp,
            amount: amount
        )
    }

    func charge(bracelet: BraceletID, lines: [CartLine]) async throws -> Participant {
        // Checked here so the operator gets a sentence rather than a
        // PERMISSION_DENIED. The server refuses a ninth line either way; see
        // `Fire.Transaction.maxItems` for why the ceiling exists at all.
        guard lines.count <= Fire.Transaction.maxItems else {
            throw TerminalError.tooManyDrinksInOneRound(limit: Fire.Transaction.maxItems)
        }
        return try await moveMoney(
            bracelet: bracelet,
            type: Fire.Transaction.typeCharge,
            // The same array produces both the total and the itemisation, because
            // the rules check one against the other. Computing them apart is how
            // they would come to disagree.
            amount: lines.ledgerTotal,
            items: lines.ledgerItems
        )
    }

    /// The one write shape that matters: a ledger entry and the new balance, in a
    /// single batch, with the client-generated id doing double duty as the
    /// idempotency key.
    ///
    /// The balance is computed from a fresh read rather than with
    /// `FieldValue.increment`, because the rules must be able to verify
    /// `balanceAfter == balanceBefore + signedAmount`. An increment sentinel gives
    /// them nothing to compare. The cost is a lost update window — which the rules
    /// close, by rejecting a balance that no longer agrees with the ledger.
    private func moveMoney(
        bracelet: BraceletID,
        type: String,
        amount: Money,
        items: [[String: Any]]? = nil
    ) async throws -> Participant {
        guard amount.isPositive else { throw TerminalError.insufficientFunds(balance: .zero, required: amount) }
        let uid = try requireStaffUid()

        guard let current = try await participant(withBracelet: bracelet) else {
            throw TerminalError.braceletNotAssigned
        }
        guard !current.isBlocked else { throw TerminalError.braceletBlocked }

        let signed = type == Fire.Transaction.typeCharge ? Money(cents: -amount.cents) : amount
        let after = current.balance + signed
        guard after.cents >= 0 else {
            throw TerminalError.insufficientFunds(balance: current.balance, required: amount)
        }

        let txId = UUID().uuidString
        let batch = db.batch()

        var entry: [String: Any] = [
            Fire.Transaction.clientTxId: txId,
            Fire.Transaction.type: type,
            Fire.Transaction.amount: amount.cents,
            Fire.Transaction.signedAmount: signed.cents,
            Fire.Transaction.staffUid: uid,
            Fire.Transaction.terminalId: terminalId,
            Fire.Transaction.createdAt: FieldValue.serverTimestamp(),
        ]
        // Set, never present-and-empty: the rules require a charge to carry at
        // least one line and a top-up to carry none at all.
        if let items, !items.isEmpty {
            entry[Fire.Transaction.items] = items
        }
        batch.setData(entry, forDocument: transactionDocument(current.id, txId))

        batch.updateData([
            Fire.Participant.balance: after.cents,
            Fire.Participant.lastTxId: txId,
            Fire.Participant.updatedAt: FieldValue.serverTimestamp(),
        ], forDocument: participantDocument(current.id))

        let kind: FailedWrite.Kind = type == Fire.Transaction.typeCharge ? .charge : .topUp
        let name = current.name
        let participantId = current.id.rawValue
        let braceletValue = bracelet.rawValue
        let terminal = terminalId

        _ = try await commit(batch) { error in
            FailedWrite(
                transactionId: txId,
                kind: kind,
                participantId: participantId,
                participantName: name,
                braceletId: braceletValue,
                amount: amount,
                attemptedAt: Date(),
                terminalId: terminal,
                reason: error.localizedDescription
            )
        }
        return try await reload(current.id)
    }

    // MARK: - Plumbing

    private func participantDocument(_ id: ParticipantID) -> DocumentReference {
        db.collection(Fire.Collection.participants).document(id.rawValue)
    }

    private func transactionDocument(_ id: ParticipantID, _ txId: String) -> DocumentReference {
        participantDocument(id).collection(Fire.Collection.transactions).document(txId)
    }

    private func braceletDocument(_ bracelet: BraceletID) -> DocumentReference {
        db.collection(Fire.Collection.bracelets).document(bracelet.rawValue)
    }

    /// Read back what the server actually stored.
    ///
    /// Every mutation returns this rather than the client's own arithmetic, so a
    /// server-side timestamp or a rules-adjusted value is what reaches the UI.
    private func reload(_ id: ParticipantID) async throws -> Participant {
        let document = try await participantDocument(id).getDocument()
        guard let participant = Participant(document: document) else {
            throw TerminalError.unknownAccount
        }
        return participant
    }
}

/// A stable per-device identifier for ledger entries.
///
/// Persisted rather than generated per launch, so "which till took this cash?"
/// survives an app restart mid-shift. Not a device fingerprint and not tied to any
/// hardware id — just a UUID this install made up once.
enum TerminalIdentity {
    private static let key = "fest.swingbuzz.terminalId"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = "terminal-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}

/// Which of the two racers got there first, resolved exactly once.
///
/// `@unchecked Sendable` over a lock rather than an actor: both callers need a
/// synchronous answer — one is a Firestore completion, the other a sleeping Task —
/// and a continuation resumed twice is a crash, not a race to be smoothed over.
private final class CommitRace: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    /// - Returns: true if the timeout already claimed it, meaning the caller has
    ///   been told the write is queued and no longer waits for an answer.
    func finishFromServer() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let alreadyQueued = finished
        finished = true
        return alreadyQueued
    }

    /// - Returns: true if the timeout won and should resume the continuation.
    func finishFromTimeout() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}
