import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  Which colour wristband somebody gets.
//
//  Two strings have to meet: a pass type typed into the admin panel, and a pass
//  type that came out of a hand-maintained Google Sheet. If they fail to match,
//  the screen shows no colour and nobody is told why — so the matching rule is
//  written down here rather than inferred from a dictionary lookup.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Bracelet colours")
struct BraceletColourTests {

    private func guest(_ ticketType: String, level: String = "") -> Participant {
        Participant(
            id: ParticipantID("101"), ticketRef: "SB-101", name: "Nina Kowalski",
            ticketType: ticketType, country: "PL", level: level
        )
    }

    private let scheme = BraceletColourScheme([
        BraceletColour(id: "full-pass", passType: "Full Pass", hex: "#1E6BB8", name: "Sky Blue"),
        BraceletColour(id: "full-pass-gold", passType: "Full Pass Gold", hex: "#C8A64B", name: "Gold"),
    ])

    // MARK: Matching

    @Test("A pass type with a colour gets it")
    func matches() {
        #expect(scheme.colour(for: guest("Full Pass"))?.hex == "#1E6BB8")
    }

    /// The bug this design is meant to avoid: "Full Pass Gold" starts with
    /// "Full Pass", and anything doing prefix matching files every Gold holder
    /// under the wrong colour. Exact keys, so it cannot happen.
    @Test("Full Pass Gold is not Full Pass")
    func longerNameIsNotAPrefixMatch() {
        #expect(scheme.colour(for: guest("Full Pass Gold"))?.name == "Gold")
        #expect(scheme.colour(for: guest("Full Pass"))?.name == "Sky Blue")
    }

    /// One side is typed into a web form, the other comes from a Sheet somebody
    /// maintains by hand. A trailing space is invisible and would silently cost
    /// somebody their colour.
    @Test("Case and surrounding whitespace do not decide it")
    func tolerantMatching() {
        #expect(scheme.colour(for: guest("  full pass  "))?.name == "Sky Blue")
        #expect(scheme.colour(for: guest("FULL PASS GOLD"))?.name == "Gold")
    }

    @Test("An uncoloured pass type gets nothing, which is a normal outcome")
    func noColour() {
        #expect(scheme.colour(for: guest("Jazz Performance Track")) == nil)
        #expect(scheme.colour(for: guest("")) == nil)
        #expect(BraceletColourScheme().colour(for: guest("Full Pass")) == nil)
        #expect(BraceletColourScheme().isEmpty)
    }

    /// Two long pass types can slug to the same document id, so the panel can
    /// produce two documents claiming one pass type. Last one wins rather than
    /// crashing — `Dictionary(uniqueKeysWith:)` would trap.
    @Test("Two documents claiming the same pass type do not crash the app")
    func duplicatePassTypes() {
        let scheme = BraceletColourScheme([
            BraceletColour(id: "a", passType: "Full Pass", hex: "#111111", name: "First"),
            BraceletColour(id: "b", passType: "full pass", hex: "#222222", name: "Second"),
        ])
        #expect(scheme.colour(for: guest("Full Pass"))?.name == "Second")
    }

    // MARK: Levels

    private let levelled = BraceletColourScheme([
        BraceletColour(id: "full-pass", passType: "Full Pass", hex: "#1E6BB8", name: "Sky Blue"),
        BraceletColour(id: "full-pass-pro", passType: "Full Pass", level: "Pro",
                       hex: "#1B1B1B", name: "Black"),
        BraceletColour(id: "party-pass", passType: "Party Pass", hex: "#C6453C", name: "Red"),
    ])

    @Test("A level with its own colour overrides the pass type's")
    func levelOverrides() {
        #expect(levelled.colour(for: guest("Full Pass", level: "Pro"))?.name == "Black")
    }

    /// The case that keeps the panel small: an organiser colours a pass type
    /// once, and everybody with it is covered whatever their level.
    @Test("A level without its own colour falls back to the pass type")
    func levelFallsBack() {
        #expect(levelled.colour(for: guest("Full Pass", level: "Advanced"))?.name == "Sky Blue")
        #expect(levelled.colour(for: guest("Full Pass", level: "Other"))?.name == "Sky Blue")
        #expect(levelled.colour(for: guest("Full Pass"))?.name == "Sky Blue")
    }

    @Test("A level does not leak across pass types")
    func levelIsPerPassType() {
        // "Pro" is coloured for Full Pass, and that must not reach a Party Pass.
        #expect(levelled.colour(for: guest("Party Pass", level: "Pro"))?.name == "Red")
    }

    @Test("A level on a pass type with no colour at all is still nothing")
    func levelWithoutPassType() {
        #expect(levelled.colour(for: guest("Jazz Performance Track", level: "Pro")) == nil)
    }

    // MARK: Contrast

    /// The bigger bar writes the colour's name on top of it, so this decides
    /// whether anybody can read it. A pale yellow with white text is the case
    /// that prompted it.
    @Test("Text flips to dark on a light colour and stays white on a dark one")
    func contrast() {
        let dark = { (hex: String) in
            BraceletColour(id: "x", passType: "p", hex: hex, name: "").prefersDarkText
        }
        #expect(dark("#FFE24D"))   // pale yellow
        #expect(dark("#FFFFFF"))
        #expect(dark("#C8A64B"))   // gold
        #expect(dark("#1B1B1B") == false)
        #expect(dark("#000000") == false)
        #expect(dark("#1E6BB8") == false)   // mid blue
        #expect(dark("#C6453C") == false)   // red
    }

    /// Luminance, not an average of the channels: a naive (r+g+b)/3 calls pure
    /// green dark and pure blue light, which is backwards for both.
    @Test("Green reads as light and blue as dark, which an average gets wrong")
    func luminanceNotAverage() {
        let dark = { (hex: String) in
            BraceletColour(id: "x", passType: "p", hex: hex, name: "").prefersDarkText
        }
        #expect(dark("#00FF00"))
        #expect(dark("#0000FF") == false)
    }

    // MARK: The label

    @Test("A named colour reads as its name, an unnamed one as its hex")
    func label() {
        #expect(BraceletColour(id: "a", passType: "x", hex: "#1E6BB8", name: "Sky Blue").label == "Sky Blue")
        // Not blank: an unnamed colour should look unnamed, and a hex is at
        // least something to read out over a radio.
        #expect(BraceletColour(id: "a", passType: "x", hex: "#1E6BB8", name: "").label == "#1E6BB8")
    }

    // MARK: Parsing

    @Test("A hex colour parses to its components")
    func parsesHex() {
        let white = BraceletColour.components(hex: "#FFFFFF")
        #expect(white?.red == 1 && white?.green == 1 && white?.blue == 1)

        let black = BraceletColour.components(hex: "#000000")
        #expect(black?.red == 0 && black?.green == 0 && black?.blue == 0)

        let red = BraceletColour.components(hex: "#FF0000")
        #expect(red?.red == 1 && red?.green == 0 && red?.blue == 0)
    }

    @Test("Lower case and a missing hash still parse")
    func lenientInput() {
        // The rules store upper case with a hash, but a document written before
        // that rule existed should still render.
        #expect(BraceletColour.components(hex: "#1e6bb8") != nil)
        #expect(BraceletColour.components(hex: "1E6BB8") != nil)
        #expect(BraceletColour.components(hex: " #1E6BB8 ") != nil)
    }

    /// No fallback colour anywhere, deliberately. A swatch of the wrong colour
    /// is worse than no swatch, because somebody hands over a wristband on the
    /// strength of it.
    @Test("Anything else is nil rather than a guess")
    func refusesJunk() {
        for bad in ["", "#", "red", "#F00", "#12345", "#1234567", "#GGGGGG", "blue"] {
            #expect(BraceletColour.components(hex: bad) == nil, "\(bad) should not parse")
        }
    }
}
