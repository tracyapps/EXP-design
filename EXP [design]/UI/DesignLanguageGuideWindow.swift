import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class DesignLanguageGuideWindow: NSWindowController, NSWindowDelegate {
    private static var openGuides: [ObjectIdentifier: DesignLanguageGuideWindow] = [:]
    private let documentID: ObjectIdentifier

    static func show(document: ExpDocument, title: String) {
        let id = ObjectIdentifier(document)
        if let guide = openGuides[id] {
            guide.showWindow(nil)
            guide.window?.makeKeyAndOrderFront(nil)
            return
        }
        let guide = DesignLanguageGuideWindow(document: document, title: title)
        openGuides[id] = guide
        guide.showWindow(nil)
        guide.window?.makeKeyAndOrderFront(nil)
    }

    private init(document: ExpDocument, title: String) {
        documentID = ObjectIdentifier(document)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1020, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "\(title) · Design Language Guide"
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: DLGuideView(document: document, title: title))
        host.sizingOptions = []
        window.contentViewController = host
        window.minSize = CGSize(width: 360, height: 380)
        window.delegate = self
        if let screen = NSApp.keyWindow?.screen ?? PanelHub.shared.activeEditorWindow?.screen ?? NSScreen.main {
            let available = screen.visibleFrame
            let width = min(1400, (available.width * 0.88).rounded(.down))
            let height = min(960, (available.height * 0.88).rounded(.down))
            window.setFrame(CGRect(x: available.midX - width / 2, y: available.midY - height / 2,
                                   width: width, height: height), display: false)
        } else {
            window.setContentSize(CGSize(width: 1120, height: 760))
            window.center()
        }
    }

    required init?(coder: NSCoder) { return nil }

    func windowWillClose(_ notification: Notification) {
        Self.openGuides.removeValue(forKey: documentID)
    }

    static func export(document: ExpDocument, title: String, parent: NSWindow?) {
        do {
            let guide = try DesignLanguageGuideBuilder.build(document: document.model, title: title)
            let html = try guide.html(template: DesignLanguageGuide.template())
            save(html, name: "\(title) – Design Language Guide.html", type: .html, parent: parent)
        } catch {
            presentError(error, parent: parent)
        }
    }

    static func exportFolder(document: ExpDocument, title: String, parent: NSWindow?) {
        do {
            let guide = try DesignLanguageGuideBuilder.build(document: document.model, title: title)
            let export = try DesignLanguageFolderExport(guide: guide, template: DesignLanguageGuide.template())
            let name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            chooseFolder(for: export, name: "\(name) – Design Language", parent: parent)
        } catch {
            presentError(error, parent: parent)
        }
    }

    private static func chooseFolder(for export: DesignLanguageFolderExport, name: String, parent: NSWindow?) {
        let panel = NSOpenPanel()
        panel.title = "Export Guide and Token Files"
        panel.prompt = "Export"
        panel.message = "Choose where to create the export folder."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        let field = NSTextField(string: name)
        field.setAccessibilityLabel("Export folder name")
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 290).isActive = true
        let caption = NSTextField(wrappingLabelWithString: export.files.map(\.name).joined(separator: " · "))
        caption.textColor = .secondaryLabelColor
        caption.preferredMaxLayoutWidth = 320
        let preview = NSStackView(views: [NSTextField(labelWithString: "New folder name"), field, caption])
        preview.orientation = .vertical
        preview.alignment = .leading
        preview.spacing = 6
        preview.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        preview.setFrameSize(preview.fittingSize)
        panel.accessoryView = preview
        panel.isAccessoryViewDisclosed = true

        let complete: (NSApplication.ModalResponse) -> Void = { [weak parent] result in
            guard result == .OK, let directory = panel.url else { return }
            do {
                let folder = try export.write(to: directory, folderName: field.stringValue)
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch {
                presentError(error, parent: parent)
            }
        }
        if let parent { panel.beginSheetModal(for: parent, completionHandler: complete) }
        else { panel.begin(completionHandler: complete) }
    }

    fileprivate static func save(_ content: String, name: String, type: UTType?, parent: NSWindow?) {
        let panel = NSSavePanel()
        if let type { panel.allowedContentTypes = [type] }
        panel.nameFieldStringValue = name.replacingOccurrences(of: "/", with: "-")
        panel.canCreateDirectories = true
        let complete: (NSApplication.ModalResponse) -> Void = { [weak parent] result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                presentError(error, parent: parent)
            }
        }
        if let parent { panel.beginSheetModal(for: parent, completionHandler: complete) }
        else { panel.begin(completionHandler: complete) }
    }

    private static func presentError(_ error: Error, parent: NSWindow?) {
        let alert = NSAlert(error: error)
        if let parent { alert.beginSheetModal(for: parent) }
        else { alert.runModal() }
    }
}

private struct DLGuideView: View {
    @ObservedObject var document: ExpDocument
    let title: String
    @State private var pending: DLGuideWebView.Content?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Menu {
                    Button("Guide HTML…") {
                        DesignLanguageGuideWindow.export(document: document, title: title, parent: NSApp.keyWindow)
                    }
                    Button("Guide and Token Files…") {
                        DesignLanguageGuideWindow.exportFolder(document: document, title: title, parent: NSApp.keyWindow)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(pending == nil)
            }
            .padding(8)
            Divider()
            ZStack {
                if let pending {
                    DLGuideWebView(content: pending)
                } else if error == nil {
                    ProgressView("Building Design Language Guide…")
                }
                if let error {
                    Text(error)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 340, minHeight: 340)
        .task(id: document.resolveGeneration) {
            do {
                if pending != nil { try await Task.sleep(for: .milliseconds(250)) }
                try Task.checkCancellation()
                let generation = document.resolveGeneration
                let template: String
                if let pending { template = pending.template }
                else { template = try DesignLanguageGuide.template() }
                let guide = try DesignLanguageGuideBuilder.build(document: document.model, title: title)
                pending = try .init(generation: generation, template: template, guide: guide)
                error = nil
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct DLGuideWebView: NSViewRepresentable {
    struct Content {
        let generation: Int
        let template: String
        let guide: DesignLanguageGuide
        let json: String

        init(generation: Int, template: String, guide: DesignLanguageGuide) throws {
            self.generation = generation
            self.template = template
            self.guide = guide
            json = try guide.json()
        }
    }

    let content: Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "designLanguageGuide")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.update(content, in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(content, in: view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "designLanguageGuide")
        view.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private var latest: Content?
        private var presented: Content?
        private var ready = false

        func update(_ content: Content, in view: WKWebView) {
            if latest == nil {
                latest = content
                load(in: view)
            } else {
                latest = content
                if ready { updatePage(in: view) }
            }
        }

        private func load(in view: WKWebView) {
            guard let latest, let html = try? latest.guide.html(template: latest.template, embedded: true) else { return }
            ready = false
            presented = latest
            view.loadHTMLString(html, baseURL: nil)
        }

        private func updatePage(in view: WKWebView) {
            guard let latest, presented?.generation != latest.generation else { return }
            presented = latest
            view.callAsyncJavaScript("window.expUpdateDesignLanguageGuide(json)", arguments: ["json": latest.json],
                                    in: nil, in: .page) { [weak self, weak view] result in
                if case .failure = result, let view { self?.load(in: view) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            updatePage(in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            load(in: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let view = message.webView,
                  let data = message.body as? [String: String], let action = data["action"] else { return }
            switch action {
            case "copy":
                guard let text = data["text"], let name = data["name"] else { return }
                NSPasteboard.general.clearContents()
                let copied = NSPasteboard.general.setString(text, forType: .string)
                view.callAsyncJavaScript("window.expGuideAnnounce(message)",
                                         arguments: ["message": copied ? "Copied \(name)." : "Could not copy \(name)."],
                                         in: nil, in: .page, completionHandler: nil)
            case "download":
                guard let name = data["filename"], let content = presented?.guide.files[name],
                      view.window?.attachedSheet == nil else { return }
                let type = UTType(filenameExtension: (name as NSString).pathExtension)
                DesignLanguageGuideWindow.save(content, name: name, type: type, parent: view.window)
            default:
                break
            }
        }
    }
}
