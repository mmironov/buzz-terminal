// Draws the app icon at 1024×1024 using the same tokens and typeface as the app,
// so the icon and the UI cannot drift apart.
//
//     swift makeicon.swift <Archivo.ttf> <out.png>

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: makeicon.swift <font.ttf> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let fontURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

let side = 1024.0

// Modernist tokens, from DesignSystem/Tokens.swift.
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: 1
    )
}
let accent = rgb(0xEC3013)   // sbAccent
let paper = rgb(0xF3F2F2)    // sbBackground

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil, width: Int(side), height: Int(side),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else { fatalError("could not create the bitmap context") }

// No rounded corners and no gradient: iOS masks the shape itself, and the design
// system uses radius 0 and flat fills everywhere.
ctx.setFillColor(accent)
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

// Archivo, at the heaviest weight its `wght` axis offers — the same axis the app
// drives at runtime rather than a separate bundled bold face.
// Register the file with the font manager first. Without this, a descriptor built
// from a font *name* cannot resolve it and CoreText silently substitutes a system
// face — which is how the first version of this drew Helvetica at Regular while
// asking for Archivo at 900. Silently: no error, just the wrong letterforms.
var registerError: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registerError) else {
    fatalError("could not register \(fontURL.path): \(registerError.map { $0.takeRetainedValue().localizedDescription } ?? "unknown")")
}

guard let dataProvider = CGDataProvider(url: fontURL as CFURL),
      let cgFont = CGFont(dataProvider),
      let psName = cgFont.postScriptName as String?
else { fatalError("could not read \(fontURL.path)") }

let wght = CTFontDescriptorCreateWithAttributes([
    kCTFontNameAttribute: psName as CFString,
    kCTFontVariationAttribute: [2003265652 as CFNumber: 900 as CFNumber] as CFDictionary,
] as CFDictionary)
let font = CTFontCreateWithFontDescriptor(wght, 540, nil)

// Assert rather than hope: a fallback would otherwise ship as the app's icon.
let resolved = CTFontCopyPostScriptName(font) as String
let variation = (CTFontCopyVariation(font) as? [CFNumber: CFNumber]) ?? [:]
let resolvedWeight = variation[2003265652 as CFNumber].map { "\($0)" } ?? "none"
print("requested \(psName) at wght 900 → got \(resolved), wght \(resolvedWeight)")
guard resolved.localizedCaseInsensitiveContains("archivo") else {
    fatalError("CoreText substituted \(resolved) for Archivo — refusing to draw the wrong typeface")
}

let text = "SB"
// CoreText attribute keys rather than the UIKit ones: this script links Foundation
// and CoreText only, so `.font` and `.kern` are not in scope.
let attributed = NSAttributedString(string: text, attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): paper,
    // Tight, as the display style does: -0.03em at this size.
    NSAttributedString.Key(kCTKernAttributeName as String): -540 * 0.03,
])
let line = CTLineCreateWithAttributedString(attributed)

// Optically centre on the glyph bounds, not on the font's line metrics — ascent
// and descent include room for characters this icon does not contain.
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
ctx.textPosition = CGPoint(
    x: (side - bounds.width) / 2 - bounds.minX,
    y: (side - bounds.height) / 2 - bounds.minY
)
CTLineDraw(line, ctx)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not encode the png") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(outURL.path)") }

print("wrote \(outURL.lastPathComponent) — \(Int(side))×\(Int(side)), glyph bounds \(Int(bounds.width))×\(Int(bounds.height))")
