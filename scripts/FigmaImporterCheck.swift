import Foundation

@main
struct FigmaImporterCheck {
    @MainActor
    static func main() throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                exit(1)
            }
        }

        let json = #"""
        {
          "name": "Two page fixture",
          "styles": {
            "fill:1": {"name":"Brand/Red","styleType":"FILL"},
            "text:1": {"name":"Body/Regular","styleType":"TEXT"}
          },
          "document": {
            "id":"0:0", "name":"Document", "type":"DOCUMENT",
            "children":[
              {
                "id":"0:1", "name":"Product", "type":"CANVAS",
                "children":[
                  {
                    "id":"1:1", "name":"Home", "type":"FRAME",
                    "absoluteBoundingBox":{"x":100,"y":100,"width":400,"height":300},
                    "fills":[{"type":"SOLID","color":{"r":1,"g":1,"b":1,"a":1}}],
                    "children":[
                      {
                        "id":"1:2", "name":"Card", "type":"RECTANGLE",
                        "absoluteBoundingBox":{"x":120,"y":130,"width":100,"height":50},
                        "rectangleCornerRadii":[8,6,4,2],
                        "fills":[{"type":"SOLID","color":{"r":1,"g":0,"b":0,"a":1}}],
                        "styles":{"fill":"fill:1"}
                      },
                      {
                        "id":"1:3", "name":"Greeting", "type":"TEXT",
                        "absoluteBoundingBox":{"x":130,"y":200,"width":160,"height":30},
                        "characters":"Hello Figma",
                        "fills":[{"type":"SOLID","color":{"r":1,"g":0.8,"b":0.1,"a":1}}],
                        "style":{"fontPostScriptName":"Helvetica","fontSize":18,
                                 "textAlignHorizontal":"LEFT","lineHeightPx":24,
                                 "letterSpacing":0,"textAutoResize":"HEIGHT"},
                        "styles":{"text":"text:1"}
                      },
                      {
                        "id":"1:4", "name":"Photo", "type":"RECTANGLE",
                        "absoluteBoundingBox":{"x":310,"y":130,"width":120,"height":80},
                        "fills":[{"type":"IMAGE","imageRef":"img-1","scaleMode":"FILL"}]
                      },
                      {
                        "id":"1:5", "name":"Mark", "type":"VECTOR",
                        "absoluteBoundingBox":{"x":250,"y":240,"width":20,"height":20},
                        "fills":[{"type":"SOLID","color":{"r":0,"g":0.5,"b":1,"a":1}}],
                        "fillGeometry":[{"path":"M0 0 L20 0 L20 20 L0 20 Z"}]
                      },
                      {
                        "id":"1:6", "name":"Button use", "type":"INSTANCE", "componentId":"9:1",
                        "absoluteBoundingBox":{"x":300,"y":240,"width":100,"height":40}
                      },
                      {
                        "id":"1:7", "name":"Rotated dotted rule", "type":"LINE",
                        "absoluteBoundingBox":{"x":120,"y":260,"width":102,"height":18},
                        "size":{"x":103.6,"y":0}, "rotation":10,
                        "strokes":[{"type":"SOLID","color":{"r":0.8,"g":0.6,"b":0.1,"a":1}}],
                        "strokeWeight":2, "strokeDashes":[0,6], "strokeCap":"ROUND"
                      },
                      {
                        "id":"1:8", "name":"Vertical rule without size", "type":"LINE",
                        "absoluteBoundingBox":{"x":450,"y":130,"width":2,"height":80},
                        "strokes":[{"type":"SOLID","color":{"r":0.8,"g":0.6,"b":0.1,"a":1}}],
                        "strokeWeight":2
                      },
                      {
                        "id":"1:9", "name":"Matrix rotated rule", "type":"LINE",
                        "absoluteBoundingBox":{"x":470,"y":130,"width":2,"height":80},
                        "size":{"x":80,"y":0}, "rotation":2,
                        "relativeTransform":[[0,1,470],[-1,0,210]],
                        "strokes":[{"type":"SOLID","color":{"r":0.8,"g":0.6,"b":0.1,"a":1}}],
                        "strokeWeight":2
                      },
                      {
                        "id":"1:10", "name":"Inline controls", "type":"FRAME",
                        "absoluteBoundingBox":{"x":120,"y":275,"width":140,"height":24},
                        "layoutMode":"HORIZONTAL", "itemSpacing":8,
                        "primaryAxisAlignItems":"MIN", "counterAxisAlignItems":"CENTER",
                        "fills":[{"type":"SOLID","color":{"r":0.15,"g":0.15,"b":0.15,"a":1}}],
                        "children":[
                          {
                            "id":"1:11", "name":"Absolute accent", "type":"RECTANGLE",
                            "layoutPositioning":"ABSOLUTE",
                            "absoluteBoundingBox":{"x":120,"y":275,"width":140,"height":2},
                            "fills":[{"type":"SOLID","color":{"r":1,"g":0.7,"b":0,"a":1}}]
                          },
                          {
                            "id":"1:12", "name":"Dot", "type":"ELLIPSE",
                            "absoluteBoundingBox":{"x":120,"y":279,"width":16,"height":16},
                            "fills":[{"type":"SOLID","color":{"r":0,"g":0.8,"b":1,"a":1}}]
                          },
                          {
                            "id":"1:13", "name":"Choice", "type":"TEXT",
                            "absoluteBoundingBox":{"x":144,"y":275,"width":48,"height":24},
                            "characters":"Choice",
                            "style":{"fontPostScriptName":"Helvetica","fontSize":12,
                                     "textAutoResize":"NONE"}
                          }
                        ]
                      }
                    ]
                  },
                  {
                    "id":"9:1", "name":"Button", "type":"COMPONENT",
                    "absoluteBoundingBox":{"x":600,"y":100,"width":100,"height":40},
                    "fills":[{"type":"SOLID","color":{"r":0.1,"g":0.2,"b":0.8,"a":1}}],
                    "children":[{
                      "id":"9:2", "name":"Label", "type":"TEXT",
                      "absoluteBoundingBox":{"x":620,"y":110,"width":60,"height":20},
                      "characters":"Button",
                      "style":{"fontPostScriptName":"Helvetica","fontSize":14,
                               "textAutoResize":"WIDTH_AND_HEIGHT",
                               "fills":[{"type":"SOLID","color":{"r":1,"g":1,"b":1,"a":1}}]}
                    }]
                  }
                ]
              },
              {
                "id":"0:2", "name":"Archive", "type":"CANVAS",
                "children":[{
                  "id":"2:1", "name":"Old screen", "type":"FRAME",
                  "absoluteBoundingBox":{"x":0,"y":0,"width":320,"height":200},
                  "fills":[{"type":"SOLID","color":{"r":0.9,"g":0.9,"b":0.9,"a":1}}],
                  "children":[]
                }]
              }
            ]
          }
        }
        """#

        let result = try FigmaRESTImporter.readFileData(
            Data(json.utf8), imageData: ["img-1": Data([0x89, 0x50, 0x4e, 0x47])])
        require(result.payload.pages.count == 2, "Figma canvases should become two EXP pages")
        require(result.payload.pages.map(\.name) == ["Product", "Archive"],
                "page names should survive")
        require(result.payload.pages[0].artboards.count == 1,
                "top-level Product frame should become one artboard")
        require(result.payload.pages[1].artboards.count == 1,
                "top-level Archive frame should become one artboard")
        require(result.payload.sources.count == 1,
                "local Figma component should become one EXP source")

        let product = result.payload.pages[0]
        require(product.nodes.count == 10,
                "eight artboard layers plus instance and visible component placement should map")
        require(product.nodes.contains { if case .image = $0.content { return true }; return false },
                "downloaded image fill should become an embedded editable image")
        require(product.nodes.contains { if case .path = $0.content { return true }; return false },
                "vector geometry should remain an editable path")
        require(product.nodes.filter { if case .instance = $0.content { return true }; return false }.count == 2,
                "local instance and visible source placement should reference the component source")
        require(product.nodes.contains { $0.name == "Card" && $0.frame.origin == CGPoint(x: 120, y: 130) },
                "artboard child geometry should remain in page coordinates")
        let greeting = product.nodes.first { $0.name == "Greeting" }
        if case .text(let text)? = greeting?.content {
            require(text.firstRun.color.r == 1 && text.firstRun.color.g == 0.8,
                    "TEXT node fills should supply the base run color")
        } else {
            require(false, "text layer should map")
        }
        let rule = product.nodes.first { $0.name == "Rotated dotted rule" }
        require(rule?.frame.width == 103.6 && rule?.frame.height == 0,
                "rotated nodes should use Figma size instead of the already-rotated bounding-box size")
        require(rule?.rotation == 10, "Figma rotation should be applied exactly once")
        if case .line(let line)? = rule?.content {
            require(line.strokePattern == .dotted,
                    "Figma round zero-length dashes should become an editable dotted line")
            require(line.start == .zero && line.end == CGPoint(x: 103.6, y: 0),
                    "Figma lines should normalize to a horizontal editable segment")
        } else {
            require(false, "rotated dotted rule should remain a line")
        }
        let vertical = product.nodes.first { $0.name == "Vertical rule without size" }
        require(vertical?.rotation == 90 && vertical?.frame.width == 80 && vertical?.frame.height == 0,
                "a vertical line without reusable size must not become a diagonal across stroke bounds")
        let matrixRule = product.nodes.first { $0.name == "Matrix rotated rule" }
        require(matrixRule?.rotation == 90,
                "relativeTransform should preserve the line's canonical rotation when the scalar is inconsistent")
        let inlineControls = product.nodes.first { $0.name == "Inline controls" }
        if let inlineControls,
           case .group(let importedChildren) = inlineControls.content,
           let importedSurface = importedChildren.first(where: { $0.name == "Background" }),
           let importedAccent = importedChildren.first(where: { $0.name == "Absolute accent" }) {
            require(importedSurface.isAbsoluteInAutoLayout,
                    "an imported auto-layout frame surface must not consume a stack slot")
            require(importedAccent.isAbsoluteInAutoLayout,
                    "Figma absolute-positioned children should remain outside the stack")
            let reflowed = AutoLayoutEngine.reflowed([inlineControls])[0]
            if case .group(let arranged) = reflowed.content {
                require(arranged.first(where: { $0.name == "Dot" })?.frame.origin == CGPoint(x: 0, y: 4),
                        "absolute backgrounds must not shift the first flow item")
                require(arranged.first(where: { $0.name == "Choice" })?.frame.origin == CGPoint(x: 24, y: 0),
                        "absolute backgrounds must not shift later flow items")
                require(reflowed.frame.size == CGSize(width: 140, height: 24),
                        "absolute frame content should preserve the imported outer size")
            } else {
                require(false, "auto-layout fixture should remain an editable group")
            }
        } else {
            require(false, "auto-layout fixture and its absolute children should import")
        }
        // Compatibility for a .design file imported before Node stored Figma's
        // absolute-layout bit: infer a full-size enclosing Background, but do not
        // mistake it for the first horizontal stack item.
        let legacyBackground = Node(name: "Background", frame: CGRect(x: 0, y: 0, width: 72, height: 24),
                                    content: .rectangle(RectangleShape(fill: .solid(.white))))
        let legacyDot = Node(name: "Dot", frame: CGRect(x: 80, y: 4, width: 16, height: 16),
                             content: .ellipse(EllipseShape(fill: .solid(.black))))
        var legacyLabelText = TextContent(string: "Choice")
        legacyLabelText.box = .fixed
        let legacyLabel = Node(name: "Label", frame: CGRect(x: 104, y: 0, width: 48, height: 24),
                               content: .text(legacyLabelText))
        var legacyLayout = AutoLayout()
        legacyLayout.direction = .horizontal
        legacyLayout.gap = 8
        var legacyPadding = AutoPadding()
        legacyPadding.paddingTop = 0
        legacyPadding.paddingRight = 0
        legacyPadding.paddingBottom = 0
        legacyPadding.paddingLeft = 0
        let legacyRow = Node(name: "Legacy imported row", frame: CGRect(x: 0, y: 0, width: 152, height: 24),
                             autoLayout: legacyLayout,
                             autoPadding: legacyPadding,
                             content: .group(children: [legacyBackground, legacyDot, legacyLabel]))
        let repairedLegacyRow = AutoLayoutEngine.reflowed([legacyRow])[0]
        if case .group(let repairedChildren) = repairedLegacyRow.content {
            require(repairedChildren.first(where: { $0.name == "Dot" })?.frame.minX == 0,
                    "legacy imported backgrounds should be inferred outside the stack")
            require(repairedChildren.first(where: { $0.name == "Label" })?.frame.minX == 24,
                    "legacy imported rows should no longer shift their content by one frame width")
            require(repairedLegacyRow.frame.width == 72,
                    "legacy repair should also remove the previously stacked background width from the group frame")
        } else {
            require(false, "legacy auto-layout fixture should remain a group")
        }
        require(result.payload.designLanguage.assets.contains { $0.name == "Brand/Red" },
                "named Figma paint style should enter Design Language")
        require(result.payload.designLanguage.typeStyles.contains { $0.name == "Body/Regular" },
                "named Figma text style should enter Design Language")
        require(FigmaRESTImporter.fileKey(from: "https://www.figma.com/design/AbC_123/File") == "AbC_123",
                "design URL should parse its file key")
        require(FigmaRESTImporter.fileKey(from: "AbC_123") == "AbC_123",
                "bare file key should parse")
        require(FigmaRESTImporter.fileKey(from: "https://example.com/design/AbC_123/File") == nil,
                "non-Figma URL should be rejected")

        print("ok: Figma pages, editable core nodes, images, local components, styles, and URL parsing")
    }
}
