//
//  ColorMath.swift
//  EXP [design]
//
//  Color-space conversions + format parsing/printing. The model stores color as
//  sRGB `RGBAColor` (0…1); this layer converts to/from the spaces designers want
//  to read and type: HEX, RGB(A), HSL, CIE LCH, and OKLCH (oklch.com). Authoring
//  in a wide space (OKLCH) is supported by converting back to sRGB (gamut-clamped)
//  on the way into the model.
//
//  All tuples are sRGB unless noted. Hue is in degrees. Everything is pure.
//

import Foundation

enum ColorFormat: String, CaseIterable, Identifiable {
    case hex = "HEX", rgba = "RGB", hsl = "HSL", lch = "LCH", oklch = "OKLCH"
    var id: String { rawValue }
}

enum ColorMath {

    // MARK: HSB / HSV (used by the picker's saturation–brightness field)

    static func rgbToHSB(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d != 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        let s = mx == 0 ? 0 : d / mx
        return (h, s, mx)
    }

    static func hsbToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        if s == 0 { return (v, v, v) }
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let i = Int(hh)
        let f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    // MARK: HSL

    static func rgbToHSL(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if d != 0 {
            s = d / (1 - abs(2 * l - 1))
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (h, s, l)
    }

    static func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hh = ((h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 60
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(hh) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }

    // MARK: sRGB <-> linear

    static func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    static func toGamma(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    // MARK: OKLCH (via OKLab — Björn Ottosson)

    static func rgbToOKLCH(_ r: Double, _ g: Double, _ b: Double) -> (l: Double, c: Double, h: Double) {
        let lr = toLinear(r), lg = toLinear(g), lb = toLinear(b)
        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        let L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        let C = sqrt(a * a + bb * bb)
        var H = atan2(bb, a) * 180 / .pi
        if H < 0 { H += 360 }
        return (L, C, H)
    }

    static func oklchToRGB(_ L: Double, _ C: Double, _ H: Double) -> (Double, Double, Double) {
        let a = C * cos(H * .pi / 180), bb = C * sin(H * .pi / 180)
        let l_ = L + 0.3963377774 * a + 0.2158037573 * bb
        let m_ = L - 0.1055613458 * a - 0.0638541728 * bb
        let s_ = L - 0.0894841775 * a - 1.2914855480 * bb
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return (clamp01(toGamma(lr)), clamp01(toGamma(lg)), clamp01(toGamma(lb)))
    }

    // MARK: CIE LCH (CIELAB, D65)

    private static let xn = 0.95047, yn = 1.0, zn = 1.08883

    static func rgbToLCH(_ r: Double, _ g: Double, _ b: Double) -> (l: Double, c: Double, h: Double) {
        let lr = toLinear(r), lg = toLinear(g), lb = toLinear(b)
        let X = 0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb
        let Y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb
        let Z = 0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : (7.787 * t + 16.0 / 116.0) }
        let fx = f(X / xn), fy = f(Y / yn), fz = f(Z / zn)
        let L = 116 * fy - 16, a = 500 * (fx - fy), bb = 200 * (fy - fz)
        let C = sqrt(a * a + bb * bb)
        var H = atan2(bb, a) * 180 / .pi
        if H < 0 { H += 360 }
        return (L, C, H)
    }

    static func lchToRGB(_ L: Double, _ C: Double, _ H: Double) -> (Double, Double, Double) {
        let a = C * cos(H * .pi / 180), bb = C * sin(H * .pi / 180)
        let fy = (L + 16) / 116, fx = fy + a / 500, fz = fy - bb / 200
        func inv(_ t: Double) -> Double { let t3 = t * t * t; return t3 > 0.008856 ? t3 : (t - 16.0 / 116.0) / 7.787 }
        let X = xn * inv(fx), Y = yn * inv(fy), Z = zn * inv(fz)
        let lr = 3.2404542 * X - 1.5371385 * Y - 0.4985314 * Z
        let lg = -0.9692660 * X + 1.8760108 * Y + 0.0415560 * Z
        let lb = 0.0556434 * X - 0.2040259 * Y + 1.0572252 * Z
        return (clamp01(toGamma(lr)), clamp01(toGamma(lg)), clamp01(toGamma(lb)))
    }

    // MARK: Formatting (model RGBAColor → string)

    static func string(_ color: RGBAColor, _ format: ColorFormat) -> String {
        let r = color.r, g = color.g, b = color.b, a = color.a
        switch format {
        case .hex:
            let hex = String(format: "#%02X%02X%02X", i255(r), i255(g), i255(b))
            return a < 1 ? hex + String(format: "%02X", i255(a)) : hex
        case .rgba:
            return a < 1 ? "rgba(\(i255(r)), \(i255(g)), \(i255(b)), \(d2(a)))"
                         : "rgb(\(i255(r)), \(i255(g)), \(i255(b)))"
        case .hsl:
            let (h, s, l) = rgbToHSL(r, g, b)
            let base = "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%"
            return a < 1 ? base + " / \(d2(a)))" : base + ")"
        case .lch:
            let (l, c, h) = rgbToLCH(r, g, b)
            return "lch(\(d1(l)) \(d1(c)) \(Int(h.rounded())))"
        case .oklch:
            let (l, c, h) = rgbToOKLCH(r, g, b)
            return "oklch(\(d3(l)) \(d3(c)) \(Int(h.rounded())))"
        }
    }

    // MARK: Parsing (string → model RGBAColor), lenient. Returns nil if unusable.

    static func parse(_ raw: String, _ format: ColorFormat, currentAlpha: Double) -> RGBAColor? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        switch format {
        case .hex:   return parseHex(s)
        case .rgba:
            let n = numbers(s); guard n.count >= 3 else { return nil }
            return RGBAColor(r: clamp01(n[0] / 255), g: clamp01(n[1] / 255), b: clamp01(n[2] / 255),
                             a: n.count >= 4 ? clamp01(n[3]) : currentAlpha)
        case .hsl:
            let n = numbers(s); guard n.count >= 3 else { return nil }
            let (r, g, b) = hslToRGB(n[0], n[1] / 100, n[2] / 100)
            return RGBAColor(r: r, g: g, b: b, a: n.count >= 4 ? clamp01(n[3]) : currentAlpha)
        case .lch:
            let n = numbers(s); guard n.count >= 3 else { return nil }
            let (r, g, b) = lchToRGB(n[0], n[1], n[2])
            return RGBAColor(r: r, g: g, b: b, a: n.count >= 4 ? clamp01(n[3]) : currentAlpha)
        case .oklch:
            let n = numbers(s); guard n.count >= 3 else { return nil }
            let (r, g, b) = oklchToRGB(n[0], n[1], n[2])
            return RGBAColor(r: r, g: g, b: b, a: n.count >= 4 ? clamp01(n[3]) : currentAlpha)
        }
    }

    static func parseHex(_ s: String) -> RGBAColor? {
        var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 6 {
            return RGBAColor(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255,
                             b: Double(v & 0xFF) / 255, a: 1)
        } else {
            return RGBAColor(r: Double((v >> 24) & 0xFF) / 255, g: Double((v >> 16) & 0xFF) / 255,
                             b: Double((v >> 8) & 0xFF) / 255, a: Double(v & 0xFF) / 255)
        }
    }

    // MARK: helpers

    private static func numbers(_ s: String) -> [Double] {
        // Pull all numeric tokens (handles %, commas, slashes); % already scaled
        // by callers that divide by 100.
        let cleaned = s.replacingOccurrences(of: "%", with: " ")
        var out: [Double] = []
        var token = ""
        for ch in cleaned {
            if ch.isNumber || ch == "." || ch == "-" { token.append(ch) }
            else { if let d = Double(token) { out.append(d) }; token = "" }
        }
        if let d = Double(token) { out.append(d) }
        return out
    }

    static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
    private static func i255(_ v: Double) -> Int { Int((clamp01(v) * 255).rounded()) }
    private static func d1(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func d2(_ v: Double) -> String { String(format: "%.2f", v) }
    private static func d3(_ v: Double) -> String { String(format: "%.3f", v) }
}
