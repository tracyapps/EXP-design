// Pre-integration engineering probe. Exercises Core Image, not EXP's renderer.
// No production document/model or filter pipeline is modified by this program.
import AppKit
import CoreImage

@main
enum VisualFeatureColorProbe {
    static func main() throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        // Explicitly premultiplied RGBA: opaque primaries/grays plus alpha edges.
        let pixels: [[UInt8]] = [
            [0, 0, 0, 255], [255, 255, 255, 255], [128, 128, 128, 255],
            [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
            [0, 0, 0, 0], [64, 64, 64, 128], [128, 0, 0, 128]
        ]
        let bytes = Data(pixels.flatMap { $0 })
        let provider = CGDataProvider(data: bytes as CFData)!
        let image = CGImage(width: pixels.count, height: 1, bitsPerComponent: 8,
                            bitsPerPixel: 32, bytesPerRow: pixels.count * 4,
                            space: colorSpace,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        let input = CIImage(cgImage: image, options: [.colorSpace: colorSpace])
        let context = CIContext(options: [.useSoftwareRenderer: true,
                                          .workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
        let identity: [Double] = [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0]
        let shadow = [0.08, 0.03, 0.26], highlight = [0.92, 1.0, 0.25]
        let weights = [0.2126, 0.7152, 0.0722]
        var duotone = [Double]()
        for channel in 0..<3 {
            let difference = highlight[channel] - shadow[channel]
            duotone += weights.map { difference * $0 } + [0, shadow[channel]]
        }
        duotone += [0, 0, 0, 1, 0]
        let swap: [Double] = [0,0,1,0,0, 0,1,0,0,0, 1,0,0,0,0, 0,0,0,1,0]
        let biased: [Double] = [1,0,0,0,0.1, 0,1,0,0,-0.1, 0,0,1,0,0, 0,0,0,1,0]
        let alphaScale: [Double] = [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,0.5,0]
        let cases = [("identity", identity), ("channel-swap", swap),
                     ("duotone", duotone), ("signed-bias", biased), ("alpha-scale", alphaScale)]
        var report: [[String: Any]] = []
        var failed = false
        for (name, matrix) in cases {
            let filter = CIFilter(name: "CIColorMatrix")!
            filter.setValue(input, forKey: kCIInputImageKey)
            for (row, key) in ["inputRVector", "inputGVector", "inputBVector", "inputAVector"].enumerated() {
                let i = row * 5
                filter.setValue(CIVector(x: matrix[i], y: matrix[i+1], z: matrix[i+2], w: matrix[i+3]), forKey: key)
            }
            filter.setValue(CIVector(x: matrix[4], y: matrix[9], z: matrix[14], w: matrix[19]), forKey: "inputBiasVector")
            guard let output = filter.outputImage else { throw NSError(domain: "VisualProbe", code: 1) }
            var actual = [UInt8](repeating: 0, count: pixels.count * 4)
            context.render(output, toBitmap: &actual, rowBytes: pixels.count * 4,
                           bounds: input.extent, format: .RGBA8, colorSpace: colorSpace)
            var largestError = 0
            var samples: [[String: Any]] = []
            for (index, pixel) in pixels.enumerated() {
                let alpha = Double(pixel[3]) / 255
                let source = (0..<3).map { alpha > 0 ? Double(pixel[$0]) / 255 / alpha : 0 } + [alpha]
                var transformed = [Double]()
                for row in 0..<4 {
                    let value = (0..<4).reduce(matrix[row*5+4]) { $0 + matrix[row*5+$1] * source[$1] }
                    transformed.append(min(1, max(0, value)))
                }
                let expected = (0..<4).map { channel in
                    Int((255 * transformed[channel] * (channel < 3 ? transformed[3] : 1)).rounded())
                }
                let observed = Array(actual[index*4..<index*4+4]).map(Int.init)
                largestError = max(largestError, zip(expected, observed).map { abs($0 - $1) }.max()!)
                samples.append(["inputPremultiplied": pixel.map(Int.init), "expected": expected, "actual": observed])
            }
            let passed = largestError <= 2
            failed = failed || !passed
            report.append(["name": name, "passed": passed, "maxByteError": largestError, "samples": samples])
            print("\(passed ? "PASS" : "FAIL"): \(name), max premultiplied-byte error \(largestError)")
        }
        if CommandLine.arguments.count == 2 {
            let path = URL(fileURLWithPath: CommandLine.arguments[1])
            try JSONSerialization.data(withJSONObject: ["scope": "Core Image-only, explicit sRGB; not EXP integration or SVG parity",
                                                       "results": report], options: [.prettyPrinted, .sortedKeys]).write(to: path)
        }
        exit(failed ? 1 : 0)
    }
}
