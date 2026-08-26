// BUG-034 Stage 2. `EffectsRender.spreadMask` casts shadow spread for shapes with
// no analytic outline by growing or shrinking the rendered ALPHA with Core Image.
// Two assumptions in that code are load-bearing and neither is obvious:
//
//   1. `side = |spread| * 2 + 1` on CIMorphologyRectangle{Maximum,Minimum} moves
//      the alpha edge by exactly |spread| pixels, matching what SVG's
//      `<feMorphology radius="|spread|">` does in a browser.
//   2. The structuring element really is a RECTANGLE. Picking the disc-shaped
//      CIMorphologyMaximum instead would look plausible on screen and quietly
//      disagree with the exported file — the exact class of bug BUG-034 exists
//      to close.
//
// This measures both against a known 40x40 square rather than trusting the docs.
// Run it with scripts/verify_morphology_spread.sh.

import Foundation
import CoreImage
import CoreGraphics

let ctxCI = CIContext(options: [.cacheIntermediates: false])

/// Draw a 40x40 opaque square centred in a 200x200 transparent bitmap.
func makeSource() -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let b = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
                      bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    b.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    b.fill(CGRect(x: 80, y: 80, width: 40, height: 40))
    return b.makeImage()!
}

/// Bounding box of pixels with alpha > 0.
func alphaBounds(_ img: CGImage) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    let w = img.width, h = img.height
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    var data = [UInt8](repeating: 0, count: w * h * 4)
    data.withUnsafeMutableBytes { raw in
        let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            if data[(y * w + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    return maxX < 0 ? nil : (minX, minY, maxX, maxY)
}

let source = makeSource()
let base = alphaBounds(source)!
print("source alpha box: x \(base.minX)...\(base.maxX)  y \(base.minY)...\(base.maxY)  (w \(base.maxX - base.minX + 1))")

func morph(_ name: String, reach: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    let side = reach * 2 + 1
    let input = CIImage(cgImage: source)
    guard let f = CIFilter(name: name) else { return nil }
    f.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    f.setValue(side, forKey: "inputWidth")
    f.setValue(side, forKey: "inputHeight")
    guard let out = f.outputImage?.cropped(to: input.extent),
          let cg = ctxCI.createCGImage(out, from: input.extent) else { return nil }
    return alphaBounds(cg)
}

print("\n--- CIMorphologyRectangleMaximum (dilate, positive spread) ---")
for r in [1, 2, 4, 8] {
    guard let b = morph("CIMorphologyRectangleMaximum", reach: r) else { print("r=\(r) FILTER FAILED"); continue }
    let growLeft = base.minX - b.minX, growRight = b.maxX - base.maxX
    let growTop = base.minY - b.minY, growBottom = b.maxY - base.maxY
    let ok = (growLeft == r && growRight == r && growTop == r && growBottom == r)
    print("r=\(r)  grew L\(growLeft) R\(growRight) T\(growTop) B\(growBottom)  \(ok ? "== r on every side  PASS" : "!= r  FAIL")")
}

print("\n--- CIMorphologyRectangleMinimum (erode, negative spread) ---")
for r in [1, 2, 4, 8] {
    guard let b = morph("CIMorphologyRectangleMinimum", reach: r) else { print("r=\(r) FILTER FAILED"); continue }
    let shrinkLeft = b.minX - base.minX, shrinkRight = base.maxX - b.maxX
    let shrinkTop = b.minY - base.minY, shrinkBottom = base.maxY - b.maxY
    let ok = (shrinkLeft == r && shrinkRight == r && shrinkTop == r && shrinkBottom == r)
    print("r=\(r)  shrank L\(shrinkLeft) R\(shrinkRight) T\(shrinkTop) B\(shrinkBottom)  \(ok ? "== r on every side  PASS" : "!= r  FAIL")")
}

// Shape check: does the dilated square stay a SQUARE (box element) rather than
// gaining rounded corners (disc element)? Compare against CIMorphologyMaximum.
print("\n--- box vs disc: corner test at r=8 ---")
func cornerAlpha(_ name: String, reach: Int) -> UInt8 {
    let side = reach * 2 + 1
    let input = CIImage(cgImage: source)
    let f = CIFilter(name: name)!
    f.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    if name.contains("Rectangle") {
        f.setValue(side, forKey: "inputWidth"); f.setValue(side, forKey: "inputHeight")
    } else {
        f.setValue(Float(reach), forKey: "inputRadius")
    }
    let out = f.outputImage!.cropped(to: input.extent)
    let cg = ctxCI.createCGImage(out, from: input.extent)!
    let w = cg.width, h = cg.height
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    var data = [UInt8](repeating: 0, count: w * h * 4)
    data.withUnsafeMutableBytes { raw in
        let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    // Extreme corner of the dilated bounding box: opaque for a box element,
    // transparent for a disc.
    let x = 80 - reach, y = 80 - reach
    return data[(y * w + x) * 4 + 3]
}
print("CIMorphologyRectangleMaximum corner alpha: \(cornerAlpha("CIMorphologyRectangleMaximum", reach: 8))  (box -> expect 255)")
print("CIMorphologyMaximum (disc) corner alpha:   \(cornerAlpha("CIMorphologyMaximum", reach: 8))  (disc -> expect 0)")
