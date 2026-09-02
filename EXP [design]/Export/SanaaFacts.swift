//
//  SanaaFacts.swift
//  EXP [design]
//
//  FEAT-055. A bounded, read-only translation from the document model to measured
//  design facts. This file deliberately contains no AppKit, SwiftUI, preferences,
//  consent, undo, or mutation surface. Interpretation belongs to the agent; EXP
//  reports values, criteria, heuristics, estimates, and omissions.
//

import Foundation
import CoreGraphics

enum SanaaFacts {
    enum Limits {
        static let maxNodes = 500
        static let maxTextPairs = 200
        static let maxGradientTextPairs = 200
        static let maxNonTextPairs = 150
        static let maxTextSizes = 300
        static let maxTargets = 200
        static let maxSpacingFacts = 250
        static let maxFonts = 100
        static let maxNotAssessed = 250
        static let maxDepth = 16
        static let maxEncodedBytes = 1_000_000
    }

    enum FactsError: LocalizedError {
        case invalidArtboard(UUID)
        case emptySelection

        var errorDescription: String? {
            switch self {
            case .invalidArtboard(let id):
                return "No artboard exists with id \(id.uuidString)"
            case .emptySelection:
                return "get_design_facts needs an artboardId or a non-empty current selection"
            }
        }
    }

    struct ScopeFact: Codable, Equatable {
        var kind: String
        var artboardIDs: [String]
        var nodeIDs: [String]
    }

    struct ColorFact: Codable, Equatable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double

        init(_ color: RGBAColor) {
            r = color.r; g = color.g; b = color.b; a = color.a
        }
    }

    struct TextContrastFact: Codable, Equatable {
        var nodeID: String
        var nodeName: String
        var instancePath: [String]
        var runIndex: Int
        var fontName: String
        var fontSize: Double
        var foreground: ColorFact
        var backing: ColorFact
        var flattenedForeground: ColorFact
        var flattenedBacking: ColorFact
        var backingSource: String
        var ratio: Double
        var threshold: Double
        var criterion: String
        var citation: String
        var largeText: Bool
        var largeTextClassification: String
        var estimated: Bool
        var estimateReason: String?
    }

    struct GradientTextContrastFact: Codable, Equatable {
        var nodeID: String
        var nodeName: String
        var instancePath: [String]
        var runIndex: Int
        var fontName: String
        var fontSize: Double
        var foreground: ColorFact
        var weakestBacking: ColorFact
        var flattenedForegroundAtWeakest: ColorFact
        var flattenedBackingAtWeakest: ColorFact
        var backingSource: String
        var gradientKind: String
        var minimumRatio: Double
        var medianRatio: Double
        var maximumRatio: Double
        var threshold: Double
        var meetingThresholdFraction: Double
        var sampleCount: Int
        var sampleGridColumns: Int
        var sampleGridRows: Int
        var weakestPointX: Double
        var weakestPointY: Double
        var samplingMethod: String
        var criterion: String
        var citation: String
        var largeText: Bool
        var largeTextClassification: String
        var estimated: Bool
        var estimateReason: String
    }

    struct NonTextContrastFact: Codable, Equatable {
        var nodeID: String
        var nodeName: String
        var instancePath: [String]
        var role: String
        var foreground: ColorFact
        var backing: ColorFact
        var ratio: Double
        var threshold: Double
        var criterion: String
        var citation: String
        var backingSource: String
    }

    struct TextSizeFact: Codable, Equatable {
        var nodeID: String
        var nodeName: String
        var instancePath: [String]
        var runIndex: Int
        var fontName: String
        var fontSize: Double
    }

    struct TargetSizeFact: Codable, Equatable {
        var nodeID: String
        var nodeName: String
        var instancePath: [String]
        var width: Double
        var height: Double
        var units: String
        var role: String?
        var classification: String
        var rotation: Double
    }

    struct TargetSizeReference: Codable, Equatable {
        var minimumWidth: Double = 24
        var minimumHeight: Double = 24
        var units: String = "CSS px ≈ EXP points at 1×"
        var criterion: String = "WCAG 2.2 SC 2.5.8"
        var citation: String = "https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html"
        var exceptions: [String] = ["spacing", "equivalent", "inline", "userAgentControl", "essential"]
        var note: String = "Sizes are measurements, not pass/fail results; the listed exceptions require human context."
    }

    struct AutoLayoutGapFact: Codable, Equatable {
        var nodeID: String
        var nodeName: String
        var instancePath: [String]
        var direction: String
        var distribution: String
        var gap: Double?
    }

    struct SiblingDeltaFact: Codable, Equatable {
        var parentNodeID: String?
        var firstNodeID: String
        var secondNodeID: String
        var instancePath: [String]
        var deltaX: Double
        var deltaY: Double
        var edgeGapX: Double
        var edgeGapY: Double
    }

    struct SpacingInventory: Codable, Equatable {
        var note: String = "Descriptive geometry only; EXP has no spacing-token model and this is not rule checking."
        var autoLayoutGaps: [AutoLayoutGapFact] = []
        var siblingDeltas: [SiblingDeltaFact] = []
    }

    struct FontInventoryFact: Codable, Equatable {
        var fontName: String
        var sizes: [Double]
        var runCount: Int
    }

    struct NotAssessedFact: Codable, Equatable {
        var category: String
        var nodeID: String?
        var nodeName: String?
        var instancePath: [String]
        var runIndex: Int?
        var reason: String
    }

    struct CountFact: Codable, Equatable {
        var nodesVisited: Int = 0
        var textRuns: Int = 0
        var colorPairs: Int = 0
        var gradientColorPairs: Int = 0
        var nonTextPairs: Int = 0
        var targets: Int = 0
    }

    struct Report: Codable, Equatable {
        var schemaVersion: Int = 2
        var scope: ScopeFact
        var interpretation: String = "measured facts, not verdicts"
        var colorSpace: String = "sRGB"
        var colorSpaceNote: String = "EXP stores straight sRGB values; these facts do not claim Display-P3 appearance."
        var colorPairs: [TextContrastFact] = []
        var gradientColorPairs: [GradientTextContrastFact] = []
        var nonTextContrast: [NonTextContrastFact] = []
        var textSizes: [TextSizeFact] = []
        var smallestText: TextSizeFact?
        var targetSizes: [TargetSizeFact] = []
        var targetSizeReference = TargetSizeReference()
        var spacingInventory = SpacingInventory()
        var fontInventory: [FontInventoryFact] = []
        var heuristics: [String] = [
            "Bold and large-text classification uses fontName markers because TextRun stores no weight flag; every text pair labels that inference.",
            "Interactive-target classification uses NodeSemantics role/implicitRole, ComponentSource accessibility roles, and control relationships because the model stores no isControl flag.",
            "Native-gradient text contrast evaluates the authored gradient at a bounded grid over the text frame. The range is conservative geometry evidence, not exact glyph-pixel sampling; minimum ratio is the accessibility signal and median/maximum are diagnostic only."
        ]
        var notAssessed: [NotAssessedFact] = []
        var truncated: Bool = false
        var counts = CountFact()
    }

    private struct Root {
        var node: Node
        var artboard: Artboard?
        var backing: Backing
        var selectedNestedWithoutAncestors: Bool
    }

    private enum Backing {
        case solid(color: RGBAColor, source: String, estimated: Bool, translucentLayers: Int)
        case gradient(fill: GradientFill, rect: CGRect, opacity: Double,
                      baseColor: RGBAColor, source: String, alphaEstimated: Bool)
        case unresolved(String)
    }

    private struct FontAccumulator {
        var sizes = Set<Double>()
        var runCount = 0
    }

    private struct Builder {
        var document: Document
        var report: Report
        var fontAccumulator: [String: FontAccumulator] = [:]
        var controlSubjects = Set<UUID>()
        var stopped = false

        mutating func build(roots: [Root]) -> Report {
            controlSubjects = collectControlSubjects(in: document)
            recordSiblingDeltas(roots.map(\.node), parentID: nil, instancePath: [])
            for (index, root) in roots.enumerated() where !stopped {
                var base = root.backing
                if root.selectedNestedWithoutAncestors {
                    base = .unresolved("Selected nested layer was read without its ancestor backing; select its containing group or artboard for contrast facts.")
                }
                let preceding = roots.prefix(index).filter {
                    $0.artboard?.id == root.artboard?.id
                }.map(\.node)
                let sibling = root.selectedNestedWithoutAncestors ? nil
                    : resolvedBacking(for: root.node.frame, preceding: preceding,
                                      parentBacking: base)
                walk(node: root.node, artboard: root.artboard, parentBacking: base,
                     siblingBacking: sibling, parentRotation: 0,
                     instancePath: [], depth: 0)
            }
            report.fontInventory = fontAccumulator.map { name, value in
                FontInventoryFact(fontName: name, sizes: value.sizes.sorted(),
                                  runCount: value.runCount)
            }.sorted { $0.fontName.localizedStandardCompare($1.fontName) == .orderedAscending }
            if report.fontInventory.count > Limits.maxFonts {
                report.fontInventory = Array(report.fontInventory.prefix(Limits.maxFonts))
                report.truncated = true
            }
            report.smallestText = report.textSizes.min {
                if $0.fontSize != $1.fontSize { return $0.fontSize < $1.fontSize }
                if $0.nodeID != $1.nodeID { return $0.nodeID < $1.nodeID }
                return $0.runIndex < $1.runIndex
            }
            report.counts.colorPairs = report.colorPairs.count
            report.counts.gradientColorPairs = report.gradientColorPairs.count
            report.counts.nonTextPairs = report.nonTextContrast.count
            report.counts.targets = report.targetSizes.count
            enforceEncodedByteLimit()
            return report
        }

        mutating func walk(node: Node, artboard: Artboard?, parentBacking: Backing,
                           siblingBacking: Backing?, parentRotation: Double,
                           instancePath: [String], depth: Int) {
            guard !stopped else { return }
            guard depth <= Limits.maxDepth else {
                addNotAssessed(category: "tree", node: node, instancePath: instancePath,
                               reason: "Nested content exceeded the \(Limits.maxDepth)-level facts depth cap.")
                report.truncated = true
                return
            }
            guard report.counts.nodesVisited < Limits.maxNodes else {
                report.truncated = true
                stopped = true
                return
            }
            guard node.isVisible else { return }
            report.counts.nodesVisited += 1

            let clippedPath = instancePath.map { clip($0) }
            let totalRotation = parentRotation + node.rotation
            let backing = siblingBacking ?? parentBacking
            let roleInfo = effectiveRole(for: node)
            let interactive = isInteractive(roleInfo.role) || isControlSubject(node)
            if interactive { recordTarget(node, roleInfo: roleInfo, instancePath: clippedPath) }
            if let layout = node.autoLayout { recordAutoLayout(node, layout, instancePath: clippedPath) }

            switch node.content {
            case .text(let content):
                recordText(content, node: node, backing: backing,
                           totalRotation: totalRotation, instancePath: clippedPath)
            case .group(let children):
                if interactive {
                    recordNonText(node, role: roleInfo.role, backing: backing,
                                  instancePath: clippedPath)
                }
                let childBacking = backingApplying(node.autoPadding?.fill,
                                                   rect: CGRect(origin: .zero,
                                                                size: node.frame.size),
                                                   opacity: node.opacity,
                                                   blendMode: node.blendMode,
                                                   source: "AutoPadding fill on \(clip(node.name))",
                                                   over: backing)
                recordSiblingDeltas(children, parentID: node.id, instancePath: clippedPath)
                walkSiblings(children, artboard: artboard, parentBacking: childBacking,
                             parentRotation: totalRotation,
                             instancePath: instancePath, depth: depth + 1)
            case .instance(let instance):
                let source = document.source(for: instance.sourceID)
                if interactive {
                    recordInstanceNonText(node, instance: instance, source: source,
                                          role: roleInfo.role, backing: backing,
                                          instancePath: clippedPath)
                }
                guard source != nil else {
                    addNotAssessed(category: "instance", node: node,
                                   instancePath: clippedPath,
                                   reason: "Component source \(instance.sourceID.uuidString) could not be resolved.")
                    return
                }
                let resolved = document.resolvedChildren(of: instance)
                guard !resolved.isEmpty else {
                    addNotAssessed(category: "instance", node: node,
                                   instancePath: clippedPath,
                                   reason: "Component instance resolved to no visible children.")
                    return
                }
                let nextPath = instancePath + [node.id.uuidString]
                recordSiblingDeltas(resolved, parentID: node.id,
                                    instancePath: nextPath.map { clip($0) })
                walkSiblings(resolved, artboard: artboard, parentBacking: backing,
                             parentRotation: totalRotation,
                             instancePath: nextPath, depth: depth + 1)
            default:
                if interactive {
                    recordNonText(node, role: roleInfo.role, backing: backing,
                                  instancePath: clippedPath)
                }
            }
        }

        mutating func walkSiblings(_ nodes: [Node], artboard: Artboard?,
                                   parentBacking: Backing, parentRotation: Double,
                                   instancePath: [String], depth: Int) {
            for (index, node) in nodes.enumerated() where !stopped {
                let sibling = resolvedBacking(for: node.frame,
                                              preceding: Array(nodes.prefix(index)),
                                              parentBacking: parentBacking)
                walk(node: node, artboard: artboard, parentBacking: parentBacking,
                     siblingBacking: sibling, parentRotation: parentRotation,
                     instancePath: instancePath,
                     depth: depth)
            }
        }

        mutating func recordText(_ content: TextContent, node: Node, backing: Backing,
                                 totalRotation: Double, instancePath: [String]) {
            for (index, run) in content.runs.enumerated() where !run.string.isEmpty {
                report.counts.textRuns += 1
                let fontName = clip(run.fontName.isEmpty ? "System" : run.fontName)
                let sizeFact = TextSizeFact(nodeID: node.id.uuidString,
                                            nodeName: clip(node.name),
                                            instancePath: instancePath,
                                            runIndex: index, fontName: fontName,
                                            fontSize: Double(run.fontSize))
                if report.textSizes.count < Limits.maxTextSizes {
                    report.textSizes.append(sizeFact)
                } else {
                    report.truncated = true
                }
                var accumulator = fontAccumulator[fontName] ?? FontAccumulator()
                accumulator.sizes.insert(Double(run.fontSize))
                accumulator.runCount += 1
                fontAccumulator[fontName] = accumulator

                guard abs(totalRotation.truncatingRemainder(dividingBy: 360)) < 0.0001 else {
                    addNotAssessed(category: "textContrast", node: node,
                                   instancePath: instancePath, runIndex: index,
                                   reason: "Text is rotated; its actual adjacent pixels cannot be inferred safely from frame geometry.")
                    continue
                }
                var foreground = run.color
                foreground.a *= max(0, min(1, node.opacity))
                let bold = isBold(fontName)
                let large = run.fontSize >= 18 || (bold && run.fontSize >= 14)
                let classification: String
                if bold {
                    classification = "large=\(large); bold inferred from fontName marker (heuristic)"
                } else {
                    classification = "large=\(large); regular inferred because fontName matched no bold marker (heuristic)"
                }

                switch backing {
                case .solid(let backingColor, let backingSource,
                            let backingEstimated, _):
                    let reportValue = ContrastMath.report(foreground: foreground,
                                                          background: backingColor,
                                                          base: .white)
                    let estimated = foreground.a < 0.999999 || backingEstimated
                    let estimateReason = estimated
                        ? "estimated — alpha was flattened over \(backingSource); WCAG defines no alpha-blending method"
                        : nil
                    let fact = TextContrastFact(
                        nodeID: node.id.uuidString, nodeName: clip(node.name),
                        instancePath: instancePath, runIndex: index,
                        fontName: fontName, fontSize: Double(run.fontSize),
                        foreground: ColorFact(foreground), backing: ColorFact(backingColor),
                        flattenedForeground: ColorFact(reportValue.flattenedForeground),
                        flattenedBacking: ColorFact(reportValue.flattenedBackground),
                        backingSource: backingSource, ratio: reportValue.ratio,
                        threshold: large ? 3 : 4.5,
                        criterion: "WCAG 2.2 SC 1.4.3",
                        citation: "https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html",
                        largeText: large, largeTextClassification: classification,
                        estimated: estimated, estimateReason: estimateReason)
                    if report.colorPairs.count < Limits.maxTextPairs {
                        report.colorPairs.append(fact)
                    } else {
                        report.truncated = true
                    }
                case .gradient(let fill, let rect, let opacity, let baseColor,
                               let source, let alphaEstimated):
                    recordGradientText(run: run, runIndex: index, fontName: fontName,
                                       node: node, foreground: foreground,
                                       fill: fill, fillRect: rect, fillOpacity: opacity,
                                       baseColor: baseColor, backingSource: source,
                                       alphaEstimated: alphaEstimated,
                                       large: large, classification: classification,
                                       instancePath: instancePath)
                case .unresolved(let reason):
                    addNotAssessed(category: "textContrast", node: node,
                                   instancePath: instancePath, runIndex: index,
                                   reason: reason)
                }
            }
        }

        mutating func recordGradientText(run: TextRun, runIndex: Int,
                                         fontName: String, node: Node,
                                         foreground: RGBAColor,
                                         fill: GradientFill, fillRect: CGRect,
                                         fillOpacity: Double, baseColor: RGBAColor,
                                         backingSource: String, alphaEstimated: Bool,
                                         large: Bool, classification: String,
                                         instancePath: [String]) {
            let columns = min(25, max(5, Int(ceil(node.frame.width / 8))))
            let rows = min(9, max(3, Int(ceil(node.frame.height / 8))))
            var samples: [(ratio: Double, x: Double, y: Double,
                           backing: RGBAColor, value: ContrastReport)] = []
            samples.reserveCapacity(columns * rows)

            for row in 0..<rows {
                let y = (Double(row) + 0.5) / Double(rows)
                for column in 0..<columns {
                    let x = (Double(column) + 0.5) / Double(columns)
                    let point = CGPoint(x: node.frame.minX + CGFloat(x) * node.frame.width,
                                        y: node.frame.minY + CGFloat(y) * node.frame.height)
                    var color = gradientColor(fill, at: point, in: fillRect)
                    color.a *= fillOpacity
                    let backing = ContrastMath.opaque(color, over: baseColor)
                    let value = ContrastMath.report(foreground: foreground,
                                                    background: backing,
                                                    base: baseColor)
                    samples.append((value.ratio, x, y, backing, value))
                }
            }
            guard let weakest = samples.min(by: { $0.ratio < $1.ratio }) else { return }
            let ratios = samples.map(\.ratio).sorted()
            let middle = ratios.count / 2
            let median = ratios.count.isMultiple(of: 2)
                ? (ratios[middle - 1] + ratios[middle]) / 2
                : ratios[middle]
            let threshold = large ? 3.0 : 4.5
            let meeting = Double(ratios.filter { $0 >= threshold }.count) / Double(ratios.count)
            var reasons = [
                "estimated — native gradient colors are evaluated from authored stops and geometry, but a bounded text-frame grid approximates glyph coverage; minimum ratio is the accessibility signal"
            ]
            if foreground.a < 0.999999 || alphaEstimated {
                reasons.append("alpha was flattened over \(backingSource); WCAG defines no alpha-blending method")
            }
            let fact = GradientTextContrastFact(
                nodeID: node.id.uuidString, nodeName: clip(node.name),
                instancePath: instancePath, runIndex: runIndex,
                fontName: fontName, fontSize: Double(run.fontSize),
                foreground: ColorFact(foreground),
                weakestBacking: ColorFact(weakest.backing),
                flattenedForegroundAtWeakest: ColorFact(weakest.value.flattenedForeground),
                flattenedBackingAtWeakest: ColorFact(weakest.value.flattenedBackground),
                backingSource: backingSource, gradientKind: fill.kind.rawValue,
                minimumRatio: weakest.ratio, medianRatio: median,
                maximumRatio: ratios.last ?? weakest.ratio,
                threshold: threshold, meetingThresholdFraction: meeting,
                sampleCount: samples.count, sampleGridColumns: columns,
                sampleGridRows: rows, weakestPointX: weakest.x,
                weakestPointY: weakest.y,
                samplingMethod: "native gradient evaluated on a bounded cell-center grid over the text frame; normalized weakest point is relative to that frame",
                criterion: "WCAG 2.2 SC 1.4.3",
                citation: "https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html",
                largeText: large, largeTextClassification: classification,
                estimated: true, estimateReason: reasons.joined(separator: "; "))
            if report.gradientColorPairs.count < Limits.maxGradientTextPairs {
                report.gradientColorPairs.append(fact)
            } else {
                report.truncated = true
            }
        }

        private func gradientColor(_ fill: GradientFill, at point: CGPoint,
                                   in rect: CGRect) -> RGBAColor {
            let t: Double
            switch fill.kind {
            case .linear:
                let (start, end) = fill.linearPoints(in: rect)
                let dx = end.x - start.x, dy = end.y - start.y
                let lengthSquared = dx * dx + dy * dy
                if lengthSquared > 0.000000001 {
                    t = Double(((point.x - start.x) * dx + (point.y - start.y) * dy)
                               / lengthSquared)
                } else {
                    t = 0
                }
            case .radial:
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let radius = hypot(rect.width, rect.height) / 2
                t = radius > 0.000000001
                    ? Double(hypot(point.x - center.x, point.y - center.y) / radius)
                    : 0
            }
            return fill.color(at: t)
        }

        mutating func recordTarget(_ node: Node,
                                   roleInfo: (role: AriaRole?, source: String),
                                   instancePath: [String]) {
            let classification: String
            if let role = roleInfo.role {
                classification = "heuristic — \(roleInfo.source) role \(role.rawValue)"
            } else {
                classification = "heuristic — subject of a stored control relationship"
            }
            let fact = TargetSizeFact(nodeID: node.id.uuidString, nodeName: clip(node.name),
                                  instancePath: instancePath,
                                  width: Double(node.frame.width), height: Double(node.frame.height),
                                  units: "EXP points ≈ CSS px at 1×",
                                  role: roleInfo.role?.rawValue,
                                  classification: classification, rotation: node.rotation)
            if report.targetSizes.count < Limits.maxTargets {
                report.targetSizes.append(fact)
            } else {
                report.truncated = true
            }
        }

        mutating func recordNonText(_ node: Node, role: AriaRole?, backing: Backing,
                                    instancePath: [String]) {
            guard let paint = directFill(of: node) else {
                addNotAssessed(category: "nonTextContrast", node: node,
                               instancePath: instancePath,
                               reason: "Interactive component has no directly measurable solid fill; strokes, icons, and nested visuals need visual-context review.")
                return
            }
            recordNonTextPaint(paint, node: node, role: role, backing: backing,
                               instancePath: instancePath)
        }

        mutating func recordInstanceNonText(_ node: Node, instance: ComponentInstance,
                                            source: ComponentSource?, role: AriaRole?,
                                            backing: Backing, instancePath: [String]) {
            guard let source else { return }
            let resolved = document.resolvedChildren(of: instance)
            guard resolved.count == 1, let paint = directFill(of: resolved[0]) else {
                addNotAssessed(category: "nonTextContrast", node: node,
                               instancePath: instancePath,
                               reason: "Component instance has no single directly measurable solid root fill.")
                return
            }
            recordNonTextPaint(paint, node: node, role: role, backing: backing,
                               instancePath: instancePath,
                               sourceLabel: "resolved root fill of \(clip(source.name))")
        }

        mutating func recordNonTextPaint(_ paint: Paint, node: Node, role: AriaRole?,
                                         backing: Backing, instancePath: [String],
                                         sourceLabel: String? = nil) {
            guard node.blendMode == .normal else {
                addNotAssessed(category: "nonTextContrast", node: node,
                               instancePath: instancePath,
                               reason: "Component uses a non-normal blend mode, so adjacent color cannot be reduced to one reliable pair.")
                return
            }
            guard case .solid(var foreground) = paint else {
                addNotAssessed(category: "nonTextContrast", node: node,
                               instancePath: instancePath,
                               reason: "Component fill is a gradient; one contrast pair would be misleading.")
                return
            }
            foreground.a *= max(0, min(1, node.opacity))
            guard foreground.a >= 0.999999 else {
                addNotAssessed(category: "nonTextContrast", node: node,
                               instancePath: instancePath,
                               reason: "Component fill is translucent; non-text contrast is reported only for determinable solid adjacent colors.")
                return
            }
            guard case .solid(let background, let backingSource, let estimated, _) = backing,
                  !estimated else {
                let reason: String
                if case .unresolved(let value) = backing { reason = value }
                else { reason = "Backing requires alpha estimation; non-text contrast is reported only for determinable solid adjacent colors." }
                addNotAssessed(category: "nonTextContrast", node: node,
                               instancePath: instancePath, reason: reason)
                return
            }
            let ratio = ContrastMath.ratio(opaque: foreground, background)
            let fact = NonTextContrastFact(
                    nodeID: node.id.uuidString, nodeName: clip(node.name),
                    instancePath: instancePath, role: role?.rawValue ?? "controlRelationship",
                    foreground: ColorFact(foreground), backing: ColorFact(background),
                    ratio: ratio, threshold: 3,
                    criterion: "WCAG 2.2 SC 1.4.11",
                    citation: "https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html",
                    backingSource: sourceLabel.map { "\($0) over \(backingSource)" } ?? backingSource)
            if report.nonTextContrast.count < Limits.maxNonTextPairs {
                report.nonTextContrast.append(fact)
            } else {
                report.truncated = true
            }
        }

        mutating func recordAutoLayout(_ node: Node, _ layout: AutoLayout,
                                       instancePath: [String]) {
            let fact = AutoLayoutGapFact(nodeID: node.id.uuidString,
                                     nodeName: clip(node.name),
                                     instancePath: instancePath,
                                     direction: layout.direction.rawValue,
                                     distribution: layout.distribution.rawValue,
                                     gap: layout.distribution == .packed ? Double(layout.gap) : nil)
            if report.spacingInventory.autoLayoutGaps.count < Limits.maxSpacingFacts {
                report.spacingInventory.autoLayoutGaps.append(fact)
            } else {
                report.truncated = true
            }
        }

        mutating func recordSiblingDeltas(_ nodes: [Node], parentID: UUID?,
                                          instancePath: [String]) {
            guard nodes.count > 1 else { return }
            for pair in zip(nodes, nodes.dropFirst()) {
                let first = pair.0, second = pair.1
                let fact = SiblingDeltaFact(
                        parentNodeID: parentID?.uuidString,
                        firstNodeID: first.id.uuidString, secondNodeID: second.id.uuidString,
                        instancePath: instancePath,
                        deltaX: Double(second.frame.minX - first.frame.minX),
                        deltaY: Double(second.frame.minY - first.frame.minY),
                        edgeGapX: Double(second.frame.minX - first.frame.maxX),
                        edgeGapY: Double(second.frame.minY - first.frame.maxY))
                if report.spacingInventory.siblingDeltas.count < Limits.maxSpacingFacts {
                    report.spacingInventory.siblingDeltas.append(fact)
                } else {
                    report.truncated = true
                }
            }
        }

        mutating func addNotAssessed(category: String, node: Node?,
                                     instancePath: [String], runIndex: Int? = nil,
                                     reason: String) {
            let fact = NotAssessedFact(category: category, nodeID: node?.id.uuidString,
                                   nodeName: node.map { clip($0.name) },
                                   instancePath: instancePath, runIndex: runIndex,
                                   reason: clip(reason, limit: 300))
            if report.notAssessed.count < Limits.maxNotAssessed {
                report.notAssessed.append(fact)
            } else {
                report.truncated = true
            }
        }

        mutating func enforceEncodedByteLimit() {
            let encoder = JSONEncoder()
            func encodedCount(_ value: Report) -> Int {
                (try? encoder.encode(value).count) ?? Int.max
            }
            guard encodedCount(report) >= Limits.maxEncodedBytes else { return }
            report.truncated = true
            while encodedCount(report) >= Limits.maxEncodedBytes {
                if !report.spacingInventory.siblingDeltas.isEmpty {
                    report.spacingInventory.siblingDeltas.removeLast()
                } else if !report.notAssessed.isEmpty {
                    report.notAssessed.removeLast()
                } else if !report.textSizes.isEmpty {
                    report.textSizes.removeLast()
                } else if !report.colorPairs.isEmpty {
                    report.colorPairs.removeLast()
                } else if !report.targetSizes.isEmpty {
                    report.targetSizes.removeLast()
                } else if !report.nonTextContrast.isEmpty {
                    report.nonTextContrast.removeLast()
                } else { break }
            }
            report.counts.colorPairs = report.colorPairs.count
            report.counts.nonTextPairs = report.nonTextContrast.count
            report.counts.targets = report.targetSizes.count
            report.smallestText = report.textSizes.min { $0.fontSize < $1.fontSize }
        }

        private func effectiveRole(for node: Node) -> (role: AriaRole?, source: String) {
            if let role = node.semantics?.role { return (role, "NodeSemantics") }
            if let raw = node.semantics?.implicitRole, let role = AriaRole(rawValue: raw) {
                return (role, "NodeSemantics implicit")
            }
            if case .instance(let instance) = node.content,
               let role = document.source(for: instance.sourceID)?.a11y.role {
                return (role, "ComponentSource accessibility")
            }
            return (nil, "none")
        }

        private func isInteractive(_ role: AriaRole?) -> Bool {
            guard let role else { return false }
            switch role {
            case .button, .link, .checkbox, .radio, .switch, .textbox, .searchbox,
                 .slider, .spinbutton, .tab, .menuitem, .listbox, .option, .treeitem:
                return true
            default:
                return false
            }
        }

        private func isControlSubject(_ node: Node) -> Bool {
            if controlSubjects.contains(node.id) { return true }
            guard case .instance(let instance) = node.content,
                  let source = document.source(for: instance.sourceID) else { return false }
            return source.a11y.rootRelationships.contains { $0.kind == .controls }
        }

        private func directFill(of node: Node) -> Paint? {
            switch node.content {
            case .rectangle(let shape): return shape.fill
            case .ellipse(let shape): return shape.fill
            case .polygon(let shape): return shape.fill
            case .path(let shape): return shape.fill
            case .group: return node.autoPadding?.fill
            default: return nil
            }
        }

        private func resolvedBacking(for target: CGRect, preceding: [Node],
                                     parentBacking: Backing) -> Backing? {
            let candidates = preceding.reversed().filter {
                $0.isVisible && $0.frame.contains(target)
            }
            guard !candidates.isEmpty else { return nil }
            var backing = parentBacking
            var sawCandidate = false
            for node in candidates.reversed() {
                sawCandidate = true
                if node.blendMode != .normal {
                    backing = .unresolved("A covering layer uses a non-normal blend mode; adjacent color cannot be reduced to one pair.")
                    continue
                }
                switch node.content {
                case .image:
                    backing = .unresolved("Text or component is over an image layer; sample-level contrast is not available from model colors.")
                case .group where node.autoPadding?.fill == nil:
                    backing = .unresolved("A covering group has no single model-level backing color.")
                default:
                    guard let paint = directFill(of: node) else { continue }
                    backing = backingApplying(paint, rect: node.frame,
                                              opacity: node.opacity,
                                              blendMode: node.blendMode,
                                              source: "fill on \(clip(node.name))",
                                              over: backing)
                }
            }
            return sawCandidate ? backing : nil
        }

        private func backingApplying(_ paint: Paint?, rect: CGRect, opacity: Double,
                                     blendMode: BlendMode, source: String,
                                     over base: Backing) -> Backing {
            guard let paint else { return base }
            guard blendMode == .normal else {
                return .unresolved("A backing layer uses a non-normal blend mode; adjacent color cannot be reduced to one pair.")
            }
            if case .gradient(let fill) = paint {
                guard rect.width > 0, rect.height > 0 else {
                    return .unresolved("A gradient backing has empty geometry and cannot be sampled.")
                }
                guard case .solid(let baseColor, let baseSource, let baseEstimated,
                                  let layers) = base else {
                    return .unresolved("A native gradient sits over an unresolvable base; its rendered colors cannot be sampled reliably.")
                }
                let clampedOpacity = max(0, min(1, opacity))
                let translucent = clampedOpacity < 0.999999
                    || fill.sortedStops.contains { $0.color.a < 0.999999 }
                guard !translucent || (!baseEstimated && layers == 0) else {
                    return .unresolved("A translucent native gradient overlaps another translucent backing; stacked alpha cannot be sampled reliably.")
                }
                return .gradient(fill: fill, rect: rect, opacity: clampedOpacity,
                                 baseColor: baseColor,
                                 source: "\(source) over \(baseSource)",
                                 alphaEstimated: translucent)
            }
            guard case .solid(var color) = paint else { return base }
            color.a *= max(0, min(1, opacity))
            if color.a >= 0.999999 {
                color.a = 1
                return .solid(color: color, source: source, estimated: false,
                              translucentLayers: 0)
            }
            guard case .solid(let baseColor, let baseSource, let baseEstimated,
                              let layers) = base else {
                return .unresolved("A translucent backing sits over an unresolvable base; stacked alpha cannot be measured reliably.")
            }
            guard !baseEstimated && layers == 0 else {
                return .unresolved("Multiple translucent backing layers overlap; stacked alpha cannot be measured reliably.")
            }
            let flattened = ContrastMath.opaque(ContrastMath.flatten(color, over: baseColor),
                                                over: baseColor)
            return .solid(color: flattened,
                          source: "\(source) flattened over \(baseSource)",
                          estimated: true, translucentLayers: 1)
        }

        private func collectControlSubjects(in document: Document) -> Set<UUID> {
            var result = Set<UUID>()
            func anchors(_ values: [AnchoredRelationship]) {
                for value in values where value.kind == .controls {
                    result.insert(value.subject.nodeID)
                }
            }
            func nodes(_ values: [Node]) {
                for node in values {
                    if node.relationships.contains(where: { $0.kind == .controls }) {
                        result.insert(node.id)
                    }
                    anchors(node.anchoredRelationships)
                    if case .group(let children) = node.content { nodes(children) }
                }
            }
            for page in document.pages { anchors(page.anchoredRelationships); nodes(page.nodes) }
            for source in document.sources {
                anchors(source.anchoredRelationships)
                if source.a11y.rootRelationships.contains(where: { $0.kind == .controls }) {
                    result.insert(source.id)
                }
                nodes(source.children)
            }
            return result
        }

        private func isBold(_ fontName: String) -> Bool {
            let compact = fontName.lowercased().replacingOccurrences(of: " ", with: "")
            return ["bold", "semibold", "demibold", "demi", "black", "heavy",
                    "extrabold", "ultrabold"].contains { compact.contains($0) }
        }
    }

    static func report(document: Document, artboardID: UUID?,
                       selectedNodeIDs: Set<UUID>,
                       selectedArtboardIDs: Set<UUID>) throws -> Report {
        let scope: ScopeFact
        let roots: [Root]

        if let artboardID {
            guard let artboard = document.allArtboards.first(where: { $0.id == artboardID }),
                  let page = document.page(containingArtboard: artboardID) else {
                throw FactsError.invalidArtboard(artboardID)
            }
            let base = artboardBacking(artboard)
            roots = page.nodes.filter {
                document.owningArtboard(of: $0, on: page.id)?.id == artboardID
            }.map { Root(node: $0, artboard: artboard, backing: base,
                         selectedNestedWithoutAncestors: false) }
            scope = ScopeFact(kind: "artboard", artboardIDs: [artboardID.uuidString],
                              nodeIDs: [])
        } else {
            guard !selectedNodeIDs.isEmpty || !selectedArtboardIDs.isEmpty else {
                throw FactsError.emptySelection
            }
            var built: [Root] = []
            var included = Set<String>()
            for id in selectedArtboardIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let artboard = document.allArtboards.first(where: { $0.id == id }),
                      let page = document.page(containingArtboard: id) else { continue }
                let base = artboardBacking(artboard)
                for node in page.nodes where document.owningArtboard(of: node, on: page.id)?.id == id {
                    if included.insert(node.id.uuidString).inserted {
                        built.append(Root(node: node, artboard: artboard, backing: base,
                                          selectedNestedWithoutAncestors: false))
                    }
                }
            }
            for id in selectedNodeIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let located = locate(id, in: document) else { continue }
                if included.insert(located.node.id.uuidString).inserted {
                    built.append(Root(node: located.node, artboard: located.artboard,
                                      backing: located.artboard.map(artboardBacking)
                                        ?? .unresolved("Selected component-source layer has no artboard backing."),
                                      selectedNestedWithoutAncestors: located.nested))
                }
            }
            roots = built
            scope = ScopeFact(
                kind: "selection",
                artboardIDs: selectedArtboardIDs.map(\.uuidString).sorted(),
                nodeIDs: selectedNodeIDs.map(\.uuidString).sorted())
        }

        var builder = Builder(document: document, report: Report(scope: scope))
        return builder.build(roots: roots)
    }

    private static func artboardBacking(_ artboard: Artboard) -> Backing {
        switch artboard.background {
        case .gradient(let fill):
            let translucent = fill.sortedStops.contains { $0.color.a < 0.999999 }
            return .gradient(fill: fill, rect: artboard.frame, opacity: 1,
                             baseColor: .white,
                             source: "artboard background over white canvas base",
                             alphaEstimated: translucent)
        case .solid(var color):
            if color.a >= 0.999999 {
                color.a = 1
                return .solid(color: color, source: "artboard background",
                              estimated: false, translucentLayers: 0)
            }
            let flattened = ContrastMath.opaque(color, over: .white)
            return .solid(color: flattened,
                          source: "artboard background flattened over white canvas base",
                          estimated: true, translucentLayers: 1)
        }
    }

    private static func locate(_ id: UUID, in document: Document)
        -> (node: Node, artboard: Artboard?, nested: Bool)? {
        func walk(_ nodes: [Node], artboard: Artboard?, nested: Bool)
            -> (node: Node, artboard: Artboard?, nested: Bool)? {
            for node in nodes {
                if node.id == id { return (node, artboard, nested) }
                if case .group(let children) = node.content,
                   let found = walk(children, artboard: artboard, nested: true) {
                    return found
                }
            }
            return nil
        }
        for page in document.pages {
            for node in page.nodes {
                let artboard = document.owningArtboard(of: node, on: page.id)
                if node.id == id { return (node, artboard, false) }
                if case .group(let children) = node.content,
                   let found = walk(children, artboard: artboard, nested: true) {
                    return found
                }
            }
        }
        for source in document.sources {
            if let found = walk(source.children, artboard: nil, nested: true) { return found }
        }
        return nil
    }

    private static func clip(_ value: String, limit: Int = 120) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }
}
