//
//  Feedback.swift
//  EXP [design]
//
//  In-app bug / idea reporter (BACKLOG FEAT-003). Captures diagnostic CONTEXT
//  (version, OS, tool, selection, doc stats — never document content) and opens a
//  prefilled GitHub New Issue, with a website fallback + copy-to-clipboard. No
//  backend, no token. Dogfoods the design-system controls (EXPSegmented / .exp
//  field / .exp buttons).
//

import SwiftUI
import AppKit

enum FeedbackKind: Hashable { case bug, idea }

enum FeedbackConfig {
    /// Set to "owner/repo" once the GitHub repo exists → reports open a prefilled
    /// New Issue there. While nil, the primary action opens the website instead.
    static let githubRepo: String? = "tracyapps/EXP-design"
    static let website = URL(string: "https://expdesign.app/")!
}

/// Auto-captured, PII-free context for a report.
@MainActor
func captureFeedbackContext(app: AppState, document: ExpDocument) -> [(String, String)] {
    let info = Bundle.main.infoDictionary
    let ver = (info?["CFBundleShortVersionString"] as? String) ?? "?"
    let build = (info?["CFBundleVersion"] as? String) ?? "?"
    func count(_ nodes: [Node]) -> Int {
        nodes.reduce(0) { acc, n in
            if case .group(let kids) = n.content { return acc + 1 + count(kids) }
            return acc + 1
        }
    }
    let m = document.model
    return [
        ("App", "EXP \(ver) (\(build))"),
        ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
        ("Tool", app.tool.label),
        ("Selection", "\(app.selectedNodeIDs.count) layer(s), \(app.selectedArtboardIDs.count) artboard(s)"),
        ("Document", "\(m.pages.count) pages · \(m.allArtboards.count) artboards · \(m.pages.reduce(0) { $0 + count($1.nodes) }) nodes · \(m.sources.count) components"),
    ]
}

struct FeedbackReport {
    var kind: FeedbackKind
    var title: String
    var detail: String
    var context: [(String, String)]

    var labels: String { kind == .bug ? "bug,triage" : "feature,triage" }

    /// Markdown body (context appended so triage has repro environment).
    var markdown: String {
        var s = detail.isEmpty ? "" : detail + "\n\n"
        s += "---\n**Context** (auto-captured)\n"
        for (k, v) in context { s += "- \(k): \(v)\n" }
        return s
    }

    /// Prefilled GitHub New Issue when a repo is configured, else the website.
    func destination() -> URL {
        guard let repo = FeedbackConfig.githubRepo,
              var c = URLComponents(string: "https://github.com/\(repo)/issues/new") else {
            return FeedbackConfig.website
        }
        c.queryItems = [
            .init(name: "labels", value: labels),
            .init(name: "title", value: (kind == .bug ? "[Bug] " : "[Idea] ") + title),
            .init(name: "body", value: markdown),
        ]
        return c.url ?? FeedbackConfig.website
    }
}

struct FeedbackSheet: View {
    let app: AppState
    let document: ExpDocument
    @Binding var isPresented: Bool

    @State private var kind: FeedbackKind = .bug
    @State private var title = ""
    @State private var detail = ""

    private var context: [(String, String)] { captureFeedbackContext(app: app, document: document) }
    private var report: FeedbackReport { .init(kind: kind, title: title, detail: detail, context: context) }
    private var primaryLabel: String { FeedbackConfig.githubRepo != nil ? "Open GitHub Issue" : "Open Feedback Site" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send Feedback")
                .font(.expDocName).foregroundStyle(EXPColor.textPrimary)
            Text("Goes to the project tracker. No document content is included — just the stats below.")
                .font(.expLabel).foregroundStyle(EXPColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            EXPSegmented(selection: $kind, segments: [
                .init(value: .bug, label: "Bug"),
                .init(value: .idea, label: "Idea"),
            ])

            TextField("Title", text: $title).textFieldStyle(.exp)

            ZStack(alignment: .topLeading) {
                if detail.isEmpty {
                    Text(kind == .bug
                         ? "What happened, and the steps to reproduce…"
                         : "What's the idea, and what are you trying to do…")
                        .font(.expLabel).foregroundStyle(EXPColor.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $detail)
                    .font(.system(size: EXPType.small))
                    .scrollContentBackground(.hidden)
                    .frame(height: 110)
                    .padding(2)
            }
            .background(EXPColor.surfaceField,
                        in: RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous)
                .strokeBorder(EXPColor.borderStrong, lineWidth: 1))

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(context, id: \.0) { k, v in
                        Text("\(k): \(v)")
                            .font(.system(size: EXPType.mini)).foregroundStyle(EXPColor.textTertiary)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Included with your report").font(.expLabel).foregroundStyle(EXPColor.textSecondary)
            }

            HStack(spacing: 8) {
                Button("Copy report") { copy() }.buttonStyle(.exp(.secondary))
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.exp(.ghost))
                Button(primaryLabel) { submit() }.buttonStyle(.exp(.primary)).disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(EXPColor.surfaceRaised)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("## \(title)\n\n\(report.markdown)", forType: .string)
    }
    private func submit() {
        copy()   // also copy, so nothing's lost if the URL is long
        NSWorkspace.shared.open(report.destination())
        isPresented = false
    }
}
