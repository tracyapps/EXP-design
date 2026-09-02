//
//  SanaaPromptStarters.swift
//  EXP [design]
//
//  FEAT-050 — selection-aware prompt starters. These compose text for review in
//  Sanaa's existing panel; they do not call a model mutation path themselves.
//

import SwiftUI

enum SanaaPromptStarter: String, Identifiable, Sendable {
    case critique
    case complete
    case variations
    case repetitive
    case directions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .critique: return "Critique this"
        case .complete: return "Complete this"
        case .variations: return "Draw variations"
        case .repetitive: return "Do repetitive work"
        case .directions: return "Design directions"
        }
    }
}

struct SanaaPromptSelectionItem: Equatable, Sendable {
    var id: UUID
    var name: String
}

struct SanaaPromptContext: Equatable, Sendable {
    var pageID: UUID
    var pageName: String
    var nodes: [SanaaPromptSelectionItem]
    var selectedArtboards: [SanaaPromptSelectionItem]
    var parentArtboards: [SanaaPromptSelectionItem]

    var hasSelection: Bool { !nodes.isEmpty || !selectedArtboards.isEmpty }
    var targetArtboards: [SanaaPromptSelectionItem] {
        var seen = Set<UUID>()
        return (selectedArtboards + parentArtboards).filter { seen.insert($0.id).inserted }
    }
}

struct SanaaPromptRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    var starter: SanaaPromptStarter
    var context: SanaaPromptContext
}

private enum SanaaCompletePlacement: String, CaseIterable, Identifiable {
    case duplicate
    case direct

    var id: String { rawValue }
}

private enum SanaaVariationPlacement: String, CaseIterable, Identifiable {
    case newPage
    case samePage

    var id: String { rawValue }
}

enum SanaaPromptComposer {
    static func critique(_ context: SanaaPromptContext) -> String {
        common(context)
            + """

            Task: Critique this selection without changing the document. After the canvas reads above confirm the scope, call get_design_facts with no arguments before writing or reasoning about any finding. If the live selection does not match the recorded IDs above, stop and ask me to reselect it instead of critiquing different work. Then load the critique-framework, a11y-foundations, design-principles, and voice modules with get_design_guidance.

            Begin with an Overview of no more than four short bullets for the compact Sanaa panel. Keep UUIDs and raw URLs out of Overview. Then follow critique-framework's five groups in order: What works, Measured findings, Design observations, Open questions, and Couldn't assess. Give each detailed finding a stable short label such as S1, S2, and S3. Every measured finding must cite the exact fact value, node ID, criterion, and source returned by EXP; copy notAssessed limitations honestly. Format citations as descriptive Markdown links rather than exposed URLs. Keep judgment separate from measurements, give a rationale and tradeoff for design observations, and use the bundled voice rules. Do not call apply_edits or change the canvas. End with a short Next steps section that names the relevant finding labels; do not add a generic open-ended question. Mirror every actionable detailed finding into the exp-response metadata described below, including its exact returned element references and a focused follow-up prompt.
            """
    }

    static func complete(_ context: SanaaPromptContext, duplicate: Bool) -> String {
        let direction: String
        if duplicate {
            if context.targetArtboards.isEmpty {
                direction = "Create a new artboard on the same page beside the selected wall layers, reconstruct the selected work there, and complete only that new artboard. Do not modify the original layers."
            } else {
                direction = "Duplicate each target artboard with apply_edits using placement kind \"besideOriginal\", then complete only the duplicate or duplicates. Do not modify the originals."
            }
        } else {
            direction = "Complete the selected work directly in its existing artboard or wall location. Keep the changes inside the stated selection unless a necessary parent edit is explained first. This route may require in-place consent."
        }
        return common(context)
            + "\n\nTask: Complete this work. \(direction) Use one honest apply_edits summary so the whole change is one named Undo step."
    }

    static func variations(_ context: SanaaPromptContext,
                           count: Int,
                           newPage: Bool) -> String {
        let placement = newPage
            ? "Create \(count) distinct variations as new artboards on a new page with placement kind \"newPage\". Name the page \"Sanaa — <short topic> variations\", deriving <short topic> from the selected artboard names or visible content."
            : "Create \(count) distinct variations as new artboards on the current page with placement kind \"samePage\", arranged near the originals without covering existing work."
        return common(context)
            + "\n\nTask: Draw \(count) genuinely different variations. \(placement) Keep the originals unchanged. Vary meaningful design axes rather than making cosmetic copies, and use one honest apply_edits summary so the result is one named Undo step."
    }

    static func repetitive(_ context: SanaaPromptContext, task: String) -> String {
        common(context)
            + "\n\nTask: Do this repetitive work: \(task.trimmingCharacters(in: .whitespacesAndNewlines))\nApply it only to the selected items and any explicitly named descendants. This is in-place work and requires the designer's consent. If the instruction or scope is ambiguous, ask one concise question before calling apply_edits. Use one honest summary so the batch is one named Undo step."
    }

    static func directions(_ context: SanaaPromptContext) -> String {
        common(context)
            + """

            Task: Propose three genuinely distinct design directions for this selection without changing the document. After the canvas reads above confirm the scope, call get_design_facts with no arguments before analyzing or proposing a direction. If the live selection does not match the recorded IDs above, stop and ask me to reselect it instead of analyzing different work. Then load the directions, anti-generic, design-principles, style-profile, and voice modules with get_design_guidance.

            Begin with an Overview of no more than four short bullets for the compact Sanaa panel; keep UUIDs and raw URLs out of it. Ground the starting point in the measured facts, existing artboards, and Design Language tokens. For each direction, give a concept name; a from-to diff across at least three named design axes; one-line rationale; one-line tradeoff; and one subject-grounded signature element. Format citations as descriptive Markdown links rather than exposed URLs. Keep real content and states constant so the comparison is honest. Do not call apply_edits or change the canvas. End by handing the choice back to me and inviting me to push one axis further. Add one exp-response choice per direction so I can stage that direction's focused follow-up in the composer.
            """
    }

    private static func common(_ context: SanaaPromptContext) -> String {
        let nodes = formatted(context.nodes)
        let selectedBoards = formatted(context.selectedArtboards)
        let parentBoards = formatted(context.parentArtboards)
        return """
        Using the exp-design MCP server:
        1. Call get_selection to confirm the live selection.
        2. Call get_artboard for every target artboard listed below before proposing or drawing.
        3. Call get_tokens and preserve the document's Design Language colors and type styles where they apply.

        Canvas page: \(context.pageName) (\(context.pageID.uuidString))
        Selected nodes: \(nodes)
        Selected artboards: \(selectedBoards)
        Parent artboards of selected nodes: \(parentBoards)

        Use only node and artboard IDs supplied here or returned by EXP tools. Do not guess IDs or silently widen the scope.

        If the response presents actionable findings, exact canvas references, or two or more concrete choices, append exactly one machine-readable block at the very end. EXP hides a valid block and renders its controls; malformed metadata stays visible and creates no action. Use strict JSON with this shape:
        ```exp-response
        {"version":1,"findings":[{"label":"S1","title":"Short human title","elements":[{"nodeID":"FULL-UUID","name":"Current layer name","instancePath":["OUTER-INSTANCE-UUID"]}],"followUp":"A complete editable prompt focused on S1"}],"choices":[{"label":"Concise button label","prompt":"A complete editable prompt for this choice"}]}
        ```
        Omit irrelevant findings or choices by using an empty array. Include at most 20 findings, 20 elements per finding, and four choices. Only include IDs returned by EXP. `instancePath` is optional, but include the ordered instance IDs when a fact supplies it. Buttons only stage text for review; write prompts accordingly and never imply that clicking a button already changed the document.
        """
    }

    private static func formatted(_ items: [SanaaPromptSelectionItem]) -> String {
        guard !items.isEmpty else { return "none" }
        return items.map { "\($0.name) (\($0.id.uuidString))" }.joined(separator: ", ")
    }
}

@MainActor
struct SanaaPromptStarterSheet: View {
    let request: SanaaPromptRequest
    let app: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var completePlacement: SanaaCompletePlacement = .duplicate
    @State private var variationPlacement: SanaaVariationPlacement = .newPage
    @State private var variationCount = 3
    @State private var repetitiveTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: EXPMetric.lg) {
            VStack(alignment: .leading, spacing: EXPMetric.xs) {
                Text(request.starter.title)
                    .font(.system(size: EXPType.xl, weight: .semibold))
                    .foregroundStyle(EXPColor.textPrimary)
                Text("Sanaa will place a detailed prompt in the composer for you to review before sending.")
                    .font(.system(size: EXPType.small))
                    .foregroundStyle(EXPColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            starterOptions

            HStack {
                Text(selectionSummary)
                    .font(.system(size: EXPType.mini))
                    .foregroundStyle(EXPColor.textTertiary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add to composer") { addToComposer() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
                    .accessibilityHint("Closes this sheet, opens the Sanaa panel, and places the prompt in its editable composer")
            }
        }
        .padding(EXPMetric.xl)
        .frame(width: 500)
        .background(EXPColor.surfaceWindow)
    }

    @ViewBuilder
    private var starterOptions: some View {
        switch request.starter {
        case .critique, .directions:
            Text("This starter uses EXP's measured facts and bundled design notes. No canvas change is requested.")
                .font(.system(size: EXPType.small))
                .foregroundStyle(EXPColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .complete:
            VStack(alignment: .leading, spacing: EXPMetric.sm) {
                Text("Where should Sanaa work?")
                    .font(.system(size: EXPType.small, weight: .medium))
                Picker("Placement", selection: $completePlacement) {
                    Text("On a duplicate beside the original — safer")
                        .tag(SanaaCompletePlacement.duplicate)
                    Text("Directly on the selected work — requires consent")
                        .tag(SanaaCompletePlacement.direct)
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Duplicate preserves the original; direct work may change selected layers")
            }

        case .variations:
            VStack(alignment: .leading, spacing: EXPMetric.md) {
                Stepper("Number of variations: \(variationCount)", value: $variationCount, in: 1...8)
                    .accessibilityHint("Choose between one and eight editable artboards")
                Picker("Placement", selection: $variationPlacement) {
                    Text("On a new page — keeps the current page clear")
                        .tag(SanaaVariationPlacement.newPage)
                    Text("On this page near the originals")
                        .tag(SanaaVariationPlacement.samePage)
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Chooses which canvas page receives the variation artboards")
            }

        case .repetitive:
            VStack(alignment: .leading, spacing: EXPMetric.sm) {
                Text("What should Sanaa repeat or apply?")
                    .font(.system(size: EXPType.small, weight: .medium))
                TextEditor(text: $repetitiveTask)
                    .font(.system(size: EXPType.small))
                    .scrollContentBackground(.hidden)
                    .padding(EXPMetric.xs)
                    .frame(minHeight: 90)
                    .background(EXPColor.surfaceField,
                                in: RoundedRectangle(cornerRadius: EXPMetric.radiusField,
                                                     style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous)
                            .strokeBorder(EXPColor.borderStrong,
                                          lineWidth: EXPMetric.strokeHairline)
                    }
                    .accessibilityLabel("Repetitive work instruction")
                    .accessibilityHint("Describe the one operation Sanaa should apply to the selected items")
                Text("This is in-place work. EXP will still require your per-document drawing consent before anything changes.")
                    .font(.system(size: EXPType.mini))
                    .foregroundStyle(EXPColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canAdd: Bool {
        request.context.hasSelection
            && (request.starter != .repetitive
                || !repetitiveTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var selectionSummary: String {
        let nodeCount = request.context.nodes.count
        let boardCount = request.context.selectedArtboards.count
        return "Selection: \(nodeCount) layer\(nodeCount == 1 ? "" : "s"), \(boardCount) artboard\(boardCount == 1 ? "" : "s")"
    }

    private func addToComposer() {
        guard canAdd else { return }
        let prompt: String
        switch request.starter {
        case .critique:
            prompt = SanaaPromptComposer.critique(request.context)
        case .complete:
            prompt = SanaaPromptComposer.complete(
                request.context,
                duplicate: completePlacement == .duplicate)
        case .variations:
            prompt = SanaaPromptComposer.variations(
                request.context,
                count: variationCount,
                newPage: variationPlacement == .newPage)
        case .repetitive:
            prompt = SanaaPromptComposer.repetitive(request.context, task: repetitiveTask)
        case .directions:
            prompt = SanaaPromptComposer.directions(request.context)
        }

        dismiss()
        app.revealPanel(.sanaa)
        SanaaActivityController.shared.prepareDraft(prompt)
    }
}
