//
//  ThumbnailProvider.swift
//  EXPThumbnail  (Quick Look Thumbnail Extension target)
//
//  Renders a Finder / Quick Look thumbnail for a ".design" file by decoding the
//  document and drawing its first artboard with the app's ExportRenderer.
//
//  SETUP (must be done once in Xcode — see the chat steps):
//   1. Add a "Thumbnail Extension" target (File ▸ New ▸ Target… ▸ macOS).
//   2. In that target's Info.plist, set NSExtension ▸ NSExtensionAttributes ▸
//      QLSupportedContentTypes = [ "tapps.exp-design.designfile" ].
//   3. Replace the generated ThumbnailProvider.swift with this file.
//   4. Add to the extension target's membership (File Inspector ▸ Target
//      Membership): Document.swift, Paint.swift, PaintRender.swift,
//      ExportRenderer.swift, plus whatever those reference (e.g. EffectsRender,
//      the font resolver) — build and add anything the compiler flags.
//

import QuickLookThumbnailing
import AppKit

final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        // Decode the document and pick the first artboard to preview.
        guard let data = try? Data(contentsOf: request.fileURL),
              let doc = try? JSONDecoder().decode(Document.self, from: data),
              let artboard = doc.artboards.first,
              artboard.frame.width > 0, artboard.frame.height > 0 else {
            handler(nil, nil)
            return
        }

        // Fit the artboard into the requested thumbnail box (keep aspect).
        let board = artboard.frame.size
        let maxSize = request.maximumSize
        let fit = min(maxSize.width / board.width, maxSize.height / board.height)
        let thumb = CGSize(width: max(1, board.width * fit),
                           height: max(1, board.height * fit))

        // Render the artboard to a raster via the app's exporter, then draw it
        // into the thumbnail context.
        guard let png = ExportRenderer(document: doc).pngData(for: artboard,
                                                              scale: max(1, request.scale)),
              let image = NSImage(data: png) else {
            handler(nil, nil)
            return
        }

        let reply = QLThumbnailReply(contextSize: thumb) {
            image.draw(in: NSRect(origin: .zero, size: thumb))
            return true
        }
        handler(reply, nil)
    }
}
