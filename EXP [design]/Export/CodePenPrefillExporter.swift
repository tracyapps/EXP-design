//
//  CodePenPrefillExporter.swift
//  EXP [design]
//
//  Export-only CodePen 2.0 boundary. CodePen supports creating a new Pen with
//  a form POST, but does not expose general authenticated file CRUD. EXP
//  therefore builds a reviewable local launch page: nothing is transmitted
//  until the person presses its Send to CodePen button in their own browser.
//

import Foundation

struct CodePenPrefillPackage: Sendable {
    var title: String
    var payloadJSON: Data
    var launcherHTML: Data
}

enum CodePenPrefillError: LocalizedError {
    case artboardNotFound
    case missingSemanticArtifact
    case payloadTooLarge(Int)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .artboardNotFound:
            return "Choose one artboard to send to CodePen."
        case .missingSemanticArtifact:
            return "EXP could not generate semantic HTML and CSS for that artboard."
        case .payloadTooLarge(let bytes):
            return "The generated CodePen payload is \(bytes / 1_024) KB, above EXP’s 4 MB safety boundary. Export Semantic HTML instead."
        case .invalidPayload:
            return "EXP could not encode the CodePen prefill payload."
        }
    }
}

struct CodePenPrefillExporter {
    /// CodePen's Prefill endpoint after the site-wide 2.0 launch. The former
    /// `/cpe/pen/define/` compatibility route now returns a plain server error.
    static let endpoint = URL(string: "https://codepen.io/pen/define")!
    static let maximumPayloadBytes = 4 * 1_024 * 1_024

    let document: Document

    func makePackage(artboardID: UUID) throws -> CodePenPrefillPackage {
        guard let artboard = document.allArtboards.first(where: { $0.id == artboardID }) else {
            throw CodePenPrefillError.artboardNotFound
        }
        let bundle = SemanticHTMLExporter(document: document)
            .makeBundle(artboardIDs: Set([artboardID]))
        guard let htmlArtifact = bundle.artifacts.first(where: {
                  $0.role == "semantic-html"
              }),
              let cssArtifact = bundle.artifacts.first(where: {
                  $0.role == "semantic-stylesheet"
              }),
              var html = String(data: htmlArtifact.data, encoding: .utf8),
              let css = String(data: cssArtifact.data, encoding: .utf8) else {
            throw CodePenPrefillError.missingSemanticArtifact
        }

        // Prefill's `html` field is the HTML editor/body content, not a second
        // complete document. CodePen owns the outer document and stylesheet
        // injection, so exclude EXP's doctype/head and package-relative link.
        html = bodyFragment(from: html)

        // Keep this to CodePen's current documented Prefill fields. Older
        // examples included `editors`, `tags`, and sentinel values such as
        // `css_starter: "neither"`; the 2.0 endpoint rejects that legacy shape
        // instead of ignoring it.
        let payload: [String: Any] = [
            "title": artboard.name,
            "description": "Exported from EXP [design] as static semantic HTML/CSS. Interactive source is retained in the .design bridge but is not rewritten or sent without an explicit behavior binding.",
            "layout": "left",
            "html": html,
            "html_pre_processor": "none",
            "css": css,
            "css_pre_processor": "none",
            "js": "",
            "js_pre_processor": "none"
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let payloadJSON = try? JSONSerialization.data(
                withJSONObject: payload, options: [.sortedKeys]) else {
            throw CodePenPrefillError.invalidPayload
        }
        guard payloadJSON.count <= Self.maximumPayloadBytes else {
            throw CodePenPrefillError.payloadTooLarge(payloadJSON.count)
        }

        let json = String(decoding: payloadJSON, as: UTF8.self)
        let endpoint = Self.endpoint.absoluteString
        let launcher = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <title>Send \(escapeText(artboard.name)) to CodePen</title>
          <style>
            :root { font: 16px/1.5 system-ui, sans-serif; color-scheme: light dark; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: Canvas; color: CanvasText; }
            main { box-sizing: border-box; width: min(34rem, calc(100% - 2rem)); padding: 2rem; border: 1px solid color-mix(in srgb, CanvasText 24%, transparent); border-radius: 1rem; }
            h1 { margin-block-start: 0; font-size: 1.5rem; }
            p { max-width: 62ch; }
            button { appearance: none; border: 0; border-radius: .5rem; padding: .75rem 1rem; font: inherit; font-weight: 650; background: #2563eb; color: white; cursor: pointer; }
            button:focus-visible { outline: 3px solid Highlight; outline-offset: 3px; }
          </style>
        </head>
        <body>
          <main>
            <h1>Send “\(escapeText(artboard.name))” to CodePen?</h1>
            <p>This creates a new Pen using EXP’s semantic HTML and CSS. CodePen receives the generated design only after you press the button below.</p>
            <p>JavaScript and other opaque source remain preserved in the EXP document, but are not sent because EXP cannot yet prove they match the reconstructed DOM.</p>
            <form action="\(escapeAttribute(endpoint))" method="post" target="_blank">
              <input type="hidden" name="data" value="\(escapeAttribute(json))">
              <button type="submit">Send to CodePen</button>
            </form>
          </main>
        </body>
        </html>
        """
        return CodePenPrefillPackage(title: artboard.name,
                                     payloadJSON: payloadJSON,
                                     launcherHTML: Data(launcher.utf8))
    }

    private func escapeText(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func bodyFragment(from html: String) -> String {
        guard let opening = html.range(
            of: #"<body\b[^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        ), let closing = html.range(
            of: #"</body\s*>"#,
            options: [.regularExpression, .caseInsensitive, .backwards]
        ), opening.upperBound <= closing.lowerBound else {
            return html
        }
        return html[opening.upperBound..<closing.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
