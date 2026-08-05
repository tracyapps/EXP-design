//
//  HTMLImportSpike.swift
//  EXP [design] — E0 spike harness (NOT shipped app code)
//
//  Answers one question that HTML-IMPORT-CONTRACT.md §2 leaves open:
//
//      WKWebView has no delegate that reports SUBRESOURCE requests. Pass 1 of
//      the two-pass trust model has to block everything AND record what was
//      attempted. Blocking is solved (WKContentRuleList). Recording is not.
//
//  So this harness implements every candidate recorder at once and prints which
//  ones actually fired, per resource. Whatever survives contact with the three
//  fixtures is the mechanism E1 gets built on; whatever a resource is missed by
//  is a blind spot that must stay named in §4 rather than be papered over.
//
//  Recorders, in the order they appear in the output:
//    D  DOM walk        — src/srcset/href/data attributes after the DOM settles
//    C  CSSOM walk      — url() in computed styles + @font-face src
//    I  Instrumentation — patched fetch / XMLHttpRequest / sendBeacon / Image
//    P  PerformanceObserver — "resource" entries, including blocked ones
//
//  Build and run via scripts/verify_html_import_spike.sh — it wraps the binary
//  in a throwaway .app bundle, because WKWebView is unreliable in a bare
//  command-line process.
//

import AppKit
import Foundation
import WebKit

// MARK: - Options

struct SpikeOptions {
    var url: URL
    /// Width × height pairs. Height feeds vh units and height media queries;
    /// the artboard would be cut to document height (contract §1.1).
    var viewports: [CGSize]
    /// Origins the user "trusted". Empty = pass 1 (discovery, loads nothing).
    var allowedOrigins: Set<String>
    /// Quiet period after `load` before extraction, so late requests are seen.
    var settleMs: Int
    var jsonOut: URL?
    var verbose: Bool

    static func parse(_ args: [String]) -> SpikeOptions? {
        var url: URL?
        var viewports: [CGSize] = [CGSize(width: 1440, height: 1024)]
        var allowed: Set<String> = []
        var settle = 1200
        var jsonOut: URL?
        var verbose = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
            switch arg {
            case "--url":
                guard let value = next() else { return nil }
                url = value.hasPrefix("http") ? URL(string: value)
                                              : URL(fileURLWithPath: value)
            case "--viewports":
                guard let value = next() else { return nil }
                viewports = value.split(separator: ",").compactMap { spec in
                    let parts = spec.lowercased().split(separator: "x")
                    guard parts.count == 2,
                          let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
                    return CGSize(width: w, height: h)
                }
                if viewports.isEmpty { return nil }
            case "--allow":
                guard let value = next() else { return nil }
                value.split(separator: ",").forEach { allowed.insert(String($0)) }
            case "--settle":
                guard let value = next(), let ms = Int(value) else { return nil }
                settle = ms
            case "--json":
                guard let value = next() else { return nil }
                jsonOut = URL(fileURLWithPath: value)
            case "--verbose":
                verbose = true
            case "--help", "-h":
                return nil
            default:
                FileHandle.standardError.write(Data("unknown argument: \(arg)\n".utf8))
                return nil
            }
            i += 1
        }
        guard let url else { return nil }
        return SpikeOptions(url: url, viewports: viewports, allowedOrigins: allowed,
                            settleMs: settle, jsonOut: jsonOut, verbose: verbose)
    }

    static let usage = """
    HTML-import spike probe (contract §2 / §4 / §10).

      --url <file-or-http-url>      the document to probe
      --viewports 393x852,1440x1024 one probe per viewport; manifest is the UNION
      --allow <origin[,origin...]>  origins to permit (omit for pass 1)
      --settle <ms>                 quiet period after load (default 1200)
      --json <path>                 machine-readable result
      --verbose                     per-resource recorder detail

    Pass 1 example (loads nothing but the document):
      probe --url http://127.0.0.1:8731/ --viewports 393x852,1440x1024

    Pass 2 example (origin A trusted; expect origin B to APPEAR):
      probe --url http://127.0.0.1:8731/ --allow http://127.0.0.1:8732
    """
}

// MARK: - Manifest

/// One resource the page wanted, plus which recorders saw it and at which
/// viewports. Both attributions are findings in their own right: the recorder
/// set decides the E1 mechanism, the viewport set proves §4's union manifest.
struct ManifestEntry: Codable {
    var url: String
    var origin: String
    var type: String
    var recorders: Set<String> = []
    var viewports: Set<String> = []
    /// viewport → recorders that saw it THERE. Unioning recorders and viewports
    /// separately loses the pairing, and the pairing is the whole question: a
    /// resource can be DECLARED at every viewport and REQUESTED at only one.
    var sightings: [String: [String]] = [:]
    var blocked: Bool = true

    /// D (DOM) and C (CSSOM) read what the page SAYS it wants. I (patched APIs)
    /// and P (PerformanceObserver) observe what it actually asked for. The
    /// distinction is not academic: in pass 1 nothing is fetched, so every entry
    /// is declaration-only by design — and in pass 2 a resource still listed as
    /// declaration-only at a given viewport is one that viewport never requested.
    static let declarationRecorders: Set<String> = ["D", "C"]

    func declared(at viewport: String) -> [String] {
        (sightings[viewport] ?? []).filter { Self.declarationRecorders.contains($0) }
    }
    func observed(at viewport: String) -> [String] {
        (sightings[viewport] ?? []).filter { !Self.declarationRecorders.contains($0) }
    }
}

struct ViewportResult: Codable {
    var viewport: String
    var nodeCount: Int
    var textNodeCount: Int
    var documentHeight: Double
    var rootRects: [String]
    var mediaQueryHits: [String]
    /// `scrollHeight` floors at the viewport height. Kept beside the real
    /// content height so the difference is visible rather than assumed.
    var viewportClampedHeight: Double
    var opaqueStylesheets: [String]
    /// Font FAMILIES the page loaded. Deliberately not manifest rows: the
    /// FontFaceSet never exposes the URL, so a family listed here with no
    /// corresponding manifest entry is a font that was fetched without ever
    /// being listed.
    var fontFaces: [String]
    var consoleErrors: [String]
}

struct SpikeResult: Codable {
    var url: String
    var pass: Int
    var allowedOrigins: [String]
    var entries: [ManifestEntry]
    var viewports: [ViewportResult]
    var notes: [String]
}

// MARK: - Injected JavaScript

enum SpikeJS {
    /// Runs at documentStart, before page script. Patches the request-making
    /// APIs and starts a PerformanceObserver. Deliberately records rather than
    /// prevents — blocking is the content rule list's job, and keeping the two
    /// separate is what makes a missed recording visible instead of silent.
    static let instrumentation = #"""
    (function () {
      var send = function (payload) {
        try { window.webkit.messageHandlers.expSpike.postMessage(payload); } catch (e) {}
      };
      var note = function (url, type, recorder) {
        if (!url) return;
        try { url = new URL(url, document.baseURI).href; } catch (e) { return; }
        send({ kind: "resource", url: url, type: type, recorder: recorder });
      };

      var nativeFetch = window.fetch;
      if (nativeFetch) {
        window.fetch = function (input, init) {
          var u = (typeof input === "string") ? input : (input && input.url);
          note(u, "fetch", "I");
          return nativeFetch.apply(this, arguments);
        };
      }

      var xhrOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        note(url, "fetch", "I");
        return xhrOpen.apply(this, arguments);
      };

      if (navigator.sendBeacon) {
        var beacon = navigator.sendBeacon.bind(navigator);
        navigator.sendBeacon = function (url) { note(url, "ping", "I"); return beacon.apply(this, arguments); };
      }

      var NativeImage = window.Image;
      if (NativeImage) {
        window.Image = function () {
          var img = new NativeImage(arguments[0], arguments[1]);
          try {
            var d = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, "src");
            Object.defineProperty(img, "src", {
              set: function (v) { note(v, "image", "I"); d.set.call(img, v); },
              get: function () { return d.get.call(img); }
            });
          } catch (e) {}
          return img;
        };
        window.Image.prototype = NativeImage.prototype;
      }

      try {
        new PerformanceObserver(function (list) {
          list.getEntries().forEach(function (e) {
            note(e.name, e.initiatorType || "other", "P");
          });
        }).observe({ type: "resource", buffered: true });
      } catch (e) {
        send({ kind: "note", message: "PerformanceObserver unavailable: " + e });
      }
    })();
    """#

    /// Runs after the settle period. Walks DOM and CSSOM for declared
    /// resources, then returns the §3-shaped extraction summary. Returns JSON
    /// as a string because evaluateJavaScript's bridging of deep objects is
    /// where this kind of harness usually starts lying about what it found.
    static let extraction = #"""
    (function () {
      var found = [];
      var seen = {};
      var push = function (raw, type, recorder) {
        if (!raw) return;
        var abs;
        try { abs = new URL(raw, document.baseURI).href; } catch (e) { return; }
        if (abs.indexOf("data:") === 0 || abs.indexOf("blob:") === 0) return;
        var key = abs + "|" + recorder;
        if (seen[key]) return;
        seen[key] = 1;
        found.push({ url: abs, type: type, recorder: recorder });
      };
      var pushSrcset = function (value, type, recorder) {
        if (!value) return;
        value.split(",").forEach(function (part) {
          push(part.trim().split(/\s+/)[0], type, recorder);
        });
      };

      // --- D: DOM walk -------------------------------------------------
      var q = function (sel) { return Array.prototype.slice.call(document.querySelectorAll(sel)); };
      q("img[src]").forEach(function (n) { push(n.getAttribute("src"), "image", "D"); });
      q("img[srcset], source[srcset]").forEach(function (n) { pushSrcset(n.getAttribute("srcset"), "image", "D"); });
      q("source[src]").forEach(function (n) { push(n.getAttribute("src"), "media", "D"); });
      q("script[src]").forEach(function (n) { push(n.getAttribute("src"), "script", "D"); });
      q("link[href]").forEach(function (n) {
        var rel = (n.getAttribute("rel") || "").toLowerCase();
        var type = rel.indexOf("stylesheet") >= 0 ? "style-sheet"
                 : rel.indexOf("icon") >= 0 ? "image" : "other";
        push(n.getAttribute("href"), type, "D");
      });
      q("video[src], audio[src]").forEach(function (n) { push(n.getAttribute("src"), "media", "D"); });
      q("iframe[src]").forEach(function (n) { push(n.getAttribute("src"), "document", "D"); });
      q("object[data]").forEach(function (n) { push(n.getAttribute("data"), "other", "D"); });
      q("use[href], use").forEach(function (n) {
        push(n.getAttribute("href") || n.getAttribute("xlink:href"), "svg-document", "D");
      });

      // --- C: CSSOM walk -----------------------------------------------
      var urlRE = /url\(\s*['"]?([^'")]+)['"]?\s*\)/g;
      var fromText = function (text, type) {
        var m;
        while ((m = urlRE.exec(text)) !== null) push(m[1], type, "C");
      };
      var mediaHits = [];
      var opaqueSheets = [];
      Array.prototype.slice.call(document.styleSheets).forEach(function (sheet) {
        var rules;
        try { rules = sheet.cssRules; } catch (e) {
          // A cross-origin stylesheet without CORS is UNREADABLE, so every
          // resource it references — webfonts, background images — is
          // undiscoverable. Silently skipping it would hide both the resources
          // and the reason. Report it as a named hole instead.
          opaqueSheets.push(sheet.href || "(inline)");
          return;
        }
        if (!rules) {
          opaqueSheets.push((sheet.href || "(inline)") + " (blocked or empty)");
          return;
        }
        var walk = function (list, inMedia) {
          Array.prototype.slice.call(list).forEach(function (rule) {
            if (rule.type === CSSRule.FONT_FACE_RULE) {
              fromText(rule.style.getPropertyValue("src") || "", "font");
            } else if (rule.type === CSSRule.MEDIA_RULE) {
              var matches = window.matchMedia(rule.conditionText || rule.media.mediaText).matches;
              mediaHits.push((rule.conditionText || rule.media.mediaText) + " => " + matches);
              walk(rule.cssRules, true);
            } else if (rule.style) {
              ["background-image", "border-image-source", "mask-image", "list-style-image"]
                .forEach(function (prop) {
                  var v = rule.style.getPropertyValue(prop);
                  if (v && v !== "none") fromText(v, "image");
                });
            }
          });
        };
        walk(rules, false);
      });
      // Computed styles catch what the rule walk cannot attribute.
      Array.prototype.slice.call(document.querySelectorAll("*")).forEach(function (el) {
        var cs = window.getComputedStyle(el);
        ["background-image", "border-image-source", "mask-image"].forEach(function (prop) {
          var v = cs.getPropertyValue(prop);
          if (v && v !== "none") fromText(v, "image");
        });
      });

      // --- R: resource-timing buffer, polled rather than observed --------
      // The observer and this poll should agree. Where they DON'T, the bug is
      // ours; where they both miss something the server actually served, the
      // blind spot is WebKit's and belongs in the contract.
      try {
        performance.getEntriesByType("resource").forEach(function (e) {
          push(e.name, e.initiatorType || "other", "R");
        });
      } catch (e) {}

      // --- Fonts, via the FontFaceSet ------------------------------------
      // @font-face inside a cross-origin stylesheet is unreadable through
      // cssRules, so this is the only surface that names the font at all. It
      // gives a FAMILY, never a URL — which is the point: it is evidence about
      // what the manifest cannot see, not a manifest row.
      var fontFaces = [];
      try {
        document.fonts.forEach(function (face) {
          if (face.family) fontFaces.push(face.family + " — " + face.status);
        });
      } catch (e) {}

      // --- §3 extraction summary ---------------------------------------
      var nodes = 0, textNodes = 0;
      var rootRects = [];
      var walkDOM = function (el, depth) {
        nodes++;
        if (depth <= 1) {
          var r = el.getBoundingClientRect();
          rootRects.push(el.tagName.toLowerCase() + " " +
            Math.round(r.x) + "," + Math.round(r.y) + " " +
            Math.round(r.width) + "×" + Math.round(r.height));
        }
        Array.prototype.slice.call(el.children).forEach(function (c) { walkDOM(c, depth + 1); });
      };
      if (document.body) walkDOM(document.body, 0);
      var tw = document.createTreeWalker(document.body || document, NodeFilter.SHOW_TEXT, null);
      while (tw.nextNode()) { if (tw.currentNode.nodeValue.trim().length) textNodes++; }

      return JSON.stringify({
        resources: found,
        nodeCount: nodes,
        textNodeCount: textNodes,
        documentHeight: Math.max(
          document.body ? document.body.getBoundingClientRect().bottom + (parseFloat(getComputedStyle(document.body).marginBottom) || 0) : 0,
          document.documentElement.getBoundingClientRect().height),
        viewportClampedHeight: document.documentElement.scrollHeight,
        rootRects: rootRects.slice(0, 12),
        mediaQueryHits: mediaHits,
        opaqueStylesheets: opaqueSheets,
        fontFaces: fontFaces
      });
    })();
    """#
}

// MARK: - Probe

@MainActor
final class Probe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let options: SpikeOptions

    /// §4: in the trust step, the document's OWN origin is pre-allowed. Pass 1
    /// allows nothing at all, so this only applies once the user has trusted
    /// anything. Getting this wrong is not cosmetic — it was silently disabling
    /// the CSSOM recorder, because a blocked same-origin stylesheet has no rules
    /// to walk.
    private var effectiveAllowedOrigins: Set<String> {
        guard !options.allowedOrigins.isEmpty else { return [] }
        var set = options.allowedOrigins
        if let scheme = options.url.scheme, let host = options.url.host {
            var origin = "\(scheme)://\(host)"
            if let port = options.url.port { origin += ":\(port)" }
            set.insert(origin)
        }
        return set
    }
    private var entries: [String: ManifestEntry] = [:]
    private var viewportResults: [ViewportResult] = []
    private var notes: [String] = []
    private var currentViewport = ""
    private var webView: WKWebView?
    private var window: NSWindow?
    private var continuation: (() -> Void)?
    private var navigationsAttempted: [String] = []

    init(options: SpikeOptions) { self.options = options }

    // MARK: Rule list

    /// Blocks every resource type EXCEPT `document`, then re-permits the trusted
    /// origins. Leaving `document` unblocked is what lets the initial navigation
    /// through while nothing else moves — the guarantee pass 1 rests on.
    private func ruleListSource() -> String {
        let blockedTypes = ["image", "style-sheet", "script", "font",
                            "svg-document", "media", "popup", "ping", "fetch",
                            "websocket", "other"]
        var rules: [[String: Any]] = [[
            "trigger": ["url-filter": ".*", "resource-type": blockedTypes],
            "action": ["type": "block"]
        ]]
        // ignore-previous-rules must come AFTER the block to override it.
        for origin in effectiveAllowedOrigins.sorted() {
            let escaped = NSRegularExpression.escapedPattern(for: origin)
            rules.append([
                "trigger": ["url-filter": "^\(escaped)/"],
                "action": ["type": "ignore-previous-rules"]
            ])
        }
        let data = try? JSONSerialization.data(withJSONObject: rules)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    // MARK: Run

    func run() async {
        for size in options.viewports {
            currentViewport = "\(Int(size.width))×\(Int(size.height))"
            await probe(size: size)
        }
        finish()
    }

    private func probe(size: CGSize) async {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()          // contract §2
        config.suppressesIncrementalRendering = true

        let controller = WKUserContentController()
        controller.add(self, name: "expSpike")
        controller.addUserScript(WKUserScript(source: SpikeJS.instrumentation,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        config.userContentController = controller

        if let list = await compileRuleList() {
            controller.add(list)
        } else {
            notes.append("RULE LIST FAILED TO COMPILE — nothing was blocked. "
                         + "Treat every result from this run as invalid.")
        }

        let frame = CGRect(origin: .zero, size: size)
        let webView = WKWebView(frame: frame, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        // WKWebView will not lay out reliably with no window behind it. Offscreen
        // and never ordered front, so nothing flashes on the owner's display.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        self.window = window

        await load(webView: webView)
        try? await Task.sleep(nanoseconds: UInt64(options.settleMs) * 1_000_000)
        await extract(from: webView, size: size)

        controller.removeScriptMessageHandler(forName: "expSpike")
        window.contentView = nil
        self.webView = nil
        self.window = nil
    }

    private func compileRuleList() async -> WKContentRuleList? {
        await withCheckedContinuation { (cont: CheckedContinuation<WKContentRuleList?, Never>) in
            WKContentRuleListStore.default()?.compileContentRuleList(
                forIdentifier: "exp-html-import-spike",
                encodedContentRuleList: ruleListSource()
            ) { list, error in
                if let error { print("rule list error: \(error)") }
                cont.resume(returning: list)
            }
        }
    }

    private func load(webView: WKWebView) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = { cont.resume() }
            if options.url.isFileURL {
                webView.loadFileURL(options.url,
                                    allowingReadAccessTo: options.url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: options.url))
            }
            // Hard deadline, contract §7: an SPA that never settles must not hang.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, let done = self.continuation else { return }
                self.notes.append("Render deadline hit at \(self.currentViewport) — partial result.")
                self.continuation = nil
                done()
            }
        }
    }

    private func extract(from webView: WKWebView, size: CGSize) async {
        let json: String? = await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            webView.evaluateJavaScript(SpikeJS.extraction) { value, error in
                if let error { print("extraction error: \(error)") }
                cont.resume(returning: value as? String)
            }
        }
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            notes.append("Extraction returned nothing at \(currentViewport).")
            return
        }
        for raw in (object["resources"] as? [[String: Any]]) ?? [] {
            guard let url = raw["url"] as? String else { continue }
            record(url: url, type: raw["type"] as? String ?? "other",
                   recorder: raw["recorder"] as? String ?? "?")
        }
        viewportResults.append(ViewportResult(
            viewport: currentViewport,
            nodeCount: object["nodeCount"] as? Int ?? 0,
            textNodeCount: object["textNodeCount"] as? Int ?? 0,
            documentHeight: object["documentHeight"] as? Double ?? 0,
            rootRects: object["rootRects"] as? [String] ?? [],
            mediaQueryHits: object["mediaQueryHits"] as? [String] ?? [],
            viewportClampedHeight: object["viewportClampedHeight"] as? Double ?? 0,
            opaqueStylesheets: object["opaqueStylesheets"] as? [String] ?? [],
            fontFaces: object["fontFaces"] as? [String] ?? [],
            consoleErrors: []))
    }

    private func record(url: String, type: String, recorder: String) {
        guard let parsed = URL(string: url), let scheme = parsed.scheme else { return }
        var origin: String
        if let host = parsed.host, !host.isEmpty {
            origin = "\(scheme)://\(host)"
            if let port = parsed.port { origin += ":\(port)" }
        } else if scheme == "file" {
            // A file URL has no host, so the web's origin concept does not apply.
            // The scoped directory is the honest equivalent: it is exactly what
            // §2's security-scoped read allows, so it is what a person would be
            // agreeing to. Grouping local resources under "file://<dir>" keeps
            // the manifest's unit of trust matched to the unit of access.
            origin = "file://" + parsed.deletingLastPathComponent().path
        } else {
            origin = scheme + ":"
        }
        var entry = entries[url] ?? ManifestEntry(url: url, origin: origin, type: type)
        entry.recorders.insert(recorder)
        entry.viewports.insert(currentViewport)
        var seen = entry.sightings[currentViewport] ?? []
        if !seen.contains(recorder) { seen.append(recorder); seen.sort() }
        entry.sightings[currentViewport] = seen
        entry.blocked = !effectiveAllowedOrigins.contains(origin)
        // A declaration recorder knows which ELEMENT declared the resource, so
        // its type is authoritative. PerformanceObserver's `initiatorType` is a
        // different vocabulary ("link", "img", "css") and letting it win made the
        // same resource read as "style-sheet" in pass 1 and "link" in pass 2.
        // §4 calls resource type per row a security detail, so it has to be one
        // stable vocabulary.
        if ManifestEntry.declarationRecorders.contains(recorder) {
            entry.type = type
        } else if entry.type == "other" {
            entry.type = Self.normalizedType(type)
        }
        entries[url] = entry
    }

    /// PerformanceObserver's vocabulary, mapped onto the contract's.
    private static func normalizedType(_ raw: String) -> String {
        switch raw {
        case "link": return "style-sheet"
        case "img": return "image"
        case "css": return "image"          // loaded-by-CSS; usually image or font
        case "xmlhttprequest": return "fetch"
        default: return raw
        }
    }

    // MARK: Delegates

    // Delivered on the main thread by WebKit, so this stays main-actor isolated
    // and records synchronously — a Task hop here would let the extraction pass
    // run before late messages land, which is exactly the race that would make
    // the instrumentation recorder look worse than it is.
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["kind"] as? String {
        case "resource":
            record(url: body["url"] as? String ?? "",
                   type: body["type"] as? String ?? "other",
                   recorder: body["recorder"] as? String ?? "?")
        case "note":
            notes.append(body["message"] as? String ?? "")
        default: break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let done = continuation; continuation = nil; done?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        notes.append("Navigation failed at \(currentViewport): \(error.localizedDescription)")
        let done = continuation; continuation = nil; done?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        notes.append("Provisional navigation failed at \(currentViewport): \(error.localizedDescription)")
        let done = continuation; continuation = nil; done?()
    }

    /// Contract §2: navigation is confined to the initial document. Anything
    /// else is blocked and REPORTED rather than silently ignored.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { decisionHandler(.cancel); return }
        let isInitial = target.absoluteString == options.url.absoluteString
        navigationsAttempted.append(target.absoluteString)
        if !isInitial && action.navigationType != .other {
            notes.append("Blocked navigation away to \(target.absoluteString)")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: Output

    private func finish() {
        let pass = options.allowedOrigins.isEmpty ? 1 : 2
        let sorted = entries.values.sorted {
            $0.origin == $1.origin ? $0.url < $1.url : $0.origin < $1.origin
        }
        let result = SpikeResult(
            url: options.url.absoluteString,
            pass: pass,
            allowedOrigins: effectiveAllowedOrigins.sorted(),
            entries: sorted,
            viewports: viewportResults,
            notes: notes)

        print("")
        print("HTML-import spike — pass \(pass)")
        print("document: \(options.url.absoluteString)")
        print("viewports: \(options.viewports.map { "\(Int($0.width))×\(Int($0.height))" }.joined(separator: ", "))")
        print("trusted: \(effectiveAllowedOrigins.isEmpty ? "(nothing — discovery pass)" : effectiveAllowedOrigins.sorted().joined(separator: ", "))")
        print("")

        var byOrigin: [String: [ManifestEntry]] = [:]
        for entry in sorted { byOrigin[entry.origin, default: []].append(entry) }
        print("MANIFEST — \(byOrigin.count) origin(s), \(sorted.count) resource(s)")
        for origin in byOrigin.keys.sorted() {
            let group = byOrigin[origin]!
            let allowed = effectiveAllowedOrigins.contains(origin)
            let implicit = allowed && !options.allowedOrigins.contains(origin)
            let state = allowed ? (implicit ? "ALLOWED (document's own origin)" : "ALLOWED") : "blocked"
            print("  \(origin)  [\(state)]  \(group.count) resource(s)")
            if origin.contains("xn--") {
                // URL parsing IDNA-encodes the host for us, so the manifest is
                // punycode by default and the homograph risk is handled by
                // construction rather than by remembering to encode. Worth
                // confirming rather than assuming — hence this line.
                print("    (host arrived already punycode-encoded — §4 homograph rule satisfied by URL parsing)")
            }
            for entry in group {
                let recorders = entry.recorders.sorted().joined()
                print("    [\(recorders.padded(to: 4))] \(entry.type.padded(to: 12)) \(entry.url)")

                let names = options.viewports.map { "\(Int($0.width))×\(Int($0.height))" }
                let rows = names.map { viewport -> String in
                    let declared = entry.declared(at: viewport)
                    let observed = entry.observed(at: viewport)
                    if declared.isEmpty && observed.isEmpty { return "\(viewport) —" }
                    var parts: [String] = []
                    if !declared.isEmpty { parts.append("declared \(declared.joined(separator: ","))") }
                    if !observed.isEmpty { parts.append("observed \(observed.joined(separator: ","))") }
                    else { parts.append("NOT requested here") }
                    return "\(viewport) \(parts.joined(separator: " · "))"
                }
                // Only worth the lines when the viewports actually disagree —
                // which is exactly when the union manifest is doing work.
                if options.verbose || Set(rows.map { $0.split(separator: " ").dropFirst().joined() }).count > 1 {
                    rows.forEach { print("           \($0)") }
                }
            }
        }

        print("")
        print("EXTRACTION")
        for result in viewportResults {
            print("  \(result.viewport): \(result.nodeCount) nodes, \(result.textNodeCount) text nodes, "
                  + "content height \(Int(result.documentHeight))"
                  + (result.viewportClampedHeight > result.documentHeight
                     ? "  (scrollHeight would say \(Int(result.viewportClampedHeight)) — viewport-clamped)"
                     : ""))
            for hit in result.mediaQueryHits { print("    media: \(hit)") }
            for face in result.fontFaces { print("    font-face: \(face)") }
            for sheet in result.opaqueStylesheets {
                print("    UNREADABLE STYLESHEET: \(sheet)")
                print("      → anything it references is undiscoverable until its origin is trusted")
            }
            for rect in result.rootRects.prefix(6) { print("    \(rect)") }
        }

        if navigationsAttempted.count > 1 {
            notes.append("Navigations attempted: \(navigationsAttempted.joined(separator: ", "))")
        }
        if !notes.isEmpty {
            print("")
            print("NOTES")
            notes.forEach { print("  • \($0)") }
        }

        print("")
        print("RECORDER COVERAGE — the point of this harness")
        var byRecorder: [String: Int] = [:]
        var onlyOne: [ManifestEntry] = []
        for entry in sorted {
            entry.recorders.forEach { byRecorder[$0, default: 0] += 1 }
            if entry.recorders.count == 1 { onlyOne.append(entry) }
        }
        for key in ["D", "C", "I", "P", "R"] {
            print("  \(key): \(byRecorder[key] ?? 0) of \(sorted.count)")
        }
        // The declared/observed split is the finding the first two runs were
        // missing. "Declared everywhere, requested at one viewport" is the union
        // manifest doing its job; "declared, never requested anywhere" is a row
        // the trust UI is asking the designer to rule on for no reason.
        let names = options.viewports.map { "\(Int($0.width))×\(Int($0.height))" }
        var splitAcrossViewports: [ManifestEntry] = []
        var declaredNeverObserved: [ManifestEntry] = []
        for entry in sorted {
            let observedAt = names.filter { !entry.observed(at: $0).isEmpty }
            let declaredAt = names.filter { !entry.declared(at: $0).isEmpty }
            if observedAt.isEmpty && !declaredAt.isEmpty { declaredNeverObserved.append(entry) }
            else if observedAt.count < declaredAt.count { splitAcrossViewports.append(entry) }
        }
        print("")
        print("  DECLARED vs OBSERVED")
        if splitAcrossViewports.isEmpty {
            print("    no resource was declared at more viewports than it was requested at")
        } else {
            print("    declared at more viewports than requested — the union manifest earning its keep:")
            splitAcrossViewports.forEach { print("      \($0.url)") }
        }
        if !declaredNeverObserved.isEmpty {
            print("    declared but never observed being requested (blocked, or genuinely unused):")
            declaredNeverObserved.forEach { print("      \($0.url)") }
        }
        print("")

        if onlyOne.isEmpty {
            print("  every resource was caught by more than one recorder")
        } else {
            print("  caught by exactly ONE recorder (drop that recorder and these vanish):")
            for entry in onlyOne {
                print("    [\(entry.recorders.sorted().joined())] \(entry.url)")
            }
        }

        if let jsonOut = options.jsonOut {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(result) {
                try? data.write(to: jsonOut)
                print("")
                print("wrote \(jsonOut.path)")
            }
        }
    }
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

// MARK: - Entry point

guard let options = SpikeOptions.parse(Array(CommandLine.arguments.dropFirst())) else {
    print(SpikeOptions.usage)
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

Task { @MainActor in
    let probe = Probe(options: options)
    await probe.run()
    exit(0)
}

app.run()
