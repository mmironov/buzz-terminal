import CoreGraphics
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  The drinks grid sizes itself.
//
//  The bar asked for the whole menu on one screen, with bigger words on it. The
//  two pull against each other, and this is where the compromise is written
//  down: rows give way, type does not.
//
//  The numbers below use 576pt of grid — what an iPhone 17 Pro leaves between
//  the "Order" header and the cart bar.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("The bar menu grid")
struct BarMenuLayoutTests {

    /// The space the grid gets on the phone the bar actually uses.
    private let screen: CGFloat = 576

    @Test("Two drinks to a row, and an odd one gets a row of its own")
    func rowCount() {
        #expect(BarMenuLayout.rowCount(forDrinks: 0) == 0)
        #expect(BarMenuLayout.rowCount(forDrinks: 1) == 1)
        #expect(BarMenuLayout.rowCount(forDrinks: 10) == 5)
        #expect(BarMenuLayout.rowCount(forDrinks: 11) == 6)
    }

    @Test("THE ONE THAT MATTERS: a bar's whole menu is on one screen")
    func itFits() {
        // Ten drinks was the menu when this was asked for; sixteen still lands
        // in one piece, which is more than the festival bar has ever poured.
        for count in 1...16 {
            #expect(
                BarMenuLayout.fitsOnScreen(drinks: count, availableHeight: screen),
                "\(count) drinks should fit without scrolling"
            )
        }
    }

    @Test("Past that it scrolls rather than shrinking the type")
    func theFloorHolds() {
        // A menu of twenty is somebody else's bar, and the answer there is a
        // scroll — not cards too short to read at arm's length, which is the
        // failure the floor exists to prevent.
        let height = BarMenuLayout.rowHeight(forDrinks: 20, availableHeight: screen)
        #expect(height == BarMenuLayout.minimumRowHeight)
        #expect(BarMenuLayout.fitsOnScreen(drinks: 20, availableHeight: screen) == false)
    }

    @Test("THE ONE THAT BIT: the floor is what the text actually needs")
    func theFloorIsMeasured() {
        // A floor below the card's own content does not produce a shorter row.
        // The text pushes the card back out, every row is taller than the
        // arithmetic said, and the last one ends up under the cart bar — which
        // is what an 18-drink menu did on the simulator at a floor of 56.
        //
        // 64pt is what the cards measure at today's sizes, read off a render
        // rather than worked out on paper. **Anybody changing the type on the
        // card has to measure again** — this number is downstream of it.
        #expect(BarMenuLayout.minimumRowHeight >= 64)
    }

    @Test("A short menu does not get playing-card-sized rows")
    func rowsNeverGrow() {
        // The grid fills the space it is given, so without the ceiling four
        // drinks would each get a quarter of the screen and read as a bug.
        #expect(BarMenuLayout.rowHeight(forDrinks: 4, availableHeight: screen) == BarMenuLayout.preferredRowHeight)
        #expect(BarMenuLayout.rowHeight(forDrinks: 2, availableHeight: 2000) == BarMenuLayout.preferredRowHeight)
    }

    @Test("A long menu tightens before it gives up")
    func rowsTighten() {
        // The point of measuring at all: between the two limits the height is
        // whatever puts the last row on the screen.
        let sixteen = BarMenuLayout.rowHeight(forDrinks: 16, availableHeight: screen)
        #expect(sixteen < BarMenuLayout.preferredRowHeight)
        #expect(sixteen > BarMenuLayout.minimumRowHeight)
        // The row that pays for it: fifteen drinks and sixteen share a row
        // count, so the odd one out costs nothing.
        #expect(BarMenuLayout.rowHeight(forDrinks: 15, availableHeight: screen) == sixteen)
        // And it is monotone: adding drinks never makes the rows taller.
        var previous = CGFloat.greatestFiniteMagnitude
        for count in 1...30 {
            let height = BarMenuLayout.rowHeight(forDrinks: count, availableHeight: screen)
            #expect(height <= previous)
            previous = height
        }
    }

    @Test("THE TRAP: a first layout pass with no height yet")
    func degenerateHeight() {
        // `GeometryReader` reports zero before it has measured anything. Doing
        // the arithmetic anyway would hand SwiftUI a negative frame.
        #expect(BarMenuLayout.rowHeight(forDrinks: 10, availableHeight: 0) == BarMenuLayout.preferredRowHeight)
        #expect(BarMenuLayout.rowHeight(forDrinks: 10, availableHeight: -40) == BarMenuLayout.preferredRowHeight)
        #expect(BarMenuLayout.rowHeight(forDrinks: 10, availableHeight: .nan) == BarMenuLayout.preferredRowHeight)
        #expect(BarMenuLayout.rowHeight(forDrinks: 0, availableHeight: screen) == BarMenuLayout.preferredRowHeight)
    }

    @Test("The rows got shorter, which is what paid for the bigger type")
    func shorterThanBefore() {
        // 82pt was the old card. The height came out of the empty space under
        // the name, not off the name itself.
        #expect(BarMenuLayout.preferredRowHeight < 82)
        #expect(BarMenuLayout.minimumRowHeight < BarMenuLayout.preferredRowHeight)
    }
}
