#if DEBUG
import SwiftUI

/// Debug-only: walk a box of wristbands and confirm every UID is unique.
///
/// The instruction on screen matters as much as the code. A repeated UID cannot be
/// told apart from the same wristband scanned twice, so the tool asks for a physical
/// process — scan from one pile into another — under which a repeat means something.
struct BatchAuditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var audit = BraceletAudit()
    @State private var isScanning = false
    @State private var lastOutcome: String = ""
    #if canImport(CoreNFC)
    @State private var auditor = NFCBatchAuditor()
    #endif

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header

                if !audit.repeats.isEmpty {
                    repeatsBanner
                }

                list
            }
            .background(Color.sbBackground)
            .navigationTitle("Bracelet audit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { stop(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isScanning {
                        Button("Stop") { stop() }
                    } else {
                        Button("Scan") { start() }
                            .disabled(!isAvailable)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(audit.summary)
                .font(.sbHeading(15))

            if !isAvailable {
                Text("This device cannot read NFC tags. Run on a physical iPhone.")
                    .font(.sbBody(12.5))
                    .foregroundStyle(.sbNeutral700)
            } else if audit.seen.isEmpty && !isScanning {
                Text("""
                    Scan from one pile into another, so a bracelet is only ever \
                    presented once. Then a repeated id means two wristbands share it, \
                    which is worth stopping for — rather than just a double scan.
                    """)
                    .font(.sbBody(12.5))
                    .foregroundStyle(.sbNeutral700)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !lastOutcome.isEmpty {
                Text(lastOutcome)
                    .font(.sbBody(12.5))
                    .foregroundStyle(.sbNeutral700)
            }

            if !audit.seen.isEmpty {
                Text("\(audit.reads) reads")
                    .font(.sbBody(11))
                    .foregroundStyle(.sbNeutral500)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var repeatsBanner: some View {
        VStack(alignment: .leading, spacing: 5) {
            SBKicker(text: "Check these", color: .sbAccent, size: 9, tracking: 0.16)
            ForEach(audit.repeats) { event in
                Text("\(event.id.rawValue) — same id as #\(event.firstSeenAt)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.sbAccent)
                    .textSelection(.enabled)
            }
            Text("""
                Set these aside. If two different wristbands are reading the same id, \
                they cannot both be used: the second guest would share the first \
                guest's balance.
                """)
                .font(.sbBody(11.5))
                .foregroundStyle(.sbNeutral700)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbAccent100)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(audit.seen.enumerated()), id: \.element) { index, id in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.sbNeutral500)
                                .frame(width: 30, alignment: .trailing)
                            Text(id.rawValue)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .id(id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .onChange(of: audit.seen.count) {
                // Keep the newest read in view, so the operator can glance rather
                // than scroll while working through a pile.
                if let last = audit.seen.last {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var isAvailable: Bool {
        #if canImport(CoreNFC)
        NFCBatchAuditor.isAvailable
        #else
        false
        #endif
    }

    private func start() {
        #if canImport(CoreNFC)
        isScanning = true
        lastOutcome = ""
        Task {
            for await chip in auditor.chips() {
                switch audit.record(chip, at: Date()) {
                case .new(let position):
                    lastOutcome = "#\(position)  \(chip.rawValue)"
                case .stillHolding:
                    // Same chip still in the field. Deliberately silent.
                    break
                case .repeated(let event):
                    lastOutcome = "Repeat of #\(event.firstSeenAt)"
                }
            }
            isScanning = false
        }
        #endif
    }

    private func stop() {
        #if canImport(CoreNFC)
        auditor.stop()
        #endif
        isScanning = false
    }
}
#endif
