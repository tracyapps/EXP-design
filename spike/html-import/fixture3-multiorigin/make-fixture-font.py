"""Build a minimal but VALID woff2 for spike fixture 3.

Synthetic on purpose: no third-party typeface is redistributed, and the fixture
makes no claim to be a real font — it only has to parse, so that "the browser
fetched it and the manifest missed it" cannot be blamed on a parse failure.
"""
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

upm = 1000
glyphs = [".notdef", "space", "A", "B"]
cmap = {0x20: "space", 0x41: "A", 0x42: "B"}

fb = FontBuilder(upm, isTTF=True)
fb.setupGlyphOrder(glyphs)
fb.setupCharacterMap(cmap)

def box(x0, y0, x1, y1):
    pen = TTGlyphPen(None)
    pen.moveTo((x0, y0)); pen.lineTo((x1, y0)); pen.lineTo((x1, y1)); pen.lineTo((x0, y1))
    pen.closePath()
    return pen.glyph()

empty = TTGlyphPen(None).glyph()
fb.setupGlyf({".notdef": box(50, 0, 550, 700), "space": empty,
              "A": box(50, 0, 550, 700), "B": box(50, 0, 550, 500)})
fb.setupHorizontalMetrics({g: (600, 50) for g in glyphs})
fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({
    "familyName": "Fixture Brand",
    "styleName": "Regular",
    "psName": "FixtureBrand-Regular",
    "licenseDescription": "Synthetic test font generated for the EXP HTML-import spike. Not a typeface.",
})
fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
fb.setupPost()
fb.font.flavor = "woff2"
fb.save("/tmp/brand.woff2")
print("built")
