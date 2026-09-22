import SwiftUI

/// The held frame between launch and knowing who is at the terminal.
///
/// Deliberately says almost nothing. This is on screen for the length of a
/// keychain read — and for a second or two on a cold launch where the token has
/// to be refreshed — so anything more than the wordmark would be a message
/// nobody has time to read. No spinner: the design system has none, and a
/// progress indicator would promise a wait that usually is not one.
struct RestoringSessionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SBKicker(text: "Swing Buzz Festival", color: .sbAccent, tracking: 0.16)
            Text("Staff\nTerminal")
                .font(.sbDisplay(40))
                .sbLineHeight(1.05, size: 40)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 26)
    }
}

#Preview {
    RestoringSessionView()
        .background(Color.sbBackground)
}
