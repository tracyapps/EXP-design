//
//  TurbulenceNoise.swift
//  EXP [design]
//
//  The SVG `<feTurbulence>` Perlin-noise algorithm, implemented verbatim from
//  the SVG 1.1 specification (§15.7.15, the reference C code), so the noise the
//  canvas draws is the SAME noise a browser generates for our exported
//  `feTurbulence` filters — one spec'd algorithm, two renderers.
//
//  Two products, both cached:
//   • `noiseImage`   — an RGBA tile of turbulence (grayscale when monochrome,
//                      independent R/G/B channels otherwise, alpha = 1). The
//                      caller composites it over a node with a blend mode +
//                      amount (see EffectsRender.drawNoise).
//   • `dissolveMask` — an alpha-only tile: turbulence thresholded at `amount`
//                      (the fraction dissolved away). Used as a clip mask
//                      around the node's own drawing.
//
//  Sampling is in NODE-LOCAL coordinates (origin = the node's own top-left), so
//  the texture travels with the node and dragging never regenerates the tile —
//  the cache key is (params + size), not position. This trades exact phase
//  parity with the SVG export (whose feTurbulence samples in user space) for
//  sane interactive performance; the statistics of the noise are identical.
//
//  PERFORMANCE (pan/zoom): generation is O(pixels × octaves) in pure Swift and
//  a tile can be up to `maxPixels`, so a COLD tile costs tens to hundreds of ms.
//  Two things keep that off the render thread:
//   1. The per-row loop is parallelised with `DispatchQueue.concurrentPerform`
//      (rows are disjoint writes into the pixel buffer), so a cold tile uses
//      every core.
//   2. `noiseImage` / `dissolveMask` NEVER block. On a cache miss they return
//      nil (the caller skips the effect for that frame) and kick the generation
//      onto a background queue; when the tile lands they post
//      `tileReadyNotification` so the canvas redraws with the effect now warm.
//      During a fast pan, grain therefore "pops in" a frame later instead of
//      freezing the gesture for seconds. This path is canvas-only — PNG/PDF/SVG
//      export renders turbulence via its own `feTurbulence`, never these tiles —
//      so there is no export-fidelity risk in being async here.
//
//  Generation cost is O(pixels × octaves) in pure Swift, so results are cached
//  (small LRU below) and the tile is capped at `maxPixels`; larger nodes get a
//  proportionally lower-res tile scaled up at draw time (interpolation .none,
//  so grain stays crisp rather than going soft).
//

import CoreGraphics
import Foundation

enum TurbulenceNoise {

    // MARK: SVG-spec pseudo-random lattice (per seed, cached)

    /// The gradient lattice `init(seed)` builds in the spec. Depends only on
    /// the seed, so it's cached separately from the rendered tiles.
    private final class Lattice {
        static let bSize = 256
        // [channel][index] gradient pairs; lattice selector permutation.
        var selector = [Int](repeating: 0, count: bSize + bSize + 2)
        var gradient = [[(Double, Double)]](repeating: [(Double, Double)](repeating: (0, 0), count: bSize + bSize + 2), count: 4)

        init(seed: Int) {
            // Spec PRNG: lehmer minstd (a=16807, m=2^31-1) with the spec's
            // exact seed clamping.
            let m: Int64 = 2147483647, a: Int64 = 16807, q: Int64 = 127773, r: Int64 = 2836
            var s = Int64(seed)
            if s <= 0 { s = -(s % (m - 1)) + 1 }
            if s > m - 1 { s = m - 1 }
            func rand() -> Int64 {
                var result = a * (s % q) - r * (s / q)
                if result <= 0 { result += m }
                s = result
                return result
            }
            let b = Self.bSize
            for k in 0..<4 {
                for i in 0..<b {
                    if k == 0 { selector[i] = i }
                    let gx = Double((Int(rand()) % (b + b)) - b) / Double(b)
                    let gy = Double((Int(rand()) % (b + b)) - b) / Double(b)
                    let len = (gx * gx + gy * gy).squareRoot()
                    gradient[k][i] = len > 0 ? (gx / len, gy / len) : (1, 0)
                }
            }
            var i = b - 1
            while i > 0 {
                let k = selector[i]
                let j = Int(rand()) % b
                selector[i] = selector[j]
                selector[j] = k
                i -= 1
            }
            for i in 0..<(b + 2) {
                selector[b + i] = selector[i]
                for k in 0..<4 { gradient[k][b + i] = gradient[k][i] }
            }
        }
    }

    private static let latticeCache = NSCache<NSNumber, Lattice>()
    private static func lattice(seed: Int) -> Lattice {
        if let hit = latticeCache.object(forKey: NSNumber(value: seed)) { return hit }
        let made = Lattice(seed: seed)
        latticeCache.setObject(made, forKey: NSNumber(value: seed))
        return made
    }

    // MARK: noise2 + turbulence (spec §15.7.15)

    private static let perlinN = 4096.0
    private static let bm = 255

    /// One octave of 2-D gradient noise for one color channel, in [-1, 1].
    private static func noise2(_ lat: Lattice, _ channel: Int, _ x: Double, _ y: Double) -> Double {
        var t = x + perlinN
        let bx0 = Int(t) & bm, bx1 = (bx0 + 1) & bm
        let rx0 = t - t.rounded(.down), rx1 = rx0 - 1.0
        t = y + perlinN
        let by0 = Int(t) & bm, by1 = (by0 + 1) & bm
        let ry0 = t - t.rounded(.down), ry1 = ry0 - 1.0
        let i = lat.selector[bx0], j = lat.selector[bx1]
        let b00 = lat.selector[i + by0], b10 = lat.selector[j + by0]
        let b01 = lat.selector[i + by1], b11 = lat.selector[j + by1]
        let sx = rx0 * rx0 * (3.0 - 2.0 * rx0)
        let sy = ry0 * ry0 * (3.0 - 2.0 * ry0)
        let g = lat.gradient[channel]
        var u = rx0 * g[b00].0 + ry0 * g[b00].1
        var v = rx1 * g[b10].0 + ry0 * g[b10].1
        let a = u + sx * (v - u)
        u = rx0 * g[b01].0 + ry1 * g[b01].1
        v = rx1 * g[b11].0 + ry1 * g[b11].1
        let b = u + sx * (v - u)
        return a + sy * (b - a)
    }

    /// Summed octaves for one channel at a point (model coords), already mapped
    /// to display range [0, 1]: fractalNoise → (sum+1)/2, turbulence → |sum|.
    private static func sample(_ lat: Lattice, channel: Int, x: Double, y: Double,
                               freq: Double, octaves: Int, fractal: Bool) -> Double {
        var vx = x * freq, vy = y * freq
        var ratio = 1.0, sum = 0.0
        for _ in 0..<max(1, octaves) {
            let n = noise2(lat, channel, vx, vy)
            sum += (fractal ? n : abs(n)) / ratio
            vx *= 2; vy *= 2; ratio *= 2
        }
        let v = fractal ? (sum + 1.0) / 2.0 : sum
        return min(1.0, max(0.0, v))
    }

    // MARK: Tile cache

    /// Everything a tile's pixels depend on. Position deliberately absent.
    private struct Key: Hashable {
        let kind: String        // "noise" | "mask"
        let type: Effect.TurbulenceType
        let freq: Double
        let octaves: Int
        let seed: Int
        let mono: Bool
        let threshold: Double   // dissolve only; -1 for noise tiles
        let w: Int, h: Int
    }
    private static var tileCache: [Key: CGImage] = [:]
    private static var tileOrder: [Key] = []          // LRU, oldest first
    private static let tileLock = NSLock()             // guards ALL mutable state below
    private static let maxTiles = 48
    /// Cap on generated pixels; larger nodes get a scaled-down tile.
    private static let maxPixels = 2_097_152           // ≈ 1448×1448

    // Pending (requested but not yet generated) work, oldest first. Drained
    // NEWEST-first (LIFO) by a single worker: dragging an inspector slider mints
    // a fresh Key every tick, and we want the value the user SETTLES on — the
    // newest — generated first, not stuck behind a backlog of superseded ticks.
    // `maxPending` drops the oldest superseded work so the queue can't back up.
    private static var pendingKeys: [Key] = []
    private static var pendingMakes: [Key: @Sendable () -> CGImage?] = [:]
    private static var generatingKey: Key?             // the one tile being made right now
    private static var workerRunning = false
    private static let maxPending = 6

    /// Background queue for cold-tile generation. A SINGLE worker drains the
    /// pending stack: each tile already saturates the cores via `concurrentPerform`,
    /// so one-at-a-time avoids thread oversubscription when several nodes reveal.
    private static let genQueue = DispatchQueue(label: "app.exp.turbulence.gen", qos: .userInitiated)

    /// Posted (on the main queue) whenever a background-generated tile lands, so
    /// each canvas can drop its pan/zoom snapshot and redraw with the effect now
    /// cache-warm. See `CanvasNSView.noiseTileBecameReady`.
    static let tileReadyNotification = Notification.Name("EXPTurbulenceTileReady")

    private static func store(_ key: Key, _ img: CGImage) {
        tileCache[key] = img
        tileOrder.removeAll { $0 == key }
        tileOrder.append(key)
        while tileOrder.count > maxTiles {
            tileCache.removeValue(forKey: tileOrder.removeFirst())
        }
    }

    /// Non-blocking cache: returns a warm tile immediately, or nil while it
    /// generates in the background. Callers MUST treat nil as "skip this effect
    /// for this frame." When the tile is ready it's stored and
    /// `tileReadyNotification` is posted on the main queue. `make` runs off the
    /// render thread and must capture only value types (no `Effect`, no view state).
    private static func cachedAsync(_ key: Key, make: @escaping @Sendable () -> CGImage?) -> CGImage? {
        tileLock.lock()
        if let hit = tileCache[key] { tileLock.unlock(); return hit }
        if key == generatingKey { tileLock.unlock(); return nil }   // already being made
        // Insert / promote as the newest pending request.
        if pendingMakes[key] == nil { pendingKeys.append(key) }
        else { pendingKeys.removeAll { $0 == key }; pendingKeys.append(key) }
        pendingMakes[key] = make
        // Drop the oldest superseded work so a fast slider drag can't pile up.
        while pendingKeys.count > maxPending {
            pendingMakes.removeValue(forKey: pendingKeys.removeFirst())
        }
        let launch = !workerRunning
        if launch { workerRunning = true }
        tileLock.unlock()
        if launch { genQueue.async { drainPending() } }
        return nil
    }

    /// Single background worker: pop the NEWEST pending key, generate it, store,
    /// notify, repeat until the stack is empty.
    private static func drainPending() {
        while true {
            tileLock.lock()
            guard let key = pendingKeys.popLast() else {   // LIFO: newest first
                workerRunning = false
                tileLock.unlock()
                return
            }
            let make = pendingMakes.removeValue(forKey: key)
            generatingKey = key
            tileLock.unlock()

            let img = make?()

            tileLock.lock()
            generatingKey = nil
            if let img { store(key, img) }
            tileLock.unlock()

            if img != nil {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: tileReadyNotification, object: nil)
                }
            }
        }
    }

    /// Pixel dimensions for a node size in model points, respecting `maxPixels`.
    /// Returns (widthPx, heightPx, pointsPerPixel).
    private static func tileDims(for size: CGSize) -> (Int, Int, Double)? {
        let w = max(1.0, size.width.rounded(.up)), h = max(1.0, size.height.rounded(.up))
        var scale = 1.0
        if w * h > Double(maxPixels) { scale = (Double(maxPixels) / (w * h)).squareRoot() }
        let pw = max(1, Int(w * scale)), ph = max(1, Int(h * scale))
        return (pw, ph, 1.0 / scale)
    }

    // MARK: Public tiles

    /// RGBA turbulence tile for a noise effect on a node of `size` model points.
    /// Monochrome = channel 0 in all of R/G/B; color = channels 0/1/2. Alpha 1
    /// throughout — the caller applies `effect.amount` via `ctx.setAlpha`.
    /// Non-blocking: nil on a cold cache (the caller skips noise this frame).
    static func noiseImage(for e: Effect, size: CGSize) -> CGImage? {
        guard let (pw, ph, step) = tileDims(for: size) else { return nil }
        let key = Key(kind: "noise", type: e.turbulenceType, freq: Double(e.frequency),
                      octaves: e.octaves, seed: e.seed, mono: e.monochrome,
                      threshold: -1, w: pw, h: ph)
        // Capture only value types so the background closure stays Sendable-clean.
        let seed = e.seed, oct = e.octaves, freq = Double(e.frequency)
        let mono = e.monochrome, fractal = e.turbulenceType == .fractalNoise
        return cachedAsync(key) {
            let lat = lattice(seed: seed)
            var buf = [UInt8](repeating: 255, count: pw * ph * 4)   // alpha stays 255
            buf.withUnsafeMutableBufferPointer { bufPtr in
                // Rows are disjoint writes, so the shared buffer is race-free even
                // though the compiler can't prove it — hence nonisolated(unsafe).
                nonisolated(unsafe) let bp = bufPtr
                DispatchQueue.concurrentPerform(iterations: ph) { py in
                    let y = (Double(py) + 0.5) * step
                    for px in 0..<pw {
                        let x = (Double(px) + 0.5) * step
                        let o = (py * pw + px) * 4
                        if mono {
                            let g = UInt8(sample(lat, channel: 0, x: x, y: y,
                                                 freq: freq, octaves: oct, fractal: fractal) * 255.0)
                            bp[o] = g; bp[o + 1] = g; bp[o + 2] = g
                        } else {
                            for k in 0..<3 {
                                bp[o + k] = UInt8(sample(lat, channel: k, x: x, y: y,
                                                         freq: freq, octaves: oct, fractal: fractal) * 255.0)
                            }
                        }
                    }
                }
            }
            return rgbaImage(buf, pw, ph)
        }
    }

    /// Grayscale luminance mask for `CGContext.clip(to:mask:)`: white where the
    /// node survives, black where it has dissolved. `e.amount` is the fraction
    /// removed (threshold). Non-blocking: nil on a cold cache.
    static func dissolveMask(for e: Effect, size: CGSize) -> CGImage? {
        guard let (pw, ph, step) = tileDims(for: size) else { return nil }
        let threshold = Double(min(1, max(0, e.amount)))
        let key = Key(kind: "mask", type: e.turbulenceType, freq: Double(e.frequency),
                      octaves: e.octaves, seed: e.seed, mono: true,
                      threshold: threshold, w: pw, h: ph)
        let seed = e.seed, oct = e.octaves, freq = Double(e.frequency)
        let fractal = e.turbulenceType == .fractalNoise
        return cachedAsync(key) {
            let lat = lattice(seed: seed)
            var buf = [UInt8](repeating: 0, count: pw * ph)
            buf.withUnsafeMutableBufferPointer { bufPtr in
                nonisolated(unsafe) let bp = bufPtr
                DispatchQueue.concurrentPerform(iterations: ph) { py in
                    let y = (Double(py) + 0.5) * step
                    for px in 0..<pw {
                        let x = (Double(px) + 0.5) * step
                        let v = sample(lat, channel: 0, x: x, y: y,
                                       freq: freq, octaves: oct, fractal: fractal)
                        bp[py * pw + px] = v >= threshold ? 255 : 0
                    }
                }
            }
            return grayMask(buf, pw, ph)
        }
    }

    // MARK: CGImage builders

    private static func rgbaImage(_ buf: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        let data = Data(buf)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// DeviceGray, no alpha — `clip(to:mask:)` treats it as a luminance mask
    /// (white = painted, black = clipped out).
    private static func grayMask(_ buf: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        let data = Data(buf)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
