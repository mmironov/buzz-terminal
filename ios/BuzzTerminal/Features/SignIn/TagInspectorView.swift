#if DEBUG
import SwiftUI

/// Debug-only: scan a tag and show everything it will tell us.
///
/// Deliberately plain rather than designed. It is a diagnostic for two people, not
/// a screen any staff member will meet, and dressing it up would imply otherwise.
/// The report is monospaced because it is mostly hex, and selectable so a finding
/// can be pasted into a message to a vendor.
struct TagInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [String] = []
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle, scanning, done, cancelled
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if lines.isEmpty {
                        Text(placeholder)
                            .font(.sbBody(13))
                            .foregroundStyle(.sbNeutral700)
                            .padding(.top, 8)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Color.sbBackground)
            .navigationTitle("Tag inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(status == .scanning ? "Scanning…" : "Scan") {
                        Task { await scan() }
                    }
                    .disabled(status == .scanning || !isAvailable)
                }
            }
        }
    }

    private var isAvailable: Bool {
        #if canImport(CoreNFC)
        NFCTagInspector.isAvailable
        #else
        false
        #endif
    }

    private var placeholder: String {
        guard isAvailable else {
            return "This device cannot read NFC tags. Run on a physical iPhone."
        }
        switch status {
        case .failed(let message): return message
        case .cancelled: return "Cancelled."
        default: return "Tap Scan, then hold a bracelet to the top of the phone."
        }
    }

    private func scan() async {
        #if canImport(CoreNFC)
        status = .scanning
        lines = []
        do {
            lines = try await NFCTagInspector.inspect()
            status = .done
            ScanFeedback.shared.success()
        } catch is CancellationError {
            // Closing the sheet is not a failure and gets no sound.
            status = .cancelled
        } catch {
            status = .failed(error.localizedDescription)
            ScanFeedback.shared.problem()
        }
        #endif
    }
}
#endif
