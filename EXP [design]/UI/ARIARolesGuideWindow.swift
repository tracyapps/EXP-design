//
//  ARIARolesGuideWindow.swift
//  EXP [design]
//
//  Focused first-party reference window. This intentionally has no address,
//  navigation, or search chrome: the guide owns those interactions itself.
//

import SwiftUI
import WebKit
import AppKit
import Combine

struct ARIARolesGuideWindow: View {
    static let sceneID = "aria-roles-guide"

    @StateObject private var model = ARIARolesGuideModel()

    var body: some View {
        ZStack {
            ARIARolesWebView(model: model)

            switch model.loadState {
            case .loading:
                ProgressView("Loading ARIA Roles Guide\u{2026}")
                    .controlSize(.small)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityAddTraits(.isModal)

            case .ready:
                EmptyView()

            case .failed(let message):
                ARIARolesGuideFailureView(message: message,
                                          retry: model.reload,
                                          openInBrowser: model.openInBrowser)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

@MainActor
private final class ARIARolesGuideModel: NSObject, ObservableObject, WKNavigationDelegate {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static let guideURL = URL(string: "https://expdesign.app/aria-roles/")!

    @Published private(set) var loadState: LoadState = .loading
    private weak var webView: WKWebView?

    func attach(to webView: WKWebView) {
        self.webView = webView
        loadGuide()
    }

    func detach(from webView: WKWebView) {
        guard self.webView === webView else { return }
        self.webView = nil
    }

    func reload() {
        loadState = .loading
        if let webView, webView.url != nil {
            webView.reload()
        } else {
            loadGuide()
        }
    }

    func openInBrowser() {
        NSWorkspace.shared.open(Self.guideURL)
    }

    private func loadGuide() {
        guard let webView else { return }
        loadState = .loading
        let request = URLRequest(url: Self.guideURL,
                                 cachePolicy: .reloadRevalidatingCacheData,
                                 timeoutInterval: 30)
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadState = .ready
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        showFailure(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        showFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadState = .failed("The guide stopped responding. You can reload it or open expdesign.app in your browser.")
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.scheme == "about" || isFirstPartyGuideURL(url) {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
            return
        }

        // W3C, MDN, mail links, and any future off-site references stay outside
        // EXP. The embedded surface never becomes an arbitrary web browser.
        if let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    private func isFirstPartyGuideURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "expdesign.app" || host == "www.expdesign.app" else {
            return false
        }
        return url.path == "/aria-roles" || url.path.hasPrefix("/aria-roles/")
    }

    private func showFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        loadState = .failed("The guide could not load from expdesign.app. Check your connection and try again.")
    }
}

private struct ARIARolesWebView: NSViewRepresentable {
    let model: ARIARolesGuideModel

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = model
        webView.allowsMagnification = true
        webView.setAccessibilityLabel("ARIA Roles Designer Guide")
        model.attach(to: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Void) {
        if let model = nsView.navigationDelegate as? ARIARolesGuideModel {
            model.detach(from: nsView)
        }
        nsView.navigationDelegate = nil
        nsView.stopLoading()
    }
}

private struct ARIARolesGuideFailureView: View {
    let message: String
    let retry: () -> Void
    let openInBrowser: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "network.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("ARIA Roles Guide is unavailable")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                Button("Open in Browser", action: openInBrowser)
                Button("Retry", action: retry)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}
