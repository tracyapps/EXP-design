import Foundation
import CoreGraphics
import ImageIO

// The importer does not render text; deterministic metrics satisfy Document's
// shared model references in this headless executable.
extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        CGSize(width: maxWidth ?? 20, height: 20)
    }

    func measuredSize(boxWidth currentWidth: CGFloat) -> CGSize {
        box == .fixed ? measuredSize(maxWidth: currentWidth) : measuredSize()
    }
}

private func validate(_ nodes: [Node], in source: String) throws -> Int {
    var count = 0
    for node in nodes {
        let frame = node.frame
        guard frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width >= 0, frame.height >= 0 else {
            throw NSError(domain: "XDImporterCorpusCheck", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid frame in \(source): \(node.name)"])
        }
        count += 1
        if case .image(let image) = node.content {
            guard image.naturalSize.width > 0, image.naturalSize.height > 0,
                  CGImageSourceCreateWithData(image.data as CFData, nil) != nil else {
                throw NSError(domain: "XDImporterCorpusCheck", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid image in \(source): \(node.name)"])
            }
        }
        if case .group(let children) = node.content { count += try validate(children, in: source) }
    }
    return count
}

private func textTrackings(in nodes: [Node]) -> [CGFloat] {
    nodes.flatMap { node -> [CGFloat] in
        switch node.content {
        case .text(let text): return [text.tracking]
        case .group(let children): return textTrackings(in: children)
        default: return []
        }
    }
}

@main
private enum XDImporterCorpusCheck {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let input = arguments.first(where: { !$0.hasPrefix("--") })
            ?? "/Users/tapps/Desktop/test2/2.0 testing/XD-FILES"
        let showDetails = arguments.contains("--details")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory) else {
            throw NSError(domain: "XDImporterCorpusCheck", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No file or directory at \(input)"])
        }
        let root = URL(fileURLWithPath: input, isDirectory: isDirectory.boolValue)
        let files: [URL]
        if isDirectory.boolValue {
            files = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "xd" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } else {
            files = root.pathExtension.lowercased() == "xd" ? [root] : []
        }
        guard !files.isEmpty else {
            fputs("FAIL: no XD files in \(root.path)\n", stderr)
            exit(1)
        }

        var failures = 0
        var totalArtboards = 0
        var totalLayers = 0
        for file in files {
            let start = Date()
            do {
                let result = try XDImporter().read(from: file)
                let nodeCount = try validate(result.payload.nodes, in: file.lastPathComponent)
                if file.lastPathComponent == "keyboardshortcuts.xd" {
                    let trackings = textTrackings(in: result.payload.nodes)
                    guard result.report.unsupportedCount == 0,
                          result.report.mappedCounts["Image"] == 180,
                          result.report.mappedCounts["Line"] == 14,
                          result.report.mappedCounts["Text"] == 77,
                          trackings.contains(where: { $0 < 0 }),
                          trackings.allSatisfy({ abs($0) < 5 }) else {
                        throw NSError(domain: "XDImporterCorpusCheck", code: 4,
                                      userInfo: [NSLocalizedDescriptionKey:
                                        "keyboardshortcuts regression: expected 180 images, 14 lines, 77 text layers, normalized XD tracking, and no unsupported content"])
                    }
                }
                totalArtboards += result.payload.artboards.count
                totalLayers += nodeCount
                let seconds = Date().timeIntervalSince(start)
                let elapsed = String(format: "%.2f", seconds)
                print("PASS\t\(file.lastPathComponent)\tboards=\(result.payload.artboards.count)\tlayers=\(nodeCount)\tdesignAssets=\(result.payload.designLanguage.assets.count)\tissues=\(result.report.issues.count)\tseconds=\(elapsed)")
                if showDetails {
                    print(result.report.detailedText)
                    for board in result.payload.artboards {
                        print("  BOARD\t\(board.name)\t\(NSStringFromRect(board.frame))")
                    }
                    for i in result.payload.artboards.indices {
                        for j in result.payload.artboards.indices where j > i {
                            let a = result.payload.artboards[i], b = result.payload.artboards[j]
                            let overlap = a.frame.intersection(b.frame)
                            if !overlap.isNull, !overlap.isEmpty {
                                print("  OVERLAP\t\(a.name)\t\(b.name)\t\(NSStringFromRect(overlap))")
                            }
                        }
                    }
                }
            } catch {
                failures += 1
                print("FAIL\t\(file.lastPathComponent)\t\(error.localizedDescription)")
            }
        }
        guard failures == 0 else { exit(1) }

        let cancelled = InteropCancellationToken()
        cancelled.cancel()
        do {
            _ = try XDImporter().read(from: files[0], context: InteropContext(cancellation: cancelled))
            fputs("FAIL: pre-cancelled import unexpectedly decoded artwork\n", stderr)
            exit(1)
        } catch InteropCodecError.cancelled {
            // Expected: cancellation is checked before package I/O begins.
        }
        print("ok: \(files.count) real XD packages, \(totalArtboards) artboards, and \(totalLayers) layers decoded with finite native geometry")
    }
}
