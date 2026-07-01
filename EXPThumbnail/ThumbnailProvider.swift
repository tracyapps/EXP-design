//
//  ThumbnailProvider.swift
//  EXPThumbnail
//
//  Renders a Finder / Quick Look thumbnail for a ".design" file by decoding the
//  document and drawing its first artboard with the app's ExportRenderer.
//
//  Target setup reminder: this target's Info.plist must list
//  NSExtension ▸ NSExtensionAttributes ▸ QLSupportedContentTypes =
//  [ "tapps.exp-design.designfile" ], and the model + renderer files must be
//  members of this target:
//   • Document.swift, Paint.swift, Typography.swift (model + codable)
//   • PaintRender.swift, EffectsRender.swift, ExportRenderer.swift (rendering)
//

import QuickLookThumbnailing
import AppKit

class ThumbnailProvider: QLThumbnailProvider {

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

        // Render the artboard to a raster via the app's exporter.
        guard let png = ExportRenderer(document: doc).pngData(for: artboard,
                                                              scale: max(1, request.scale)),
              let image = NSImage(data: png) else {
            handler(nil, nil)
            return
        }

        // Draw into the current context (set up for us by QuickLook).
        let reply = QLThumbnailReply(contextSize: thumb, currentContextDrawing: { () -> Bool in
            image.draw(in: NSRect(origin: .zero, size: thumb))
            return true
        })
        handler(reply, nil)
    }
}
