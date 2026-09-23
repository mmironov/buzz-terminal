import CoreGraphics

/// How tall a row of the drinks grid is, given how many drinks there are and how
/// much room the grid has.
///
/// The bar's screen is read at arm's length by somebody with wet hands and a
/// queue, so two things are in tension: **the whole menu should be on one
/// screen** — scrolling to find the wine while three people wait is the failure
/// this exists to prevent — and **the words and the prices should be big**.
///
/// The resolution is that rows shrink, text does not. A menu with room to spare
/// gets `preferredRowHeight`; a longer one gets tighter rows, down to
/// `minimumRowHeight`, which is the shortest a card can be and still hold a name
/// and a price at the sizes the grid uses. Past that the grid scrolls rather
/// than shrinking the type, because a menu you cannot read is worse than a menu
/// you have to scroll.
///
/// Rows never grow beyond the preferred height. A four-drink bar would otherwise
/// get cards the size of playing cards, which reads as a mistake rather than as
/// generosity.
enum BarMenuLayout {

    /// Two, because a drink's name has to fit beside the price on a phone.
    static let columns = 2

    /// Between cards, both ways.
    static let spacing: CGFloat = 8

    /// A row when the menu leaves room. Was 82 before the bar asked for more of
    /// the menu at once, and the height came off the empty space under the name
    /// rather than out of the type.
    static let preferredRowHeight: CGFloat = 66

    /// The floor, and it is **measured, not chosen**: a card's name (19pt) over
    /// its price (16pt) and quantity (18pt), plus the card's own padding, comes
    /// to this. A smaller number here does not make a shorter row — the text
    /// pushes the card back out and the last row slides under the cart bar.
    /// Asking for 56 is exactly how that was discovered.
    ///
    /// So it moves whenever the type does, and it moved when the bar asked for
    /// bigger names: anything below this now has to come back out of the type.
    static let minimumRowHeight: CGFloat = 64

    /// Rows needed for a menu of `count` drinks.
    static func rowCount(forDrinks count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + columns - 1) / columns
    }

    /// The height every card on the grid gets.
    ///
    /// `availableHeight` is what the grid has between the header and the cart
    /// bar. A zero or nonsensical value — which is what a `GeometryReader`
    /// reports on its first pass — falls back to the preferred height rather
    /// than to something negative.
    static func rowHeight(forDrinks count: Int, availableHeight: CGFloat) -> CGFloat {
        let rows = rowCount(forDrinks: count)
        guard rows > 0, availableHeight.isFinite, availableHeight > 0 else { return preferredRowHeight }

        let fitted = (availableHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        return min(preferredRowHeight, max(minimumRowHeight, fitted))
    }

    /// True when the menu is on the screen in one piece at that height.
    ///
    /// Not used to lay anything out — the grid simply scrolls when it has to.
    /// It is here so the promise this file makes can be asserted in a test.
    static func fitsOnScreen(drinks count: Int, availableHeight: CGFloat) -> Bool {
        let rows = rowCount(forDrinks: count)
        guard rows > 0 else { return true }
        let height = rowHeight(forDrinks: count, availableHeight: availableHeight)
        return CGFloat(rows) * height + spacing * CGFloat(rows - 1) <= availableHeight
    }
}
