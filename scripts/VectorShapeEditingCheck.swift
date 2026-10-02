import Foundation
import CoreGraphics
import ImageIO

// Text is deliberately rejected by these edits; no typography is exercised.
extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize { .zero }
    func measuredSize(boxWidth: CGFloat) -> CGSize { .zero }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private func rect(_ name: String, _ x: CGFloat = 0, _ y: CGFloat = 0, _ w: CGFloat = 100, _ h: CGFloat = 80) -> Node {
    Node(name: name, frame: CGRect(x: x, y: y, width: w, height: h), content: .rectangle(RectangleShape(strokeWidth: 0)))
}
private func path(_ node: Node, in nodes: [Node]) -> CGPath { VectorShapeEditing.documentPath(node, index: NodeTreeIndex(nodes))! }
private func union(_ paths: [CGPath]) -> CGPath { paths.dropFirst().reduce(paths[0]) { $0.union($1, using: .winding) } }
private func sameInk(_ before: CGPath, _ after: CGPath, _ message: String) {
    let b = before.boundingBoxOfPath.union(after.boundingBoxOfPath).insetBy(dx: -1, dy: -1)
    // CG's boolean kernel normalizes intersected curves. Membership immediately
    // at a boundary can differ numerically; allow at most 0.02 document points.
    let edge = before.copy(strokingWithWidth: 0.04, lineCap: .butt, lineJoin: .round, miterLimit: 4)
    for iy in 0..<63 {
        for ix in 0..<61 {
            let p = CGPoint(x: b.minX + b.width * (CGFloat(ix) + 0.347) / 61,
                            y: b.minY + b.height * (CGFloat(iy) + 0.619) / 63)
            require(before.contains(p, using: .winding) == after.contains(p, using: .winding)
                    || edge.contains(p, using: .winding), "\(message) at \(p), bounds \(before.boundingBoxOfPath) / \(after.boundingBoxOfPath)")
        }
    }
}

@main enum Check {
    static func main() throws {
        let rectangle = rect("Rectangle")
        var maskShape = rectangle; maskShape.isMaskShape = true
        require(VectorShapeEditing.cut([maskShape], selected: [maskShape.id], from: CGPoint(x: -10,y: 40), to: CGPoint(x: 110,y: 40)) != nil,
                "Knife cuts a closed mask shape")
        let drawn = [CGPoint(x:-10,y:20),CGPoint(x:40,y:20),CGPoint(x:40,y:60),CGPoint(x:110,y:60)]
        let freehand = KnifeEditing.cut([rectangle], samples:drawn)!
        sameInk(path(rectangle,in:[rectangle]),union(freehand.nodes.map { path($0,in:freehand.nodes) }),"freehand covers original")
        require(freehand.nodes.allSatisfy { path($0,in:freehand.nodes).copy(strokingWithWidth:0.01,lineCap:.butt,lineJoin:.miter,miterLimit:4).contains(CGPoint(x:40,y:40)) },"cut boundary follows sampled bend")
        require(KnifeEditing.cut([rectangle], samples:[CGPoint(x:20,y:20),CGPoint(x:80,y:60)]) == nil,"interior open gesture does not invent extensions")
        let loop = [CGPoint(x:20,y:20),CGPoint(x:70,y:20),CGPoint(x:70,y:60),CGPoint(x:20,y:60),CGPoint(x:20,y:20)]
        let loopEdit = KnifeEditing.cut([rectangle],samples:loop)!
        sameInk(path(rectangle,in:[rectangle]),union(loopEdit.nodes.map { path($0,in:loopEdit.nodes) }),"closed loop covers original")
        let line = Node(name:"Line",frame:CGRect(x:0,y:0,width:100,height:0),content:.line(LineShape(start:.zero,end:CGPoint(x:100,y:0))))
        let lineEdit = KnifeEditing.cut([line],samples:[CGPoint(x:40,y:-10),CGPoint(x:40,y:10)])!
        require(lineEdit.nodes.count == 2 && abs(lineEdit.nodes[0].frame.maxX-40)<1e-5 && abs(lineEdit.nodes[1].frame.minX-40)<1e-5,"open line splits at actual finite crossing")
        let cubic = PathShape(points:[PathPoint(point:.zero,controlOut:CGPoint(x:0,y:100)),PathPoint(point:CGPoint(x:100,y:100),controlIn:CGPoint(x:100,y:0))],closed:false)
        let curveNode = Node(name:"Curve",frame:CGRect(x:0,y:0,width:100,height:100),content:.path(cubic))
        let curveEdit = KnifeEditing.cut([curveNode],samples:[CGPoint(x:50,y:-10),CGPoint(x:50,y:110)])!
        require(curveEdit.nodes.count == 2,"open cubic split")
        for p in stride(from:CGFloat(0),through:1,by:0.025) {
            let expected = CGPoint(x:300*p*p-200*p*p*p,y:300*p-600*p*p+400*p*p*p)
            let piece = curveEdit.nodes[p <= 0.5 ? 0 : 1]
            guard case .path(let shape) = piece.content, shape.points.count == 2,
                  let b = shape.points[0].controlOut, let c = shape.points[1].controlIn else { fatalError("cubic handles missing") }
            let a = shape.points[0].point, d = shape.points[1].point
            let t = p <= 0.5 ? 2*p : 2*p-1, u = 1-t
            let actual = VectorPathGeometry.pointToParent(CGPoint(x:u*u*u*a.x+3*u*u*t*b.x+3*u*t*t*c.x+t*t*t*d.x,
                y:u*u*u*a.y+3*u*u*t*b.y+3*u*t*t*c.y+t*t*t*d.y),node:piece)
            require(hypot(expected.x-actual.x,expected.y-actual.y)<1e-6,"analytic cubic retained after split at \(p)")
        }
        let bytes = Data([1,2,3,4])
        let image = Node(name:"Image",frame:CGRect(x:0,y:0,width:100,height:80),rotation:27,flipH:true,content:.image(ImageContent(data:bytes,naturalSize:CGSize(width:500,height:400))))
        let imagePoints = [CGPoint(x:-10,y:40),CGPoint(x:110,y:40)].map { VectorPathGeometry.pointToParent($0,node:image) }
        let imageEdit = KnifeEditing.cut([image],selected:[image.id],samples:imagePoints,straight:true)!
        require(imageEdit.nodes.count == 2 && imageEdit.nodes.allSatisfy(\.isMask),"raster becomes two masks")
        for piece in imageEdit.nodes {
            guard case .group(let kids) = piece.content, let pixels = kids.first(where:{ if case .image = $0.content { return true }; return false }),case .image(let data) = pixels.content else { fatalError("missing image pixels") }
            require(data.data == bytes && data.naturalSize == CGSize(width:500,height:400),"original pixels retained")
            let oldPoint = VectorPathGeometry.pointToParent(CGPoint(x:20,y:30),node:image)
            let newPoint = VectorPathGeometry.pointToParent(VectorPathGeometry.pointToParent(CGPoint(x:20,y:30),node:pixels),node:piece)
            require(hypot(oldPoint.x-newPoint.x,oldPoint.y-newPoint.y)<1e-7,"pixel mapping retained under rotation/flip")
            var unrotated = piece; unrotated.rotation = 0; unrotated.flipH = false
            let bounds = SelectionTransform.visualBounds(unrotated)
            require(abs(bounds.width-piece.frame.width)<1e-6 && abs(bounds.height-piece.frame.height)<1e-6,"mask selection bounds match visible cut piece")
            let painted = SelectionTransform.paintedBounds(unrotated)
            require(abs(painted.height-piece.frame.height)<1e-6 && abs(painted.width-piece.frame.width)<1e-6,"mask Inspector/outline bounds exclude hidden pixels")
        }
        var clip = rectangle; clip.isMaskShape = true
        let mask = Node(name:"Mask",frame:rectangle.frame,isMask:true,content:.group(children:[clip,line]))
        let maskEdit = KnifeEditing.cut([mask],selected:[clip.id],samples:[CGPoint(x:-10,y:40),CGPoint(x:110,y:40)],straight:true)!
        require(maskEdit.nodes.count == 2 && maskEdit.selection.contains(mask.id) && !maskEdit.selection.contains(clip.id),"selected mask shape cuts whole masked artwork")
        var outsideContent = image; outsideContent.frame.origin = CGPoint(x:300,y:300)
        let emptyMask = Node(name:"Empty mask",frame:rectangle.frame,rotation:45,isMask:true,content:.group(children:[clip,outsideContent]))
        for bounds in [SelectionTransform.visualBounds(emptyMask),SelectionTransform.paintedBounds(emptyMask)] {
            require(bounds.minX.isFinite && bounds.minY.isFinite && bounds.width.isFinite && bounds.height.isFinite,"empty rotated mask retains finite editable bounds")
        }
        let maskIndex = NodeTreeIndex(maskEdit.nodes)
        require(maskIndex.entries[clip.id] != nil && Set(maskIndex.entries.keys).count == 10,"mask content ids retained once and copies unique")
        let lower = rect("Lower"), top = rect("Top",10,0)
        let group = Node(name:"Targets",frame:rectangle.frame,content:.group(children:[lower,top]))
        let separate = rect("Separate",0,0)
        let scopeNodes = [separate,group]
        var settings = KnifeSettings.allTypes
        let scopeStroke = [CGPoint(x:-20,y:40),CGPoint(x:150,y:40)]
        let topEdit = KnifeEditing.cut(scopeNodes,samples:scopeStroke,settings:settings)!
        require(topEdit.selection.contains(top.id) && !topEdit.selection.contains(lower.id),"top scope")
        settings.scope = .group
        let groupEdit = KnifeEditing.cut(scopeNodes,samples:scopeStroke,settings:settings)!
        require(groupEdit.selection.count == 4 && !groupEdit.selection.contains(separate.id),"group scope")
        settings.scope = .all
        require(KnifeEditing.cut(scopeNodes,samples:scopeStroke,settings:settings)!.selection.count == 6,"all scopes")
        settings.shapes = false
        require(KnifeEditing.cut(scopeNodes,samples:scopeStroke,settings:settings) == nil,"type toggles exclude shapes")
        require(KnifeEditing.hit(scopeNodes,at:CGPoint(x:50,y:40),settings:.allTypes) == top.id,"click selects top eligible item")
        let nestedScope = Node(name:"Outer",frame:rectangle.frame,content:.group(children:[lower,
            Node(name:"Nested",frame:rectangle.frame,content:.group(children:[top]))]))
        settings = .allTypes; settings.scope = .group
        require(KnifeEditing.cut([separate,nestedScope],samples:scopeStroke,settings:settings)!.selection.count == 4,"group scope includes nested folder")
        var locked = top; locked.isLocked = true
        var hidden = top; hidden.id = UUID(); hidden.isVisible = false
        settings.scope = .all
        let protectedEdit = KnifeEditing.cut([lower,locked,hidden],samples:scopeStroke,settings:settings)!
        require(protectedEdit.selection.count == 2 && NodeTreeIndex(protectedEdit.nodes).entries[locked.id]!.node.isLocked,"hidden/locked layers excluded")
        let imageJSON = try JSONEncoder().encode(imageEdit.nodes)
        let reopenedImage = try JSONDecoder().decode([Node].self,from:imageJSON)
        require(reopenedImage.count == 2 && reopenedImage.allSatisfy(\.isMask),"masked image pieces persist")
        let ellipse = Node(name: "Ellipse", frame: rectangle.frame, content: .ellipse(EllipseShape(strokeWidth: 0)))
        let rounded = Node(name: "Rounded", frame: rectangle.frame,
                           content: .rectangle(RectangleShape(cornerRadius: 17, strokeWidth: 0)))
        for original in [rectangle, ellipse, rounded] {
            for (a,b) in [(CGPoint(x: -5,y: 40),CGPoint(x: 105,y: 40)),
                          (CGPoint(x: 50,y: -5),CGPoint(x: 50,y: 85)),
                          (CGPoint(x: -5,y: -5),CGPoint(x: 105,y: 85))] {
                let edit = VectorShapeEditing.cut([original], selected: [original.id], from: a, to: b)!
                require(edit.nodes.count == 2 && edit.selection.count == 2, "two editable selected pieces")
                require(edit.nodes[0].id == original.id && edit.nodes[1].id != original.id, "identity and fresh id")
                sameInk(path(original, in: [original]), union(edit.nodes.map { path($0, in: edit.nodes) }), "\(original.name) \(a) → \(b) split covers original ink")
                require(edit.nodes.allSatisfy { if case .path(let p) = $0.content { return p.closed }; return false }, "closed editable paths")
            }
        }
        let circlePieces = VectorShapeEditing.cut([ellipse], selected: [ellipse.id], from: CGPoint(x: 50,y: 0), to: CGPoint(x: 50,y: 80))!.nodes
        require(circlePieces.allSatisfy { n in
            guard case .path(let p) = n.content else { return false }
            return p.points.contains { $0.controlIn != nil || $0.controlOut != nil }
        }, "curve handles retained")
        let outer = CGMutablePath(); outer.addRect(CGRect(x: 0,y: 0,width: 100,height: 100))
        let hole = CGPath(rect: CGRect(x: 25,y: 25,width: 50,height: 50), transform: nil)
        let ring = outer.subtracting(hole, using: .winding)
        let cutRing = VectorPathGeometry.split(ring, from: CGPoint(x: 0,y: 50), to: CGPoint(x: 100,y: 50))!
        sameInk(ring, union(cutRing), "hole survives")
        require(cutRing.allSatisfy { !$0.contains(CGPoint(x: 50,y: 50), using: .winding) }, "no filled hole")
        let concave = CGMutablePath()
        concave.addLines(between: [CGPoint(x: 0,y: 0),CGPoint(x: 20,y: 0),CGPoint(x: 20,y: 60),
                                  CGPoint(x: 80,y: 60),CGPoint(x: 80,y: 0),CGPoint(x: 100,y: 0),
                                  CGPoint(x: 100,y: 100),CGPoint(x: 0,y: 100)]); concave.closeSubpath()
        let halves = VectorPathGeometry.split(concave, from: CGPoint(x: 0,y: 40), to: CGPoint(x: 100,y: 40))!
        sameInk(concave, union(halves), "concave compound cut")
        require(halves.contains { VectorPathGeometry.pathShape(from: $0, fill: .white)!.shape.isMultiContour }, "disconnected side stays one compound shape")
        for (a,b) in [(CGPoint.zero,CGPoint.zero),(CGPoint(x: 0,y: -20),CGPoint(x: 100,y: -20)),
                      (CGPoint.zero,CGPoint(x: 100,y: 0)),(CGPoint(x: -1,y: 1),CGPoint(x: 1,y: -1))] {
            require(VectorPathGeometry.split(path(rectangle, in: [rectangle]), from: a, to: b) == nil, "no-op/tangent must not create a sliver")
        }
        for angle in [0.0, 33.0, -90.0, 120.0] {
            for horizontal in [false,true] {
                for vertical in [false,true] {
                    var leaf = ellipse; leaf.rotation = angle; leaf.flipH = horizontal; leaf.flipV = vertical
                    let inner = Node(name: "Inner", frame: CGRect(x: 40,y: 30,width: 200,height: 160),
                                     rotation: -27, flipV: true, content: .group(children: [leaf]))
                    let root = Node(name: "Root", frame: CGRect(x: 120,y: 70,width: 400,height: 300),
                                    rotation: 41, flipH: true, content: .group(children: [inner]))
                    let nodes = [root], before = path(leaf, in: nodes), b = before.boundingBoxOfPath
                    let edit = VectorShapeEditing.cut(nodes, selected: [leaf.id], from: CGPoint(x: b.minX-5,y: b.midY), to: CGPoint(x: b.maxX+5,y: b.midY))!
                    let index = NodeTreeIndex(edit.nodes)
                    require(index.ancestorGroups(of: leaf.id).map(\.id) == [root.id,inner.id], "cut retains hierarchy")
                    sameInk(before, union(edit.selection.map { VectorShapeEditing.documentPath(index.entries[$0]!.node, index: index)! }), "rotated/mirrored cut stays in place")
                }
            }
        }
        var styled = rectangle
        var ps = VectorPathGeometry.pathShape(from: styled.content, size: styled.frame.size)!
        ps.fill = .gradient(GradientFill(angle: 17)); ps.strokePattern = .dashed; ps.strokeJoin = .bevel
        ps.strokeCap = .square; ps.strokeMiterLimit = 7; ps.strokeWidth = 3
        styled.content = .path(ps)
        for piece in VectorPathGeometry.cut(styled, from: CGPoint(x: 0,y: 40), to: CGPoint(x: 100,y: 40))! {
            guard case .path(let p) = piece.content else { fatalError() }
            require(p.fill == ps.fill && p.stroke == ps.stroke && p.strokeWidth == 3 && p.strokePattern == .dashed
                    && p.strokeCap == .square && p.strokeJoin == .bevel && p.strokeMiterLimit == 7, "inherit complete paint/stroke style")
        }
        let a = rect("A",10,20), b = rect("B",60,10)
        let nested = Node(name: "Nested", frame: CGRect(x: 20,y: 10,width: 200,height: 160), rotation: 19, flipH: true, content: .group(children: [b]))
        let folder = Node(name: "Folder", frame: CGRect(x: 30,y: 50,width: 300,height: 240), rotation: -13, flipV: true, content: .group(children: [a,nested]))
        let sibling = rect("Untouched", 500,500)
        let parent = Node(name: "Parent", frame: CGRect(x: 10,y: 20,width: 700,height: 700), rotation: 37, content: .group(children: [sibling,folder]))
        let original = [parent], scope = VectorOperationSelection.closed(in: NodeTreeIndex(original), selected: [folder.id,a.id,b.id], includingGroups: true)!
        require(scope.roots.map(\.id) == [folder.id] && scope.shapes.map(\.id) == [a.id,b.id], "nested folders and redundant selection deduplicate")
        let unite = VectorShapeEditing.unite(original, selected: [folder.id,a.id,b.id])!
        let index = NodeTreeIndex(unite.nodes), united = index.entries[folder.id]!.node
        require(unite.selection == [folder.id] && index.entries[a.id] == nil && index.entries[b.id] == nil, "folder becomes one selected path")
        require(index.ancestorGroups(of: folder.id).map(\.id) == [parent.id], "retain folder parent")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let siblingAfter = try encoder.encode(index.entries[sibling.id]!.node)
        let siblingBefore = try encoder.encode(sibling)
        require(siblingAfter == siblingBefore, "unselected sibling untouched")
        sameInk(union([path(a, in: original),path(b, in: original)]), VectorShapeEditing.documentPath(united, index: index)!, "nested unite transform parity")
        require(unite.removedIDs == [a.id,b.id,nested.id], "removed subtree references cleaned")
        let direct = VectorShapeEditing.unite(original, selected: [a.id,b.id])!
        require(direct.nodes.count == 2 && direct.selection.count == 1, "mixed parent leaves retain existing document promotion")
        sameInk(union([path(a, in: original),path(b, in: original)]), path(direct.nodes.last!, in: direct.nodes), "mixed parent geometry")
        for blocked in [0,1,2,3,4] {
            var bad = b
            if blocked == 0 { bad.isLocked = true }
            if blocked == 1 { bad.isVisible = false }
            if blocked == 2 { bad.content = .text(TextContent()) }
            if blocked == 3 { bad.content = .line(LineShape(start: .zero, end: CGPoint(x: 20,y: 20))) }
            if blocked == 4 { bad.isMask = true }
            let group = Node(name: "Mixed", frame: folder.frame, content: .group(children: [a,bad]))
            require(VectorShapeEditing.unite([group], selected: [group.id]) == nil, "reject mixed/hidden/locked folder wholly")
        }
        require(VectorShapeEditing.cut([folder], selected: [folder.id], from: .zero, to: CGPoint(x: 100,y: 100)) == nil, "knife requires explicit shapes")
        require(VectorShapeEditing.unite([folder], selected: [UUID()]) == nil, "missing selection")
        let encoded = try JSONEncoder().encode(unite.nodes)
        let reopened = try JSONDecoder().decode([Node].self, from: encoded)
        sameInk(path(united, in: unite.nodes), path(NodeTreeIndex(reopened).entries[folder.id]!.node, in: reopened), "save/reopen geometry")
        if CommandLine.arguments.count > 1 {
            let knife = Node(name: "Cut this ellipse", frame: CGRect(x: 70,y: 80,width: 240,height: 180),
                             content: .ellipse(EllipseShape(fill: .solid(RGBAColor(r: 0.1,g: 0.6,b: 0.8,a: 1)))))
            var one = rect("Shape A", 0,0,120,120)
            one.content = .rectangle(RectangleShape(fill: .solid(RGBAColor(r: 0.9,g: 0.4,b: 0.2,a: 1))))
            var two = rect("Shape B", 70,40,120,120)
            two.content = .rectangle(RectangleShape(fill: .solid(RGBAColor(r: 0.7,g: 0.25,b: 0.6,a: 1))))
            let inner = Node(name: "Nested folder", frame: CGRect(x: 0,y: 0,width: 200,height: 160),
                             content: .group(children: [two]))
            let folder = Node(name: "Unite this folder", frame: CGRect(x: 430,y: 80,width: 200,height: 160),
                              content: .group(children: [one,inner]))
            let text = Node(name: "Keep this text", frame: CGRect(x: 20,y: 30,width: 150,height: 35), content: .text(TextContent(string: "Keep this text")))
            let mixed = Node(name: "Mixed folder — keep intact", frame: CGRect(x: 430,y: 600,width: 220,height: 160), content: .group(children: [one,text]))
            let bitmap = CGContext(data:nil,width:32,height:24,bitsPerComponent:8,bytesPerRow:128,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            for y in 0..<24 { for x in 0..<32 {
                bitmap.setFillColor(CGColor(red:CGFloat(x)/32,green:CGFloat(y)/24,blue:0.6,alpha:1))
                bitmap.fill(CGRect(x:x,y:y,width:1,height:1))
            }}
            let png = NSMutableData()
            let destination = CGImageDestinationCreateWithData(png,"public.png" as CFString,1,nil)!
            CGImageDestinationAddImage(destination,bitmap.makeImage()!,nil); require(CGImageDestinationFinalize(destination),"PNG fixture")
            let photo = Node(name:"Cut this image",frame:CGRect(x:70,y:380,width:240,height:180),content:.image(ImageContent(data:png as Data,naturalSize:CGSize(width:32,height:24))))
            var photoChild = Document.duplicatingNode(photo); photoChild.frame.origin = .zero
            let maskClip = Node(name:"Ellipse mask",frame:CGRect(x:0,y:0,width:240,height:180),isMaskShape:true,content:.ellipse(EllipseShape()))
            let masked = Node(name:"Cut this mask",frame:CGRect(x:430,y:380,width:240,height:180),isMask:true,content:.group(children:[photoChild,maskClip]))
            // Distinct ids, even when the same visual fixture is reused.
            let fixture = Document(artboards: [Artboard(name: "Vector tools", frame: CGRect(x: 0,y: 0,width: 900,height: 800))],
                                   nodes: [knife,folder,Document.duplicatingNode(mixed),photo,masked])
            try encoder.encode(fixture).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("PASS: straight/freehand/loop cuts, exact open cubics/lines, masks/images/pixel transforms, target types/scopes/protection, curves/holes/no-ops, nested transforms, styles/ids, recursive Unite and persistence")
    }
}
