import SwiftUI

// MARK: - Buttons

/// The `.btn` family: `.btn-primary`, `.btn-secondary`, `.btn-ghost`.
enum SBButtonKind {
    /// Solid accent fill. One per screen — "use the accent sparingly".
    case primary
    /// Outlined in the divider colour.
    case secondary
    /// Accent text, no chrome.
    case ghost
}

/// Modernist's button, including the rule that trips people up:
/// "Button labels are flush left — a button wider than its label starts the text
/// at the left padding edge (trailing icon and all), never centered."
///
/// So a full-width button is `.leading`, not `.center`. That is the opposite of
/// the iOS default and the single most visible thing to get wrong here.
struct SBButtonStyle: ButtonStyle {
    var kind: SBButtonKind
    /// Full width, label flush left.
    var block: Bool = false
    var minHeight: CGFloat?
    var fontSize: CGFloat = 14

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        configuration.label
            .font(.sbHeading(fontSize, weight: .extrabold))
            .foregroundStyle(foreground)
            .frame(maxWidth: block ? .infinity : nil, alignment: block ? .leading : .center)
            .frame(minHeight: minHeight)
            .padding(.vertical, kind == .ghost ? 0 : SBSpace.x2)
            .padding(.horizontal, horizontalPadding)
            .background(background(pressed: pressed))
            .overlay {
                if kind == .secondary {
                    Rectangle().stroke(Color.sbDivider, lineWidth: SBRule.hairline)
                }
            }
            // `--radius-md` is 0: clip to a rectangle so nothing softens.
            .clipShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }

    private var horizontalPadding: CGFloat {
        // `padding: var(--space-2) calc(var(--space-3) * 1.2)` = 8px 14.4px,
        // and `.btn-ghost { padding-inline: var(--space-1) }`.
        kind == .ghost ? SBSpace.x1 : SBSpace.x3 * 1.2
    }

    private var foreground: Color {
        switch kind {
        case .primary: .sbBackground
        case .secondary: .sbInk
        case .ghost: .sbAccent
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary:
            // `:active { background: var(--color-accent-700) }`
            pressed ? .sbAccent700 : .sbAccent
        case .secondary:
            pressed ? .sbInk(0.14) : .clear
        case .ghost:
            pressed ? Color.sbAccent.opacity(0.18) : .clear
        }
    }
}

extension ButtonStyle where Self == SBButtonStyle {
    static var sbPrimary: SBButtonStyle { SBButtonStyle(kind: .primary) }
    static var sbSecondary: SBButtonStyle { SBButtonStyle(kind: .secondary) }
    static var sbGhost: SBButtonStyle { SBButtonStyle(kind: .ghost, fontSize: 12) }

    /// The full-width, flush-left action at the bottom of most screens.
    static func sbBlock(
        _ kind: SBButtonKind,
        minHeight: CGFloat = 46,
        fontSize: CGFloat = 15
    ) -> SBButtonStyle {
        SBButtonStyle(kind: kind, block: true, minHeight: minHeight, fontSize: fontSize)
    }

    /// `.btn-icon` — the 36×36 square used by the cart's − and + controls.
    static func sbIcon(fontSize: CGFloat = 18) -> SBButtonStyle {
        SBButtonStyle(kind: .secondary, minHeight: 36, fontSize: fontSize)
    }
}

// MARK: - Rules

/// `.hr` — the strong 2pt rule. Modernist's don'ts: "Do not soften the rules
/// into hairlines or drop them for whitespace."
struct SBDivider: View {
    var weight: CGFloat = SBRule.strong
    var color: Color = .sbDivider

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: weight)
    }
}

// MARK: - Tags

/// `.tag` with `.tag-neutral` / `.tag-outline`.
struct SBTag: View {
    enum Style { case neutral, outline, accent }

    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(.sbBody(11))
            .tracking(0.02 * 11)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(fill)
            .overlay {
                if style == .outline {
                    Rectangle().stroke(Color.sbAccent, lineWidth: SBRule.hairline)
                }
            }
    }

    private var foreground: Color {
        switch style {
        case .neutral: .sbNeutral800
        case .outline: .sbAccent
        case .accent: .sbAccent800
        }
    }

    private var fill: Color {
        switch style {
        case .neutral: .sbNeutral100
        case .outline: .clear
        case .accent: .sbAccent100
        }
    }
}

// MARK: - Text fields

/// `.field` + `label` + `.input`.
struct SBTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType?
    /// `.never` suits every field this started with — an email and a password.
    /// A person's name is the exception, and typing one in lower case at a desk
    /// is a worse default than an occasional stray capital.
    var autocapitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.sbBody(12))
                .foregroundStyle(.sbInk(0.7))

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.sbBody(14))
            .foregroundStyle(.sbInk)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .textContentType(textContentType)
            // `caret-color: var(--color-accent)`
            .tint(.sbAccent)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(Color.sbSurface)
            .overlay {
                Rectangle().stroke(Color.sbDivider, lineWidth: SBRule.hairline)
            }
        }
    }
}

// MARK: - Status bands

/// The full-bleed coloured band that announces an outcome: green for approved,
/// accent red for blocked or declined. Used on the participant, blocked,
/// receipt and pay-review screens.
struct SBBand: View {
    enum Tone {
        case ok
        case alert

        var fill: Color {
            switch self {
            case .ok: .sbOk
            case .alert: .sbAccent
            }
        }
    }

    let text: String
    var tone: Tone = .ok
    var glyph: SBGlyph = .check
    var glyphSize: CGFloat = 24
    var fontSize: CGFloat = 15
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)

    var body: some View {
        HStack(spacing: 10) {
            SBGlyphView(glyph: glyph, size: glyphSize, color: .white)
            Text(text.uppercased())
                .font(.sbHeading(fontSize, weight: .extrabold))
                .tracking(0.14 * fontSize)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(padding)
        .background(tone.fill)
    }
}

// MARK: - Key/value rows

/// The receipt's line rows: label left in muted ink, value right in tabular
/// figures, hairline underneath.
struct SBDetailRow: View {
    let key: String
    let value: String
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: SBSpace.x3) {
                Text(key)
                    .font(.sbBody(13.5))
                    .foregroundStyle(.sbInk(0.6))
                Spacer(minLength: 0)
                Text(value)
                    .font(.sbBody(13.5))
            }
            .padding(.vertical, 10)

            if showsDivider {
                SBDivider(weight: SBRule.hairline)
            }
        }
    }
}

// MARK: - Choices

/// One option in a small mutually exclusive set: a dance role, a level, cash or
/// card.
///
/// A radio button drawn square rather than round, because "do not round a corner
/// anywhere" is the design system's first don't and a circle here would be the
/// only one on the screen. It still reads as a radio: two or three exclusive
/// options, one marker, filled when chosen.
///
/// The selected state is carried by the fill and the marker together, not by
/// colour alone — the accent is the only strong colour in this design, and a
/// terminal at a dim reception desk is exactly where a colour-only difference
/// fails.
struct SBChoiceBox: View {
    let title: String
    let isSelected: Bool
    /// A word under the title saying why this one cannot be chosen.
    var note: String? = nil
    var isEnabled: Bool = true
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: SBSpace.x2) {
                Rectangle()
                    .stroke(marker, lineWidth: SBRule.hairline)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isSelected {
                            Rectangle().fill(Color.sbAccent).frame(width: 8, height: 8)
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.sbHeading(14, weight: .extrabold))
                        .foregroundStyle(.sbInk(isEnabled ? 1 : 0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let note {
                        Text(note)
                            .font(.sbBody(10.5))
                            .foregroundStyle(.sbInk(0.4))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SBSpace.x3)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isSelected ? Color.sbAccent.opacity(0.12) : .clear)
            .overlay {
                Rectangle().stroke(
                    isSelected ? Color.sbAccent : Color.sbDivider,
                    lineWidth: isSelected ? SBRule.strong : SBRule.hairline
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(note.map { "\(title), \($0)" } ?? title)
    }

    /// The marker fades with the label, so a full class does not read as an
    /// empty checkbox somebody has not got round to ticking.
    private var marker: Color {
        if isSelected { return .sbAccent }
        return .sbInk(isEnabled ? 0.45 : 0.2)
    }
}

#Preview("Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: SBSpace.x4) {
            Button("Sign in") {}.buttonStyle(.sbBlock(.primary))
            Button("Scan another bracelet") {}.buttonStyle(.sbBlock(.secondary, minHeight: 44))
            HStack {
                Button("Cancel") {}.buttonStyle(.sbGhost)
                Button("−") {}.buttonStyle(.sbIcon())
                Button("+") {}.buttonStyle(.sbIcon())
            }
            SBDivider()
            HStack {
                SBTag(text: "Checked in Fri 17:12")
                SBTag(text: "Assign", style: .outline)
            }
            SBTextField(label: "Email", placeholder: "name@swingbuzz.fest", text: .constant(""))
            SBBand(text: "Payment approved")
            SBBand(text: "Bracelet blocked", tone: .alert, glyph: .blocked)
            SBDetailRow(key: "Participant", value: "Marta Lindqvist")
            HStack(spacing: SBSpace.x2) {
                SBChoiceBox(title: "Cash", isSelected: true) {}
                SBChoiceBox(title: "Card", isSelected: false) {}
            }
            SBChoiceBox(title: "Advanced", isSelected: false, note: "Sold out", isEnabled: false) {}
        }
        .padding(SBSpace.x4)
    }
    .background(Color.sbBackground)
}
