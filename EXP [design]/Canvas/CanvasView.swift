//
//  CanvasView.swift
//  EXP [design]
//
//  The canvas: an AppKit NSView (Core Graphics drawing) wrapped for SwiftUI.
//
//  THE WALL MODEL: every shape lives in `document.nodes` in DOCUMENT
//  coordinates. Artboard membership uses hysteresis: a wall shape enters when
//  more than half overlaps, then stays attached/cropped while ANY visible geometry
//  still overlaps. It returns to the wall only when completely outside. Drag an
//  artboard and the shapes it currently owns travel with it.
//
//  Coordinate spaces:
//   • document — where artboards and shapes live (frames).
//   • view     — pixels on screen: viewPoint = docPoint * zoom + pan.
//
//  Cosmetic chrome (shadow/border, halos, handles, marquee) draws in VIEW space
//  so it's a constant size at any zoom. Edits funnel through ExpDocument so each
//  gesture is one undo step.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreImage
import ImageIO   // downsampled image cache (CGImageSource thumbnails)

// MARK: - SwiftUI bridge

/// What a canvas instance edits: the whole document (top-level nodes + artboards),
/// or one component source's children (the source-editor window).
enum CanvasScope: Equatable {
    case document
    case source(UUID)
}

final class CanvasPageTransferRequest: NSObject {
    let pageID: UUID
    /// Context menus snapshot the selection when they open. SwiftUI/AppKit may
    /// retarget a List row while the menu is tracking; carrying the ids here
    /// prevents a multi-layer transfer from silently shrinking to that one row.
    /// App-menu requests leave these nil and intentionally use the live selection.
    let nodeIDs: Set<UUID>?
    let artboardIDs: Set<UUID>?

    init(pageID: UUID,
         nodeIDs: Set<UUID>? = nil,
         artboardIDs: Set<UUID>? = nil) {
        self.pageID = pageID
        self.nodeIDs = nodeIDs
        self.artboardIDs = artboardIDs
    }
}

struct CanvasView: NSViewRepresentable {
    let app: AppState
    @ObservedObject var document: ExpDocument
    var scope: CanvasScope = .document
    var documentURL: URL?

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.app = app
        view.document = document
        view.scope = scope
        view.documentURL = documentURL
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.app = app
        nsView.document = document
        nsView.scope = scope
        nsView.documentURL = documentURL
        _ = (app.zoom, app.panOffset, app.tool,
             app.selectedArtboardIDs, app.selectedNodeIDs,
             app.selectedGradientStopID,
             app.activeCanvasPageID,
             document.model.page(for: app.activeCanvasPageID)?.nodes.count ?? 0,
             document.model.page(for: app.activeCanvasPageID)?.artboards.count ?? 0,
             document.model.sources.count, app.sourceBackdrop,
             app.activeComponentStateID)   // state switch redraws the preview
        nsView.syncActivePageIfNeeded()
        // Inspector text-style changes are applied synchronously via
        // `app.applyTextStyle` (installed in beginEditingText), not through this
        // update cycle — see AppState.applyTextStyle.
        nsView.endPenIfNeeded()   // tool switched away (e.g. via the tools strip)
        nsView.syncPointSelectionIfNeeded()   // edited path/tool changed elsewhere (Layers panel, etc.)
        // A Layers-panel or other SwiftUI selection change can move selection
        // away from an active inline editor without sending the canvas a mouse
        // event. Commit on the next tick so the document mutation stays outside
        // SwiftUI's view-update pass.
        DispatchQueue.main.async { [weak nsView] in
            nsView?.commitTextEditingIfSelectionChanged()
        }
        nsView.refreshCursor()
        nsView.needsDisplay = true
    }
}

// MARK: - The drawing surface

/// Testing-Mode main-thread watchdog (PERF round 6, see docs/PERF-LOG.md).
/// A background thread pings the main queue every 100ms; if a ping takes
/// >250ms to land, the main thread was held that long by something outside
/// the draw buckets (save machinery, event routing, SwiftUI, ...). Lines go
/// to the diagnostic file, not the Xcode console.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()
    private var started = false
    private let lock = NSLock()

    func startIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return }
        started = true
        let thread = Thread {
            while true {
                let t0 = ProcessInfo.processInfo.systemUptime
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { sem.signal() }
                sem.wait()
                let dt = ProcessInfo.processInfo.systemUptime - t0
                if dt > 0.25 {
                    DiagnosticLog.shared.log(String(format: "[EXP watchdog] main thread held %.2fs  (t=%.1f)",
                                                    dt, ProcessInfo.processInfo.systemUptime))
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread.name = "exp.mainthread.watchdog"
        thread.qualityOfService = .userInitiated
        thread.start()
    }
}

final class CanvasNSView: NSView {

    weak var app: AppState?
    weak var document: ExpDocument?
    var scope: CanvasScope = .document
    var documentURL: URL?

    static let nodePasteboardType = NSPasteboard.PasteboardType("tapps.exp-design.nodes")
    static let artboardPasteboardType = NSPasteboard.PasteboardType("tapps.exp-design.artboards")

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    /// A draggable part of a path point (for the node / direct-selection tool).
    enum PathPointTarget {
        case anchor(Int, Int)       // (contour, index)
        case controlIn(Int, Int)
        case controlOut(Int, Int)
    }

    /// A path point's address within its (possibly multi-contour) shape — the
    /// (contour, index) pair `PathPointTarget.anchor` carries, but `Hashable`
    /// so a Set of these can track the node tool's multi-point selection.
    struct PointAddress: Hashable { let contour: Int; let index: Int }
    /// An anchor and its two control handles, in node-local space. `PointAddress`
    /// names ANCHORS only, which is also the answer to FEAT-026's "can a handle be
    /// transformed on its own" question: there is no such thing as a selected
    /// handle, so a handle always travels with the anchor that owns it.
    typealias PointBaseline = [PointAddress: (point: CGPoint, controlIn: CGPoint?, controlOut: CGPoint?)]

    /// Default board for a bare click with the artboard tool — the same size the
    /// New Artboard menu's primary action places.
    private static let defaultDrawnArtboardSize = CGSize(width: 375, height: 667)

    private enum DragMode {
        case none
        case hand
        case artboards(startDoc: CGPoint, boardOrigins: [UUID: CGPoint], childOrigins: [UUID: CGPoint])
        case resizeArtboard(id: UUID, handle: Handle, original: CGRect)
        case resizeSource(handle: Handle, original: CGRect)   // component viewBox resize
        case nodes(startDoc: CGPoint, origins: [UUID: CGPoint])
        case resize(id: UUID, handle: Handle, original: CGRect)
        case rotate(id: UUID, centerView: CGPoint, lastAngle: Double, rawRotation: Double)
        // Resize/rotate a whole selection as a unit: multiple top-level nodes, or a
        // single group (scaling its children). `original` is the selection's doc
        // bounds at drag start; the transform reads from `selectionDragBaseline`.
        case resizeSelection(handle: Handle, original: CGRect)
        case rotateSelection(centerDoc: CGPoint, startAngle: Double)
        case draw(id: UUID, originDoc: CGPoint)
        // Artboard tool. Separate from `.draw` because a board is NOT a node: it
        // lives on the page, so it writes through `withActivePage`, not `withNodes`.
        case drawArtboard(id: UUID, originDoc: CGPoint)
        case drawLine(id: UUID, startDoc: CGPoint)
        case lineEndpoint(id: UUID, movingStart: Bool, fixedDoc: CGPoint)
        case penHandle(nodeID: UUID, anchorIndex: Int)     // pen: drag the new anchor's handles
        // pencil: accumulate a freehand stroke. The samples live in
        // `pencilSamples` rather than the case so a long stroke does not copy an
        // ever-growing array on every enum assignment.
        case pencilStroke
        case pathPoint(nodeID: UUID, target: PathPointTarget)  // node tool: drag an anchor/handle
        // node tool: drag every selected anchor/handle together by the same
        // delta, so grabbing one selected point (or the shape body, see
        // `nodeToolMouseDown`) moves the whole multi-point selection.
        case pathPointGroup(nodeID: UUID, startLocal: CGPoint,
                             originals: [PointAddress: (point: CGPoint, controlIn: CGPoint?, controlOut: CGPoint?)])
        // node tool: resize / rotate the SELECTED POINTS as a unit (FEAT-026).
        // `original` is the padded box in NODE-LOCAL space at drag start and
        // `originals` the points it acts on, so every tick transforms from a stable
        // baseline instead of accumulating rounding.
        case resizePoints(nodeID: UUID, handle: Handle, original: CGRect,
                          originals: PointBaseline)
        case rotatePoints(nodeID: UUID, centerLocal: CGPoint, startAngle: Double,
                          originals: PointBaseline)
        // FEAT-032: drag the on-canvas gradient line. `movingStart` picks the end;
        // a stop is addressed by its own id because `sortedStops` reorders.
        case gradientEnd(id: UUID, movingStart: Bool)
        case gradientStop(id: UUID, stopID: UUID)
        case marquee(startView: CGPoint, additive: Bool)
        // node tool: box-select points of the path currently being edited.
        case pointMarquee(startView: CGPoint, additive: Bool)
        case drawTextBox(originView: CGPoint)   // text tool: drag a paragraph box
        case guide                              // creating or moving a ruler guide
    }

    private var dragMode: DragMode = .none
    private var dragBaseline: Document?
    /// Option-drag-duplicate state for the CURRENT `.nodes` gesture (BUG-025).
    /// `dragCopyActive` is whether copies are materialized right now;
    /// `dragCopySourceSelection` is the selection as it stood at mouseDown, so the
    /// gesture can flip back to moving the originals when Option is released.
    private var dragCopyActive = false
    private var dragCopySourceSelection: Set<UUID> = []
    private var didEdit = false
    private var gestureUndoName = "Edit"
    private var lastDragPoint: CGPoint?
    private var marqueeCurrent: CGPoint?

    /// The node tool's multi-selected path points (anchors), by address.
    /// Cleared whenever the edited path or tool changes — see
    /// `syncPointSelectionIfNeeded`.
    private var selectedPointAddresses: Set<PointAddress> = []
    /// Which path's points `selectedPointAddresses` belongs to, so a change of
    /// edited shape (or leaving the node tool) clears a stale selection.
    private var lastEditedPathID: UUID?

    /// True while ⌥ is held with the pointer over the canvas — drives the Figma-style
    /// spacing-measurement overlay (distances from the selection to the hovered shape
    /// or the artboard edges).
    private var optionHeld = false

    /// A guide being CREATED by dragging from a ruler (not yet in the model — drawn
    /// as a live preview). nil between gestures.
    private var draggingGuide: Guide?
    /// An EXISTING guide being moved (mutated live in the model by id; dropping it on
    /// a ruler deletes it).
    private var movingGuideID: UUID?

    // Pen tool session (spans multiple clicks until closed/finished).
    private var penNodeID: UUID?
    private var penBaseline: Document?
    // Pencil (FEAT-029). Samples are captured in DOCUMENT space so zoom never
    // changes what gets drawn — only how densely it is sampled on screen.
    private var pencilNodeID: UUID?
    private var pencilBaseline: Document?
    private var pencilSamples: [CGPoint] = []

    // Node tool: a point-group drag that started on the path BODY (not an anchor),
    // so a click-without-drag there deselects the points (Adobe direct-select).
    private var pointGroupFromBody = false

    // The node's flip state at the start of a resize drag, so dragging a handle
    // PAST the opposite edge mirrors the object (relative to where it started).
    private var resizeFlipBaseline: (h: Bool, v: Bool) = (false, false)

    // The path anchor a right-click landed on (for the corner/curve menu item).
    private var pendingCurveToggle: (id: UUID, contour: Int, index: Int)?

    // Retained while an export Save/Open panel (with its format accessory) is up.
    private var exportPanels: ExportPanels?
    /// Most recent fidelity report stays available on demand without turning a
    /// successful import into a modal interruption.
    private var lastImportReport: InteropImportReport?

    // The path shape at the start of a resize drag, so points scale from a stable
    // baseline (set when a path's resize handle is grabbed).
    private var resizePathBaseline: PathShape?
    /// Geometry→ink insets for the node being resized (BUG-036(a)). Captured at drag
    /// start because they cannot change during the drag: a resize does not alter
    /// stroke width. The handle drag is computed in INK terms so the box tracks the
    /// cursor, then inset back to geometry, which is what the model stores.
    private var resizeInkInsets = SelectionTransform.InkInsets.zero

    // Snapshot of each selected top-level node at the start of a selection
    // resize/rotate gesture, so every drag tick transforms from a stable baseline
    // (no cumulative drift). Keyed by node id.
    private var selectionDragBaseline: [UUID: Node] = [:]   // SELECTION-SPACE snapshot
    /// Offset of each baselined node from the selection space's origin to its own
    /// parent's, so the transform can convert its result back to parent-local on write.
    private var selectionDragOffsets: [UUID: CGPoint] = [:]
    /// FEAT-045: the stop a mouse-DOWN landed on. If the mouse comes up without a
    /// drag it was a click, and a click opens that stop's editor.
    private var gradientStopClickCandidate: UUID?
    /// The live gradient-stop editor popover, so a second click closes rather than
    /// stacking another one.
    private var gradientStopPopover: NSPopover?
    /// What a gradient context menu is acting on: the gradient's node, the stop under
    /// the pointer (nil when the click was on bare line), and `t` — the position along
    /// the line where the click landed. `t` is what Paste uses, so a stop lands where
    /// you asked for it rather than where it came from.
    private var pendingGradientMenu: (nodeID: UUID, stopID: UUID?, t: CGFloat)?

    /// The ancestor chain the in-flight selection transform is expressed in (BUG-035).
    /// Empty = document space. Captured at drag start so the math cannot change space
    /// mid-gesture if the selection or tree shifts underneath it.
    private var selectionDragChain: [Node] = []
    /// Geometry→ink insets of the unified selection box for the in-flight gesture.
    private var selectionDragInkInsets = SelectionTransform.InkInsets.zero

    private var spaceHeld = false
    private var lastMouse: CGPoint = .zero
    private var trackingArea: NSTrackingArea?
    private var spaceKeyUpMonitor: Any?
    private var observesAppDeactivation = false

    private let handleSize: CGFloat = 8
    private let handleGrab: CGFloat = 12
    /// How much closer than the anchor a curve handle must be before it wins the
    /// click (view points). Small on purpose: it only needs to cover a handle
    /// sitting ON its anchor, not to re-create the old exclusive radius. BUG-027.
    private static let anchorPriorityBias: CGFloat = 3
    private let rulerThickness: CGFloat = 20

    private var didInitialFit = false
    private var cameraPersistTimer: Timer?
    private var lastPersistedCamera: PersistedCanvasCamera?
    private var lastActivePageID: UUID?
    /// A cross-page move/duplicate should reveal its result, not restore an old
    /// destination camera and make the designer hunt for it. Consumed by the
    /// same page-switch funnel that normally restores per-page view state.
    private var pendingPageFocus: (pageID: UUID, bounds: CGRect)?

    // Inline text editing: an NSTextView overlay sits over the node while you
    // type; the model is updated on commit.
    private var editingNodeID: UUID?
    private var textEditor: NSTextView?

    // Stable working copy of the editor's attributed text. NSTextView can adjust
    // selection/typing state while first responder moves between the canvas and
    // Inspector. Committing this snapshot keeps per-run attributes independent of
    // that focus lifecycle; every actual text/style mutation refreshes it.
    private var textEditSnapshot: NSAttributedString?

    // The editor's last *user-driven* selection. Clicking an Inspector control
    // resigns the text view's first responder, which collapses its live
    // `selectedRange()` to a caret — so we remember the real selection here (only
    // updated while the editor is focused) and target it when applying Inspector
    // style changes. Without this, a size/color change made via the Inspector lands
    // on typing-attributes instead of the selected text and is lost on commit.
    private var editorSelectedRange = NSRange(location: 0, length: 0)

    // Inline artboard rename (a one-line NSTextField over the name label).
    private var editingArtboardID: UUID?
    private var artboardNameField: NSTextField?

    // Font-size scale the active text editor renders at. Keep the editor on the
    // proven scaled-font path; a custom-bounds NSTextView caused TextKit crashes
    // in an earlier session.
    private var textEditScale: CGFloat = 1
    private var editingIsNew = false
    private var textEditBaseline: Document?
    private var committingText = false

    // MARK: Smart Guides
    
    /// Active smart guide lines shown during drag (Figma/XD-style).
    private struct SmartGuideLine {
        enum Axis { case horizontal, vertical }
        var axis: Axis
        var position: CGFloat       // doc coordinate
        var matchedEdges: [CGFloat] // doc coords of aligned elements (for visual extent)
    }
    private var activeSmartGuides: [SmartGuideLine] = []

    // MARK: Setup

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    private func configureAccessibility() {
        // The canvas uses oversized halo bitmaps during fast pan/zoom. SwiftUI's
        // NSViewRepresentable hosting can briefly composite that backing surface
        // above an adjacent SwiftUI sibling unless the native layer owns an
        // explicit clip. Keep every live/snapshot pixel inside the canvas frame;
        // chrome such as the page-tab strip must never become part of the wall.
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Design canvas")
        setAccessibilityRoleDescription("design canvas")
        observeNoiseTiles()
    }

    /// Noise / dissolve tiles are generated off the render thread (see
    /// TurbulenceNoise): a cold tile returns nil so the gesture never blocks, and
    /// posts `tileReadyNotification` once it lands. React by dropping any pan/zoom
    /// snapshot (it may have been captured before the grain existed) and redrawing
    /// so the effect appears now that it's cache-warm.
    private func observeNoiseTiles() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(noiseTileBecameReady),
            name: TurbulenceNoise.tileReadyNotification, object: nil)
    }

    @objc private func noiseTileBecameReady() {
        panZoomSnapshot = nil
        needsDisplay = true
    }

    deinit {
        cameraPersistTimer?.invalidate()
        if let spaceKeyUpMonitor { NSEvent.removeMonitor(spaceKeyUpMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        // Accept image / SVG files and raw image-or-SVG data dragged onto the canvas.
        registerForDraggedTypes([.fileURL, .png, .tiff, .string,
                                 NSPasteboard.PasteboardType(UTType.svg.identifier)])
        // Temporary Space-pan begins while the canvas owns keyboard focus, but
        // its key-up may arrive after a panel/editor takes focus. Observe that
        // release anywhere in EXP so the hand cursor cannot remain stuck.
        if spaceKeyUpMonitor == nil {
            spaceKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
                [weak self] event in
                if event.keyCode == 49 { self?.endTemporaryPan() }
                return event
            }
        }
        if !observesAppDeactivation {
            observesAppDeactivation = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(applicationDidResignActive),
                name: NSApplication.didResignActiveNotification, object: nil)
        }
    }

    override func layout() {
        super.layout()
        // Report viewport size so AppState's zoom commands can keep the center.
        if app?.viewportSize != bounds.size { app?.viewportSize = bounds.size }
        if !didInitialFit, bounds.width > 1, bounds.height > 1 {
            didInitialFit = true
            if !restorePersistedCamera() {
                fitContent()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Camera persistence

    /// Local view state for reopening a document near the last working area.
    /// Stored in UserDefaults keyed by file URL: it is not part of the design data,
    /// so ordinary pan/zoom does not dirty the document or create undo steps.
    private struct PersistedCanvasCamera: Codable, Equatable {
        var zoom: Double
        var centerX: Double
        var centerY: Double
        var viewportWidth: Double
        var viewportHeight: Double
    }

    private func persistedCameraKey(for pageID: UUID?) -> String? {
        guard !isSourceScope, let path = documentURL?.standardizedFileURL.path,
              !path.isEmpty else { return nil }
        var encoded = Data(path.utf8).base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: ".")
        let page = pageID?.uuidString ?? "default"
        return "exp.canvas.camera.v2.\(encoded).\(page)"
    }

    private var persistedCameraKey: String? { persistedCameraKey(for: activePageID) }

    private func currentPersistedCamera() -> PersistedCanvasCamera? {
        guard let app, didInitialFit, bounds.width > 1, bounds.height > 1 else { return nil }
        let center = viewToDoc(viewCenter)
        let camera = PersistedCanvasCamera(
            zoom: Double(app.zoom),
            centerX: Double(center.x),
            centerY: Double(center.y),
            viewportWidth: Double(bounds.width),
            viewportHeight: Double(bounds.height))
        guard camera.zoom.isFinite, camera.centerX.isFinite, camera.centerY.isFinite else { return nil }
        return camera
    }

    func scheduleCameraPersistenceIfReady() {
        guard persistedCameraKey != nil, currentPersistedCamera() != nil else { return }
        cameraPersistTimer?.invalidate()
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.persistCameraNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        cameraPersistTimer = timer
    }

    private func persistCameraNow() {
        persistCameraNow(for: activePageID)
    }

    private func persistCameraNow(for pageID: UUID?) {
        guard let key = persistedCameraKey(for: pageID),
              let camera = currentPersistedCamera(),
              camera != lastPersistedCamera,
              let data = try? JSONEncoder().encode(camera) else { return }
        UserDefaults.standard.set(data, forKey: key)
        lastPersistedCamera = camera
    }

    private func restorePersistedCamera() -> Bool {
        guard let app, let key = persistedCameraKey,
              let data = UserDefaults.standard.data(forKey: key),
              let camera = try? JSONDecoder().decode(PersistedCanvasCamera.self, from: data),
              camera.zoom.isFinite, camera.centerX.isFinite, camera.centerY.isFinite else { return false }
        let zoom = app.clampZoom(CGFloat(camera.zoom))
        app.zoom = zoom
        app.panOffset = CGPoint(x: viewCenter.x - CGFloat(camera.centerX) * zoom,
                                y: viewCenter.y - CGFloat(camera.centerY) * zoom)
        lastPersistedCamera = camera
        needsDisplay = true
        return true
    }

    /// Called from the representable update whenever the browser-style page tab
    /// changes. Each page restores its own camera; selection and transient editing
    /// cannot cross a page boundary.
    func syncActivePageIfNeeded() {
        guard !isSourceScope, let document, let app,
              let resolved = document.model.pageID(resolving: app.activeCanvasPageID) else { return }
        if app.activeCanvasPageID != resolved { app.activeCanvasPageID = resolved }
        guard lastActivePageID != resolved else { return }
        if let previous = lastActivePageID { persistCameraNow(for: previous) }
        commitTextEditing(keepNodeSelected: false)
        lastActivePageID = resolved
        lastPersistedCamera = nil
        panZoomBlitActive = false
        panZoomSnapshot = nil
        guard didInitialFit, bounds.width > 1, bounds.height > 1 else { return }
        app.zoom = 1
        app.panOffset = .zero
        if let focus = pendingPageFocus, focus.pageID == resolved {
            pendingPageFocus = nil
            fitViewport(to: focus.bounds)
        } else {
            pendingPageFocus = nil
            if !restorePersistedCamera() { fitContent() }
        }
        needsDisplay = true
    }

    // MARK: Camera helpers

    private func docToView(_ rect: CGRect) -> CGRect {
        guard let app else { return rect }
        return CGRect(x: rect.minX * app.zoom + app.panOffset.x,
                      y: rect.minY * app.zoom + app.panOffset.y,
                      width: rect.width * app.zoom, height: rect.height * app.zoom)
    }

    private func viewToDoc(_ p: CGPoint) -> CGPoint {
        guard let app else { return p }
        return CGPoint(x: (p.x - app.panOffset.x) / app.zoom,
                       y: (p.y - app.panOffset.y) / app.zoom)
    }

    private func viewToDoc(_ rect: CGRect) -> CGRect {
        let a = viewToDoc(CGPoint(x: rect.minX, y: rect.minY))
        let b = viewToDoc(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func docToViewPoint(_ p: CGPoint) -> CGPoint {
        guard let app else { return p }
        return CGPoint(x: p.x * app.zoom + app.panOffset.x, y: p.y * app.zoom + app.panOffset.y)
    }

    /// Absolute document-space endpoints of a line node, given a parent offset
    /// (.zero at top level; the group's absolute origin when nested).
    private func lineEndpointsDoc(_ node: Node, offset: CGPoint = .zero) -> (a: CGPoint, b: CGPoint)? {
        guard case .line(let ls) = node.content else { return nil }
        let ox = offset.x + node.frame.minX, oy = offset.y + node.frame.minY
        return (CGPoint(x: ox + ls.start.x, y: oy + ls.start.y),
                CGPoint(x: ox + ls.end.x,   y: oy + ls.end.y))
    }

    /// Both line endpoints in DOCUMENT space, honoring the node's own rotation/flip
    /// AND ancestor group transforms — so a line nested in a group hit-tests and
    /// drags from the right place (the unresolved `lineEndpointsDoc` only knows the
    /// node's own frame, which is parent-local for a nested line).
    private func lineEndpointsResolvedDoc(_ n: Node) -> (a: CGPoint, b: CGPoint)? {
        guard case .line(let ls) = n.content else { return nil }
        let chain = ancestorGroups(of: n.id)
        func toDoc(_ local: CGPoint) -> CGPoint {
            var lp = local
            if n.flipH { lp.x = n.frame.width - lp.x }
            if n.flipV { lp.y = n.frame.height - lp.y }
            var pl = CGPoint(x: n.frame.minX + lp.x, y: n.frame.minY + lp.y)
            if n.rotation != 0 {
                pl = rotatePoint(pl, around: CGPoint(x: n.frame.midX, y: n.frame.midY), byDegrees: n.rotation)
            }
            return parentLocalToDoc(pl, chain: chain)
        }
        return (toDoc(ls.start), toDoc(ls.end))
    }

    /// Snap a line endpoint to a 45° increment around the fixed end (horizontal,
    /// vertical, or diagonal), preserving the cursor distance — the shift-constrain
    /// for drawing/editing a line. Doc space.
    private func constrainLineEndpoint(_ p: CGPoint, from fixed: CGPoint) -> CGPoint {
        let dx = p.x - fixed.x, dy = p.y - fixed.y
        let r = hypot(dx, dy)
        guard r > 0 else { return p }
        let step = Double.pi / 4
        let ang = (atan2(Double(dy), Double(dx)) / step).rounded() * step
        return CGPoint(x: fixed.x + CGFloat(cos(ang)) * r, y: fixed.y + CGFloat(sin(ang)) * r)
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        if dx == 0 && dy == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Which nodes get the 8-handle box + rotate knob on the canvas. Lines use
    /// endpoint handles; groups/instances aren't box-resizable yet. Paths get the
    /// box too (resize scales their points) AND keep point-editing via the A tool.
    private func isBoxResizable(_ node: Node) -> Bool {
        switch node.content {
        case .rectangle, .ellipse, .polygon, .text, .path, .image: return true
        default: return false
        }
    }

    /// A doc-space cursor → the node's UNROTATED local coords (relative to the
    /// frame origin). Inverse of `localToDoc`. Used by pen/point editing so they
    /// work correctly on a rotated node.
    private func docToLocal(_ doc: CGPoint, _ node: Node) -> CGPoint {
        let unrot = node.rotation == 0 ? doc
            : rotatePoint(doc, around: CGPoint(x: node.frame.midX, y: node.frame.midY), byDegrees: -node.rotation)
        return CGPoint(x: unrot.x - node.frame.minX, y: unrot.y - node.frame.minY)
    }

    /// A node-local point → doc space, applying the node's rotation about center.
    private func localToDoc(_ local: CGPoint, _ node: Node) -> CGPoint {
        let doc = CGPoint(x: node.frame.minX + local.x, y: node.frame.minY + local.y)
        return node.rotation == 0 ? doc
            : rotatePoint(doc, around: CGPoint(x: node.frame.midX, y: node.frame.midY), byDegrees: node.rotation)
    }

    /// A view-space NSBezierPath for a path shape (cubic segments; missing handles
    /// collapse to the anchor, i.e. a straight segment).
    private func bezierPath(for ps: PathShape, frameOrigin: CGPoint) -> NSBezierPath {
        let bez = NSBezierPath()
        func v(_ local: CGPoint) -> CGPoint {
            docToViewPoint(CGPoint(x: frameOrigin.x + local.x, y: frameOrigin.y + local.y))
        }
        func addContour(_ pts: [PathPoint], closed: Bool) {
            guard !pts.isEmpty else { return }
            bez.move(to: v(pts[0].point))
            for i in 1..<pts.count {
                let prev = pts[i - 1], cur = pts[i]
                bez.curve(to: v(cur.point),
                          controlPoint1: v(prev.controlOut ?? prev.point),
                          controlPoint2: v(cur.controlIn ?? cur.point))
            }
            if closed && pts.count >= 2 {
                let last = pts[pts.count - 1], first = pts[0]
                bez.curve(to: v(first.point),
                          controlPoint1: v(last.controlOut ?? last.point),
                          controlPoint2: v(first.controlIn ?? first.point))
                bez.close()
            }
        }
        if ps.isMultiContour {
            for c in ps.renderContours { addContour(c, closed: true) }
            // Nonzero (the font's intended rule): outer + counter contours are wound
            // oppositely so holes appear, but OVERLAPPING contours (grunge faces, an
            // 'e' bar built from overlap) fill as a union instead of subtracting.
            bez.windingRule = .nonZero
        } else {
            addContour(ps.points, closed: ps.closed)
        }
        return bez
    }

    /// The path's ink in NODE-LOCAL coordinates — the same curve construction as
    /// `bezierPath(for:)` but with no view transform. `nodeHit` tests clicks
    /// against this geometry; `.winding` at containment time matches the
    /// renderer's `.nonZero` rule so holes/counters pass through.
    private static func inkPath(for ps: PathShape) -> CGPath {
        let path = CGMutablePath()
        func add(_ pts: [PathPoint], closed: Bool) {
            guard let first = pts.first else { return }
            path.move(to: first.point)
            for i in 1..<pts.count {
                let prev = pts[i - 1], cur = pts[i]
                path.addCurve(to: cur.point,
                              control1: prev.controlOut ?? prev.point,
                              control2: cur.controlIn ?? cur.point)
            }
            if closed && pts.count >= 2 {
                let last = pts[pts.count - 1]
                path.addCurve(to: first.point,
                              control1: last.controlOut ?? last.point,
                              control2: first.controlIn ?? first.point)
                path.closeSubpath()
            }
        }
        if ps.isMultiContour { for c in ps.renderContours { add(c, closed: true) } }
        else { add(ps.points, closed: ps.closed) }
        return path
    }

    /// Whether a paint draws anything a click could reasonably target: a fully
    /// transparent solid is "no fill", so only the outline is grabbable.
    private func paintHittable(_ p: Paint) -> Bool {
        if case .solid(let c) = p { return c.a > 0.001 }
        return true   // gradients always count
    }

    /// A closed bezier through polygon vertices (shared shape: build once, fill/stroke).
    static func polygonBezier(_ verts: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = verts.first else { return path }
        path.move(to: first)
        for v in verts.dropFirst() { path.line(to: v) }
        path.close()
        return path
    }

    /// The single selected path node (for the node / direct-selection tool).
    private func selectedPath() -> (id: UUID, ps: PathShape, origin: CGPoint)? {
        guard let app, let id = app.singleSelectedNodeID, let n = node(id),
              case .path(let ps) = n.content else { return nil }
        return (id, ps, n.frame.origin)
    }

    /// Which anchor/handle of the selected path is under a view point, if any.
    private func hitTestPathPoint(atViewPoint p: CGPoint) -> (id: UUID, target: PathPointTarget)? {
        guard let sel = selectedPath(), let n = node(sel.id) else { return nil }
        let chain = ancestorGroups(of: n.id)
        let contours = sel.ps.editContours
        if perf.enabled {
            perf.gauge("pathPts", contours.reduce(0) { $0 + $1.count })
            perf.gauge("selectedPts", selectedPointAddresses.count)
        }

        // Point/handle chrome is constant-size in view space, but the node/group
        // transforms are rotation/flip/translate only. Convert the cursor once and
        // compare in local units instead of projecting every point/handle to view
        // space on each click.
        let local = viewToNodeLocal(p, n, chain: chain)
        let grab = handleGrab / max(app?.zoom ?? 1, 0.0001)
        func dist(_ q: CGPoint) -> CGFloat { hypot(local.x - q.x, local.y - q.y) }

        // Anchors win when they overlap their own handles. That matches what users
        // see (the anchor square sits on top) and prevents collapsed handles from
        // stealing attempts to move the actual point.
        var bestAnchor: (target: PathPointTarget, distance: CGFloat)?
        for (c, pts) in contours.enumerated() {
            for (i, pt) in pts.enumerated() {
                let d = dist(pt.point)
                if d <= grab, bestAnchor == nil || d < bestAnchor!.distance {
                    bestAnchor = (.anchor(c, i), d)
                }
            }
        }
        // NOTE: the anchor is NOT returned yet — see the arbitration below. This
        // used to `return` here the moment any anchor fell inside `grab`, which
        // meant the anchor owned its entire 12pt radius outright and a handle
        // sitting anywhere inside it was unreachable at any practical zoom
        // (BUG-027: "changing curve handles that are really close but not on top
        // of the base point require zooming several hundred percent in").

        // Only selected anchors expose handles, so only those handles should be
        // interactive. This also keeps dense imported SVG paths from checking
        // invisible handles on every point click.
        var bestHandle: (target: PathPointTarget, distance: CGFloat)?
        for addr in selectedPointAddresses {
            guard contours.indices.contains(addr.contour),
                  contours[addr.contour].indices.contains(addr.index) else { continue }
            let pt = contours[addr.contour][addr.index]
            if let cin = pt.controlIn {
                let d = dist(cin)
                if d <= grab, bestHandle == nil || d < bestHandle!.distance {
                    bestHandle = (.controlIn(addr.contour, addr.index), d)
                }
            }
            if let cout = pt.controlOut {
                let d = dist(cout)
                if d <= grab, bestHandle == nil || d < bestHandle!.distance {
                    bestHandle = (.controlOut(addr.contour, addr.index), d)
                }
            }
        }
        // Arbitrate. The original intent — an anchor beats a handle COLLAPSED ON
        // TOP of it, because the anchor square is what the user sees there — was
        // right and is preserved by the bias. What was wrong was expressing that as
        // an exclusive radius rather than as a tie-break: the anchor now wins only
        // where it is actually the nearer target, plus `anchorBias` of slack.
        // Worked example at zoom 1, handle 5pt from its anchor: cursor on the
        // handle → 5 <= 0 + 3 is false, handle wins; cursor on the anchor →
        // 0 <= 5 + 3 is true, anchor wins; handle fully collapsed onto the anchor →
        // distances equal, anchor wins. Bias is in view points and converted the
        // same way `grab` is, so the feel is zoom-independent.
        let anchorBias = Self.anchorPriorityBias / max(app?.zoom ?? 1, 0.0001)
        switch (bestAnchor, bestHandle) {
        case (let a?, let h?): return (sel.id, a.distance <= h.distance + anchorBias ? a.target : h.target)
        case (let a?, nil):    return (sel.id, a.target)
        case (nil, let h?):    return (sel.id, h.target)
        case (nil, nil):       return nil
        }
    }

    /// Recompute a path node's frame to the bbox of its anchors, re-basing all
    /// local points + handles so absolute positions stay put.
    private func normalizePath(_ id: UUID) {
        updateNode(id) { Self.normalizePathNode(&$0) }
    }

    /// Pure/in-place half of `normalizePath`, shared by point edits that already
    /// hold a pending node array. Keeping frame + path coordinates in one mutation
    /// lets keyboard/Inspector edits commit as ONE undo step instead of committing
    /// geometry first and repairing the bounds in a second write.
    private static func normalizePathNode(_ node: inout Node) {
        guard case .path(var ps) = node.content else { return }
        var cs = ps.editContours
        guard !cs.isEmpty, !cs.allSatisfy({ $0.isEmpty }) else { return }
        let oldCenter = CGPoint(x: node.frame.midX, y: node.frame.midY)

        // Bbox from every contour's anchors AND control handles, not anchors
        // alone — a bezier curve never leaves the convex hull of its anchor +
        // handle points, so including handles guarantees the new frame always
        // encloses the actual curve (rendering never clips a path to its own
        // node.frame — only artboards clip, see drawDocument — so a frame that
        // grows or shrinks here is always safe). This used to skip multi-contour
        // (outlined-text) paths entirely, leaving a stale frame once points were
        // dragged outside it — and `nodeHit` relies on the frame ENCLOSING the
        // ink as its fast bounding-box reject, so a stale frame makes the parts
        // of the shape outside the old box unclickable.
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for pts in cs {
            for pt in pts {
                xs.append(node.frame.minX + pt.point.x); ys.append(node.frame.minY + pt.point.y)
                if let c = pt.controlIn { xs.append(node.frame.minX + c.x); ys.append(node.frame.minY + c.y) }
                if let c = pt.controlOut { xs.append(node.frame.minX + c.x); ys.append(node.frame.minY + c.y) }
            }
        }
        guard let minX = xs.min(), let minY = ys.min(),
              let maxX = xs.max(), let maxY = ys.max() else { return }

        let newOrigin = CGPoint(x: minX, y: minY)
        let dx = node.frame.minX - newOrigin.x
        let dy = node.frame.minY - newOrigin.y

        for c in cs.indices {
            for i in cs[c].indices {
                cs[c][i].point.x += dx
                cs[c][i].point.y += dy
                if cs[c][i].controlIn != nil {
                    cs[c][i].controlIn!.x += dx
                    cs[c][i].controlIn!.y += dy
                }
                if cs[c][i].controlOut != nil {
                    cs[c][i].controlOut!.x += dx
                    cs[c][i].controlOut!.y += dy
                }
            }
        }

        let width = max(1, maxX - minX)
        let height = max(1, maxY - minY)
        let size = CGSize(width: width, height: height)

        // Re-basing the bbox moves the frame CENTER — the pivot BOTH rotation
        // and flip mirror about — so an unadjusted origin shifts the rendered
        // ink. Most visible on FLIPPED paths: the whole shape "walked"
        // sideways whenever a point drag grew or shrank the box, because the
        // old math only kept the unflipped coordinates fixed. Keep the ink
        // fixed for ANY rotation + flip combination instead:
        //   rendered(p) = C + R·F·(p − c)     C: frame center (doc space),
        //   c: local center, F: flip mirror, R: rotation about the center
        // ⇒ the new center must be C′ = C + R·F·(c′ − c − d), where d is the
        // shift just applied to the local points. With no rotation and no
        // flip this reduces to finalOrigin == newOrigin (the old behavior).
        var v = CGPoint(x: size.width / 2 - node.frame.width / 2 - dx,
                        y: size.height / 2 - node.frame.height / 2 - dy)
        if node.flipH { v.x = -v.x }
        if node.flipV { v.y = -v.y }
        if node.rotation != 0 {
            let r = node.rotation * .pi / 180, s = sin(r), c = cos(r)
            v = CGPoint(x: v.x * c - v.y * s, y: v.x * s + v.y * c)
        }
        let finalOrigin = CGPoint(x: oldCenter.x + v.x - size.width / 2,
                                  y: oldCenter.y + v.y - size.height / 2)

        ps.writeEditContours(cs)
        node.frame = CGRect(origin: finalOrigin, size: size)
        node.content = .path(ps)
    }

    // MARK: Pen tool

    private func penMouseDown(_ p: CGPoint) {
        guard let app, let document else { return }
        let docP = viewToDoc(p)

        if let penID = penNodeID, let n = node(penID), case .path(let ps) = n.content {
            // Click the first anchor (with ≥2 points) closes the path.
            if ps.points.count >= 2 {
                let firstView = docToViewPoint(CGPoint(x: n.frame.minX + ps.points[0].point.x,
                                                       y: n.frame.minY + ps.points[0].point.y))
                if hypot(p.x - firstView.x, p.y - firstView.y) <= handleGrab {
                    updateNode(penID) { if case .path(var p2) = $0.content { p2.closed = true; $0.content = .path(p2) } }
                    finishPen()
                    return
                }
            }
            // Otherwise append a new anchor; arm a handle-drag for it.
            var newIndex = 0
            updateNode(penID) {
                if case .path(var p2) = $0.content {
                    let local = CGPoint(x: docP.x - n.frame.minX, y: docP.y - n.frame.minY)
                    p2.points.append(PathPoint(point: local))
                    newIndex = p2.points.count - 1
                    $0.content = .path(p2)
                }
            }
            normalizePath(penID)
            dragMode = .penHandle(nodeID: penID, anchorIndex: newIndex)
            needsDisplay = true
        } else {
            // Directly over an existing anchor (no active session) REMOVES it —
            // takes priority over the broader "anywhere on the shape" add-point hit
            // just below, so a point sitting on top of its own path's fill still
            // removes rather than adds another point on top of it. Both checks share
            // the SAME topmost-hit scoping as the rest of the canvas's hit-testing
            // (penHover → hitPath), instead of scanning every path in the document —
            // a flat whole-document anchor scan was the Session 111 bug that made the
            // "+"/"−" cursors fire on anchors far from the actual cursor position.
            if let hover = penHover(atViewPoint: p) {
                if let addr = hover.removable {
                    removePenPoint(from: hover.leafID, at: addr)
                    return
                }
                if let hit = node(hover.leafID), penAddable(hit) {
                    addPenPoint(to: hover.leafID, at: docP)
                    return
                }
            }
            // Start a new path with its first anchor at the click.
            penBaseline = document.model
            let node = Node(name: "Path", frame: CGRect(origin: docP, size: .zero),
                            content: .path(PathShape(points: [PathPoint(point: .zero)])))
            withNodes { $0.append(node) }
            app.selectedArtboardID = nil
            app.selectedNodeIDs = [node.id]
            penNodeID = node.id
            dragMode = .penHandle(nodeID: node.id, anchorIndex: 0)
            needsDisplay = true
        }
    }

    /// Pen can add a point to a path, or to a basic shape/line (converted first).
    private func penAddable(_ node: Node) -> Bool {
        switch node.content {
        case .path, .rectangle, .ellipse, .polygon, .line: return true
        default: return false
        }
    }

    /// Insert a corner anchor on an existing node's nearest segment (converting a
    /// rect/ellipse/line to a path first). One undo step.
    private func addPenPoint(to id: UUID, at docP: CGPoint) {
        guard let target = node(id) else { return }
        // Cursor → the node's own local space, through any ancestor group transforms
        // and the node's own rotation, so the point lands where it was clicked.
        let chain = ancestorGroups(of: id)
        var pl = docToParentLocal(docP, chain: chain)
        if target.rotation != 0 {
            pl = rotatePoint(pl, around: CGPoint(x: target.frame.midX, y: target.frame.midY), byDegrees: -target.rotation)
        }
        var local = CGPoint(x: pl.x - target.frame.minX, y: pl.y - target.frame.minY)
        // Un-flip so the new anchor lands where the cursor is on a flipped path.
        if target.flipH { local.x = target.frame.width - local.x }
        if target.flipV { local.y = target.frame.height - local.y }

        var nodes = currentNodes
        var added = false
        Self.mutateNested(id, in: &nodes) { n in
            // Convert a rect/ellipse/line to a path first.
            if case .path = n.content {} else if let ps = Self.pathShape(from: n.content, size: n.frame.size) {
                n.content = .path(ps)
            } else { return }
            guard case .path(var ps) = n.content else { return }
            // Nearest segment across EVERY contour (multi-contour shapes
            // included), measured along the ACTUAL curve (flattened) — on a curvy
            // path the straight anchor-to-anchor chord can sit nowhere near the
            // ink, which used to pick the wrong segment (or contour) entirely.
            var cs = ps.editContours
            var best: (c: Int, seg: Int, dist: CGFloat, t: CGFloat) = (-1, 0, .greatestFiniteMagnitude, 0.5)
            for (c, pts) in cs.enumerated() {
                let count = pts.count
                guard count >= 2 else { continue }
                let segCount = ps.contourClosed(c) ? count : count - 1
                for s in 0..<max(segCount, 1) {
                    let hit = Self.nearestOnSegment(local, pts[s], pts[(s + 1) % count])
                    if hit.dist < best.dist { best = (c, s, hit.dist, hit.t) }
                }
            }
            guard best.c >= 0 else { return }
            let insertAt = min(best.seg + 1, cs[best.c].count)
            let segA = cs[best.c][best.seg]
            let bIndex = (best.seg + 1) % cs[best.c].count
            let segB = cs[best.c][bIndex]
            if segA.controlOut != nil || segB.controlIn != nil {
                // Curved segment: SPLIT the cubic at the nearest point (de
                // Casteljau) so the outline doesn't move — the new anchor sits
                // exactly ON the ink with handles that preserve the shape,
                // instead of a corner point yanking the curve toward the cursor.
                let t = min(max(best.t, 0.02), 0.98)   // avoid a degenerate split
                let cut = Self.splitCubic(segA.point, segA.controlOut ?? segA.point,
                                          segB.controlIn ?? segB.point, segB.point, at: t)
                cs[best.c][best.seg].controlOut = cut.c1
                cs[best.c][bIndex].controlIn = cut.c2
                cs[best.c].insert(PathPoint(point: cut.mid, controlIn: cut.midIn, controlOut: cut.midOut),
                                  at: insertAt)
            } else {
                cs[best.c].insert(PathPoint(point: local), at: insertAt)
            }
            ps.writeEditContours(cs)
            n.content = .path(ps)
            added = true
        }
        guard added else { return }
        commitNodes(nodes, actionName: "Add Point")
        app?.selectedNodeIDs = [id]
        app?.selectedArtboardID = nil
        needsDisplay = true
    }

    /// What's directly under the cursor for an inactive pen session. The SELECTED
    /// shape gets first claim: with overlapping shapes (tree branches), the
    /// topmost hit under the cursor is often a neighbor, and adding/removing a
    /// point on IT instead of the shape being worked on made point editing feel
    /// like a gamble. Only when the cursor isn't on the selected shape's ink does
    /// this fall back to the deepest hit node — the SAME topmost-hit scoping
    /// `hitPath` gives every other tool (so a far-away path's anchors never steal
    /// the hover/click). Also reports the anchor within `handleGrab` of the
    /// cursor, if any, so the click removes it instead of adding.
    private func penHover(atViewPoint p: CGPoint) -> (leafID: UUID, removable: PointAddress?)? {
        if let sel = penSelectedTarget(atViewPoint: p) {
            return (sel.id, removableAnchor(of: sel, atViewPoint: p))
        }
        guard let leaf = hitPath(atDoc: viewToDoc(p)).last, let n = node(leaf.id) else { return nil }
        return (n.id, removableAnchor(of: n, atViewPoint: p))
    }

    /// The single selected pen-editable node, but only if the cursor is on its
    /// ink (nodeHit's real-ink test, honoring group transforms) — the pen never
    /// captures clicks landing off the active shape.
    private func penSelectedTarget(atViewPoint p: CGPoint) -> Node? {
        guard let app, let id = app.singleSelectedNodeID, id != penNodeID,
              let n = node(id), n.isVisible, !n.isLocked, penAddable(n) else { return nil }
        let pl = docToParentLocal(viewToDoc(p), chain: ancestorGroups(of: id))
        return nodeHit(n, at: pl, offset: .zero) ? n : nil
    }

    /// The anchor of `n` within grab range of the cursor, scanning EVERY contour
    /// (multi-contour outlined-text / SVG subpaths included) — shared by the
    /// selected-shape and topmost-hit branches of `penHover`.
    private func removableAnchor(of n: Node, atViewPoint p: CGPoint) -> PointAddress? {
        guard case .path(let ps) = n.content else { return nil }
        let chain = ancestorGroups(of: n.id)
        for (c, pts) in ps.editContours.enumerated() {
            for (i, pt) in pts.enumerated() {
                let v = nodeLocalToView(pt.point, n, chain: chain)
                if hypot(p.x - v.x, p.y - v.y) <= handleGrab { return PointAddress(contour: c, index: i) }
            }
        }
        return nil
    }

    /// Remove a single anchor (pen tool "−" click) — not the whole path. Mirrors
    /// `addPenPoint`'s commit pattern and `finishPen`'s "< 2 points = no path"
    /// convention, but removes the whole node via `removeNested` (not a flat
    /// `removeAll`) so a path nested in a group is handled correctly.
    private func removePenPoint(from id: UUID, at addr: PointAddress) {
        var nodes = currentNodes
        var removed = false, collapsed = false
        Self.mutateNested(id, in: &nodes) { n in
            guard case .path(var ps) = n.content else { return }
            var cs = ps.editContours
            guard cs.indices.contains(addr.contour), cs[addr.contour].indices.contains(addr.index) else { return }
            cs[addr.contour].remove(at: addr.index)
            // A contour that fell below 2 points can't draw — drop the whole contour.
            if cs[addr.contour].count < 2 { cs.remove(at: addr.contour) }
            ps.writeEditContours(cs)
            n.content = .path(ps)
            removed = true
            // Nothing left to keep → remove the node (mirrors finishPen's "< 2" rule).
            collapsed = cs.isEmpty || (cs.count == 1 && cs[0].count < 2)
        }
        guard removed else { return }
        if collapsed {
            Self.removeNested([id], from: &nodes)
            app?.selectedNodeIDs = []
            app?.selectedArtboardID = nil
        }
        commitNodes(nodes, actionName: "Delete Point")
        needsDisplay = true
    }

    /// Drag right after placing an anchor to pull symmetric bezier handles.
    private func penHandleDrag(_ p: CGPoint, nodeID: UUID, anchorIndex: Int, shift: Bool = false) {
        guard let n = node(nodeID), case .path(let ps) = n.content, anchorIndex < ps.points.count else { return }
        let docP = viewToDoc(p)
        let anchorLocal = ps.points[anchorIndex].point
        var outLocal = docToLocal(docP, n)
        // Shift locks the new handle to axis/45-degree increments, exactly like
        // editing an existing control handle in pathPointDrag (BUG-005). The
        // opposite handle is re-derived below so it stays mirrored.
        if shift { outLocal = constrainLineEndpoint(outLocal, from: anchorLocal) }
        let inLocal = CGPoint(x: 2 * anchorLocal.x - outLocal.x, y: 2 * anchorLocal.y - outLocal.y)
        updateNodeLive(nodeID) {
            if case .path(var p2) = $0.content {
                p2.points[anchorIndex].controlOut = outLocal
                p2.points[anchorIndex].controlIn = inLocal
                $0.content = .path(p2)
            }
        }
        needsDisplay = true
    }

    /// Commit (or cancel) the in-progress pen path. One undo step for the path.
    private func finishPen() {
        guard let penID = penNodeID else { return }
        if let n = node(penID), case .path(let ps) = n.content, ps.points.count < 2 {
            withNodes { $0.removeAll { $0.id == penID } }   // a lone click = no path
            app?.selectedNodeIDs = []
        } else {
            normalizePath(penID)
            if let baseline = penBaseline {
                document?.registerUndo(restoring: baseline, undoManager: undoManager, actionName: "Draw Path")
            }
        }
        penNodeID = nil
        penBaseline = nil
        needsDisplay = true
    }

    // MARK: Pencil (FEAT-029)

    /// Samples closer together than this (in DOCUMENT space) are discarded. Every
    /// mouse event on a slow stroke produces near-identical points, which cost the
    /// live redraw and tell the fitter nothing it does not already know.
    private static let pencilMinSampleDistance: CGFloat = 1.5

    /// Close the stroke if the release lands within this many VIEW points of where
    /// it started. Measured on screen, not in the document, so the gesture means the
    /// same thing at every zoom.
    private static let pencilCloseDistance: CGFloat = 12

    private func pencilMouseDown(_ p: CGPoint) {
        guard let app, let document else { return }
        let docP = viewToDoc(p)
        pencilBaseline = document.model
        pencilSamples = [docP]
        let node = Node(name: "Path", frame: CGRect(origin: docP, size: .zero),
                        content: .path(PathShape(points: [PathPoint(point: .zero)])))
        withNodes { $0.append(node) }
        app.selectedArtboardID = nil
        app.selectedNodeIDs = [node.id]
        pencilNodeID = node.id
        dragMode = .pencilStroke
        needsDisplay = true
    }

    private func pencilMouseDragged(_ p: CGPoint) {
        guard let id = pencilNodeID else { return }
        let docP = viewToDoc(p)
        if let last = pencilSamples.last,
           hypot(docP.x - last.x, docP.y - last.y) < Self.pencilMinSampleDistance { return }
        pencilSamples.append(docP)
        // Live feedback is the RAW polyline. It is cheap, it is honest about what was
        // actually captured, and it is replaced by the fitted curve on release.
        // Re-fitting every tick would cost far more and would show a curve that keeps
        // rewriting itself under the cursor.
        applyPencilPoints(pencilSamples.map { PathPoint(point: $0) }, closed: false, to: id)
        didEdit = true
        needsDisplay = true
    }

    /// Write anchors given in DOCUMENT space into the node, re-based to node-local
    /// space with the frame refitted around them. Done live rather than only at the
    /// end because `nodeHit` uses the frame as its bounding-box reject and culling
    /// uses it too — a stale frame mid-stroke means the ink stops being clickable
    /// and can vanish while being drawn.
    private func applyPencilPoints(_ docPoints: [PathPoint], closed: Bool, to id: UUID) {
        guard !docPoints.isEmpty else { return }
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for pt in docPoints {
            xs.append(pt.point.x); ys.append(pt.point.y)
            if let c = pt.controlIn { xs.append(c.x); ys.append(c.y) }
            if let c = pt.controlOut { xs.append(c.x); ys.append(c.y) }
        }
        guard let minX = xs.min(), let minY = ys.min(),
              let maxX = xs.max(), let maxY = ys.max() else { return }
        func rebase(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x - minX, y: q.y - minY) }
        let local = docPoints.map {
            PathPoint(point: rebase($0.point),
                      controlIn: $0.controlIn.map(rebase),
                      controlOut: $0.controlOut.map(rebase))
        }
        updateNode(id) {
            $0.frame = CGRect(x: minX, y: minY,
                              width: max(maxX - minX, 0), height: max(maxY - minY, 0))
            if case .path(var ps) = $0.content {
                ps.points = local
                ps.closed = closed
                $0.content = .path(ps)
            }
        }
    }

    /// Fit the captured samples and commit the whole stroke as ONE undo step.
    private func finishPencilStroke() {
        guard let id = pencilNodeID else { return }
        defer {
            pencilNodeID = nil
            pencilBaseline = nil
            pencilSamples = []
            dragMode = .none
            needsDisplay = true
        }
        // A click is not a stroke: leave nothing behind, and no undo step for it.
        guard pencilSamples.count >= 2 else {
            withNodes { $0.removeAll { $0.id == id } }
            app?.selectedNodeIDs = []
            if let baseline = pencilBaseline { document?.model = baseline }
            return
        }
        let closed = shouldClosePencilStroke()
        let fitted = CurveFitting.fit(pencilSamples,
                                      tolerance: AppPreferences.pencilFidelityValue)
        // The fitter can only fail by returning too little to draw. Keeping the raw
        // polyline is better than discarding what the designer just drew.
        let points = fitted.count >= 2 ? fitted : pencilSamples.map { PathPoint(point: $0) }
        applyPencilPoints(points, closed: closed, to: id)
        normalizePath(id)
        if let baseline = pencilBaseline {
            document?.registerUndo(restoring: baseline, undoManager: undoManager,
                                   actionName: "Draw Path")
        }
    }

    /// True when the stroke ended close enough to where it began to have meant it.
    /// Requires a real loop's worth of samples so a short scribble that happens to
    /// end near its start is not closed behind the designer's back.
    private func shouldClosePencilStroke() -> Bool {
        guard pencilSamples.count >= 8,
              let first = pencilSamples.first, let last = pencilSamples.last else { return false }
        let a = docToViewPoint(first), b = docToViewPoint(last)
        return hypot(a.x - b.x, a.y - b.y) <= Self.pencilCloseDistance
    }

    /// Finish any active pencil stroke if the tool is no longer the pencil.
    func endPencilIfNeeded() {
        if pencilNodeID != nil, app?.tool != .pencil { finishPencilStroke() }
    }

    /// Finish any active pen session if the tool is no longer the pen.
    func endPenIfNeeded() {
        if penNodeID != nil, app?.tool != .pen { finishPen() }
    }

    // MARK: Node tool (point editing)

    private func nodeToolMouseDown(_ p: CGPoint, shift: Bool) {
        guard let app, let document else { return }

        // Lines have two editable points but no PathShape anchor array. Treat
        // their visible endpoint handles as direct-selection targets so the
        // Inspector can expose exactly that endpoint's marker slot.
        if let movingStart = hitTestLineEndpoint(atViewPoint: p),
           let id = app.singleSelectedNodeID, let n = node(id),
           let (a, b) = lineEndpointsResolvedDoc(n) {
            setSelectedPoints([])
            app.selectedStrokeEndpoint = movingStart ? .start : .end
            dragBaseline = document.model
            gestureUndoName = "Edit Line"
            dragMode = .lineEndpoint(id: id, movingStart: movingStart,
                                     fixedDoc: movingStart ? b : a)
            return
        }
        app.selectedStrokeEndpoint = nil

        // 0) The point-selection transform box (FEAT-026). Tested FIRST, which is
        //    safe because the box is padded outward: its handles never sit on an
        //    anchor, so this cannot steal a click meant for a point. Shift is left
        //    to the anchor-toggle path below rather than being given a second job.
        if !shift, selectedPointAddresses.count >= 2,
           let id = app.singleSelectedNodeID, let n = node(id),
           case .path(let ps) = n.content {
            if let rot = hitTestPointBoxRotate(atViewPoint: p) {
                dragBaseline = document.model
                gestureUndoName = "Rotate Points"
                didEdit = false
                dragMode = .rotatePoints(
                    nodeID: id, centerLocal: rot.centerLocal,
                    startAngle: pointBoxAngle(ofViewPoint: p, aroundLocal: rot.centerLocal,
                                              node: n, chain: ancestorGroups(of: id)),
                    originals: selectedPointBaseline(ps))
                return
            }
            if let hit = hitTestPointBoxHandle(atViewPoint: p) {
                dragBaseline = document.model
                gestureUndoName = "Resize Points"
                didEdit = false
                dragMode = .resizePoints(nodeID: id, handle: hit.handle, original: hit.box,
                                         originals: selectedPointBaseline(ps))
                return
            }
        }

        // 1) An anchor or handle of the path currently being point-edited.
        if let hit = perf.measure("hit-points", { hitTestPathPoint(atViewPoint: p) }) {
            switch hit.target {
            case .anchor(let c, let i):
                let addr = PointAddress(contour: c, index: i)
                if shift {
                    // Shift-click only toggles membership — it never starts a
                    // drag on its own (Illustrator/Figma-style direct select).
                    var addrs = selectedPointAddresses
                    if addrs.contains(addr) { addrs.remove(addr) } else { addrs.insert(addr) }
                    setSelectedPoints(addrs)
                    return
                }
                if !selectedPointAddresses.contains(addr) { setSelectedPoints([addr]) }
                dragBaseline = document.model
                gestureUndoName = "Edit Path"
                didEdit = false
                pointGroupFromBody = false
                beginPathPointGroupDrag(nodeID: hit.id, atView: p)
            case .controlIn, .controlOut:
                // A handle belongs to one anchor only — dragging it never moves
                // a multi-point selection, even when other points are selected.
                dragBaseline = document.model
                gestureUndoName = "Edit Path"
                didEdit = false
                dragMode = .pathPoint(nodeID: hit.id, target: hit.target)
            }
            return
        }

        // 2) No anchor/handle hit, but points ARE selected and the click landed
        //    on the body of the path that owns them — grabbing the shape moves
        //    the whole selection, same as grabbing one of its anchors.
        if let sel = selectedPath(), !selectedPointAddresses.isEmpty,
           hitPath(atDoc: viewToDoc(p)).last?.id == sel.id {
            dragBaseline = document.model
            gestureUndoName = "Edit Path"
            didEdit = false
            pointGroupFromBody = true   // a click here (no drag) will deselect on mouse-up
            beginPathPointGroupDrag(nodeID: sel.id, atView: p)
            return
        }

        // 3) FEAT-025 — the press landed on an object's BODY with nothing finer to
        //    edit under the cursor, so move the whole object, the way Illustrator's
        //    Direct Selection does. Pressing an anchor or a handle already won at
        //    step 1, and a point selection on THIS object already won at step 2, so
        //    reaching this line means a point edit was never what was being asked
        //    for. `.last` is the deepest leaf rather than the group around it —
        //    addressing individual objects IS the direct-selection semantic.
        //
        //    Reuses `beginSelectedNodeDrag`, the one route the select tool and
        //    Auto-select already share, so Option-copy, snapping, nested movement,
        //    smart guides and one-step undo stay a single implementation instead of
        //    becoming a second copy that drifts.
        //
        //    Arming the drag costs a click nothing: the `.nodes` case in mouseUp
        //    registers undo only `if didEdit`, so a press that never moves still
        //    just selects, exactly as it did before this existed.
        //
        //    THIS IS NOT A FIX FOR BUG-028 and must never be recorded as one.
        //    Making the wrong mode less painful is not the same as making the tool
        //    switch work; BUG-028 is still live and is fixed and verified on its own.
        if let leaf = hitPath(atDoc: viewToDoc(p)).last {
            if leaf.id != selectedPath()?.id {
                // Switching which object the tool addresses. Its points start
                // unselected — unchanged from before this feature.
                setSelectedPoints([])
                app.selectedNodeIDs = [leaf.id]
                app.selectedArtboardID = nil
            }
            beginSelectedNodeDrag(at: viewToDoc(p))
            return
        }

        // 4) Empty space (or the active path's own interior with nothing
        //    grabbable yet) while a path is being point-edited → marquee-select
        //    its points.
        if selectedPath() != nil {
            if !shift { setSelectedPoints([]) }
            dragMode = .pointMarquee(startView: p, additive: shift)
            marqueeCurrent = p
            return
        }

        // Nothing to edit at all.
        setSelectedPoints([])
        app.selectedNodeIDs = []
        needsDisplay = true
    }

    /// Replace the node tool's point selection, keeping the Inspector's point-
    /// rotation channel (`AppState.applyPointRotation`/`selectedPointCount`) in
    /// sync — same install/uninstall pattern as `applyTextStyle`.
    private func setSelectedPoints(_ addrs: Set<PointAddress>) {
        perf.measure("select-points") {
            selectedPointAddresses = addrs
            app?.selectedPointCount = addrs.count
            var endpoint: StrokeEndpoint?
            if addrs.count == 1, let address = addrs.first, address.contour == 0,
               let selected = selectedPath(), !selected.ps.closed,
               !selected.ps.isMultiContour, selected.ps.points.count >= 2 {
                if address.index == 0 { endpoint = .start }
                else if address.index == selected.ps.points.count - 1 { endpoint = .end }
            }
            app?.selectedStrokeEndpoint = endpoint
            if addrs.isEmpty {
                app?.applyPointRotation = nil
                app?.pointSelectionRotation = 0
            } else {
                app?.pointSelectionRotation = 0   // a fresh dial for this selection
                app?.applyPointRotation = { [weak self] delta in self?.rotateSelectedPoints(by: delta) }
            }
        }
        needsDisplay = true
    }

    /// Drop the node tool's point selection if the edited path changed (e.g. a
    /// different shape picked in the Layers panel) or the tool switched away
    /// from Edit Points — called every SwiftUI update cycle from
    /// `CanvasView.updateNSView` so a stale highlighted selection never lingers.
    func syncPointSelectionIfNeeded() {
        guard let app else { return }
        if app.tool != .node { app.selectedStrokeEndpoint = nil }
        let currentID = (app.tool == .node) ? app.singleSelectedNodeID : nil
        guard currentID != lastEditedPathID else { return }
        lastEditedPathID = currentID
        if !selectedPointAddresses.isEmpty { setSelectedPoints([]) }
    }

    /// Snapshot the selected anchors' local point + handle positions and begin a
    /// group drag — every selected point moves by the same delta as the cursor.
    private func beginPathPointGroupDrag(nodeID: UUID, atView p: CGPoint) {
        guard let n = node(nodeID), case .path(let ps) = n.content else { return }
        let local = viewToNodeLocal(p, n, chain: ancestorGroups(of: n.id))
        let contours = ps.editContours
        var originals: [PointAddress: (point: CGPoint, controlIn: CGPoint?, controlOut: CGPoint?)] = [:]
        for addr in selectedPointAddresses {
            guard addr.contour < contours.count, addr.index < contours[addr.contour].count else { continue }
            let pt = contours[addr.contour][addr.index]
            originals[addr] = (pt.point, pt.controlIn, pt.controlOut)
        }
        guard !originals.isEmpty else { return }
        dragMode = .pathPointGroup(nodeID: nodeID, startLocal: local, originals: originals)
    }

    /// Move every selected anchor (+ its handles) by the same delta from where
    /// the group drag started — keeps the whole multi-point selection rigid.
    private func pathPointGroupDrag(_ p: CGPoint, nodeID: UUID, startLocal: CGPoint,
                                     originals: [PointAddress: (point: CGPoint, controlIn: CGPoint?, controlOut: CGPoint?)],
                                     shift: Bool = false) {
        guard let n = node(nodeID), case .path(var ps) = n.content else { return }
        let local = viewToNodeLocal(p, n, chain: ancestorGroups(of: n.id))
        var dx = local.x - startLocal.x, dy = local.y - startLocal.y
        // Shift locks the move to the dominant axis (Figma/Illustrator-style).
        if shift { if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 } }
        for (addr, orig) in originals {
            ps.mutatePoint(contour: addr.contour, index: addr.index) { pt in
                pt.point = CGPoint(x: orig.point.x + dx, y: orig.point.y + dy)
                pt.controlIn = orig.controlIn.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                pt.controlOut = orig.controlOut.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
        }
        updateNodeLive(nodeID) { $0.content = .path(ps) }
        didEdit = true
        needsDisplay = true
    }

    /// Finish a node-tool marquee: select every point of the edited path whose
    /// VIEW position lands inside the dragged rectangle.
    private func finishPointMarquee(start: CGPoint, end: CGPoint, additive: Bool) {
        guard let sel = selectedPath(), let n = node(sel.id) else {
            if !additive { setSelectedPoints([]) }
            return
        }
        if hypot(end.x - start.x, end.y - start.y) <= 3 {
            if !additive { setSelectedPoints([]) }   // a plain click that hit nothing
            return
        }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        let chain = ancestorGroups(of: n.id)
        func v(_ local: CGPoint) -> CGPoint { nodeLocalToView(local, n, chain: chain) }
        var hits = Set<PointAddress>()
        for (c, pts) in sel.ps.editContours.enumerated() {
            for (i, pt) in pts.enumerated() where rect.contains(v(pt.point)) {
                hits.insert(PointAddress(contour: c, index: i))
            }
        }
        setSelectedPoints(additive ? selectedPointAddresses.union(hits) : hits)
    }

    /// Rotate the node tool's selected points about THEIR OWN bounding-box
    /// centre (in the path's local space) — the selection behaves like its own
    /// little element, independent of the shape's `rotation` property. `delta`
    /// is the change since the Inspector's point-rotation field was last set
    /// (see `AppState.pointSelectionRotation`), not an absolute angle.
    private func rotateSelectedPoints(by delta: Double) {
        guard delta != 0, let id = app?.singleSelectedNodeID,
              let n = node(id), case .path(let ps0) = n.content,
              !selectedPointAddresses.isEmpty else { return }
        var ps = ps0
        let contours = ps.editContours
        let anchors = selectedPointAddresses.compactMap { addr -> CGPoint? in
            guard addr.contour < contours.count, addr.index < contours[addr.contour].count else { return nil }
            return contours[addr.contour][addr.index].point
        }
        guard !anchors.isEmpty else { return }
        let xs = anchors.map(\.x), ys = anchors.map(\.y)
        let center = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        for addr in selectedPointAddresses {
            ps.mutatePoint(contour: addr.contour, index: addr.index) { pt in
                pt.point = rotatePoint(pt.point, around: center, byDegrees: delta)
                pt.controlIn = pt.controlIn.map { rotatePoint($0, around: center, byDegrees: delta) }
                pt.controlOut = pt.controlOut.map { rotatePoint($0, around: center, byDegrees: delta) }
            }
        }
        var nodes = currentNodes
        guard Self.mutateNested(id, in: &nodes, {
            $0.content = .path(ps)
            Self.normalizePathNode(&$0)
        }) else { return }
        commitNodes(nodes, actionName: "Rotate Points")
        needsDisplay = true
    }

    private func pathPointDrag(_ p: CGPoint, nodeID: UUID, target: PathPointTarget, shift: Bool = false) {
        guard let n = node(nodeID), case .path(var ps) = n.content else { return }
        var local = viewToNodeLocal(p, n, chain: ancestorGroups(of: n.id))
        switch target {
        case .anchor(let c, let i):
            guard let cur = ps.editPoint(contour: c, index: i) else { return }
            if shift { local = constrainLineEndpoint(local, from: cur.point) }   // lock to axis/45°
            let dx = local.x - cur.point.x, dy = local.y - cur.point.y
            ps.mutatePoint(contour: c, index: i) {
                $0.point = local
                $0.controlIn = $0.controlIn.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                $0.controlOut = $0.controlOut.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
        case .controlIn(let c, let i):
            // Shift snaps a handle to 45°/axis about its own anchor.
            if shift, let a = ps.editPoint(contour: c, index: i)?.point { local = constrainLineEndpoint(local, from: a) }
            ps.mutatePoint(contour: c, index: i) { $0.controlIn = local }
        case .controlOut(let c, let i):
            if shift, let a = ps.editPoint(contour: c, index: i)?.point { local = constrainLineEndpoint(local, from: a) }
            ps.mutatePoint(contour: c, index: i) { $0.controlOut = local }
        }
        updateNodeLive(nodeID) { $0.content = .path(ps) }
        didEdit = true
        needsDisplay = true
    }

    // MARK: Convert to path

    @objc func convertToPathAction(_ sender: Any?) { convertSelectionToPaths() }

    private func convertSelectionToPaths() {
        guard let app else { return }
        let selected = app.selectedNodeIDs
        var nodes = currentNodes
        var changed = false
        // A selected group is an operation scope: convert every compatible leaf at
        // any depth while retaining the hierarchy and leaving text/images/paths alone.
        func process(_ array: inout [Node], selectedAbove: Bool = false) {
            for i in array.indices {
                let active = selectedAbove || selected.contains(array[i].id)
                if case .group(var children) = array[i].content {
                    process(&children, selectedAbove: active)
                    array[i].content = .group(children: children)
                } else if active,
                          let ps = Self.pathShape(from: array[i].content,
                                                  size: array[i].frame.size) {
                    array[i].content = .path(ps)
                    changed = true
                }
            }
        }
        process(&nodes)
        guard changed else { return }
        commitNodes(nodes, actionName: "Convert to Path")
        needsDisplay = true
    }

    /// Convert a rectangle/ellipse/line into an equivalent path shape.
    private static func pathShape(from content: NodeContent, size: CGSize) -> PathShape? {
        VectorPathGeometry.pathShape(from: content, size: size)
    }

    // MARK: Outline Stroke + Pathfinder

    @objc func outlineStrokeAction(_ sender: Any?) { outlineSelectedStrokes() }
    @objc func pathfinderUniteAction(_ sender: Any?) { applyPathfinder(.unite) }
    @objc func pathfinderSubtractAction(_ sender: Any?) { applyPathfinder(.subtract) }
    @objc func pathfinderIntersectAction(_ sender: Any?) { applyPathfinder(.intersect) }
    @objc func pathfinderExcludeAction(_ sender: Any?) { applyPathfinder(.exclude) }

    /// A node-local vector point in its direct parent's coordinate space. This
    /// bakes the node's own flip/rotation but deliberately leaves ancestor-group
    /// transforms alone; replacement geometry stays in the same parent.
    private func vectorPointToParent(_ local: CGPoint, node: Node) -> CGPoint {
        var point = local
        if node.flipH { point.x = node.frame.width - point.x }
        if node.flipV { point.y = node.frame.height - point.y }
        point.x += node.frame.minX
        point.y += node.frame.minY
        if node.rotation != 0 {
            point = rotatePoint(point,
                                around: CGPoint(x: node.frame.midX, y: node.frame.midY),
                                byDegrees: node.rotation)
        }
        return point
    }

    private func vectorPointToDocument(_ local: CGPoint, node: Node) -> CGPoint {
        parentLocalToDoc(vectorPointToParent(local, node: node),
                         chain: ancestorGroups(of: node.id))
    }

    private func vectorPathInDocument(_ node: Node) -> CGPath? {
        guard let shape = VectorPathGeometry.pathShape(from: node.content,
                                                       size: node.frame.size) else { return nil }
        let local = VectorPathGeometry.cgPath(from: shape)
        return VectorPathGeometry.map(local) { self.vectorPointToDocument($0, node: node) }
    }

    private static func paintIsVisible(_ paint: Paint?) -> Bool {
        guard let paint else { return false }
        if case .solid(let color) = paint { return color.a > 0.000_1 }
        return true
    }

    /// Illustrator-style expansion: a stroke-only object becomes one filled
    /// path. A filled+stroked object becomes a group containing an editable fill
    /// path and an editable outline path in the same paint order as the original.
    /// Resizing that group therefore scales the former stroke as geometry.
    private func outlineSelectedStrokes() {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        let selected = app.selectedNodeIDs
        var nodes = currentNodes
        var changed = false

        func outlinedReplacement(for original: Node) -> Node? {
            guard let sourceShape = VectorPathGeometry.pathShape(from: original.content,
                                                                 size: original.frame.size),
                  let stroke = VectorPathGeometry.stroke(from: original.content) else { return nil }
            let centerline = VectorPathGeometry.cgPath(from: sourceShape)
            let outlinePath = VectorPathGeometry.outlinedStroke(centerline: centerline,
                                                                 shape: sourceShape,
                                                                 stroke: stroke)
            guard let outline = VectorPathGeometry.pathShape(from: outlinePath,
                                                              fill: .solid(stroke.color)) else { return nil }
            let visibleFill = Self.paintIsVisible(VectorPathGeometry.fill(from: original.content))

            // Stroke-only (lines, open paths, or a transparent closed shape): one
            // direct filled path, with the old transform baked into its anchors.
            if !visibleFill {
                let parentPath = VectorPathGeometry.map(outlinePath) {
                    self.vectorPointToParent($0, node: original)
                }
                guard let converted = VectorPathGeometry.pathShape(from: parentPath,
                                                                    fill: .solid(stroke.color)) else { return nil }
                return Node(id: original.id, name: original.name, frame: converted.bounds,
                            artboardID: original.artboardID,
                            isVisible: original.isVisible, isLocked: original.isLocked,
                            opacity: original.opacity, effects: original.effects,
                            blendMode: original.blendMode,
                            autoLayout: original.autoLayout, autoPadding: original.autoPadding,
                            isAbsoluteInAutoLayout: original.isAbsoluteInAutoLayout,
                            isMask: original.isMask, isMaskShape: original.isMaskShape,
                            relationships: original.relationships,
                            anchoredRelationships: original.anchoredRelationships,
                            publicProps: original.publicProps, semantics: original.semantics,
                            content: .path(converted.shape))
            }

            // Preserve the original center as the group's transform center. The
            // outline can have asymmetric miter bounds, so make a symmetric frame
            // large enough for both children instead of shifting rotation on expand.
            let originalBounds = CGRect(origin: .zero, size: original.frame.size)
            let inkBounds = originalBounds.union(outline.bounds)
            let center = CGPoint(x: original.frame.width / 2, y: original.frame.height / 2)
            let halfWidth = max(center.x - inkBounds.minX, inkBounds.maxX - center.x)
            let halfHeight = max(center.y - inkBounds.minY, inkBounds.maxY - center.y)
            let groupFrame = CGRect(x: original.frame.midX - halfWidth,
                                    y: original.frame.midY - halfHeight,
                                    width: max(1, halfWidth * 2),
                                    height: max(1, halfHeight * 2))
            let childOffset = CGPoint(x: original.frame.minX - groupFrame.minX,
                                      y: original.frame.minY - groupFrame.minY)

            var fillShape = sourceShape
            fillShape.strokeWidth = 0
            fillShape.strokeAlignment = .center
            let fillNode = Node(name: "\(original.name) Fill",
                                frame: CGRect(origin: childOffset, size: original.frame.size),
                                content: .path(fillShape))
            let outlineNode = Node(name: "\(original.name) Outline",
                                   frame: outline.bounds.offsetBy(dx: childOffset.x, dy: childOffset.y),
                                   content: .path(outline.shape))
            return Node(id: original.id, name: original.name, frame: groupFrame,
                        artboardID: original.artboardID,
                        isVisible: original.isVisible, isLocked: original.isLocked,
                        rotation: original.rotation, opacity: original.opacity,
                        effects: original.effects, blendMode: original.blendMode,
                        autoLayout: original.autoLayout, autoPadding: original.autoPadding,
                        isAbsoluteInAutoLayout: original.isAbsoluteInAutoLayout,
                        flipH: original.flipH, flipV: original.flipV,
                        isMask: original.isMask, isMaskShape: original.isMaskShape,
                        relationships: original.relationships,
                        anchoredRelationships: original.anchoredRelationships,
                        publicProps: original.publicProps, semantics: original.semantics,
                        content: .group(children: [fillNode, outlineNode]))
        }

        func process(_ array: inout [Node], selectedAbove: Bool = false) {
            for i in array.indices {
                let active = selectedAbove || selected.contains(array[i].id)
                if active, let replacement = outlinedReplacement(for: array[i]) {
                    array[i] = replacement
                    changed = true
                } else if case .group(var children) = array[i].content {
                    process(&children, selectedAbove: active)
                    array[i].content = .group(children: children)
                }
            }
        }
        process(&nodes)
        guard changed else { NSSound.beep(); return }
        commitNodes(nodes, actionName: "Outline Stroke")
        needsDisplay = true
    }

    private struct PathfinderInput {
        var node: Node
        var path: CGPath
    }

    /// Selected closed vector nodes in paint order (last = topmost).
    private func pathfinderInputs() -> [PathfinderInput] {
        guard let app else { return [] }
        var result: [PathfinderInput] = []
        func walk(_ nodes: [Node]) {
            for node in nodes {
                if app.selectedNodeIDs.contains(node.id),
                   VectorPathGeometry.isClosedVector(node.content),
                   let path = vectorPathInDocument(node) {
                    result.append(PathfinderInput(node: node, path: path))
                }
                if case .group(let children) = node.content { walk(children) }
            }
        }
        walk(currentNodes)
        return result
    }

    private func applyPathfinder(_ operation: VectorBooleanOperation) {
        guard let app else { return }
        let inputs = pathfinderInputs()
        // Do not partially consume a mixed selection: every selected item must be
        // a closed vector shape, and Pathfinder always needs at least two.
        guard inputs.count >= 2, inputs.count == app.selectedNodeIDs.count else {
            NSSound.beep(); return
        }

        let combined: CGPath
        let styleNode: Node
        switch operation {
        case .unite:
            combined = inputs.dropFirst().reduce(inputs[0].path) {
                $0.union($1.path, using: .winding)
            }
            styleNode = inputs.last!.node
        case .subtract:
            let cutters = inputs.dropFirst().dropFirst().reduce(inputs[1].path) {
                $0.union($1.path, using: .winding)
            }
            combined = inputs[0].path.subtracting(cutters, using: .winding)
            styleNode = inputs[0].node
        case .intersect:
            combined = inputs.dropFirst().reduce(inputs[0].path) {
                $0.intersection($1.path, using: .winding)
            }
            styleNode = inputs.last!.node
        case .exclude:
            combined = inputs.dropFirst().reduce(inputs[0].path) {
                $0.symmetricDifference($1.path, using: .winding)
            }
            styleNode = inputs.last!.node
        }
        guard !combined.isEmpty else { NSSound.beep(); return }

        let ids = app.selectedNodeIDs
        let parents = Set(ids.map { parentGroupID(of: $0) })
        let sharedParent: UUID? = parents.count == 1 ? parents.first! : nil
        let outputPath: CGPath
        if let first = inputs.first, parents.count == 1 {
            let parentChain = ancestorGroups(of: first.node.id)
            outputPath = parentChain.isEmpty ? combined : VectorPathGeometry.map(combined) {
                self.docToParentLocal($0, chain: parentChain)
            }
        } else {
            outputPath = combined       // mixed parents are promoted to document level
        }

        guard let sourceStyle = VectorPathGeometry.pathShape(from: styleNode.content,
                                                              size: styleNode.frame.size),
              let converted = VectorPathGeometry.pathShape(from: outputPath,
                                                            fill: sourceStyle.fill,
                                                            stroke: sourceStyle.stroke,
                                                            strokeWidth: sourceStyle.strokeWidth,
                                                            strokeAlignment: sourceStyle.effectiveStrokeAlignment)
        else { NSSound.beep(); return }

        var result = Node(id: styleNode.id, name: styleNode.name, frame: converted.bounds,
                          isVisible: styleNode.isVisible, isLocked: styleNode.isLocked,
                          opacity: styleNode.opacity, effects: styleNode.effects,
                          blendMode: styleNode.blendMode,
                          isMask: styleNode.isMask, isMaskShape: styleNode.isMaskShape,
                          relationships: styleNode.relationships, publicProps: styleNode.publicProps,
                          content: .path(converted.shape))
        // All source transforms are already baked into `combined`.
        result.rotation = 0; result.flipH = false; result.flipV = false

        var nodes = currentNodes
        func replaceSelected(in array: inout [Node]) {
            guard let topIndex = array.indices.last(where: { ids.contains(array[$0].id) }) else { return }
            let insertion = array[..<topIndex].filter { !ids.contains($0.id) }.count
            array.removeAll { ids.contains($0.id) }
            array.insert(result, at: min(insertion, array.count))
        }
        if parents.count == 1 {
            if let parentID = sharedParent {
                Self.mutateNested(parentID, in: &nodes) { parent in
                    guard case .group(var children) = parent.content else { return }
                    replaceSelected(in: &children)
                    parent.content = .group(children: children)
                }
            } else {
                replaceSelected(in: &nodes)
            }
        } else {
            Self.removeNested(ids, from: &nodes)
            nodes.append(result)
        }

        commitNodes(nodes, actionName: operation.actionName)
        app.selectedNodeIDs = [result.id]
        app.selectedArtboardID = nil
        needsDisplay = true
    }

    private var selectionCanOutlineStroke: Bool {
        selectedSubtreesContain { VectorPathGeometry.stroke(from: $0.content) != nil }
    }

    private var selectionCanPathfinder: Bool {
        guard let app, app.selectedNodeIDs.count >= 2 else { return false }
        return pathfinderInputs().count == app.selectedNodeIDs.count
    }

    private var selectionConvertibleToPath: Bool {
        selectedSubtreesContain { node in
            switch node.content {
            case .rectangle, .ellipse, .polygon, .line: return true
            default: return false
            }
        }
    }

    private var selectionCanConvertTextToOutlines: Bool {
        selectedSubtreesContain { if case .text = $0.content { return true }; return false }
    }

    /// Whether any selected node, or anything recursively inside a selected group,
    /// satisfies `predicate`. Instances remain atomic references and are not entered.
    private func selectedSubtreesContain(_ predicate: (Node) -> Bool) -> Bool {
        guard let app else { return false }
        func scan(_ node: Node) -> Bool {
            if predicate(node) { return true }
            if case .group(let children) = node.content { return children.contains(where: scan) }
            return false
        }
        return app.selectedNodeIDs.contains { id in node(id).map(scan) ?? false }
    }

    // MARK: Convert text → shapes (glyph outlines)

    var selectionIsText: Bool {
        guard let app, let id = app.singleSelectedNodeID, let n = node(id),
              case .text = n.content else { return false }
        return true
    }

    // MARK: Type styles (v1.3 — Design Language)

    /// TYPE ▸ Save as Type Style: capture the selected text layer's treatment —
    /// everything EXCEPT color (owner decision; color pairs from the color
    /// library) — into the document's Design Language. Starts named after the
    /// layer; rename in the Design Language panel.
    @objc func saveTypeStyleAction(_ sender: Any?) {
        guard let app, let document, let id = app.singleSelectedNodeID,
              let n = node(id), case .text(let tc) = n.content else { return }
        var model = document.model
        let style = TypeStyle.capture(from: tc, name: n.name)
        model.designLanguage.saveTypeStyle(style)
        document.setModel(model, undoManager: undoManager, actionName: "Save Type Style")
    }

    /// TYPE / Inspector / context menu all write the same content-level intent.
    /// This deliberately leaves type-style identity and visual metrics untouched.
    @objc func setTextContentRoleAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let role = TextContentRole(rawValue: raw),
              let id = app?.singleSelectedNodeID else { return }
        var nodes = currentNodes
        guard Self.mutateNested(id, in: &nodes, { node in
            guard case .text(var text) = node.content else { return }
            text.contentRole = role
            node.content = .text(text)
        }) else { return }
        commitNodes(nodes, actionName: "Text Content Role")
    }

    /// Right-click ▸ Apply Type Style ▸ <style>. The NSMenuItem carries the
    /// style's UUID in representedObject (menus are built per-document).
    @objc func applyTypeStyleMenuAction(_ sender: NSMenuItem) {
        guard let styleID = sender.representedObject as? UUID,
              let style = document?.model.designLanguage.typeStyle(styleID),
              let id = app?.singleSelectedNodeID else { return }
        applyTypeStyle(style, toTextNode: id)
    }

    /// Apply a type style to a text node (one undo step). Same re-hug rule as
    /// every whole-text styling op (`toggleWholeText`).
    func applyTypeStyle(_ style: TypeStyle, toTextNode id: UUID) {
        guard let n = node(id), case .text(var tc) = n.content else { return }
        style.apply(to: &tc)
        var nodes = currentNodes
        guard let i = nodes.firstIndex(where: { $0.id == id }) else { return }
        app?.rememberTextStyle(fontName: style.fontName, fontSize: style.fontSize)
        nodes[i].content = .text(tc)
        nodes[i].frame.size = tc.measuredSize(boxWidth: nodes[i].frame.width)
        commitNodes(nodes, actionName: "Apply Type Style")
    }

    @objc func convertTextToShapesAction(_ sender: Any?) { convertSelectedTextToShapes() }

    private func convertSelectedTextToShapes() {
        guard let app, !app.selectedNodeIDs.isEmpty else { NSSound.beep(); return }
        let selected = app.selectedNodeIDs

        func replacement(for original: Node, text tc: TextContent) -> Node? {
            let glyphs = tc.outlineGlyphs(in: original.frame.size)
            guard !glyphs.isEmpty else { return nil }

            // Each glyph becomes its own path node, sized to its tight ink box. The
            // frame is in the text node's PARENT space, so nesting depth is irrelevant.
            let fx = original.frame.minX, fy = original.frame.minY
            func pathNode(_ glyph: GlyphOutline, frame: CGRect) -> Node {
                let ps = PathShape(points: glyph.localContours.first ?? [], closed: true,
                                   fill: .solid(glyph.color), stroke: .black, strokeWidth: 0,
                                   contours: glyph.localContours)
                let trimmed = glyph.char.trimmingCharacters(in: .whitespacesAndNewlines)
                return Node(name: trimmed.isEmpty ? "Glyph" : glyph.char,
                            frame: frame, content: .path(ps))
            }
            let frames = glyphs.map {
                CGRect(x: fx + $0.boxInText.minX, y: fy + $0.boxInText.minY,
                       width: $0.boxInText.width, height: $0.boxInText.height)
            }
            let frame: CGRect
            let content: NodeContent
            if glyphs.count == 1 {
                frame = frames[0]
                content = pathNode(glyphs[0], frame: frame).content
            } else {
                let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
                frame = union
                let children = zip(glyphs, frames).map { glyph, glyphFrame in
                    pathNode(glyph, frame: glyphFrame.offsetBy(dx: -union.minX,
                                                               dy: -union.minY))
                }
                content = .group(children: children)
            }
            // Preserve identity and every non-text layer contract. Relationships,
            // component public-prop identity, masks, locks, and auto-layout placement
            // must not disappear merely because editable text became vector geometry.
            return Node(id: original.id, name: original.name, frame: frame,
                        artboardID: original.artboardID,
                        isVisible: original.isVisible, isLocked: original.isLocked,
                        rotation: original.rotation, opacity: original.opacity,
                        effects: original.effects, blendMode: original.blendMode,
                        autoLayout: original.autoLayout, autoPadding: original.autoPadding,
                        isAbsoluteInAutoLayout: original.isAbsoluteInAutoLayout,
                        flipH: original.flipH, flipV: original.flipV,
                        isMask: original.isMask, isMaskShape: original.isMaskShape,
                        relationships: original.relationships,
                        anchoredRelationships: original.anchoredRelationships,
                        publicProps: original.publicProps, semantics: original.semantics,
                        content: content)
        }

        var nodes = currentNodes
        var replaced = false
        func process(_ array: inout [Node], selectedAbove: Bool = false) {
            for i in array.indices {
                let active = selectedAbove || selected.contains(array[i].id)
                if active, case .text(let text) = array[i].content,
                   let outlined = replacement(for: array[i], text: text) {
                    array[i] = outlined
                    replaced = true
                } else if case .group(var children) = array[i].content {
                    process(&children, selectedAbove: active)
                    array[i].content = .group(children: children)
                }
            }
        }
        process(&nodes)
        // Beep rather than fail silently — a selection can contain only whitespace
        // text, which legitimately has no glyph outlines, but still needs feedback.
        guard replaced else { NSSound.beep(); return }
        commitNodes(nodes, actionName: "Convert Text to Outlines")
        needsDisplay = true
    }

    // MARK: Align & distribute

    @objc func alignLeftAction(_ s: Any?)     { align(.left) }
    @objc func alignHCenterAction(_ s: Any?)  { align(.hCenter) }
    @objc func alignRightAction(_ s: Any?)    { align(.right) }
    @objc func alignTopAction(_ s: Any?)      { align(.top) }
    @objc func alignVCenterAction(_ s: Any?)  { align(.vCenter) }
    @objc func alignBottomAction(_ s: Any?)   { align(.bottom) }
    @objc func distributeHorizontallyAction(_ s: Any?) { distribute(horizontal: true) }
    @objc func distributeVerticallyAction(_ s: Any?)   { distribute(horizontal: false) }

    /// Tidying board PLACEMENT is a genuinely different idea from aligning things
    /// to each other — it's Finder's "Clean Up", not Align — so it stays its own
    /// command. Align and distribute above deliberately do NOT fork; see `align(_:)`.
    @objc func cleanUpArtboardsAction(_ s: Any?) { cleanUpArtboards() }

    /// The rect alignment is measured against: the selection's bounding box, or —
    /// when "Align to" is Artboard — the board the selection sits in.
    private func alignReference(_ frames: [CGRect]) -> CGRect {
        let selectionBox = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        guard app?.alignTarget == .artboard, document != nil, !isSourceScope else { return selectionBox }
        if let ab = owningArtboard(of: selectionBox) { return ab.frame }
        if let id = app?.selectedArtboardID,
           let ab = currentArtboards.first(where: { $0.id == id }) { return ab.frame }
        return selectionBox
    }

    private struct AlignmentItem {
        let id: UUID
        let node: Node
        let ancestors: [Node]
        let bounds: CGRect
    }

    /// The node's visual AABB in its parent's coordinate space, including its own
    /// rotation and live group contents. This is the natural alignment space when
    /// every selected layer is a sibling inside the same group.
    private func parentLocalAlignmentBounds(_ node: Node) -> CGRect {
        SelectionTransform.visualBounds(node)
    }

    /// Lift a parent-local visual box through every transformed ancestor. Mapping
    /// all four corners (rather than adding group origins) keeps mixed-parent and
    /// Align-to-Artboard operations correct inside rotated/flipped groups.
    private func documentAlignmentBounds(_ node: Node, ancestors: [Node]) -> CGRect {
        let local = parentLocalAlignmentBounds(node)
        let corners = [
            CGPoint(x: local.minX, y: local.minY),
            CGPoint(x: local.maxX, y: local.minY),
            CGPoint(x: local.maxX, y: local.maxY),
            CGPoint(x: local.minX, y: local.maxY),
        ].map { parentLocalToDoc($0, chain: ancestors) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// True when the space the selection shares is not screen-aligned — i.e. some
    /// ancestor group above it is rotated or flipped (BUG-042).
    private func selectionAncestorsAreTransformed() -> Bool {
        guard let app else { return false }
        for id in app.selectedNodeIDs where !hasSelectedAncestor(id) {
            if ancestorGroups(of: id).contains(where: { $0.rotation != 0 || $0.flipH || $0.flipV }) {
                return true
            }
        }
        return false
    }

    private func alignmentItems(documentSpace: Bool) -> [AlignmentItem] {
        guard let app else { return [] }
        return app.selectedNodeIDs.compactMap { id in
            guard !hasSelectedAncestor(id), let selected = node(id) else { return nil }
            let ancestors = ancestorGroups(of: id)
            let bounds = documentSpace
                ? documentAlignmentBounds(selected, ancestors: ancestors)
                : parentLocalAlignmentBounds(selected)
            return AlignmentItem(id: id, node: selected, ancestors: ancestors, bounds: bounds)
        }
    }

    /// Apply a translation expressed either in the shared parent-local space or
    /// in document space. The document-space branch inverses each node's ancestor
    /// transform so a selected child moves by the requested on-screen amount.
    private func applyAlignmentOffsets(_ offsets: [UUID: CGPoint],
                                       items: [AlignmentItem],
                                       documentSpace: Bool,
                                       to nodes: inout [Node]) {
        for item in items {
            guard let delta = offsets[item.id] else { continue }
            let localDelta: CGPoint
            if documentSpace {
                let localOrigin = item.node.frame.origin
                let documentOrigin = parentLocalToDoc(localOrigin, chain: item.ancestors)
                let destination = CGPoint(x: documentOrigin.x + delta.x,
                                          y: documentOrigin.y + delta.y)
                let destinationLocal = docToParentLocal(destination, chain: item.ancestors)
                localDelta = CGPoint(x: destinationLocal.x - localOrigin.x,
                                     y: destinationLocal.y - localOrigin.y)
            } else {
                localDelta = delta
            }
            _ = Self.mutateNested(item.id, in: &nodes) { selected in
                selected.frame.origin.x += localDelta.x
                selected.frame.origin.y += localDelta.y
            }
        }
    }

    private func align(_ edge: SelectionTransform.AlignEdge) {
        guard let app else { return }
        // ONE align command. Boards and nodes are separate collections underneath,
        // but nobody thinks of aligning boards as a different verb from aligning
        // layers, so the same command routes to whichever is selected. Selecting a
        // board clears the node selection, so this test is unambiguous.
        if app.selectedNodeIDs.isEmpty && !app.selectedArtboardIDs.isEmpty {
            alignArtboards(edge)
            return
        }
        // Aligning to the selection needs 2+ (one item is a no-op); aligning to the
        // artboard works on a single item (e.g. center one thing on the board).
        let minCount = app.alignTarget == .artboard ? 1 : 2
        // Siblings align in their common parent-local coordinate system — EXCEPT
        // when that space is not screen-aligned. BUG-042: "Align Left" names a
        // direction the user can SEE, and its button draws a vertical bar. Inside a
        // flipped group, local-left is screen-RIGHT, so aligning in local space did
        // the exact opposite of what the control promised; inside a rotated group it
        // aligned along an axis the user was not looking at. Mixed parents, artboard
        // alignment, and now any transformed ancestor all use document space, then
        // inverse-transform each movement on write-back.
        let documentSpace = app.alignTarget == .artboard
            || selectionLevel(for: app.selectedNodeIDs) == .mixed
            || selectionAncestorsAreTransformed()
        let items = alignmentItems(documentSpace: documentSpace)
        guard items.count >= minCount else { return }
        let ref = alignReference(items.map(\.bounds))
        let offsets = SelectionTransform.alignmentOffsets(
            items.map { ($0.id, $0.bounds) }, edge: edge, reference: ref)
        var nodes = currentNodes
        applyAlignmentOffsets(offsets, items: items,
                              documentSpace: documentSpace, to: &nodes)
        commitNodes(nodes, actionName: "Align")
        needsDisplay = true
    }

    /// Equalize the gaps between selected items along an axis (keeps the two
    /// extremes fixed). Needs 3+.
    private func distribute(horizontal: Bool) {
        guard let app else { return }
        if app.selectedNodeIDs.isEmpty && !app.selectedArtboardIDs.isEmpty {
            distributeArtboards(horizontal: horizontal)
            return
        }
        // Same rule as align (BUG-042): distributing inside a rotated or flipped
        // group has to space things out along the axis on screen, not the group's.
        let documentSpace = selectionLevel(for: app.selectedNodeIDs) == .mixed
            || selectionAncestorsAreTransformed()
        let items = alignmentItems(documentSpace: documentSpace)
        guard items.count >= 3 else { return }
        let offsets = SelectionTransform.distributionOffsets(
            items.map { ($0.id, $0.bounds) }, horizontal: horizontal)
        var nodes = currentNodes
        applyAlignmentOffsets(offsets, items: items,
                              documentSpace: documentSpace, to: &nodes)
        commitNodes(nodes, actionName: "Distribute")
        needsDisplay = true
    }

    // MARK: Artboard placement (align / distribute / clean up)

    /// Move whole boards by per-board offsets, carrying whatever sits on them.
    ///
    /// Two things here are easy to get wrong. Node ownership is by CONTAINMENT, so
    /// the owner map has to be built BEFORE anything moves — read it afterwards and
    /// a board that already slid away will claim (or abandon) the wrong nodes. And
    /// rounding is done once, on the board's landing origin, then the SAME delta is
    /// applied to its children: round them independently and contents drift up to a
    /// point away from the board they belong to.
    private func moveArtboards(_ offsets: [UUID: CGPoint], actionName: String) {
        guard let document, !isSourceScope else { return }

        var deltas: [UUID: CGPoint] = [:]
        for board in currentArtboards {
            guard let offset = offsets[board.id] else { continue }
            let landed = CGPoint(x: (board.frame.origin.x + offset.x).rounded(),
                                 y: (board.frame.origin.y + offset.y).rounded())
            let delta = CGPoint(x: landed.x - board.frame.origin.x,
                                y: landed.y - board.frame.origin.y)
            if delta.x != 0 || delta.y != 0 { deltas[board.id] = delta }
        }
        guard !deltas.isEmpty else { return }

        var owned: [UUID: [UUID]] = [:]
        for node in currentNodes {
            if let owner = owningArtboard(of: node)?.id, deltas[owner] != nil {
                owned[owner, default: []].append(node.id)
            }
        }

        let baseline = document.model
        withActivePage { page in
            for i in page.artboards.indices {
                guard let d = deltas[page.artboards[i].id] else { continue }
                page.artboards[i].frame.origin.x += d.x
                page.artboards[i].frame.origin.y += d.y
            }
        }
        for (boardID, nodeIDs) in owned {
            guard let d = deltas[boardID] else { continue }
            for id in nodeIDs {
                updateNode(id) {
                    $0.frame.origin = CGPoint(x: $0.frame.origin.x + d.x,
                                              y: $0.frame.origin.y + d.y)
                }
            }
        }
        document.registerUndo(restoring: baseline, undoManager: undoManager, actionName: actionName)
        needsDisplay = true
    }

    private var selectedArtboards: [Artboard] {
        guard let app else { return [] }
        return currentArtboards.filter { app.selectedArtboardIDs.contains($0.id) }
    }

    /// Boards always align to the SELECTION's bounding box. There is no enclosing
    /// board to align a board to, so `alignTarget` deliberately doesn't apply.
    private func alignArtboards(_ edge: SelectionTransform.AlignEdge) {
        let boards = selectedArtboards
        guard boards.count >= 2 else { return }
        let reference = boards.dropFirst().reduce(boards[0].frame) { $0.union($1.frame) }
        moveArtboards(
            SelectionTransform.alignmentOffsets(boards.map { ($0.id, $0.frame) },
                                                edge: edge, reference: reference),
            actionName: "Align Artboards")
    }

    private func distributeArtboards(horizontal: Bool) {
        let boards = selectedArtboards
        guard boards.count >= 3 else { return }
        moveArtboards(
            SelectionTransform.distributionOffsets(boards.map { ($0.id, $0.frame) },
                                                   horizontal: horizontal),
            actionName: "Distribute Artboards")
    }

    /// Tidy placement WITHOUT discarding where things are. Boards are clustered into
    /// the rows they already roughly form, each row keeps its left-to-right order,
    /// and the set keeps its top-left origin — so the canvas you remember is the
    /// canvas you get back, just square. Nothing is sorted or renumbered.
    private func cleanUpArtboards() {
        let boards = selectedArtboards
        guard boards.count >= 2 else { return }

        let gap = AppPreferences.artboardSpacingValue
        // Same row when tops are closer than half the shortest board: tolerant
        // enough for hand-placed boards, tight enough not to merge two real rows.
        let tolerance = max(24, (boards.map(\.frame.height).min() ?? 0) / 2)

        var rows: [[Artboard]] = []
        for board in boards.sorted(by: { $0.frame.minY < $1.frame.minY }) {
            if let last = rows.indices.last, let top = rows[last].first?.frame.minY,
               abs(board.frame.minY - top) <= tolerance {
                rows[last].append(board)
            } else {
                rows.append([board])
            }
        }

        let originX = boards.map(\.frame.minX).min() ?? 0
        var y = boards.map(\.frame.minY).min() ?? 0
        var offsets: [UUID: CGPoint] = [:]

        for row in rows {
            var x = originX
            let ordered = row.sorted { $0.frame.minX < $1.frame.minX }
            for board in ordered {
                offsets[board.id] = CGPoint(x: x - board.frame.minX, y: y - board.frame.minY)
                x += board.frame.width + gap
            }
            y += (ordered.map(\.frame.height).max() ?? 0) + gap
        }
        moveArtboards(offsets, actionName: "Clean Up Artboards")
    }

    // MARK: Path-point overlay (anchors + handles)

    private func drawPathPoints(_ node: Node, in ctx: CGContext,
                                selected: Set<PointAddress> = [],
                                handleOwners: Set<PointAddress> = []) {
        guard case .path(let ps) = node.content else { return }
        let chain = ancestorGroups(of: node.id)
        func v(_ local: CGPoint) -> CGPoint { nodeLocalToView(local, node, chain: chain) }
        let visible = bounds.insetBy(dx: -32, dy: -32)
        ctx.saveGState()
        for (c, pts) in ps.editContours.enumerated() {
            for (i, pt) in pts.enumerated() {
                let a = v(pt.point)
                guard visible.contains(a) else { continue }
                let addr = PointAddress(contour: c, index: i)
                let isSelected = selected.contains(addr)
                // Handles are the expensive/visually noisy part on imported SVGs.
                // Show them for selected/active anchors, not for every point in a
                // dense compound path.
                if isSelected || handleOwners.contains(addr) {
                    for handle in [pt.controlIn, pt.controlOut].compactMap({ $0 }) {
                        let hv = v(handle)
                        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
                        ctx.setLineWidth(1)
                        ctx.move(to: a); ctx.addLine(to: hv); ctx.strokePath()
                        let r: CGFloat = 3
                        NSColor.white.setFill(); NSColor.controlAccentColor.setStroke()
                        let dot = CGRect(x: hv.x - r, y: hv.y - r, width: r * 2, height: r * 2)
                        ctx.fillEllipse(in: dot); ctx.strokeEllipse(in: dot)
                    }
                }
                // Anchor square — solid accent fill when selected (so a multi-
                // point selection reads clearly), hollow/white otherwise.
                let box = CGRect(x: a.x - handleSize / 2, y: a.y - handleSize / 2, width: handleSize, height: handleSize)
                if isSelected {
                    NSColor.controlAccentColor.setFill(); NSColor.white.setStroke()
                } else {
                    NSColor.white.setFill(); NSColor.controlAccentColor.setStroke()
                }
                ctx.setLineWidth(1)
                ctx.fill(box); ctx.stroke(box.insetBy(dx: 0.5, dy: 0.5))
            }
        }
        ctx.restoreGState()
    }

    /// True if a document-space point lands on a node's actual geometry. Recurses
    /// into groups so clicking empty space inside a group's bounds doesn't select it.
    /// Rotate a point around a center by `deg` degrees (matches the canvas's
    /// flipped, clockwise-positive convention).
    private func rotatePoint(_ p: CGPoint, around c: CGPoint, byDegrees deg: Double) -> CGPoint {
        guard deg != 0 else { return p }
        let r = deg * .pi / 180
        let s = sin(r), co = cos(r)
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * co - dy * s, y: c.y + dx * s + dy * co)
    }

    /// Point on a cubic bezier at parameter `t`.
    private static func cubicPoint(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint,
                                   _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p3.x,
                       y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p3.y)
    }

    /// Distance from `p` to the segment between two path points — along the
    /// FLATTENED curve when either side has a handle, the straight chord when
    /// not. Returns the distance and the bezier parameter of the nearest spot.
    private static func nearestOnSegment(_ p: CGPoint, _ a: PathPoint, _ b: PathPoint)
        -> (dist: CGFloat, t: CGFloat) {
        func chord(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (dist: CGFloat, t: CGFloat) {
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx*dx + dy*dy
            guard len2 > 0 else { return (hypot(p.x - a.x, p.y - a.y), 0) }
            let t = max(0, min(1, ((p.x - a.x)*dx + (p.y - a.y)*dy) / len2))
            return (hypot(p.x - (a.x + t*dx), p.y - (a.y + t*dy)), t)
        }
        guard a.controlOut != nil || b.controlIn != nil else { return chord(p, a.point, b.point) }
        let c1 = a.controlOut ?? a.point, c2 = b.controlIn ?? b.point
        var best: (dist: CGFloat, t: CGFloat) = (.greatestFiniteMagnitude, 0.5)
        let steps = 24
        var prev = a.point
        for s in 1...steps {
            let t1 = CGFloat(s) / CGFloat(steps)
            let pt = cubicPoint(a.point, c1, c2, b.point, t1)
            let d = chord(p, prev, pt)
            if d.dist < best.dist {
                let t0 = CGFloat(s - 1) / CGFloat(steps)
                best = (d.dist, t0 + d.t * (t1 - t0))
            }
            prev = pt
        }
        return best
    }

    /// De Casteljau split of a cubic at `t`: new handles for the anchor before
    /// (`c1`) and after (`c2`) the cut, plus the on-curve point and ITS handles.
    private static func splitCubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint,
                                   at t: CGFloat)
        -> (c1: CGPoint, midIn: CGPoint, mid: CGPoint, midOut: CGPoint, c2: CGPoint) {
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let p01 = lerp(p0, c1), p12 = lerp(c1, c2), p23 = lerp(c2, p3)
        let p012 = lerp(p01, p12), p123 = lerp(p12, p23)
        return (c1: p01, midIn: p012, mid: lerp(p012, p123), midOut: p123, c2: p23)
    }

    private func nodeHit(_ node: Node, at rawPoint: CGPoint, offset: CGPoint = .zero) -> Bool {
        let frame = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        // Test in the node's UNROTATED space: inverse-rotate the cursor about the
        // node center. (Children recurse with this already-untwisted point.)
        let docPoint = node.rotation != 0
            ? rotatePoint(rawPoint, around: CGPoint(x: frame.midX, y: frame.midY), byDegrees: -node.rotation)
            : rawPoint
        switch node.content {
        case .line:
            guard let (a, b) = lineEndpointsDoc(node, offset: offset), let app else { return false }
            return distanceToSegment(docPoint, a, b) <= 6 / app.zoom
        case .path(let ps):
            guard let app else { return false }
            // Hit-test the ACTUAL ink — real bezier curves, correct winding rule —
            // not an approximation. The old anchor-only polygon (and the old multi-
            // contour "anywhere in the bounding box" shortcut) let the transparent
            // regions of an upper shape swallow clicks meant for the shape under
            // it, making overlapping organic shapes (tree branches) ungrabbable.
            // Rules:
            //   • a VISIBLE fill hits anywhere inside the drawn interior;
            //   • otherwise only the outline hits — within the stroke's own width
            //     or the standard grab tolerance, whichever is wider.
            let tol = max(ps.strokeWidth / 2, 6 / app.zoom)
            // Fast reject: normalizePath keeps `frame` enclosing all anchors AND
            // handles (a cubic never leaves their hull), so the box is a safe gate.
            guard frame.insetBy(dx: -tol, dy: -tol).contains(docPoint) else { return false }
            // Into node-local space (docPoint is already inverse-rotated above);
            // un-flip so the test matches the mirrored ink the renderer draws.
            var local = CGPoint(x: docPoint.x - frame.minX, y: docPoint.y - frame.minY)
            if node.flipH { local.x = frame.width - local.x }
            if node.flipV { local.y = frame.height - local.y }
            if !ps.isMultiContour && ps.points.count == 1 {
                let a = ps.points[0].point
                return hypot(local.x - a.x, local.y - a.y) <= tol
            }
            let ink = Self.inkPath(for: ps)
            let fillDrawn = ps.isMultiContour || (ps.closed && ps.points.count >= 2)   // matches drawNode
            if fillDrawn, paintHittable(ps.fill), ink.contains(local, using: .winding) { return true }
            let band = ink.copy(strokingWithWidth: tol * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            return band.contains(local)
        case .group(let children):
            let childOffset = CGPoint(x: frame.minX, y: frame.minY)
            // Un-mirror through the group's flip (matches hitPath's descent).
            var childPoint = docPoint
            if node.flipH { childPoint.x = 2 * frame.midX - childPoint.x }
            if node.flipV { childPoint.y = 2 * frame.midY - childPoint.y }
            if children.contains(where: { $0.isVisible && nodeHit($0, at: childPoint, offset: childOffset) }) { return true }
            // A filled/stroked padded frame is a solid surface (button/pill) —
            // clickable anywhere inside its rect, including the padding.
            if let pad = node.autoPadding, pad.fill != nil || pad.strokeWidth > 0 { return frame.contains(docPoint) }
            return false
        case .instance(let inst):
            // Hit the instance's RESOLVED box (re-hugged for its overrides).
            let size = document?.model.resolvedSize(of: inst) ?? frame.size
            return CGRect(origin: frame.origin, size: size).contains(docPoint)
        default:
            return frame.contains(docPoint)
        }
    }

    private func zoom(by factor: CGFloat, anchor: CGPoint) {
        guard let app else { return }
        let old = app.zoom
        let new = app.clampZoom(old * factor)
        guard new != old else { return }
        beginPanZoomInteraction()
        let docX = (anchor.x - app.panOffset.x) / old
        let docY = (anchor.y - app.panOffset.y) / old
        app.zoom = new
        app.panOffset = CGPoint(x: anchor.x - docX * new, y: anchor.y - docY * new)
        scheduleCameraPersistenceIfReady()
        suppressBlurDuringInteraction()
        needsDisplay = true
    }

    private var viewCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func fitContent() {
        guard let app, let document else { return }
        let content: CGRect
        if isSourceScope {
            content = sourceBoundsRect() ?? .zero
        } else {
            content = document.model.contentBounds(on: activePageID)
        }
        guard content.width > 0 else { return }
        // Center within the VISIBLE drawing area (inside the top/left ruler strips),
        // so the artboard reads as centered rather than nudged down-right.
        let inset: CGFloat = (app.showRulers && !isSourceScope) ? rulerThickness : 0
        let cx = inset + (bounds.width - inset) / 2
        let cy = inset + (bounds.height - inset) / 2
        app.panOffset = CGPoint(x: cx - content.midX * app.zoom,
                                y: cy - content.midY * app.zoom)
        needsDisplay = true
    }

    /// "Zoom to Fit" — and it now actually fits.
    ///
    /// This used to be `zoom = 1.0` followed by `fitContent()`, which only CENTERS.
    /// It never scaled anything. On any document whose boards span more than a
    /// screen at 100%, centering on the midpoint lands you in the gap BETWEEN
    /// boards — which is exactly why the command reliably dumped you in blank
    /// canvas when you were already lost.
    private func zoomToFit() {
        guard let app else { return }
        let content = fittableContent()
        guard content.width > 0, content.height > 0 else {
            // Genuinely nothing on the page. Still land somewhere predictable
            // rather than leaving the camera wherever the user got lost.
            app.viewportSize = bounds.size
            app.zoom = 1
            app.panOffset = CGPoint(x: bounds.midX, y: bounds.midY)
            scheduleCameraPersistenceIfReady()
            needsDisplay = true
            return
        }
        fitViewport(to: content, maximumZoom: 1)
    }

    /// Everything worth finding on this page. `contentBounds` unions ARTBOARDS
    /// only, but loose artwork parked out on the wall is precisely what you're
    /// hunting for when you're lost, so it counts as content too.
    private func fittableContent() -> CGRect {
        if isSourceScope { return sourceBoundsRect() ?? .zero }
        var rect = CGRect.null
        if let document {
            let boards = document.model.contentBounds(on: activePageID)
            if boards.width > 0 || boards.height > 0 { rect = boards }
        }
        for node in currentNodes {
            rect = rect.isNull ? node.frame : rect.union(node.frame)
        }
        return rect.isNull ? .zero : rect
    }

    /// Document-space bounds of whatever is selected — boards if any, else nodes.
    /// Node bounds come from `alignmentItems(documentSpace:)` because a nested
    /// node's own `frame` is PARENT-local and would point at the wrong place.
    private func selectionBounds() -> CGRect {
        guard let app else { return .null }
        var rect = CGRect.null
        if !app.selectedArtboardIDs.isEmpty {
            for board in currentArtboards where app.selectedArtboardIDs.contains(board.id) {
                rect = rect.isNull ? board.frame : rect.union(board.frame)
            }
            return rect
        }
        for item in alignmentItems(documentSpace: true) {
            rect = rect.isNull ? item.bounds : rect.union(item.bounds)
        }
        return rect
    }

    /// Bring a rectangle on screen WITHOUT yanking the zoom around: if it's already
    /// fully visible, do nothing; if it fits at the current zoom, just pan; only
    /// zoom out when it genuinely can't fit. Losing your zoom level is its own kind
    /// of being lost, so this never zooms in.
    private func revealInViewport(_ rect: CGRect) {
        guard let app, !rect.isNull, rect.width > 0, rect.height > 0 else { return }
        app.viewportSize = bounds.size
        if let visible = app.visibleDocumentRect, visible.contains(rect) { return }

        let inset: CGFloat = (app.showRulers && !isSourceScope) ? rulerThickness : 0
        let padding: CGFloat = 48
        let availableWidth = max(1, bounds.width - inset - padding * 2)
        let availableHeight = max(1, bounds.height - inset - padding * 2)

        if rect.width * app.zoom <= availableWidth && rect.height * app.zoom <= availableHeight {
            let cx = inset + (bounds.width - inset) / 2
            let cy = inset + (bounds.height - inset) / 2
            app.panOffset = CGPoint(x: cx - rect.midX * app.zoom,
                                    y: cy - rect.midY * app.zoom)
            scheduleCameraPersistenceIfReady()
            needsDisplay = true
        } else {
            fitViewport(to: rect, maximumZoom: app.zoom)
        }
    }

    /// Put a newly imported region visibly in front of the designer. Importers
    /// place content away from existing work, so selection alone is not enough
    /// feedback—the selected artboard can otherwise remain entirely off-screen.
    private func fitViewport(to content: CGRect, maximumZoom: CGFloat = 1) {
        guard let app, content.width > 0, content.height > 0,
              bounds.width > 1, bounds.height > 1 else { return }
        let rulerInset: CGFloat = (app.showRulers && !isSourceScope) ? rulerThickness : 0
        let padding: CGFloat = 48
        let availableWidth = max(1, bounds.width - rulerInset - padding * 2)
        let availableHeight = max(1, bounds.height - rulerInset - padding * 2)
        let zoom = app.clampZoom(min(maximumZoom,
                                     availableWidth / content.width,
                                     availableHeight / content.height))
        let centerX = rulerInset + (bounds.width - rulerInset) / 2
        let centerY = rulerInset + (bounds.height - rulerInset) / 2
        app.viewportSize = bounds.size
        app.zoom = zoom
        app.panOffset = CGPoint(x: centerX - content.midX * zoom,
                                y: centerY - content.midY * zoom)
        scheduleCameraPersistenceIfReady()
        needsDisplay = true
    }

    // MARK: Scoped node access
    //
    // The canvas edits either the document's top-level nodes (.document) or a
    // component source's children (.source). Everything below reads/writes the
    // node list through these accessors, so the same canvas drives both windows.

    private var sourceIndex: Int? {
        guard case .source(let sid) = scope else { return nil }
        return document?.model.sources.firstIndex { $0.id == sid }
    }

    private var activePageID: UUID? {
        document?.model.pageID(resolving: app?.activeCanvasPageID)
    }

    private var activePageIndex: Int? {
        document?.model.pageIndex(for: activePageID)
    }

    private var currentArtboards: [Artboard] {
        guard !isSourceScope, let document else { return [] }
        return document.model.page(for: activePageID)?.artboards ?? []
    }

    private var currentGuides: [Guide] {
        guard !isSourceScope, let document else { return [] }
        return document.model.page(for: activePageID)?.guides ?? []
    }

    private func owningArtboard(of frame: CGRect) -> Artboard? {
        guard !isSourceScope else { return nil }
        return document?.model.owningArtboard(of: frame, on: activePageID)
    }

    private func owningArtboard(of node: Node) -> Artboard? {
        guard !isSourceScope else { return nil }
        return document?.model.owningArtboard(of: node, on: activePageID)
    }

    private func withActivePage(_ body: (inout CanvasPage) -> Void) {
        guard !isSourceScope, let document,
              let index = document.model.pageIndex(for: activePageID) else { return }
        body(&document.model.pages[index])
    }

    /// The component source's viewBox — its own little artboard: a STABLE,
    /// user-resizable rect (NOT auto-hugged to content), so elements can be moved /
    /// centered within it like an SVG viewBox. nil outside source scope.
    private func sourceBoundsRect() -> CGRect? {
        guard let si = sourceIndex, let document else { return nil }
        return document.model.sources[si].bounds
    }

    /// The component STATE being edited in this window (source scope only;
    /// nil = default/base). Display resolves through it and `commitNodes`
    /// splits edits into base + diff while it's set (v1.6 Chunk H).
    private var activeEditingState: ComponentState? {
        guard case .source = scope, let sid = app?.activeComponentStateID,
              let si = sourceIndex, let document else { return nil }
        return document.model.sources[si].states.first { $0.id == sid }
    }

    /// The editable node list for the current scope. With a component state
    /// active, this is the base children WITH the state's text/fill overrides
    /// applied — display, hit-testing, and editing all see the state's look,
    /// while the underlying model keeps base + diff separate.
    private var currentNodes: [Node] {
        guard let document else { return [] }
        switch scope {
        case .document: return document.model.page(for: activePageID)?.nodes ?? []
        case .source:
            guard let si = sourceIndex else { return [] }
            let children = document.model.sources[si].children
            if let state = activeEditingState {
                return ComponentStateEditing.applied(children, state: state)
            }
            return children
        }
    }

    /// Visual-only source nodes. State text overrides can resize managed frames
    /// for preview, while edit/commit paths keep using `currentNodes` so the base
    /// geometry doesn't accidentally absorb preview-only reflow.
    private var displayedCurrentNodes: [Node] {
        guard let document else { return [] }
        switch scope {
        case .document:
            return document.model.page(for: activePageID)?.nodes ?? []
        case .source:
            guard let si = sourceIndex else { return [] }
            let children = document.model.sources[si].children
            if let state = activeEditingState {
                // Reflow through the document so component instances inside a
                // state contribute their resolved size, not a stale frame
                // (BUG-007).
                return document.model.reflowed(
                    ComponentStateEditing.applied(children, state: state))
            }
            return children
        }
    }

    /// Mutate the current scope's node array in place (for live drag feedback).
    private func withNodes(_ body: (inout [Node]) -> Void) {
        guard let document else { return }
        switch scope {
        case .document:
            guard let index = activePageIndex else { return }
            body(&document.model.pages[index].nodes)
        case .source:
            guard let si = sourceIndex else { return }
            body(&document.model.sources[si].children)
        }
    }

    /// True when this canvas edits a component source rather than the document.
    private var isSourceScope: Bool { if case .source = scope { return true }; return false }

    private func flattenedNodes(_ nodes: [Node]) -> [Node] {
        nodes.flatMap { node -> [Node] in
            if case .group(let children) = node.content {
                return [node] + flattenedNodes(children)
            }
            return [node]
        }
    }

    /// Mirrors `MainWindow`'s rule: reachable when the COMPONENT ROOT can carry
    /// relationships, or when the selected layer has a role of its OWN. ARIA roles
    /// do not inherit, so sitting inside a roled component is not enough — that
    /// was BUG-008. Kept in step with the inspector deliberately; the menu item and
    /// the panel must never disagree about whether there is anything to edit.
    /// Mirrors `MainWindow`'s rule, and both now answer from the SAME model
    /// predicate rather than each keeping a copy — which is how a menu item and a
    /// panel drift apart. Relationships are reachable when there is an anchor
    /// holding both ends and something inside it that can carry one.
    private var canEditRelationships: Bool {
        guard let document else { return false }
        let allNodes = flattenedNodes(currentNodes)
        let selected: Node? = {
            guard let app, app.selectedNodeIDs.count == 1,
                  let selectedID = app.selectedNodeIDs.first else { return nil }
            return allNodes.first { $0.id == selectedID }
        }()
        let carries = selected.map { document.model.hasRelationshipParticipant(in: $0) } ?? false
        guard isSourceScope, case .source(let sid) = scope,
              let source = document.model.source(for: sid) else {
            // Document scope: enabled even when the layer is not grouped yet, so the
            // panel can explain the grouping rule instead of the menu going grey for
            // a reason nobody can see.
            return carries
        }
        let rootCarries = !(source.a11y.role?.authoredRelationshipKinds.isEmpty ?? true)
            || !source.anchoredRelationships.isEmpty
        return carries || rootCarries
    }

    /// Replace the current scope's node list and register one undo step.
    /// - Parameter appendingRootAnchors: relationships that must land on the SCOPE
    ///   ROOT (the document, or the component source) rather than on any node —
    ///   what happens when a top-level group carrying them is ungrouped. Passed
    ///   through here rather than committed separately so the whole edit remains a
    ///   single undo step.
    /// - Parameter removingAnchorsReferencing: node ids being explicitly deleted.
    ///   Relationships naming them at either end go with them, in the SAME undo
    ///   step, so an undo restores the layer and its connections together.
    private func commitNodes(_ newNodes: [Node], actionName: String,
                             appendingRootAnchors rootAnchors: [AnchoredRelationship] = [],
                             removingAnchorsReferencing removedIDs: Set<UUID> = []) {
        guard let document else { return }
        // Editing a component STATE: split the edited tree into base + diff.
        // Appearance changes become the state's override-diff; geometry and
        // structural edits pass through to the base shared by every state.
        if case .source(let sid) = scope, let state = activeEditingState {
            var model = document.model
            guard let si = model.sources.firstIndex(where: { $0.id == sid }) else { return }
            let (newBase, newState) = ComponentStateEditing.capture(
                base: model.sources[si].children, edited: newNodes, state: state)
            let reflowed = model.reflowed(newBase)
            let fitSourceBounds = model.sourceUsesManagedBounds(model.sources[si])
            model.sources[si].children = reflowed
            if let sti = model.sources[si].states.firstIndex(where: { $0.id == state.id }) {
                model.sources[si].states[sti] = newState
            }
            if fitSourceBounds, let bounds = model.managedRootBounds(in: reflowed) {
                model.sources[si].origin = bounds.origin
                model.sources[si].size = bounds.size
            }
            model.sources[si].anchoredRelationships.append(contentsOf: rootAnchors)
            if !removedIDs.isEmpty {
                model.sources[si].anchoredRelationships = Document.removingAnchors(
                    referencing: removedIDs, in: model.sources[si].anchoredRelationships)
                Document.removingAnchors(referencing: removedIDs,
                                         in: &model.sources[si].children)
            }
            document.setModel(model, undoManager: undoManager, actionName: actionName)
            return
        }
        // Reflow auto-layout frames before committing, so any change (text growing,
        // a child resized/added/removed, a layout setting tweaked) ripples through
        // managed frames in the same undo step.
        var model = document.model
        let reflowed = model.reflowed(newNodes)
        switch scope {
        case .document:
            guard let pageIndex = model.pageIndex(for: activePageID) else { return }
            model.pages[pageIndex].nodes = reflowed
            model.pages[pageIndex].anchoredRelationships.append(contentsOf: rootAnchors)
            if !removedIDs.isEmpty {
                model.pages[pageIndex].anchoredRelationships = Document.removingAnchors(
                    referencing: removedIDs, in: model.pages[pageIndex].anchoredRelationships)
                Document.removingAnchors(referencing: removedIDs,
                                         in: &model.pages[pageIndex].nodes)
            }
            model.reconcileArtboardOwnership(on: model.pages[pageIndex].id)
        case .source(let sid):
            guard let si = model.sources.firstIndex(where: { $0.id == sid }) else { return }
            let fitSourceBounds = model.sourceUsesManagedBounds(model.sources[si])
            model.sources[si].children = reflowed
            if fitSourceBounds,
               let bounds = model.managedRootBounds(in: reflowed) {
                model.sources[si].origin = bounds.origin
                model.sources[si].size = bounds.size
            }
            model.sources[si].anchoredRelationships.append(contentsOf: rootAnchors)
            if !removedIDs.isEmpty {
                model.sources[si].anchoredRelationships = Document.removingAnchors(
                    referencing: removedIDs, in: model.sources[si].anchoredRelationships)
                Document.removingAnchors(referencing: removedIDs,
                                         in: &model.sources[si].children)
            }
        }
        document.setModel(model, undoManager: undoManager, actionName: actionName)
    }

    // MARK: Lookups

    private func nodeIndex(_ id: UUID) -> Int? {
        currentNodes.firstIndex { $0.id == id }
    }

    /// Find a node by id, searching INTO groups (so nested children resolve). The
    /// returned node's `frame` is in its parent's local space — use `nodeOffset` to
    /// get the document-space origin to add.
    private func node(_ id: UUID) -> Node? {
        func find(_ nodes: [Node]) -> Node? {
            for n in nodes {
                if n.id == id { return n }
                if case .group(let kids) = n.content, let f = find(kids) { return f }
            }
            return nil
        }
        return find(currentNodes)
    }

    /// The accumulated document-space offset of a node (sum of ancestor group
    /// origins). `.zero` for a top-level node. A nested node's absolute frame is
    /// `node.frame.offsetBy(nodeOffset(id))`.
    private func nodeOffset(_ id: UUID) -> CGPoint {
        func find(_ nodes: [Node], _ off: CGPoint) -> CGPoint? {
            for n in nodes {
                if n.id == id { return off }
                if case .group(let kids) = n.content,
                   let r = find(kids, CGPoint(x: off.x + n.frame.minX, y: off.y + n.frame.minY)) { return r }
            }
            return nil
        }
        return find(currentNodes, .zero) ?? .zero
    }

    /// True if `id` is a top-level node (not nested inside a group).
    private func isTopLevelNode(_ id: UUID) -> Bool {
        currentNodes.contains { $0.id == id }
    }

    /// True when the node's ancestor chain applies NO transform — every group
    /// above it is unrotated AND unflipped — so plain offset math (`nodeOffset`)
    /// is exact. Single-node resize/rotate handles are only offered here; under
    /// a transformed group the node stays move-only (same rule the rotated-
    /// ancestor case always had, now covering flips too).
    private func ancestorsUntransformed(_ id: UUID) -> Bool {
        ancestorGroups(of: id).allSatisfy { $0.rotation == 0 && !$0.flipH && !$0.flipV }
    }

    private enum SelectionLevel: Equatable {
        case none
        case topLevel
        case group(UUID)
        case mixed
    }

    /// The direct parent level shared by a node selection.
    private func selectionLevel(for ids: Set<UUID>) -> SelectionLevel {
        guard !ids.isEmpty else { return .none }
        var parent: UUID?
        var sawFirst = false
        for id in ids {
            guard node(id) != nil else { continue }
            let p = parentGroupID(of: id)
            if !sawFirst {
                parent = p
                sawFirst = true
            } else if parent != p {
                return .mixed
            }
        }
        guard sawFirst else { return .none }
        return parent.map { .group($0) } ?? .topLevel
    }

    private func hitTargetInSelectionLevel(from path: [(id: UUID, offset: CGPoint)],
                                           level: SelectionLevel) -> UUID? {
        switch level {
        case .group(let parentID):
            return path.last(where: { parentGroupID(of: $0.id) == parentID })?.id
        case .topLevel:
            return path.first?.id
        case .none, .mixed:
            return nil
        }
    }

    private func childIDs(inParentGroup parentID: UUID?) -> [UUID] {
        guard let parentID else { return currentNodes.map(\.id) }
        guard let parent = node(parentID), case .group(let children) = parent.content else { return [] }
        return children.map(\.id)
    }

    /// Total rotation (degrees) of a node's ANCESTOR groups — the rotation of the
    /// coordinate space its `frame.origin` lives in. 0 for a top-level node. (The
    /// node's own rotation isn't included; that rotates its content, not its slot.)
    private func ancestorRotation(of id: UUID) -> Double {
        func find(_ nodes: [Node], _ acc: Double) -> Double? {
            for n in nodes {
                if n.id == id { return acc }
                if case .group(let k) = n.content, let r = find(k, acc + n.rotation) { return r }
            }
            return nil
        }
        return find(currentNodes, 0) ?? 0
    }

    /// Rotate a free vector (no center) by `deg`, matching the canvas's flipped,
    /// clockwise-positive convention.
    private func rotateVector(_ v: CGPoint, byDegrees deg: Double) -> CGPoint {
        guard deg != 0 else { return v }
        let r = deg * .pi / 180, s = sin(r), c = cos(r)
        return CGPoint(x: v.x * c - v.y * s, y: v.x * s + v.y * c)
    }

    /// The ancestor groups of a node, outermost (top-level) first to its immediate
    /// parent. Empty for a top-level node.
    private func ancestorGroups(of id: UUID) -> [Node] {
        var chain: [Node] = []
        func find(_ nodes: [Node], _ stack: [Node]) -> Bool {
            for n in nodes {
                if n.id == id { chain = stack; return true }
                if case .group(let k) = n.content, find(k, stack + [n]) { return true }
            }
            return false
        }
        _ = find(currentNodes, [])
        return chain
    }

    /// Map a point from a node's PARENT-local space up to document space, applying
    /// each ancestor group's FLIP mirror and rotation about its center (innermost
    /// parent first) — the renderer mirrors a flipped group's whole subtree, so
    /// skipping the flip here put children "back in their unflipped position".
    private func parentLocalToDoc(_ p: CGPoint, chain: [Node]) -> CGPoint {
        var pt = p
        for g in chain.reversed() {
            var x = pt.x + g.frame.minX, y = pt.y + g.frame.minY   // into the group's parent space
            if g.flipH { x = 2 * g.frame.midX - x }
            if g.flipV { y = 2 * g.frame.midY - y }
            if g.rotation != 0 {
                let cx = g.frame.midX, cy = g.frame.midY
                let r = g.rotation * .pi / 180, s = sin(r), c = cos(r)
                let dx = x - cx, dy = y - cy
                x = cx + dx * c - dy * s
                y = cy + dx * s + dy * c
            }
            pt = CGPoint(x: x, y: y)
        }
        return pt
    }

    /// Inverse of `parentLocalToDoc`: document space → a node's parent-local space
    /// (un-rotate about each group's center, then un-mirror its flip).
    private func docToParentLocal(_ p: CGPoint, chain: [Node]) -> CGPoint {
        var pt = p
        for g in chain {   // outermost first (undo in reverse order)
            if g.rotation != 0 {
                let cx = g.frame.midX, cy = g.frame.midY
                let r = -g.rotation * .pi / 180, s = sin(r), c = cos(r)
                let dx = pt.x - cx, dy = pt.y - cy
                pt = CGPoint(x: cx + dx * c - dy * s, y: cy + dx * s + dy * c)
            }
            if g.flipH { pt.x = 2 * g.frame.midX - pt.x }
            if g.flipV { pt.y = 2 * g.frame.midY - pt.y }
            pt = CGPoint(x: pt.x - g.frame.minX, y: pt.y - g.frame.minY)
        }
        return pt
    }

    /// A node-local point (relative to its frame origin) → VIEW, honoring the node's
    /// own rotation AND every ancestor group's transform.
    // MARK: On-canvas gradient line (FEAT-032)

    /// `line(t)` is a hit on the gradient line itself, `t` being the position along
    /// it — that is where a click ADDS a stop (FEAT-045).
    enum GradientHandleHit: Equatable { case start, end, stop(UUID), line(CGFloat) }

    /// The LINEAR gradient fill of a node, if it has one. Radial is excluded on
    /// purpose: its on-canvas control is a different shape (centre + radius) and is
    /// not what this feature was asked for.
    private func linearGradientFill(of node: Node) -> GradientFill? {
        let paint: Paint?
        switch node.content {
        case .rectangle(let s): paint = s.fill
        case .ellipse(let s):   paint = s.fill
        case .polygon(let s):   paint = s.fill
        case .path(let s):      paint = s.fill
        default:                paint = nil
        }
        guard let g = paint?.gradientValue, g.kind == .linear else { return nil }
        return g
    }

    private func setGradientFill(_ g: GradientFill, on id: UUID) {
        updateNode(id) { n in
            switch n.content {
            case .rectangle(var s): s.fill = .gradient(g); n.content = .rectangle(s)
            case .ellipse(var s):   s.fill = .gradient(g); n.content = .ellipse(s)
            case .polygon(var s):   s.fill = .gradient(g); n.content = .polygon(s)
            case .path(var s):      s.fill = .gradient(g); n.content = .path(s)
            default: break
            }
        }
    }

    /// Unit space (0…1 of the fill rect) ⇄ the node's local points. Going through
    /// `nodeLocalToView` / `viewToNodeLocal` is what makes the line follow the shape
    /// through its own rotation and flip and every ancestor transform.
    private func gradientUnitToView(_ u: CGPoint, _ n: Node, chain: [Node]) -> CGPoint {
        nodeLocalToView(CGPoint(x: u.x * n.frame.width, y: u.y * n.frame.height), n, chain: chain)
    }

    private func gradientViewToUnit(_ p: CGPoint, _ n: Node, chain: [Node]) -> CGPoint {
        let l = viewToNodeLocal(p, n, chain: chain)
        return CGPoint(x: n.frame.width  > 0 ? l.x / n.frame.width  : 0,
                       y: n.frame.height > 0 ? l.y / n.frame.height : 0)
    }

    /// The gradient handle line for the current selection, in view space.
    private func gradientHandleLine()
        -> (id: UUID, node: Node, chain: [Node], gradient: GradientFill,
            start: CGPoint, end: CGPoint)? {
        guard app?.tool == .select, editingNodeID == nil,
              let id = app?.singleSelectedNodeID, let n = node(id),
              n.frame.width > 0, n.frame.height > 0,
              let g = linearGradientFill(of: n) else { return nil }
        let chain = ancestorGroups(of: id)
        let (u0, u1) = g.unitLinearPoints(in: CGRect(origin: .zero, size: n.frame.size))
        return (id, n, chain, g,
                gradientUnitToView(u0, n, chain: chain),
                gradientUnitToView(u1, n, chain: chain))
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Ends win over stops, stops win over the bare line — a stop at 0 or 1 sits
    /// underneath an end, and every stop sits on the line.
    ///
    /// The LINE is deliberately hit-testable along its whole length, INCLUDING where
    /// it crosses a hole in the shape or empty space beyond the ink. It is chrome for
    /// the already-selected object, not part of the object: a click on it must never
    /// fall through and deselect what you are editing (owner requirement 2026-08-19).
    private func hitTestGradientHandle(atViewPoint p: CGPoint) -> (id: UUID, hit: GradientHandleHit)? {
        guard let h = gradientHandleLine() else { return nil }
        func near(_ c: CGPoint) -> Bool {
            hypot(p.x - c.x, p.y - c.y) <= handleGrab * 0.6
        }
        if near(h.start) { return (h.id, .start) }
        if near(h.end)   { return (h.id, .end) }
        for stop in h.gradient.sortedStops
        where near(Self.lerp(h.start, h.end, CGFloat(stop.position))) {
            return (h.id, .stop(stop.id))
        }
        // Distance to the SEGMENT (not the infinite line), so the grab region stops
        // at the ends rather than running off across the canvas.
        let vx = h.end.x - h.start.x, vy = h.end.y - h.start.y
        let len2 = vx * vx + vy * vy
        guard len2 > 1e-9 else { return nil }
        let t = max(0, min(1, ((p.x - h.start.x) * vx + (p.y - h.start.y) * vy) / len2))
        let c = CGPoint(x: h.start.x + vx * t, y: h.start.y + vy * t)
        guard hypot(p.x - c.x, p.y - c.y) <= 5 else { return nil }
        return (h.id, .line(t))
    }

    /// Add a stop where the line was clicked, in the colour already showing there, and
    /// make it the selected stop. Returns its id so the click can go straight into a
    /// drag — click-and-drag places a stop in one motion.
    @discardableResult
    private func addGradientStop(on id: UUID, at t: CGFloat) -> UUID? {
        guard let n = node(id), var g = linearGradientFill(of: n) else { return nil }
        let stop = GradientStop(color: g.color(at: Double(t)), position: Double(t))
        g.stops.append(stop)
        dragBaseline = document?.model
        gestureUndoName = "Add Gradient Stop"
        setGradientFill(g, on: id)
        registerUndoForGesture()
        dragBaseline = nil
        app?.selectedGradientStopID = stop.id
        needsDisplay = true
        return stop.id
    }

    // MARK: Gradient stop editing (FEAT-045)

    /// One discrete edit to a stop, as one undo step. Live DRAGS go through
    /// `setGradientFill` directly and register once on mouse-up; this is for the
    /// menu and the popover, where each change is its own action.
    private func mutateGradientStop(nodeID: UUID, stopID: UUID, actionName: String,
                                    _ change: (inout GradientStop) -> Void) {
        guard let n = node(nodeID), var g = linearGradientFill(of: n),
              let i = g.stops.firstIndex(where: { $0.id == stopID }) else { return }
        dragBaseline = document?.model
        gestureUndoName = actionName
        change(&g.stops[i])
        setGradientFill(g, on: nodeID)
        registerUndoForGesture()
        dragBaseline = nil
        needsDisplay = true
    }

    private func gradientStop(nodeID: UUID, stopID: UUID) -> GradientStop? {
        guard let n = node(nodeID), let g = linearGradientFill(of: n) else { return nil }
        return g.stops.first { $0.id == stopID }
    }

    /// The stop's editor, as a popover anchored to its knob ON THE CANVAS. This is the
    /// point of the whole feature: the colour control appears where you are looking,
    /// instead of in a panel picker that can move out from under you mid-edit.
    /// It reuses `ColorPopover`, so the eyedropper, the code field, the WCAG contrast
    /// strip and "add to Design Language" all come along unchanged.
    private func showGradientStopEditor(nodeID: UUID, stopID: UUID) {
        gradientStopPopover?.close()
        gradientStopPopover = nil
        guard let h = gradientHandleLine(), h.id == nodeID,
              let stop = h.gradient.stops.first(where: { $0.id == stopID }) else { return }
        let knob = Self.lerp(h.start, h.end, CGFloat(stop.position))
        let color = Binding<RGBAColor>(
            get: { [weak self] in self?.gradientStop(nodeID: nodeID, stopID: stopID)?.color ?? .black },
            set: { [weak self] c in
                self?.mutateGradientStop(nodeID: nodeID, stopID: stopID,
                                         actionName: "Gradient Stop Color") { $0.color = c }
            })
        let position = Binding<Double>(
            get: { [weak self] in
                Double(self?.gradientStop(nodeID: nodeID, stopID: stopID)?.position ?? 0) * 100
            },
            set: { [weak self] v in
                self?.mutateGradientStop(nodeID: nodeID, stopID: stopID,
                                         actionName: "Gradient Stop Position") {
                    $0.position = min(1, max(0, v / 100))
                }
            })
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: GradientStopEditor(color: color, positionPercent: position))
        popover.show(relativeTo: CGRect(x: knob.x - 6, y: knob.y - 6, width: 12, height: 12),
                     of: self, preferredEdge: .maxY)
        gradientStopPopover = popover
    }

    @objc func editGradientStopAction(_ sender: Any?) {
        guard let m = pendingGradientMenu, let stopID = m.stopID else { return }
        showGradientStopEditor(nodeID: m.nodeID, stopID: stopID)
    }

    /// Send the stop's colour straight to the document's Design Language.
    ///
    /// This REPLACED "Copy Color" here (owner 2026-08-19): copying a hex only to turn
    /// around and paste it into the library was a step that did not need to exist, and
    /// the library is where a colour worth keeping actually belongs. Uses the same
    /// `save` + `remember` pair as the picker's own Save button, so a colour added
    /// from the canvas is indistinguishable from one added anywhere else — with
    /// `provenance` saying where it came from. Partly delivers FEAT-034.
    @objc func addGradientStopColorToDesignLanguageAction(_ sender: Any?) {
        guard let m = pendingGradientMenu, let stopID = m.stopID,
              let stop = gradientStop(nodeID: m.nodeID, stopID: stopID),
              let document else { return }
        var model = document.model
        let paint = Paint.solid(stop.color)
        _ = model.designLanguage.save(paint, provenance: "gradient stop")
        model.designLanguage.remember(paint)
        document.setModel(model, undoManager: undoManager, actionName: "Save Color")
    }

    @objc func copyGradientStopAction(_ sender: Any?) {
        guard let m = pendingGradientMenu, let stopID = m.stopID,
              let stop = gradientStop(nodeID: m.nodeID, stopID: stopID) else { return }
        app?.copiedGradientStop = CopiedGradientStop(color: stop.color,
                                                     position: Double(stop.position))
    }

    /// Add a stop where the menu was opened — the right-click equivalent of clicking
    /// the line, so both routes to "put a stop here" exist.
    @objc func addGradientStopHereAction(_ sender: Any?) {
        guard let m = pendingGradientMenu else { return }
        addGradientStop(on: m.nodeID, at: m.t)
    }

    /// Paste puts the copied colour WHERE THE POINTER IS, not where it was copied
    /// from (owner revision 2026-08-19 — "put it where the mouse is to paste").
    ///
    /// Consequence worth knowing: the position stored by Copy Stop is now unused by
    /// Paste. It is still copied because it honestly describes the stop, but if that
    /// stays unused, Copy Stop and Copy Color end up meaning almost the same thing and
    /// one of them should probably go. Recorded rather than quietly resolved.
    ///
    /// Right-clicking ON a stop pastes at that stop's own position, which lands on the
    /// existing stop and recolours it instead of stacking an unseparable duplicate.
    @objc func pasteGradientStopAction(_ sender: Any?) {
        guard let copied = app?.copiedGradientStop, let m = pendingGradientMenu,
              let n = node(m.nodeID), var g = linearGradientFill(of: n) else { return }
        let t = Double(min(1, max(0, m.t)))
        dragBaseline = document?.model
        gestureUndoName = "Paste Gradient Stop"
        if let i = g.stops.firstIndex(where: { abs(Double($0.position) - t) < 0.005 }) {
            g.stops[i].color = copied.color
            app?.selectedGradientStopID = g.stops[i].id
        } else {
            let stop = GradientStop(color: copied.color, position: CGFloat(t))
            g.stops.append(stop)
            app?.selectedGradientStopID = stop.id
        }
        setGradientFill(g, on: m.nodeID)
        registerUndoForGesture()
        dragBaseline = nil
        needsDisplay = true
    }

    /// Delete a stop. Refuses below two, because a gradient with one stop is not a
    /// gradient and there is no sensible thing to draw.
    @objc func deleteGradientStopAction(_ sender: Any?) {
        guard let m = pendingGradientMenu, let stopID = m.stopID,
              let n = node(m.nodeID), var g = linearGradientFill(of: n),
              g.stops.count > 2, let i = g.stops.firstIndex(where: { $0.id == stopID })
        else { NSSound.beep(); return }
        dragBaseline = document?.model
        gestureUndoName = "Delete Gradient Stop"
        g.stops.remove(at: i)
        setGradientFill(g, on: m.nodeID)
        registerUndoForGesture()
        dragBaseline = nil
        if app?.selectedGradientStopID == stopID { app?.selectedGradientStopID = nil }
        needsDisplay = true
    }

    /// Snap a dragged end to 15° steps about the fixed end, measured in the node's
    /// LOCAL point space — the space the gradient's angle is defined in. Snapping in
    /// unit space would mean a different real angle on every aspect ratio.
    private static func constrainedGradientEnd(_ u: CGPoint, from fixed: CGPoint,
                                               size: CGSize) -> CGPoint {
        let dx = (u.x - fixed.x) * size.width, dy = (u.y - fixed.y) * size.height
        let len = hypot(dx, dy)
        guard len > 0.0001 else { return u }
        let snapped = (atan2(dy, dx) * 180 / .pi / 15).rounded() * 15 * .pi / 180
        return CGPoint(x: fixed.x + (size.width  > 0 ? cos(snapped) * len / size.width  : 0),
                       y: fixed.y + (size.height > 0 ? sin(snapped) * len / size.height : 0))
    }

    // MARK: Point-selection transform box (FEAT-026)

    /// Padding around the point box, in NODE-LOCAL units so it is a constant size on
    /// screen. The box is deliberately NOT tight: its corner handle would otherwise
    /// sit exactly on the extreme anchor and make that anchor impossible to grab.
    private var pointBoxPadding: CGFloat { 7 / max(0.0001, app?.zoom ?? 1) }

    /// The transform box for the current point selection, in the edited path's
    /// NODE-LOCAL space — the space `PathPoint.point` lives in, so the box, its
    /// handles and the write-back all inherit the node's own rotation/flip and every
    /// ancestor transform for free.
    ///
    /// Bounds come from the selected ANCHORS only, not their control handles, which
    /// matches the pivot the inspector's point-rotation field has always used.
    private func pointTransformBox() -> (node: Node, chain: [Node], box: CGRect)? {
        guard app?.tool == .node, selectedPointAddresses.count >= 2,
              let id = app?.singleSelectedNodeID, let n = node(id),
              case .path(let ps) = n.content else { return nil }
        let contours = ps.editContours
        var pts: [CGPoint] = []
        for addr in selectedPointAddresses
        where contours.indices.contains(addr.contour)
            && contours[addr.contour].indices.contains(addr.index) {
            pts.append(contours[addr.contour][addr.index].point)
        }
        guard pts.count >= 2 else { return nil }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let pad = pointBoxPadding
        let box = CGRect(x: xs.min()! - pad, y: ys.min()! - pad,
                         width: (xs.max()! - xs.min()!) + pad * 2,
                         height: (ys.max()! - ys.min()!) + pad * 2)
        return (n, ancestorGroups(of: id), box)
    }

    private func pointBoxCorners(_ box: CGRect, _ n: Node, _ chain: [Node]) -> [CGPoint] {
        [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
         CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            .map { nodeLocalToView($0, n, chain: chain) }
    }

    private func hitTestPointBoxHandle(atViewPoint point: CGPoint)
        -> (handle: Handle, box: CGRect)? {
        guard let b = pointTransformBox() else { return nil }
        for handle in Handle.allCases {
            let c = nodeLocalToView(handlePoint(handle, in: b.box), b.node, chain: b.chain)
            if CGRect(x: c.x - handleGrab / 2, y: c.y - handleGrab / 2,
                      width: handleGrab, height: handleGrab).contains(point) {
                return (handle, b.box)
            }
        }
        return nil
    }

    private func hitTestPointBoxRotate(atViewPoint point: CGPoint)
        -> (centerLocal: CGPoint, centerView: CGPoint, corner: CGPoint)? {
        guard let b = pointTransformBox() else { return nil }
        guard let corner = cornerRotateRegion(at: point,
                                              corners: pointBoxCorners(b.box, b.node, b.chain))
        else { return nil }
        let centerLocal = CGPoint(x: b.box.midX, y: b.box.midY)
        return (centerLocal, nodeLocalToView(centerLocal, b.node, chain: b.chain), corner)
    }

    /// Pointer angle measured IN node-local space, so a flipped or rotated ancestor
    /// cannot reverse the direction the points turn.
    private func pointBoxAngle(ofViewPoint p: CGPoint, aroundLocal c: CGPoint,
                               node n: Node, chain: [Node]) -> Double {
        let b = viewToNodeLocal(p, n, chain: chain)
        var deg = atan2(Double(b.x - c.x), Double(-(b.y - c.y))) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    /// The selected anchors and their handles, captured at drag start.
    private func selectedPointBaseline(_ ps: PathShape) -> PointBaseline {
        var out = PointBaseline()
        let contours = ps.editContours
        for addr in selectedPointAddresses
        where contours.indices.contains(addr.contour)
            && contours[addr.contour].indices.contains(addr.index) {
            let pt = contours[addr.contour][addr.index]
            out[addr] = (point: pt.point, controlIn: pt.controlIn, controlOut: pt.controlOut)
        }
        return out
    }

    /// Map every baselined point (anchor AND its handles) through `transform`, in one
    /// write. Unselected points are untouched, so the rest of the path stays anchored.
    private func applyPointTransform(nodeID: UUID, originals: PointBaseline,
                                     _ transform: (CGPoint) -> CGPoint) {
        guard let n = node(nodeID), case .path(var ps) = n.content else { return }
        for (addr, base) in originals {
            ps.mutatePoint(contour: addr.contour, index: addr.index) { pt in
                pt.point = transform(base.point)
                pt.controlIn = base.controlIn.map(transform)
                pt.controlOut = base.controlOut.map(transform)
            }
        }
        var nodes = currentNodes
        guard Self.mutateNested(nodeID, in: &nodes, { $0.content = .path(ps) }) else { return }
        commitNodes(nodes, actionName: gestureUndoName)
    }

    private func nodeLocalToView(_ local: CGPoint, _ node: Node, chain: [Node]) -> CGPoint {
        // Flip first (mirror within the frame about its centre), matching how the
        // renderer applies the flip inside the rotation — so anchors/handles track
        // the flipped shape.
        var lp = local
        if node.flipH { lp.x = node.frame.width - lp.x }
        if node.flipV { lp.y = node.frame.height - lp.y }
        var pl = CGPoint(x: node.frame.minX + lp.x, y: node.frame.minY + lp.y)
        if node.rotation != 0 {
            pl = rotatePoint(pl, around: CGPoint(x: node.frame.midX, y: node.frame.midY), byDegrees: node.rotation)
        }
        return docToViewPoint(parentLocalToDoc(pl, chain: chain))
    }

    /// Inverse: a VIEW point → node-local coordinates (relative to frame origin).
    private func viewToNodeLocal(_ viewPt: CGPoint, _ node: Node, chain: [Node]) -> CGPoint {
        var pl = docToParentLocal(viewToDoc(viewPt), chain: chain)
        if node.rotation != 0 {
            pl = rotatePoint(pl, around: CGPoint(x: node.frame.midX, y: node.frame.midY), byDegrees: -node.rotation)
        }
        var local = CGPoint(x: pl.x - node.frame.minX, y: pl.y - node.frame.minY)
        // Un-flip (mirror is its own inverse) so a dragged point writes back to the
        // correct un-flipped local coordinate.
        if node.flipH { local.x = node.frame.width - local.x }
        if node.flipV { local.y = node.frame.height - local.y }
        return local
    }

    /// The union of a group's leaf descendants' absolute frames (doc coords).
    /// `parentOffset` is the group's own accumulated offset. nil for an empty group.
    private func groupContentBounds(_ node: Node, parentOffset: CGPoint) -> CGRect? {
        let absFrame = node.frame.offsetBy(dx: parentOffset.x, dy: parentOffset.y)
        guard case .group(let kids) = node.content else { return absFrame }
        var union: CGRect?
        for k in kids {
            if let b = groupContentBounds(k, parentOffset: absFrame.origin) {
                union = union?.union(b) ?? b
            }
        }
        return union
    }

    /// The chain of nodes under a document point, outermost (top-level) first to the
    /// deepest leaf, descending only through groups that are hit. Each entry carries
    /// the node id + its document-space offset.
    private func hitPath(atDoc docPoint: CGPoint,
                         includingLocked: Bool = false) -> [(id: UUID, offset: CGPoint)] {
        var path: [(UUID, CGPoint)] = []
        // `point` is the cursor in the CURRENT level's space: each rotated group we
        // descend into inverse-rotates it about that group's center, mirroring how
        // nodeHit/drawNode handle nested rotation — otherwise children of a rotated
        // group are tested at the wrong spot.
        func descend(_ nodes: [Node], _ off: CGPoint, _ point: CGPoint) {
            guard let hit = nodes.last(where: {
                $0.isVisible && (includingLocked || !$0.isLocked)
                    && nodeHit($0, at: point, offset: off)
            })
            else { return }
            path.append((hit.id, off))
            // A locked group is one locked object for canvas interaction. A
            // context-click may target it so it can be unlocked, but must not drill
            // through it and expose a child as though the parent lock did not exist.
            if case .group(let kids) = hit.content, !(includingLocked && hit.isLocked) {
                let frame = hit.frame.offsetBy(dx: off.x, dy: off.y)
                var childPoint = hit.rotation != 0
                    ? rotatePoint(point, around: CGPoint(x: frame.midX, y: frame.midY), byDegrees: -hit.rotation)
                    : point
                // A flipped group mirrors its whole subtree about its center —
                // un-mirror the cursor too, or children get tested (and picked)
                // at their unflipped positions.
                if hit.flipH { childPoint.x = 2 * frame.midX - childPoint.x }
                if hit.flipV { childPoint.y = 2 * frame.midY - childPoint.y }
                descend(kids, CGPoint(x: off.x + hit.frame.minX, y: off.y + hit.frame.minY), childPoint)
            }
        }
        descend(currentNodes, .zero, docPoint)
        return path
    }

    private func updateNode(_ id: UUID, _ change: (inout Node) -> Void) {
        withNodes { nodes in
            _ = Self.mutateNested(id, in: &nodes, change)
            // A committed node change (e.g. text edited → frame grew) must reflow any
            // auto-layout frame that contains it. updateNode is the semantic-change
            // funnel (live drags use withNodes directly and reflow on mouse-up).
            // Document-aware so component instances contribute their RESOLVED
            // size rather than a stale stored frame (BUG-007).
            if let model = document?.model {
                nodes = model.reflowed(nodes)
            } else {
                nodes = AutoLayoutEngine.reflowed(nodes)
            }
        }
    }

    /// FEAT-023 responder-chain route for Edit ▸ Duplicate Effect. The Inspector
    /// records the last edited row in AppState; this action performs the same
    /// adjacent-copy operation as its overflow/context menus in one undo step.
    @objc func duplicateSelectedEffectAction(_ sender: Any?) {
        guard let app, let nodeID = app.singleSelectedNodeID,
              let effectID = app.selectedEffectID else { return }
        var nodes = currentNodes
        var duplicateID: UUID?
        let changed = Self.mutateNested(nodeID, in: &nodes) { node in
            guard let index = node.effects.firstIndex(where: { $0.id == effectID }) else { return }
            var copy = node.effects[index]
            copy.id = UUID()
            node.effects.insert(copy, at: index)
            duplicateID = copy.id
        }
        guard changed, let duplicateID else { return }
        commitNodes(nodes, actionName: "Duplicate Effect")
        app.selectedEffectID = duplicateID
    }

    /// Fast path for live point editing. Moving anchors/handles only changes the
    /// path's local geometry; it does not require re-running auto-layout across the
    /// whole document on every mouse tick. The commit path normalizes/reflows once
    /// on mouse-up through `normalizePath` + undo registration.
    private func updateNodeLive(_ id: UUID, _ change: (inout Node) -> Void) {
        withNodes { nodes in
            _ = Self.mutateNested(id, in: &nodes, change)
        }
    }

    /// Apply `change` to the node with `id` anywhere in the tree (recursing into
    /// groups). Returns true if found.
    @discardableResult
    private static func mutateNested(_ id: UUID, in nodes: inout [Node], _ change: (inout Node) -> Void) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id { change(&nodes[i]); return true }
            if case .group(var kids) = nodes[i].content {
                if mutateNested(id, in: &kids, change) { nodes[i].content = .group(children: kids); return true }
            }
        }
        return false
    }

    /// Mutate the ARRAY (and index) that directly contains `id` — the top-level list
    /// or a group's children. Lets duplicate/reorder act on a node within its own
    /// parent, however deeply nested. Returns true if found.
    @discardableResult
    private static func inParentArray(of id: UUID, in nodes: inout [Node], _ body: (inout [Node], Int) -> Void) -> Bool {
        if let i = nodes.firstIndex(where: { $0.id == id }) { body(&nodes, i); return true }
        for j in nodes.indices {
            if case .group(var kids) = nodes[j].content {
                if inParentArray(of: id, in: &kids, body) { nodes[j].content = .group(children: kids); return true }
            }
        }
        return false
    }

    /// Apply `transform` to EVERY array in the tree (top-level + each group's
    /// children) that contains at least one selected id — so z-order ops reorder
    /// within whichever parent each selection lives in.
    private static func reorderInParents(_ selected: Set<UUID>, in nodes: inout [Node], _ transform: (inout [Node]) -> Void) {
        if nodes.contains(where: { selected.contains($0.id) }) { transform(&nodes) }
        for j in nodes.indices {
            if case .group(var kids) = nodes[j].content {
                reorderInParents(selected, in: &kids, transform)
                nodes[j].content = .group(children: kids)
            }
        }
    }

    /// Remove the nodes with these ids anywhere in the tree (recursing into groups).
    /// Every node id in a subtree, including the root. Used so deleting a group
    /// also clears relationships naming something INSIDE it.
    private static func collectSubtreeIDs(_ node: Node, into ids: inout Set<UUID>) {
        ids.insert(node.id)
        if case .group(let children) = node.content {
            for child in children { collectSubtreeIDs(child, into: &ids) }
        }
    }

    private static func removeNested(_ ids: Set<UUID>, from nodes: inout [Node]) {
        nodes.removeAll { ids.contains($0.id) }
        for i in nodes.indices {
            if case .group(var kids) = nodes[i].content {
                removeNested(ids, from: &kids)
                nodes[i].content = .group(children: kids)
            }
        }
    }

    /// Set a line node from two document-space endpoints: frame becomes the tight
    /// bounding box, endpoints stored relative to it. (Min 1pt so the box has
    /// area and can still be owned/clipped by an artboard.)
    private func setLine(_ id: UUID, aDoc: CGPoint, bDoc: CGPoint) {
        // A nested line's frame lives in its group's local space — convert the
        // doc-space endpoints down through the ancestor chain first.
        let chain = ancestorGroups(of: id)
        let a = chain.isEmpty ? aDoc : docToParentLocal(aDoc, chain: chain)
        let b = chain.isEmpty ? bDoc : docToParentLocal(bDoc, chain: chain)
        updateNode(id) { node in
            guard case .line(var ls) = node.content else { return }
            let minX = min(a.x, b.x), minY = min(a.y, b.y)
            ls.start = CGPoint(x: a.x - minX, y: a.y - minY)
            ls.end   = CGPoint(x: b.x - minX, y: b.y - minY)
            node.frame = CGRect(x: minX, y: minY,
                                width: max(1, abs(b.x - a.x)),
                                height: max(1, abs(b.y - a.y)))
            node.content = .line(ls)
        }
    }

    /// Topmost selectable shape under a view point (skips hidden/locked).
    private func hitTestNode(atViewPoint point: CGPoint) -> Node? {
        let docPoint = viewToDoc(point)
        return currentNodes.last { $0.isVisible && !$0.isLocked && nodeHit($0, at: docPoint) }
    }

    private func hitTestArtboard(atViewPoint point: CGPoint) -> Artboard? {
        guard let document, !isSourceScope else { return nil }   // source scope has no artboards
        let docPoint = viewToDoc(point)
        return currentArtboards.last { $0.frame.contains(docPoint) }
    }

    /// The artboard name label sits just above its frame; dragging it moves the
    /// artboard (and the shapes it owns), keeping empty interior free for marquee.
    private func hitTestArtboardLabel(atViewPoint point: CGPoint) -> Artboard? {
        guard let document, !isSourceScope else { return nil }
        for ab in currentArtboards.reversed() {
            let r = docToView(ab.frame)
            let band = CGRect(x: r.minX, y: r.minY - 22, width: max(r.width, 80), height: 20)
            if band.contains(point) { return ab }
        }
        return nil
    }

    private func handlePoint(_ handle: Handle, in r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:     return CGPoint(x: r.minX, y: r.minY)
        case .top:         return CGPoint(x: r.midX, y: r.minY)
        case .topRight:    return CGPoint(x: r.maxX, y: r.minY)
        case .right:       return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom:      return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft:  return CGPoint(x: r.minX, y: r.maxY)
        case .left:        return CGPoint(x: r.minX, y: r.midY)
        }
    }

    /// A parent-local BOX point (frame corner / edge midpoint) → view space,
    /// through the node's own rotation about its center and every ancestor
    /// group's transform (rotation + flips). docToView is a uniform scale, so
    /// angles and proportions survive. The one mapper the handle chrome, handle
    /// hit-tests, and rotate knob all share — they can't disagree.
    private func boxPointToView(_ p: CGPoint, _ node: Node, chain: [Node]) -> CGPoint {
        let rotated = node.rotation != 0
            ? rotatePoint(p, around: CGPoint(x: node.frame.midX, y: node.frame.midY), byDegrees: node.rotation)
            : p
        return docToViewPoint(parentLocalToDoc(rotated, chain: chain))
    }

    private func hitTestHandle(atViewPoint point: CGPoint) -> Handle? {
        // Groups use the child-aware unified transform box.  Falling through to
        // the node-frame handles would leave a second, invisible resize target
        // whenever rotated children make the visual bounds differ from the raw
        // group frame.
        guard !usesSelectionTransform(),
              let app, let id = app.singleSelectedNodeID,
              let node = node(id), isBoxResizable(node) else { return nil }
        // Handles work under ANY ancestor chain — rotated and/or flipped groups
        // included — because the handle position maps through the full chain and
        // the resize math itself runs in parent-local space (see `.resize`).
        let chain = ancestorGroups(of: id)
        // The same ink box the handles are DRAWN on, so grabbing one is not offset by
        // the stroke width (BUG-036(a)).
        let box = SelectionTransform.outset(node.frame, by: SelectionTransform.inkInsets(of: node))
        for handle in Handle.allCases {
            let c = boxPointToView(handlePoint(handle, in: box), node, chain: chain)
            if CGRect(x: c.x - handleGrab / 2, y: c.y - handleGrab / 2,
                      width: handleGrab, height: handleGrab).contains(point) { return handle }
        }
        return nil
    }

    /// Adobe-style rotate region: just outside each corner, leaving the square
    /// resize handle itself untouched. `corners` are clockwise in view space, so
    /// the two adjacent edge vectors define the outward corner quadrant even for
    /// rotated/flipped nodes.
    private func cornerRotateRegion(at point: CGPoint, corners: [CGPoint]) -> CGPoint? {
        guard corners.count == 4 else { return nil }
        let minDistance = handleGrab * 0.75
        let maxDistance: CGFloat = 30
        for i in corners.indices {
            let corner = corners[i]
            let delta = CGPoint(x: point.x - corner.x, y: point.y - corner.y)
            let distance = hypot(delta.x, delta.y)
            guard distance >= minDistance, distance <= maxDistance else { continue }
            let adjacent = [corners[(i + 3) % 4], corners[(i + 1) % 4]]
            let outsideBothEdges = adjacent.allSatisfy { neighbor in
                let edge = CGPoint(x: neighbor.x - corner.x, y: neighbor.y - corner.y)
                let length = hypot(edge.x, edge.y)
                guard length > 0.001 else { return false }
                return (delta.x * edge.x + delta.y * edge.y) / length < -2
            }
            if outsideBothEdges { return corner }
        }
        return nil
    }

    private func hitTestRotateHandle(atViewPoint point: CGPoint)
        -> (id: UUID, center: CGPoint, corner: CGPoint)? {
        guard !usesSelectionTransform(),
              let app, let id = app.singleSelectedNodeID,
              let node = node(id), isBoxResizable(node) else { return nil }
        let chain = ancestorGroups(of: id)
        let f = SelectionTransform.outset(node.frame, by: SelectionTransform.inkInsets(of: node))
        let corners = [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                       CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)]
            .map { boxPointToView($0, node, chain: chain) }
        guard let corner = cornerRotateRegion(at: point, corners: corners) else { return nil }
        let center = boxPointToView(CGPoint(x: f.midX, y: f.midY), node, chain: chain)
        return (id, center, corner)
    }

    // MARK: Selection transform (multi-select + group resize / rotate)

    /// Selected ids the box transform acts on: any selected node whose ANCESTOR
    /// chain is unrotated (so doc↔parent-local is a pure translation we can invert),
    /// minus any node that has a selected ancestor (it'd be transformed twice via its
    /// parent). Generalizes the old top-level-only unit to nested layers.
    private func selectionTransformIDs() -> [UUID] {
        selectionSpace().nodes.map(\.id)
    }

    /// True if any ancestor group of `id` is itself selected.
    private func hasSelectedAncestor(_ id: UUID) -> Bool {
        guard let app else { return false }
        func walk(_ nodes: [Node], _ selectedAbove: Bool) -> Bool? {
            for n in nodes {
                if n.id == id { return selectedAbove }
                if case .group(let kids) = n.content,
                   let r = walk(kids, selectedAbove || app.selectedNodeIDs.contains(n.id)) { return r }
            }
            return nil
        }
        return walk(currentNodes, false) ?? false
    }

    /// The transform's selected nodes with frames lifted into DOCUMENT space (parent
    /// offset folded in), so union/box/scale/rotate math is uniform across nesting.
    /// The coordinate space the unified selection box operates in, plus the selected
    /// nodes expressed in it (BUG-035).
    ///
    /// Originally this was document space only, which meant the box switched itself
    /// OFF whenever any ancestor was rotated or flipped — a doc-space non-uniform
    /// scale cannot be written back through a rotated ancestor without shearing. The
    /// visible result was a group inside a rotated group, or any multi-selection
    /// inside one, drawing a bare outline with no handles at all.
    ///
    /// The generalisation: find the selected nodes' deepest COMMON ancestor chain and
    /// work in ITS local space, where everything is axis-aligned again. The box is
    /// drawn as a quad mapped through that chain and the resize/rotate math runs in
    /// the same space, so no shear can arise. `SelectionTransform`'s own contract
    /// already anticipates this — "the caller chooses the shared coordinate space
    /// (a group's local space or document space)".
    ///
    /// Collapses to document space (`chain` empty) whenever the common ancestors are
    /// a pure translation, so every case that worked before takes the identical path.
    /// Refuses (returns empty) only when a rotated or flipped group sits BETWEEN the
    /// common space and a selected node — there is no single axis-aligned box that is
    /// honest about that selection.
    private struct SelectionSpace {
        /// Ancestor groups, outermost first. Empty = document space.
        var chain: [Node] = []
        /// Selected nodes with frames lifted into `chain`'s local space.
        var nodes: [Node] = []
        /// Per node: the translation from the space's origin to that node's own
        /// parent origin, so a transformed result can be written back local.
        var offsets: [UUID: CGPoint] = [:]
    }

    private func selectionSpace() -> SelectionSpace {
        guard let app else { return SelectionSpace() }
        return selectionSpace(for: app.selectedNodeIDs)
    }

    private func selectionSpace(for selectedIDs: Set<UUID>) -> SelectionSpace {
        guard !selectedIDs.isEmpty else { return SelectionSpace() }
        // Each selected node with its ancestor chain, skipping any node that has a
        // selected ancestor — it would otherwise be transformed twice, once through
        // its parent and once on its own.
        var picked: [(node: Node, chain: [Node])] = []
        // One mutable stack rather than `stack + [node]` per group: this runs on every
        // mouse-move through the hit-tests, and the chain is only copied for the few
        // nodes that are actually selected.
        var stack: [Node] = []
        func walk(_ nodes: [Node], _ selectedAbove: Bool) {
            for node in nodes {
                let selected = selectedIDs.contains(node.id)
                if selected, !selectedAbove { picked.append((node, stack)) }
                if case .group(let kids) = node.content {
                    stack.append(node)
                    walk(kids, selectedAbove || selected)
                    stack.removeLast()
                }
            }
        }
        walk(currentNodes, false)
        guard !picked.isEmpty else { return SelectionSpace() }

        // Deepest ancestor chain every selected node shares.
        var common = picked[0].chain
        for item in picked.dropFirst() {
            var i = 0
            while i < common.count, i < item.chain.count, common[i].id == item.chain[i].id { i += 1 }
            common = Array(common.prefix(i))
        }
        // Anything transformed BELOW that space breaks the axis-aligned promise.
        for item in picked {
            for group in item.chain.dropFirst(common.count)
            where group.rotation != 0 || group.flipH || group.flipV {
                return SelectionSpace()
            }
        }
        // If the shared ancestors are a pure translation, document space describes the
        // selection just as well — take the original path so nothing that works today
        // changes behaviour.
        let translationOnly = common.allSatisfy { $0.rotation == 0 && !$0.flipH && !$0.flipV }
        let chain = translationOnly ? [] : common
        let skip = translationOnly ? 0 : common.count

        var space = SelectionSpace(chain: chain)
        for item in picked {
            var offset = CGPoint.zero
            for group in item.chain.dropFirst(skip) {
                offset.x += group.frame.minX
                offset.y += group.frame.minY
            }
            var lifted = item.node
            lifted.frame = item.node.frame.offsetBy(dx: offset.x, dy: offset.y)
            space.nodes.append(lifted)
            space.offsets[item.node.id] = offset
        }
        return space
    }

    /// A point in the selection space, in VIEW coordinates.
    private func selectionSpaceToView(_ p: CGPoint, chain: [Node]) -> CGPoint {
        chain.isEmpty ? docToViewPoint(p) : docToViewPoint(parentLocalToDoc(p, chain: chain))
    }

    /// A view point back in the selection space.
    private func viewToSelectionSpace(_ p: CGPoint, chain: [Node]) -> CGPoint {
        chain.isEmpty ? viewToDoc(p) : docToParentLocal(viewToDoc(p), chain: chain)
    }

    /// The selection box's four corners in view space, clockwise from top-left of the
    /// space-local rect (so a rotated space yields a rotated quad).
    private func selectionBoxCorners(_ bounds: CGRect, chain: [Node]) -> [CGPoint] {
        [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
         CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY)]
            .map { selectionSpaceToView($0, chain: chain) }
    }

    /// Pointer angle measured IN the selection space, so a rotated or flipped
    /// ancestor cannot invert the direction the selection turns.
    private func selectionSpaceAngle(ofViewPoint p: CGPoint, aroundLocal c: CGPoint,
                                     chain: [Node]) -> Double {
        let b = viewToSelectionSpace(p, chain: chain)
        var deg = atan2(Double(b.x - c.x), Double(-(b.y - c.y))) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    /// Whether the unified selection box (8 handles + rotate knob) is in play:
    /// more than one node selected, or a single GROUP (which needs child-aware
    /// resize). A lone non-group node keeps the existing single-node handles.
    private func usesSelectionTransform() -> Bool {
        usesSelectionTransform(selectionSpace().nodes)
    }

    private func usesSelectionTransform(_ nodes: [Node]) -> Bool {
        if nodes.count > 1 { return true }
        if nodes.count == 1, case .group = nodes[0].content { return true }
        return false
    }

    /// The unified selection box in its SELECTION SPACE: the INK rect that gets
    /// drawn and hit-tested (BUG-036(a) — it encloses outside and centre strokes, so
    /// the visible edge of the art is never outside the box that claims to bound it),
    /// plus the constant insets back to the GEOMETRY bounds the model, align and
    /// export keep using.
    private func selectionLocalBox(_ space: SelectionSpace)
        -> (ink: CGRect, insets: SelectionTransform.InkInsets)? {
        guard let geometry = SelectionTransform.unionBounds(space.nodes),
              let ink = SelectionTransform.unionPaintedBounds(space.nodes) else { return nil }
        return (ink, SelectionTransform.inkInsets(geometry: geometry, ink: ink))
    }

    private func hitTestSelectionHandle(atViewPoint point: CGPoint) -> Handle? {
        let space = selectionSpace()
        guard usesSelectionTransform(space.nodes),
              let bounds = selectionLocalBox(space)?.ink else { return nil }
        // Handle positions are computed in the SELECTION SPACE and mapped to view,
        // exactly like the drawing does — so a rotated space's handles are hit where
        // they are actually drawn rather than at some phantom axis-aligned rect.
        for handle in Handle.allCases {
            let c = selectionSpaceToView(handlePoint(handle, in: bounds), chain: space.chain)
            if CGRect(x: c.x - handleGrab / 2, y: c.y - handleGrab / 2,
                      width: handleGrab, height: handleGrab).contains(point) { return handle }
        }
        return nil
    }

    /// Rotation pivot + hovered view-space corner when the pointer is just outside
    /// a selection-box corner. The corner chooses the inward-facing authored cursor.
    private func hitTestSelectionRotate(atViewPoint point: CGPoint)
        -> (pivot: CGPoint, center: CGPoint, corner: CGPoint)? {
        let space = selectionSpace()
        guard usesSelectionTransform(space.nodes),
              let bounds = selectionLocalBox(space)?.ink else { return nil }
        let corners = selectionBoxCorners(bounds, chain: space.chain)
        guard let corner = cornerRotateRegion(at: point, corners: corners) else { return nil }
        let centerLocal = CGPoint(x: bounds.midX, y: bounds.midY)
        return (centerLocal, selectionSpaceToView(centerLocal, chain: space.chain), corner)
    }

    /// Pointer angle in the selected node's parent coordinate space. Mapping both
    /// center and pointer through the ancestor chain preserves flipped handedness.
    private func nodeRotationAngle(atViewPoint p: CGPoint, id: UUID, centerView: CGPoint) -> Double {
        let chain = ancestorGroups(of: id)
        let a = docToParentLocal(viewToDoc(centerView), chain: chain)
        let b = docToParentLocal(viewToDoc(p), chain: chain)
        var deg = atan2(Double(b.x - a.x), Double(-(b.y - a.y))) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    /// Snapshot the selected nodes IN THE SELECTION SPACE for a stable transform
    /// baseline, remembering each one's offset within that space so the result can be
    /// written back parent-local. Also captures the space's chain for the gesture.
    private func snapshotSelectionBaseline() {
        let space = selectionSpace()
        var snap: [UUID: Node] = [:]
        for n in space.nodes { snap[n.id] = n }   // frames already lifted into the space
        selectionDragBaseline = snap
        selectionDragOffsets = space.offsets
        selectionDragChain = space.chain
    }

    /// The point a resize handle keeps fixed (opposite corner / edge midpoint).
    private static func anchorPoint(_ handle: Handle, in r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:     return CGPoint(x: r.maxX, y: r.maxY)
        case .topRight:    return CGPoint(x: r.minX, y: r.maxY)
        case .bottomLeft:  return CGPoint(x: r.maxX, y: r.minY)
        case .bottomRight: return CGPoint(x: r.minX, y: r.minY)
        case .left:        return CGPoint(x: r.maxX, y: r.midY)
        case .right:       return CGPoint(x: r.minX, y: r.midY)
        case .top:         return CGPoint(x: r.midX, y: r.maxY)
        case .bottom:      return CGPoint(x: r.midX, y: r.minY)
        }
    }

    /// A resize handle on the lone selected artboard (only when no shapes are
    /// selected — resizing is single-board).
    private func soleSelectedArtboard() -> Artboard? {
        guard let app, let document, !isSourceScope,
              app.selectedNodeIDs.isEmpty, app.selectedArtboardIDs.count == 1,
              let id = app.selectedArtboardIDs.first else { return nil }
        return currentArtboards.first { $0.id == id }
    }

    /// The topmost selected artboard whose frame contains the document point.
    private func selectedBoardContaining(_ docPoint: CGPoint) -> Artboard? {
        guard let app, let document, !isSourceScope else { return nil }
        return currentArtboards.last {
            app.selectedArtboardIDs.contains($0.id) && $0.frame.contains(docPoint)
        }
    }

    private func hitTestArtboardHandle(atViewPoint point: CGPoint, board: Artboard) -> Handle? {
        let viewRect = docToView(board.frame)
        for handle in Handle.allCases {
            let c = handlePoint(handle, in: viewRect)
            if CGRect(x: c.x - handleGrab / 2, y: c.y - handleGrab / 2,
                      width: handleGrab, height: handleGrab).contains(point) { return handle }
        }
        return nil
    }

    /// A handle on the component source's viewBox (source editor only).
    private func hitTestSourceHandle(atViewPoint point: CGPoint) -> Handle? {
        guard isSourceScope, let rect = sourceBoundsRect() else { return nil }
        let viewRect = docToView(rect)
        for handle in Handle.allCases {
            let c = handlePoint(handle, in: viewRect)
            if CGRect(x: c.x - handleGrab / 2, y: c.y - handleGrab / 2,
                      width: handleGrab, height: handleGrab).contains(point) { return handle }
        }
        return nil
    }

    /// Document-space origins of the given artboards (for a group move).
    private func artboardOrigins(_ ids: [UUID]) -> [UUID: CGPoint] {
        guard let document else { return [:] }
        var result: [UUID: CGPoint] = [:]
        for ab in currentArtboards where ids.contains(ab.id) {
            result[ab.id] = ab.frame.origin
        }
        return result
    }

    /// Origins of every shape owned by any of the given artboards (so a group
    /// move/duplicate carries all their contents).
    private func ownedNodeOrigins(forBoards ids: [UUID]) -> [UUID: CGPoint] {
        guard let document else { return [:] }
        let idSet = Set(ids)
        var result: [UUID: CGPoint] = [:]
        for node in currentNodes {
            if let owner = owningArtboard(of: node)?.id, idSet.contains(owner) {
                result[node.id] = node.frame.origin
            }
        }
        return result
    }

    private func ownedNodeOrigins(artboardID: UUID) -> [UUID: CGPoint] {
        guard let document else { return [:] }
        var result: [UUID: CGPoint] = [:]
        for node in currentNodes {
            if owningArtboard(of: node)?.id == artboardID {
                result[node.id] = node.frame.origin
            }
        }
        return result
    }

    // MARK: Drawing

    /// Core Image context for background-blur compositing (created once).
    private lazy var ciContext = CIContext(options: nil)

    /// True if any node (recursing groups) has an enabled background-blur effect —
    /// the only case that needs the offscreen render pass.
    /// Background-blur effect is DISABLED pending a performance rewrite. It forced
    /// the ENTIRE scene through an offscreen bitmap + `makeImage()` every frame (plus
    /// a per-node Core Image gaussian), which on large docs produced multi-second
    /// frames and "Surface too large" failures at high zoom. Drop / inner shadows are
    /// unaffected. Flip this back to `true` once the blur path is reworked (see
    /// ROADMAP). The UI to ADD a background blur was also removed; any blur effect
    /// already saved in a file simply doesn't render.
    static let backgroundBlurEnabled = false

    private var documentHasBackgroundBlur: Bool {
        guard Self.backgroundBlurEnabled else { return false }
        func scan(_ nodes: [Node]) -> Bool {
            for n in nodes {
                if n.effects.contains(where: { $0.isEnabled && $0.kind == .backgroundBlur }) { return true }
                if case .group(let k) = n.content, scan(k) { return true }
            }
            return false
        }
        return scan(currentNodes)
    }

    // Reused offscreen backing for the background-blur pass — allocating a
    // multi-megabyte bitmap every frame is what makes pan/zoom choppy, so we keep
    // one and only rebuild it when the pixel size changes.
    private var blurBacking: CGContext?
    private var blurBackingPx: (w: Int, h: Int) = (0, 0)

    // Live backdrop blur is the expensive part of a frame (full-scene readback +
    // Core Image). During an active pan/zoom we skip it and draw the cheap direct
    // path, then do one high-quality blurred pass ~120ms after motion settles —
    // the standard "blur catches up" behavior.
    private var blurSuppressed = false
    private var blurSettleTimer: Timer?
    private func suppressBlurDuringInteraction() {
        guard documentHasBackgroundBlur else { return }
        blurSuppressed = true
        blurSettleTimer?.invalidate()
        blurSettleTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.blurSuppressed = false
            self.needsDisplay = true
        }
    }

    // MARK: Pan/zoom bitmap blit
    //
    // During a live pan/zoom gesture the scene doesn't change — only the view
    // transform does. Re-rendering every visible node per tick is what made
    // heavy documents feel klunky. Instead: on the FIRST tick of a gesture we
    // render the scene once into a bitmap, then every subsequent tick just
    // blits that bitmap translated/scaled (near-zero cost). ~120ms after the
    // last tick a full-quality vector render "settles" back in — the same
    // catch-up pattern the background-blur path uses. Rulers are excluded from
    // the snapshot and drawn live on top so they never smear.
    private var panZoomSnapshot: CGImage?
    private var panZoomSnapshotZoom: CGFloat = 1
    private var panZoomSnapshotPan: CGPoint = .zero
    private var panZoomSnapshotSize: CGSize = .zero     // snapshot region size (points)
    private var panZoomSnapshotOrigin: CGPoint = .zero  // region origin in capture view space
    /// Snapshot halo: capture this fraction of the viewport EXTRA on every side,
    /// so panning reveals real pre-rendered content instead of blank background.
    /// User-tunable via Settings ▸ Canvas ▸ Performance (speed 0.15 / balanced
    /// 0.25 / detail 0.40 — bigger halo, fewer blank-edge recaptures).
    private var blitHaloFraction: CGFloat { app?.performanceMode.panHaloFraction ?? 0.25 }
    private var panZoomBlitActive = false
    private var panZoomSettleTimer: Timer?
    /// Safety valve: if a capture ever blows the budget (below), stop trying for
    /// the rest of the run — a laggy-but-live gesture beats a beach ball.
    private var panZoomBlitDisabled = false
    // 0.4s: the halo makes captures ~2.25× a plain frame, and first-appearance
    // image mip decodes can spike one capture; the valve is for pathology only.
    private static let blitCaptureBudget: CFAbsoluteTime = 0.4   // seconds
    /// Two-strike valve: ONE slow capture is usually cold caches (measured:
    /// 500ms at launch, ~40ms warm on the same doc) and shouldn't bench the
    /// blit for the whole run. A capture under budget clears the strike; two
    /// consecutive slow ones mean the document really can't afford captures.
    private var panZoomCaptureStrikes = 0
    /// PERF-TODO T1: the pan/zoom sensitivity check can walk the whole visible
    /// scene and resolve component instances. Cache only the "no sensitive
    /// content exists anywhere in this scope" result; when sensitive content does
    /// exist, keep the existing precise viewport check so blit on/off decisions
    /// stay identical as the camera pans.
    private var panZoomAllClearCache: (generation: Int, isAllClear: Bool)?

    /// Call at every pan/zoom tick, BEFORE mutating `app.zoom`/`app.panOffset`,
    /// so a first-tick capture renders exactly what's already on screen.
    private func beginPanZoomInteraction() {
        guard let app, !panZoomBlitDisabled else { return }
        if panZoomSensitivityCached() {
            // Gradients and shadows currently shift when flattened into the
            // temporary gesture bitmap, even though their live vector render is
            // stable. Favor fidelity for those documents and render live per tick.
            panZoomBlitActive = false
            panZoomSnapshot = nil
            panZoomSettleTimer?.invalidate()
            return
        }
        // Recapture when zoom has drifted far enough from the snapshot that the
        // scaled blit would look too soft (zooming in) or wastefully large —
        // OR when the pan has consumed the halo, so real content replaces what
        // would otherwise show as blank background ("minor freakouts").
        if panZoomSnapshot != nil {
            let k = app.zoom / panZoomSnapshotZoom
            if k > 1.75 || k < 0.6 {
                panZoomSnapshot = nil
            } else {
                // Doc-space containment: the snapshot region must still cover the
                // current viewport, with a margin so we recapture a tick early
                // (this runs BEFORE the incoming pan delta is applied).
                let snapDoc = CGRect(
                    x: (panZoomSnapshotOrigin.x - panZoomSnapshotPan.x) / panZoomSnapshotZoom,
                    y: (panZoomSnapshotOrigin.y - panZoomSnapshotPan.y) / panZoomSnapshotZoom,
                    width: panZoomSnapshotSize.width / panZoomSnapshotZoom,
                    height: panZoomSnapshotSize.height / panZoomSnapshotZoom)
                let nowDoc = CGRect(
                    x: (bounds.minX - app.panOffset.x) / app.zoom,
                    y: (bounds.minY - app.panOffset.y) / app.zoom,
                    width: bounds.width / app.zoom,
                    height: bounds.height / app.zoom)
                let margin = 48 / app.zoom   // covers a fast tick's delta
                if !snapDoc.insetBy(dx: margin, dy: margin).contains(nowDoc) {
                    panZoomSnapshot = nil
                }
            }
        }
        if panZoomSnapshot == nil { capturePanZoomSnapshot() }
        panZoomBlitActive = panZoomSnapshot != nil
        panZoomSettleTimer?.invalidate()
        // .common run-loop mode so the settle fires even while events stream in.
        // Delay is user-tuned (Settings ▸ Canvas ▸ Performance): with the halo
        // covering slow pans, the settle only restores what's beyond it.
        let timer = Timer(timeInterval: app.performanceMode.settleDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.panZoomBlitActive = false
            self.panZoomSnapshot = nil        // next gesture recaptures fresh
            self.needsDisplay = true          // full-quality settle render
        }
        RunLoop.main.add(timer, forMode: .common)
        panZoomSettleTimer = timer
    }

    private func panZoomSensitivityCached() -> Bool {
        guard let document else { return false }
        let gen = document.resolveGeneration
        if let cached = panZoomAllClearCache, cached.generation == gen {
            if cached.isAllClear { return false }
        } else {
            let isAllClear = !scopeHasBitmapSensitiveContent(model: document.model)
            panZoomAllClearCache = (gen, isAllClear)
            if isAllClear { return false }
        }
        return visibleBitmapSensitiveContent(in: bounds)
    }

    private func scopeHasBitmapSensitiveContent(model: Document) -> Bool {
        if !isSourceScope, currentArtboards.contains(where: { $0.background.isGradient }) {
            return true
        }
        return currentNodes.contains { $0.isVisible && nodeHasBitmapSensitiveContent($0, model: model) }
    }

    // Capture instrumentation (Testing Mode): the capture render has repeatedly
    // been ~60× slower than the identical on-screen render, and two root-cause
    // theories (pixel format, unclipped shadow layers) each explained only part
    // of it. These buckets say where the offscreen milliseconds ACTUALLY go, so
    // the next fix targets the measured hotspot instead of a hypothesis.
    private var capturingSnapshot = false
    private var currentRenderRegion: CGRect?
    private var capShadowMs = 0.0, capImageMs = 0.0, capTextMs = 0.0
    private var capShapeMs = 0.0, capBoardMs = 0.0, capLayerMs = 0.0

    private func withCanvasAppearance<T>(_ body: () -> T) -> T {
        let prior = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        defer { NSAppearance.current = prior }
        return body()
    }

    /// One full scene render (no rulers) into the reusable offscreen backing,
    /// kept as a CGImage together with the transform it was rendered at.
    private func capturePanZoomSnapshot() {
        // Capture the viewport plus a halo on every side (see blitHaloFraction),
        // so slow pans reveal pre-rendered content, not blank background.
        // AFTER A STRIKE, retry WITHOUT the halo: slow captures are usually the
        // halo reaching into never-yet-rendered territory (cold text layouts +
        // image decodes for content that's never been on screen) — a
        // viewport-only capture costs ≈ one frame and keeps the blit alive.
        let fraction = panZoomCaptureStrikes == 0 ? blitHaloFraction : 0
        let halo = CGSize(width: bounds.width * fraction,
                          height: bounds.height * fraction)
        let region = bounds.insetBy(dx: -halo.width, dy: -halo.height)
        guard let app, let cg = offscreenBacking(sizePt: region.size, colorSpace: .documentSRGB) else { return }
        let t0 = CFAbsoluteTimeGetCurrent()   // always timed — feeds the safety valve
        let scale = backingScale
        cg.saveGState()
        cg.clear(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        cg.translateBy(x: 0, y: CGFloat(cg.height))
        cg.scaleBy(x: scale, y: -scale)
        cg.translateBy(x: -region.minX, y: -region.minY)   // region origin → bitmap origin
        let nsctx = NSGraphicsContext(cgContext: cg, flipped: true)
        capturingSnapshot = true
        capShadowMs = 0; capImageMs = 0; capTextMs = 0
        capShapeMs = 0; capBoardMs = 0; capLayerMs = 0
        let tRender = CFAbsoluteTimeGetCurrent()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsctx
        withCanvasAppearance {
            renderCanvas(into: cg, includeRulers: false, viewport: region)
        }
        NSGraphicsContext.restoreGraphicsState()
        let renderMs = (CFAbsoluteTimeGetCurrent() - tRender) * 1000
        capturingSnapshot = false
        cg.restoreGState()
        let tImage = CFAbsoluteTimeGetCurrent()
        panZoomSnapshot = cg.makeImage()
        panZoomSnapshotZoom = app.zoom
        panZoomSnapshotPan = app.panOffset
        panZoomSnapshotSize = region.size
        panZoomSnapshotOrigin = region.origin
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        if perf.enabled {
            perf.record("blit-capture", ms: elapsed * 1000)
            perf.record("blit-render", ms: renderMs)
            perf.record("blit-makeImage", ms: (CFAbsoluteTimeGetCurrent() - tImage) * 1000)
            perf.record("blit-shadows", ms: capShadowMs)
            perf.record("blit-images", ms: capImageMs)
            perf.record("blit-text", ms: capTextMs)
            perf.record("blit-shapes", ms: capShapeMs)
            perf.record("blit-boards", ms: capBoardMs)
            perf.record("blit-layers", ms: capLayerMs)   // opacity/blend transparency layers
        }
        if elapsed > Self.blitCaptureBudget {
            panZoomCaptureStrikes += 1
            if panZoomCaptureStrikes >= 2 {
                // Two consecutive slow captures — the document genuinely can't
                // afford them. Use this snapshot for the current gesture, then
                // fall back to live rendering for the rest of the run.
                panZoomBlitDisabled = true
                NSLog("⏱ [EXP perf] blit-capture took %.0fms (> %.0fms budget, 2nd strike) — pan/zoom blit disabled for this run",
                      elapsed * 1000, Self.blitCaptureBudget * 1000)
                DiagnosticLog.shared.log(String(format: "blit-capture %.0fms > %.0fms budget (2nd strike) — pan/zoom blit disabled for this run", elapsed * 1000, Self.blitCaptureBudget * 1000))
            } else {
                NSLog("⏱ [EXP perf] blit-capture took %.0fms (> %.0fms budget) — likely cold caches, will retry next gesture",
                      elapsed * 1000, Self.blitCaptureBudget * 1000)
                DiagnosticLog.shared.log(String(format: "blit-capture %.0fms > %.0fms budget — likely cold caches, will retry next gesture", elapsed * 1000, Self.blitCaptureBudget * 1000))
            }
        } else {
            panZoomCaptureStrikes = 0
        }
    }

    /// Draw the cached gesture snapshot under the current pan/zoom. Pure blit —
    /// the win over a full vector render. Returns false if there's nothing valid
    /// to blit (caller falls through to the normal render).
    private func drawPanZoomBlit(into ctx: CGContext) -> Bool {
        guard let app, panZoomBlitActive, let snap = panZoomSnapshot,
              panZoomSnapshotSize.width > 0 else { return false }
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        let k = app.zoom / panZoomSnapshotZoom
        // A snapshot pixel at capture-view point v maps to k·v + (pan1 − k·pan0);
        // the bitmap starts at the region's (halo-shifted) origin, hence the k·origin term.
        let origin = CGPoint(
            x: app.panOffset.x - panZoomSnapshotPan.x * k + panZoomSnapshotOrigin.x * k,
            y: app.panOffset.y - panZoomSnapshotPan.y * k + panZoomSnapshotOrigin.y * k)
        let size = CGSize(width: panZoomSnapshotSize.width * k,
                          height: panZoomSnapshotSize.height * k)
        ctx.saveGState()
        ctx.interpolationQuality = .low   // speed over polish mid-gesture
        // Flipped view ↔ y-up CGImage: flip within the target rect (image idiom).
        ctx.translateBy(x: origin.x, y: origin.y + size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(snap, in: CGRect(origin: .zero, size: size))
        ctx.restoreGState()
        // Rulers are excluded from the snapshot; draw them live so they stay put.
        if app.showRulers && !isSourceScope { drawRulers(in: ctx) }
        return true
    }

    // MARK: Drag-overlay blit
    //
    // Node drags used to re-render the whole scene every mouse tick (35–60ms,
    // ~20fps — the "moving things feels laggy" complaint). During a drag the
    // STATIC content doesn't change, so: capture it once into two bitmaps split
    // at the dragged nodes' z-position — BELOW (background + boards + nodes
    // under the dragged ones) and ABOVE (transparent; nodes over them + grids +
    // guides) — then each tick blit BELOW, draw only the dragged nodes live,
    // blit ABOVE, and draw chrome. Z-order stays truthful. Capture costs ≈ two
    // frames, once per gesture (cheap since the transparency-layer clip fixes).
    //
    // Known mid-gesture approximations (settle restores exactness at mouseUp):
    // static nodes with blend modes in the ABOVE layer composite as normal-over
    // (they were rendered against transparency), and static content BETWEEN two
    // dragged nodes' z-positions lumps into ABOVE.
    private var dragBlitBelow: CGImage?
    private var dragBlitAbove: CGImage?
    private var dragBlitZoom: CGFloat = 1
    private var dragBlitPan: CGPoint = .zero
    private var dragBlitSize: CGSize = .zero
    private var dragBlitSkipIDs: Set<UUID> = []   // TOP-LEVEL ancestors of the dragged ids
    private var dragBlitUnsupported = false       // set when capture can't represent this gesture
    // PERF-002 conditional fidelity (see drawDragBlit): decided once per gesture.
    private var dragFidelityChecked = false
    private var dragWantsTrueComposite = false
    /// Frames drawn so far in the current drag. The first couple render LIVE
    /// before the snapshot capture: a big edit right before a drag (duplicate,
    /// paste) empties the text/image caches, and a cold capture measured ~284ms
    /// (a felt beachball) versus ~2 frames warm. Two live 10–20ms ticks warm
    /// the caches AND spare tiny nudge-drags from ever paying for a capture.
    private var dragBlitTicks = 0

    /// Should this drag keep TRUE live compositing? Yes when the user's
    /// performance mode grants a budget, the recent full-frame cost fits it,
    /// and the moving content actually uses a non-normal blend mode (plain
    /// content composites correctly on the fast path anyway, so fidelity
    /// spend would buy nothing).
    private func shouldTrueCompositeDrag(_ ids: Set<UUID>) -> Bool {
        guard let app else { return false }
        let budget = app.performanceMode.trueDragBudgetMs
        guard budget > 0 else { return false }                      // Speed focus
        guard fullFrameEMA > 0, fullFrameEMA < budget else { return false }
        func hasBlend(_ n: Node) -> Bool {
            if n.blendMode != .normal { return true }
            if case .group(let children) = n.content {
                return children.contains(where: hasBlend)
            }
            return false
        }
        return ids.contains { id in node(id).map(hasBlend) ?? false }
    }

    /// The node ids a drag gesture is actively mutating, or nil when the drag
    /// kind isn't node-shaped (marquee, hand, artboards, guides…).
    private func activeDragNodeIDs() -> Set<UUID>? {
        switch dragMode {
        case .nodes(_, let origins):            return Set(origins.keys)
        case .resize(let id, _, _):             return [id]
        case .rotate(let id, _, _, _):          return [id]
        case .resizeSelection, .rotateSelection: return Set(selectionDragBaseline.keys)
        case .draw(let id, _):                  return [id]
        case .drawArtboard:                     return []   // a board is not a node
        case .drawLine(let id, _):              return [id]
        case .lineEndpoint(let id, _, _):       return [id]
        case .penHandle(let nodeID, _):         return [nodeID]
        case .pathPoint(let nodeID, _):         return [nodeID]
        case .pathPointGroup(let nodeID, _, _): return [nodeID]
        default:                                return nil
        }
    }

    /// The top-level node whose subtree contains `id` (or `id` itself).
    /// Dragged nodes can be nested; snapshots exclude whole TOP-LEVEL subtrees,
    /// and the containing subtree is redrawn live so siblings stay correct.
    private func topLevelAncestorID(of id: UUID) -> UUID? {
        guard let document else { return nil }
        func contains(_ node: Node, _ target: UUID) -> Bool {
            if node.id == target { return true }
            if case .group(let children) = node.content {
                return children.contains { contains($0, target) }
            }
            return false
        }
        return currentNodes.first { contains($0, id) }?.id
    }

    /// Render the two static layers for the current drag. Returns false when the
    /// gesture can't be represented (no top-level ancestor, source scope, …).
    private func captureDragSnapshots() -> Bool {
        guard let app, let document, !isSourceScope,
              let ids = activeDragNodeIDs(), !ids.isEmpty,
              // documentSRGB: same fidelity rule as the pan/zoom snapshot -- EXP
              // fills/gradients are authored in sRGB, so the static layers render
              // in document space and match the settled vector frame (minimizes
              // any visible pop when tick 3 swaps from live render to blit).
              let cg = offscreenBacking(colorSpace: .documentSRGB) else { return false }
        var skip: Set<UUID> = []
        for id in ids {
            guard let top = topLevelAncestorID(of: id) else { return false }
            skip.insert(top)
        }
        let nodes = currentNodes
        guard let split = nodes.firstIndex(where: { skip.contains($0.id) }) else { return false }
        let t0 = CFAbsoluteTimeGetCurrent()
        let scale = backingScale
        let visible = bounds

        func renderLayer(_ body: (CGContext) -> Void) -> CGImage? {
            cg.saveGState()
            cg.clear(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            cg.translateBy(x: 0, y: CGFloat(cg.height))
            cg.scaleBy(x: scale, y: -scale)
            let nsctx = NSGraphicsContext(cgContext: cg, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsctx
            withCanvasAppearance {
                body(cg)
            }
            NSGraphicsContext.restoreGraphicsState()
            cg.restoreGState()
            return cg.makeImage()
        }

        // BELOW: opaque base — background, boards, nodes under the dragged ones.
        dragBlitBelow = renderLayer { ctx in
            NSColor.underPageBackgroundColor.setFill()
            bounds.fill()
            for artboard in currentArtboards {
                guard docToView(artboard.frame).insetBy(dx: -24, dy: -24).intersects(visible)
                else { continue }
                drawArtboardBackground(artboard, in: ctx)
            }
            for node in nodes[..<split]
            where node.isVisible && node.id != editingNodeID && !skip.contains(node.id) {
                drawCulledTopLevelNode(node, visible: visible, in: ctx)
            }
        }
        // ABOVE: transparent overlay — nodes over the dragged ones, then grids
        // and static guides (they draw over content in the normal path too).
        dragBlitAbove = renderLayer { ctx in
            ctx.clear(bounds)
            for node in nodes[split...]
            where node.isVisible && node.id != editingNodeID && !skip.contains(node.id) {
                drawCulledTopLevelNode(node, visible: visible, in: ctx)
            }
            drawLayoutGrids(in: ctx)
            if app.showGrid { drawUniformGrid(in: ctx) }
            if app.showGuides { drawGuides(in: ctx) }
        }
        guard dragBlitBelow != nil, dragBlitAbove != nil else {
            dragBlitBelow = nil; dragBlitAbove = nil
            return false
        }
        dragBlitZoom = app.zoom
        dragBlitPan = app.panOffset
        dragBlitSize = bounds.size
        dragBlitSkipIDs = skip
        if perf.enabled { perf.record("dragblit-capture", ms: (CFAbsoluteTimeGetCurrent() - t0) * 1000) }
        return true
    }

    /// The per-tick drag frame: blit BELOW, draw the dragged subtrees live (in
    /// z order, with the standard clips), blit ABOVE, then live chrome. Returns
    /// false to fall through to the normal full render.
    private func drawDragBlit(into ctx: CGContext) -> Bool {
        guard let app, let document, !isSourceScope,
              let ids = activeDragNodeIDs(), !ids.isEmpty else {
            // Not in a node drag: drop any leftover snapshot, re-arm for next time.
            if dragBlitBelow != nil { dragBlitBelow = nil; dragBlitAbove = nil; dragBlitSkipIDs = [] }
            dragBlitUnsupported = false
            dragFidelityChecked = false
            dragBlitTicks = 0
            return false
        }
        guard !dragBlitUnsupported else { return false }
        // PERF-002 — conditional fidelity, decided ONCE per gesture: when the
        // moving content carries blend modes (difference/overlay/…) it flattens
        // against the ABOVE snapshot layer mid-drag. If the user's performance
        // mode allows it and the document is currently cheap enough to render
        // live, keep TRUE compositing for this whole gesture instead of the
        // fast snapshot path.
        if !dragFidelityChecked {
            dragFidelityChecked = true
            // Blend modes still get TRUE compositing (budget-gated below); static
            // gradients/shadows do NOT force live rendering here. Unlike the
            // pan/zoom blit, the drag snapshots are drawn 1:1 with the view
            // transform pinned for the whole gesture (any zoom/pan/resize change
            // recaptures or bails), so flattened static pixels cannot shift the
            // way a scaled pan/zoom bitmap can. 2026-07-14: this decision
            // previously also OR'd visibleBitmapSensitiveContent(in: bounds, ...),
            // which forced FULL LIVE renders every tick (17-33ms measured on a
            // 233-node doc) for every node/anchor/handle drag whenever ANY
            // shadow or gradient was visible -- the "hit or miss" point-drag lag.
            dragWantsTrueComposite = shouldTrueCompositeDrag(ids)
        }
        if dragWantsTrueComposite { return false }   // full live render per tick
        // Warm-up: first two ticks render live (see dragBlitTicks).
        dragBlitTicks += 1
        if dragBlitTicks <= 2 { return false }
        // (Re)capture when this is the first tick or the view transform moved
        // (scroll-during-drag, window resize) — static pixels are transform-bound.
        if dragBlitBelow == nil || app.zoom != dragBlitZoom
            || app.panOffset != dragBlitPan || bounds.size != dragBlitSize {
            guard captureDragSnapshots() else {
                dragBlitUnsupported = true   // fall back to live rendering this gesture
                return false
            }
        }
        guard let below = dragBlitBelow else { return false }

        func blit(_ img: CGImage) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(origin: .zero, size: bounds.size))
            ctx.restoreGState()
        }
        blit(below)
        for node in currentNodes
        where dragBlitSkipIDs.contains(node.id) && node.isVisible && node.id != editingNodeID {
            drawCulledTopLevelNode(node, visible: bounds, in: ctx)
        }
        if let above = dragBlitAbove { blit(above) }
        // Live chrome — everything that moves with the gesture.
        drawSmartGuides(in: ctx)
        drawSelectionChrome(in: ctx)
        if optionHeld { drawMeasurements(in: ctx) }
        if app.showRulers && !isSourceScope { drawRulers(in: ctx) }
        return true
    }

    /// A flipped (top-left origin, y-down) offscreen CGContext that matches the
    /// view's coordinate system 1:1, so renderCanvas — including NSString text,
    /// which honors `isFlipped` — draws identically to on-screen. Cached/reused.
    private enum OffscreenColorSpace {
        case window
        case documentSRGB

        var cgColorSpace: CGColorSpace? {
            switch self {
            case .window:
                // Match the WINDOW's colorspace (usually Display P3 on modern Macs):
                // this remains useful for image-heavy and backdrop-style offscreen
                // passes that want to mirror the window target directly.
                return nil
            case .documentSRGB:
                // EXP-authored fills/gradients are stored as straight sRGB numbers.
                // Pan/zoom snapshots are temporary stand-ins for those vectors, so
                // render that bitmap in document color space before it is drawn into
                // the window. This avoids a mid-gesture color-managed bitmap path
                // disagreeing with the settled vector render.
                return CGColorSpace(name: CGColorSpace.sRGB)
            }
        }
    }

    private func offscreenBacking(sizePt: CGSize? = nil,
                                  colorSpace mode: OffscreenColorSpace = .window) -> CGContext? {
        let scale = backingScale
        let size = sizePt ?? bounds.size
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        let space = mode.cgColorSpace
                 ?? window?.colorSpace?.cgColorSpace
                 ?? CGColorSpace(name: CGColorSpace.sRGB)
        if blurBacking == nil || blurBackingPx != (w, h)
            || blurBackingSpace != space {   // value equality — identity would rebuild every call
            // NATIVE pixel format (BGRA, premultipliedFirst + 32Little): the
            // premultipliedLast (RGBA) layout is non-native on Apple hardware and
            // can push Core Graphics onto slower software paths.
            let native = CGImageAlphaInfo.premultipliedFirst.rawValue
                       | CGBitmapInfo.byteOrder32Little.rawValue
            guard let space,
                  let cg = CGContext(data: nil, width: w, height: h,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: native)
            else { return nil }
            blurBacking = cg
            blurBackingPx = (w, h)
            blurBackingSpace = space
        }
        return blurBacking
    }
    private var blurBackingSpace: CGColorSpace?

    override func draw(_ dirtyRect: NSRect) {
        guard let app, let document else { return }
        perf.enabled = (app.testingMode == true)
        let perfFrameT0 = CFAbsoluteTimeGetCurrent()   // always — feeds fullFrameEMA
        // Live pan/zoom: blit the cached gesture snapshot instead of re-rendering
        // the scene (see the "Pan/zoom bitmap blit" section above).
        if let ctx = NSGraphicsContext.current?.cgContext, drawPanZoomBlit(into: ctx) {
            if perf.enabled {
                perf.record("frame(blit)", ms: (CFAbsoluteTimeGetCurrent() - perfFrameT0) * 1000)
                perf.flushIfNeeded()
            }
            recordInputToFrame()
            return
        }
        // Live node drag: composite static below/above snapshots around the
        // dragged nodes (see the "Drag-overlay blit" section above).
        if let ctx = NSGraphicsContext.current?.cgContext, drawDragBlit(into: ctx) {
            if perf.enabled {
                perf.record("frame(drag)", ms: (CFAbsoluteTimeGetCurrent() - perfFrameT0) * 1000)
                perf.flushIfNeeded()
            }
            recordInputToFrame()
            return
        }
        // Background blur needs to sample what's behind it, which means the scene has
        // to live in a bitmap we can read back. Only pay that cost when a blur node
        // exists; otherwise draw straight to the window context as before.
        if documentHasBackgroundBlur, !blurSuppressed, let cg = offscreenBacking() {
            let scale = backingScale
            cg.saveGState()
            cg.clear(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            // Map point-space (y-down, top-left, as docToView produces) onto the
            // bottom-up bitmap buffer.
            cg.translateBy(x: 0, y: CGFloat(cg.height))
            cg.scaleBy(x: scale, y: -scale)
            let nsctx = NSGraphicsContext(cgContext: cg, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsctx
            withCanvasAppearance {
                renderCanvas(into: cg)           // drawNode samples this same cg
            }
            NSGraphicsContext.restoreGraphicsState()
            cg.restoreGState()
            if let img = cg.makeImage(), let ctx = NSGraphicsContext.current?.cgContext {
                // Blit the upright image into the flipped view (the image-node idiom).
                ctx.saveGState()
                ctx.translateBy(x: 0, y: bounds.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(origin: .zero, size: bounds.size))
                ctx.restoreGState()
            }
        } else if let ctx = NSGraphicsContext.current?.cgContext {
            renderCanvas(into: ctx)
        }
        if perf.enabled {
            perf.record("frame", ms: (CFAbsoluteTimeGetCurrent() - perfFrameT0) * 1000)
            perf.flushIfNeeded()
        }
        // Rolling FULL-render cost (only this path renders the whole scene).
        // Feeds the PERF-002 drag-fidelity decision; EMA so one outlier frame
        // doesn't flip the mode.
        let frameMs = (CFAbsoluteTimeGetCurrent() - perfFrameT0) * 1000
        fullFrameEMA = fullFrameEMA == 0 ? frameMs : fullFrameEMA * 0.8 + frameMs * 0.2
        recordInputToFrame()
    }

    /// Exponential moving average of a full scene render, in ms (0 = no sample
    /// yet). Updated on every non-blit frame — cheap: two timestamps.
    private var fullFrameEMA: Double = 0

    private func renderCanvas(into ctx: CGContext, includeRulers: Bool = true,
                              viewport: CGRect? = nil) {
        guard let document else { return }
        perfCacheHit = 0; perfCacheMiss = 0   // reset per-frame instance-cache tally
        // `viewport` widens the render region for the pan/zoom snapshot's halo
        // (culling + background fill follow it); nil = the on-screen bounds.
        let region = viewport ?? bounds
        let priorRenderRegion = currentRenderRegion
        let ownsImageResidencyPass = imageMipKeysUsedInRender == nil
        if ownsImageResidencyPass { imageMipKeysUsedInRender = [] }
        currentRenderRegion = region
        defer {
            currentRenderRegion = priorRenderRegion
            if ownsImageResidencyPass {
                let used = imageMipKeysUsedInRender ?? []
                latestImageMipKeys = used
                residentImageMips = residentImageMips.filter { used.contains($0.key) }
                imageMipKeysUsedInRender = nil
            }
        }

        perf.measure("draw-bg") {
            NSColor.underPageBackgroundColor.setFill()
            region.fill()
        }

        if isSourceScope {
            perf.measure("draw-source") {
                // Draw the component's viewBox "page" (a stable, resizable frame) plus its
                // resize handles, so it reads and behaves like its own little artboard.
                if let rect = sourceBoundsRect() {
                    drawSourceBounds(rect, in: ctx)
                    drawArtboardHandles(docToView(rect), in: ctx)
                }
                for node in displayedCurrentNodes where node.isVisible && node.id != editingNodeID {
                    drawNode(node, offset: .zero, in: ctx)
                }
            }
        } else {
            // Viewport culling — only paint what can land inside the visible region.
            // Pan/zoom redraw the WHOLE scene, so with many artboards/layers this is
            // the difference between O(everything) and O(what's on screen) per frame.
            let visible = region
            var perfDrawn = 0, perfBoards = 0
            perf.measure("draw-boards") {
                for artboard in currentArtboards {
                    // Grow for the name label above and the soft drop shadow around it.
                    guard docToView(artboard.frame).insetBy(dx: -24, dy: -24).intersects(visible)
                    else { continue }
                    let capB = capturingSnapshot ? CFAbsoluteTimeGetCurrent() : 0
                    drawArtboardBackground(artboard, in: ctx)
                    if capB != 0 { capBoardMs += (CFAbsoluteTimeGetCurrent() - capB) * 1000 }
                    perfBoards += 1
                }
            }
            // Shapes clipped to the artboard that owns them (or unclipped on the
            // wall). The node being text-edited is skipped — the overlay stands in.
            perf.measure("draw-nodes") {
                for node in currentNodes where node.isVisible && node.id != editingNodeID {
                    if drawCulledTopLevelNode(node, visible: visible, in: ctx) { perfDrawn += 1 }
                }
            }
            if perf.enabled {
                perf.gauge("nodes(total)", currentNodes.count)
                perf.gauge("nodes(drawn)", perfDrawn)
                perf.gauge("boards(drawn)", perfBoards)
                perf.gauge("instCacheHit", perfCacheHit)
                perf.gauge("instCacheMiss", perfCacheMiss)
            }
        }

        // Grids over content (document scope only), then guides, then chrome.
        if !isSourceScope {
            perf.measure("draw-grids") {
                drawLayoutGrids(in: ctx)
                if app?.showGrid == true { drawUniformGrid(in: ctx) }
            }
        }
        if app?.showGuides == true { perf.measure("draw-guides") { drawGuides(in: ctx) } }
        
        // Smart guides (shown during drag, on top of static guides)
        perf.measure("draw-smart") { drawSmartGuides(in: ctx) }

        // Selection chrome on top (shared with the drag-overlay blit path).
        perf.measure("draw-chrome") { drawSelectionChrome(in: ctx) }

        var rubberBandStart: CGPoint?
        if case .marquee(let start, _) = dragMode { rubberBandStart = start }
        if case .pointMarquee(let start, _) = dragMode { rubberBandStart = start }
        if case .drawTextBox(let start) = dragMode { rubberBandStart = start }
        if let start = rubberBandStart, let cur = marqueeCurrent {
            let r = CGRect(x: min(start.x, cur.x), y: min(start.y, cur.y),
                           width: abs(cur.x - start.x), height: abs(cur.y - start.y))
            ctx.saveGState()
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            ctx.fill(r)
            NSColor.controlAccentColor.setStroke()
            ctx.setLineWidth(1)
            ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
            ctx.restoreGState()
        }

        if optionHeld { perf.measure("draw-measure") { drawMeasurements(in: ctx) } }

        // Rulers are chrome at the very top, over everything else. (Excluded from
        // the pan/zoom gesture snapshot — the blit path draws them live instead.)
        if includeRulers && app?.showRulers == true && !isSourceScope {
            perf.measure("draw-rulers") { drawRulers(in: ctx) }
        }
    }

    /// One top-level node: viewport + artboard culling, then the standard clip
    /// stack, then drawNode. Shared by renderCanvas's node loop and the
    /// drag-overlay blit (both the snapshot captures and the live dragged
    /// nodes), so all paths cull and clip identically. Returns true if drawn.
    @discardableResult
    private func drawCulledTopLevelNode(_ node: Node, visible: CGRect, in ctx: CGContext) -> Bool {
        guard let document else { return false }
        // Cheap reject for the common case (a leaf shape): it only paints
        // within its frame plus a margin for stroke / effects / rotation, so
        // a node whose expanded frame is fully off-screen can't contribute a
        // pixel — and we skip the owningArtboard scan for it entirely. Groups
        // and instances can hold children outside their own frame, so they
        // fall through to the artboard-clip cull below (which stays exact).
        if isLeafContent(node.content) {
            let m = nodeCullMargin(node)
            if !docToView(node.frame).insetBy(dx: -m, dy: -m).intersects(visible) { return false }
        }
        let owner = owningArtboard(of: node)
        // An owned node is hard-clipped to its artboard (below), so if that
        // board is off-screen the node is invisible regardless of effects or
        // stray children — an exact cull that also covers containers.
        if let owner, !docToView(owner.frame).intersects(visible) { return false }
        ctx.saveGState()
        // Clip to the viewport FIRST. Transparency layers (shadows, layer
        // opacity, blend modes) allocate a surface the size of the current
        // clip; without this, at high zoom an artboard-sized clip becomes
        // tens of thousands of pixels and the shadow's gaussian convolution
        // hangs the render thread ("Surface too large"). You can't see past
        // `bounds` anyway, so this is invisible — it just caps the surface.
        ctx.clip(to: visible)
        if let owner { ctx.clip(to: docToView(owner.frame)) }
        drawNode(node, offset: .zero, in: ctx)
        ctx.restoreGState()
        return true
    }

    /// Selection halos, transform box, and path/pen anchors — the live chrome
    /// drawn over content. Factored out so the drag-overlay blit path can draw
    /// it on top of the composited snapshot without re-rendering the scene.
    private func drawSelectionChrome(in ctx: CGContext) {
        guard let app else { return }
        let selectedIDs = app.selectedNodeIDs
        let selectedCount = selectedIDs.count
        let space = selectionSpace(for: selectedIDs)
        let drawsUnifiedTransform = usesSelectionTransform(space.nodes)
        if perf.enabled { perf.gauge("selectedNodes", selectedCount) }
        let single = selectedCount == 1
        let drawPerNodeHints = single || selectedCount <= 32
        if drawPerNodeHints {
            perf.measure("chrome-node-selection") {
                for id in selectedIDs {
                    guard let node = node(id) else { continue }
                    // A single group already gets the authoritative, rotation-aware
                    // unified transform box below. Its older per-node hint measures
                    // raw descendant frames and can disagree when children are
                    // rotated, producing two crossed sets of resize handles.
                    if single && drawsUnifiedTransform { continue }
                    // Resize/rotate handles for a lone selection that's top-level OR
                    // nested under only UNrotated groups (handle math is a pure offset
                    // there). Nested under a rotated group stays move-only.
                    drawNodeSelection(node, offset: nodeOffset(id), ctx: ctx, handles: single)
                }
            }
        }
        // Unified selection box (8 handles + rotate knob) for a multi-selection
        // or a single group — the per-node boxes above stay as a hint.
        perf.measure("chrome-transform-box") {
            if drawsUnifiedTransform, let box = selectionLocalBox(space) {
                drawSelectionTransformBox(box.ink, chain: space.chain, in: ctx)
            }
        }
        perf.measure("chrome-gradient-line") { drawGradientHandles(in: ctx) }
        // Path anchors + handles: while editing points (node tool) or
        // while the pen is drawing.
        if app.tool == .node, let id = app.singleSelectedNodeID, let n = node(id),
           case .path = n.content {
            perf.measure("chrome-path-points") {
                drawPathPoints(n, in: ctx, selected: selectedPointAddresses,
                               handleOwners: selectedPointAddresses)
                drawPointTransformBox(in: ctx)
            }
        }
        if let penID = penNodeID, let n = node(penID) {
            var active = Set<PointAddress>()
            if case .path(let ps) = n.content, !ps.points.isEmpty {
                active.insert(PointAddress(contour: 0, index: ps.points.count - 1))
            }
            perf.measure("chrome-pen-active-points") {
                drawPathPoints(n, in: ctx, selected: active, handleOwners: active)
            }
        }
        // Pen tool, not mid-draw: show the anchors of the SELECTED path and the
        // path under the cursor, so you can see exactly where to add / remove a
        // point on an existing vector.
        if app.tool == .pen, penNodeID == nil {
            perf.measure("chrome-pen-hover-points") {
                var shown = Set<UUID>()
                if let id = app.singleSelectedNodeID, let n = node(id), case .path = n.content {
                    drawPathPoints(n, in: ctx); shown.insert(id)
                }
                if let hover = penHover(atViewPoint: lastMouse), !shown.contains(hover.leafID),
                   let n = node(hover.leafID), case .path = n.content {
                    drawPathPoints(n, in: ctx)
                }
            }
        }
    }

    // MARK: Rulers

    private func drawRulers(in ctx: CGContext) {
        guard let app else { return }
        let t = rulerThickness
        ctx.saveGState()
        let bg = NSColor.windowBackgroundColor
        bg.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: bounds.width, height: t))
        ctx.fill(CGRect(x: 0, y: t, width: t, height: bounds.height - t))

        drawRulerTicks(horizontal: true, in: ctx)
        drawRulerTicks(horizontal: false, in: ctx)

        // Corner square + separators.
        bg.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: t, height: t))
        NSColor.separatorColor.setStroke()
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 0, y: t - 0.5)); ctx.addLine(to: CGPoint(x: bounds.width, y: t - 0.5))
        ctx.move(to: CGPoint(x: t - 0.5, y: 0)); ctx.addLine(to: CGPoint(x: t - 0.5, y: bounds.height))
        ctx.strokePath()

        // Pointer position markers.
        NSColor.controlAccentColor.setStroke()
        ctx.setLineWidth(1)
        if lastMouse.x >= t { ctx.move(to: CGPoint(x: lastMouse.x, y: 0)); ctx.addLine(to: CGPoint(x: lastMouse.x, y: t)) }
        if lastMouse.y >= t { ctx.move(to: CGPoint(x: 0, y: lastMouse.y)); ctx.addLine(to: CGPoint(x: t, y: lastMouse.y)) }
        ctx.strokePath()
        _ = app
        ctx.restoreGState()
    }

    /// A "nice" round doc-units step (1/2/5 × 10ⁿ) for ~`targetPixels` spacing.
    private func rulerStep(targetPixels: CGFloat) -> CGFloat {
        let zoom = max(app?.zoom ?? 1, 0.0001)
        let raw = targetPixels / zoom
        let mag = pow(10, floor(log10(raw)))
        let norm = raw / mag
        let nice: CGFloat = norm < 1.5 ? 1 : (norm < 3 ? 2 : (norm < 7 ? 5 : 10))
        return nice * mag
    }

    private func drawRulerTicks(horizontal: Bool, in ctx: CGContext) {
        let t = rulerThickness
        let major = rulerStep(targetPixels: 80)
        let minor = major / 5
        let axisEnd = horizontal ? bounds.width : bounds.height
        func docAt(_ vp: CGFloat) -> CGFloat {
            horizontal ? viewToDoc(CGPoint(x: vp, y: 0)).x : viewToDoc(CGPoint(x: 0, y: vp)).y
        }
        let d0 = docAt(t), d1 = docAt(axisEnd)
        let lo = min(d0, d1), hi = max(d0, d1)
        let startK = Int((lo / minor).rounded(.down)), endK = Int((hi / minor).rounded(.up))
        guard endK > startK, endK - startK < 5000 else { return }   // sanity at extreme zoom
        NSColor.tertiaryLabelColor.setStroke()
        ctx.setLineWidth(1)
        for k in startK...endK {
            let v = CGFloat(k) * minor
            let isMajor = k % 5 == 0
            let vp = horizontal ? docToViewPoint(CGPoint(x: v, y: 0)).x : docToViewPoint(CGPoint(x: 0, y: v)).y
            guard vp >= t, vp <= axisEnd else { continue }
            let len: CGFloat = isMajor ? t * 0.55 : t * 0.28
            if horizontal {
                ctx.move(to: CGPoint(x: vp, y: t - len)); ctx.addLine(to: CGPoint(x: vp, y: t))
            } else {
                ctx.move(to: CGPoint(x: t - len, y: vp)); ctx.addLine(to: CGPoint(x: t, y: vp))
            }
            ctx.strokePath()
            if isMajor { drawRulerNumber(Int(v.rounded()), at: vp, horizontal: horizontal) }
        }
    }

    private func drawRulerNumber(_ n: Int, at vp: CGFloat, horizontal: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.secondaryLabelColor]
        let s = "\(n)" as NSString
        if horizontal {
            s.draw(at: CGPoint(x: vp + 2, y: 2), withAttributes: attrs)
        } else {
            s.draw(at: CGPoint(x: 2, y: vp + 1), withAttributes: attrs)
        }
    }

    // MARK: Grids

    /// The global Photoshop-style square grid: minor lines per `gridSubdivisions`,
    /// darker major lines at `gridSize`, aligned to the document origin.
    private func drawUniformGrid(in ctx: CGContext) {
        guard let app, app.gridSize > 0 else { return }
        let major = app.gridSize
        let minor = major / CGFloat(max(1, app.gridSubdivisions))
        let tl = viewToDoc(CGPoint.zero), br = viewToDoc(CGPoint(x: bounds.width, y: bounds.height))
        let loX = min(tl.x, br.x), hiX = max(tl.x, br.x)
        let loY = min(tl.y, br.y), hiY = max(tl.y, br.y)
        guard (hiX - loX) / minor < 4000, (hiY - loY) / minor < 4000 else { return }

        func lines(spacing: CGFloat, color: NSColor) {
            color.setStroke(); ctx.setLineWidth(1); ctx.beginPath()
            var kx = Int((loX / spacing).rounded(.down))
            while CGFloat(kx) * spacing <= hiX {
                let x = docToViewPoint(CGPoint(x: CGFloat(kx) * spacing, y: 0)).x
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)); kx += 1
            }
            var ky = Int((loY / spacing).rounded(.down))
            while CGFloat(ky) * spacing <= hiY {
                let y = docToViewPoint(CGPoint(x: 0, y: CGFloat(ky) * spacing)).y
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)); ky += 1
            }
            ctx.strokePath()
        }
        ctx.saveGState()
        if app.gridSubdivisions > 1 { lines(spacing: minor, color: NSColor.systemGray.withAlphaComponent(0.12)) }
        lines(spacing: major, color: NSColor.systemGray.withAlphaComponent(0.28))
        ctx.restoreGState()
    }

    /// Per-artboard layout grids (columns / rows / baseline), clipped to each board.
    private func drawLayoutGrids(in ctx: CGContext) {
        guard let document else { return }
        for ab in currentArtboards {
            let grids = ab.layoutGrids.filter { $0.visible }
            guard !grids.isEmpty else { continue }
            ctx.saveGState()
            ctx.clip(to: docToView(ab.frame))
            for g in grids { drawLayoutGrid(g, artboard: ab.frame, in: ctx) }
            ctx.restoreGState()
        }
    }

    private func drawLayoutGrid(_ g: LayoutGrid, artboard f: CGRect, in ctx: CGContext) {
        let color = PaintRender.nsColor(g.color)
        switch g.kind {
        case .columns:
            let usable = f.width - 2 * g.margin
            guard g.count > 0, usable > 0 else { return }
            let colW = (usable - g.gutter * CGFloat(g.count - 1)) / CGFloat(g.count)
            guard colW > 0 else { return }
            color.setFill()
            for i in 0..<g.count {
                let x0 = f.minX + g.margin + CGFloat(i) * (colW + g.gutter)
                ctx.fill(docToView(CGRect(x: x0, y: f.minY, width: colW, height: f.height)))
            }
        case .rows:
            let usable = f.height - 2 * g.margin
            guard g.count > 0, usable > 0 else { return }
            let rowH = (usable - g.gutter * CGFloat(g.count - 1)) / CGFloat(g.count)
            guard rowH > 0 else { return }
            color.setFill()
            for i in 0..<g.count {
                let y0 = f.minY + g.margin + CGFloat(i) * (rowH + g.gutter)
                ctx.fill(docToView(CGRect(x: f.minX, y: y0, width: f.width, height: rowH)))
            }
        case .baseline:
            guard g.size > 0, (f.height / g.size) < 5000 else { return }
            let v = docToView(f)
            color.setStroke(); ctx.setLineWidth(1); ctx.beginPath()
            var y = f.minY
            while y <= f.maxY {
                let vy = docToViewPoint(CGPoint(x: 0, y: y)).y
                ctx.move(to: CGPoint(x: v.minX, y: vy)); ctx.addLine(to: CGPoint(x: v.maxX, y: vy))
                y += g.size
            }
            ctx.strokePath()
        }
    }

    /// Snap-line x positions (column edges) for a layout grid.
    private func layoutGridXLines(_ g: LayoutGrid, _ f: CGRect) -> [CGFloat] {
        guard g.kind == .columns, g.count > 0 else { return [] }
        let usable = f.width - 2 * g.margin
        let colW = (usable - g.gutter * CGFloat(g.count - 1)) / CGFloat(g.count)
        guard colW > 0 else { return [] }
        var xs: [CGFloat] = []
        for i in 0..<g.count {
            let x0 = f.minX + g.margin + CGFloat(i) * (colW + g.gutter)
            xs.append(x0); xs.append(x0 + colW)
        }
        return xs
    }
    /// Snap-line y positions (row edges or baseline lines) for a layout grid.
    private func layoutGridYLines(_ g: LayoutGrid, _ f: CGRect) -> [CGFloat] {
        switch g.kind {
        case .rows:
            guard g.count > 0 else { return [] }
            let usable = f.height - 2 * g.margin
            let rowH = (usable - g.gutter * CGFloat(g.count - 1)) / CGFloat(g.count)
            guard rowH > 0 else { return [] }
            var ys: [CGFloat] = []
            for i in 0..<g.count {
                let y0 = f.minY + g.margin + CGFloat(i) * (rowH + g.gutter)
                ys.append(y0); ys.append(y0 + rowH)
            }
            return ys
        case .baseline:
            guard g.size > 0, (f.height / g.size) < 5000 else { return [] }
            var ys: [CGFloat] = []; var y = f.minY
            while y <= f.maxY { ys.append(y); y += g.size }
            return ys
        case .columns:
            return []
        }
    }

    // MARK: Guides

    /// True if a view point is inside either ruler strip.
    private func inRuler(_ p: CGPoint) -> Bool {
        guard app?.showRulers == true, !isSourceScope else { return false }
        return p.x < rulerThickness || p.y < rulerThickness
    }

    private func drawGuides(in ctx: CGContext) {
        guard let document, !isSourceScope else { return }
        let cyan = NSColor(srgbRed: 0, green: 0.66, blue: 0.93, alpha: 0.9)
        ctx.saveGState()
        cyan.setStroke()
        ctx.setLineWidth(1)
        for g in currentGuides { strokeGuide(g.axis, g.position, in: ctx) }
        if let dg = draggingGuide { strokeGuide(dg.axis, dg.position, in: ctx) }   // live preview
        ctx.strokePath()
        ctx.restoreGState()
    }
    
    /// Draw smart guide lines (Figma/XD-style alignment indicators during drag).
    private func drawSmartGuides(in ctx: CGContext) {
        guard !activeSmartGuides.isEmpty else { return }
        ctx.saveGState()
        // Magenta/pink to distinguish from cyan ruler guides
        NSColor(srgbRed: 0.98, green: 0.24, blue: 0.52, alpha: 0.9).setStroke()
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 4])  // dashed line
        
        for guide in activeSmartGuides {
            guard !guide.matchedEdges.isEmpty else { continue }
            let min = guide.matchedEdges.min()!
            let max = guide.matchedEdges.max()!
            
            switch guide.axis {
            case .vertical:
                let x = docToViewPoint(CGPoint(x: guide.position, y: 0)).x
                let y1 = docToViewPoint(CGPoint(x: 0, y: min)).y
                let y2 = docToViewPoint(CGPoint(x: 0, y: max)).y
                ctx.move(to: CGPoint(x: x, y: y1))
                ctx.addLine(to: CGPoint(x: x, y: y2))
            case .horizontal:
                let y = docToViewPoint(CGPoint(x: 0, y: guide.position)).y
                let x1 = docToViewPoint(CGPoint(x: min, y: 0)).x
                let x2 = docToViewPoint(CGPoint(x: max, y: 0)).x
                ctx.move(to: CGPoint(x: x1, y: y))
                ctx.addLine(to: CGPoint(x: x2, y: y))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// An existing guide under the cursor (within a few px), if any. Skips when in a
    /// ruler strip (rulers create new guides) or guides are hidden.
    private func hitTestGuide(at p: CGPoint) -> Guide? {
        guard let document, app?.showGuides == true, !inRuler(p) else { return nil }
        let tol: CGFloat = 4
        return currentGuides.last { g in
            switch g.axis {
            case .horizontal: return abs(docToViewPoint(CGPoint(x: 0, y: g.position)).y - p.y) <= tol
            case .vertical:   return abs(docToViewPoint(CGPoint(x: g.position, y: 0)).x - p.x) <= tol
            }
        }
    }

    /// Start a guide gesture if the click is in a ruler (create) or on a guide
    /// (move). Returns true if a guide drag began.
    private func beginGuideDrag(at p: CGPoint) -> Bool {
        guard let document else { return false }
        if inRuler(p) {
            // Top ruler → horizontal guide; left ruler → vertical guide; corner = no-op.
            if p.y < rulerThickness, p.x >= rulerThickness {
                draggingGuide = Guide(axis: .horizontal, position: viewToDoc(p).y)
            } else if p.x < rulerThickness, p.y >= rulerThickness {
                draggingGuide = Guide(axis: .vertical, position: viewToDoc(p).x)
            } else { return false }
            movingGuideID = nil
            dragBaseline = document.model
            gestureUndoName = "Add Guide"
            dragMode = .guide
            needsDisplay = true
            return true
        }
        if let g = hitTestGuide(at: p) {
            movingGuideID = g.id
            draggingGuide = nil
            dragBaseline = document.model
            gestureUndoName = "Move Guide"
            dragMode = .guide
            needsDisplay = true
            return true
        }
        return false
    }

    private func updateGuideDrag(at p: CGPoint) {
        guard let document else { return }
        let doc = viewToDoc(p)
        if let id = movingGuideID, let i = currentGuides.firstIndex(where: { $0.id == id }) {
            withActivePage { page in
                page.guides[i].position = (page.guides[i].axis == .horizontal) ? doc.y : doc.x
            }
        } else if var g = draggingGuide {
            g.position = (g.axis == .horizontal) ? doc.y : doc.x
            draggingGuide = g
        }
        didEdit = true
        needsDisplay = true
    }

    private func finishGuideDrag(at p: CGPoint) {
        guard let document else { return }
        let droppedOnRuler = inRuler(p)
        if let id = movingGuideID {
            if droppedOnRuler {
                withActivePage { $0.guides.removeAll { $0.id == id } }
                gestureUndoName = "Delete Guide"
            }
            registerUndoForGesture()
        } else if let g = draggingGuide, !droppedOnRuler {
            withActivePage { $0.guides.append(g) }
            registerUndoForGesture()
        }
        draggingGuide = nil
        movingGuideID = nil
        dragBaseline = nil
        dragMode = .none
        needsDisplay = true
    }

    /// Adjust a node-drag offset so the selection's edges/centers snap to nearby
    /// guides, artboard edges, grid lines, AND other elements (smart guides).
    private func snapNodeOffset(dx: CGFloat, dy: CGFloat, origins: [UUID: CGPoint]) -> (CGFloat, CGFloat) {
        guard let app, let document, !isSourceScope else { return (dx, dy) }
        let perfSnapT0 = perf.enabled ? CFAbsoluteTimeGetCurrent() : 0
        var perfCands = 0
        var box: CGRect?
        for (id, o0) in origins {
            guard let n = node(id) else { continue }
            // Measure the same visual bounds the alignment commands use, including
            // nested/rotated/flipped content. `origins` is the gesture baseline;
            // rebuilding that origin here keeps the snap box stable even though the
            // live model already contains the previous mouse tick.
            var baseline = n
            baseline.frame.origin = o0
            let f = documentAlignmentBounds(baseline, ancestors: ancestorGroups(of: id))
                .offsetBy(dx: dx, dy: dy)
            box = box.map { $0.union(f) } ?? f
        }
        guard let b = box else { return (dx, dy) }
        let thr = 6 / max(app.zoom, 0.0001)
        
        var xLines: [CGFloat] = [], yLines: [CGFloat] = []
        var xSources: [CGFloat: Set<CGFloat>] = [:], ySources: [CGFloat: Set<CGFloat>] = [:]  // track which elements contribute to each line
        
        // Ruler guides
        if app.showGuides {
            for g in currentGuides {
                if g.axis == .vertical { 
                    xLines.append(g.position)
                } else { 
                    yLines.append(g.position) 
                }
            }
        }
        
        // Artboard edges/center. Include every board the selection touches OR is
        // within the magnetic threshold of. The old owning-board-only lookup meant
        // a layer approaching from the wall could never snap flush to the OUTSIDE of
        // a board: at a flush edge there is zero overlap, so the board did not own it
        // yet. The expanded 2D probe keeps this local and subtle — a far-away board
        // that merely shares an x/y coordinate cannot pull the drag sideways.
        let boardObj = owningArtboard(of: b)
        let boardProbe = b.insetBy(dx: -thr, dy: -thr)
        for board in currentArtboards where board.frame.intersects(boardProbe) {
            let ab = board.frame
            for x in [ab.minX, ab.midX, ab.maxX] {
                xLines.append(x)
                if app.smartGuidesEnabled {
                    xSources[x, default: []].formUnion([ab.minY, ab.maxY])
                }
            }
            for y in [ab.minY, ab.midY, ab.maxY] {
                yLines.append(y)
                if app.smartGuidesEnabled {
                    ySources[y, default: []].formUnion([ab.minX, ab.maxX])
                }
            }
        }
        
        // Grid snapping
        if app.snapToGrid {
            // Uniform grid: the nearest minor line to each box edge/center.
            if app.gridSize > 0 {
                let minor = app.gridSize / CGFloat(max(1, app.gridSubdivisions))
                for v in [b.minX, b.midX, b.maxX] { xLines.append((v / minor).rounded() * minor) }
                for v in [b.minY, b.midY, b.maxY] { yLines.append((v / minor).rounded() * minor) }
            }
            // Layout grid column/row/baseline edges of the owning artboard.
            if let ab = boardObj {
                for g in ab.layoutGrids where g.visible {
                    xLines += layoutGridXLines(g, ab.frame)
                    yLines += layoutGridYLines(g, ab.frame)
                }
            }
        }
        
        // Smart guides: snap to other visible, unselected elements ON THE SAME
        // ARTBOARD. Scoping to the owning artboard (a) matches what you're actually
        // working on and (b) is the performance fix for dragging on the wall: with
        // many items, re-scanning every distant node on each mouse-move stalls the
        // drag. A selection loose on the wall (no owning artboard) gets no element
        // smart guides at all — only ruler guides / the uniform grid still apply.
        if app.smartGuidesEnabled, let boardFrame = boardObj?.frame {
            let selectedIDs = Set(origins.keys)
            // Collect visible, unselected nodes that TOUCH this artboard, at every
            // level (recursing into groups). Off-board / wall nodes are skipped before
            // recursion, so far-distant items never enter the snap calculation.
            func collectCandidates(_ nodes: [Node], offset: CGPoint, parent: Node? = nil) -> [(frame: CGRect, parentFrame: CGRect?)] {
                var result: [(CGRect, CGRect?)] = []
                for n in nodes {
                    guard n.isVisible, !selectedIDs.contains(n.id) else { continue }
                    let absFrame = n.frame.offsetBy(dx: offset.x, dy: offset.y)
                    guard absFrame.intersects(boardFrame) else { continue }
                    // Include both the element itself and its parent group frame (for spacing to group edges)
                    result.append((absFrame, parent?.frame.offsetBy(dx: offset.x - n.frame.minX, dy: offset.y - n.frame.minY)))
                    if case .group(let children) = n.content {
                        result += collectCandidates(children, 
                                                   offset: CGPoint(x: offset.x + n.frame.minX, y: offset.y + n.frame.minY),
                                                   parent: n)
                    }
                }
                return result
            }
            
            let candidates = collectCandidates(currentNodes, offset: .zero)
            perfCands = candidates.count
            for (frame, parentFrame) in candidates {
                // Element edges and center
                for x in [frame.minX, frame.midX, frame.maxX] {
                    xLines.append(x)
                    xSources[x, default: []].insert(frame.minY)
                    xSources[x, default: []].insert(frame.maxY)
                }
                for y in [frame.minY, frame.midY, frame.maxY] {
                    yLines.append(y)
                    ySources[y, default: []].insert(frame.minX)
                    ySources[y, default: []].insert(frame.maxX)
                }
                
                // Parent group inside edges (for spacing measurements within groups)
                if let pf = parentFrame {
                    for x in [pf.minX, pf.maxX] {
                        xLines.append(x)
                        xSources[x, default: []].insert(pf.minY)
                        xSources[x, default: []].insert(pf.maxY)
                    }
                    for y in [pf.minY, pf.maxY] {
                        yLines.append(y)
                        ySources[y, default: []].insert(pf.minX)
                        ySources[y, default: []].insert(pf.maxX)
                    }
                }
            }
        }
        
        func best(_ values: [CGFloat], _ lines: [CGFloat]) -> (offset: CGFloat, snappedLine: CGFloat?) {
            var bestD: CGFloat = 0, bestAbs = thr
            var bestLine: CGFloat?
            for v in values { for l in lines {
                let d = l - v
                if abs(d) < bestAbs { bestAbs = abs(d); bestD = d; bestLine = l }
            } }
            return (bestD, bestLine)
        }
        
        let xResult = best([b.minX, b.midX, b.maxX], xLines)
        let yResult = best([b.minY, b.midY, b.maxY], yLines)
        
        // Build smart guide lines for visual feedback
        activeSmartGuides = []
        if app.smartGuidesEnabled {
            if let line = xResult.snappedLine, xSources[line] != nil {
                let edges = Array(xSources[line]!).sorted()
                activeSmartGuides.append(SmartGuideLine(axis: .vertical, position: line, matchedEdges: edges + [b.minY, b.maxY]))
            }
            if let line = yResult.snappedLine, ySources[line] != nil {
                let edges = Array(ySources[line]!).sorted()
                activeSmartGuides.append(SmartGuideLine(axis: .horizontal, position: line, matchedEdges: edges + [b.minX, b.maxX]))
            }
        }
        
        if perf.enabled {
            perf.record("snap", ms: (CFAbsoluteTimeGetCurrent() - perfSnapT0) * 1000)
            perf.gauge("snapCands", perfCands)
        }
        return (dx + xResult.offset, dy + yResult.offset)
    }

    private func strokeGuide(_ axis: Guide.Axis, _ position: CGFloat, in ctx: CGContext) {
        switch axis {
        case .horizontal:
            let y = docToViewPoint(CGPoint(x: 0, y: position)).y
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y))
        case .vertical:
            let x = docToViewPoint(CGPoint(x: position, y: 0)).x
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height))
        }
    }

    // MARK: ⌥-hover spacing measurements

    /// Distances from the selection to the shape under the cursor (or, hovering
    /// empty space, to the artboard/group edges). Shown while ⌥ is held and not dragging.
    /// Enhanced to work with grouped elements and show spacing to group edges.
    private func drawMeasurements(in ctx: CGContext) {
        guard let app, let document, case .none = dragMode else { return }
        let selIDs = app.selectedNodeIDs
        
        // Get the selection's absolute frame (handling nested nodes)
        func getAbsoluteFrame(_ id: UUID) -> CGRect? {
            guard let n = node(id) else { return nil }
            let offset = nodeOffset(id)
            return n.frame.offsetBy(dx: offset.x, dy: offset.y)
        }
        
        let selFrames = selIDs.compactMap { getAbsoluteFrame($0) }
        guard let first = selFrames.first else { return }
        let s = selFrames.dropFirst().reduce(first) { $0.union($1) }

        let docPt = viewToDoc(lastMouse)
        
        // Find hovered element (including nested ones) and its parent
        func findHoveredWithContext(at point: CGPoint) -> (node: Node, absFrame: CGRect, parentFrame: CGRect?)? {
            func search(_ nodes: [Node], offset: CGPoint, parent: Node? = nil) -> (Node, CGRect, CGRect?)? {
                for n in nodes.reversed() {
                    guard n.isVisible, !selIDs.contains(n.id) else { continue }
                    let absFrame = n.frame.offsetBy(dx: offset.x, dy: offset.y)
                    if nodeHit(n, at: point, offset: offset) {
                        // Calculate parent's absolute frame if it exists
                        let parentAbsFrame = parent.map { p in
                            p.frame.offsetBy(dx: offset.x - n.frame.minX, dy: offset.y - n.frame.minY)
                        }
                        
                        // Check children first (deepest hit wins)
                        if case .group(let children) = n.content {
                            if let deeper = search(children, 
                                                 offset: CGPoint(x: offset.x + n.frame.minX, y: offset.y + n.frame.minY),
                                                 parent: n) {
                                return deeper
                            }
                        }
                        return (n, absFrame, parentAbsFrame)
                    }
                }
                return nil
            }
            return search(currentNodes, offset: .zero)
        }
        
        ctx.saveGState()
        if let hit = findHoveredWithContext(at: docPt) {
            // Show gap to the hovered element
            drawGapMeasure(s, hit.absFrame, in: ctx)
            
            // If the hovered element has a parent group, also show spacing to parent edges
            if let parentFrame = hit.parentFrame {
                // Only show parent edge measurements if they're meaningful (element not at edges)
                if hit.absFrame.minX > parentFrame.minX + 1 {
                    drawHMeasure(x1: parentFrame.minX, x2: hit.absFrame.minX, y: hit.absFrame.midY, in: ctx)
                }
                if hit.absFrame.maxX < parentFrame.maxX - 1 {
                    drawHMeasure(x1: hit.absFrame.maxX, x2: parentFrame.maxX, y: hit.absFrame.midY, in: ctx)
                }
                if hit.absFrame.minY > parentFrame.minY + 1 {
                    drawVMeasure(y1: parentFrame.minY, y2: hit.absFrame.minY, x: hit.absFrame.midX, in: ctx)
                }
                if hit.absFrame.maxY < parentFrame.maxY - 1 {
                    drawVMeasure(y1: hit.absFrame.maxY, y2: parentFrame.maxY, x: hit.absFrame.midX, in: ctx)
                }
            }
        } else {
            // No hovered element - show spacing to container edges
            // Check if selection is inside a group
            let selectedNode = selIDs.first.flatMap { node($0) }
            let parentGroupID = selectedNode.flatMap { _ in self.parentGroupID(of: selIDs.first!) }
            
            if let pgid = parentGroupID, let parent = node(pgid) {
                // Show spacing to parent group edges
                let parentOffset = nodeOffset(pgid)
                let parentAbsFrame = parent.frame.offsetBy(dx: parentOffset.x, dy: parentOffset.y)
                drawEdgeMeasures(s, container: parentAbsFrame, in: ctx)
            } else if !isSourceScope, let ab = owningArtboard(of: s) {
                // Show spacing to artboard edges
                drawEdgeMeasures(s, container: ab.frame, in: ctx)
            } else if isSourceScope {
                // Show spacing to the component's viewBox bounds.
                if let container = sourceBoundsRect() {
                    drawEdgeMeasures(s, container: container, in: ctx)
                }
            }
        }
        ctx.restoreGState()
    }

    /// Horizontal + vertical gaps between two boxes (whichever axes are separated).
    private func drawGapMeasure(_ s: CGRect, _ t: CGRect, in ctx: CGContext) {
        func sharedMid(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>, fallback: CGFloat) -> CGFloat {
            let lo = max(a.lowerBound, b.lowerBound), hi = min(a.upperBound, b.upperBound)
            return lo <= hi ? (lo + hi) / 2 : fallback
        }
        let y = sharedMid(s.minY...s.maxY, t.minY...t.maxY, fallback: (s.midY + t.midY) / 2)
        if t.minX >= s.maxX { drawHMeasure(x1: s.maxX, x2: t.minX, y: y, in: ctx) }
        else if s.minX >= t.maxX { drawHMeasure(x1: t.maxX, x2: s.minX, y: y, in: ctx) }
        let x = sharedMid(s.minX...s.maxX, t.minX...t.maxX, fallback: (s.midX + t.midX) / 2)
        if t.minY >= s.maxY { drawVMeasure(y1: s.maxY, y2: t.minY, x: x, in: ctx) }
        else if s.minY >= t.maxY { drawVMeasure(y1: t.maxY, y2: s.minY, x: x, in: ctx) }
    }

    /// The four distances from the selection box to the container's edges.
    private func drawEdgeMeasures(_ s: CGRect, container c: CGRect, in ctx: CGContext) {
        if s.minX > c.minX { drawHMeasure(x1: c.minX, x2: s.minX, y: s.midY, in: ctx) }
        if c.maxX > s.maxX { drawHMeasure(x1: s.maxX, x2: c.maxX, y: s.midY, in: ctx) }
        if s.minY > c.minY { drawVMeasure(y1: c.minY, y2: s.minY, x: s.midX, in: ctx) }
        if c.maxY > s.maxY { drawVMeasure(y1: s.maxY, y2: c.maxY, x: s.midX, in: ctx) }
    }

    private func drawHMeasure(x1: CGFloat, x2: CGFloat, y: CGFloat, in ctx: CGContext) {
        guard abs(x2 - x1) > 0.01 else { return }
        let a = docToViewPoint(CGPoint(x: x1, y: y)), b = docToViewPoint(CGPoint(x: x2, y: y))
        drawMeasureLine(from: a, to: b, label: measureLabel(abs(x2 - x1)), horizontal: true, in: ctx)
    }
    private func drawVMeasure(y1: CGFloat, y2: CGFloat, x: CGFloat, in ctx: CGContext) {
        guard abs(y2 - y1) > 0.01 else { return }
        let a = docToViewPoint(CGPoint(x: x, y: y1)), b = docToViewPoint(CGPoint(x: x, y: y2))
        drawMeasureLine(from: a, to: b, label: measureLabel(abs(y2 - y1)), horizontal: false, in: ctx)
    }

    private func drawMeasureLine(from a: CGPoint, to b: CGPoint, label: String, horizontal: Bool, in ctx: CGContext) {
        NSColor.systemRed.setStroke()
        ctx.setLineWidth(1)
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        let tick: CGFloat = 3   // perpendicular end caps
        ctx.beginPath()
        if horizontal {
            for x in [a.x, b.x] { ctx.move(to: CGPoint(x: x, y: a.y - tick)); ctx.addLine(to: CGPoint(x: x, y: a.y + tick)) }
        } else {
            for y in [a.y, b.y] { ctx.move(to: CGPoint(x: a.x - tick, y: y)); ctx.addLine(to: CGPoint(x: a.x + tick, y: y)) }
        }
        ctx.strokePath()
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let labelPos = horizontal ? CGPoint(x: mid.x, y: mid.y - 9) : CGPoint(x: mid.x + 13, y: mid.y)
        drawMeasureLabel(label, at: labelPos)
    }

    private func drawMeasureLabel(_ text: String, at p: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 3
        let box = CGRect(x: p.x - size.width / 2 - pad, y: p.y - size.height / 2 - pad,
                         width: size.width + pad * 2, height: size.height + pad * 2)
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad), withAttributes: attrs)
    }

    private func measureLabel(_ v: CGFloat) -> String {
        // 2 decimals max, trailing zeros trimmed — same precision the inspector
        // shows, so the canvas and the panel never disagree about a value.
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        let s = String(format: "%.2f", r)
        return s.hasSuffix("0") ? String(s.dropLast()) : s
    }

    // MARK: - Viewport culling helpers

    /// True for content that paints strictly within its own frame (plus the margin
    /// from `nodeCullMargin` for stroke / effects / rotation). Groups and instances
    /// can place children outside their frame, so they're never frame-culled.
    private func isLeafContent(_ c: NodeContent) -> Bool {
        switch c {
        case .group, .instance: return false
        default:                return true
        }
    }

    /// Content that must stay on the live vector path during interaction.
    ///
    /// The fast pan/zoom and drag paths flatten static content into temporary
    /// bitmaps. Owner testing showed that gradient fills and shadows visibly shift
    /// in those snapshots while the live-rendered moving node stays correct. Until
    /// the bitmap color/compositing path can be made pixel-identical, keep these
    /// nodes on the exact renderer and use snapshots only for plain content.
    private func visibleBitmapSensitiveContent(in region: CGRect,
                                               excludingTopLevelIDs excluded: Set<UUID> = []) -> Bool {
        guard let document else { return false }
        if !isSourceScope {
            for artboard in currentArtboards
            where docToView(artboard.frame).insetBy(dx: -24, dy: -24).intersects(region) {
                if artboard.background.isGradient { return true }
            }
        }
        for node in currentNodes where node.isVisible && !excluded.contains(node.id) {
            guard nodeMayPaintInRegion(node, region) else { continue }
            if nodeHasBitmapSensitiveContent(node, model: document.model) { return true }
        }
        return false
    }

    private func nodeMayPaintInRegion(_ node: Node, _ region: CGRect) -> Bool {
        guard let document else { return false }
        if isLeafContent(node.content) {
            let m = nodeCullMargin(node)
            if !docToView(node.frame).insetBy(dx: -m, dy: -m).intersects(region) { return false }
        }
        if let owner = owningArtboard(of: node),
           !docToView(owner.frame).intersects(region) { return false }
        return true
    }

    private func nodeHasBitmapSensitiveContent(_ node: Node, model: Document) -> Bool {
        if node.effects.contains(where: {
            $0.isEnabled && ($0.kind == .dropShadow || $0.kind == .innerShadow || $0.kind == .layerBlur)
        }) {
            return true
        }
        func sensitivePaint(_ paint: Paint?) -> Bool { paint?.isGradient == true }
        switch node.content {
        case .rectangle(let s):
            return sensitivePaint(s.fill)
        case .ellipse(let s):
            return sensitivePaint(s.fill)
        case .polygon(let s):
            return sensitivePaint(s.fill)
        case .path(let s):
            return sensitivePaint(s.fill)
        case .group(let children):
            if sensitivePaint(node.autoPadding?.fill) { return true }
            return children.contains { $0.isVisible && nodeHasBitmapSensitiveContent($0, model: model) }
        case .instance(let inst):
            return model.resolvedChildren(of: inst).contains { $0.isVisible && nodeHasBitmapSensitiveContent($0, model: model) }
        case .line, .text, .image:
            return false
        }
    }

    /// View-space margin to grow a leaf's frame before the viewport cull test, so a
    /// node whose paint spills past its frame (thick stroke, drop shadow, rotation)
    /// is never culled while any of it is still on screen.
    private func nodeCullMargin(_ node: Node) -> CGFloat {
        let z = app?.zoom ?? 1
        var doc = strokeReach(node.content)
        for e in node.effects where e.isEnabled && e.kind == .dropShadow {
            doc = max(doc, max(abs(e.dx), abs(e.dy)) + e.blur * 3 + e.spread)
        }
        for e in node.effects where e.isEnabled && e.kind == .layerBlur {
            doc = max(doc, e.blur * 3)
        }
        var margin = doc * z + 2
        if node.rotation != 0 {
            // Rotation about the centre can push the AABB out by up to half the
            // diagonal — a safe upper bound regardless of the angle.
            margin += hypot(node.frame.width, node.frame.height) * z / 2
        }
        return margin
    }

    /// How far past the frame the stroke paints (document space), else 0 —
    /// alignment-aware (v1.3): inside strokes never leave the frame, outside
    /// strokes reach a full width, centered ones half.
    private func strokeReach(_ c: NodeContent) -> CGFloat {
        switch c {
        case .rectangle(let s): return s.strokeAlignment.reach(for: s.strokeWidth)
        case .ellipse(let s):   return s.strokeAlignment.reach(for: s.strokeWidth)
        case .polygon(let s):   return s.strokeAlignment.reach(for: s.strokeWidth)
        case .line(let s):
            return (s.startMarker != .none || s.endMarker != .none) ? s.strokeWidth * 4 : s.strokeWidth / 2
        case .path(let s):
            if !s.closed, !s.isMultiContour, s.startMarker != .none || s.endMarker != .none {
                return s.strokeWidth * 4
            }
            return s.effectiveStrokeAlignment.reach(for: s.strokeWidth)
        default:                return 0
        }
    }

    private func drawArtboardBackground(_ artboard: Artboard, in ctx: CGContext) {
        let rect = docToView(artboard.frame)

        ctx.saveGState()
        // Bound the shadow's working buffer to the board + blur reach (the same
        // clip-before-shadow rule as EffectsRender.drawDropShadow) — an unclipped
        // shadow can allocate a surface for the whole context.
        ctx.clip(to: rect.insetBy(dx: -24, dy: -24))
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 8,
                      color: NSColor.black.withAlphaComponent(0.18).cgColor)
        PaintRender.fillRect(artboard.background, rect: rect, in: ctx)
        ctx.restoreGState()

        ctx.saveGState()
        NSColor.separatorColor.setStroke()
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()

        let selected = app?.selectedArtboardIDs.contains(artboard.id) ?? false
        if selected, app?.selectedNodeIDs.isEmpty ?? true {
            ctx.saveGState()
            NSColor.controlAccentColor.setStroke()
            ctx.setLineWidth(2)
            ctx.stroke(rect.insetBy(dx: -1, dy: -1))
            ctx.restoreGState()
            // Resize handles only when this is the sole selected board.
            if app?.selectedArtboardIDs.count == 1 {
                drawArtboardHandles(rect, in: ctx)
            }
        }

        if artboard.id != editingArtboardID {
            drawLabel(artboard.name, above: rect)
        }
    }

    /// The 8 resize handles around a selected artboard (view space).
    private func drawArtboardHandles(_ rect: CGRect, in ctx: CGContext) {
        for handle in Handle.allCases {
            let c = handlePoint(handle, in: rect)
            let r = CGRect(x: c.x - handleSize / 2, y: c.y - handleSize / 2,
                           width: handleSize, height: handleSize)
            ctx.saveGState()
            NSColor.white.setFill()
            ctx.fill(r)
            NSColor.controlAccentColor.setStroke()
            ctx.setLineWidth(1)
            ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
            ctx.restoreGState()
        }
    }

    /// White bounds frame for a component source in the source editor.
    private func drawSourceBounds(_ docRect: CGRect, in ctx: CGContext) {
        let rect = docToView(docRect)
        // The component "page" takes the chosen VIEW backdrop shade (light/grey/dark)
        // so white or black artwork stays visible while editing. This is purely a
        // viewing aid — it never changes the component's own background.
        let shade = app?.sourceBackdrop.white ?? 0.96
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 8,
                      color: NSColor.black.withAlphaComponent(0.25).cgColor)
        NSColor(white: shade, alpha: 1).setFill()
        ctx.fill(rect)
        ctx.restoreGState()
        ctx.saveGState()
        // Luminance-aware hairline so the bounds read on a light OR dark shade.
        let line = shade > 0.5 ? NSColor.black.withAlphaComponent(0.22)
                               : NSColor.white.withAlphaComponent(0.30)
        line.setStroke()
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
    }

    /// True when drawing this node is one compositing operation — one fill OR
    /// one stroke, never both, and no effects — so whole-layer opacity/blend can
    /// be plain context state instead of a transparency layer. A stroke with
    /// zero width or a fully transparent color doesn't count as an operation
    /// (draw sites guard on `strokeWidth > 0`, and clear paints nothing).
    /// Text keeps the layer: glyphs can overlap each other (tight tracking,
    /// script faces) and would double-composite under plain alpha. Groups and
    /// instances composite children, so they always keep it.
    private func isSinglePaintOp(_ node: Node) -> Bool {
        guard !node.effects.contains(where: { $0.isEnabled }) else { return false }
        func strokeOp(_ w: CGFloat, _ c: RGBAColor) -> Bool { w > 0 && c.a > 0 }
        func fillOp(_ p: Paint) -> Bool {
            if case .solid(let c) = p { return c.a > 0 }
            return true   // gradients: treat as visible
        }
        switch node.content {
        case .rectangle(let s): return !(fillOp(s.fill) && strokeOp(s.strokeWidth, s.stroke))
        case .ellipse(let s):   return !(fillOp(s.fill) && strokeOp(s.strokeWidth, s.stroke))
        case .polygon(let s):   return !(fillOp(s.fill) && strokeOp(s.strokeWidth, s.stroke))
        case .path(let s):      return !(fillOp(s.fill) && strokeOp(s.strokeWidth, s.stroke))
        case .line:             return true    // stroke only
        case .image:            return true    // one draw
        default:                return false   // text, group, instance
        }
    }

    /// Conservative VIEW-space bounds of everything a node can paint — the clip
    /// for its opacity/blend transparency layer. Leaves = frame + cull margin
    /// (stroke/shadow/rotation, the culling invariant). Groups = union of the
    /// padded frame and every visible child's paint bounds, recursively, grown
    /// for the group's own rotation. Instances = their viewBox (instance drawing
    /// hard-clips to it). Frame traversal only — no drawing, cheap per frame.
    private func paintBoundsView(_ node: Node, offset: CGPoint) -> CGRect {
        let frameDoc = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        let rect = docToView(frameDoc)
        switch node.content {
        case .group(let children):
            let childOffset = CGPoint(x: frameDoc.minX, y: frameDoc.minY)
            var b = rect
            for child in children where child.isVisible {
                b = b.union(paintBoundsView(child, offset: childOffset))
            }
            if node.rotation != 0 {
                // Rotation about the centre can push the AABB out by up to half
                // the diagonal — same safe bound as nodeCullMargin.
                let grow = hypot(b.width, b.height) / 2
                b = b.insetBy(dx: -grow, dy: -grow)
            }
            return b.insetBy(dx: -2, dy: -2)   // antialiasing fringe
        case .instance(let inst):
            guard let document else { return rect }
            let box = CGRect(origin: frameDoc.origin, size: document.model.resolvedSize(of: inst))
            return docToView(box).insetBy(dx: -2, dy: -2)
        default:
            let m = nodeCullMargin(node)
            return rect.insetBy(dx: -m, dy: -m)
        }
    }

    private func drawNode(_ node: Node, offset: CGPoint, in ctx: CGContext) {
        guard let app else { return }
        // The node being inline-edited is drawn by its NSTextView overlay instead
        // (true at any nesting depth).
        if node.id == editingNodeID { return }
        let frameDoc = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        let rect = docToView(frameDoc)

        // Background blur — blur whatever is BEHIND this node, within its silhouette,
        // before anything else of the node draws. Captured from the offscreen pass
        // (ctx.makeImage is nil on the window context → no-op fallback). v1 covers
        // un-rotated, un-flipped nodes; the sampled backdrop aligns 1:1 in base space.
        if Self.backgroundBlurEnabled,
           node.rotation == 0, !node.flipH, !node.flipV,
           node.effects.contains(where: { $0.isEnabled && $0.kind == .backgroundBlur && $0.blur > 0 }),
           let backdrop = ctx.makeImage() {
            let clip = nodeSilhouette(node, frameDoc: frameDoc, rect: rect)?.clip
                ?? CGPath(rect: rect, transform: nil)
            for e in node.effects where e.isEnabled && e.kind == .backgroundBlur && e.blur > 0 {
                drawBackgroundBlur(backdrop: backdrop, rect: rect,
                                   radiusPx: CGFloat(e.blur) * app.zoom * backingScale,
                                   clip: clip, in: ctx)
            }
        }

        // Whole-layer opacity: composite the node's drawing as one group at this
        // alpha (a transparency layer, so overlapping fill+stroke don't double up).
        // Whole-layer opacity + blend mode: composite the node as one group. A
        // transparency layer captures the alpha + blend set before it and resets
        // them to normal INSIDE, so the layer composites onto the backdrop with
        // the node's blend mode (Photoshop-style).
        let groupAlpha = max(0, min(1, CGFloat(node.opacity)))
        let needsGroup = groupAlpha < 0.999 || node.blendMode != .normal
        // A node whose drawing is a SINGLE compositing operation doesn't need the
        // transparency layer at all — plain context alpha/blend composites
        // identically (the layer only exists so overlapping fill+stroke don't
        // double-darken). SVG imports produce hundreds of "filled shape,
        // 0-width stroke, per-shape opacity" nodes that all take this free path.
        let usesLayer = needsGroup && !isSinglePaintOp(node)
        if !usesLayer && needsGroup {
            ctx.saveGState()
            ctx.setAlpha(groupAlpha)
            ctx.setBlendMode(node.blendMode.cg)
        }
        defer { if !usesLayer && needsGroup { ctx.restoreGState() } }
        if usesLayer {
            ctx.saveGState()
            // Bound the layer's buffer to what this node can actually paint — the
            // same clip-before-layer rule as drop shadows. An UNCLIPPED transparency
            // layer allocates a surface the size of the current clip, which in the
            // snapshot/export path is the ENTIRE canvas: one ~screen-sized CPU
            // alloc + clear + composite per semi-transparent node (measured: ~3.3s
            // of a 3.3s capture, invisible to every content bucket because it
            // wraps them). `paintBoundsView` is conservative for every node kind —
            // leaf cull margin / recursive group union / instance viewBox — so the
            // output is pixel-identical.
            ctx.clip(to: paintBoundsView(node, offset: offset))
            ctx.setAlpha(groupAlpha)
            ctx.setBlendMode(node.blendMode.cg)
            let capT = capturingSnapshot ? CFAbsoluteTimeGetCurrent() : 0
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            if capT != 0 { capLayerMs += (CFAbsoluteTimeGetCurrent() - capT) * 1000 }
        }
        defer {
            if usesLayer {
                // The composite cost lands at END — time it into blit-layers.
                let capT = capturingSnapshot ? CFAbsoluteTimeGetCurrent() : 0
                ctx.endTransparencyLayer()
                if capT != 0 { capLayerMs += (CFAbsoluteTimeGetCurrent() - capT) * 1000 }
                ctx.restoreGState()
            }
        }

        // Rotation (degrees, clockwise about the node's center). In our flipped
        // (y-down) context a positive CTM rotation reads clockwise on screen.
        let rotating = node.rotation != 0
        let flipping = node.flipH || node.flipV
        if rotating || flipping {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            if rotating { ctx.rotate(by: CGFloat(node.rotation * .pi / 180)) }
            if flipping { ctx.scaleBy(x: node.flipH ? -1 : 1, y: node.flipV ? -1 : 1) }
            ctx.translateBy(x: -c.x, y: -c.y)
        }
        defer { if rotating || flipping { ctx.restoreGState() } }

        // Effects: dissolve masks everything the node draws (shadow casters
        // included, so a dissolved node casts a dissolved shadow); drop shadows
        // go behind the content, inner shadows on top (clipped), noise last.
        let enabled = node.effects.filter { $0.isEnabled }
        let sil = nodeSilhouette(node, frameDoc: frameDoc, rect: rect)
        let dissolves = enabled.filter { $0.kind == .dissolve && $0.amount > 0 }
        let noises = enabled.filter { $0.kind == .noise && $0.amount > 0 }
        let layerBlurs = enabled.filter { $0.kind == .layerBlur && $0.blur > 0 }
        /// Intersect the ctx's clip with each dissolve's thresholded-noise mask
        /// (tile is node-local model space, mapped onto the view-space rect).
        func applyDissolveMasks() {
            for e in dissolves {
                if let m = TurbulenceNoise.dissolveMask(for: e, size: node.frame.size) {
                    ctx.clip(to: rect, mask: m)
                }
            }
        }
        var capT0 = (capturingSnapshot && !enabled.isEmpty) ? CFAbsoluteTimeGetCurrent() : 0
        if !enabled.isEmpty {
            for e in enabled where e.kind == .dropShadow {
                if let s = sil {
                    let outset = s.path(spread: CGFloat(e.spread) * app.zoom)
                    // Knockout punches the TRUE silhouette (spread 0), not the
                    // outset — the spread ring must survive outside the object.
                    EffectsRender.drawDropShadow(e, scale: app.zoom, in: ctx,
                                                 castBounds: outset.boundingBoxOfPath,
                                                 knockout: {
                        if !dissolves.isEmpty { ctx.saveGState(); applyDissolveMasks() }
                        ctx.addPath(s.path(spread: 0)); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
                        if !dissolves.isEmpty { ctx.restoreGState() }
                    }) {
                        if !dissolves.isEmpty { ctx.saveGState(); applyDissolveMasks() }
                        ctx.addPath(outset); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
                        if !dissolves.isEmpty { ctx.restoreGState() }
                    }
                } else {
                    EffectsRender.drawDropShadow(e, scale: app.zoom, in: ctx,
                                                 castBounds: rect,
                                                 knockout: {
                        if !dissolves.isEmpty { ctx.saveGState(); applyDissolveMasks() }
                        self.drawNodeContent(node, frameDoc: frameDoc, rect: rect, in: ctx)
                        if !dissolves.isEmpty { ctx.restoreGState() }
                    }) {
                        if !dissolves.isEmpty { ctx.saveGState(); applyDissolveMasks() }
                        self.drawNodeContent(node, frameDoc: frameDoc, rect: rect, in: ctx)
                        if !dissolves.isEmpty { ctx.restoreGState() }
                    }
                }
            }
        }

        // Pause the shadow timer across the content draw (content has its own
        // image/text buckets), then resume it for the inner-shadow pass.
        if capT0 != 0 { capShadowMs += (CFAbsoluteTimeGetCurrent() - capT0) * 1000; capT0 = 0 }

        if !dissolves.isEmpty { ctx.saveGState(); applyDissolveMasks() }
        // Silhouette-less nodes (text/group/line/instance) restrict noise to the
        // node's own pixels with a transparency layer + destination-in punch, so
        // the content + noise pair must composite atomically.
        let layerNoise = !noises.isEmpty && sil == nil
        if layerNoise {
            ctx.saveGState()
            ctx.clip(to: rect.insetBy(dx: -1, dy: -1))   // bound the layer's buffer
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        if layerBlurs.isEmpty {
            drawNodeContent(node, frameDoc: frameDoc, rect: rect, in: ctx)
        } else {
            EffectsRender.drawLayerBlur(layerBlurs,
                                        bounds: paintBoundsView(node, offset: offset),
                                        deviceScale: backingScale, in: ctx) { blurContext in
                self.drawNodeContent(node, frameDoc: frameDoc, rect: rect, in: blurContext)
            }
        }

        if let s = sil {
            capT0 = capturingSnapshot ? CFAbsoluteTimeGetCurrent() : 0
            for e in enabled where e.kind == .innerShadow {
                EffectsRender.drawInnerShadow(e, clip: s.clip,
                                              hole: s.path(spread: -CGFloat(e.spread) * app.zoom),
                                              in: ctx, scale: app.zoom)
            }
            if capT0 != 0 { capShadowMs += (CFAbsoluteTimeGetCurrent() - capT0) * 1000 }
        }

        if !noises.isEmpty {
            capT0 = capturingSnapshot ? CFAbsoluteTimeGetCurrent() : 0
            for e in noises {
                EffectsRender.drawNoise(e, clip: sil?.clip, rect: rect,
                                        modelSize: node.frame.size, in: ctx)
            }
            if layerNoise {
                // Keep the noise only where the node's own pixels are: redraw
                // the content as a destination-in mask over the layer.
                ctx.setBlendMode(.destinationIn)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                drawNodeContent(node, frameDoc: frameDoc, rect: rect, in: ctx)
                ctx.endTransparencyLayer()
                ctx.setBlendMode(.normal)
            }
            if capT0 != 0 { capShadowMs += (CFAbsoluteTimeGetCurrent() - capT0) * 1000 }
        }
        if layerNoise { ctx.endTransparencyLayer(); ctx.restoreGState() }
        if !dissolves.isEmpty { ctx.restoreGState() }
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// Composite a Gaussian-blurred copy of the backdrop BEHIND a node, clipped to
    /// its silhouette — the background-blur effect. Only the node's region (plus a
    /// blur margin) is rendered, not the whole canvas, so this stays cheap during
    /// pan/zoom. Drawn in BASE canvas space (the caller guards rotation/flip).
    /// `rect` is the node's frame in view (point) space; `backdrop` is the full
    /// offscreen bitmap at backing resolution.
    private func drawBackgroundBlur(backdrop: CGImage, rect: CGRect, radiusPx: CGFloat,
                                    clip: CGPath, in ctx: CGContext) {
        let scale = backingScale
        let imgH = CGFloat(backdrop.height)
        // The node's pixel region in CIImage space (bottom-up, y-up), padded so the
        // gaussian has real neighbours and no hard cropped edge.
        let pad = radiusPx * 3 + 2
        var region = CGRect(x: rect.minX * scale,
                            y: imgH - rect.maxY * scale,
                            width: rect.width * scale,
                            height: rect.height * scale).insetBy(dx: -pad, dy: -pad)
        region = region.intersection(CGRect(x: 0, y: 0,
                                            width: CGFloat(backdrop.width), height: imgH))
        guard !region.isNull, region.width >= 1, region.height >= 1 else { return }

        let ci = CIImage(cgImage: backdrop)
        let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(max(0, radiusPx)))
        // createCGImage(from: region) renders ONLY that rectangle — the win.
        guard let out = ciContext.createCGImage(blurred, from: region) else { return }

        // Region back to view (point, top-left) space for the destination rect.
        let dest = CGRect(x: region.minX / scale,
                          y: (imgH - region.maxY) / scale,
                          width: region.width / scale,
                          height: region.height / scale)
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        // Image-node idiom, localised to the node's region.
        ctx.translateBy(x: dest.minX, y: dest.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(out, in: CGRect(origin: .zero, size: dest.size))
        ctx.restoreGState()
    }

    /// Accumulate a node's silhouette (in view space) into `path` for use as a mask
    /// clip. A group mask child contributes the union of its descendants' shapes
    /// (additive merge). Falls back to the frame rect for content with no outline.
    /// Each node's own rotation/flip (about its center) is baked into the path and
    /// composed with ancestor transforms via `base`, matching how `drawNode` applies
    /// the CTM — so a rotated/flipped mask shape clips where it actually appears.
    /// (The mask GROUP's own rotation is already the active CTM when the clip runs.)
    private func appendSilhouette(of node: Node, offset: CGPoint,
                                  base: CGAffineTransform, into path: CGMutablePath) {
        let fd = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        let r = docToView(fd)
        let c = CGPoint(x: r.midX, y: r.midY)
        var t = CGAffineTransform.identity.translatedBy(x: c.x, y: c.y)
        if node.rotation != 0 { t = t.rotated(by: CGFloat(node.rotation * .pi / 180)) }
        if node.flipH || node.flipV { t = t.scaledBy(x: node.flipH ? -1 : 1, y: node.flipV ? -1 : 1) }
        t = t.translatedBy(x: -c.x, y: -c.y)
        let combined = t.concatenating(base)
        if case .group(let kids) = node.content {
            let off = CGPoint(x: fd.minX, y: fd.minY)
            for k in kids where k.isVisible { appendSilhouette(of: k, offset: off, base: combined, into: path) }
        } else if let s = nodeSilhouette(node, frameDoc: fd, rect: r) {
            path.addPath(s.clip, transform: combined)
        } else {
            path.addPath(CGPath(rect: r, transform: nil), transform: combined)
        }
    }

    /// Dashed accent outline of a mask shape, shown only while the mask is being
    /// edited so the (otherwise invisible) clip boundary is grabbable.
    private func drawMaskOutline(of node: Node, offset: CGPoint, in ctx: CGContext) {
        let p = CGMutablePath()
        appendSilhouette(of: node, offset: offset, base: .identity, into: p)
        ctx.saveGState()
        ctx.addPath(p)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// True when a mask group or any of its descendants is selected — i.e. the user
    /// is working inside it, so we should reveal the clip boundary.
    private func maskEditingActive(_ mask: Node) -> Bool {
        guard let app else { return false }
        if app.selectedNodeIDs.contains(mask.id) { return true }
        var found = false
        func scan(_ nodes: [Node]) {
            for n in nodes {
                if app.selectedNodeIDs.contains(n.id) { found = true; return }
                if case .group(let k) = n.content { scan(k) }
            }
        }
        if case .group(let kids) = mask.content { scan(kids) }
        return found
    }

    /// The shadow silhouette for a node in view space (nil for content that has no
    /// fillable outline — text, lines, open/partial paths, groups, instances —
    /// which fall back to a content-stamp drop shadow and skip inner shadow).
    private func nodeSilhouette(_ node: Node, frameDoc: CGRect, rect: CGRect) -> Silhouette? {
        guard let app else { return nil }
        switch node.content {
        case .rectangle(let s):
            // Uniform and per-corner rectangles must share the CSS overlap rule.
            // AppKit's roundedRect accepts an oversized uniform radius but turns
            // a capsule into a stretched oval instead of clamping it.
            return Silhouette(rect: rect,
                              shape: .perCornerRect(s.effectiveRadii.scaled(by: app.zoom)))
        case .ellipse:          return Silhouette(rect: rect, shape: .oval)
        case .polygon(let s):   return Silhouette(rect: rect, shape: .custom(Self.polygonBezier(s.vertices(in: rect)).cgPath))
        case .path(let ps) where ps.closed && ps.points.count >= 2:
            return Silhouette(rect: rect, shape: .custom(bezierPath(for: ps, frameOrigin: frameDoc.origin).cgPath))
        case .image:            return Silhouette(rect: rect, shape: .roundRect(radius: 0))
        default: return nil
        }
    }

    private func drawNodeContent(_ node: Node, frameDoc: CGRect, rect: CGRect, in ctx: CGContext) {
        guard let app else { return }
        // Capture instrumentation: time LEAF shape drawing (rect/oval/polygon/
        // line/path). Groups + instances recurse (their children time themselves);
        // image + text have their own buckets at their cases.
        let capLeafT: CFAbsoluteTime
        switch node.content {
        case .group, .instance, .image, .text: capLeafT = 0
        default: capLeafT = capturingSnapshot ? CFAbsoluteTimeGetCurrent() : 0
        }
        defer { if capLeafT != 0 { capShapeMs += (CFAbsoluteTimeGetCurrent() - capLeafT) * 1000 } }
        switch node.content {
        case .rectangle(let shape):
            // The shared builder normalizes both uniform and per-corner radii
            // exactly as Convert to Path does.
            let path = NSBezierPath(
                cgPath: shape.effectiveRadii.path(in: rect, scale: app.zoom))
            PaintRender.fill(shape.fill, path: path, bounds: rect, in: ctx)
            if shape.strokeWidth > 0 {
                PaintRender.strokeAligned(path, width: shape.strokeWidth * app.zoom,
                                          alignment: shape.strokeAlignment,
                                          color: shape.stroke.nsColor,
                                          pattern: shape.strokePattern, in: ctx)
            }
        case .ellipse(let shape):
            let path = NSBezierPath(ovalIn: rect)
            PaintRender.fill(shape.fill, path: path, bounds: rect, in: ctx)
            if shape.strokeWidth > 0 {
                PaintRender.strokeAligned(path, width: shape.strokeWidth * app.zoom,
                                          alignment: shape.strokeAlignment,
                                          color: shape.stroke.nsColor,
                                          pattern: shape.strokePattern, in: ctx)
            }
        case .polygon(let shape):
            let path = Self.polygonBezier(shape.vertices(in: rect))
            PaintRender.fill(shape.fill, path: path, bounds: rect, in: ctx)
            if shape.strokeWidth > 0 {
                PaintRender.strokeAligned(path, width: shape.strokeWidth * app.zoom,
                                          alignment: shape.strokeAlignment,
                                          color: shape.stroke.nsColor,
                                          join: .miter, pattern: shape.strokePattern, in: ctx)
            }
        case .line(let ls):
            let a = docToViewPoint(CGPoint(x: frameDoc.minX + ls.start.x, y: frameDoc.minY + ls.start.y))
            let b = docToViewPoint(CGPoint(x: frameDoc.minX + ls.end.x,   y: frameDoc.minY + ls.end.y))
            let renderedWidth = max(1, ls.strokeWidth * app.zoom)
            ctx.saveGState()
            ls.stroke.nsColor.setStroke()
            ctx.setLineWidth(renderedWidth)
            PaintRender.configureStrokePattern(ls.strokePattern,
                                               width: renderedWidth,
                                               fallbackCap: ls.strokeCap.cgLineCap, in: ctx)
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
            ctx.restoreGState()
            PaintRender.drawMarker(ls.startMarker, endpoint: a, interior: b,
                                   strokeWidth: renderedWidth, color: ls.stroke.nsColor, in: ctx)
            PaintRender.drawMarker(ls.endMarker, endpoint: b, interior: a,
                                   strokeWidth: renderedWidth, color: ls.stroke.nsColor, in: ctx)
        case .path(let ps):
            guard !ps.renderContours.isEmpty else { break }
            let bez = bezierPath(for: ps, frameOrigin: frameDoc.origin)
            if ps.isMultiContour || (ps.closed && ps.points.count >= 2) {
                PaintRender.fill(ps.fill, path: bez, bounds: bez.bounds, in: ctx)
            }
            if ps.strokeWidth > 0 {
                PaintRender.strokeAligned(bez, width: ps.strokeWidth * app.zoom,
                                          alignment: ps.effectiveStrokeAlignment,
                                          color: ps.stroke.nsColor,
                                          join: .round, cap: ps.strokeCap.cgLineCap,
                                          pattern: ps.strokePattern, in: ctx)
            }
            if ps.strokeWidth > 0, let tangents = ps.endpointTangents {
                let pointInView: (CGPoint) -> CGPoint = { point in
                    self.docToViewPoint(CGPoint(x: frameDoc.minX + point.x, y: frameDoc.minY + point.y))
                }
                let renderedWidth = ps.strokeWidth * app.zoom
                PaintRender.drawMarker(ps.startMarker,
                                       endpoint: pointInView(tangents.start.tip),
                                       interior: pointInView(tangents.start.interior),
                                       strokeWidth: renderedWidth, color: ps.stroke.nsColor, in: ctx)
                PaintRender.drawMarker(ps.endMarker,
                                       endpoint: pointInView(tangents.end.tip),
                                       interior: pointInView(tangents.end.interior),
                                       strokeWidth: renderedWidth, color: ps.stroke.nsColor, in: ctx)
            }
        case .text(let text):
            // Lay the text out at TRUE size and scale the drawing, so wrapping and
            // line height are identical at every zoom (no per-zoom reflow). draw(in:)
            // clips to the box, which is the crop for a fixed/paragraph box.
            let capT = capturingSnapshot ? CFAbsoluteTimeGetCurrent() : 0
            ctx.saveGState()
            ctx.translateBy(x: rect.minX, y: rect.minY)
            ctx.scaleBy(x: app.zoom, y: app.zoom)
            drawText(text, nodeID: node.id, in: CGRect(origin: .zero, size: frameDoc.size))
            ctx.restoreGState()
            if capT != 0 { capTextMs += (CFAbsoluteTimeGetCurrent() - capT) * 1000 }
            // Overflow ("more text than fits") badge for fixed boxes. Ask the
            // SAME TextKit layout that drew the layer whether any meaningful
            // characters were excluded; a separate height estimate produced
            // false positives for tight line boxes and fonts with deep leading.
            if text.box == .fixed,
               textOverflows(text, nodeID: node.id, in: frameDoc.size) {
                drawTextOverflowBadge(at: rect, in: ctx)
            }
        case .group(let children):
            // An auto-padding frame's background (fill/corner/stroke) is drawn at the
            // PADDING box — the frame inset by the margin — behind the children.
            if let pad = node.autoPadding, pad.fill != nil || pad.strokeWidth > 0 {
                let z = app.zoom
                let box = CGRect(x: rect.minX + pad.marginLeft * z, y: rect.minY + pad.marginTop * z,
                                 width: max(0, rect.width - pad.marginW * z),
                                 height: max(0, rect.height - pad.marginH * z))
                let radius = pad.cornerRadius * z
                let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
                if let fill = pad.fill { PaintRender.fill(fill, path: path, bounds: box, in: ctx) }
                if pad.strokeWidth > 0, let stroke = pad.stroke {
                    PaintRender.strokeAligned(path, width: pad.strokeWidth * z,
                                              alignment: pad.strokeAlignment,
                                              color: stroke.nsColor,
                                              pattern: pad.strokePattern, in: ctx)
                }
            }
            let childOffset = CGPoint(x: frameDoc.minX, y: frameDoc.minY)
            if node.isMask {
                // MASK group: clip the content children to the union of the mask
                // shape(s)' silhouettes (a group mask child = its merged descendants,
                // additive). Mask shapes aren't drawn as fill — they only clip.
                let clip = CGMutablePath()
                for child in children where child.isMaskShape && child.isVisible {
                    appendSilhouette(of: child, offset: childOffset, base: .identity, into: clip)
                }
                ctx.saveGState()
                if !clip.isEmpty { ctx.addPath(clip); ctx.clip() }
                for child in children where !child.isMaskShape && child.isVisible {
                    drawNode(child, offset: childOffset, in: ctx)
                }
                ctx.restoreGState()
                // While editing the mask (it or a descendant is selected), show the
                // clip boundary so the mask shape is visible/grabbable.
                if maskEditingActive(node) {
                    for child in children where child.isMaskShape && child.isVisible {
                        drawMaskOutline(of: child, offset: childOffset, in: ctx)
                    }
                }
            } else {
                for child in children where child.isVisible {
                    drawNode(child, offset: childOffset, in: ctx)
                }
            }
        case .instance(let inst):
            // Resolve the source (overrides + visibility + auto layout) and draw its
            // children at this instance's origin — a reference, never a copy. The
            // resolve re-hugs auto-padding/layout frames for this instance's overrides.
            guard let document else { break }
            let childOffset = CGPoint(x: frameDoc.minX, y: frameDoc.minY)
            // Crop to the component's viewBox (SVG / artboard semantics): content
            // outside the bounds doesn't show in a placement. The source EDITOR draws
            // its content directly (not via this path), so it stays unclipped — you can
            // still see and drag elements that sit outside the box while editing.
            let box = CGRect(origin: frameDoc.origin, size: document.model.resolvedSize(of: inst))
            ctx.saveGState()
            ctx.clip(to: docToView(box))
            for child in resolvedChildrenCached(for: node, inst) {
                drawNode(child, offset: childOffset, in: ctx)
            }
            ctx.restoreGState()
        case .image(let img):
            let capT = capturingSnapshot ? CFAbsoluteTimeGetCurrent() : 0
            // Ask for a variant sized to the VISIBLE portion, not the placed
            // image's full frame. Large stock photos are often cropped by the
            // viewport/artboard; sizing from the full rect made snapshot captures
            // decode/draw 2K–8K variants for a few hundred visible pixels.
            let renderRegion = currentRenderRegion ?? bounds
            let visibleRect = rect.intersection(renderRegion)
            let sampleRect = visibleRect.isNull || visibleRect.isEmpty ? rect : visibleRect
            let targetPx = max(sampleRect.width, sampleRect.height) * backingScale
            if let cg = cgImage(for: img, targetPx: targetPx) {
                // The context is y-down (flipped view); CGImage draws y-up, so flip
                // within the node's rect before drawing.
                ctx.saveGState()
                ctx.interpolationQuality = capturingSnapshot ? .medium : .high
                ctx.translateBy(x: rect.minX, y: rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
                ctx.restoreGState()
            }
            if capT != 0 { capImageMs += (CFAbsoluteTimeGetCurrent() - capT) * 1000 }
        }
    }

    // Per-instance resolution cache. Resolving an instance (apply overrides + reflow
    // auto-layout) is one of the heaviest things a frame does, and pan/zoom redraw
    // every visible instance every frame for ZERO model change. We cache the resolved
    // children by the instance node's id, valid for one `resolveGeneration`: any edit
    // bumps the generation and clears the cache, so a hit is never stale.
    private var instanceResolveCache: [UUID: [Node]] = [:]
    private var instanceResolveGen: Int = -1
    private var instanceTopLevelIDs: Set<UUID> = []

    // Testing Mode instrumentation (see PerfMeter). All near-free when disabled.
    let perf = PerfMeter()
    private var perfCacheHit = 0
    private var perfCacheMiss = 0

    /// `resolvedChildren(of:)` with a redraw-spanning cache. Only TOP-LEVEL instance
    /// nodes are cached: their ids are unique. A nested instance reuses its source
    /// layer's id, which is shared across every placement of that component, so
    /// caching nested resolves by id would collide between placements — those fall
    /// through to a fresh (correct) resolve.
    /// True while a canvas gesture is mutating the model every mouse tick. Those
    /// mid-gesture bumps are FRAME-ONLY mutations (move/resize/draw change node
    /// frames), and `resolvedChildren(of:)` reads sources + overrides, never
    /// frames — so caches keyed on resolveGeneration stay exact through a drag.
    /// Clearing them anyway made a group drag re-resolve every instance every
    /// frame (measured: 60ms frames → 320ms). Anything that CAN change a resolve
    /// (override edits, source edits, undo, paste) happens outside a drag, where
    /// the normal generation clear still runs.
    private var frameOnlyGestureActive: Bool {
        if case .none = dragMode { return false }
        return true
    }

    private func resolvedChildrenCached(for node: Node, _ inst: ComponentInstance) -> [Node] {
        guard let document else { return [] }
        if document.resolveGeneration != instanceResolveGen {
            if frameOnlyGestureActive, instanceResolveGen != -1 {
                instanceResolveGen = document.resolveGeneration   // keep the warm cache
            } else {
                instanceResolveCache.removeAll(keepingCapacity: true)
                instanceResolveGen = document.resolveGeneration
                instanceTopLevelIDs = Set(currentNodes.map(\.id))
            }
        }
        guard instanceTopLevelIDs.contains(node.id) else {
            return document.model.resolvedChildren(of: inst)
        }
        if let hit = instanceResolveCache[node.id] { perfCacheHit += 1; return hit }
        perfCacheMiss += 1
        let resolved = document.model.resolvedChildren(of: inst)
        instanceResolveCache[node.id] = resolved
        return resolved
    }

    /// Decoded-image cache with DOWNSAMPLED variants ("mips"), keyed by
    /// image-data hash + size bucket. Drawing a 4000px photo into a 200px frame
    /// used to resample the FULL bitmap every frame; now each draw pulls a
    /// pre-decoded variant no bigger than ~2× the pixels it actually covers on
    /// screen. `kCGImageSourceShouldCacheImmediately` force-decodes once at
    /// creation (the old NSImage path could re-decode lazily on draw). NSCache
    /// evicts by memory cost, so image-heavy documents stay bounded.
    /// NOTE: canvas-only. Export renders its own full-resolution path.
    private lazy var imageCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 256 << 20   // ~256 MB of decoded pixels
        return cache
    }()

    /// `NSCache` may evict an entry at any time, including immediately when a
    /// large screenshot mip approaches the cache's cost limit. Keep the exact mips
    /// used by the most recent full render strongly referenced. Without this, an
    /// idle redraw can fall back to the 256px placeholder, schedule the same large
    /// decode again, briefly draw sharp, get evicted, and repeat forever — visible
    /// as sharp/soft cycling and sustained CPU while nothing is moving.
    private var residentImageMips: [String: CGImage] = [:]
    private var imageMipKeysUsedInRender: Set<String>?
    private var latestImageMipKeys: Set<String> = []
    /// Avoid minting separate 4K/8K cache entries that both decode to the same
    /// smaller source image. Header dimensions are tiny metadata and stable for
    /// the immutable `ImageContent.data` payload.
    private var imageMaxPixelCache: [Int: CGFloat] = [:]

    /// CGImage is an immutable, thread-safe CF object; the box just tells Swift
    /// concurrency it may cross from the decode queue to the main actor.
    private final class UncheckedBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }
    private let imageDecodeQueue = DispatchQueue(label: "exp.image-decode",
                                                 qos: .userInitiated,
                                                 attributes: .concurrent)
    private var imageDecodesInFlight: Set<String> = []   // main-thread only

    private func cgImage(for img: ImageContent, targetPx: CGFloat) -> CGImage? {
        let imageID = img.data.hashValue
        let sourceMaxPx: CGFloat = {
            if let cached = imageMaxPixelCache[imageID] { return cached }
            let size = Self.imagePixelDimensions(img.data)
            let value = size.map { max($0.width, $0.height) } ?? targetPx
            imageMaxPixelCache[imageID] = value
            return value
        }()
        // Power-of-two buckets so zooming doesn't mint a variant per pixel step.
        // Clamp to the source size BEFORE bucketing: ImageIO does not upscale, but
        // storing the same source bitmap under several oversized keys is not free.
        let requiredPx = min(targetPx, sourceMaxPx)
        var bucket: CGFloat = 128
        while bucket < requiredPx && bucket < 8192 { bucket *= 2 }
        let keyString = "\(imageID)-\(Int(bucket))"
        let key = keyString as NSString
        imageMipKeysUsedInRender?.insert(keyString)
        if let resident = residentImageMips[keyString] { return resident }
        if let hit = imageCache.object(forKey: key) {
            residentImageMips[keyString] = hit
            return hit
        }

        // Nearest ALREADY-CACHED bucket (larger first — stays sharp; then smaller
        // — briefly soft). If one exists, draw it NOW and decode the right bucket
        // in the background: zoom-crossing re-decodes measured 46–248ms on the
        // main thread (blit-images spikes) — the dominant remaining stall on
        // image-heavy documents. A soft frame beats a frozen one.
        var fallback: CGImage?
        var fallbackKeyUsed: String?
        var b = bucket * 2
        while b <= 8192, fallback == nil {
            let fallbackKey = "\(imageID)-\(Int(b))"
            fallback = residentImageMips[fallbackKey]
                ?? imageCache.object(forKey: fallbackKey as NSString)
            if fallback != nil { fallbackKeyUsed = fallbackKey }
            b *= 2
        }
        b = bucket / 2
        while b >= 128, fallback == nil {
            let fallbackKey = "\(imageID)-\(Int(b))"
            fallback = residentImageMips[fallbackKey]
                ?? imageCache.object(forKey: fallbackKey as NSString)
            if fallback != nil { fallbackKeyUsed = fallbackKey }
            b /= 2
        }
        if let fallbackKeyUsed { imageMipKeysUsedInRender?.insert(fallbackKeyUsed) }

        if fallback == nil {
            let imagePixels = Self.imagePixelDimensions(img.data).map { $0.width * $0.height } ?? .greatestFiniteMagnitude
            if imagePixels <= 6_000_000 || bucket <= 1024 {
                guard let cg = Self.decodeImage(img.data, maxPx: bucket) else { return nil }
                imageCache.setObject(cg, forKey: key, cost: cg.bytesPerRow * cg.height)
                residentImageMips[keyString] = cg
                return cg
            }
            // First-ever appearance (nothing cached at any size). Decoding the
            // FULL bucket here measured 43–200ms per image when panning into
            // fresh territory — so decode only a small placeholder now (a few
            // ms even for huge photos; never blank), and let the async path
            // below fetch the real size.
            let placeholderPx: CGFloat = 256
            if bucket <= placeholderPx {
                guard let cg = Self.decodeImage(img.data, maxPx: bucket) else { return nil }
                imageCache.setObject(cg, forKey: key, cost: cg.bytesPerRow * cg.height)
                residentImageMips[keyString] = cg
                return cg
            }
            guard let small = Self.decodeImage(img.data, maxPx: placeholderPx) else { return nil }
            let smallKey = "\(imageID)-\(Int(placeholderPx))" as NSString
            imageCache.setObject(small, forKey: smallKey, cost: small.bytesPerRow * small.height)
            fallback = small
        }

        if !imageDecodesInFlight.contains(keyString) {
            imageDecodesInFlight.insert(keyString)
            let data = img.data
            imageDecodeQueue.async {
                let boxed = Self.decodeImage(data, maxPx: bucket).map(UncheckedBox.init)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.imageDecodesInFlight.remove(keyString)
                    if let boxed {
                        self.imageCache.setObject(boxed.value, forKey: keyString as NSString,
                                                  cost: boxed.value.bytesPerRow * boxed.value.height)
                        if self.latestImageMipKeys.contains(keyString) {
                            self.residentImageMips[keyString] = boxed.value
                        }
                        self.needsDisplay = true   // redraw sharp once it lands
                    }
                }
            }
        }
        return fallback
    }

    /// One ImageIO thumbnail decode — pure function, safe off the main thread
    /// (each call builds its own CGImageSource).
    private nonisolated static func decodeImage(_ data: Data, maxPx: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPx,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honor EXIF orientation
            kCGImageSourceShouldCacheImmediately: true          // decode NOW, once
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private nonisolated static func imagePixelDimensions(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = props[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func pngData(from ns: NSImage) -> Data? {
        guard let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    // Text layout cache: building an NSTextStorage + NSLayoutManager +
    // NSTextContainer per text node per FRAME was pure waste — the layout only
    // depends on content + box size, never on zoom (drawing scales the ctx).
    // Keyed by node id, validated by a content fingerprint (covers per-instance
    // text/fill overrides on resolved children that share source-layer ids),
    // cleared on any model edit via resolveGeneration — the instance-cache pattern.
    private struct TextLayoutEntry {
        let storage: NSTextStorage      // retained: the layout manager needs it alive
        let layout: NSLayoutManager
        let fingerprint: Int
    }
    private var textLayoutCache: [UUID: TextLayoutEntry] = [:]
    private var textLayoutGen: Int = -1

    private func textFingerprint(_ t: TextContent, _ size: CGSize) -> Int {
        var h = Hasher()
        h.combine(size.width); h.combine(size.height)
        h.combine(t.align.rawValue); h.combine(t.lineHeight)
        h.combine(t.lineHeightUnit.rawValue); h.combine(t.tracking)
        h.combine(t.centersFixedLineHeightLeading)
        h.combine(t.box.rawValue); h.combine(t.textCase.rawValue)
        for run in t.runs {
            h.combine(run.string); h.combine(run.fontName); h.combine(run.fontSize)
            h.combine(run.color.r); h.combine(run.color.g)
            h.combine(run.color.b); h.combine(run.color.a)
            h.combine(run.underline)
        }
        return h.finalize()
    }

    private func textLayoutEntry(_ text: TextContent, nodeID: UUID,
                                 size: CGSize) -> TextLayoutEntry {
        if let document, document.resolveGeneration != textLayoutGen {
            // Entries self-validate via the fingerprint, so mid-drag generation
            // bumps (frame-only mutations) don't need the clear — without this,
            // every drag tick re-laid-out every visible text layer. The clear's
            // real job is pruning deleted nodes, which can't happen mid-gesture.
            if !frameOnlyGestureActive || textLayoutGen == -1 {
                textLayoutCache.removeAll(keepingCapacity: true)
            }
            textLayoutGen = document.resolveGeneration
        }
        let fp = textFingerprint(text, size)
        if let hit = textLayoutCache[nodeID], hit.fingerprint == fp {
            return hit
        }
        let storage = NSTextStorage(attributedString: text.attributedString(scale: 1))
        let layout = NSLayoutManager()
        layout.usesFontLeading = true
        let container = NSTextContainer(containerSize: size)
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let entry = TextLayoutEntry(storage: storage, layout: layout, fingerprint: fp)
        textLayoutCache[nodeID] = entry
        return entry
    }

    private func drawText(_ text: TextContent, nodeID: UUID, in rect: CGRect) {
        let entry = textLayoutEntry(text, nodeID: nodeID, size: rect.size)
        guard let container = entry.layout.textContainers.first else { return }
        let glyphRange = entry.layout.glyphRange(for: container)
        entry.layout.drawBackground(forGlyphRange: glyphRange, at: rect.origin)
        entry.layout.drawGlyphs(forGlyphRange: glyphRange, at: rect.origin)
    }

    /// True only when the finite TextKit container omitted visible content.
    /// Line-fragment leading, descender space, and trailing whitespace are not
    /// "more text," so none of them can light the red plus badge.
    private func textOverflows(_ text: TextContent, nodeID: UUID,
                               in size: CGSize) -> Bool {
        guard !text.isEmpty else { return false }
        let entry = textLayoutEntry(text, nodeID: nodeID, size: size)
        guard let container = entry.layout.textContainers.first else { return false }
        let glyphRange = entry.layout.glyphRange(for: container)
        let characterRange = entry.layout.characterRange(
            forGlyphRange: glyphRange, actualGlyphRange: nil)
        let end = min(entry.storage.length, NSMaxRange(characterRange))
        guard end < entry.storage.length else { return false }
        let remainder = (entry.storage.string as NSString).substring(
            with: NSRange(location: end, length: entry.storage.length - end))
        return remainder.rangeOfCharacter(
            from: CharacterSet.whitespacesAndNewlines.inverted) != nil
    }

    private func drawNodeSelection(_ node: Node, offset: CGPoint = .zero, ctx: CGContext, handles: Bool) {
        let absFrame = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        let chain = ancestorGroups(of: node.id)
        // Lines: highlight the segment + two endpoint handles (no bounding box).
        // Endpoints map through the node's own rotation AND any ancestor rotation.
        if case .line(let ls) = node.content {
            let av = nodeLocalToView(ls.start, node, chain: chain)
            let bv = nodeLocalToView(ls.end, node, chain: chain)
            ctx.saveGState()
            NSColor.controlAccentColor.setStroke()
            ctx.setLineWidth(1)
            ctx.move(to: av)
            ctx.addLine(to: bv)
            ctx.strokePath()
            ctx.restoreGState()
            if handles {
                drawHandleBox(centeredAt: av, in: ctx)
                drawHandleBox(centeredAt: bv, in: ctx)
            }
            return
        }

        // If an ancestor group is rotated OR flipped, the node is drawn
        // transformed with it — draw the selection box as a transformed quad
        // where the shape actually appears (parentLocalToDoc carries both the
        // rotation and the flip mirror), with handles + knob at their mapped
        // positions so the node stays resizable/rotatable inside the group.
        if chain.contains(where: { $0.rotation != 0 || $0.flipH || $0.flipV }) {
            perf.measure("sel-transformed-box") {
                drawTransformedSelectionBox(node, chain: chain, in: ctx, handles: handles)
            }
            return
        }

        // A group's stored frame can lag its contents (e.g. after a child is dragged
        // in via the Layers panel). Draw the box around the live union of its
        // descendants so the selection always matches what's on screen. EXCEPTION:
        // an auto-layout / auto-padding FRAME keeps its frame accurate (and the
        // padded frame is larger than its content), so use the stored frame there.
        var boxFrame = absFrame
        if case .group = node.content, node.rotation == 0,
           node.autoLayout == nil, node.autoPadding == nil,
           let cb = perf.measure("sel-group-bounds", {
               groupContentBounds(node, parentOffset: offset)
           }) {
            // The group's own flip mirrors its children about ITS center — the
            // live content union must mirror the same way to sit on the ink.
            var mirrored = cb
            if node.flipH { mirrored.origin.x = 2 * absFrame.midX - cb.maxX }
            if node.flipV { mirrored.origin.y = 2 * absFrame.midY - cb.maxY }
            boxFrame = mirrored
        }
        // An instance's box follows its RESOLVED size (re-hugged for its overrides).
        if case .instance(let inst) = node.content, node.rotation == 0,
           let size = document?.model.resolvedSize(of: inst), size.width > 0 {
            boxFrame = CGRect(origin: absFrame.origin, size: size)
        }

        let rect = docToView(boxFrame)
        // BUG-036(a): the accent box and its handles sit on the INK — geometry plus
        // whatever an outside or centre stroke paints past it — so the visible edge of
        // the art is never outside the box that claims to bound it. Everything else
        // below (auto-padding bands, instance chrome, the path outline trace) stays on
        // the geometry `rect`, because those describe layout, not paint.
        let inkRect = docToView(SelectionTransform.outset(boxFrame,
                                                          by: SelectionTransform.inkInsets(of: node)))
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Everything below draws inside the node's rotation, so the box, outline,
        // handles, and rotate knob all sit on the rotated shape.
        ctx.saveGState()
        if node.rotation != 0 {
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: CGFloat(node.rotation * .pi / 180))
            ctx.translateBy(x: -center.x, y: -center.y)
        }
        defer { ctx.restoreGState() }

        // Paths also trace their actual outline (clearer than just a box), then
        // fall through to the box + handles so they're resizable/rotatable too.
        if case .path(let ps) = node.content {
            if perf.enabled { perf.gauge("selectedPathPts", ps.points.count) }
            perf.measure("sel-path-outline") {
                let bez = bezierPath(for: ps, frameOrigin: absFrame.origin)
                ctx.saveGState()
                // Mirror the trace to match a flipped path (flip is applied INSIDE the
                // rotation above, matching the renderer). The box/handles are symmetric,
                // so only the outline needs this.
                if node.flipH || node.flipV {
                    ctx.translateBy(x: center.x, y: center.y)
                    ctx.scaleBy(x: node.flipH ? -1 : 1, y: node.flipV ? -1 : 1)
                    ctx.translateBy(x: -center.x, y: -center.y)
                }
                NSColor.controlAccentColor.setStroke()
                bez.lineWidth = 1
                bez.stroke()
                ctx.restoreGState()
            }
        }

        // Auto-padding overlay: shade the MARGIN band (frame → background box) and
        // the PADDING band (background box → content) in distinct colors, so both are
        // visible and update live as the values change.
        if let pad = node.autoPadding, let app {
            perf.measure("sel-autopad") {
                let z = app.zoom
                // Background (padding) box = frame inset by the margin.
                let box = CGRect(x: rect.minX + pad.marginLeft * z, y: rect.minY + pad.marginTop * z,
                                 width: max(0, rect.width - pad.marginW * z),
                                 height: max(0, rect.height - pad.marginH * z))
                // Content box = padding box inset by the padding.
                let content = CGRect(x: box.minX + pad.paddingLeft * z, y: box.minY + pad.paddingTop * z,
                                     width: max(0, box.width - (pad.paddingLeft + pad.paddingRight) * z),
                                     height: max(0, box.height - (pad.paddingTop + pad.paddingBottom) * z))
                func band(_ outer: CGRect, _ inner: CGRect, _ color: NSColor) {
                    ctx.saveGState()
                    let p = CGMutablePath(); p.addRect(outer); p.addRect(inner); ctx.addPath(p)
                    color.setFill(); ctx.drawPath(using: .eoFill)
                    ctx.restoreGState()
                }
                if pad.marginW > 0 || pad.marginH > 0 {
                    band(rect, box, NSColor.systemOrange.withAlphaComponent(0.18))   // margin
                }
                band(box, content, NSColor.systemTeal.withAlphaComponent(0.22))       // padding
                ctx.saveGState()
                NSColor.systemTeal.withAlphaComponent(0.85).setStroke()
                ctx.setLineWidth(1); ctx.setLineDash(phase: 0, lengths: [3, 3])
                ctx.stroke(content)
                ctx.restoreGState()
            }
        }

        // Bounding-box outline (optional — View ▸ Show Selection Bounds). Component
        // instances get PURPLE double-outline chrome + a top label bar (icon ·
        // Name — State · state dropdown) instead of the plain accent box, so a
        // component reads unmistakably as a component and its state is switchable
        // right on the canvas.
        if app?.showSelectionBounds ?? true {
            perf.measure("sel-bounds") {
                if case .instance(let inst) = node.content,
                   let source = document?.model.source(for: inst.sourceID) {
                    drawInstanceChrome(rect: rect, inst: inst, source: source, in: ctx)
                } else {
                    ctx.saveGState()
                    NSColor.controlAccentColor.setStroke()
                    ctx.setLineWidth(1.5)
                    ctx.stroke(inkRect)
                    ctx.restoreGState()
                }
            }
        }

        // Eight resize handles. Rotation is available in the invisible outside-
        // corner regions, communicated by the rotate cursor rather than a notch.
        guard handles, isBoxResizable(node) else { return }
        perf.measure("sel-handles") {
            for handle in Handle.allCases {
                drawHandleBox(centeredAt: handlePoint(handle, in: inkRect), in: ctx)
            }
        }
    }

    // MARK: Component instance chrome (purple double outline + state dropdown)

    /// Represented object for the component-state menu items (which instance node,
    /// which source state — nil = base/default).
    private final class InstanceStateChoice: NSObject {
        let nodeID: UUID
        let stateID: UUID?
        init(nodeID: UUID, stateID: UUID?) { self.nodeID = nodeID; self.stateID = stateID }
    }

    /// "Name — State" shown on the instance's label bar.
    private func instanceLabelText(_ inst: ComponentInstance, _ source: ComponentSource) -> String {
        let state = inst.activeStateID.flatMap { id in source.states.first { $0.id == id } }?.name ?? "default"
        return "\(source.name) \u{2014} \(state)"
    }

    /// The label bar's view-space rect (sits just above the selection box). Sized
    /// to its content and allowed to overhang a narrow instance, Figma-style.
    private func instanceChromeBarRect(for rect: CGRect, text: String) -> CGRect {
        let h: CGFloat = 17
        let textW = (text as NSString).size(withAttributes:
            [.font: NSFont.systemFont(ofSize: 10, weight: .medium)]).width
        // padL 6 + icon 14 + gap 4 + text + gap 4 + chevron 14 + padR 6 = text + 48
        return CGRect(x: rect.minX, y: rect.minY - h - 3, width: ceil(textW) + 48, height: h)
    }

    /// The dropdown chevron's rect within the label bar (right end).
    private func instanceChevronRect(inBar bar: CGRect) -> CGRect {
        CGRect(x: bar.maxX - 6 - 14, y: bar.minY, width: 14, height: bar.height)
    }

    /// Draw an SF Symbol tinted white, centered (natural size) in `box`.
    private func drawWhiteSymbol(_ name: String, pointSize: CGFloat, centeredIn box: CGRect) {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return }
        let s = img.size
        img.draw(in: CGRect(x: box.midX - s.width / 2, y: box.midY - s.height / 2,
                            width: s.width, height: s.height))
    }

    /// Purple double-outline + top label bar for a selected component instance.
    private func drawInstanceChrome(rect: CGRect, inst: ComponentInstance,
                                    source: ComponentSource, in ctx: CGContext) {
        let purple = NSColor.systemPurple
        ctx.saveGState()
        purple.setStroke()
        ctx.setLineWidth(1.5); ctx.stroke(rect)
        ctx.setLineWidth(1);   ctx.stroke(rect.insetBy(dx: 2.5, dy: 2.5))
        ctx.restoreGState()

        let text = instanceLabelText(inst, source)
        let bar = instanceChromeBarRect(for: rect, text: text)
        ctx.saveGState()
        purple.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
        drawWhiteSymbol("rectangle.3.group", pointSize: 10,
                        centeredIn: CGRect(x: bar.minX + 6, y: bar.minY, width: 14, height: bar.height))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        (text as NSString).draw(at: CGPoint(x: bar.minX + 24, y: bar.midY - 6), withAttributes: attrs)
        drawWhiteSymbol("chevron.down", pointSize: 8, centeredIn: instanceChevronRect(inBar: bar))
        ctx.restoreGState()
    }

    /// The single selected component instance + its view-space box, or nil.
    private func selectedInstanceForChrome()
        -> (node: Node, inst: ComponentInstance, source: ComponentSource, rect: CGRect)? {
        guard let app, let document, let id = app.singleSelectedNodeID, let n = node(id),
              n.rotation == 0, case .instance(let inst) = n.content,
              let source = document.model.source(for: inst.sourceID) else { return nil }
        var boxFrame = n.frame
        let size = document.model.resolvedSize(of: inst)
        if size.width > 0 { boxFrame = CGRect(origin: n.frame.origin, size: size) }
        return (n, inst, source, docToView(boxFrame))
    }

    /// If the click landed on the selected instance's dropdown chevron, open the
    /// state menu and report handled.
    private func presentInstanceStateMenuIfHit(at p: CGPoint) -> Bool {
        guard app?.showSelectionBounds ?? true, let sel = selectedInstanceForChrome() else { return false }
        let bar = instanceChromeBarRect(for: sel.rect, text: instanceLabelText(sel.inst, sel.source))
        guard instanceChevronRect(inBar: bar).insetBy(dx: -5, dy: -3).contains(p) else { return false }
        presentInstanceStateMenu(forNode: sel.node.id, source: sel.source,
                                 current: sel.inst.activeStateID, at: bar)
        return true
    }

    private func presentInstanceStateMenu(forNode nodeID: UUID, source: ComponentSource,
                                          current: UUID?, at bar: CGRect) {
        let menu = NSMenu()
        let def = NSMenuItem(title: "default", action: #selector(setInstanceStateMenuAction(_:)), keyEquivalent: "")
        def.target = self
        def.representedObject = InstanceStateChoice(nodeID: nodeID, stateID: nil)
        def.state = current == nil ? .on : .off
        menu.addItem(def)
        if !source.states.isEmpty { menu.addItem(.separator()) }
        for st in source.states {
            let it = NSMenuItem(title: st.name, action: #selector(setInstanceStateMenuAction(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = InstanceStateChoice(nodeID: nodeID, stateID: st.id)
            it.state = current == st.id ? .on : .off
            menu.addItem(it)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: bar.minX, y: bar.maxY + 2), in: self)
    }

    /// Right-click "State ▸" submenu (command-coverage: same action, menu path).
    private func instanceStateMenuItem(forNode nodeID: UUID, sourceID: UUID, current: UUID?) -> NSMenuItem {
        let item = NSMenuItem(title: "State", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let def = NSMenuItem(title: "default", action: #selector(setInstanceStateMenuAction(_:)), keyEquivalent: "")
        def.target = self
        def.representedObject = InstanceStateChoice(nodeID: nodeID, stateID: nil)
        def.state = current == nil ? .on : .off
        sub.addItem(def)
        if let source = document?.model.source(for: sourceID), !source.states.isEmpty {
            sub.addItem(.separator())
            for st in source.states {
                let it = NSMenuItem(title: st.name, action: #selector(setInstanceStateMenuAction(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = InstanceStateChoice(nodeID: nodeID, stateID: st.id)
                it.state = current == st.id ? .on : .off
                sub.addItem(it)
            }
        }
        item.submenu = sub
        return item
    }

    @objc private func setInstanceStateMenuAction(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? InstanceStateChoice else { return }
        setInstanceState(nodeID: choice.nodeID, stateID: choice.stateID)
    }

    /// Undoably set which source state an instance displays.
    private func setInstanceState(nodeID: UUID, stateID: UUID?) {
        var nodes = currentNodes
        guard let i = nodes.firstIndex(where: { $0.id == nodeID }),
              case .instance(var inst) = nodes[i].content, inst.activeStateID != stateID else { return }
        inst.activeStateID = stateID
        nodes[i].content = .instance(inst)
        commitNodes(nodes, actionName: "Change Component State")
        needsDisplay = true
    }

    /// The unified selection box for a multi-selection or a single group: an
    /// axis-aligned accent rect over the selection's bounds with 8 resize handles.
    /// Rotation lives just outside the corners (Adobe-style), without extra chrome.
    /// The unified selection box: outline plus eight handles, drawn in the SELECTION
    /// SPACE and mapped to view (BUG-035). An empty chain is document space and takes
    /// the original axis-aligned path unchanged; a chain with a rotated or flipped
    /// ancestor draws the same box as a quad sitting on the art, with its handles at
    /// the positions `hitTestSelectionHandle` tests.
    private func drawSelectionTransformBox(_ bounds: CGRect, chain: [Node], in ctx: CGContext) {
        ctx.saveGState()
        NSColor.controlAccentColor.setStroke()
        ctx.setLineWidth(1.5)
        if chain.isEmpty {
            ctx.stroke(docToView(bounds))
        } else {
            let corners = selectionBoxCorners(bounds, chain: chain)
            ctx.beginPath()
            ctx.move(to: corners[0])
            for i in 1..<corners.count { ctx.addLine(to: corners[i]) }
            ctx.closePath()
            ctx.strokePath()
        }
        ctx.restoreGState()
        for handle in Handle.allCases {
            drawHandleBox(centeredAt: selectionSpaceToView(handlePoint(handle, in: bounds),
                                                           chain: chain), in: ctx)
        }
    }

    /// Selection box for a node living inside rotated group(s): its frame corners
    /// (with the node's own rotation) mapped through the ancestor rotations to where
    /// the shape actually appears, stroked as a quad. (Nested = move-only, no handles.)
    private func drawTransformedSelectionBox(_ node: Node, chain: [Node], in ctx: CGContext,
                                             handles: Bool = false) {
        // Ink bounds, matching the unrotated path and the hit-tests (BUG-036(a)).
        let f = SelectionTransform.outset(node.frame, by: SelectionTransform.inkInsets(of: node))
        let view = [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                    CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)]
            .map { boxPointToView($0, node, chain: chain) }
        ctx.saveGState()
        NSColor.controlAccentColor.setStroke()
        ctx.setLineWidth(1.5)
        ctx.beginPath()
        ctx.move(to: view[0])
        for i in 1..<view.count { ctx.addLine(to: view[i]) }
        ctx.closePath()
        ctx.strokePath()
        ctx.restoreGState()
        // Resize handles at the same mapped positions the hit-tests use. Rotation
        // is the invisible outside-corner region and needs no extra notch/knob.
        guard handles, isBoxResizable(node) else { return }
        for handle in Handle.allCases {
            drawHandleBox(centeredAt: boxPointToView(handlePoint(handle, in: f), node, chain: chain), in: ctx)
        }
    }

    /// A small red "+" badge at the box's bottom-right when a fixed text box has
    /// more text than fits (overset), drawn in view space (constant size).
    private func drawTextOverflowBadge(at rect: CGRect, in ctx: CGContext) {
        let s: CGFloat = 12
        let box = CGRect(x: rect.maxX - s, y: rect.maxY - s, width: s, height: s)
        ctx.saveGState()
        NSColor.systemRed.setFill()
        ctx.fill(box)
        NSColor.white.setStroke()
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: box.midX, y: box.minY + 3)); ctx.addLine(to: CGPoint(x: box.midX, y: box.maxY - 3))
        ctx.move(to: CGPoint(x: box.minX + 3, y: box.midY)); ctx.addLine(to: CGPoint(x: box.maxX - 3, y: box.midY))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// The point-selection transform box (FEAT-026). Drawn DASHED so it cannot be
    /// mistaken for an object selection: it bounds a set of points inside a shape,
    /// not the shape itself. Corners map through the node's own transform and its
    /// ancestor chain, so inside a rotated group the box sits on the points.
    private func drawPointTransformBox(in ctx: CGContext) {
        guard let b = pointTransformBox() else { return }
        let corners = pointBoxCorners(b.box, b.node, b.chain)
        ctx.saveGState()
        NSColor.controlAccentColor.setStroke()
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.beginPath()
        ctx.move(to: corners[0])
        for i in 1..<corners.count { ctx.addLine(to: corners[i]) }
        ctx.closePath()
        ctx.strokePath()
        ctx.restoreGState()
        for handle in Handle.allCases {
            drawHandleBox(centeredAt: nodeLocalToView(handlePoint(handle, in: b.box),
                                                      b.node, chain: b.chain), in: ctx)
        }
    }

    /// The on-canvas gradient line (FEAT-032): the line itself, a knob at each end,
    /// and one knob per stop sitting at its position along it. Drawn white over a
    /// dark halo so it stays legible on any fill — a single-colour line disappears
    /// into roughly half the gradients it is meant to control.
    private func drawGradientHandles(in ctx: CGContext) {
        guard let h = gradientHandleLine() else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        NSColor.black.withAlphaComponent(0.35).setStroke()
        ctx.setLineWidth(3)
        ctx.move(to: h.start); ctx.addLine(to: h.end); ctx.strokePath()
        NSColor.white.setStroke()
        ctx.setLineWidth(1)
        ctx.move(to: h.start); ctx.addLine(to: h.end); ctx.strokePath()
        ctx.restoreGState()

        // Stops first, ends on top: an end knob and a 0/1 stop share a position, and
        // the end is what the hit-test prefers, so it should be what you see.
        for stop in h.gradient.sortedStops {
            drawGradientKnob(at: Self.lerp(h.start, h.end, CGFloat(stop.position)),
                             fill: PaintRender.nsColor(stop.color), radius: 4,
                             isSelected: app?.selectedGradientStopID == stop.id, in: ctx)
        }
        drawGradientKnob(at: h.start, fill: .white, radius: 5.5, in: ctx)
        drawGradientKnob(at: h.end, fill: .white, radius: 5.5, in: ctx)
    }

    private func drawGradientKnob(at c: CGPoint, fill: NSColor, radius: CGFloat,
                                  isSelected: Bool = false,
                                  in ctx: CGContext) {
        let r = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 2, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        fill.setFill()
        ctx.fillEllipse(in: r)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        (isSelected ? NSColor.controlAccentColor : NSColor.white).setStroke()
        ctx.setLineWidth(isSelected ? 3 : 1.5)
        ctx.strokeEllipse(in: r.insetBy(dx: 0.75, dy: 0.75))
        ctx.restoreGState()
    }

    private func drawHandleBox(centeredAt c: CGPoint, in ctx: CGContext) {
        let box = CGRect(x: c.x - handleSize / 2, y: c.y - handleSize / 2,
                         width: handleSize, height: handleSize)
        ctx.saveGState()
        NSColor.white.setFill()
        NSColor.controlAccentColor.setStroke()
        ctx.setLineWidth(1)
        ctx.fill(box)
        ctx.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
    }

    /// Which line endpoint (if any) is under the cursor, for the selected line.
    /// Returns true for the start endpoint, false for the end.
    private func hitTestLineEndpoint(atViewPoint p: CGPoint) -> Bool? {
        guard let app, let id = app.singleSelectedNodeID, let n = node(id),
              let (a, b) = lineEndpointsResolvedDoc(n) else { return nil }
        let av = docToViewPoint(a), bv = docToViewPoint(b)
        if hypot(p.x - av.x, p.y - av.y) <= handleGrab { return true }
        if hypot(p.x - bv.x, p.y - bv.y) <= handleGrab { return false }
        return nil
    }

    private func drawLabel(_ text: String, above rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        string.draw(at: CGPoint(x: rect.minX, y: rect.minY - string.size().height - 6))
    }

    // MARK: Pan / zoom

    override func scrollWheel(with event: NSEvent) {
        guard let app else { return }
        if editingNodeID != nil { commitTextEditing() }
        if event.modifierFlags.contains(.command) {
            zoom(by: 1 + event.scrollingDeltaY * 0.01, anchor: convert(event.locationInWindow, from: nil))
            return
        }
        beginPanZoomInteraction()
        app.panOffset.x += event.scrollingDeltaX
        app.panOffset.y += event.scrollingDeltaY
        scheduleCameraPersistenceIfReady()
        suppressBlurDuringInteraction()
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        if editingNodeID != nil { commitTextEditing() }
        zoom(by: 1 + event.magnification, anchor: convert(event.locationInWindow, from: nil))
    }

    // MARK: Cursor

    /// End the momentary Space-pan without changing the selected tool. This is
    /// intentionally idempotent: both the canvas key handler and the app-wide
    /// key-up monitor can observe the same release.
    private func endTemporaryPan() {
        guard spaceHeld else { return }
        spaceHeld = false
        if case .hand = dragMode {
            dragMode = .none
            lastDragPoint = nil
        }
        refreshCursor()
    }

    @objc private func applicationDidResignActive() {
        endTemporaryPan()
    }

    func refreshCursor(flags: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        desiredCursor(at: lastMouse, flags: flags).set()
    }

    /// Switch tools, finishing any in-progress pen path first.
    private func setTool(_ tool: Tool) {
        if penNodeID != nil, tool != .pen { finishPen() }
        if pencilNodeID != nil, tool != .pencil { finishPencilStroke() }
        app?.tool = tool
        refreshCursor()
    }

    // MARK: Tool actions (menu-bar reachable) — BUG-028
    //
    // The letter shortcuts in `keyDown` only fire when the CANVAS holds focus, so
    // with focus in Layers or a floating tray the tool silently did not change —
    // and because the point tool will not move a whole object with nothing
    // point-selected, the app then read as broken rather than as merely in the
    // wrong mode. Same responder-chain boundary as BUG-016 (copy/paste) and
    // BUG-020 (opacity digits).
    //
    // These give every tool a menu-bar home, which the command-coverage rule
    // requires anyway and which routes through `sendCanvasAction` — so it reaches
    // the canvas from ANY focus location. They are deliberately NOT given
    // single-letter key equivalents; see the note in EXP__design_App.swift's Tools
    // menu for why that would be actively harmful.
    //
    // No `validateMenuItem` cases: a tool is never unavailable, so there is nothing
    // to gate. That is a deliberate decision, not an omission.
    @objc func selectToolAction(_ s: Any?)     { setTool(.select) }
    @objc func nodeToolAction(_ s: Any?)       { setTool(.node) }
    @objc func penToolAction(_ s: Any?)        { setTool(.pen) }
    @objc func pencilToolAction(_ s: Any?)     { setTool(.pencil) }
    @objc func textToolAction(_ s: Any?)       { setTool(.text) }
    @objc func rectangleToolAction(_ s: Any?)  { setTool(.rectangle) }
    @objc func ellipseToolAction(_ s: Any?)    { setTool(.ellipse) }
    @objc func polygonToolAction(_ s: Any?)    { setTool(.polygon) }
    @objc func lineToolAction(_ s: Any?)       { setTool(.line) }
    @objc func artboardToolAction(_ s: Any?)   { setTool(.artboard) }
    @objc func panToolAction(_ s: Any?)        { setTool(.pan) }

    /// Load an authored vector cursor from Assets.xcassets while preserving its
    /// vector representation. `size` is in display points, not source SVG pixels.
    private static func authoredCursor(_ assetName: String, size: NSSize,
                                       hotSpot: NSPoint, fallback: NSCursor) -> NSCursor {
        guard let source = NSImage(named: NSImage.Name(assetName)),
              let image = source.copy() as? NSImage else { return fallback }
        image.size = size
        image.isTemplate = false
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    /// Code-drawn fallbacks keep every interaction usable if an asset ever fails
    /// to load from a development build. Shipped builds use the authored SVGs.
    private static let fallbackRemovePointCursor: NSCursor = {
        let arrow = NSCursor.arrow
        let base = arrow.image
        let canvas = NSImage(size: base.size)
        canvas.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        let badge = CGRect(x: base.size.width - 9, y: 0, width: 9, height: 9)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: badge.insetBy(dx: -1, dy: -1)).fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: badge).fill()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(x: badge.minX + 2, y: badge.midY - 0.75,
                                  width: badge.width - 4, height: 1.5)).fill()
        canvas.unlockFocus()
        return NSCursor(image: canvas, hotSpot: arrow.hotSpot)
    }()

    private static let fallbackRotateCursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 22, height: 22)).fill()
        if let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Rotate")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .bold)
                .applying(.init(paletteColors: [.black]))) {
            symbol.draw(in: CGRect(x: 4, y: 4, width: 16, height: 16))
        }
        canvas.unlockFocus()
        return NSCursor(image: canvas, hotSpot: NSPoint(x: 12, y: 12))
    }()

    // The source SVG family was drawn at one shared 8x working scale. Keeping
    // that relationship makes the pointer, point badges, and rotate marks feel
    // like one system while remaining crisp on Retina displays.
    private static let pointerCursor = authoredCursor(
        "cursor-pointer", size: NSSize(width: 19, height: 28),
        hotSpot: NSPoint(x: 4.5, y: 1.75), fallback: .arrow)
    private static let addPointCursor = authoredCursor(
        "cursor-pen-add", size: NSSize(width: 28, height: 37),
        hotSpot: NSPoint(x: 4.5, y: 1.75), fallback: .dragCopy)
    private static let removePointCursor = authoredCursor(
        "cursor-pen-delete", size: NSSize(width: 28, height: 37),
        hotSpot: NSPoint(x: 4.5, y: 1.75), fallback: fallbackRemovePointCursor)
    private static let rotateTopLeftCursor = authoredCursor(
        "cursor-rotate-top-left", size: NSSize(width: 24, height: 24),
        hotSpot: NSPoint(x: 12, y: 12), fallback: fallbackRotateCursor)
    private static let rotateTopRightCursor = authoredCursor(
        "cursor-rotate-top-right", size: NSSize(width: 24, height: 24),
        hotSpot: NSPoint(x: 12, y: 12), fallback: fallbackRotateCursor)
    private static let rotateBottomLeftCursor = authoredCursor(
        "cursor-rotate-bottom-left", size: NSSize(width: 24, height: 24),
        hotSpot: NSPoint(x: 12, y: 12), fallback: fallbackRotateCursor)
    private static let rotateBottomRightCursor = authoredCursor(
        "cursor-rotate-bottom-right", size: NSSize(width: 24, height: 24),
        hotSpot: NSPoint(x: 12, y: 12), fallback: fallbackRotateCursor)

    /// Pick by the corner's VIEW-space quadrant, not its logical handle name.
    /// A rotated/flipped object can move its logical top-left corner elsewhere on
    /// screen; view-space selection keeps the authored arrows pointing inward.
    private static func rotateCursor(corner: CGPoint, center: CGPoint) -> NSCursor {
        if corner.y <= center.y {
            return corner.x <= center.x ? rotateTopLeftCursor : rotateTopRightCursor
        }
        return corner.x <= center.x ? rotateBottomLeftCursor : rotateBottomRightCursor
    }

    private func desiredCursor(at p: CGPoint, flags: NSEvent.ModifierFlags) -> NSCursor {
        if spaceHeld { return .openHand }
        guard let app else { return Self.pointerCursor }
        switch app.tool {
        case .pen:
            // "−" badge directly over an existing anchor (no active session) =
            // remove that point; "+" when hovering an existing shape's body =
            // add one. Both share `penHover`'s topmost-hit scoping (see its doc
            // comment) so neither badge fires on anchors elsewhere in the document.
            if penNodeID == nil, let hover = penHover(atViewPoint: p) {
                if hover.removable != nil { return Self.removePointCursor }
                if let n = node(hover.leafID), penAddable(n) { return Self.addPointCursor }
            }
            return .crosshair
        case .rectangle, .ellipse, .polygon, .line, .artboard, .pencil:
            return .crosshair
        case .pan:
            return .openHand
        case .image, .component:
            return Self.pointerCursor
        case .text:
            return .iBeam
        case .node:
            if let rot = hitTestPointBoxRotate(atViewPoint: p) {
                return Self.rotateCursor(corner: rot.corner, center: rot.centerView)
            }
            if let hit = hitTestPointBoxHandle(atViewPoint: p) { return cursor(for: hit.handle) }
            return Self.pointerCursor
        case .select:
            // The cursor is what tells you the line is live: crosshair = "click adds a
            // stop here", open hand = "grab this knob".
            if let g = hitTestGradientHandle(atViewPoint: p) {
                if case .line = g.hit { return .crosshair }
                return .openHand
            }
            if let hit = hitTestSelectionRotate(atViewPoint: p) {
                return Self.rotateCursor(corner: hit.corner, center: hit.center)
            }
            if let handle = hitTestSelectionHandle(atViewPoint: p) { return cursor(for: handle) }
            if let hit = hitTestRotateHandle(atViewPoint: p) {
                return Self.rotateCursor(corner: hit.corner, center: hit.center)
            }
            if let handle = hitTestHandle(atViewPoint: p) { return cursor(for: handle) }
            if let board = soleSelectedArtboard(),
               let handle = hitTestArtboardHandle(atViewPoint: p, board: board) { return cursor(for: handle) }
            if let handle = hitTestSourceHandle(atViewPoint: p) { return cursor(for: handle) }
            if flags.contains(.option), hitTestNode(atViewPoint: p) != nil { return .dragCopy }
            if flags.contains(.option), hitTestArtboardLabel(atViewPoint: p) != nil { return .dragCopy }
            return Self.pointerCursor
        }
    }

    private func cursor(for handle: Handle) -> NSCursor {
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default:            return .crosshair
        }
    }

    override func mouseMoved(with event: NSEvent) {
        lastMouse = convert(event.locationInWindow, from: nil)
        let opt = event.modifierFlags.contains(.option)
        // Redraw while measuring, to track the ruler pointer marker, and under the
        // pen tool so the hovered vector's anchors light up as the cursor moves.
        if opt || optionHeld || app?.showRulers == true || app?.tool == .pen { needsDisplay = true }
        optionHeld = opt
        refreshCursor(flags: event.modifierFlags)
    }

    override func flagsChanged(with event: NSEvent) {
        let opt = event.modifierFlags.contains(.option)
        if opt != optionHeld { optionHeld = opt; needsDisplay = true }
        refreshCursor(flags: event.modifierFlags)
        super.flagsChanged(with: event)
    }

    // MARK: Keyboard

    // MARK: Input latency instrumentation (Testing Mode)
    //
    // 2026-07-14: owner reports big FELT lag on arrow-key nudges while the
    // frame buckets read a healthy 16-25ms. The draw buckets cannot see (a)
    // how long the event sat in the queue / event routing before the handler
    // ran, or (b) main-thread work after the handler (SwiftUI publish cycle,
    // panels re-evaluating) that delays the repaint. These two buckets close
    // that gap:
    //   input-pre(...)  = handler start - event.timestamp (hardware-stamped)
    //   input->frame    = completed repaint - event.timestamp
    // If input-pre is big  -> the delay happens BEFORE our code (event routing
    //   / menu key-equivalent scanning / a busy main thread).
    // If input-pre is tiny but input->frame is big -> the delay is between our
    //   commit and the repaint (SwiftUI publish / panel re-evaluation, F3).
    // If both are small but it still FEELS slow -> the window server /
    //   CVDisplayLink side, not the app (unlikely).
    private var perfInputEventTime: TimeInterval?

    private func notePerfInput(_ event: NSEvent, _ label: String) {
        guard perf.enabled else { return }
        MainThreadWatchdog.shared.startIfNeeded()
        let now = ProcessInfo.processInfo.systemUptime
        let preMs = (now - event.timestamp) * 1000
        perf.record("input-pre(\(label))", ms: preMs)
        // Round 6: big delays also log IMMEDIATELY with an uptime stamp, so
        // they can be lined up against watchdog entries on one clock (the
        // aggregated meter has no per-event timestamps).
        if preMs > 500 {
            DiagnosticLog.shared.log(String(format: "[EXP input] %@ delayed %.2fs  (t=%.1f)",
                                            label, preMs / 1000, now))
        }
        perfInputEventTime = event.timestamp
    }

    /// Called at every completed `draw(_:)` exit; records once per noted event.
    private func recordInputToFrame() {
        guard let t0 = perfInputEventTime else { return }
        perfInputEventTime = nil
        guard perf.enabled else { return }
        perf.record("input->frame", ms: (ProcessInfo.processInfo.systemUptime - t0) * 1000)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            if !spaceHeld { spaceHeld = true; NSCursor.openHand.set() }
            return
        }

        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "=", "+": zoom(by: 1.25, anchor: viewCenter); return
            case "-", "_": zoom(by: 0.8,  anchor: viewCenter); return
            case "0":      zoomActualAction(nil);              return   // matches View ▸ Actual Size
            case "1":      zoomToFit();                        return   // matches View ▸ Zoom to Fit
            case "2":      centerSelectionAction(nil);         return
            case "d":      duplicate();                        return
            case "g":      group();                            return   // ⌘G
            case "G":      ungroup();                           return   // ⇧⌘G
            case "k":      createComponent();                  return   // ⌘K
            case "K":      detachSelectedInstances();          return   // ⇧⌘K
            case "[":      nudgeOrder(by: -1);                 return   // ⌘[  send backward
            case "]":      nudgeOrder(by: +1);                 return   // ⌘]  bring forward
            case "{":      reorderSelection(toFront: false);   return   // ⇧⌘[ send to back
            case "}":      reorderSelection(toFront: true);    return   // ⇧⌘] bring to front
            default: break
            }
        }

        if !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control),
           !event.modifierFlags.contains(.option) {
            // ⇧A is Sketch's and XD's Artboard shortcut. Plain A is Edit Points here
            // (Illustrator's Direct Selection), so the alias goes on ⇧A rather than
            // stealing a key that already means something.
            if event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers?.lowercased() == "a" {
                setTool(.artboard); return
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "h": setTool(.pan);       return
            case "v": setTool(.select);    return
            case "a": setTool(.node);      return
            case "r": setTool(.rectangle); return
            case "o": setTool(.ellipse);   return
            case "g": setTool(.polygon);   return
            case "l": setTool(.line);      return
            case "p": setTool(.pen);       return
            case "n": setTool(.pencil);    return   // Illustrator's Pencil key
            case "t": setTool(.text);      return
            case "f": setTool(.artboard);  return   // Figma's Frame key
            case "i": eyedropToSelection(); return   // sample → apply to selection
            default: break
            }

            // Number keys set the selected layer(s)' opacity (Figma-style): 1–9 =
            // 10–90%, 0 = 100%. Only when shapes are selected and NOT editing text
            // (text editing makes the NSTextView first responder, so we never get
            // these key events mid-edit; the guard is belt-and-suspenders).
            if editingNodeID == nil,
               let ch = event.charactersIgnoringModifiers, ch.count == 1,
               let digit = ch.first, digit.isASCII, digit.isNumber,
               let app, !app.selectedNodeIDs.isEmpty {
                let d = digit.wholeNumberValue ?? 0
                setOpacityOnSelection(d == 0 ? 1.0 : Double(d) / 10.0)
                return
            }
        }

        switch event.keyCode {
        case 123, 124, 125, 126:
            notePerfInput(event, "key")
            nudgeSelection(keyCode: event.keyCode, large: event.modifierFlags.contains(.shift)); return
        case 51, 117:            deleteSelection(); return
        case 48:                 cycleArtboardSelection(forward: !event.modifierFlags.contains(.shift)); return
        case 36:                 if penNodeID != nil { finishPen() }; return        // Return finishes a pen path
        case 53:                                                                    // Esc finishes pen, else Select tool
            if penNodeID != nil { finishPen() } else { setTool(.select) }
            return
        default: break
        }

        super.keyDown(with: event)
    }

    /// Set opacity (0…1) on every selected node as one undo step.
    private func setOpacityOnSelection(_ opacity: Double) {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        var nodes = currentNodes
        guard LayerOpacityMutation.apply(opacity, to: app.selectedNodeIDs,
                                         in: &nodes) else { return }
        commitNodes(nodes, actionName: "Opacity")
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            endTemporaryPan()
            return
        }
        super.keyUp(with: event)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        notePerfInput(event, "down")
        let p = convert(event.locationInWindow, from: nil)
        lastMouse = p

        // A click anywhere outside the text editor commits the in-progress edit.
        if editingNodeID != nil { commitTextEditing() }
        // Clicking the canvas must also reclaim keyboard ownership from a panel or
        // inspector field. Without this, the click can select a perfectly valid
        // layer while Command-C / Command-V still route to the previously focused
        // sibling view and appear broken.
        window?.makeFirstResponder(self)

        if spaceHeld || app?.tool == .pan {
            dragMode = .hand
            lastDragPoint = p
            NSCursor.closedHand.set()
            return
        }

        guard let app, let document else { return }
        didEdit = false
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)

        // Rulers / guides: pull a new guide from a ruler, or grab an existing one.
        if !isSourceScope, !app.guidesLocked, beginGuideDrag(at: p) { return }

        // Pen tool: place/extend/close a path.
        if app.tool == .pen {
            penMouseDown(p)
            return
        }

        // Node tool: edit the selected path's points/handles.
        if app.tool == .node {
            nodeToolMouseDown(p, shift: shift)
            return
        }

        // Pencil tool: capture a freehand stroke; fitted to anchors on release.
        if app.tool == .pencil {
            pencilMouseDown(p)
            return
        }

        // Text tool: click places an auto-width node; drag makes a fixed paragraph
        // box. Decided on mouseUp.
        if app.tool == .text {
            dragMode = .drawTextBox(originView: p)
            marqueeCurrent = p
            return
        }

        // Line tool: drag from start to end.
        if app.tool == .line {
            dragBaseline = document.model
            let startDoc = viewToDoc(p)
            let line = LineShape(start: .zero, end: .zero)
            let newNode = Node(name: "Line", frame: CGRect(origin: startDoc, size: .zero), content: .line(line))
            withNodes { $0.append(newNode) }
            app.selectedArtboardID = nil
            app.selectedNodeIDs = [newNode.id]
            gestureUndoName = "Draw Line"
            dragMode = .drawLine(id: newNode.id, startDoc: startDoc)
            needsDisplay = true
            return
        }

        // Artboard tool: draw a board anywhere on the page. Click = default size at
        // the click point, drag = exact bounds.
        //
        // The point of the tool is drawing a board AROUND work that already exists,
        // and note what that gets for free: node ownership is by CONTAINMENT, so any
        // artwork the new board encloses is adopted immediately — no move, no
        // reparent step. Component-source scope has no artboards, so it falls through.
        if app.tool == .artboard, !isSourceScope {
            dragBaseline = document.model
            let originDoc = viewToDoc(p)
            let board = Artboard(name: "Artboard \(currentArtboards.count + 1)",
                                 frame: CGRect(origin: originDoc, size: .zero))
            withActivePage { $0.artboards.append(board) }
            app.selectedNodeIDs = []
            app.selectedArtboardIDs = [board.id]
            gestureUndoName = "Draw Artboard"
            dragMode = .drawArtboard(id: board.id, originDoc: originDoc)
            needsDisplay = true
            return
        }

        // Shape tools: draw a new shape anywhere (artboard OR wall).
        if app.tool == .rectangle || app.tool == .ellipse || app.tool == .polygon {
            dragBaseline = document.model
            let originDoc = viewToDoc(p)
            let newNode = makeNode(for: app.tool, frame: CGRect(origin: originDoc, size: .zero))
            withNodes { $0.append(newNode) }
            app.selectedArtboardID = nil
            app.selectedNodeIDs = [newNode.id]
            gestureUndoName = app.tool == .ellipse ? "Draw Ellipse"
                : app.tool == .polygon ? "Draw Polygon" : "Draw Rectangle"
            dragMode = .draw(id: newNode.id, originDoc: originDoc)
            needsDisplay = true
            return
        }

        // Component state dropdown: a click on a selected instance's label-bar
        // chevron opens the state menu instead of starting a selection/drag.
        if presentInstanceStateMenuIfHit(at: p) { return }

        // Line endpoint handle (single line selected) — edit before box handles.
        if let movingStart = hitTestLineEndpoint(atViewPoint: p), let id = app.singleSelectedNodeID,
           let n = node(id), let (a, b) = lineEndpointsResolvedDoc(n) {
            dragBaseline = document.model
            gestureUndoName = "Edit Line"
            dragMode = .lineEndpoint(id: id, movingStart: movingStart, fixedDoc: movingStart ? b : a)
            return
        }

        // FEAT-032: the gradient line. Tested before the selection chrome because
        // its handles live INSIDE the shape, where nothing else is grabbable.
        if let g = hitTestGradientHandle(atViewPoint: p) {
            didEdit = false
            switch g.hit {
            case .start, .end:
                dragBaseline = document.model
                gestureUndoName = "Gradient Direction"
                dragMode = .gradientEnd(id: g.id, movingStart: g.hit == .start)
            case .stop(let stopID):
                dragBaseline = document.model
                gestureUndoName = "Gradient Stop"
                app.selectedGradientStopID = stopID
                gradientStopClickCandidate = stopID   // opens the editor on mouse-UP
                dragMode = .gradientStop(id: g.id, stopID: stopID)
                needsDisplay = true
            case .line(let t):
                // A single click on the line adds a stop there (owner's call). The new
                // stop takes the colour already at that spot, so the gradient does not
                // change appearance — then the same gesture continues as a drag, so
                // click-and-drag places it in one motion.
                guard let newID = addGradientStop(on: g.id, at: t) else { return }
                dragBaseline = document.model
                gestureUndoName = "Gradient Stop"
                dragMode = .gradientStop(id: g.id, stopID: newID)
            }
            return
        }

        // Outside-corner rotation (multi-select or a group) — before resize.
        if let rotateHit = hitTestSelectionRotate(atViewPoint: p) {
            dragBaseline = document.model
            gestureUndoName = "Rotate"
            snapshotSelectionBaseline()
            // `centerDoc` and the angle are both in the SELECTION SPACE (document
            // space when its chain is empty). Measuring the angle there rather than in
            // view space is what keeps a flipped ancestor from reversing the turn.
            dragMode = .rotateSelection(
                centerDoc: rotateHit.pivot,
                startAngle: selectionSpaceAngle(ofViewPoint: p, aroundLocal: rotateHit.pivot,
                                                chain: selectionDragChain))
            return
        }

        // Selection resize handle (multi-select or a group).
        if let handle = hitTestSelectionHandle(atViewPoint: p),
           let box = selectionLocalBox(selectionSpace()) {
            dragBaseline = document.model
            gestureUndoName = "Resize"
            snapshotSelectionBaseline()
            selectionDragInkInsets = box.insets
            // `original` is the INK box in space-local coordinates: the handle the
            // user grabbed is on it, so the drag must be computed against it.
            dragMode = .resizeSelection(handle: handle, original: box.ink)
            return
        }

        // Outside-corner rotation (single selection) — before resize handles.
        if let rk = hitTestRotateHandle(atViewPoint: p), let n = node(rk.id) {
            dragBaseline = document.model
            gestureUndoName = "Rotate"
            dragMode = .rotate(id: rk.id, centerView: rk.center,
                               lastAngle: nodeRotationAngle(atViewPoint: p, id: rk.id, centerView: rk.center),
                               rawRotation: n.rotation)
            return
        }

        // Resize handle (single selection).
        if let handle = hitTestHandle(atViewPoint: p), let id = app.singleSelectedNodeID, let n = node(id) {
            dragBaseline = document.model
            gestureUndoName = "Resize Shape"
            resizePathBaseline = { if case .path(let ps) = n.content { return ps }; return nil }()
            resizeFlipBaseline = (n.flipH, n.flipV)
            resizeInkInsets = SelectionTransform.inkInsets(of: n)
            dragMode = .resize(id: id, handle: handle, original: n.frame)
            return
        }

        // Component viewBox resize handle (source editor) — its own little artboard.
        if let handle = hitTestSourceHandle(atViewPoint: p), let rect = sourceBoundsRect() {
            dragBaseline = document.model
            gestureUndoName = "Resize Component Bounds"
            dragMode = .resizeSource(handle: handle, original: rect)
            return
        }

        // Artboard resize handle (lone selected board, no shapes selected).
        if let board = soleSelectedArtboard(), let handle = hitTestArtboardHandle(atViewPoint: p, board: board) {
            dragBaseline = document.model
            gestureUndoName = "Resize Artboard"
            dragMode = .resizeArtboard(id: board.id, handle: handle, original: board.frame)
            return
        }

        // Artboard name label → select / move / duplicate / rename the board(s).
        if let board = hitTestArtboardLabel(atViewPoint: p) {
            app.selectedNodeIDs = []
            // Double-click the label to rename it inline.
            if event.clickCount == 2 {
                app.selectedArtboardIDs = [board.id]
                beginRenamingArtboard(board.id)
                return
            }
            if shift {
                // Toggle this board in the multi-selection; no drag.
                if app.selectedArtboardIDs.contains(board.id) { app.selectedArtboardIDs.remove(board.id) }
                else { app.selectedArtboardIDs.insert(board.id) }
                dragMode = .none
                needsDisplay = true
                return
            }
            // Clicking an unselected board selects just it; clicking one already
            // in the set keeps the whole set (so you can drag the group).
            if !app.selectedArtboardIDs.contains(board.id) { app.selectedArtboardIDs = [board.id] }
            let ids = Array(app.selectedArtboardIDs)
            dragBaseline = document.model
            if option {
                let dup = duplicateArtboards(ids, offset: .zero)
                app.selectedArtboardIDs = Set(dup.boardOrigins.keys)
                gestureUndoName = "Duplicate Artboard"
                didEdit = true
                dragMode = .artboards(startDoc: viewToDoc(p),
                                      boardOrigins: dup.boardOrigins, childOrigins: dup.childOrigins)
            } else {
                gestureUndoName = "Move Artboard"
                dragMode = .artboards(startDoc: viewToDoc(p),
                                      boardOrigins: artboardOrigins(ids),
                                      childOrigins: ownedNodeOrigins(forBoards: ids))
            }
            needsDisplay = true
            return
        }

        // With multiple boards selected (a "rearrange boards" mode — usually
        // zoomed out), dragging anywhere inside any selected board moves the
        // whole set + contents, instead of grabbing the shape under the cursor.
        if app.tool == .select, app.selectedArtboardIDs.count > 1,
           selectedBoardContaining(viewToDoc(p)) != nil {
            let ids = Array(app.selectedArtboardIDs)
            dragBaseline = document.model
            if option {
                let dup = duplicateArtboards(ids, offset: .zero)
                app.selectedArtboardIDs = Set(dup.boardOrigins.keys)
                gestureUndoName = "Duplicate Artboard"
                didEdit = true
                dragMode = .artboards(startDoc: viewToDoc(p),
                                      boardOrigins: dup.boardOrigins, childOrigins: dup.childOrigins)
            } else {
                gestureUndoName = "Move Artboard"
                dragMode = .artboards(startDoc: viewToDoc(p),
                                      boardOrigins: artboardOrigins(ids),
                                      childOrigins: ownedNodeOrigins(forBoards: ids))
            }
            needsDisplay = true
            return
        }

        // A shape. `hitPath` is the chain top-level → deepest leaf under the cursor.
        let clickDoc = viewToDoc(p)
        let path = hitPath(atDoc: clickDoc)

        // Photoshop-style selected-layer mode. With Auto-select OFF, the Layers
        // panel remains authoritative: a covered selected layer can still begin a
        // move because we test its own real geometry independently of z-order, while
        // clicking a different visible layer does not silently replace the selection.
        if app.tool == .select, event.clickCount == 1, !app.autoSelectLayers, !shift,
           !app.selectedNodeIDs.isEmpty {
            if selectedGeometryContains(clickDoc) {
                beginSelectedNodeDrag(at: clickDoc)
                return
            }
            if !path.isEmpty {
                dragMode = .none
                return
            }
        }
        if !path.isEmpty {
            let cmd = event.modifierFlags.contains(.command)

            // Double-click: open an instance's source, edit a (top-level) text, else
            // DRILL one level deeper into the group along the cursor's path.
            if event.clickCount == 2 {
                let deepest = node(path.last!.id)
                if case .instance(let inst)? = deepest?.content {
                    app.selectedNodeIDs = [path.last!.id]; app.selectedArtboardID = nil
                    openSourceEditor(inst.sourceID); return
                }
                // Edit text. A TOP-LEVEL text enters edit on double-click. A text
                // nested in a group needs an extra step: the first double-click only
                // drills in / selects it (so it can be dragged), and a further
                // double-click — now that it's selected — opens the editor. This
                // matches other tools and stops a group text from being un-draggable.
                // (Rotated ancestors skip editing; they'd need a rotated overlay.)
                if case .text? = deepest?.content, ancestorRotation(of: path.last!.id) == 0 {
                    let tid = path.last!.id
                    if isTopLevelNode(tid) || app.selectedNodeIDs.contains(tid) {
                        app.selectedNodeIDs = [tid]; app.selectedArtboardID = nil
                        beginEditingText(nodeID: tid, isNew: false); return
                    }
                    // else: fall through to drill/select; the next double-click edits.
                }
            }

            // Which node this click acts on:
            let targetID: UUID
            if cmd {
                targetID = path.last!.id                       // ⌘-click → deepest leaf
            } else if event.clickCount == 2 {
                if let i = path.firstIndex(where: { app.selectedNodeIDs.contains($0.id) }), i + 1 < path.count {
                    targetID = path[i + 1].id                  // drill one deeper
                } else {
                    targetID = path.count > 1 ? path[1].id : path[0].id   // enter the group
                }
            } else if let scoped = hitTargetInSelectionLevel(from: path, level: selectionLevel(for: app.selectedNodeIDs)) {
                targetID = scoped                              // stay at the active group/top-level selection context
            } else if let sel = path.first(where: { app.selectedNodeIDs.contains($0.id) }) {
                targetID = sel.id                              // keep a drilled-in node to drag it
            } else {
                targetID = path[0].id                          // outermost (group/shape)
            }

            if shift {
                if app.selectedNodeIDs.contains(targetID) { app.selectedNodeIDs.remove(targetID) }
                else { app.selectedNodeIDs.insert(targetID) }
                app.selectedArtboardID = nil
                dragMode = .none
                needsDisplay = true
                return
            }
            if !app.selectedNodeIDs.contains(targetID) { app.selectedNodeIDs = [targetID] }
            app.selectedArtboardID = nil
            app.selectionAnchorID = targetID

            beginSelectedNodeDrag(at: clickDoc)
            return
        }

        // Empty space → marquee.
        marqueeCurrent = p
        dragMode = .marquee(startView: p, additive: shift)
    }

    // MARK: Pixel snap
    //
    // Canvas gestures snap to WHOLE document pixels by default, so what you drag
    // is what the inspector reads — no more fractional coordinates minted by
    // dragging at odd zoom levels. ⌘ bypasses (the same modifier that already
    // bypasses smart-guide snapping), and the inspector accepts typed fractional
    // values (⌥-arrows step by 0.1) when sub-pixel placement is intentional.
    // Smart guides run AFTER pixel snap, so exact edge alignment always wins.

    private func pxSnap(_ v: CGFloat) -> CGFloat { v.rounded() }
    private func pxSnap(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x.rounded(), y: p.y.rounded())
    }
    /// Snap a rect by its EDGES, so the far edge lands on the pixel the cursor
    /// indicated (rounding origin and size independently can drift the far edge).
    /// Size floors at 1 — the same minimum the inspector clamps to.
    private func pxSnapRect(_ r: CGRect) -> CGRect {
        let x0 = r.minX.rounded(), y0 = r.minY.rounded()
        return CGRect(x: x0, y: y0,
                      width: Swift.max(1, r.maxX.rounded() - x0),
                      height: Swift.max(1, r.maxY.rounded() - y0))
    }

    /// Square off a drag rect for Shift-constrain: the larger dimension wins, so
    /// the shape still follows the cursor's dominant direction, and the corner
    /// OPPOSITE the origin is the one that moves (the origin corner is pinned,
    /// which is what a drag-from-corner means). BUG-037.
    private func squared(from origin: CGPoint, to cur: CGPoint) -> CGPoint {
        let side = max(abs(cur.x - origin.x), abs(cur.y - origin.y))
        return CGPoint(x: origin.x + (cur.x < origin.x ? -side : side),
                       y: origin.y + (cur.y < origin.y ? -side : side))
    }

    override func mouseDragged(with event: NSEvent) {
        notePerfInput(event, "drag")
        let p = convert(event.locationInWindow, from: nil)
        lastMouse = p
        let shift = event.modifierFlags.contains(.shift)
        // ⌘ bypasses every kind of snapping for this gesture. Whole-pixel rounding
        // is a separate preference from guides/grid/artboard snapping (BUG-036(b));
        // turning pixels off must not quietly turn all of the others off with it.
        let bypassAllSnapping = event.modifierFlags.contains(.command)
        let snapToPixels = !bypassAllSnapping && (app?.pixelSnap ?? true)

        switch dragMode {
        case .hand:
            guard let app, let last = lastDragPoint else { return }
            beginPanZoomInteraction()
            app.panOffset.x += p.x - last.x
            app.panOffset.y += p.y - last.y
            lastDragPoint = p
            scheduleCameraPersistenceIfReady()
            suppressBlurDuringInteraction()
            needsDisplay = true

        case .draw(let id, let originDoc):
            var cur = viewToDoc(p)
            var org = originDoc
            // Shift = 1:1 (perfect square / circle). Sampled LIVE from `shift`, so
            // it can be pressed or released mid-draw, same as the Option handling
            // in `.nodes`. Constrain BEFORE the pixel snap so the two edges round
            // identically and the result stays square. BUG-037.
            if shift { cur = squared(from: org, to: cur) }
            if snapToPixels { cur = pxSnap(cur); org = pxSnap(org) }
            updateNode(id) {
                $0.frame = CGRect(x: min(org.x, cur.x), y: min(org.y, cur.y),
                                  width: abs(cur.x - org.x), height: abs(cur.y - org.y))
            }
            didEdit = true
            needsDisplay = true

        case .drawArtboard(let id, let originDoc):
            var cur = viewToDoc(p)
            var org = originDoc
            if shift { cur = squared(from: org, to: cur) }   // 1:1 frames — BUG-037
            if snapToPixels { cur = pxSnap(cur); org = pxSnap(org) }
            withActivePage { page in
                guard let i = page.artboards.firstIndex(where: { $0.id == id }) else { return }
                page.artboards[i].frame = CGRect(x: min(org.x, cur.x), y: min(org.y, cur.y),
                                                 width: abs(cur.x - org.x),
                                                 height: abs(cur.y - org.y))
            }
            didEdit = true
            needsDisplay = true

        case .nodes(let startDoc, let dragOrigins):
            // Sample Option LIVE, every tick, so it can be pressed or released
            // mid-drag and the gesture flips between duplicate and move — the
            // behavior every other editor has (BUG-025). Re-read the origins after
            // a flip: duplicating swaps the selection to freshly-minted ids, so the
            // origins captured in `dragMode` are stale the moment it happens.
            var origins = dragOrigins
            let wantCopy = event.modifierFlags.contains(.option)
            if wantCopy != dragCopyActive {
                setDragCopy(wantCopy, startDoc: startDoc)
                if case .nodes(_, let refreshed) = dragMode { origins = refreshed }
            }
            let now = viewToDoc(p)
            var dx = now.x - startDoc.x, dy = now.y - startDoc.y
            if shift { if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 } }   // axis lock
            // Pixel snap first, smart guides after (⌘ skips both): round where the
            // selection's top-left-most origin lands, keeping relative offsets, then
            // let guide/edge alignment override — exact alignment beats whole pixels.
            if snapToPixels {
                let refX = origins.values.map(\.x).min() ?? 0
                let refY = origins.values.map(\.y).min() ?? 0
                dx = (refX + dx).rounded() - refX
                dy = (refY + dy).rounded() - refY
            }
            if !bypassAllSnapping {
                (dx, dy) = snapNodeOffset(dx: dx, dy: dy, origins: origins)
            }
            for (id, origin0) in origins {
                // A node's position lives in its PARENT's space. Convert the
                // document-space delta through the whole ancestor chain —
                // rotations AND flips — by mapping two doc points down and
                // differencing. (The old rotate-only shortcut moved children of
                // a flipped group the wrong way along the mirrored axis, and
                // summed angles ignore that a mirror reverses rotation.)
                let chain = ancestorGroups(of: id)
                let d: CGPoint
                if chain.isEmpty {
                    d = CGPoint(x: dx, y: dy)
                } else {
                    let a = docToParentLocal(startDoc, chain: chain)
                    let b = docToParentLocal(CGPoint(x: startDoc.x + dx, y: startDoc.y + dy), chain: chain)
                    d = CGPoint(x: b.x - a.x, y: b.y - a.y)
                }
                updateNode(id) { $0.frame.origin = CGPoint(x: origin0.x + d.x, y: origin0.y + d.y) }
            }
            didEdit = true
            needsDisplay = true

        case .resize(let id, let handle, let original):
            // `original` is the node's parent-local frame; convert the cursor into
            // that same space (a nested node sits under an unrotated-group offset).
            // Cursor into the node's PARENT-LOCAL space through the full
            // ancestor chain (rotations + flips) — `original` lives there, so
            // every bit of resize math below is chain-agnostic. The old plain
            // offset subtraction only held for untransformed ancestors.
            let cur = docToParentLocal(viewToDoc(p), chain: ancestorGroups(of: id))
            let rot = node(id)?.rotation ?? 0
            // The handle the user grabbed sits on the INK box, so the drag is computed
            // against it and the result is inset back to the geometry the model
            // stores (BUG-036(a)). With no stroke the insets are zero and every line
            // below is byte-for-byte the old geometry math.
            let ink = resizeInkInsets
            let originalInk = SelectionTransform.outset(original, by: ink)
            // Flip when a handle is dragged PAST the opposite edge (un-rotated only).
            var desiredFlipH: Bool? = nil, desiredFlipV: Bool? = nil
            if rot == 0 {
                let left = [Handle.left, .topLeft, .bottomLeft].contains(handle)
                let right = [Handle.right, .topRight, .bottomRight].contains(handle)
                let top = [Handle.top, .topLeft, .topRight].contains(handle)
                let bottom = [Handle.bottom, .bottomLeft, .bottomRight].contains(handle)
                let crossedH = (left && cur.x > originalInk.maxX) || (right && cur.x < originalInk.minX)
                let crossedV = (top && cur.y > originalInk.maxY) || (bottom && cur.y < originalInk.minY)
                if left || right { desiredFlipH = resizeFlipBaseline.h != crossedH }
                if top || bottom { desiredFlipV = resizeFlipBaseline.v != crossedV }
            }
            var frameInk: CGRect
            if rot == 0 {
                frameInk = shift ? Self.proportionalFrame(originalInk, handle: handle, cursor: cur)
                                 : Self.resizedFrame(originalInk, handle: handle, cursor: cur)
            } else {
                // Resize in the node's unrotated local space, then translate so the
                // anchored (opposite) corner stays put in world space.
                let c0 = CGPoint(x: originalInk.midX, y: originalInk.midY)
                let localCur = rotatePoint(cur, around: c0, byDegrees: -rot)
                let newLocal = shift ? Self.proportionalFrame(originalInk, handle: handle, cursor: localCur)
                                     : Self.resizedFrame(originalInk, handle: handle, cursor: localCur)
                let anchor = Self.anchorPoint(handle, in: originalInk)     // fixed in local space
                let worldBefore = rotatePoint(anchor, around: c0, byDegrees: rot)
                let c1 = CGPoint(x: newLocal.midX, y: newLocal.midY)
                let worldAfter = rotatePoint(anchor, around: c1, byDegrees: rot)
                frameInk = newLocal.offsetBy(dx: worldBefore.x - worldAfter.x,
                                             dy: worldBefore.y - worldAfter.y)
            }
            var frame = SelectionTransform.inset(frameInk, by: ink)
            // Whole-pixel resize (un-rotated only — a rotated frame's edges don't
            // sit on the pixel grid anyway). ⌘ bypasses.
            if snapToPixels && rot == 0 { frame = pxSnapRect(frame) }
            updateNode(id) { node in
                // Resizing a text box makes it a fixed-width paragraph (so it wraps
                // and keeps its width when the font changes), instead of hugging
                // one line.
                if case .text(var tc) = node.content {
                    tc.box = .fixed
                    node.content = .text(tc)
                }
                // Paths: scale the points (from the start-of-drag baseline) to fit
                // the new frame; box shapes just take the new frame. Multi-contour
                // paths (outlined text, compound shapes) render from `contours`,
                // not `points` — scale both, or the rendered shape stays put while
                // only the bounding box grows/shrinks.
                if case .path = node.content, let base = self.resizePathBaseline {
                    let sx = frame.width / max(1, original.width)
                    let sy = frame.height / max(1, original.height)
                    func scaledPoint(_ pt: PathPoint) -> PathPoint {
                        var q = pt
                        q.point = CGPoint(x: pt.point.x * sx, y: pt.point.y * sy)
                        q.controlIn = pt.controlIn.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
                        q.controlOut = pt.controlOut.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
                        return q
                    }
                    var ps = base
                    ps.points = ps.points.map(scaledPoint)
                    if let cs = ps.contours {
                        ps.contours = cs.map { $0.map(scaledPoint) }
                    }
                    node.content = .path(ps)
                }
                node.frame = frame
                if let h = desiredFlipH { node.flipH = h }
                if let v = desiredFlipV { node.flipV = v }
            }
            didEdit = true
            needsDisplay = true

        case .rotate(let id, let centerView, let lastAngle, let rawRotation):
            // `rotation` is stored in the node's PARENT-local space. Map the
            // pointer direction through the ancestor chain. Corner rotation is
            // DELTA-based (unlike the old top notch's absolute 0° direction), so
            // grabbing any of the four corners never makes the object jump.
            let angle = nodeRotationAngle(atViewPoint: p, id: id, centerView: centerView)
            var delta = angle - lastAngle
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            let raw = rawRotation + delta
            var displayed = raw.truncatingRemainder(dividingBy: 360)
            if displayed < 0 { displayed += 360 }
            if shift { displayed = (displayed / 15).rounded() * 15 }   // snap to 15°
            updateNode(id) { $0.rotation = displayed }
            dragMode = .rotate(id: id, centerView: centerView,
                               lastAngle: angle, rawRotation: raw)
            didEdit = true
            needsDisplay = true

        case .resizeSelection(let handle, let original):
            // `original` and the baseline frames live in the SELECTION SPACE, so the
            // cursor comes back into it too. With an empty chain this is `viewToDoc`.
            let cur = viewToSelectionSpace(p, chain: selectionDragChain)
            // `original` and `ink1` are INK rects — that is what the handle sits on,
            // so the box follows the cursor exactly. Everything written to the model
            // is the GEOMETRY inside them; the insets between are fixed for the drag.
            let ink1 = shift ? Self.proportionalFrame(original, handle: handle, cursor: cur)
                             : Self.resizedFrame(original, handle: handle, cursor: cur)
            let k = selectionDragInkInsets
            let g0 = SelectionTransform.inset(original, by: k)
            var g1 = SelectionTransform.inset(ink1, by: k)
            // Snap the GEOMETRY, not the ink: whole-pixel means the stored frame lands
            // on whole points, and a stroke width may legitimately be fractional.
            if snapToPixels { g1 = pxSnapRect(g1) }   // ⌘ bypasses
            let sx = g1.width / max(1, g0.width)
            let sy = g1.height / max(1, g0.height)
            let anchor = Self.anchorPoint(handle, in: g0)
            for (id, base) in selectionDragBaseline {
                let off = selectionDragOffsets[id] ?? .zero
                var t = SelectionTransform.scaled(base, about: anchor, sx: sx, sy: sy)
                t.frame = t.frame.offsetBy(dx: -off.x, dy: -off.y)
                updateNode(id) { $0 = t }
            }
            didEdit = true
            needsDisplay = true

        case .rotateSelection(let centerDoc, let startAngle):
            var delta = selectionSpaceAngle(ofViewPoint: p, aroundLocal: centerDoc,
                                            chain: selectionDragChain) - startAngle
            if shift { delta = (delta / 15).rounded() * 15 }   // snap to 15°
            for (id, base) in selectionDragBaseline {
                let off = selectionDragOffsets[id] ?? .zero
                var t = SelectionTransform.rotated(base, aboutDoc: centerDoc, deg: delta)
                t.frame = t.frame.offsetBy(dx: -off.x, dy: -off.y)
                updateNode(id) { $0 = t }
            }
            didEdit = true
            needsDisplay = true

        case .drawLine(let id, let startDoc):
            var endDoc = viewToDoc(p)
            if shift { endDoc = constrainLineEndpoint(endDoc, from: startDoc) }   // 45° snap
            let a = snapToPixels ? pxSnap(startDoc) : startDoc
            if snapToPixels { endDoc = pxSnap(endDoc) }
            setLine(id, aDoc: a, bDoc: endDoc)
            didEdit = true
            needsDisplay = true

        case .lineEndpoint(let id, let movingStart, let fixedDoc):
            var cur = viewToDoc(p)
            if shift { cur = constrainLineEndpoint(cur, from: fixedDoc) }   // 45° snap (incl. x/y axis)
            if snapToPixels { cur = pxSnap(cur) }
            setLine(id, aDoc: movingStart ? cur : fixedDoc, bDoc: movingStart ? fixedDoc : cur)
            didEdit = true
            needsDisplay = true

        case .artboards(let startDoc, let boardOrigins, let childOrigins):
            guard let document else { return }
            let now = viewToDoc(p)
            var dx = now.x - startDoc.x, dy = now.y - startDoc.y
            if shift { if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 } }   // axis lock
            if snapToPixels, let refX = boardOrigins.values.map(\.x).min(),
               let refY = boardOrigins.values.map(\.y).min() {
                dx = (refX + dx).rounded() - refX   // whole-pixel board landing (⌘ bypasses)
                dy = (refY + dy).rounded() - refY
            }
            withActivePage { page in
                for bi in page.artboards.indices {
                    if let o = boardOrigins[page.artboards[bi].id] {
                        page.artboards[bi].frame.origin = CGPoint(x: o.x + dx, y: o.y + dy)
                    }
                }
            }
            for (cid, origin0) in childOrigins {
                updateNode(cid) { $0.frame.origin = CGPoint(x: origin0.x + dx, y: origin0.y + dy) }
            }
            didEdit = true
            needsDisplay = true

        case .resizeArtboard(let id, let handle, let original):
            guard document != nil, let i = currentArtboards.firstIndex(where: { $0.id == id }) else { return }
            let cur = viewToDoc(p)
            var boardFrame = shift
                ? Self.proportionalFrame(original, handle: handle, cursor: cur)
                : Self.resizedFrame(original, handle: handle, cursor: cur)
            if snapToPixels { boardFrame = pxSnapRect(boardFrame) }
            withActivePage { $0.artboards[i].frame = boardFrame }
            didEdit = true
            needsDisplay = true

        case .resizeSource(let handle, let original):
            guard let document, let si = sourceIndex else { return }
            let cur = viewToDoc(p)
            var newRect = shift
                ? Self.proportionalFrame(original, handle: handle, cursor: cur)
                : Self.resizedFrame(original, handle: handle, cursor: cur)
            if snapToPixels { newRect = pxSnapRect(newRect) }
            document.model.sources[si].origin = newRect.origin
            document.model.sources[si].size = newRect.size
            didEdit = true
            needsDisplay = true

        case .penHandle(let nodeID, let anchorIndex):
            penHandleDrag(p, nodeID: nodeID, anchorIndex: anchorIndex, shift: shift)

        case .pathPoint(let nodeID, let target):
            pathPointDrag(p, nodeID: nodeID, target: target, shift: shift)

        case .pathPointGroup(let nodeID, let startLocal, let originals):
            pathPointGroupDrag(p, nodeID: nodeID, startLocal: startLocal, originals: originals, shift: shift)

        case .gradientEnd(let id, let movingStart):
            guard let n = node(id), let g0 = linearGradientFill(of: n) else { return }
            let rect = CGRect(origin: .zero, size: n.frame.size)
            var (u0, u1) = g0.unitLinearPoints(in: rect)
            var u = gradientViewToUnit(p, n, chain: ancestorGroups(of: id))
            if shift {
                u = Self.constrainedGradientEnd(u, from: movingStart ? u1 : u0,
                                                size: n.frame.size)
            }
            if movingStart { u0 = u } else { u1 = u }
            // `settingLine` also refreshes `angle`, which is what keeps the
            // inspector's numeric field live and truthful while the line is dragged.
            setGradientFill(g0.settingLine(start: u0, end: u1, in: rect), on: id)
            didEdit = true
            needsDisplay = true

        case .gradientStop(let id, let stopID):
            guard let n = node(id), var g = linearGradientFill(of: n),
                  let i = g.stops.firstIndex(where: { $0.id == stopID }) else { return }
            let rect = CGRect(origin: .zero, size: n.frame.size)
            let (u0, u1) = g.unitLinearPoints(in: rect)
            // Project onto the line in LOCAL POINTS, not unit space: on a non-square
            // shape the two are not the same direction, and projecting in unit space
            // would slide the stop to the wrong place.
            let a = CGPoint(x: u0.x * n.frame.width, y: u0.y * n.frame.height)
            let b = CGPoint(x: u1.x * n.frame.width, y: u1.y * n.frame.height)
            let cur = viewToNodeLocal(p, n, chain: ancestorGroups(of: id))
            let vx = b.x - a.x, vy = b.y - a.y
            let len2 = vx * vx + vy * vy
            guard len2 > 1e-9 else { return }
            let t = ((cur.x - a.x) * vx + (cur.y - a.y) * vy) / len2
            g.stops[i].position = min(1, max(0, t))
            setGradientFill(g, on: id)
            didEdit = true
            needsDisplay = true

        case .resizePoints(let nodeID, let handle, let original, let originals):
            guard let n = node(nodeID) else { return }
            let cur = viewToNodeLocal(p, n, chain: ancestorGroups(of: nodeID))
            let box = shift ? Self.proportionalFrame(original, handle: handle, cursor: cur)
                            : Self.resizedFrame(original, handle: handle, cursor: cur)
            // A degenerate axis (every selected point on one line) cannot be scaled;
            // leave it at 1 rather than dividing by ~0 and throwing the points away.
            let sx = original.width  > 0.001 ? box.width  / original.width  : 1
            let sy = original.height > 0.001 ? box.height / original.height : 1
            let anchor = Self.anchorPoint(handle, in: original)
            applyPointTransform(nodeID: nodeID, originals: originals) { pt in
                CGPoint(x: anchor.x + (pt.x - anchor.x) * sx,
                        y: anchor.y + (pt.y - anchor.y) * sy)
            }
            didEdit = true
            needsDisplay = true

        case .rotatePoints(let nodeID, let centerLocal, let startAngle, let originals):
            guard let n = node(nodeID) else { return }
            var delta = pointBoxAngle(ofViewPoint: p, aroundLocal: centerLocal,
                                      node: n, chain: ancestorGroups(of: nodeID)) - startAngle
            if shift { delta = (delta / 15).rounded() * 15 }   // same 15° snap as elsewhere
            applyPointTransform(nodeID: nodeID, originals: originals) { pt in
                rotatePoint(pt, around: centerLocal, byDegrees: delta)
            }
            didEdit = true
            needsDisplay = true

        case .pencilStroke:
            pencilMouseDragged(p)

        case .marquee:
            marqueeCurrent = p
            needsDisplay = true

        case .pointMarquee:
            marqueeCurrent = p
            needsDisplay = true

        case .drawTextBox:
            marqueeCurrent = p
            needsDisplay = true

        case .guide:
            updateGuideDrag(at: p)

        case .none:
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let mode = dragMode
        let p = convert(event.locationInWindow, from: nil)

        switch mode {
        case .hand:
            refreshCursor()

        case .draw(let id, _):
            updateNode(id) {
                if $0.frame.width < 3 || $0.frame.height < 3 { $0.frame.size = CGSize(width: 100, height: 100) }
            }
            registerUndoForGesture()
            app?.tool = .select
            refreshCursor()

        case .pencilStroke:
            finishPencilStroke()

        case .drawArtboard(let id, _):
            // A bare click lands the same default the New Artboard menu's primary
            // action uses, so the two routes agree on what "an artboard" means.
            withActivePage { page in
                guard let i = page.artboards.firstIndex(where: { $0.id == id }) else { return }
                if page.artboards[i].frame.width < 3 || page.artboards[i].frame.height < 3 {
                    page.artboards[i].frame.size = Self.defaultDrawnArtboardSize
                }
            }
            registerUndoForGesture()
            app?.tool = .select
            refreshCursor()

        case .drawLine(let id, let startDoc):
            // A bare click makes a default 100pt horizontal line.
            if let n = node(id), let (a, b) = lineEndpointsDoc(n), hypot(b.x - a.x, b.y - a.y) < 3 {
                setLine(id, aDoc: startDoc, bDoc: CGPoint(x: startDoc.x + 100, y: startDoc.y))
            }
            registerUndoForGesture()
            app?.tool = .select
            refreshCursor()

        case .nodes, .resize, .rotate, .artboards, .resizeArtboard, .resizeSource, .lineEndpoint:
            if didEdit { registerUndoForGesture() }

        case .resizeSelection, .rotateSelection:
            if didEdit { registerUndoForGesture() }
            selectionDragBaseline = [:]
            selectionDragOffsets = [:]
            selectionDragChain = []
            selectionDragInkInsets = .zero

        case .penHandle:
            break   // pen session continues; one undo is registered at finishPen()

        case .pathPoint(let nodeID, _):
            if didEdit { normalizePath(nodeID); registerUndoForGesture() }

        case .gradientEnd:
            if didEdit { registerUndoForGesture() }

        case .gradientStop(let id, let stopID):
            if didEdit { registerUndoForGesture() }
            // Press-and-release with no movement is a CLICK: open the stop's editor
            // right where the knob is, which is the whole point of editing colour on
            // the canvas instead of in a panel that moves out from under you.
            else if gradientStopClickCandidate == stopID {
                showGradientStopEditor(nodeID: id, stopID: stopID)
            }

        case .resizePoints(let nodeID, _, _, _), .rotatePoints(let nodeID, _, _, _):
            // Same close-out as any other point edit: the frame has to be refitted to
            // the moved points or hit-testing and bounds go stale.
            if didEdit { normalizePath(nodeID); registerUndoForGesture() }

        case .pathPointGroup(let nodeID, _, _):
            if didEdit { normalizePath(nodeID); registerUndoForGesture() }
            else if pointGroupFromBody { setSelectedPoints([]) }   // click on body = deselect

        case .marquee(let start, let additive):
            finishMarquee(start: start, end: p, additive: additive)

        case .pointMarquee(let start, let additive):
            finishPointMarquee(start: start, end: p, additive: additive)

        case .drawTextBox(let originView):
            finishTextBox(start: originView, end: p)

        case .guide:
            finishGuideDrag(at: p)

        case .none:
            break
        }

        dragMode = .none
        gradientStopClickCandidate = nil
        dragBaseline = nil
        dragCopyActive = false
        dragCopySourceSelection = []
        resizePathBaseline = nil
        lastDragPoint = nil
        marqueeCurrent = nil
        didEdit = false
        activeSmartGuides = []  // Clear smart guides when drag ends
        needsDisplay = true
    }

    private func finishMarquee(start: CGPoint, end: CGPoint, additive: Bool) {
        guard let app, let document else { return }
        if hypot(end.x - start.x, end.y - start.y) <= 3 {
            // Plain click on empty space.
            if !additive {
                app.selectedNodeIDs = []
                app.selectedArtboardID = hitTestArtboard(atViewPoint: start)?.id
            }
            return
        }
        let rectDoc = viewToDoc(CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                       width: abs(end.x - start.x), height: abs(end.y - start.y)))

        // Lasso that fully encloses one or more artboards selects the BOARDS
        // (you're arranging boards). Partial drags still select items below.
        if !isSourceScope {
            let enclosed = currentArtboards.filter { rectDoc.contains($0.frame) }
            if !enclosed.isEmpty {
                let ids = Set(enclosed.map { $0.id })
                app.selectedArtboardIDs = additive ? app.selectedArtboardIDs.union(ids) : ids
                app.selectedNodeIDs = []
                return
            }
        }

        var hits = Set<UUID>()
        for node in currentNodes where node.isVisible && !node.isLocked {
            if node.frame.intersects(rectDoc) { hits.insert(node.id) }
        }
        app.selectedNodeIDs = additive ? app.selectedNodeIDs.union(hits) : hits
        if !app.selectedNodeIDs.isEmpty { app.selectedArtboardIDs = [] }
    }

    private func registerUndoForGesture() {
        guard let document, let baseline = dragBaseline else { return }
        if !isSourceScope {
            document.model.reconcileArtboardOwnership(on: activePageID)
        }
        document.registerUndo(restoring: baseline, undoManager: undoManager, actionName: gestureUndoName)
    }

    // MARK: Text

    /// Seed a new node from the type tool's app-wide memory. A remembered face may
    /// have been removed since the prior launch; fall back to System for creation
    /// rather than writing an unavailable PostScript name into the document.
    private func rememberedTextContent() -> TextContent {
        let style = app?.rememberedTextStyle ?? RememberedTextStyle()
        let fontName = style.fontName.isEmpty
            || NSFont(name: style.fontName, size: style.fontSize) != nil
            ? style.fontName : ""
        return TextContent(string: "", fontSize: style.fontSize,
                           color: style.color, fontName: fontName)
    }

    /// Place a new text node at a click and immediately edit it.
    private func placeTextNode(at viewPoint: CGPoint) {
        guard let app, let document else { return }
        textEditBaseline = document.model
        let origin = pxSnap(viewToDoc(viewPoint))   // whole-pixel text placement
        let content = rememberedTextContent()
        let size = content.measuredSize()   // placeholder box (font-aware)
        let node = Node(name: "Text",
                        frame: CGRect(origin: origin, size: size),
                        content: .text(content))
        withNodes { $0.append(node) }
        app.selectedArtboardID = nil
        app.selectedNodeIDs = [node.id]
        beginEditingText(nodeID: node.id, isNew: true)
    }

    /// Finish a text-tool drag: a tiny drag = a click (auto-width node); a real
    /// drag = a fixed-width paragraph box of that size. Then edit it inline.
    private func finishTextBox(start: CGPoint, end: CGPoint) {
        if abs(end.x - start.x) < 6 || abs(end.y - start.y) < 6 {
            placeTextNode(at: start)
            return
        }
        guard let app, let document else { return }
        textEditBaseline = document.model
        let viewRect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y))
        var content = rememberedTextContent()
        content.box = .fixed
        let node = Node(name: "Text", frame: pxSnapRect(viewToDoc(viewRect)), content: .text(content))
        withNodes { $0.append(node) }
        app.selectedArtboardID = nil
        app.selectedNodeIDs = [node.id]
        beginEditingText(nodeID: node.id, isNew: true)
    }

    /// Show the NSTextView overlay over a text node and start editing.
    ///
    /// FEAT-024: entering edit mode SELECTS the existing contents rather than
    /// placing a caret. Double-clicking a text node is already a commitment to
    /// editing it, and typing over the whole string is the common case; a further
    /// click inside the now-focused editor places a caret normally, so a
    /// one-character edit is still one click away. The editor is a stock
    /// `NSTextView`, so every standard caret/selection key, alternative input
    /// method, and user key binding keeps working — this changes only the range
    /// the editor opens with.
    private func beginEditingText(nodeID: UUID, isNew: Bool) {
        guard let document, let target = node(nodeID),
              case .text(let tc) = target.content else { return }
        app?.rememberTextStyle(fontName: tc.firstRun.fontName,
                               fontSize: tc.firstRun.fontSize,
                               color: tc.firstRun.color)
        if editingNodeID != nil { commitTextEditing() }
        if textEditBaseline == nil { textEditBaseline = document.model }

        let zoom = app?.zoom ?? 1
        textEditScale = zoom
        let fixed = tc.box == .fixed
        // Place the editor at the node's ABSOLUTE frame — a nested node's own
        // frame is in its group's local space, so add the ancestor offset.
        let nodeAbsOrigin = nodeOffset(nodeID)
        let absFrame = target.frame.offsetBy(dx: nodeAbsOrigin.x, dy: nodeAbsOrigin.y)
        let base = docToView(absFrame)
        let slack = ceil(tc.firstRun.fontSize * zoom)  // a line of slack so nothing clips
        // Match the canvas's text container width so alignment renders identically
        // (a wider editor box made centred/right-aligned text shift sideways while
        // editing). Only a brand-new, empty node needs extra room to type into.
        let editWidth = fixed ? base.width : max(base.width, isNew ? 220 : 1)
        let tv = NSTextView(frame: CGRect(x: base.minX, y: base.minY,
                                          width: editWidth,
                                          height: max(base.height + slack, ceil(tc.firstRun.fontSize * zoom * 1.8))))
        tv.isRichText = true                 // rich: per-selection bold/italic/underline
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        if fixed {
            tv.isHorizontallyResizable = false
            tv.textContainer?.widthTracksTextView = true
            tv.textContainer?.containerSize = CGSize(width: base.width, height: .greatestFiniteMagnitude)
        }
        tv.textStorage?.setAttributedString(tc.attributedString(scale: textEditScale, applyCase: false))
        tv.typingAttributes = [
            .font: tc.firstRun.nsFont(scale: textEditScale),
            .foregroundColor: PaintRender.nsColor(tc.firstRun.color)
        ]
        tv.delegate = self
        addSubview(tv)
        window?.makeFirstResponder(tv)

        // Select what is already there (FEAT-024); an empty or brand-new node has
        // nothing to select, so it just gets a caret.
        let length = tv.string.utf16.count
        tv.setSelectedRange(NSRange(location: 0, length: length))
        // Announce the opening selection explicitly. AppKit posts this for ordinary
        // selection changes, but the range is set here as part of taking focus, and
        // a VoiceOver user needs to hear that the text is selected before typing
        // replaces it.
        NSAccessibility.post(element: tv, notification: .selectedTextChanged)

        textEditor = tv
        editingNodeID = nodeID
        editingIsNew = isNew
        editorSelectedRange = tv.selectedRange()
        captureTextEditSnapshot()
        // Inspector controls call this directly (synchronously) while editing.
        app?.applyTextStyle = { [weak self] op in self?.applyTextStyleOp(op) }
        publishTextSelection()
        needsDisplay = true
    }

    private func syncTextEditorFrameToModel() {
        guard let tv = textEditor, let id = editingNodeID,
              let target = node(id), case .text(let tc) = target.content else { return }
        let zoom = app?.zoom ?? 1
        let fixed = tc.box == .fixed
        let nodeAbsOrigin = nodeOffset(id)
        let absFrame = target.frame.offsetBy(dx: nodeAbsOrigin.x, dy: nodeAbsOrigin.y)
        let base = docToView(absFrame)
        let slack = ceil(tc.firstRun.fontSize * zoom)
        let editWidth = fixed ? base.width : max(base.width, editingIsNew ? 220 : 1)
        tv.frame = CGRect(x: base.minX, y: base.minY,
                          width: editWidth,
                          height: max(base.height + slack, ceil(tc.firstRun.fontSize * zoom * 1.8)))
        tv.textContainer?.widthTracksTextView = true
        if fixed {
            tv.textContainer?.containerSize = CGSize(width: base.width, height: .greatestFiniteMagnitude)
        }
    }

    /// Write the edited string back to the model (one undo step), or discard a
    /// brand-new empty node. Called when the user clicks away or the field ends.
    /// Commit if the selected node changed out from under an open editor.
    func commitTextEditingIfSelectionChanged() {
        guard let id = editingNodeID, let app else { return }
        if !app.selectedNodeIDs.contains(id) { commitTextEditing(keepNodeSelected: false) }
    }

    private func commitTextEditing(keepNodeSelected: Bool = true) {
        guard !committingText, let tv = textEditor, let id = editingNodeID, let document else { return }
        committingText = true
        defer { committingText = false }

        // If an Inspector field (for example font size) is first responder, ask
        // it to commit while the live editor hook is still installed. Do not make
        // the NSTextView first responder again: that focus/selection round-trip is
        // the path that could erase selected-run attributes on direct click-out.
        if window?.firstResponder !== tv {
            window?.endEditing(for: nil)
        }

        // Inspector style changes were already applied synchronously to the editor
        // (via app.applyTextStyle), so the editor's attributed string is the source
        // of truth here. Tear down the live hook so stray calls can't target a
        // committed editor.
        app?.applyTextStyle = nil

        // Text/style delegate paths update this snapshot synchronously. It is the
        // source of truth at commit so AppKit's first-responder teardown cannot
        // flatten or otherwise alter rich-text runs before model reconstruction.
        let edited = textEditSnapshot
            ?? tv.textStorage.map { NSAttributedString(attributedString: $0) }
            ?? tv.attributedString()
        let scale = textEditScale
        tv.removeFromSuperview()
        textEditor = nil
        textEditSnapshot = nil
        editingNodeID = nil
        let wasNew = editingIsNew
        editingIsNew = false
        let baseline = textEditBaseline
        textEditBaseline = nil

        let trimmed = edited.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && wasNew {
            // Never really created — silently drop it (no undo, no dirtying).
            if let baseline { document.model = baseline }
            if keepNodeSelected { app?.selectedNodeIDs = [] }
        } else if let target = node(id), case .text(let old) = target.content {
            // Rebuild styled runs from the edited attributed string (keep the
            // node's paragraph settings).
            let tc = TextContent(attributed: edited, scale: scale, align: old.align,
                                 lineHeight: old.lineHeight, lineHeightUnit: old.lineHeightUnit,
                                 tracking: old.tracking, box: old.box, textCase: old.textCase,
                                 centersFixedLineHeightLeading: old.centersFixedLineHeightLeading)
            // Auto hugs; fixed keeps its box (text may overflow → badge).
            let newSize = old.box == .auto ? tc.measuredSize() : target.frame.size
            // Recursive so a text node INSIDE a group is written back too.
            updateNode(id) { node in
                node.content = .text(tc)
                node.frame.size = newSize
            }
            if let baseline {
                document.registerUndo(restoring: baseline, undoManager: undoManager,
                                      actionName: wasNew ? "Add Text" : "Edit Text")
            }
            // Leave the text box SELECTED after committing (Esc / click-out) so it can
            // be grabbed and moved immediately — including for auto-layout reordering.
            if keepNodeSelected {
                app?.selectedNodeIDs = [id]
                app?.selectedArtboardID = nil
            }
        }

        app?.textSelection = nil
        app?.tool = .select
        // A canvas-originated commit should return keyboard focus to the canvas.
        // If selection changed elsewhere (for example in Layers), leave focus
        // with the control the user actually clicked.
        if keepNodeSelected {
            window?.makeFirstResponder(self)
            refreshCursor()
        }
        needsDisplay = true
    }

    // (text sizing now lives on TextContent.measuredSize() — font-aware)

    // MARK: Text styling (Bold / Italic / Underline)
    //
    // While editing, these affect the NSTextView's selection (or typing
    // attributes when nothing is selected). Otherwise they toggle the whole
    // selected text node. Reached via the Format menu (⌘B/⌘I/⌘U) and the
    // inspector buttons through the responder chain.

    @objc func toggleBoldText(_ sender: Any?)   { applyFontTrait(.boldFontMask) }
    @objc func toggleItalicText(_ sender: Any?) { applyFontTrait(.italicFontMask) }

    private func toggledFont(_ f: NSFont, _ trait: NSFontTraitMask) -> NSFont {
        let fm = NSFontManager.shared
        return fm.traits(of: f).contains(trait)
            ? fm.convert(f, toNotHaveTrait: trait)
            : fm.convert(f, toHaveTrait: trait)
    }

    private func applyFontTrait(_ trait: NSFontTraitMask) {
        if editingNodeID != nil, let tv = textEditor, let storage = tv.textStorage {
            let sel = effectiveEditorRange()
            if sel.length > 0, tv.selectedRange() != sel { tv.setSelectedRange(sel) }
            if sel.length == 0 {
                let f = (tv.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 16)
                tv.typingAttributes[.font] = toggledFont(f, trait)
                return
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: sel, options: []) { val, sub, _ in
                let f = (val as? NSFont) ?? .systemFont(ofSize: 16)
                storage.addAttribute(.font, value: self.toggledFont(f, trait), range: sub)
            }
            storage.endEditing()
            captureTextEditSnapshot()
            tv.didChangeText()
            publishTextSelection()
            needsDisplay = true
        } else if let id = app?.singleSelectedNodeID {
            toggleWholeText(id) { tc in
                let fm = NSFontManager.shared
                let firstHas = fm.traits(of: tc.firstRun.nsFont()).contains(trait)
                tc.applyToAllRuns { run in
                    let f = run.nsFont()
                    let nf = firstHas ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait)
                    run.fontName = (nf.fontName == NSFont.systemFont(ofSize: nf.pointSize).fontName) ? "" : nf.fontName
                }
            }
        }
    }

    @objc func toggleUnderlineText(_ sender: Any?) {
        if editingNodeID != nil, let tv = textEditor, let storage = tv.textStorage {
            let sel = effectiveEditorRange()
            if sel.length > 0, tv.selectedRange() != sel { tv.setSelectedRange(sel) }
            if sel.length == 0 {
                let cur = (tv.typingAttributes[.underlineStyle] as? Int) ?? 0
                tv.typingAttributes[.underlineStyle] = cur == 0 ? NSUnderlineStyle.single.rawValue : 0
                return
            }
            let firstOn = ((storage.attribute(.underlineStyle, at: sel.location, effectiveRange: nil) as? Int) ?? 0) != 0
            storage.beginEditing()
            if firstOn { storage.removeAttribute(.underlineStyle, range: sel) }
            else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: sel) }
            storage.endEditing()
            captureTextEditSnapshot()
            tv.didChangeText()
            needsDisplay = true
        } else if let id = app?.singleSelectedNodeID {
            toggleWholeText(id) { tc in
                let on = tc.firstRun.underline
                tc.applyToAllRuns { $0.underline = !on }
            }
        }
    }

    /// Apply a styling change to the whole selected text node (one undo step).
    private func toggleWholeText(_ id: UUID, _ change: (inout TextContent) -> Void) {
        guard let n = node(id), case .text(var tc) = n.content else { return }
        change(&tc)
        var nodes = currentNodes
        guard let i = nodes.firstIndex(where: { $0.id == id }) else { return }
        app?.rememberTextStyle(fontName: tc.firstRun.fontName,
                               fontSize: tc.firstRun.fontSize,
                               color: tc.firstRun.color)
        nodes[i].content = .text(tc)
        nodes[i].frame.size = tc.measuredSize(boxWidth: nodes[i].frame.width)
        commitNodes(nodes, actionName: "Text Style")
    }

    // MARK: Inspector → text (font / size / color), selection-aware

    private func captureTextEditSnapshot() {
        guard editingNodeID != nil, let storage = textEditor?.textStorage else { return }
        textEditSnapshot = NSAttributedString(attributedString: storage)
    }

    /// The range an Inspector style op should target: the live selection while the
    /// editor is focused, otherwise the last user-driven selection (since clicking
    /// the Inspector collapses the live one). Clamped to the current text length.
    private func effectiveEditorRange() -> NSRange {
        guard let tv = textEditor else { return NSRange(location: 0, length: 0) }
        let live = tv.selectedRange()
        let r = (window?.firstResponder === tv) ? live : (editorSelectedRange.length > 0 ? editorSelectedRange : live)
        let len = (tv.textStorage?.length ?? tv.string.utf16.count)
        let loc = min(r.location, len)
        return NSRange(location: loc, length: min(r.length, len - loc))
    }

    /// Apply a font/size/color from the Inspector: to the editor selection while
    /// editing, otherwise to the whole selected text node.
    func applyTextStyleOp(_ op: AppState.TextStyleOp) {
        if editingNodeID != nil, let tv = textEditor, let storage = tv.textStorage {
            // Paragraph props (align/line-height/spacing) are node-level: re-sync
            // the editor's paragraph style from the (just-updated) model so they
            // show live while editing.
            if case .paragraph = op {
                if let id = editingNodeID, case .text(let tc)? = node(id)?.content {
                    let para = tc.paragraphStyle(scale: textEditScale)
                    storage.addAttribute(.paragraphStyle, value: para,
                                         range: NSRange(location: 0, length: storage.length))
                    tv.typingAttributes[.paragraphStyle] = para
                    syncTextEditorFrameToModel()
                    captureTextEditSnapshot()
                    tv.didChangeText()
                    needsDisplay = true
                }
                return
            }
            let scale = textEditScale
            let sel = effectiveEditorRange()
            // The op may target a stored selection while the editor is unfocused,
            // so reassert it as the live selection too (keeps the highlight + makes
            // the change visible immediately).
            if sel.length > 0, tv.selectedRange() != sel { tv.setSelectedRange(sel) }
            let fm = NSFontManager.shared
            func newFont(_ existing: NSFont) -> NSFont {
                switch op {
                case .fontName(let ps):
                    let size = existing.pointSize
                    return ps.isEmpty ? .systemFont(ofSize: size) : (NSFont(name: ps, size: size) ?? .systemFont(ofSize: size))
                case .fontSize(let pts):
                    return fm.convert(existing, toSize: max(1, pts * scale))
                default:
                    return existing
                }
            }
            if sel.length == 0 {
                if case .color(let c) = op {
                    tv.typingAttributes[.foregroundColor] = PaintRender.nsColor(c)
                } else {
                    let f = (tv.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 16)
                    tv.typingAttributes[.font] = newFont(f)
                }
            } else {
                storage.beginEditing()
                if case .color(let c) = op {
                    storage.addAttribute(.foregroundColor, value: PaintRender.nsColor(c), range: sel)
                } else {
                    storage.enumerateAttribute(.font, in: sel, options: []) { val, sub, _ in
                        let f = (val as? NSFont) ?? .systemFont(ofSize: 16)
                        storage.addAttribute(.font, value: newFont(f), range: sub)
                    }
                }
                storage.endEditing()
            }
            captureTextEditSnapshot()
            tv.didChangeText()
            publishTextSelection()
            needsDisplay = true
        } else if let id = app?.singleSelectedNodeID {
            toggleWholeText(id) { tc in
                tc.applyToAllRuns { run in
                    switch op {
                    case .fontName(let ps): run.fontName = ps
                    case .fontSize(let pts): run.fontSize = max(1, pts)
                    case .color(let c): run.color = c
                    case .paragraph: break   // node-level; handled while editing only
                    }
                }
            }
        }
    }

    /// Set `app.textSelection` on the NEXT runloop tick. This is called from
    /// AppKit delegate callbacks that can fire during the window's layout pass
    /// (which SwiftUI drives); assigning synchronously there is "publishing changes
    /// from within view updates". Deferring keeps it out of any update cycle.
    private func setTextSelection(_ s: AppState.TextSelectionStyle?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if s != nil, self.editingNodeID == nil { return }
            if let s {
                self.app?.rememberTextStyle(fontName: s.fontName,
                                            fontSize: s.fontSize,
                                            color: s.color)
            }
            guard self.app?.textSelection != s else { return }
            self.app?.textSelection = s
        }
    }

    /// Summarize the current editor selection's style into AppState so the
    /// Inspector reflects it (nil component = mixed across the selection).
    func publishTextSelection() {
        guard editingNodeID != nil, let tv = textEditor, let storage = tv.textStorage else {
            setTextSelection(nil)
            return
        }
        let scale = textEditScale
        let fm = NSFontManager.shared
        var faces = Set<String>(), sizes = Set<Double>(), colors = Set<String>()
        var bolds = Set<Bool>(), italics = Set<Bool>(), unders = Set<Bool>()

        func record(font: NSFont, color: NSColor?, underline: Bool) {
            let isSystem = font.fontName == NSFont.systemFont(ofSize: font.pointSize).fontName
            faces.insert(isSystem ? "" : font.fontName)
            let logicalSize = Double(font.pointSize / max(scale, 0.0001))
            sizes.insert((logicalSize * 1_000).rounded() / 1_000)
            let t = fm.traits(of: font)
            bolds.insert(t.contains(.boldFontMask)); italics.insert(t.contains(.italicFontMask))
            let c = (color ?? .black).usingColorSpace(.sRGB) ?? .black
            colors.insert("\(c.redComponent),\(c.greenComponent),\(c.blueComponent),\(c.alphaComponent)")
            unders.insert(underline)
        }

        let sel = effectiveEditorRange()
        if sel.length == 0 {
            let f = (tv.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 16)
            record(font: f, color: tv.typingAttributes[.foregroundColor] as? NSColor,
                   underline: ((tv.typingAttributes[.underlineStyle] as? Int) ?? 0) != 0)
        } else {
            storage.enumerateAttributes(in: sel, options: []) { attrs, _, _ in
                let f = (attrs[.font] as? NSFont) ?? .systemFont(ofSize: 16)
                record(font: f, color: attrs[.foregroundColor] as? NSColor,
                       underline: ((attrs[.underlineStyle] as? Int) ?? 0) != 0)
            }
        }
        func uniformColor() -> RGBAColor? {
            guard colors.count == 1 else { return nil }
            let parts = colors.first!.split(separator: ",").compactMap { Double($0) }
            return parts.count == 4 ? RGBAColor(r: parts[0], g: parts[1], b: parts[2], a: parts[3]) : nil
        }
        setTextSelection(AppState.TextSelectionStyle(
            fontName: faces.count == 1 ? faces.first : nil,
            fontSize: sizes.count == 1 ? CGFloat(sizes.first!) : nil,
            color: uniformColor(),
            bold: bolds.count == 1 ? bolds.first : nil,
            italic: italics.count == 1 ? italics.first : nil,
            underline: unders.count == 1 ? unders.first : nil))
    }

    // MARK: Node helpers

    private func makeNode(for tool: Tool, frame: CGRect) -> Node {
        let fill = Paint.solid(RGBAColor(r: 0.85, g: 0.85, b: 0.85, a: 1))
        switch tool {
        case .ellipse:
            return Node(name: "Ellipse", frame: frame, content: .ellipse(EllipseShape(fill: fill)))
        case .polygon:
            let sides = app?.polygonSides ?? 3
            return Node(name: "Polygon", frame: frame, content: .polygon(PolygonShape(sides: sides, fill: fill)))
        default:
            return Node(name: "Rectangle", frame: frame, content: .rectangle(RectangleShape(fill: fill, cornerRadius: 0)))
        }
    }

    /// A copy of `node` with fresh ids throughout, and its anchored relationships
    /// re-pointed at the COPY.
    ///
    /// The remap is not optional. Duplicating a group used to carry its
    /// relationships across verbatim, still naming the ORIGINAL's nodes — so the
    /// copy described the original's structure instead of its own (BUG-010). Ids
    /// outside the copied subtree are deliberately left alone: a source child id is
    /// stable across every placement, and a link that genuinely points outside the
    /// copy should keep doing so.
    private func cloned(_ node: Node) -> Node {
        Document.duplicatingNode(node)
    }

    private func selectedNodeOrigins() -> [UUID: CGPoint] {
        guard let app else { return [:] }
        var result: [UUID: CGPoint] = [:]
        // Recursive `node(_:)` resolves nested children too; their frame.origin is in
        // the parent group's local space, and a move applies the same doc-space delta
        // (groups aren't scaled), so this is correct for nested moves.
        for id in app.selectedNodeIDs {
            if let n = node(id) { result[id] = n.frame.origin }
        }
        return result
    }

    /// True when `docPoint` is on the actual ink/surface of any selected root.
    /// This deliberately does not ask `hitPath`, whose answer is z-ordered and
    /// therefore cannot see a selected layer underneath another one.
    private func selectedGeometryContains(_ docPoint: CGPoint) -> Bool {
        guard let app else { return false }
        for id in app.selectedNodeIDs where !hasSelectedAncestor(id) {
            guard let selected = node(id), selected.isVisible, !selected.isLocked else { continue }
            let pointInParent = docToParentLocal(docPoint, chain: ancestorGroups(of: id))
            if nodeHit(selected, at: pointInParent) { return true }
        }
        return false
    }

    /// Arm the standard selection drag without changing which nodes are selected.
    /// Shared by ordinary Auto-select clicks and selected-layer mode so Option-drag,
    /// nested movement, smart guides, and one-step undo remain one implementation.
    private func beginSelectedNodeDrag(at startDoc: CGPoint) {
        guard let app, let document else { return }
        dragBaseline = document.model
        // Option-drag duplicates the selection in place (nested items included) —
        // but the decision is DEFERRED to the drag and re-read live from there.
        // See the `.nodes` case in mouseDragged and `setDragCopy` (BUG-025).
        dragCopyActive = false
        dragCopySourceSelection = app.selectedNodeIDs
        gestureUndoName = "Move Shape"
        dragMode = .nodes(startDoc: startDoc, origins: selectedNodeOrigins())
        needsDisplay = true
    }

    /// Flip the in-progress `.nodes` drag between moving the originals and
    /// dragging fresh copies, without ending the gesture (BUG-025).
    ///
    /// Implemented as REWIND-THEN-REAPPLY rather than by surgically deleting the
    /// copies. `dragBaseline` is the model exactly as it stood at mouseDown, so
    /// restoring it is both easier to reason about and immune to whatever else the
    /// drag has already touched along the way — artboard membership, reparenting,
    /// snapping. Trying to unpick just the copies would have to know about all of
    /// that and would rot the first time one of them changed.
    ///
    /// This runs ONLY when the modifier actually changes, never per drag tick, so
    /// the whole-model copy is off the hot path. Undo is unaffected: gesture undo is
    /// registered once at mouseUp from `dragBaseline`, and `withNodes` mutates live
    /// without registering anything, so flipping back and forth mid-drag still
    /// yields exactly one undo step named for whichever state the drag ended in.
    private func setDragCopy(_ on: Bool, startDoc: CGPoint) {
        guard let app, let document, let baseline = dragBaseline else { return }
        document.model = baseline
        app.selectedNodeIDs = dragCopySourceSelection
        if on {
            let copies = duplicateSelectedInPlace(offset: .zero)
            app.selectedNodeIDs = Set(copies)
            gestureUndoName = "Duplicate"
        } else {
            gestureUndoName = "Move Shape"
        }
        dragCopyActive = on
        dragMode = .nodes(startDoc: startDoc, origins: selectedNodeOrigins())
        needsDisplay = true
    }

    /// Append clones of the current selection (live, no undo registration — the
    /// caller owns the single undo step). Returns the new ids.
    @discardableResult
    private func duplicateSelectedInPlace(offset: CGPoint) -> [UUID] {
        guard let app else { return [] }
        var newIDs: [UUID] = []
        withNodes { nodes in
            let duplication = Document.duplicatingNodes(
                app.selectedNodeIDs, in: nodes, offset: offset)
            nodes = duplication.nodes
            newIDs = duplication.copiedIDs
        }
        return newIDs
    }

    /// Duplicate the given artboards AND every shape they own, offset by `offset`
    /// (new ids throughout). Mutates the document live — the caller owns the
    /// single undo step. Returns the new boards' origins + the new children's
    /// origins, ready to seed an `.artboards` drag.
    private func duplicateArtboards(_ ids: [UUID], offset: CGPoint)
        -> (boardOrigins: [UUID: CGPoint], childOrigins: [UUID: CGPoint]) {
        guard let document else { return ([:], [:]) }
        var model = document.model
        guard let pageIndex = model.pageIndex(for: activePageID) else { return ([:], [:]) }
        var boardOrigins: [UUID: CGPoint] = [:]
        var childOrigins: [UUID: CGPoint] = [:]
        for id in ids {
            guard let ab = model.pages[pageIndex].artboards.first(where: { $0.id == id }) else { continue }
            var newAb = ab
            newAb.id = UUID()
            newAb.name = ab.name + " copy"
            newAb.frame.origin.x += offset.x
            newAb.frame.origin.y += offset.y
            // Copy the shapes this board owns (decided against the original model).
            let owned = currentNodes.filter {
                owningArtboard(of: $0)?.id == id
            }
            for original in owned {
                var copy = cloned(original)
                copy.frame.origin.x += offset.x
                copy.frame.origin.y += offset.y
                copy.artboardID = newAb.id
                model.pages[pageIndex].nodes.append(copy)
                childOrigins[copy.id] = copy.frame.origin
            }
            model.pages[pageIndex].artboards.append(newAb)
            boardOrigins[newAb.id] = newAb.frame.origin
        }
        document.model = model
        return (boardOrigins, childOrigins)
    }

    private static func resizedFrame(_ o: CGRect, handle: Handle, cursor p: CGPoint) -> CGRect {
        var l = o.minX, t = o.minY, r = o.maxX, b = o.maxY
        switch handle {
        case .left: l = p.x
        case .right: r = p.x
        case .top: t = p.y
        case .bottom: b = p.y
        case .topLeft: l = p.x; t = p.y
        case .topRight: r = p.x; t = p.y
        case .bottomLeft: l = p.x; b = p.y
        case .bottomRight: r = p.x; b = p.y
        }
        return CGRect(x: min(l, r), y: min(t, b), width: max(1, abs(r - l)), height: max(1, abs(b - t)))
    }

    private static func proportionalFrame(_ o: CGRect, handle: Handle, cursor p: CGPoint) -> CGRect {
        let aspect = o.height == 0 ? 1 : o.width / o.height
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let anchor: CGPoint
            switch handle {
            case .topLeft:     anchor = CGPoint(x: o.maxX, y: o.maxY)
            case .topRight:    anchor = CGPoint(x: o.minX, y: o.maxY)
            case .bottomLeft:  anchor = CGPoint(x: o.maxX, y: o.minY)
            default:           anchor = CGPoint(x: o.minX, y: o.minY)
            }
            let scale = max(abs(p.x - anchor.x) / max(o.width, 1), abs(p.y - anchor.y) / max(o.height, 1))
            let fw = max(1, o.width * scale), fh = max(1, o.height * scale)
            let dirX: CGFloat = p.x >= anchor.x ? 1 : -1
            let dirY: CGFloat = p.y >= anchor.y ? 1 : -1
            let corner = CGPoint(x: anchor.x + dirX * fw, y: anchor.y + dirY * fh)
            return CGRect(x: min(anchor.x, corner.x), y: min(anchor.y, corner.y), width: fw, height: fh)
        case .left, .right:
            let fixedX = handle == .right ? o.minX : o.maxX
            let fw = max(1, abs(p.x - fixedX)), fh = max(1, fw / aspect)
            return CGRect(x: min(fixedX, p.x), y: o.midY - fh / 2, width: fw, height: fh)
        case .top, .bottom:
            let fixedY = handle == .bottom ? o.minY : o.maxY
            let fh = max(1, abs(p.y - fixedY)), fw = max(1, fh * aspect)
            return CGRect(x: o.midX - fw / 2, y: min(fixedY, p.y), width: fw, height: fh)
        }
    }

    // MARK: Keyboard edits

    private func nudgeSelection(keyCode: UInt16, large: Bool) {
        guard let app, let document else { return }
        let step: CGFloat = large ? 10 : 1
        let dx: CGFloat = keyCode == 123 ? -step : keyCode == 124 ? step : 0
        let dy: CGFloat = keyCode == 126 ? -step : keyCode == 125 ? step : 0

        // Node tool with a point selection → nudge just those points, not the
        // whole shape. (Arrow keys used to move the entire object even while a
        // subset of its anchors was selected in Edit Points.)
        if app.tool == .node, !selectedPointAddresses.isEmpty {
            nudgeSelectedPoints(dx: dx, dy: dy)
            return
        }

        if !app.selectedNodeIDs.isEmpty {
            var nodes = currentNodes
            for id in app.selectedNodeIDs {
                // A node's origin lives in its parent's space; if an ancestor group is
                // rotated, rotate the doc-space delta into that local space (same as the
                // move drag). Recurse so a node INSIDE a group is nudged too (was
                // top-level only — arrow keys did nothing for grouped elements).
                let rot = ancestorRotation(of: id)
                let d = rot != 0 ? rotateVector(CGPoint(x: dx, y: dy), byDegrees: -rot)
                                 : CGPoint(x: dx, y: dy)
                _ = Self.mutateNested(id, in: &nodes) { n in
                    n.frame.origin.x += d.x
                    n.frame.origin.y += d.y
                }
            }
            commitNodes(nodes, actionName: "Move Shape")
        } else if !isSourceScope, !app.selectedArtboardIDs.isEmpty {
            // Move every selected artboard and carry the shapes each owns.
            var model = document.model
            guard let pageIndex = model.pageIndex(for: activePageID) else { return }
            let owned = ownedNodeOrigins(forBoards: Array(app.selectedArtboardIDs))
            for ai in model.pages[pageIndex].artboards.indices
            where app.selectedArtboardIDs.contains(model.pages[pageIndex].artboards[ai].id) {
                model.pages[pageIndex].artboards[ai].frame.origin.x += dx
                model.pages[pageIndex].artboards[ai].frame.origin.y += dy
            }
            for ni in model.pages[pageIndex].nodes.indices
            where owned[model.pages[pageIndex].nodes[ni].id] != nil {
                model.pages[pageIndex].nodes[ni].frame.origin.x += dx
                model.pages[pageIndex].nodes[ni].frame.origin.y += dy
            }
            document.setModel(model, undoManager: undoManager, actionName: "Move Artboard")
        }
        needsDisplay = true
    }

    /// Nudge the node tool's selected anchors (+ their handles) by a doc-space
    /// delta, translated into the edited path's LOCAL space. This is the
    /// points-only counterpart to `nudgeSelection`'s whole-object move — mirrors
    /// `rotateSelectedPoints`'s selection source and commit pattern.
    private func nudgeSelectedPoints(dx: CGFloat, dy: CGFloat) {
        guard let id = app?.singleSelectedNodeID, let n = node(id),
              case .path(let ps0) = n.content, !selectedPointAddresses.isEmpty else { return }
        // Doc-space delta → node-local: undo ancestor + own rotation, then flips
        // (mirror negates the axis). A pure vector needs no translation term.
        var d = rotateVector(CGPoint(x: dx, y: dy), byDegrees: -ancestorRotation(of: id))
        if n.rotation != 0 { d = rotateVector(d, byDegrees: -n.rotation) }
        if n.flipH { d.x = -d.x }
        if n.flipV { d.y = -d.y }
        var ps = ps0
        for addr in selectedPointAddresses {
            ps.mutatePoint(contour: addr.contour, index: addr.index) { pt in
                pt.point = CGPoint(x: pt.point.x + d.x, y: pt.point.y + d.y)
                pt.controlIn  = pt.controlIn.map  { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
                pt.controlOut = pt.controlOut.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
            }
        }
        var nodes = currentNodes
        guard Self.mutateNested(id, in: &nodes, {
            $0.content = .path(ps)
            Self.normalizePathNode(&$0)
        }) else { return }
        commitNodes(nodes, actionName: selectedPointAddresses.count == 1 ? "Move Point" : "Move Points")
        needsDisplay = true
    }

    /// Delete the node tool's selected points (and the segments between them)
    /// from the edited path, instead of deleting the whole element. Removing a
    /// point just reconnects its neighbors — same convention as every vector
    /// tool. Mirrors `rotateSelectedPoints`'s selection source and commit
    /// pattern. Handles multi-contour paths too; a contour emptied out by the
    /// deletion is dropped entirely (e.g. an outlined glyph's hole).
    private func deleteSelectedPoints() {
        guard let id = app?.singleSelectedNodeID, let n = node(id),
              case .path(let ps0) = n.content,
              !selectedPointAddresses.isEmpty else { return }
        var ps = ps0
        var cs = ps.editContours
        let byContour = Dictionary(grouping: selectedPointAddresses, by: \.contour)
        for (c, addrs) in byContour {
            guard cs.indices.contains(c) else { continue }
            for i in addrs.map(\.index).sorted(by: >) where cs[c].indices.contains(i) {
                cs[c].remove(at: i)
            }
        }
        cs.removeAll { $0.isEmpty }
        ps.writeEditContours(cs)
        var nodes = currentNodes
        let count = selectedPointAddresses.count
        guard Self.mutateNested(id, in: &nodes, {
            $0.content = .path(ps)
            Self.normalizePathNode(&$0)
        }) else { return }
        commitNodes(nodes, actionName: count == 1 ? "Delete Point" : "Delete Points")
        setSelectedPoints([])
        needsDisplay = true
    }

    private func deleteSelection() {
        guard let app, let document else { return }
        if app.tool == .node, !selectedPointAddresses.isEmpty {
            deleteSelectedPoints()
        } else if !app.selectedNodeIDs.isEmpty {
            var nodes = currentNodes
            // Collect the WHOLE subtree being removed, not just the selection —
            // a relationship may name a layer nested inside a deleted group.
            var doomed = Set<UUID>()
            for id in app.selectedNodeIDs {
                if let n = node(id) { Self.collectSubtreeIDs(n, into: &doomed) }
            }
            Self.removeNested(app.selectedNodeIDs, from: &nodes)   // nested children too
            commitNodes(nodes, actionName: "Delete",
                        removingAnchorsReferencing: doomed)
            app.selectedNodeIDs = []
        } else if !isSourceScope, !app.selectedArtboardIDs.isEmpty {
            var model = document.model
            guard let pageIndex = model.pageIndex(for: activePageID) else { return }
            let ids = app.selectedArtboardIDs
            // Deleting an artboard also deletes the artwork it contains. Ownership
            // is geometric, so resolve it BEFORE the boards are removed (otherwise
            // owningArtboard has nothing to match and the nodes get orphaned onto
            // the wall — which is what left stray PDF-page content behind).
            let ownedIDs = Set(model.pages[pageIndex].nodes.compactMap { n -> UUID? in
                guard let owner = model.owningArtboard(of: n, on: activePageID),
                      ids.contains(owner.id) else { return nil }
                return n.id
            })
            model.pages[pageIndex].nodes.removeAll { ownedIDs.contains($0.id) }
            model.pages[pageIndex].artboards.removeAll { ids.contains($0.id) }
            document.setModel(model, undoManager: undoManager,
                              actionName: ids.count == 1 ? "Delete Artboard" : "Delete Artboards")
            app.selectedArtboardIDs = []
            app.selectedNodeIDs = []
        }
        needsDisplay = true
    }

    private func cycleArtboardSelection(forward: Bool) {
        guard let app, document != nil, !isSourceScope, !currentArtboards.isEmpty else { return }
        let boards = currentArtboards
        app.selectedNodeIDs = []
        if let id = app.selectedArtboardID, let idx = boards.firstIndex(where: { $0.id == id }) {
            let n = boards.count
            app.selectedArtboardID = boards[forward ? (idx + 1) % n : (idx - 1 + n) % n].id
        } else {
            app.selectedArtboardID = forward ? boards.first?.id : boards.last?.id
        }
        needsDisplay = true
    }

    // MARK: Clipboard + duplicate (responder actions → Edit menu + context menu)

    private func collectSelectedNodes(_ requestedIDs: Set<UUID>? = nil) -> [Node] {
        guard let app else { return [] }
        let selectedIDs = requestedIDs ?? app.selectedNodeIDs
        // Gather selected nodes anywhere in the tree. A nested node is copied with its
        // ABSOLUTE frame (parent offset folded in) so paste lands it where it visually
        // sat, not at the group-relative origin.
        var out: [Node] = []
        func walk(_ nodes: [Node], _ off: CGPoint) {
            for n in nodes {
                if selectedIDs.contains(n.id) {
                    var c = n
                    c.frame = n.frame.offsetBy(dx: off.x, dy: off.y)
                    out.append(c)
                    continue
                }
                if case .group(let kids) = n.content {
                    walk(kids, CGPoint(x: off.x + n.frame.minX, y: off.y + n.frame.minY))
                }
            }
        }
        walk(currentNodes, .zero)
        return out
    }

    @objc func copy(_ sender: Any?) {
        guard let app, let document else { return }
        let pb = NSPasteboard.general

        // Boards take priority when artboards are selected and no shapes are.
        if !isSourceScope, app.selectedNodeIDs.isEmpty, !app.selectedArtboardIDs.isEmpty {
            let boards = currentArtboards.filter { app.selectedArtboardIDs.contains($0.id) }
            let owned = currentNodes.filter {
                guard let o = owningArtboard(of: $0)?.id else { return false }
                return app.selectedArtboardIDs.contains(o)
            }
            if let data = try? JSONEncoder().encode(ArtboardClipboard(artboards: boards, nodes: owned)) {
                pb.clearContents()
                pb.setData(data, forType: Self.artboardPasteboardType)
            }
            return
        }

        let nodes = collectSelectedNodes()
        guard !nodes.isEmpty else { return }
        // Remember the owning board (when the selection shares exactly one) so
        // paste can land on a *different* board at the same relative position.
        var srcOrigin: CGPoint?
        let owners = Set(nodes.compactMap { owningArtboard(of: $0)?.id })
        if owners.count == 1, let oid = owners.first,
           let ab = currentArtboards.first(where: { $0.id == oid }) {
            srcOrigin = ab.frame.origin
        }
        if let data = try? JSONEncoder().encode(NodeClipboard(nodes: nodes, sourceOrigin: srcOrigin)) {
            pb.clearContents()
            pb.setData(data, forType: Self.nodePasteboardType)
        }
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        deleteSelection()
    }

    @objc func paste(_ sender: Any?) {
        guard document != nil else { return }
        let pb = NSPasteboard.general
        // Artboards first (only in the main document scope).
        if !isSourceScope, let data = pb.data(forType: Self.artboardPasteboardType),
           let clip = try? JSONDecoder().decode(ArtboardClipboard.self, from: data), !clip.artboards.isEmpty {
            pasteArtboards(clip)
            return
        }
        if let data = pb.data(forType: Self.nodePasteboardType),
           let clip = try? JSONDecoder().decode(NodeClipboard.self, from: data), !clip.nodes.isEmpty {
            pasteNodes(clip)
            return
        }
        // SVG(s) on the clipboard → import as editable vector layers.
        let svgItems = svgImports(from: pb)
        if !svgItems.isEmpty { placeSVGImports(svgItems, at: nil); return }
        // A PDF on the clipboard (a vector copy from Illustrator/Figma/Sketch/
        // Preview lands as com.adobe.pdf, NOT svg) → import as an editable vector
        // group. Checked before the raster branch so vector wins over NSImage.
        if let pdf = pdfData(from: pb) { placePDF(pdf, at: nil); return }
        // Otherwise: image(s) on the clipboard (copied image(s), or file(s)) → place them.
        let images = imageImports(from: pb)
        if !images.isEmpty { placeImageImports(images, at: nil) }
    }

    // MARK: Images (place / paste / drag-drop)

    /// Pull image bytes from a pasteboard: every dragged/pasted image FILE
    /// (original bytes, format preserved, in drop order), or -- if there are no
    /// image files -- raw PNG data / any NSImage-readable content (a copied
    /// image). Multiple files dragged or pasted at once all come back here.
    private struct NamedImport {
        let data: Data
        let name: String?
    }

    /// A Finder filename becomes a useful layer name. Keep Unicode and spaces;
    /// only the file extension is transport detail rather than part of the name.
    private func layerName(for url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func imageImports(from pb: NSPasteboard) -> [NamedImport] {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let fromFiles = urls.compactMap { url -> NamedImport? in
                guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return nil }
                return NamedImport(data: data, name: layerName(for: url))
            }
            if !fromFiles.isEmpty { return fromFiles }
        }
        if let data = pb.data(forType: .png) { return [NamedImport(data: data, name: nil)] }
        if let data = pb.data(forType: .tiff), Self.imagePixelDimensions(data) != nil {
            return [NamedImport(data: data, name: nil)]
        }
        if let ns = NSImage(pasteboard: pb), let png = Self.pngData(from: ns) {
            return [NamedImport(data: png, name: nil)]
        }
        return []
    }

    /// Create an image node from raw image bytes, centred at `viewPoint` (or the
    /// viewport centre), at the image's full natural size. One undo step.
    @discardableResult
    func placeImageData(_ data: Data, at viewPoint: CGPoint?, name: String? = nil) -> Bool {
        placeImageImports([NamedImport(data: data, name: name)], at: viewPoint)
    }

    /// Create one image node per item in `datas`, each at its full natural size,
    /// laid out left-to-right as a row centred at `viewPoint` (or the viewport
    /// centre) so images dropped together land side-by-side instead of stacked
    /// exactly on top of one another. All of them land in a single undo step.
    @discardableResult
    private func placeImageImports(_ imports: [NamedImport], at viewPoint: CGPoint?) -> Bool {
        guard let app else { return false }
        let images: [(data: Data, size: CGSize, name: String?)] = imports.compactMap { item in
            guard let ns = NSImage(data: item.data), ns.size.width > 0, ns.size.height > 0 else { return nil }
            return (item.data, ns.size, item.name)
        }
        guard !images.isEmpty else { return false }

        let gap: CGFloat = 24
        let totalWidth = images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(images.count - 1)
        let center = viewPoint.map { viewToDoc($0) } ?? viewToDoc(viewCenter)
        var x = center.x - totalWidth / 2

        var nodes = currentNodes
        var newIDs: [UUID] = []
        for img in images {
            let origin = CGPoint(x: x, y: center.y - img.size.height / 2)
            let node = Node(name: img.name ?? "Image", frame: CGRect(origin: origin, size: img.size),
                            content: .image(ImageContent(data: img.data, naturalSize: img.size)))
            nodes.append(node)
            newIDs.append(node.id)
            x += img.size.width + gap
        }
        commitNodes(nodes, actionName: images.count > 1 ? "Place Images" : "Place Image")
        app.selectedArtboardID = nil
        app.selectedNodeIDs = Set(newIDs)
        app.tool = .select
        needsDisplay = true
        return true
    }

    /// File ▸ Place Image… — pick one or more image (or SVG) files and drop them
    /// on the canvas. Each media type is placed as a named row in one undo step.
    @objc func placeImageAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .svg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var svgs: [NamedImport] = []
        var images: [NamedImport] = []
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let item = NamedImport(data: data, name: layerName(for: url))
            if url.pathExtension.lowercased() == "svg" || looksLikeSVG(data) {
                svgs.append(item)
            } else {
                images.append(item)
            }
        }
        if !svgs.isEmpty { placeSVGImports(svgs, at: nil) }
        if !images.isEmpty { placeImageImports(images, at: nil) }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canDrop(sender.draggingPasteboard) ? .copy : []
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canDrop(sender.draggingPasteboard) ? .copy : []
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let at = convert(sender.draggingLocation, from: nil)
        // Component drag from the Components panel (the pasteboard string is the
        // source's UUID) — checked FIRST so a UUID never falls through to the
        // SVG/text sniffers.
        if let sid = componentSourceID(from: sender.draggingPasteboard) {
            return placeComponentInstance(sid, at: at)
        }
        let svgs = svgImports(from: sender.draggingPasteboard)
        if !svgs.isEmpty { return placeSVGImports(svgs, at: at) }
        if let pdf = pdfData(from: sender.draggingPasteboard) { return placePDF(pdf, at: at) }
        let images = imageImports(from: sender.draggingPasteboard)
        guard !images.isEmpty else { return false }
        return placeImageImports(images, at: at)
    }

    private func canDrop(_ pb: NSPasteboard) -> Bool {
        componentSourceID(from: pb).map(canPlaceComponent) == true || !svgImports(from: pb).isEmpty
            || pdfData(from: pb) != nil || !imageImports(from: pb).isEmpty
    }

    // MARK: Component drop (v1.3 — drag a component from the panel onto the canvas)

    /// The dragged component's source id, IF the pasteboard string is a UUID
    /// matching one of this document's sources (a plain text drag never is).
    private func componentSourceID(from pb: NSPasteboard) -> UUID? {
        guard let s = pb.string(forType: .string),
              let id = UUID(uuidString: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              document?.model.source(for: id) != nil else { return nil }
        return id
    }

    /// A document canvas accepts every valid source. A component-source canvas
    /// accepts only edges that keep the source dependency graph acyclic.
    private func canPlaceComponent(_ sourceID: UUID) -> Bool {
        guard let document, document.model.source(for: sourceID) != nil else { return false }
        switch scope {
        case .document:
            return true
        case .source(let parentSourceID):
            return document.model.canNestComponent(sourceID, in: parentSourceID)
        }
    }

    /// Create an instance centered at the drop point (one undo step). In a source
    /// editor the dependency graph rejects direct and indirect cycles before any
    /// mutation (`A -> A` and `A -> B -> A`).
    @discardableResult
    private func placeComponentInstance(_ sourceID: UUID, at viewPoint: CGPoint) -> Bool {
        guard let app, let document,
              let source = document.model.source(for: sourceID),
              canPlaceComponent(sourceID) else {
            NSSound.beep()
            return false
        }
        let center = viewToDoc(viewPoint)
        let frame = CGRect(x: center.x - source.size.width / 2,
                           y: center.y - source.size.height / 2,
                           width: source.size.width, height: source.size.height)
        let node = Node(name: "Instance", frame: frame,
                        content: .instance(ComponentInstance(sourceID: sourceID)))
        var nodes = currentNodes
        nodes.append(node)
        commitNodes(nodes, actionName: "Create Instance")
        app.selectedNodeIDs = [node.id]
        app.selectedArtboardIDs = []
        app.tool = .select
        needsDisplay = true
        return true
    }

    // MARK: SVG (import as editable vector layers)

    /// True if these bytes are an SVG document (root `<svg …>` near the start).
    private func looksLikeSVG(_ data: Data) -> Bool {
        let head = data.prefix(1024)
        guard let s = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) else { return false }
        return s.contains("<svg")
    }

    /// Pull every SVG from a pasteboard. Finder drops retain each source filename;
    /// raw SVG data/markup remains a single unnamed import.
    private func svgImports(from pb: NSPasteboard) -> [NamedImport] {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let files = urls.compactMap { url -> NamedImport? in
                guard url.pathExtension.lowercased() == "svg",
                      let data = try? Data(contentsOf: url) else { return nil }
                return NamedImport(data: data, name: layerName(for: url))
            }
            if !files.isEmpty { return files }
        }
        if let svgType = UTType.svg.identifier as String?,
           let data = pb.data(forType: NSPasteboard.PasteboardType(svgType)), looksLikeSVG(data) {
            return [NamedImport(data: data, name: nil)]
        }
        if let s = pb.string(forType: .string), s.contains("<svg"),
           let data = s.data(using: .utf8) { return [NamedImport(data: data, name: nil)] }
        return []
    }

    /// Import an SVG as a group of editable native layers, centred at `viewPoint`
    /// (or the viewport centre). Falls back to a raster image if the document
    /// can't be parsed into vectors. One undo step.
    @discardableResult
    func placeSVG(_ data: Data, at viewPoint: CGPoint?, name: String? = nil) -> Bool {
        placeSVGImports([NamedImport(data: data, name: name)], at: viewPoint)
    }

    /// Import multiple SVGs as one named, side-by-side batch and one undo step.
    /// Invalid vector markup still gets the existing raster fallback when AppKit
    /// can render it, so one problematic file does not cancel the rest of a drop.
    @discardableResult
    private func placeSVGImports(_ imports: [NamedImport], at viewPoint: CGPoint?) -> Bool {
        guard let app else { return false }
        var imported: [Node] = []
        for item in imports {
            if var group = SVGImporter.importGroup(from: item.data) {
                if let name = item.name { group.name = name }
                imported.append(group)
            } else if let image = NSImage(data: item.data), image.size.width > 0, image.size.height > 0 {
                imported.append(Node(name: item.name ?? "Image",
                                     frame: CGRect(origin: .zero, size: image.size),
                                     content: .image(ImageContent(data: item.data, naturalSize: image.size))))
            }
        }
        guard !imported.isEmpty else { return false }

        let gap: CGFloat = 24
        let totalWidth = imported.reduce(0) { $0 + $1.frame.width }
            + gap * CGFloat(imported.count - 1)
        let center = viewPoint.map { viewToDoc($0) } ?? viewToDoc(viewCenter)
        var x = center.x - totalWidth / 2
        var nodes = currentNodes
        var newIDs: [UUID] = []
        for var node in imported {
            node.frame.origin = CGPoint(x: x, y: center.y - node.frame.height / 2)
            nodes.append(node)
            newIDs.append(node.id)
            x += node.frame.width + gap
        }
        commitNodes(nodes, actionName: imported.count > 1 ? "Import SVGs" : "Import SVG")
        app.selectedArtboardID = nil
        app.selectedNodeIDs = Set(newIDs)
        app.tool = .select
        needsDisplay = true
        return true
    }

    // MARK: PDF (import as editable vector layers / artboards)

    /// Pull PDF bytes from a pasteboard: a dragged/pasted `.pdf` FILE, or the
    /// `com.adobe.pdf` flavor apps put down for a vector copy. nil if there's none.
    private func pdfData(from pb: NSPasteboard) -> Data? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where url.pathExtension.lowercased() == "pdf" {
                if let data = try? Data(contentsOf: url) { return data }
            }
        }
        if let data = pb.data(forType: NSPasteboard.PasteboardType("com.adobe.pdf")) { return data }
        if let data = pb.data(forType: NSPasteboard.PasteboardType(UTType.pdf.identifier)) { return data }
        return nil
    }

    /// Import a PDF's first page as a group of editable vector layers, centred at
    /// `viewPoint` (paste/drop semantics — mirrors `placeSVG`). Falls back to a
    /// raster image if the page can't be reconstructed. One undo step.
    @discardableResult
    func placePDF(_ data: Data, at viewPoint: CGPoint?) -> Bool {
        guard let app else { return false }
        guard var group = PDFImporter.importGroup(from: data) else {
            // Couldn't reconstruct → place a faithful PNG raster of page 1. NEVER
            // hand the raw PDF bytes to an image node: NSImage treats them as a
            // PDF-backed image, which errors and beach-balls the canvas on redraw.
            if let png = PDFImporter.rasterPNGForPage(from: data, page: 1) {
                return placeImageData(png, at: viewPoint)
            }
            NSSound.beep(); return false
        }
        let size = group.frame.size
        let center = viewPoint.map { viewToDoc($0) } ?? viewToDoc(viewCenter)
        group.frame.origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        var nodes = currentNodes
        nodes.append(group)
        commitNodes(nodes, actionName: "Paste Vector")
        app.selectedArtboardID = nil
        app.selectedNodeIDs = [group.id]
        app.tool = .select
        needsDisplay = true
        return true
    }

    /// File ▸ Import PDF… — pick a PDF, choose pages (each becomes an artboard),
    /// and add them to the CURRENT document beside its existing content.
    @objc func importPDFAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let count = PDFImporter.pageCount(from: data)
        guard count > 0 else { NSSound.beep(); return }
        var pages: [Int]? = nil
        if count > 1 {
            guard let chosen = askPageSelection(count: count) else { return }   // cancelled
            pages = chosen
        }
        guard let imported = PDFImporter.importPages(from: data, pages: pages), !imported.isEmpty else {
            NSSound.beep(); return
        }
        placeImportedPages(imported, sourceName: url.deletingPathExtension().lastPathComponent)
    }

    // MARK: Adobe XD (offline InteropCodec import + visible fidelity report)

    /// File ▸ Import Adobe XD… — decode the frozen ZIP/AGC package off the main
    /// thread, append its native artboards/layers in one undo step, then show the
    /// Import Report even when fidelity is partial.
    @objc func importXDAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xd") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an Adobe XD document to rescue into the current EXP document."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let token = InteropCancellationToken()
        let progress = InteropImportProgressController(format: .adobeXD,
                                                       sourceName: url.lastPathComponent)
        let importTask = Task.detached(priority: .userInitiated) {
            do {
                let result = try XDImporter().read(
                    from: url,
                    context: InteropContext(cancellation: token) { update in
                        Task { @MainActor in progress.update(update) }
                    })
                await progress.finish(.success(result))
            } catch {
                await progress.finish(.failure(error.localizedDescription))
            }
        }

        let response = progress.runModal()
        if response == .alertFirstButtonReturn {
            token.cancel()
            importTask.cancel()
            return
        }
        switch progress.outcome {
        case .success(let result):
            applyXDImport(result)
        case .failure(let message):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Adobe XD Import Failed"
            alert.informativeText = message
            alert.runModal()
        case nil:
            break
        }
    }

    private func applyXDImport(_ result: InteropImportResult) {
        guard let document else { return }
        var payload = result.payload
        let importBounds: CGRect? = {
            // XD documents can have substantial pasteboard artwork outside every
            // artboard. Reserve space for ALL imported content; using only board
            // frames let a later import collide with those wall layers.
            let frames = payload.artboards.map(\.frame) + payload.nodes.map(\.frame)
            guard let first = frames.first else { return nil }
            return frames.dropFirst().reduce(first) { $0.union($1) }
        }()
        if let bounds = importBounds {
            let hasExistingContent = !currentArtboards.isEmpty || !currentNodes.isEmpty
            let currentMaxX = hasExistingContent
                ? document.model.contentBounds(on: activePageID).maxX : -120
            payload.translate(by: CGPoint(x: currentMaxX + 120 - bounds.minX,
                                          y: -bounds.minY))
        }

        var model = document.model
        guard let pageIndex = model.pageIndex(for: activePageID) else { return }
        model.pages[pageIndex].artboards.append(contentsOf: payload.artboards)
        model.pages[pageIndex].nodes.append(contentsOf: payload.nodes)
        model.sources.append(contentsOf: payload.sources)
        for asset in payload.designLanguage.assets
            where model.designLanguage.firstAsset(matching: asset.value) == nil {
            model.designLanguage.assets.append(asset)
        }
        for style in payload.designLanguage.typeStyles
            where !model.designLanguage.typeStyles.contains(where: { $0.sameValues(as: style) }) {
            model.designLanguage.typeStyles.append(style)
        }
        document.setModel(model, undoManager: undoManager, actionName: "Import Adobe XD")
        let firstImportedArtboard = payload.artboards.first
        app?.selectedArtboardID = firstImportedArtboard?.id
        app?.selectedNodeIDs = []
        app?.tool = .select
        if let frame = firstImportedArtboard?.frame {
            fitViewport(to: frame)
        } else if let firstNode = payload.nodes.first {
            let bounds = payload.nodes.dropFirst().reduce(firstNode.frame) {
                $0.union($1.frame)
            }
            fitViewport(to: bounds)
        }
        needsDisplay = true
        lastImportReport = result.report
        // A clean/approximated import should simply reveal the artwork. Interrupt
        // only when content was actually rejected; all reports remain available
        // from File > Show Last Import Report.
        if result.report.errorCount > 0 || result.report.unsupportedCount > 0 {
            showImportReport(result.report)
        }
    }

    // MARK: Rendered HTML/CSS (E1b local-file vertical slice)

    /// File ▸ Import HTML/CSS… — renders a user-selected local HTML file in a
    /// short-lived, non-persistent WKWebView and converts the resolved DOM into
    /// editable EXP artboards. This first production slice intentionally grants
    /// only the chosen folder; remote-origin trust/session UI follows separately.
    @objc func importRenderedHTMLAction(_ sender: Any?) {
        guard let source = askRenderedHTMLSource(),
              let viewports = askRenderedHTMLViewports() else { return }

        let url = source.file
        let directory = source.directory
        let token = InteropCancellationToken()
        let progress = InteropImportProgressController(format: .renderedHTML,
                                                       sourceName: url.lastPathComponent)
        let capture = RenderedHTMLWebKitCapture()
        let importTask = Task { @MainActor in
            do {
                let result = try await capture.readLocalFile(
                    from: url,
                    scopedDirectory: directory,
                    viewports: viewports,
                    context: InteropContext(cancellation: token) { update in
                        Task { @MainActor in progress.update(update) }
                    })
                progress.finish(.success(result))
            } catch {
                progress.finish(.failure(error.localizedDescription))
            }
        }

        let response = progress.runModal()
        if response == .alertFirstButtonReturn {
            token.cancel()
            capture.cancel()
            importTask.cancel()
            return
        }
        switch progress.outcome {
        case .success(let result):
            applyRenderedHTMLImport(result)
        case .failure(let message):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "HTML/CSS Import Failed"
            alert.informativeText = message
            alert.runModal()
        case nil:
            break
        }
    }

    /// File ▸ Import CodePen Export… — recognizes CodePen's exported ZIP,
    /// renders only the last successful dist/index.html, and retains the full
    /// bounded src/config receipt without invoking any build tooling.
    @objc func importCodePenPackageAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Import CodePen Export"
        panel.message = "Choose a CodePen 2.0 exported ZIP. EXP renders its last successful dist build and preserves source/configuration without running build scripts."
        guard panel.runModal() == .OK, let url = panel.url,
              let viewports = askRenderedHTMLViewports() else { return }

        let token = InteropCancellationToken()
        let progress = InteropImportProgressController(format: .codePen,
                                                       sourceName: url.lastPathComponent)
        let importer = CodePenPackageImporter()
        let importTask = Task { @MainActor in
            do {
                let result = try await importer.read(
                    from: url,
                    viewports: viewports,
                    context: InteropContext(cancellation: token) { update in
                        Task { @MainActor in progress.update(update) }
                    })
                progress.finish(.success(result))
            } catch {
                progress.finish(.failure(error.localizedDescription))
            }
        }

        let response = progress.runModal()
        if response == .alertFirstButtonReturn {
            token.cancel()
            importer.cancel()
            importTask.cancel()
            return
        }
        switch progress.outcome {
        case .success(let result):
            applyRenderedHTMLImport(result, actionName: "Import CodePen Export")
        case .failure(let message):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "CodePen Import Failed"
            alert.informativeText = message
            alert.runModal()
        case nil:
            break
        }
    }

    /// File ▸ Import Storybook Build… — discovers a local static build through
    /// Storybook's index.json and renders isolated iframe stories. No source build,
    /// package manager, or framework command runs inside EXP.
    @objc func importStorybookPackageAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Import Storybook Build"
        panel.message = "Choose a static Storybook build containing index.json and iframe.html. EXP renders its browser-ready stories locally and blocks network access."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let importer = StorybookPackageImporter()
        let catalog: StorybookCatalogSummary
        do {
            catalog = try importer.discover(from: url)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Storybook Discovery Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        guard let storyIDs = askStorybookStories(catalog),
              let viewports = askRenderedHTMLViewports() else { return }

        let token = InteropCancellationToken()
        let progress = InteropImportProgressController(format: .storybook,
                                                       sourceName: url.lastPathComponent)
        let importTask = Task { @MainActor in
            do {
                let result = try await importer.read(
                    from: url, storyIDs: storyIDs, viewports: viewports,
                    context: InteropContext(cancellation: token) { update in
                        Task { @MainActor in progress.update(update) }
                    })
                progress.finish(.success(result))
            } catch {
                progress.finish(.failure(error.localizedDescription))
            }
        }

        let response = progress.runModal()
        if response == .alertFirstButtonReturn {
            token.cancel()
            importer.cancel()
            importTask.cancel()
            return
        }
        switch progress.outcome {
        case .success(let result):
            applyRenderedHTMLImport(result, actionName: "Import Storybook Build")
        case .failure(let message):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Storybook Import Failed"
            alert.informativeText = message
            alert.runModal()
        case nil:
            break
        }
    }

    private func askStorybookStories(_ catalog: StorybookCatalogSummary)
        -> Set<String>? {
        let controller = StorybookStorySelectionController(
            stories: catalog.stories, maximumSelection: 100)
        let alert = NSAlert()
        alert.messageText = "Choose Storybook Stories"
        let version = catalog.version.map { " · catalog v\($0)" } ?? ""
        alert.informativeText = "Found \(catalog.stories.count) stories\(version). Search by component, story, tag, id, or source path."
        let importButton = alert.addButton(withTitle: "Import Selected")
        importButton.keyEquivalent = "\r"
        importButton.isEnabled = false
        alert.addButton(withTitle: "Cancel")
        controller.importButton = importButton
        alert.accessoryView = controller.view
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let selection = controller.selectedStoryIDs
        return selection.isEmpty ? nil : selection
    }

    /// The app sandbox grants exactly what the person chooses. Asking for the
    /// containing folder makes the permission match the UI promise that relative
    /// CSS, fonts, and images can load; inferring a sibling-file grant from a
    /// single selected HTML file would work outside the sandbox and fail in release.
    private func askRenderedHTMLSource() -> (file: URL, directory: URL)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose the folder containing the HTML entry file and its local CSS, fonts, and images. Remote resources stay blocked."
        guard panel.runModal() == .OK else { return nil }
        // When the person navigates *into* a folder and presses Choose Folder,
        // AppKit can return no selected-item URL. The visible directory is still
        // the intended choice; treating nil as cancellation made the panel simply
        // disappear with no next step or error.
        guard let directory = panel.url ?? panel.directoryURL else {
            showRenderedHTMLSourceError(
                "EXP could not determine which folder was selected. Please choose it again.")
            return nil
        }

        let accessStarted = directory.startAccessingSecurityScopedResource()
        defer {
            if accessStarted { directory.stopAccessingSecurityScopedResource() }
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey, .contentTypeKey]
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])
                .filter { url in
                    guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                        return false
                    }
                    return values.isRegularFile == true
                        && values.isHidden != true
                        && (values.contentType?.conforms(to: .html) == true
                            || ["html", "htm"].contains(url.pathExtension.lowercased()))
                }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            showRenderedHTMLSourceError(
                "EXP could not read that folder: \(error.localizedDescription)")
            return nil
        }
        guard !files.isEmpty else {
            showRenderedHTMLSourceError(
                "That folder has no top-level .html or .htm file to render.")
            return nil
        }
        guard files.count > 1 else { return (files[0], directory) }

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
        picker.addItems(withTitles: files.map(\.lastPathComponent))
        if let index = files.firstIndex(where: {
            $0.lastPathComponent.caseInsensitiveCompare("index.html") == .orderedSame
        }) {
            picker.selectItem(at: index)
        }
        picker.setAccessibilityLabel("HTML entry file")
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Choose the HTML Entry File"
        alert.informativeText = "This first local import renders one HTML file. Its relative resources may come from the selected folder."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = picker
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (files[picker.indexOfSelectedItem], directory)
    }

    private func showRenderedHTMLSourceError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "HTML/CSS Source Unavailable"
        alert.informativeText = message
        alert.runModal()
    }

    private func askRenderedHTMLViewports() -> [RenderedHTMLViewport]? {
        let presets = ArtboardPreset.all.filter { $0.group == "Mobile" || $0.group == "Web" }
        let choices = HTMLViewportSelectionController(presets: presets)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Choose Browser Viewports"
        alert.informativeText = "Each selected width becomes an independent editable artboard. Desktop 1440 is selected by default."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = choices.view
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let selected = choices.selectedViewports
        guard !selected.isEmpty else {
            let warning = NSAlert()
            warning.alertStyle = .warning
            warning.messageText = "Choose at Least One Viewport"
            warning.informativeText = "The browser needs a width and render height before it can resolve the page."
            warning.runModal()
            return askRenderedHTMLViewports()
        }
        return selected
    }

    private func applyRenderedHTMLImport(_ result: InteropImportResult,
                                         actionName: String = "Import HTML/CSS") {
        guard let document, let imported = result.payload.pages.first,
              !imported.artboards.isEmpty else { return }
        var page = imported
        let frames = page.artboards.map(\.frame) + page.nodes.map(\.frame)
        guard let firstFrame = frames.first else { return }
        let bounds = frames.dropFirst().reduce(firstFrame) { $0.union($1) }
        let hasExistingContent = !currentArtboards.isEmpty || !currentNodes.isEmpty
        let currentMaxX = hasExistingContent
            ? document.model.contentBounds(on: activePageID).maxX : -120
        let delta = CGPoint(x: currentMaxX + 120 - bounds.minX, y: -bounds.minY)
        for index in page.artboards.indices {
            page.artboards[index].frame.origin.x += delta.x
            page.artboards[index].frame.origin.y += delta.y
        }
        for index in page.nodes.indices {
            page.nodes[index].frame.origin.x += delta.x
            page.nodes[index].frame.origin.y += delta.y
        }

        var model = document.model
        guard let pageIndex = model.pageIndex(for: activePageID) else { return }
        model.pages[pageIndex].artboards.append(contentsOf: page.artboards)
        model.pages[pageIndex].nodes.append(contentsOf: page.nodes)
        model.sources.append(contentsOf: result.payload.sources)
        model.codeBridges.append(contentsOf: result.codeBridges)
        document.setModel(model, undoManager: undoManager,
                          actionName: actionName)

        let firstBoard = page.artboards[0]
        app?.selectedNodeIDs = []
        app?.selectedArtboardIDs = [firstBoard.id]
        app?.selectionAnchorID = nil
        app?.tool = .select
        fitViewport(to: firstBoard.frame)
        needsDisplay = true
        lastImportReport = result.report
        if result.report.errorCount > 0 || result.report.unsupportedCount > 0 {
            showImportReport(result.report)
        }
    }

    // MARK: Figma (sanctioned REST import)

    /// File ▸ Import Figma File… — the token is deliberately memory-only in this
    /// first slice. EXP sends it only to api.figma.com and never writes or logs it.
    @objc func importFigmaAction(_ sender: Any?) {
        guard let credentials = askForFigmaImportCredentials() else { return }
        let token = InteropCancellationToken()
        let progress = InteropImportProgressController(format: .figma,
                                                       sourceName: credentials.displayName)
        let request = FigmaRESTImporter.Request(fileKey: credentials.fileKey,
                                                token: credentials.token)
        let importTask = Task.detached(priority: .userInitiated) {
            do {
                let result = try await FigmaRESTImporter().read(
                    request,
                    context: InteropContext(cancellation: token) { update in
                        Task { @MainActor in progress.update(update) }
                    })
                await progress.finish(.success(result))
            } catch {
                await progress.finish(.failure(error.localizedDescription))
            }
        }

        let response = progress.runModal()
        if response == .alertFirstButtonReturn {
            token.cancel()
            importTask.cancel()
            return
        }
        switch progress.outcome {
        case .success(let result):
            applyFigmaImport(result)
        case .failure(let message):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Figma Import Failed"
            alert.informativeText = message
            alert.runModal()
        case nil:
            break
        }
    }

    private struct FigmaImportCredentials {
        var fileKey: String
        var token: String
        var displayName: String
    }

    private func askForFigmaImportCredentials() -> FigmaImportCredentials? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Import Figma File"
        alert.informativeText = "Paste a Figma file URL (or key) and a personal access token with file_content:read scope. EXP sends the token only to api.figma.com for this import; it is never saved or logged."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        let fileLabel = NSTextField(labelWithString: "Figma file URL or key")
        let fileField = NSTextField(frame: .zero)
        fileField.placeholderString = "https://www.figma.com/design/…"
        fileField.setAccessibilityLabel("Figma file URL or key")
        if let clipboard = NSPasteboard.general.string(forType: .string),
           FigmaRESTImporter.fileKey(from: clipboard) != nil {
            fileField.stringValue = clipboard
        }
        let tokenLabel = NSTextField(labelWithString: "Personal access token")
        let tokenField = NSSecureTextField(frame: .zero)
        tokenField.placeholderString = "figd_…"
        tokenField.setAccessibilityLabel("Figma personal access token")
        let privacy = NSTextField(wrappingLabelWithString:
            "Network access is required. The token remains in memory only and is discarded when this import finishes.")
        privacy.textColor = .secondaryLabelColor
        privacy.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [fileLabel, fileField, tokenLabel, tokenField, privacy])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 480, height: 126)
        fileField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        tokenField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        privacy.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        alert.accessoryView = stack
        alert.window.initialFirstResponder = fileField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let raw = fileField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = FigmaRESTImporter.fileKey(from: raw), !token.isEmpty else {
            let error = NSAlert()
            error.alertStyle = .warning
            error.messageText = "Figma Import Needs More Information"
            error.informativeText = token.isEmpty
                ? "Enter a personal access token with file_content:read scope."
                : "Enter a valid Figma design, file, prototype, or FigJam URL—or its file key."
            error.runModal()
            return nil
        }
        return FigmaImportCredentials(fileKey: key, token: token,
                                      displayName: raw.contains("/") ? "Figma file \(key)" : key)
    }

    private func applyFigmaImport(_ result: InteropImportResult) {
        guard let document, !result.payload.pages.isEmpty else { return }
        var model = document.model
        var usedNames = Set(model.pages.map { $0.name.lowercased() })
        var importedPages: [CanvasPage] = []
        for var page in result.payload.pages {
            let base = page.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Figma Page" : page.name
            var name = base
            var suffix = 2
            while usedNames.contains(name.lowercased()) {
                name = "\(base) \(suffix)"
                suffix += 1
            }
            page.name = name
            usedNames.insert(name.lowercased())
            importedPages.append(page)
        }
        model.pages.append(contentsOf: importedPages)
        model.sources.append(contentsOf: result.payload.sources)
        for asset in result.payload.designLanguage.assets
            where model.designLanguage.firstAsset(matching: asset.value) == nil {
            model.designLanguage.assets.append(asset)
        }
        for style in result.payload.designLanguage.typeStyles
            where !model.designLanguage.typeStyles.contains(where: { $0.sameValues(as: style) }) {
            model.designLanguage.typeStyles.append(style)
        }
        document.setModel(model, undoManager: undoManager, actionName: "Import Figma File")

        guard let firstPage = importedPages.first else { return }
        let firstBoard = firstPage.artboards.first
        let focus: CGRect? = firstBoard?.frame ?? firstPage.nodes.first.map { first in
            firstPage.nodes.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        }
        if let focus { pendingPageFocus = (firstPage.id, focus) }
        app?.selectedNodeIDs = []
        app?.selectedArtboardIDs = Set(firstBoard.map { [$0.id] } ?? [])
        app?.selectionAnchorID = nil
        app?.tool = .select
        app?.activeCanvasPageID = firstPage.id
        syncActivePageIfNeeded()
        needsDisplay = true
        lastImportReport = result.report
        if result.report.errorCount > 0 || result.report.unsupportedCount > 0 {
            showImportReport(result.report)
        }
    }

    @objc func showLastImportReportAction(_ sender: Any?) {
        guard let lastImportReport else { NSSound.beep(); return }
        showImportReport(lastImportReport)
    }

    private func showImportReport(_ report: InteropImportReport) {
        let alert = NSAlert()
        let needsReview = report.errorCount > 0 || report.unsupportedCount > 0
        alert.alertStyle = needsReview ? .warning : .informational
        alert.messageText = needsReview
            ? "\(report.format.rawValue) Import Needs Review"
            : "\(report.format.rawValue) Import Report"
        alert.informativeText = needsReview
            ? "Import completed, but some content could not be preserved. \(report.summary)."
            : "Import succeeded. \(report.summary). Fidelity details are diagnostic information."
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Copy Report")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 280))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.string = report.detailedText
        text.setAccessibilityLabel("\(report.format.rawValue) import fidelity report")
        scroll.documentView = text
        alert.accessoryView = scroll

        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report.detailedText, forType: .string)
        }
    }

    /// Append imported PDF pages as new artboards to the right of existing content
    /// (one undo step) and select the first.
    private func placeImportedPages(_ pages: [PDFImporter.Page], sourceName: String) {
        guard let document else { return }
        var model = document.model
        guard let pageIndex = model.pageIndex(for: activePageID) else { return }
        let startX = (model.pages[pageIndex].artboards.map { $0.frame.maxX }.max() ?? -120) + 120
        let laid = PDFImporter.layout(pages, origin: CGPoint(x: startX, y: 0),
                                      namePrefix: sourceName.isEmpty ? "Page" : sourceName)
        model.pages[pageIndex].artboards.append(contentsOf: laid.artboards)
        model.pages[pageIndex].nodes.append(contentsOf: laid.nodes)
        document.setModel(model, undoManager: undoManager,
                          actionName: pages.count > 1 ? "Import PDF Pages" : "Import PDF")
        app?.selectedArtboardID = laid.artboards.first?.id
        app?.selectedNodeIDs = []
        needsDisplay = true
    }

    /// Ask which pages to import from a multi-page PDF. Returns 1-based page
    /// numbers, or nil if cancelled. "All"/empty ⇒ every page.
    private func askPageSelection(count: Int) -> [Int]? {
        let alert = NSAlert()
        alert.messageText = "Import PDF"
        alert.informativeText = "This PDF has \(count) pages. Which pages? (e.g. 1-3, 5 — or leave “All”.) Each page becomes its own artboard."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = "All"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text.lowercased() == "all" { return Array(1...count) }
        let parsed = Self.parsePageRanges(text, max: count)
        return parsed.isEmpty ? Array(1...count) : parsed
    }

    /// Parse "1-3, 5, 8-9" → sorted unique 1-based page numbers within [1, max].
    static func parsePageRanges(_ s: String, max: Int) -> [Int] {
        var out = Set<Int>()
        for part in s.split(separator: ",") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if let dash = p.firstIndex(of: "-") {
                let lo = Int(p[p.startIndex..<dash].trimmingCharacters(in: .whitespaces))
                let hi = Int(p[p.index(after: dash)...].trimmingCharacters(in: .whitespaces))
                if let lo, let hi, lo <= hi { for n in lo...hi where n >= 1 && n <= max { out.insert(n) } }
            } else if let n = Int(p), n >= 1, n <= max {
                out.insert(n)
            }
        }
        return out.sorted()
    }

    /// Paste shapes, retargeting to the focused artboard: same position relative
    /// to that board if it fits, otherwise centered in the board. With no target
    /// board (wall), just nudge by 10pt like a plain duplicate.
    private func pasteNodes(_ clip: NodeClipboard) {
        guard let app else { return }
        var clones = clip.nodes.map { cloned($0) }
        if let target = pasteTargetBoard() {
            clones = repositioned(clones, from: clip, into: target)
        } else {
            clones = centered(clones, atDoc: viewToDoc(viewCenter))   // land near the viewport, not far off on the wall
        }
        var newNodes = currentNodes
        newNodes.append(contentsOf: clones)
        commitNodes(newNodes, actionName: "Paste")
        app.selectedNodeIDs = Set(clones.map { $0.id })
        app.selectedArtboardID = nil
        needsDisplay = true
    }

    /// The board paste should land on: the selected board, else the owning board
    /// of a selected shape, else none (paste to the wall).
    private func pasteTargetBoard() -> Artboard? {
        guard let document, !isSourceScope else { return nil }
        // Paste lands where you're LOOKING: the board under the viewport centre. If
        // the viewport is over empty wall (far from any board), return nil so the
        // caller drops the paste at the viewport centre instead of on a board you
        // selected earlier and then scrolled away from.
        let centerDoc = viewToDoc(viewCenter)
        return currentArtboards.first { $0.frame.contains(centerDoc) }
    }

    /// Shift the pasted group onto `target`: same offset-from-board-origin when it
    /// fits, otherwise centered.
    /// Shift a set of clones so their combined bounding box is centred on `c`
    /// (document space). Used when pasting onto the open wall.
    private func centered(_ clones: [Node], atDoc c: CGPoint) -> [Node] {
        guard let first = clones.first else { return clones }
        let bbox = clones.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let delta = CGPoint(x: c.x - bbox.midX, y: c.y - bbox.midY)
        return clones.map { var n = $0; n.frame.origin.x += delta.x; n.frame.origin.y += delta.y; return n }
    }

    private func repositioned(_ clones: [Node], from clip: NodeClipboard, into target: Artboard) -> [Node] {
        guard !clones.isEmpty else { return clones }
        let bbox = clones.dropFirst().reduce(clones[0].frame) { $0.union($1.frame) }
        var delta: CGPoint
        if let src = clip.sourceOrigin {
            let relMinX = bbox.minX - src.x, relMinY = bbox.minY - src.y
            let fits = relMinX >= 0 && relMinY >= 0
                && relMinX + bbox.width <= target.frame.width
                && relMinY + bbox.height <= target.frame.height
            delta = fits ? CGPoint(x: target.frame.minX - src.x, y: target.frame.minY - src.y)
                         : centerDelta(bbox: bbox, in: target)
        } else {
            delta = centerDelta(bbox: bbox, in: target)
        }
        return clones.map { var c = $0; c.frame.origin.x += delta.x; c.frame.origin.y += delta.y; return c }
    }

    private func centerDelta(bbox: CGRect, in target: Artboard) -> CGPoint {
        let tx = target.frame.minX + (target.frame.width - bbox.width) / 2
        let ty = target.frame.minY + (target.frame.height - bbox.height) / 2
        return CGPoint(x: tx - bbox.minX, y: ty - bbox.minY)
    }

    /// Paste boards (and the shapes they own) as new copies, offset, selected.
    private func pasteArtboards(_ clip: ArtboardClipboard) {
        guard let app, let document else { return }
        var model = document.model
        guard let pageIndex = model.pageIndex(for: activePageID) else { return }
        let offset = CGPoint(x: 40, y: 40)
        var newBoardIDs: [UUID] = []
        for board in clip.artboards {
            var nb = board
            nb.id = UUID()
            nb.frame.origin.x += offset.x; nb.frame.origin.y += offset.y
            for original in clip.nodes where Self.boardOwns(board, original.frame) {
                var c = cloned(original)
                c.frame.origin.x += offset.x; c.frame.origin.y += offset.y
                c.artboardID = nb.id
                model.pages[pageIndex].nodes.append(c)
            }
            model.pages[pageIndex].artboards.append(nb)
            newBoardIDs.append(nb.id)
        }
        document.setModel(model, undoManager: undoManager,
                          actionName: clip.artboards.count == 1 ? "Paste Artboard" : "Paste Artboards")
        app.selectedNodeIDs = []
        app.selectedArtboardIDs = Set(newBoardIDs)
        needsDisplay = true
    }

    /// The >50%-overlap ownership test against a specific board (clipboard has
    /// only the copied boards, so we can't use the document-wide resolver).
    private static func boardOwns(_ board: Artboard, _ nodeFrame: CGRect) -> Bool {
        let area = nodeFrame.width * nodeFrame.height
        guard area > 0 else { return false }
        let overlap = board.frame.intersection(nodeFrame)
        guard !overlap.isNull else { return false }
        return (overlap.width * overlap.height) / area > 0.5
    }

    @objc func delete(_ sender: Any?) { deleteSelection() }

    // MARK: Lock / Unlock (responder actions → Object menu + context menu)

    @objc func lockSelection(_ sender: Any?)   { setLockOnSelection(true) }
    @objc func unlockSelection(_ sender: Any?) { setLockOnSelection(false) }

    /// Set `isLocked` on every selected node (recursing into groups so a child
    /// selected inside a group is reached too) as one undo step. Selection is kept
    /// so an immediate Unlock (or Lock) can act on the same nodes — a locked node
    /// can't be re-picked on the canvas, but stays reachable via the Layers panel.
    private func setLockOnSelection(_ locked: Bool) {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        var nodes = currentNodes
        var changed = false
        for id in app.selectedNodeIDs {
            _ = Self.mutateNested(id, in: &nodes) { n in
                if n.isLocked != locked { n.isLocked = locked; changed = true }
            }
        }
        guard changed else { return }
        commitNodes(nodes, actionName: locked ? "Lock" : "Unlock")
        needsDisplay = true
    }

    /// True if any selected node (resolving nested children) satisfies `predicate`
    /// — used to enable Lock when something's unlocked and Unlock when locked.
    private func anySelected(_ predicate: (Node) -> Bool) -> Bool {
        guard let app, !app.selectedNodeIDs.isEmpty else { return false }
        return app.selectedNodeIDs.contains { id in node(id).map(predicate) ?? false }
    }

	@objc override func selectAll(_ sender: Any?) {
        guard let app else { return }
        if !app.selectedNodeIDs.isEmpty {
            switch selectionLevel(for: app.selectedNodeIDs) {
            case .group(let parentID):
                app.selectedNodeIDs = Set(childIDs(inParentGroup: parentID))
                app.selectedArtboardIDs = []
            case .topLevel:
                if !isSourceScope, let document {
                    let selected = currentNodes.filter { app.selectedNodeIDs.contains($0.id) }
                    let owners = Set(selected.compactMap { owningArtboard(of: $0)?.id })
                    let hasWall = selected.contains { owningArtboard(of: $0) == nil }
                    if owners.count == 1, !hasWall, let owner = owners.first {
                        app.selectedNodeIDs = Set(currentNodes.filter { owningArtboard(of: $0)?.id == owner }.map(\.id))
                        app.selectedArtboardIDs = []
                        needsDisplay = true
                        return
                    }
                    if owners.isEmpty, hasWall {
                        app.selectedNodeIDs = Set(currentNodes.filter { owningArtboard(of: $0) == nil }.map(\.id))
                        app.selectedArtboardIDs = []
                        needsDisplay = true
                        return
                    }
                }
                app.selectedNodeIDs = Set(currentNodes.map(\.id))
                app.selectedArtboardIDs = []
            case .mixed, .none:
                app.selectedNodeIDs = Set(currentNodes.map(\.id))
                app.selectedArtboardIDs = []
            }
            needsDisplay = true
            return
        }

        if !isSourceScope, let document, !app.selectedArtboardIDs.isEmpty {
            app.selectedArtboardIDs = Set(currentArtboards.map(\.id))
            app.selectedNodeIDs = Set(currentNodes.filter { owningArtboard(of: $0) == nil }.map(\.id))
            needsDisplay = true
            return
        }

        app.selectedNodeIDs = Set(currentNodes.map(\.id))
        app.selectedArtboardIDs = []
        needsDisplay = true
    }

    @objc func duplicateSelection(_ sender: Any?) { duplicate() }

    private func duplicate() {
        guard let app, let document, !app.selectedNodeIDs.isEmpty else { return }
        let baseline = document.model
        let newIDs = duplicateSelectedInPlace(offset: CGPoint(x: 10, y: 10))
        guard !newIDs.isEmpty else { return }
        document.registerUndo(restoring: baseline, undoManager: undoManager, actionName: "Duplicate")
        app.selectedNodeIDs = Set(newIDs)
        needsDisplay = true
    }

    @objc func duplicateArtboardsAction(_ sender: Any?) {
        guard let app, let document, !app.selectedArtboardIDs.isEmpty else { return }
        let baseline = document.model
        let dup = duplicateArtboards(Array(app.selectedArtboardIDs), offset: CGPoint(x: 20, y: 20))
        document.registerUndo(restoring: baseline, undoManager: undoManager, actionName: "Duplicate Artboard")
        app.selectedArtboardIDs = Set(dup.boardOrigins.keys)
        app.selectedNodeIDs = []
        needsDisplay = true
    }

    @objc func moveSelectionToPageAction(_ sender: Any?) {
        guard let request = pageTransferRequest(from: sender) else { return }
        transferSelection(request, duplicate: false)
    }

    @objc func duplicateSelectionToPageAction(_ sender: Any?) {
        guard let request = pageTransferRequest(from: sender) else { return }
        transferSelection(request, duplicate: true)
    }

    private func pageTransferRequest(from sender: Any?) -> CanvasPageTransferRequest? {
        if let request = sender as? CanvasPageTransferRequest { return request }
        if let item = sender as? NSMenuItem {
            if let request = item.representedObject as? CanvasPageTransferRequest { return request }
            if let id = item.representedObject as? UUID { return CanvasPageTransferRequest(pageID: id) }
            if let string = item.representedObject as? String,
               let id = UUID(uuidString: string) { return CanvasPageTransferRequest(pageID: id) }
        }
        return nil
    }

    /// One shared implementation backs the app menu, canvas context menu, and
    /// Layers context menu. Nested selections are promoted to destination-page
    /// top level with their absolute frame; selecting a child never carries its
    /// enclosing group along with it.
    private func transferSelection(_ request: CanvasPageTransferRequest, duplicate: Bool) {
        guard let app, let document, !isSourceScope,
              let sourceID = activePageID, sourceID != request.pageID else { return }
        let destinationID = request.pageID
        let requestedNodeIDs = request.nodeIDs ?? app.selectedNodeIDs
        let requestedBoardIDs = request.artboardIDs ?? app.selectedArtboardIDs
        guard !requestedNodeIDs.isEmpty || !requestedBoardIDs.isEmpty else { return }

        var model = document.model
        guard let sourceIndex = model.pages.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = model.pages.firstIndex(where: { $0.id == destinationID }) else { return }

        var selectedNodeIDs = Set<UUID>()
        var selectedBoardIDs = Set<UUID>()
        var transferredBounds: CGRect?

        if !requestedNodeIDs.isEmpty {
            let originals = collectSelectedNodes(requestedNodeIDs)
            guard !originals.isEmpty else { return }
            var movedSubtreeIDs = Set<UUID>()
            for original in originals { Self.collectSubtreeIDs(original, into: &movedSubtreeIDs) }
            let duplication = duplicate
                ? Document.duplicatingNodesForTransferWithMap(originals)
                : (nodes: originals, idMap: [:])
            let transferred = duplication.nodes
            let internalAnchors = model.pages[sourceIndex].anchoredRelationships.filter {
                relationshipIDs($0).isSubset(of: movedSubtreeIDs)
            }
            if !duplicate {
                Self.removeNested(requestedNodeIDs, from: &model.pages[sourceIndex].nodes)
                model.pages[sourceIndex].anchoredRelationships = Document.removingAnchors(
                    referencing: movedSubtreeIDs,
                    in: model.pages[sourceIndex].anchoredRelationships)
            }
            model.pages[destinationIndex].nodes.append(contentsOf: transferred)
            model.pages[destinationIndex].anchoredRelationships.append(contentsOf:
                duplicate ? remappedAnchors(internalAnchors, through: duplication.idMap)
                          : internalAnchors)
            selectedNodeIDs = Set(transferred.map(\.id))
            transferredBounds = transferred.dropFirst().reduce(transferred.first?.frame) {
                $0?.union($1.frame) ?? $1.frame
            }
        } else if !requestedBoardIDs.isEmpty {
            let boardIDs = requestedBoardIDs
            let sourcePage = model.pages[sourceIndex]
            let boards = sourcePage.artboards.filter { boardIDs.contains($0.id) }
            guard !boards.isEmpty else { return }
            let owned = sourcePage.nodes.filter { node in
                guard let owner = model.owningArtboard(of: node, on: sourceID) else { return false }
                return boardIDs.contains(owner.id)
            }
            var ownedSubtreeIDs = Set<UUID>()
            for node in owned { Self.collectSubtreeIDs(node, into: &ownedSubtreeIDs) }
            let internalAnchors = sourcePage.anchoredRelationships.filter {
                relationshipIDs($0).isSubset(of: ownedSubtreeIDs)
            }
            if duplicate {
                let duplication = Document.duplicatingNodesForTransferWithMap(owned)
                model.pages[destinationIndex].nodes.append(contentsOf: duplication.nodes)
                model.pages[destinationIndex].anchoredRelationships.append(contentsOf:
                    remappedAnchors(internalAnchors, through: duplication.idMap))
                let boardCopies = boards.map { board -> Artboard in
                    var copy = board
                    copy.id = UUID()
                    return copy
                }
                model.pages[destinationIndex].artboards.append(contentsOf: boardCopies)
                selectedBoardIDs = Set(boardCopies.map(\.id))
                transferredBounds = boardCopies.dropFirst().reduce(boardCopies.first?.frame) {
                    $0?.union($1.frame) ?? $1.frame
                }
            } else {
                let ownedIDs = Set(owned.map(\.id))
                model.pages[sourceIndex].nodes.removeAll { ownedIDs.contains($0.id) }
                model.pages[sourceIndex].artboards.removeAll { boardIDs.contains($0.id) }
                model.pages[sourceIndex].anchoredRelationships = Document.removingAnchors(
                    referencing: ownedSubtreeIDs,
                    in: model.pages[sourceIndex].anchoredRelationships)
                model.pages[destinationIndex].nodes.append(contentsOf: owned)
                model.pages[destinationIndex].artboards.append(contentsOf: boards)
                model.pages[destinationIndex].anchoredRelationships.append(contentsOf: internalAnchors)
                selectedBoardIDs = boardIDs
                transferredBounds = boards.dropFirst().reduce(boards.first?.frame) {
                    $0?.union($1.frame) ?? $1.frame
                }
            }
        } else {
            return
        }

        let verb = duplicate ? "Duplicate" : "Move"
        document.setModel(model, undoManager: undoManager, actionName: "\(verb) to Canvas Page")
        if let transferredBounds { pendingPageFocus = (destinationID, transferredBounds) }
        app.activeCanvasPageID = destinationID
        app.selectedNodeIDs = selectedNodeIDs
        app.selectedArtboardIDs = selectedBoardIDs
        app.selectionAnchorID = selectedNodeIDs.first
        syncActivePageIfNeeded()
        needsDisplay = true
    }

    private func relationshipIDs(_ relationship: AnchoredRelationship) -> Set<UUID> {
        Set(relationship.subject.path + relationship.target.path)
    }

    private func remappedAnchors(_ anchors: [AnchoredRelationship],
                                 through map: [UUID: UUID]) -> [AnchoredRelationship] {
        anchors.map {
            AnchoredRelationship(kind: $0.kind,
                                 subject: Document.remapped($0.subject, map: map),
                                 target: Document.remapped($0.target, map: map))
        }
    }

    // MARK: Artboard rename (inline label editor)

    @objc func renameArtboardAction(_ sender: Any?) {
        if let id = app?.selectedArtboardIDs.first { beginRenamingArtboard(id) }
    }

    /// Float a one-line text field over the artboard's name label to rename it.
    func beginRenamingArtboard(_ id: UUID) {
        guard let document, !isSourceScope,
              let ab = currentArtboards.first(where: { $0.id == id }) else { return }
        commitArtboardRename()   // finish any prior edit
        let r = docToView(ab.frame)
        let frame = CGRect(x: r.minX, y: max(0, r.minY - 22), width: max(r.width, 120), height: 18)
        let tf = NSTextField(frame: frame)
        tf.stringValue = ab.name
        tf.font = .systemFont(ofSize: 11)
        tf.bezelStyle = .squareBezel
        tf.isBezeled = true
        tf.drawsBackground = true
        tf.focusRingType = .none
        tf.delegate = self
        tf.target = self
        tf.action = #selector(artboardNameFieldAction(_:))   // Return commits
        addSubview(tf)
        window?.makeFirstResponder(tf)
        tf.currentEditor()?.selectAll(nil)
        artboardNameField = tf
        editingArtboardID = id
        needsDisplay = true
    }

    @objc private func artboardNameFieldAction(_ sender: Any?) { commitArtboardRename() }

    private func commitArtboardRename() {
        guard let tf = artboardNameField, let id = editingArtboardID, let document else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        tf.removeFromSuperview()
        artboardNameField = nil
        editingArtboardID = nil
        if !name.isEmpty, let i = currentArtboards.firstIndex(where: { $0.id == id }),
           currentArtboards[i].name != name {
            var model = document.model
            guard let pageIndex = model.pageIndex(for: activePageID) else { return }
            model.pages[pageIndex].artboards[i].name = name
            document.setModel(model, undoManager: undoManager, actionName: "Rename Artboard")
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    @objc func bringToFront(_ sender: Any?) { reorderSelection(toFront: true) }
    @objc func sendToBack(_ sender: Any?) { reorderSelection(toFront: false) }
    @objc func bringForward(_ sender: Any?) { nudgeOrder(by: +1) }
    @objc func sendBackward(_ sender: Any?) { nudgeOrder(by: -1) }
    @objc func flipHorizontalAction(_ sender: Any?) { flipSelection(horizontal: true) }
    @objc func flipVerticalAction(_ sender: Any?) { flipSelection(horizontal: false) }

    @objc func copyLayerStyle(_ sender: Any?) { copySelectedStyle() }
    @objc func pasteLayerStyle(_ sender: Any?) { pasteStyleToSelection() }

    /// The node whose appearance "Copy Style" reads: the first selected node in
    /// document (z) order, so it's deterministic even with a multi-selection. nil
    /// when nothing is selected.
    private func primaryStyleSourceNode() -> Node? {
        guard let app, !app.selectedNodeIDs.isEmpty else { return nil }
        func walk(_ nodes: [Node]) -> Node? {
            for n in nodes {
                if app.selectedNodeIDs.contains(n.id) { return n }
                if case .group(let kids) = n.content, let f = walk(kids) { return f }
            }
            return nil
        }
        return walk(currentNodes)
    }

    /// Copy Style — capture the primary selected node's effects + blend mode +
    /// opacity into the shared clipboard (no undo; it changes nothing on canvas).
    private func copySelectedStyle() {
        guard let app, let src = primaryStyleSourceNode() else { return }
        app.copiedLayerStyle = src.layerStyle
    }

    /// Paste Style — apply the copied appearance to every selected node (recursing
    /// into groups so a child picked inside a group is reached too) as one undo
    /// step. Only appearance is touched; geometry/fill/content stay put.
    private func pasteStyleToSelection() {
        guard let app, let style = app.copiedLayerStyle, !app.selectedNodeIDs.isEmpty else { return }
        var nodes = currentNodes
        var changed = false
        for id in app.selectedNodeIDs {
            if Self.mutateNested(id, in: &nodes, { $0.applyLayerStyle(style) }) { changed = true }
        }
        guard changed else { return }
        commitNodes(nodes, actionName: "Paste Style")
        needsDisplay = true
    }

    /// Mirror each selected node about its own centre (a render-time flag, so it
    /// works for images/text/paths/groups alike). One undo step.
    private func flipSelection(horizontal: Bool) {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        var nodes = currentNodes
        for id in app.selectedNodeIDs {
            Self.mutateNested(id, in: &nodes) { n in
                if horizontal { n.flipH.toggle() } else { n.flipV.toggle() }
            }
        }
        commitNodes(nodes, actionName: horizontal ? "Flip Horizontal" : "Flip Vertical")
        needsDisplay = true
    }

    /// Move the selection one step in z-order (+1 forward/up, -1 backward/down),
    /// keeping a multi-selection grouped. Bubble the selected past one neighbor.
    private func nudgeOrder(by delta: Int) {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        let selected = app.selectedNodeIDs
        var nodes = currentNodes
        // Reorder within whichever parent each selected node lives in (top-level or
        // a group's children), bubbling each past one unselected neighbor.
        Self.reorderInParents(selected, in: &nodes) { arr in
            if delta > 0 {
                var i = arr.count - 2
                while i >= 0 {
                    if selected.contains(arr[i].id) && !selected.contains(arr[i + 1].id) { arr.swapAt(i, i + 1) }
                    i -= 1
                }
            } else {
                var i = 1
                while i < arr.count {
                    if selected.contains(arr[i].id) && !selected.contains(arr[i - 1].id) { arr.swapAt(i, i - 1) }
                    i += 1
                }
            }
        }
        commitNodes(nodes, actionName: delta > 0 ? "Bring Forward" : "Send Backward")
        needsDisplay = true
    }

    private func reorderSelection(toFront: Bool) {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        let selected = app.selectedNodeIDs
        var nodes = currentNodes
        Self.reorderInParents(selected, in: &nodes) { arr in
            let moved = arr.filter { selected.contains($0.id) }
            guard !moved.isEmpty else { return }
            arr.removeAll { selected.contains($0.id) }
            if toFront { arr.append(contentsOf: moved) } else { arr.insert(contentsOf: moved, at: 0) }
        }
        commitNodes(nodes, actionName: toFront ? "Bring to Front" : "Send to Back")
        needsDisplay = true
    }

    @objc func fitToScreen(_ sender: Any?) { zoomToFit() }

    /// Bring the selection on screen. Deliberately "center", not "zoom to" — it
    /// preserves your zoom unless the selection can't fit at it.
    @objc func centerSelectionAction(_ sender: Any?) { revealInViewport(selectionBounds()) }
    @objc func zoomInAction(_ sender: Any?) {
        app?.viewportSize = bounds.size
        app?.zoomIn()
        scheduleCameraPersistenceIfReady()
        needsDisplay = true
    }
    @objc func zoomOutAction(_ sender: Any?) {
        app?.viewportSize = bounds.size
        app?.zoomOut()
        scheduleCameraPersistenceIfReady()
        needsDisplay = true
    }
    @objc func zoomActualAction(_ sender: Any?) {
        app?.viewportSize = bounds.size
        app?.zoomActual()
        scheduleCameraPersistenceIfReady()
        needsDisplay = true
    }

    @objc func toggleSelectionBounds(_ sender: Any?) {
        app?.showSelectionBounds.toggle()
        needsDisplay = true
    }

    @objc func toggleAutoSelectLayersAction(_ sender: Any?) {
        app?.autoSelectLayers.toggle()
    }

    /// Layers rows call this after a pointer selection so arrows and standard edit
    /// commands immediately act on the layer just chosen rather than stale panel focus.
    @objc func focusCanvasAction(_ sender: Any?) {
        guard let window else { return }
        // In Single-Window mode changing first responder is enough. In Multi-Window
        // mode the Layers tray is a DIFFERENT key window; setting a responder on this
        // inactive document window does not redirect the next arrow key. Make the
        // document key as well, then put focus on its canvas. Floating trays stay
        // visibly above it without owning keyboard input (see PanelWindow.open).
        window.makeKey()
        window.makeFirstResponder(self)
    }

    @objc func toggleRulersAction(_ sender: Any?) {
        app?.showRulers.toggle()
        needsDisplay = true
    }
    @objc func toggleGuidesAction(_ sender: Any?) {
        app?.showGuides.toggle()
        needsDisplay = true
    }
    @objc func toggleLockGuidesAction(_ sender: Any?) {
        app?.guidesLocked.toggle()
    }
    @objc func clearGuidesAction(_ sender: Any?) {
        guard let document, !currentGuides.isEmpty else { return }
        let baseline = document.model
        withActivePage { $0.guides.removeAll() }
        document.registerUndo(restoring: baseline, undoManager: undoManager, actionName: "Clear Guides")
        needsDisplay = true
    }
    @objc func toggleGridAction(_ sender: Any?) {
        app?.showGrid.toggle()
        needsDisplay = true
    }
    @objc func toggleSnapToGridAction(_ sender: Any?) {
        app?.snapToGrid.toggle()
    }

    /// BUG-036(b). Off = drags move through fractional values; ⌘ still bypasses
    /// snapping for a single drag either way.
    @objc func togglePixelSnapAction(_ sender: Any?) {
        app?.pixelSnap.toggle()
    }
    
    @objc func toggleSmartGuidesAction(_ sender: Any?) {
        app?.smartGuidesEnabled.toggle()
    }

    /// Developer Testing Mode — hidden from the public menus. When enabled
    /// internally, lightweight perf stats stream to the diagnostic file only.
    @objc func toggleTestingModeAction(_ sender: Any?) {
        app?.testingMode.toggle()
        let on = app?.testingMode == true
        perf.enabled = on
        perf.reset()
        let msg = "[EXP perf] Testing Mode \(on ? "ON — logging frame / snap / cull stats ~2x/sec" : "off")"
        DiagnosticLog.shared.log(msg)
    }

    // MARK: Round to Pixel (v1.3 — companion to the geometry audit)

    /// Snap every selected node's and artboard's frame (origin AND size) to
    /// whole pixels, in one undo step. The cure for imported-SVG fuzziness:
    /// fractional frames antialias across 2px and read "soft" (see the
    /// geometry audit). Nested selections round in their local space — the
    /// same space their frames live in.
    @objc func roundToPixelAction(_ sender: Any?) {
        guard let app, let document else { return }
        let nodeIDs = app.selectedNodeIDs
        let boardIDs = app.selectedArtboardIDs
        guard !nodeIDs.isEmpty || !boardIDs.isEmpty else { return }
        var model = document.model
        func rounded(_ r: CGRect) -> CGRect {
            CGRect(x: r.origin.x.rounded(), y: r.origin.y.rounded(),
                   width: max(1, r.width.rounded()), height: max(1, r.height.rounded()))
        }
        func walk(_ nodes: inout [Node]) {
            for i in nodes.indices {
                if nodeIDs.contains(nodes[i].id) { nodes[i].frame = rounded(nodes[i].frame) }
                if case .group(var kids) = nodes[i].content {
                    walk(&kids); nodes[i].content = .group(children: kids)
                }
            }
        }
        switch scope {
        case .document:
            guard let pageIndex = model.pageIndex(for: activePageID) else { return }
            walk(&model.pages[pageIndex].nodes)
            model.pages[pageIndex].nodes = model.reflowed(model.pages[pageIndex].nodes)
            for i in model.pages[pageIndex].artboards.indices
            where boardIDs.contains(model.pages[pageIndex].artboards[i].id) {
                model.pages[pageIndex].artboards[i].frame = rounded(model.pages[pageIndex].artboards[i].frame)
            }
        case .source(let sid):
            guard let si = model.sources.firstIndex(where: { $0.id == sid }) else { return }
            walk(&model.sources[si].children)
            model.sources[si].children = model.reflowed(model.sources[si].children)
        }
        document.setModel(model, undoManager: undoManager, actionName: "Round to Pixel")
        needsDisplay = true
    }

    // MARK: Geometry audit + diagnostic report (v1.3 tester tooling)

    /// Numeric proof for "do these two objects REALLY have the same size?" —
    /// reports doc-space frames and the EXACT view-space rects the renderer
    /// paints, for the current selection (or every artboard + top-level node
    /// when nothing is selected), then cross-checks every pair with equal doc
    /// sizes. Separates "the math is wrong" (a real bug — flagged loudly) from
    /// "the paint reads differently":
    ///  • a shape's outline reach follows its Inside / Center / Outside setting,
    ///    and the audit reports the same painted-outer bounds as the Inspector;
    ///  • an artboard's 1px hairline is drawn fully INSIDE its frame, and its
    ///    drop shadow softens the bottom edge;
    ///  • fractional origins/sizes antialias across 2px and read "soft".
    private func geometryAuditLines() -> [String] {
        guard let app, let document else { return ["(geometry audit: no document)"] }
        struct Item {
            let kind: String
            let name: String
            let frame: CGRect
            let painted: CGRect
            let visualNote: String
        }
        var items: [Item] = []

        let selBoards = app.selectedArtboardIDs
        let selNodes = app.selectedNodeIDs
        let auditAll = selBoards.isEmpty && selNodes.isEmpty

        for ab in currentArtboards where auditAll || selBoards.contains(ab.id) {
            items.append(Item(kind: "artboard", name: ab.name, frame: ab.frame, painted: ab.frame,
                              visualNote: "1px hairline drawn INSIDE frame; shadow softens bottom edge"))
        }
        for node in currentNodes where auditAll || selNodes.contains(node.id) {
            let reach = strokeReach(node.content)
            let note: String
            switch node.content {
            case .rectangle(let s) where s.strokeWidth > 0:
                note = "\(s.strokeAlignment.label.lowercased()) stroke; outer reach \(String(format: "%.2f", reach))pt"
            case .ellipse(let s) where s.strokeWidth > 0:
                note = "\(s.strokeAlignment.label.lowercased()) stroke; outer reach \(String(format: "%.2f", reach))pt"
            case .polygon(let s) where s.strokeWidth > 0:
                note = "\(s.strokeAlignment.label.lowercased()) stroke; outer reach \(String(format: "%.2f", reach))pt"
            case .path(let s) where s.strokeWidth > 0:
                note = "\(s.effectiveStrokeAlignment.label.lowercased()) stroke; outer reach \(String(format: "%.2f", reach))pt"
            case .line(let s) where s.strokeWidth > 0:
                note = "centered line stroke; outer reach \(String(format: "%.2f", reach))pt"
            default:
                note = "no outline beyond geometry frame"
            }
            items.append(Item(kind: "node", name: node.name, frame: node.frame,
                              painted: SelectionTransform.paintedBounds(node), visualNote: note))
        }

        var lines: [String] = []
        lines.append(String(format: "— GEOMETRY AUDIT — zoom %.4f  pan (%.2f, %.2f)  backing %.0f×  scope: %@  (%d object(s))",
                            app.zoom, app.panOffset.x, app.panOffset.y, backingScale,
                            auditAll ? "all" : "selection", items.count))
        for it in items {
            let v = docToView(it.frame)
            let frac = it.frame.minX != it.frame.minX.rounded()
                    || it.frame.minY != it.frame.minY.rounded()
                    || it.frame.width != it.frame.width.rounded()
                    || it.frame.height != it.frame.height.rounded()
            lines.append(String(format: "%@ \"%@\": doc(x %.3f, y %.3f, w %.3f, h %.3f)%@",
                                it.kind, it.name, it.frame.minX, it.frame.minY,
                                it.frame.width, it.frame.height,
                                frac ? "  ⚠️ fractional — edges antialias across 2px" : ""))
            lines.append(String(format: "    view(x %.3f, y %.3f, w %.3f, h %.3f) — %@",
                                v.minX, v.minY, v.width, v.height, it.visualNote))
            if it.painted != it.frame {
                lines.append(String(format: "    inspector outer(x %.3f, y %.3f, w %.3f, h %.3f)",
                                    it.painted.minX, it.painted.minY,
                                    it.painted.width, it.painted.height))
            }
        }
        // Any two audited objects with equal doc sizes MUST produce identical
        // view sizes (same docToView math). If they don't, that IS the bug.
        for i in items.indices {
            for j in items.indices where j > i {
                let a = items[i], b = items[j]
                guard a.frame.size == b.frame.size else { continue }
                let va = docToView(a.frame), vb = docToView(b.frame)
                let dw = abs(va.width - vb.width), dh = abs(va.height - vb.height)
                if dw < 0.0001, dh < 0.0001 {
                    lines.append("✓ \"\(a.name)\" + \"\(b.name)\": equal doc sizes → identical view sizes (renderer math agrees)")
                } else {
                    lines.append(String(format: "✗ \"%@\" vs \"%@\": equal doc sizes but view sizes differ by (%.4f, %.4f) — REPORT THIS",
                                        a.name, b.name, dw, dh))
                }
            }
        }
        return lines
    }

    /// Hidden developer action. Writes the geometry audit to the diagnostic log
    /// and confirms with a small alert.
    @objc func runGeometryAuditAction(_ sender: Any?) {
        let lines = geometryAuditLines()
        DiagnosticLog.shared.log(lines: lines)

        let mismatches = lines.filter { $0.hasPrefix("✗") }.count
        let alert = NSAlert()
        alert.messageText = "Geometry Audit Complete"
        alert.informativeText = mismatches == 0
            ? "Size math checks out for every audited object."
            : "\(mismatches) size mismatch(es) found — details are in the diagnostic log. Please send them via Help ▸ Save Diagnostic Report."
        alert.alertStyle = mismatches == 0 ? .informational : .warning
        alert.runModal()
    }

    /// HELP ▸ Save Diagnostic Report… — one shareable file: machine/app header,
    /// document stats, and a geometry audit. NSSavePanel keeps it sandbox-safe
    /// and lets the tester choose where.
    @objc func saveDiagnosticReportAction(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.title = "Save Diagnostic Report"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmm"
        df.locale = Locale(identifier: "en_US_POSIX")
        panel.nameFieldStringValue = "EXP-diagnostic-report-\(df.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            var lines = DiagnosticLog.sessionHeader()
            let scales = NSScreen.screens
                .map { String(format: "%.0f×", $0.backingScaleFactor) }
                .joined(separator: ", ")
            lines.append("Displays: \(NSScreen.screens.count) (backing \(scales))")
            if let model = self.document?.model {
                lines.append("Document: \(model.allNodes.count) top-level node(s), \(model.allArtboards.count) artboard(s), \(model.pages.count) canvas page(s), \(model.sources.count) component source(s)")
            }
            lines.append("")
            lines.append(contentsOf: self.geometryAuditLines())
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func deselectAllAction(_ sender: Any?) {
        app?.selectedNodeIDs = []
        app?.selectedArtboardIDs = []
        needsDisplay = true
    }

    // Lifecycle-safe requests consumed by the live docked, floating, or source
    // Layers surface. No view/proxy closure crosses an NSWindow boundary.
    @objc func expandAllLayersAction(_ sender: Any?) {
        app?.requestLayersPanelCommand(.expandAll)
    }
    @objc func collapseAllLayersAction(_ sender: Any?) {
        app?.requestLayersPanelCommand(.collapseAll)
    }
    @objc func revealSelectionInLayersAction(_ sender: Any?) {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        if !isSourceScope { app.revealPanel(.layers) }
        app.requestLayersPanelCommand(.revealSelection)
    }
    @objc func showRelationshipsAction(_ sender: Any?) {
        guard let app, canEditRelationships else { return }
        if !app.isPanelShown(.properties) { app.togglePanel(.properties) }
        app.showRightPanel = true
    }

    // MARK: Panels menu (show/hide panels, reset layout)

    @objc func togglePanelLayers(_ sender: Any?)     { app?.togglePanel(.layers) }
    @objc func togglePanelProperties(_ sender: Any?) { app?.togglePanel(.properties) }
    @objc func togglePanelComponents(_ sender: Any?) { app?.togglePanel(.components) }
    @objc func sendFeedbackAction(_ sender: Any?) { app?.showingFeedback = true }
    @objc func toggleLeftDock(_ sender: Any?)        { app?.showLeftPanel.toggle() }
    @objc func toggleRightDock(_ sender: Any?)       { app?.showRightPanel.toggle() }
    @objc func resetPanelLayout(_ sender: Any?)      { app?.resetWorkspace() }

    // MARK: Export

    /// The artboard an export targets: the selected artboard, else the owning
    /// artboard of a selected shape, else the first artboard.
    private func targetExportArtboard() -> Artboard? {
        guard let document else { return nil }
        if let id = app?.selectedArtboardID, let ab = currentArtboards.first(where: { $0.id == id }) { return ab }
        if let nid = app?.selectedNodeIDs.first, let n = node(nid),
           let owner = owningArtboard(of: n) { return owner }
        return currentArtboards.first
    }

    /// The artboards an export targets: all selected boards (document order),
    /// else the single fallback target.
    private func selectedExportArtboards() -> [Artboard] {
        guard let document, let app else { return [] }
        if !app.selectedArtboardIDs.isEmpty {
            return currentArtboards.filter { app.selectedArtboardIDs.contains($0.id) }
        }
        return targetExportArtboard().map { [$0] } ?? []
    }

    @objc func exportSelectedArtboard(_ sender: Any?) {
        guard let document else { NSSound.beep(); return }
        let boards = selectedExportArtboards()
        guard !boards.isEmpty else { NSSound.beep(); return }
        let panels = ExportPanels(model: document.model)
        exportPanels = panels
        if boards.count == 1 {
            panels.exportSelected(boards[0], in: window)
        } else {
            // Multiple boards → folder + format picker + combine-PDF option.
            panels.exportAll(boards, in: window,
                             message: "Choose a folder to export the \(boards.count) selected artboards.")
        }
    }

    @objc func exportAllArtboards(_ sender: Any?) {
        guard let document, !currentArtboards.isEmpty else { NSSound.beep(); return }
        let panels = ExportPanels(model: document.model)
        exportPanels = panels
        panels.exportAll(currentArtboards, in: window)
    }

    @objc func exportHandoffPackage(_ sender: Any?) {
        guard let document else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: HandoffPackageWriter.packageExtension) ?? .folder]
        let baseName = window?.representedURL?.deletingPathExtension().lastPathComponent
            ?? window?.title
            ?? "EXP Handoff"
        panel.nameFieldStringValue = "\(baseName).\(HandoffPackageWriter.packageExtension)"
        panel.message = "Export a folder package with design.json, tokens.json, a manifest, and an LLM-readable README."

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try HandoffPackageWriter(document: document.model,
                                         sourceURL: self.window?.representedURL).write(to: url)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Handoff package export failed"
                if let window = self.window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    /// Standalone semantic HTML/CSS export. The full handoff package remains the
    /// richer artifact; this is the quick path for a developer who only needs
    /// inspectable web output.
    @objc func exportSemanticHTMLAction(_ sender: Any?) {
        guard let document else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the generated HTML pages and shared styles.css file."

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let directory = panel.url else { return }
            do {
                let bundle = SemanticHTMLExporter(document: document.model).makeBundle()
                for artifact in bundle.artifacts {
                    let relativePath = artifact.path.hasPrefix("html/")
                        ? String(artifact.path.dropFirst("html/".count)) : artifact.path
                    let target = directory.appendingPathComponent(relativePath)
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try artifact.data.write(to: target, options: .atomic)
                }
            } catch {
                self.presentExportError(error, title: "Semantic HTML export failed")
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    /// CodePen currently supports creating a new Pen through a documented form
    /// POST, not authenticated update-in-place source sync. Open a local,
    /// accessible review page in the person's browser so no design bytes leave
    /// EXP until they explicitly press Send to CodePen there.
    @objc func exportCurrentArtboardToCodePen(_ sender: Any?) {
        guard let document else { NSSound.beep(); return }
        let boards = selectedExportArtboards()
        guard boards.count == 1, let artboard = boards.first else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Choose One Artboard"
            alert.informativeText = "A new CodePen Pen represents one page. Select one artboard, then try again."
            if let window { alert.beginSheetModal(for: window) }
            else { alert.runModal() }
            return
        }
        do {
            let package = try CodePenPrefillExporter(document: document.model)
                .makePackage(artboardID: artboard.id)
            let launcher = FileManager.default.temporaryDirectory
                .appendingPathComponent("EXP-CodePen-\(UUID().uuidString)")
                .appendingPathExtension("html")
            try package.launcherHTML.write(to: launcher, options: .atomic)
            guard NSWorkspace.shared.open(launcher) else {
                throw CocoaError(.fileNoSuchFile)
            }
        } catch {
            presentExportError(error, title: "CodePen handoff failed")
        }
    }

    /// Design Language tokens in the W3C Design Tokens Community Group shape.
    @objc func exportDesignTokensAction(_ sender: Any?) {
        guard let document else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "tokens.json"
        panel.message = "Export this document's Design Language as portable design tokens."

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let data = try DesignLanguageIO.exportDesignTokensJSON(document.model.designLanguage)
                try data.write(to: url, options: .atomic)
            } catch {
                self.presentExportError(error, title: "Design token export failed")
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    private func presentExportError(_ error: Error, title: String) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: Point corner/curve toggle

    @objc func togglePointCurveAction(_ sender: Any?) {
        if let t = pendingCurveToggle { togglePointCurve(nodeID: t.id, contour: t.contour, index: t.index) }
    }

    /// Convert an anchor between a corner (no handles) and a smooth bezier point
    /// (symmetric handles along the local tangent). Works on any contour.
    private func togglePointCurve(nodeID: UUID, contour c: Int, index: Int) {
        guard let document, let n = node(nodeID), case .path(var ps) = n.content,
              let anchor = ps.editPoint(contour: c, index: index) else { return }
        let baseline = document.model
        if anchor.controlIn != nil || anchor.controlOut != nil {
            ps.mutatePoint(contour: c, index: index) { $0.controlIn = nil; $0.controlOut = nil }
        } else {
            let pts = ps.editContours[c]
            let count = pts.count
            let closedC = ps.contourClosed(c)
            let a = anchor.point
            let prev = (closedC || index > 0) ? pts[(index - 1 + count) % count].point : a
            let next = (closedC || index < count - 1) ? pts[(index + 1) % count].point : a
            var dir = CGPoint(x: next.x - prev.x, y: next.y - prev.y)
            let len = hypot(dir.x, dir.y)
            if len > 0 { dir.x /= len; dir.y /= len } else { dir = CGPoint(x: 1, y: 0) }
            let prevLen = hypot(a.x - prev.x, a.y - prev.y)
            let nextLen = hypot(next.x - a.x, next.y - a.y)
            let usable = [prevLen, nextLen].filter { $0 > 0.001 }
            let localScale = usable.min() ?? max(min(n.frame.width, n.frame.height), 4)
            // Keep the default gentle. The old minimum of 20 document units could
            // dwarf small imported SVG paths and create giant handles/segments.
            let reach = min(max(localScale * 0.25, 1), 12)
            ps.mutatePoint(contour: c, index: index) {
                $0.controlOut = CGPoint(x: a.x + dir.x * reach, y: a.y + dir.y * reach)
                $0.controlIn = CGPoint(x: a.x - dir.x * reach, y: a.y - dir.y * reach)
            }
        }
        updateNode(nodeID) { $0.content = .path(ps) }
        document.registerUndo(restoring: baseline, undoManager: undoManager, actionName: "Toggle Point")
        needsDisplay = true
    }

    // MARK: Grouping

    @objc func groupSelection(_ sender: Any?) { group() }
    @objc func ungroupSelection(_ sender: Any?) { ungroup() }
    @objc func maskWithTopShapeAction(_ sender: Any?) { maskWithTopShape() }
    @objc func releaseMaskAction(_ sender: Any?) { releaseMask() }
    @objc func eyedropperAction(_ sender: Any?) { eyedropToSelection() }   // keyboard: i
    @objc func toggleAutoLayoutAction(_ sender: Any?) { toggleFrameTrait(.layout) }
    @objc func toggleAutoPaddingAction(_ sender: Any?) { toggleFrameTrait(.padding) }
    @objc func nudgeItemForwardAction(_ sender: Any?) { nudgeItem(forward: true) }
    @objc func nudgeItemBackwardAction(_ sender: Any?) { nudgeItem(forward: false) }

    /// The single selected node, if it's a group (top-level or nested).
    private var singleSelectedGroupID: UUID? {
        guard let app, app.selectedNodeIDs.count == 1, let id = app.selectedNodeIDs.first,
              case .group = node(id)?.content else { return nil }
        return id
    }

    /// True when the one selected group already stacks (autoLayout).
    var selectedGroupHasAutoLayout: Bool {
        guard let id = singleSelectedGroupID else { return false }
        return node(id)?.autoLayout != nil
    }
    /// True when the one selected group already pads (autoPadding).
    var selectedGroupHasAutoPadding: Bool {
        guard let id = singleSelectedGroupID else { return false }
        return node(id)?.autoPadding != nil
    }
    /// True when the one selected node is an item inside an auto-layout stack.
    var selectedItemInAutoLayout: Bool {
        guard let app, app.selectedNodeIDs.count == 1, let id = app.selectedNodeIDs.first,
              let pid = parentGroupID(of: id) else { return false }
        return node(pid)?.autoLayout != nil
    }

    private enum FrameTrait { case layout, padding }

    /// Add/Remove a frame trait. A single selected group toggles that trait; any
    /// other non-empty selection is wrapped in a group first, then the trait is
    /// enabled (Figma-style).  ⌥⌘A = Auto Layout (stacking), ⌥⌘P = Auto Padding.
    private func toggleFrameTrait(_ trait: FrameTrait) {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }

        if let gid = singleSelectedGroupID {
            let has = (trait == .layout) ? node(gid)?.autoLayout != nil : node(gid)?.autoPadding != nil
            var nodes = currentNodes
            Self.mutateNested(gid, in: &nodes) { g in
                if has { if trait == .layout { g.autoLayout = nil } else { g.autoPadding = nil } }
                else { Self.enableTrait(trait, on: &g) }
            }
            commitNodes(nodes, actionName: Self.traitActionName(trait, adding: !has))
            needsDisplay = true
            return
        }

        // Wrap the selection in a group, then enable the trait on it.
        group()
        guard let gid = singleSelectedGroupID else { return }
        var nodes = currentNodes
        Self.mutateNested(gid, in: &nodes) { g in Self.enableTrait(trait, on: &g) }
        commitNodes(nodes, actionName: Self.traitActionName(trait, adding: true))
        needsDisplay = true
    }

    private static func traitActionName(_ t: FrameTrait, adding: Bool) -> String {
        switch (t, adding) {
        case (.layout, true):  return "Add Auto Layout"
        case (.layout, false): return "Remove Auto Layout"
        case (.padding, true): return "Add Auto Padding"
        case (.padding, false):return "Remove Auto Padding"
        }
    }

    private static func enableTrait(_ t: FrameTrait, on g: inout Node) {
        switch t {
        case .layout:
            var al = AutoLayout(); al.direction = guessedDirection(of: g); g.autoLayout = al
        case .padding:
            AutoLayoutEngine.enableAutoPadding(on: &g)   // absorb enclosing background
        }
    }

    /// Move the selected item one slot along its auto-layout parent's axis. Works by
    /// pushing the item's position just past (or before) its neighbour; the reflow
    /// then re-sorts and normalises the spacing. ⌥⌘] / ⌥⌘[.
    private func nudgeItem(forward: Bool) {
        guard let app, app.selectedNodeIDs.count == 1, let id = app.selectedNodeIDs.first,
              let pid = parentGroupID(of: id), let parent = node(pid),
              let al = parent.autoLayout, case .group(let kids) = parent.content else { return }
        let horizontal = al.direction == .horizontal
        func primary(_ n: Node) -> CGFloat { horizontal ? n.frame.minX : n.frame.minY }
        func primarySize(_ n: Node) -> CGFloat { horizontal ? n.frame.width : n.frame.height }
        let sorted = kids.filter { $0.isVisible }.sorted { primary($0) < primary($1) }
        guard let k = sorted.firstIndex(where: { $0.id == id }) else { return }
        let target = forward ? k + 1 : k - 1
        guard target >= 0, target < sorted.count else { return }
        let neighbor = sorted[target]
        let newPrimary = forward ? primary(neighbor) + primarySize(neighbor)
                                 : primary(neighbor) - primarySize(sorted[k])
        var nodes = currentNodes
        Self.mutateNested(id, in: &nodes) { n in
            if horizontal { n.frame.origin.x = newPrimary } else { n.frame.origin.y = newPrimary }
        }
        commitNodes(nodes, actionName: "Reorder Item")
        needsDisplay = true
    }

    /// Guess a frame's direction from how its children are currently arranged:
    /// wider spread ⇒ a row, taller spread ⇒ a column.
    private static func guessedDirection(of g: Node) -> AutoLayout.Direction {
        guard case .group(let kids) = g.content, kids.count >= 2 else { return .horizontal }
        let xs = kids.map { $0.frame.midX }, ys = kids.map { $0.frame.midY }
        let spanX = (xs.max() ?? 0) - (xs.min() ?? 0)
        let spanY = (ys.max() ?? 0) - (ys.min() ?? 0)
        return spanX >= spanY ? .horizontal : .vertical
    }

    /// True if any selected node is a group (recursive — nested groups count too).
    private var selectionHasGroup: Bool {
        guard let app else { return false }
        return app.selectedNodeIDs.contains {
            if case .group = node($0)?.content { return true }
            return false
        }
    }

    /// Wrap the selected top-level nodes into a group. Children are stored in
    /// group-local coordinates (relative to the group's bounding box) so moving
    /// the group moves them for free.
    private func group() {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        let ids = app.selectedNodeIDs
        var nodes = currentNodes
        var newGroupID: UUID?

        // Build a group from the selected nodes already present in `arr`, in place.
        func groupInPlace(_ arr: inout [Node]) {
            let selected = arr.filter { ids.contains($0.id) }
            guard !selected.isEmpty else { return }
            let inheritedOwners = Set(selected.compactMap(\.artboardID))
            let frames = selected.map(\.frame)
            let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
            let children = selected.map { n -> Node in
                var c = n
                c.frame = c.frame.offsetBy(dx: -union.minX, dy: -union.minY)
                c.artboardID = nil
                return c
            }
            // BUG-032: the group used to `append`, i.e. land at the very top of the
            // stack no matter where its members were. It should take the z-position
            // of its TOP-MOST member and go no higher — what Illustrator and Figma
            // both do, and what the owner expected.
            //
            // Later in the array = higher in z, so the top-most member is the LAST
            // selected index. Count the unselected rows below it; after the removal
            // that count IS the insertion index, which puts the group above
            // everything that was below its top-most member and below everything
            // that was above it.
            let topMost = arr.lastIndex { ids.contains($0.id) } ?? arr.count - 1
            let unselectedBelow = arr[..<topMost].filter { !ids.contains($0.id) }.count
            arr.removeAll { ids.contains($0.id) }
            let g = Node(name: "Group", frame: union,
                         artboardID: inheritedOwners.count == 1 ? inheritedOwners.first : nil,
                         content: .group(children: children))
            arr.insert(g, at: Swift.min(unselectedBelow, arr.count))
            newGroupID = g.id
        }

        let parents = Set(ids.map { parentGroupID(of: $0) })
        if parents.count == 1, let parent = parents.first {
            if let pid = parent {
                // Same parent group → group within that group's children only.
                Self.mutateNested(pid, in: &nodes) { g in
                    guard case .group(var kids) = g.content else { return }
                    groupInPlace(&kids)
                    g.content = .group(children: kids)
                }
            } else {
                groupInPlace(&nodes)   // all top-level
            }
        } else {
            // Selection spans multiple parents → pull to a top-level group (absolute
            // frames preserve on-screen position).
            let selected = collectSelectedNodes()
            guard !selected.isEmpty else { return }
            let inheritedOwners = Set(selected.compactMap(\.artboardID))
            let frames = selected.map(\.frame)
            let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
            let children = selected.map { n -> Node in
                var c = n
                c.frame = c.frame.offsetBy(dx: -union.minX, dy: -union.minY)
                c.artboardID = nil
                return c
            }
            // Cross-parent selection. Anchor on the top-most TOP-LEVEL node that is
            // itself selected; when every selected node is nested there is no
            // top-level anchor to speak of, so the old append is kept. Deliberately
            // NOT trying to resolve each nested node's top-level ancestor here —
            // that is a bigger change and this branch is the rarer case. Recorded so
            // the limitation is visible rather than discovered later. BUG-032.
            let topMostTopLevel = nodes.lastIndex { ids.contains($0.id) }
            let unselectedBelow = topMostTopLevel.map { nodes[..<$0].filter { !ids.contains($0.id) }.count }
            Self.removeNested(ids, from: &nodes)
            let g = Node(name: "Group", frame: union,
                         artboardID: inheritedOwners.count == 1 ? inheritedOwners.first : nil,
                         content: .group(children: children))
            if let at = unselectedBelow { nodes.insert(g, at: Swift.min(at, nodes.count)) }
            else { nodes.append(g) }
            newGroupID = g.id
        }

        guard let gid = newGroupID else { return }
        commitNodes(nodes, actionName: "Group")
        app.selectedNodeIDs = [gid]
        app.selectedArtboardID = nil
        needsDisplay = true
    }

    /// The group directly containing `id`, or nil if it's top-level.
    private func parentGroupID(of id: UUID) -> UUID? {
        var result: UUID?
        func walk(_ nodes: [Node], _ parent: UUID?) -> Bool {
            for n in nodes {
                if n.id == id { result = parent; return true }
                if case .group(let k) = n.content, walk(k, n.id) { return true }
            }
            return false
        }
        _ = walk(currentNodes, nil)
        return result
    }

    /// Replace each selected group with its children, rebased into the parent's
    /// coordinates — anywhere in the tree (including a group nested in a group).
    private func ungroup() {
        guard let app else { return }
        let sel = app.selectedNodeIDs
        var freed = Set<UUID>()
        /// Relationships freed at the CURRENT level by a group disappearing. They
        /// have to move UP to whatever now contains both ends — endpoints stay
        /// valid because a path names component instances only, never groups, so a
        /// link survives ungrouping as long as its STORAGE does. Before this, the
        /// group node was replaced by its children and its `anchoredRelationships`
        /// went with it: authored semantics destroyed by an ordinary edit, with no
        /// warning. Exactly the silent loss BUG-012 was filed for, one door over.
        func process(_ arr: inout [Node], hoisting hoist: inout [AnchoredRelationship]) {
            var i = 0
            while i < arr.count {
                if sel.contains(arr[i].id), case .group(let kids) = arr[i].content {
                    hoist.append(contentsOf: arr[i].anchoredRelationships)
                    let o = arr[i].frame.origin
                    let inheritedOwner = arr[i].artboardID
                    let rebased = kids.map { k -> Node in
                        var c = k
                        c.frame = c.frame.offsetBy(dx: o.x, dy: o.y)
                        c.artboardID = inheritedOwner
                        return c
                    }
                    arr.replaceSubrange(i...i, with: rebased)
                    rebased.forEach { freed.insert($0.id) }
                    i += rebased.count
                } else {
                    if case .group(var kids) = arr[i].content {
                        var inner: [AnchoredRelationship] = []
                        process(&kids, hoisting: &inner)
                        arr[i].content = .group(children: kids)
                        // This group survives and still contains both ends, so it
                        // becomes the new anchor for anything freed beneath it.
                        arr[i].anchoredRelationships.append(contentsOf: inner)
                    }
                    i += 1
                }
            }
        }
        var nodes = currentNodes
        var hoistedToRoot: [AnchoredRelationship] = []
        process(&nodes, hoisting: &hoistedToRoot)
        guard !freed.isEmpty else { return }
        commitNodes(nodes, actionName: "Ungroup",
                    appendingRootAnchors: hoistedToRoot)
        app.selectedNodeIDs = freed
        needsDisplay = true
    }

    // MARK: Mask

    /// Wrap the selection into a non-destructive mask: the TOPMOST selected node
    /// becomes the clip shape (`isMaskShape`), the rest become masked content. The
    /// container is a `.group` flagged `isMask`, so it reuses all group machinery
    /// (enter-to-edit, drag-in, layers, copy/paste). Mirrors `group()`.
    private func maskWithTopShape() {
        guard let app, app.selectedNodeIDs.count >= 2 else { return }
        let ids = app.selectedNodeIDs
        var nodes = currentNodes
        var newGroupID: UUID?

        func wrap(_ selected: [Node]) -> Node {
            let topID = selected.last!.id          // drawn last = topmost = the mask
            let inheritedOwners = Set(selected.compactMap(\.artboardID))
            let frames = selected.map(\.frame)
            let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
            let children = selected.map { n -> Node in
                var c = n
                c.frame = c.frame.offsetBy(dx: -union.minX, dy: -union.minY)
                c.artboardID = nil
                c.isMaskShape = (n.id == topID)
                return c
            }
            var g = Node(name: "Mask", frame: union,
                         artboardID: inheritedOwners.count == 1 ? inheritedOwners.first : nil,
                         content: .group(children: children))
            g.isMask = true
            return g
        }
        func maskInPlace(_ arr: inout [Node]) {
            let selected = arr.filter { ids.contains($0.id) }
            guard selected.count >= 2 else { return }
            arr.removeAll { ids.contains($0.id) }
            let g = wrap(selected)
            arr.append(g)
            newGroupID = g.id
        }

        let parents = Set(ids.map { parentGroupID(of: $0) })
        if parents.count == 1, let parent = parents.first {
            if let pid = parent {
                Self.mutateNested(pid, in: &nodes) { g in
                    guard case .group(var kids) = g.content else { return }
                    maskInPlace(&kids)
                    g.content = .group(children: kids)
                }
            } else {
                maskInPlace(&nodes)
            }
        } else {
            let selected = collectSelectedNodes()
            guard selected.count >= 2 else { return }
            Self.removeNested(ids, from: &nodes)
            let g = wrap(selected)
            nodes.append(g)
            newGroupID = g.id
        }

        guard let gid = newGroupID else { return }
        commitNodes(nodes, actionName: "Mask with Top Shape")
        app.selectedNodeIDs = [gid]
        app.selectedArtboardID = nil
        needsDisplay = true
    }

    /// Turn a selected mask back into an ordinary group (clears the mask flags;
    /// content stops clipping and the mask shape draws normally again).
    private func releaseMask() {
        guard let app else { return }
        let sel = app.selectedNodeIDs
        var nodes = currentNodes
        var changed = false
        func process(_ arr: inout [Node]) {
            for i in arr.indices {
                if sel.contains(arr[i].id), arr[i].isMask {
                    arr[i].isMask = false
                    if case .group(var kids) = arr[i].content {
                        for j in kids.indices { kids[j].isMaskShape = false }
                        arr[i].content = .group(children: kids)
                    }
                    changed = true
                }
                if case .group(var kids) = arr[i].content {
                    process(&kids)
                    arr[i].content = .group(children: kids)
                }
            }
        }
        process(&nodes)
        guard changed else { return }
        commitNodes(nodes, actionName: "Release Mask")
        needsDisplay = true
    }

    /// True when the selection contains at least one mask group (for menu validation).
    private func selectionHasMask() -> Bool {
        guard let app else { return false }
        let sel = app.selectedNodeIDs
        var found = false
        func scan(_ nodes: [Node]) {
            for n in nodes {
                if sel.contains(n.id), n.isMask { found = true; return }
                if case .group(let k) = n.content { scan(k) }
            }
        }
        scan(currentNodes)
        return found
    }

    // MARK: Eyedropper

    /// Sample a color from anywhere on screen (system loupe) and apply it to the
    /// selection: fill for shapes/paths, stroke for a line (its fill-equivalent),
    /// text color for text, and the frame background for an auto-padding group.
    /// Triggered by `i` with a selection; one undo step. No-op if nothing selected.
    private func eyedropToSelection() {
        guard let app, !app.selectedNodeIDs.isEmpty else { return }
        let ids = app.selectedNodeIDs
        NSColorSampler().show { [weak self] picked in
            guard let self, let ns = picked?.usingColorSpace(.sRGB) else { return }   // nil = cancelled
            let rgba = RGBAColor(r: Double(ns.redComponent), g: Double(ns.greenComponent),
                                 b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
            let paint = Paint.solid(rgba)
            var nodes = self.currentNodes
            for id in ids {
                _ = Self.mutateNested(id, in: &nodes) { node in
                    switch node.content {
                    case .rectangle(var s): s.fill = paint; node.content = .rectangle(s)
                    case .ellipse(var s):   s.fill = paint; node.content = .ellipse(s)
                    case .polygon(var s):   s.fill = paint; node.content = .polygon(s)
                    case .path(var s):      s.fill = paint; node.content = .path(s)
                    case .line(var s):      s.stroke = rgba; node.content = .line(s)
                    case .text(var t):      t.applyToAllRuns { $0.color = rgba }; node.content = .text(t)
                    case .group:            if node.autoPadding != nil { node.autoPadding?.fill = paint }
                    default: break
                    }
                }
            }
            self.commitNodes(nodes, actionName: "Eyedropper Fill")
            self.needsDisplay = true
        }
    }

    // MARK: Components

    /// Context-menu placement carries the click location; the Object menu and
    /// Components panel carry only the source id and therefore place at the
    /// visible canvas centre.
    private final class ComponentPlacementRequest: NSObject {
        let sourceID: UUID
        let viewPoint: CGPoint?
        init(sourceID: UUID, viewPoint: CGPoint? = nil) {
            self.sourceID = sourceID
            self.viewPoint = viewPoint
        }
    }

    @objc func placeComponentAction(_ sender: Any?) {
        let request = (sender as? NSMenuItem)?.representedObject
        let sourceID: UUID?
        let point: CGPoint?
        if let request = request as? ComponentPlacementRequest {
            sourceID = request.sourceID
            point = request.viewPoint
        } else if let id = request as? UUID {
            sourceID = id
            point = nil
        } else if let string = request as? String {
            sourceID = UUID(uuidString: string)
            point = nil
        } else if let string = request as? NSString {
            sourceID = UUID(uuidString: string as String)
            point = nil
        } else {
            sourceID = nil
            point = nil
        }
        guard let sourceID else { return }
        _ = placeComponentInstance(sourceID,
                                   at: point ?? CGPoint(x: bounds.midX, y: bounds.midY))
    }

    @objc func createComponentAction(_ sender: Any?) { createComponent() }

    /// Turn the selected nodes into a reusable component source, and replace the
    /// selection with a single instance referencing it. The source's children are
    /// stored source-local (relative to the selection's bounding box).
    private func createComponent() {
        guard let app, let document else { return }
        let selected = currentNodes.filter { app.selectedNodeIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        let frames = selected.map(\.frame)
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let children = selected.map { node -> Node in
            var c = node
            c.frame = c.frame.offsetBy(dx: -union.minX, dy: -union.minY)
            return c
        }
        // Name the component after the selection when it's a single (named) layer —
        // typically a group the user just named — so "Button" → component "Button".
        // Falls back to the auto number for a multi-shape selection.
        let baseName: String = {
            if selected.count == 1 {
                let n = selected[0].name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { return n }
            }
            return "Component \(document.model.sources.count + 1)"
        }()
        let source = ComponentSource(name: baseName,
                                     size: union.size, children: children)
        let instance = Node(name: "Instance", frame: union,
                            content: .instance(ComponentInstance(sourceID: source.id)))

        // Mutate the whole model: add the source (document-level) and swap the
        // selection for the instance within the CURRENT scope's node list.
        var model = document.model
        model.sources.append(source)
        let selectedIDs = app.selectedNodeIDs
        switch scope {
        case .document:
            guard let pageIndex = model.pageIndex(for: activePageID) else { return }
            model.pages[pageIndex].nodes.removeAll { selectedIDs.contains($0.id) }
            model.pages[pageIndex].nodes.append(instance)
        case .source(let sid):
            if let si = model.sources.firstIndex(where: { $0.id == sid }) {
                model.sources[si].children.removeAll { selectedIDs.contains($0.id) }
                model.sources[si].children.append(instance)
            }
        }
        document.setModel(model, undoManager: undoManager, actionName: "Create Component")
        app.selectedNodeIDs = [instance.id]
        app.selectedArtboardID = nil
        needsDisplay = true
    }

    /// The component TOOL: make an EMPTY component source and open its editor so
    /// the user can build it from scratch (vs. `createComponentAction`, which wraps
    /// a selection). No instance is placed; instances come from the Components panel.
    @objc func newEmptyComponentAction(_ sender: Any?) {
        guard let document else { return }
        let source = ComponentSource(name: "Component \(document.model.sources.count + 1)",
                                     size: CGSize(width: 200, height: 200), children: [])
        var model = document.model
        model.sources.append(source)
        document.setModel(model, undoManager: undoManager, actionName: "New Component")
        openSourceEditor(source.id)
    }

    // MARK: Component categories (Phase 19a — ARIA-role organizing)

    /// The component source the category commands act on: the source being
    /// edited in a source-editor window, else the source of the first selected
    /// instance in the document.
    private var categoryTargetSourceID: UUID? {
        if case .source(let sid) = scope { return sid }
        guard let app else { return nil }
        for n in currentNodes where app.selectedNodeIDs.contains(n.id) {
            if case .instance(let inst) = n.content { return inst.sourceID }
        }
        return nil
    }

    /// Which source a category menu item writes to, and what it writes. Carrying
    /// the source id on the item is what makes NESTED authoring possible: inside
    /// a source editor, right-clicking a nested instance must categorise THAT
    /// component, not the source being edited.
    final class ComponentCategoryRequest: NSObject {
        let sourceID: UUID
        let role: AriaRole?
        init(sourceID: UUID, role: AriaRole?) {
            self.sourceID = sourceID
            self.role = role
        }
    }

    /// Single source of truth for assigning a component category. The sender's
    /// representedObject carries a `ComponentCategoryRequest`; the legacy plain
    /// ARIA-token form still resolves against the ambient target so older menu
    /// builders keep working. The UI always shows the friendly label, the model
    /// always stores the token.
    @objc func setComponentCategoryAction(_ sender: NSMenuItem) {
        guard let document else { return }
        let target: UUID?
        let role: AriaRole?
        if let request = sender.representedObject as? ComponentCategoryRequest {
            target = request.sourceID
            role = request.role
        } else {
            target = categoryTargetSourceID
            role = (sender.representedObject as? String).flatMap(AriaRole.init(rawValue:))
        }
        guard let sid = target,
              let si = document.model.sources.firstIndex(where: { $0.id == sid }) else { return }
        var model = document.model
        guard model.sources[si].a11y.role != role else { return }
        model.sources[si].a11y.role = role
        document.setModel(model, undoManager: undoManager, actionName: "Set Component Category")
    }

    /// The role of the component this canvas is editing, if any — the parent
    /// half of a semantic-containment question.
    private var editingSourceRole: AriaRole? {
        guard case .source(let sid) = scope else { return nil }
        return document?.model.source(for: sid)?.a11y.role
    }

    /// "Set Category" submenu for the right-click menu: friendly labels grouped
    /// by ARIA category, checkmark on the current choice, "Uncategorized" on top.
    private func categoryMenuItem(for sourceID: UUID) -> NSMenuItem {
        let current = document?.model.sources.first { $0.id == sourceID }?.a11y.role
        // Semantic containment (Chunk I): when this component sits inside another
        // component with ownership expectations, promote the roles that fit and
        // say why. The full list still follows — a recommendation shortens the
        // path to the right answer, it never removes a legitimate choice.
        let advice = document?.model.containmentAdvice(forChildRole: current,
                                                       inParentRole: editingSourceRole)
        let item = NSMenuItem(title: "Set Category", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        func add(_ role: AriaRole?, indented: Bool) {
            let entry = NSMenuItem(title: role?.friendlyLabel ?? "Uncategorized",
                                   action: #selector(setComponentCategoryAction(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.representedObject = ComponentCategoryRequest(sourceID: sourceID, role: role)
            entry.state = current == role ? .on : .off
            entry.toolTip = role?.blurb
            if indented { entry.indentationLevel = 1 }
            sub.addItem(entry)
        }

        if let advice {
            // A disabled first line explains the situation in plain language.
            // Warnings are marked as such; suggestions must not read as errors.
            let header = NSMenuItem(
                title: (advice.isWarning ? "\u{26A0}\u{FE0F} " : "") + advice.message,
                action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)
            if !advice.recommended.isEmpty {
                sub.addItem(.separator())
                let label = NSMenuItem(title: "Recommended here", action: nil, keyEquivalent: "")
                label.isEnabled = false
                sub.addItem(label)
                for role in advice.recommended { add(role, indented: true) }
            }
            sub.addItem(.separator())
        }

        add(nil, indented: false)
        for group in AriaRole.grouped() {
            sub.addItem(.separator())
            let header = NSMenuItem(title: group.category.label, action: nil, keyEquivalent: "")
            header.isEnabled = false   // section label, not a choice
            sub.addItem(header)
            for role in group.roles { add(role, indented: true) }
        }
        item.submenu = sub
        return item
    }

    @objc func editComponentAction(_ sender: Any?) {
        guard let app, let id = app.selectedNodeIDs.first, let node = node(id),
              case .instance(let inst) = node.content else { return }
        openSourceEditor(inst.sourceID)
    }

    @objc func detachComponentAction(_ sender: Any?) { detachSelectedInstances() }

    /// The component source carried by a panel/menu item, the source currently
    /// being edited, or the source behind the selected instance (in that order).
    /// Source-level commands share this resolver so panel, canvas, and Object-menu
    /// actions always target the same definition.
    private func componentSourceTarget(for sender: Any?) -> UUID? {
        if let item = sender as? NSMenuItem {
            if let id = item.representedObject as? UUID { return id }
            if let string = item.representedObject as? String,
               let id = UUID(uuidString: string) { return id }
            if let string = item.representedObject as? NSString,
               let id = UUID(uuidString: string as String) { return id }
        }
        if case .source(let sourceID) = scope { return sourceID }
        if let app, let id = app.selectedNodeIDs.first, let node = node(id),
           case .instance(let inst) = node.content { return inst.sourceID }
        return nil
    }

    /// Make a new, independent component SOURCE. This is intentionally different
    /// from duplicating a selected instance/layer: existing instances keep pointing
    /// at the original source, and the copy opens as its own working component.
    @objc func duplicateComponentSourceAction(_ sender: Any?) {
        guard let document,
              let sourceID = componentSourceTarget(for: sender),
              let duplicated = document.model.duplicatingComponentSource(sourceID)
        else { return }
        document.setModel(duplicated.document, undoManager: undoManager,
                          actionName: "Duplicate Component")
        openSourceEditor(duplicated.sourceID)
        needsDisplay = true
    }

    /// The component source a Delete Component command would remove: the id
    /// carried by the menu item when a Components panel raised it, otherwise the
    /// source behind the selected instance. Menu validation and the action share
    /// this so an enabled item always deletes what its title names.
    func deleteComponentTarget(for sender: Any?) -> UUID? {
        componentSourceTarget(for: sender)
    }

    /// Delete the component SOURCE behind the selection. Deliberately distinct
    /// from deleting the selected layer: the source and its definition go away,
    /// but no work is lost — every instance of it, here and inside other
    /// sources, becomes an ordinary group of the layers it was drawing.
    @objc func deleteComponentSourceAction(_ sender: Any?) {
        guard let document, let sourceID = deleteComponentTarget(for: sender),
              document.model.source(for: sourceID) != nil else { return }
        document.setModel(document.model.deletingComponentSource(sourceID),
                          undoManager: undoManager,
                          actionName: "Delete Component")
        // A source editor open on the deleted source would be editing something
        // the document no longer has. Close it rather than leave a ghost window.
        SourceEditorWindowManager.shared.close(sourceID: sourceID)
        needsDisplay = true
    }

    /// Add the next likely component state from the Object menu / shortcut.
    /// Source-editor only: state editing belongs to the source, not placed
    /// instances in the document canvas.
    @objc func addComponentStateAction(_ sender: Any?) {
        guard let app, let document, case .source(let sid) = scope,
              let si = document.model.sources.firstIndex(where: { $0.id == sid }) else { return }
        let name = Self.nextComponentStateName(existing: document.model.sources[si].states.map(\.name))
        let state = ComponentState(name: name)
        var model = document.model
        model.sources[si].states.append(state)
        document.setModel(model, undoManager: undoManager, actionName: "Add Component State")
        app.activeComponentStateID = state.id
        needsDisplay = true
    }

    @objc func nextComponentStateAction(_ sender: Any?) {
        cycleComponentState(forward: true)
    }

    @objc func previousComponentStateAction(_ sender: Any?) {
        cycleComponentState(forward: false)
    }

    private static func nextComponentStateName(existing: [String]) -> String {
        let lowered = Set(existing.map { $0.lowercased() })
        if let conventional = ComponentState.conventionalNames.first(where: { !lowered.contains($0.lowercased()) }) {
            return conventional
        }
        var index = existing.count + 1
        while lowered.contains("state \(index)") { index += 1 }
        return "state \(index)"
    }

    private func cycleComponentState(forward: Bool) {
        guard let app, let document, case .source(let sid) = scope,
              let source = document.model.source(for: sid),
              !source.states.isEmpty else { return }
        let ids: [UUID?] = [nil] + source.states.map { Optional($0.id) }
        let current = ids.firstIndex { $0 == app.activeComponentStateID } ?? 0
        let delta = forward ? 1 : -1
        let next = (current + delta + ids.count) % ids.count
        app.activeComponentStateID = ids[next]
        needsDisplay = true
    }

    /// True if any selected node is an instance (for menu validation).
    private var selectionHasInstance: Bool {
        guard let app else { return false }
        return currentNodes.contains {
            if app.selectedNodeIDs.contains($0.id), case .instance = $0.content { return true }
            return false
        }
    }

    /// Convert selected instance(s) back into independent layers: replace each
    /// instance with fresh copies of its source's children (placed at the
    /// instance's position). The source definition is left intact for other
    /// instances. Per-instance hidden layers carry over as `isVisible = false`.
    private func detachSelectedInstances() {
        guard let app, let document else { return }
        let ids = app.selectedNodeIDs
        var result: [Node] = []
        var newSelection = Set<UUID>()
        var didDetach = false
        for node in currentNodes {
            if ids.contains(node.id), case .instance(let inst) = node.content {
                didDetach = true
                // Bake the fully-resolved instance (overrides + visibility + auto
                // layout) into independent nodes — exactly what was on screen.
                for child in document.model.resolvedChildren(of: inst) {
                    var copy = cloned(child)
                    copy.frame = copy.frame.offsetBy(dx: node.frame.minX, dy: node.frame.minY)
                    result.append(copy)
                    newSelection.insert(copy.id)
                }
            } else {
                result.append(node)
            }
        }
        guard didDetach else { return }
        commitNodes(result, actionName: "Detach Component")
        app.selectedNodeIDs = newSelection
        needsDisplay = true
    }

    private func openSourceEditor(_ sourceID: UUID) {
        guard let document else { return }
        SourceEditorWindowManager.shared.open(sourceID: sourceID, document: document, undoManager: undoManager)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()

        // Right-click anywhere on the gradient line → a gradient menu (FEAT-045).
        // First, like the path-anchor case below, because it is chrome sitting on top
        // of the shape. The BARE LINE gets a menu too, not just the stops: paste puts
        // a stop where the pointer is, so the empty stretches have to be reachable or
        // there is nowhere to paste into.
        if let g = hitTestGradientHandle(atViewPoint: p) {
            var stopID: UUID? = nil
            var t: CGFloat = 0
            switch g.hit {
            case .stop(let id):
                stopID = id
                t = CGFloat(gradientStop(nodeID: g.id, stopID: id)?.position ?? 0)
            case .line(let hitT):
                t = hitT
            case .start, .end:
                return super.menu(for: event)   // the ends are not stops; no menu of their own
            }
            pendingGradientMenu = (g.id, stopID, t)
            if let stopID { app?.selectedGradientStopID = stopID; needsDisplay = true }

            let canPaste = app?.copiedGradientStop != nil
            func item(_ title: String, _ action: Selector, enabled: Bool = true) {
                let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
                mi.target = self
                mi.isEnabled = enabled
                menu.addItem(mi)
            }
            if stopID != nil {
                item("Edit Stop…", #selector(editGradientStopAction(_:)))
                menu.addItem(.separator())
                item("Add Color to Design Language",
                     #selector(addGradientStopColorToDesignLanguageAction(_:)))
                item("Copy Stop", #selector(copyGradientStopAction(_:)))
                item("Paste Stop Here", #selector(pasteGradientStopAction(_:)), enabled: canPaste)
                menu.addItem(.separator())
                let canDelete = (node(g.id).flatMap { linearGradientFill(of: $0) }?.stops.count ?? 0) > 2
                item("Delete Stop", #selector(deleteGradientStopAction(_:)), enabled: canDelete)
            } else {
                item("Add Stop Here", #selector(addGradientStopHereAction(_:)))
                item("Paste Stop Here", #selector(pasteGradientStopAction(_:)), enabled: canPaste)
            }
            return menu
        }

        // Right-click directly on a path anchor → corner/curve toggle.
        if let pt = hitTestPathPoint(atViewPoint: p), case .anchor(let c, let i) = pt.target,
           let n = node(pt.id), case .path(let ps) = n.content, let anchor = ps.editPoint(contour: c, index: i) {
            pendingCurveToggle = (pt.id, c, i)
            let curved = anchor.controlIn != nil || anchor.controlOut != nil
            add(menu, curved ? "Make Corner" : "Make Curved", #selector(togglePointCurveAction(_:)))
            return menu
        }

        // Target the node the menu acts on: if a currently-selected node is under the
        // cursor (e.g. a drilled-in child of a group), keep it; otherwise select the
        // top-level node. This stops a right-click on a nested item from jumping focus
        // out to its parent group.
        // Normal canvas picking skips locked nodes so they never block work behind
        // them. A context-click is the deliberate exception: it must be able to
        // target a locked object in order to offer the escape hatch, Unlock.
        let clickPath = hitPath(atDoc: viewToDoc(p), includingLocked: true)
        if let hitID = clickPath.first(where: { app?.selectedNodeIDs.contains($0.id) == true })?.id
                    ?? clickPath.first?.id,
           let hit = node(hitID) {
            if !(app?.selectedNodeIDs.contains(hitID) ?? false) {
                app?.selectedNodeIDs = [hitID]
                app?.selectedArtboardID = nil
                needsDisplay = true
            }
            if hit.isLocked {
                add(menu, "Reveal in Layers", #selector(revealSelectionInLayersAction(_:)))
                menu.addItem(.separator())
                add(menu, "Unlock", #selector(unlockSelection(_:)))
                return menu
            }
            add(menu, "Cut", #selector(cut(_:)))
            add(menu, "Copy", #selector(copy(_:)))
            add(menu, "Duplicate", #selector(duplicateSelection(_:)))
            if let move = pageTransferMenuItem(title: "Move to Page", duplicate: false) { menu.addItem(move) }
            if let copy = pageTransferMenuItem(title: "Duplicate to Page", duplicate: true) { menu.addItem(copy) }
            add(menu, "Delete", #selector(delete(_:)))
            add(menu, "Reveal in Layers", #selector(revealSelectionInLayersAction(_:)))
            menu.addItem(.separator())
            // Copy / Paste Style (effects + blend mode + opacity). Both always
            // appear; validateMenuItem greys out Paste Style until a style is copied.
            add(menu, "Copy Style", #selector(copyLayerStyle(_:)))
            add(menu, "Paste Style", #selector(pasteLayerStyle(_:)))
            menu.addItem(.separator())
            // Lock / Unlock — show whichever applies to the current selection.
            if anySelected({ !$0.isLocked }) { add(menu, "Lock", #selector(lockSelection(_:))) }
            if anySelected({ $0.isLocked })  { add(menu, "Unlock", #selector(unlockSelection(_:))) }
            menu.addItem(.separator())
            add(menu, "Group", #selector(groupSelection(_:)))
            add(menu, "Ungroup", #selector(ungroupSelection(_:)))
            if (app?.selectedNodeIDs.count ?? 0) >= 2 {
                add(menu, "Mask with Top Shape", #selector(maskWithTopShapeAction(_:)))
            }
            if selectionHasMask() {
                add(menu, "Release Mask", #selector(releaseMaskAction(_:)))
            }
            // Titles are replaced contextually (Add/Remove) by validateMenuItem.
            add(menu, "Auto Layout", #selector(toggleAutoLayoutAction(_:)))
            add(menu, "Auto Padding", #selector(toggleAutoPaddingAction(_:)))
            if selectedItemInAutoLayout {
                add(menu, "Move Item Forward", #selector(nudgeItemForwardAction(_:)))
                add(menu, "Move Item Backward", #selector(nudgeItemBackwardAction(_:)))
            }
            if canEditRelationships {
                add(menu, "Relationships…", #selector(showRelationshipsAction(_:)))
            }
            add(menu, "Create Component", #selector(createComponentAction(_:)))
            if let placeItem = componentPlacementMenuItem(at: p) {
                menu.addItem(placeItem)
            }
            if case .instance(let inst) = hit.content {
                add(menu, "Edit Component", #selector(editComponentAction(_:)))
                add(menu, "Duplicate Component", #selector(duplicateComponentSourceAction(_:)))
                add(menu, "Detach Component", #selector(detachComponentAction(_:)))
                add(menu, "Delete Component", #selector(deleteComponentSourceAction(_:)))
                menu.addItem(categoryMenuItem(for: inst.sourceID))
                menu.addItem(instanceStateMenuItem(forNode: hit.id, sourceID: inst.sourceID,
                                                   current: inst.activeStateID))
            }
            if selectionConvertibleToPath {
                add(menu, "Convert to Path", #selector(convertToPathAction(_:)))
            }
            if selectionCanConvertTextToOutlines {
                add(menu, "Convert to Outlines", #selector(convertTextToShapesAction(_:)))
            }
            switch hit.content {
            case .text:
                add(menu, "Save as Type Style", #selector(saveTypeStyleAction(_:)))
                let roleItem = NSMenuItem(title: "Content Role", action: nil, keyEquivalent: "")
                let roleMenu = NSMenu()
                let currentRole: TextContentRole = {
                    guard case .text(let text) = hit.content else { return .plain }
                    return text.contentRole
                }()
                for role in TextContentRole.allCases {
                    let item = NSMenuItem(title: role.friendlyLabel,
                                          action: #selector(setTextContentRoleAction(_:)),
                                          keyEquivalent: "")
                    item.target = self
                    item.representedObject = role.rawValue
                    item.state = role == currentRole ? .on : .off
                    roleMenu.addItem(item)
                }
                roleItem.submenu = roleMenu
                menu.addItem(roleItem)
                if let styles = document?.model.designLanguage.typeStyles, !styles.isEmpty {
                    let styleItem = NSMenuItem(title: "Apply Type Style", action: nil, keyEquivalent: "")
                    let sub = NSMenu()
                    for s in styles {
                        let it = NSMenuItem(title: s.name.isEmpty ? s.fallbackLabel : s.name,
                                            action: #selector(applyTypeStyleMenuAction(_:)),
                                            keyEquivalent: "")
                        it.target = self
                        it.representedObject = s.id
                        sub.addItem(it)
                    }
                    styleItem.submenu = sub
                    menu.addItem(styleItem)
                }
            default: break
            }
            if selectionCanOutlineStroke {
                add(menu, "Outline Stroke", #selector(outlineStrokeAction(_:)))
            }
            if selectionCanPathfinder {
                let pathfinder = NSMenuItem(title: "Pathfinder", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                add(sub, "Unite", #selector(pathfinderUniteAction(_:)))
                add(sub, "Subtract Front", #selector(pathfinderSubtractAction(_:)))
                add(sub, "Intersect", #selector(pathfinderIntersectAction(_:)))
                add(sub, "Exclude Overlap", #selector(pathfinderExcludeAction(_:)))
                pathfinder.submenu = sub
                menu.addItem(pathfinder)
            }
            menu.addItem(.separator())
            add(menu, "Bring Forward", #selector(bringForward(_:)))
            add(menu, "Send Backward", #selector(sendBackward(_:)))
            add(menu, "Bring to Front", #selector(bringToFront(_:)))
            add(menu, "Send to Back", #selector(sendToBack(_:)))
            menu.addItem(.separator())
            add(menu, "Flip Horizontal", #selector(flipHorizontalAction(_:)))
            add(menu, "Flip Vertical", #selector(flipVerticalAction(_:)))
            add(menu, "Round to Pixel", #selector(roundToPixelAction(_:)))
            menu.addItem(.separator())
            add(menu, "Eyedropper (Pick Fill)", #selector(eyedropperAction(_:)))
            if (app?.selectedNodeIDs.count ?? 0) >= 2 {
                menu.addItem(.separator())
                let alignItem = NSMenuItem(title: "Align & Distribute", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                add(sub, "Align Left", #selector(alignLeftAction(_:)))
                add(sub, "Align Horizontal Centers", #selector(alignHCenterAction(_:)))
                add(sub, "Align Right", #selector(alignRightAction(_:)))
                add(sub, "Align Top", #selector(alignTopAction(_:)))
                add(sub, "Align Vertical Centers", #selector(alignVCenterAction(_:)))
                add(sub, "Align Bottom", #selector(alignBottomAction(_:)))
                sub.addItem(.separator())
                add(sub, "Distribute Horizontally", #selector(distributeHorizontallyAction(_:)))
                add(sub, "Distribute Vertically", #selector(distributeVerticallyAction(_:)))
                alignItem.submenu = sub
                menu.addItem(alignItem)
            }
        } else if let board = hitTestArtboard(atViewPoint: p) {
            // Right-clicking a board selects it (unless already in a board set).
            if !(app?.selectedArtboardIDs.contains(board.id) ?? false) {
                app?.selectedArtboardIDs = [board.id]
                app?.selectedNodeIDs = []
                needsDisplay = true
            }
            add(menu, "Rename", #selector(renameArtboardAction(_:)))
            add(menu, "Center in View", #selector(centerSelectionAction(_:)))
            add(menu, "Round to Pixel", #selector(roundToPixelAction(_:)))
            if (app?.selectedArtboardIDs.count ?? 0) >= 2 {
                menu.addItem(.separator())
                let arrangeItem = NSMenuItem(title: "Align & Distribute", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                add(sub, "Align Left", #selector(alignLeftAction(_:)))
                add(sub, "Align Horizontal Centers", #selector(alignHCenterAction(_:)))
                add(sub, "Align Right", #selector(alignRightAction(_:)))
                add(sub, "Align Top", #selector(alignTopAction(_:)))
                add(sub, "Align Vertical Centers", #selector(alignVCenterAction(_:)))
                add(sub, "Align Bottom", #selector(alignBottomAction(_:)))
                sub.addItem(.separator())
                add(sub, "Distribute Horizontally", #selector(distributeHorizontallyAction(_:)))
                add(sub, "Distribute Vertically", #selector(distributeVerticallyAction(_:)))
                arrangeItem.submenu = sub
                menu.addItem(arrangeItem)
                add(menu, "Clean Up", #selector(cleanUpArtboardsAction(_:)))
            }
            menu.addItem(.separator())
            add(menu, "Cut", #selector(cut(_:)))
            add(menu, "Copy", #selector(copy(_:)))
            add(menu, "Paste", #selector(paste(_:)))
            add(menu, "Duplicate", #selector(duplicateArtboardsAction(_:)))
            if let move = pageTransferMenuItem(title: "Move to Page", duplicate: false) { menu.addItem(move) }
            if let copy = pageTransferMenuItem(title: "Duplicate to Page", duplicate: true) { menu.addItem(copy) }
            add(menu, "Delete", #selector(delete(_:)))
            if let placeItem = componentPlacementMenuItem(at: p) {
                menu.addItem(.separator())
                menu.addItem(placeItem)
            }
        } else {
            add(menu, "Paste", #selector(paste(_:)))
            if let placeItem = componentPlacementMenuItem(at: p) {
                menu.addItem(placeItem)
            }
            add(menu, "Fit to Screen", #selector(fitToScreen(_:)))
        }
        return menu
    }

    private func pageTransferMenuItem(title: String, duplicate: Bool) -> NSMenuItem? {
        guard let document, let active = activePageID else { return nil }
        let destinations = document.model.pages.filter { $0.id != active }
        guard !destinations.isEmpty else { return nil }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for page in destinations {
            let item = NSMenuItem(
                title: page.name,
                action: duplicate
                    ? #selector(duplicateSelectionToPageAction(_:))
                    : #selector(moveSelectionToPageAction(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = CanvasPageTransferRequest(
                pageID: page.id,
                nodeIDs: app?.selectedNodeIDs ?? [],
                artboardIDs: app?.selectedArtboardIDs ?? [])
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    /// A selection-independent placement path for the canvas context menu. Only
    /// graph-safe choices are shown while editing a component source, so keyboard
    /// and VoiceOver users encounter the same constraint as drag/drop users.
    private func componentPlacementMenuItem(at point: CGPoint) -> NSMenuItem? {
        guard let document else { return nil }
        let sources = document.model.sources
            .filter { canPlaceComponent($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !sources.isEmpty else { return nil }

        let parent = NSMenuItem(title: "Place Component Instance", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for source in sources {
            let item = NSMenuItem(title: source.name,
                                  action: #selector(placeComponentAction(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = ComponentPlacementRequest(sourceID: source.id,
                                                                viewPoint: point)
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
}

// MARK: - Inline text editing delegate

extension CanvasNSView: NSTextViewDelegate {
    // NOTE: we deliberately do NOT commit on `textDidEndEditing`. Clicking an
    // Inspector control resigns the text view's first responder; committing there
    // would end editing and drop the selection before the style change applies.
    // The editor keeps its selection while you use the Inspector; we commit on an
    // explicit trigger instead (canvas click outside the box, Escape, or selecting
    // a different node — see mouseDown / keyDown / updateNSView).
    func textViewDidChangeSelection(_ notification: Notification) {
        // Only record the selection while the editor is actually focused. When it
        // resigns (e.g. the user clicks an Inspector field) AppKit collapses the
        // selection; ignoring that keeps the real selection for the Inspector op.
        if let tv = textEditor, window?.firstResponder === tv {
            editorSelectedRange = tv.selectedRange()
        }
        publishTextSelection()
    }
    func textDidChange(_ notification: Notification) {
        captureTextEditSnapshot()
        publishTextSelection()
    }
    /// Escape ends editing but KEEPS the text node selected (commitTextEditing
    /// re-selects it + restores canvas first responder), so it can be moved right
    /// away without re-clicking. Return true so the key isn't beeped/inserted.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            commitTextEditing()
            return true
        }
        return false
    }
}

// MARK: - Artboard rename field delegate

extension CanvasNSView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        commitArtboardRename()
    }
}

// MARK: - Menu validation

extension CanvasNSView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasNodes = !(app?.selectedNodeIDs.isEmpty ?? true)
        let hasArtboards = !(app?.selectedArtboardIDs.isEmpty ?? true)
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return hasNodes || hasArtboards
        case #selector(lockSelection(_:)):
            return anySelected { !$0.isLocked }
        case #selector(unlockSelection(_:)):
            return anySelected { $0.isLocked }
        case #selector(duplicateSelection(_:)), #selector(bringToFront(_:)),
             #selector(sendToBack(_:)), #selector(bringForward(_:)), #selector(sendBackward(_:)),
             #selector(createComponentAction(_:)),
             #selector(flipHorizontalAction(_:)), #selector(flipVerticalAction(_:)),
             #selector(copyLayerStyle(_:)):
            return hasNodes
        case #selector(duplicateSelectedEffectAction(_:)):
            guard let nodeID = app?.singleSelectedNodeID,
                  let effectID = app?.selectedEffectID else { return false }
            return node(nodeID)?.effects.contains(where: { $0.id == effectID }) == true
        case #selector(groupSelection(_:)):
            return (app?.selectedNodeIDs.count ?? 0) >= 2
        case #selector(pasteLayerStyle(_:)):
            return hasNodes && (app?.copiedLayerStyle != nil)
        case #selector(duplicateArtboardsAction(_:)), #selector(renameArtboardAction(_:)):
            return hasArtboards
        case #selector(moveSelectionToPageAction(_:)), #selector(duplicateSelectionToPageAction(_:)):
            guard let request = pageTransferRequest(from: item) else { return false }
            let requestHasSelection = !(request.nodeIDs ?? app?.selectedNodeIDs ?? []).isEmpty
                || !(request.artboardIDs ?? app?.selectedArtboardIDs ?? []).isEmpty
            return requestHasSelection
                && request.pageID != activePageID
                && document?.model.pages.contains(where: { $0.id == request.pageID }) == true
        case #selector(ungroupSelection(_:)):
            return selectionHasGroup
        case #selector(maskWithTopShapeAction(_:)):
            return (app?.selectedNodeIDs.count ?? 0) >= 2
        case #selector(releaseMaskAction(_:)):
            return selectionHasMask()
        case #selector(eyedropperAction(_:)):
            return hasNodes
        case #selector(expandAllLayersAction(_:)), #selector(collapseAllLayersAction(_:)):
            return isSourceScope || app?.isPanelShown(.layers) == true
        case #selector(revealSelectionInLayersAction(_:)):
            return hasNodes
        case #selector(showRelationshipsAction(_:)):
            return canEditRelationships
        case #selector(toggleAutoLayoutAction(_:)):
            // Title flips to reflect what the command will do to the selection.
            item.title = selectedGroupHasAutoLayout ? "Remove Auto Layout" : "Add Auto Layout"
            return hasNodes
        case #selector(toggleAutoPaddingAction(_:)):
            item.title = selectedGroupHasAutoPadding ? "Remove Auto Padding" : "Add Auto Padding"
            return hasNodes
        case #selector(nudgeItemForwardAction(_:)), #selector(nudgeItemBackwardAction(_:)):
            return selectedItemInAutoLayout
        case #selector(editComponentAction(_:)), #selector(detachComponentAction(_:)):
            return selectionHasInstance
        case #selector(duplicateComponentSourceAction(_:)):
            guard let sourceID = componentSourceTarget(for: item) else { return false }
            return document?.model.source(for: sourceID) != nil
        case #selector(deleteComponentSourceAction(_:)):
            // Name the source in the title so this can never be mistaken for
            // deleting the selected layer.
            guard let sourceID = deleteComponentTarget(for: item),
                  let source = document?.model.source(for: sourceID) else {
                item.title = "Delete Component"
                return false
            }
            item.title = "Delete Component \u{201C}\(source.name)\u{201D}"
            return true
        case #selector(placeComponentAction(_:)):
            let object = item.representedObject
            if let request = object as? ComponentPlacementRequest {
                return canPlaceComponent(request.sourceID)
            }
            if let id = object as? UUID { return canPlaceComponent(id) }
            if let string = object as? String, let id = UUID(uuidString: string) {
                return canPlaceComponent(id)
            }
            if let string = object as? NSString, let id = UUID(uuidString: string as String) {
                return canPlaceComponent(id)
            }
            return false
        case #selector(setComponentCategoryAction(_:)):
            return categoryTargetSourceID != nil
        case #selector(addComponentStateAction(_:)):
            if case .source(let sid) = scope, let document,
               let source = document.model.source(for: sid) {
                let nextName = Self.nextComponentStateName(existing: source.states.map(\.name))
                let conventional = ComponentState.conventionalNames.contains {
                    $0.caseInsensitiveCompare(nextName) == .orderedSame
                }
                item.title = conventional ? "Add \(nextName.capitalized) State" : "Add Component State"
                return true
            }
            item.title = "Add Component State"
            return false
        case #selector(nextComponentStateAction(_:)), #selector(previousComponentStateAction(_:)):
            if case .source(let sid) = scope, let document,
               let source = document.model.source(for: sid) {
                return !source.states.isEmpty
            }
            return false
        case #selector(convertToPathAction(_:)):
            return selectionConvertibleToPath
        case #selector(outlineStrokeAction(_:)):
            return selectionCanOutlineStroke
        case #selector(pathfinderUniteAction(_:)), #selector(pathfinderSubtractAction(_:)),
             #selector(pathfinderIntersectAction(_:)), #selector(pathfinderExcludeAction(_:)):
            return selectionCanPathfinder
        case #selector(toggleBoldText(_:)), #selector(toggleItalicText(_:)), #selector(toggleUnderlineText(_:)):
            return selectionIsText || textEditor != nil
        case #selector(convertTextToShapesAction(_:)):
            return selectionCanConvertTextToOutlines
        case #selector(saveTypeStyleAction(_:)), #selector(setTextContentRoleAction(_:)):
            return selectionIsText
        case #selector(alignLeftAction(_:)), #selector(alignHCenterAction(_:)), #selector(alignRightAction(_:)),
             #selector(alignTopAction(_:)), #selector(alignVCenterAction(_:)), #selector(alignBottomAction(_:)):
            let n = app?.selectedNodeIDs.count ?? 0
            // No nodes selected → the same command is aligning BOARDS. See align(_:).
            if n == 0 { return !isSourceScope && (app?.selectedArtboardIDs.count ?? 0) >= 2 }
            return n >= 2 || (n >= 1 && app?.alignTarget == .artboard)
        case #selector(distributeHorizontallyAction(_:)), #selector(distributeVerticallyAction(_:)):
            let n = app?.selectedNodeIDs.count ?? 0
            if n == 0 { return !isSourceScope && (app?.selectedArtboardIDs.count ?? 0) >= 3 }
            return n >= 3
        case #selector(cleanUpArtboardsAction(_:)):
            return !isSourceScope && (app?.selectedArtboardIDs.count ?? 0) >= 2
        case #selector(centerSelectionAction(_:)):
            return hasNodes || hasArtboards
        case #selector(selectAll(_:)):
            return !currentNodes.isEmpty || (!isSourceScope && !currentArtboards.isEmpty)
        case #selector(deselectAllAction(_:)):
            return hasNodes || hasArtboards
        // Panel show/hide items: checkmark reflects whether the panel is in the
        // active layout (trays in multi-window, docks in single-window).
        case #selector(togglePanelLayers(_:)):
            item.state = (app?.isPanelShown(.layers) ?? false) ? .on : .off
            return true
        case #selector(togglePanelProperties(_:)):
            item.state = (app?.isPanelShown(.properties) ?? false) ? .on : .off
            return true
        case #selector(togglePanelComponents(_:)):
            item.state = (app?.isPanelShown(.components) ?? false) ? .on : .off
            return true
        case #selector(toggleLeftDock(_:)):
            item.state = (app?.showLeftPanel ?? false) ? .on : .off
            return app?.workspaceMode == .single   // docks only exist in single-window
        case #selector(toggleRightDock(_:)):
            item.state = (app?.showRightPanel ?? false) ? .on : .off
            return app?.workspaceMode == .single
        case #selector(toggleTestingModeAction(_:)):
            item.state = (app?.testingMode ?? false) ? .on : .off
            return true
        case #selector(showLastImportReportAction(_:)):
            return lastImportReport != nil
        case #selector(placeImageAction(_:)), #selector(importPDFAction(_:)),
             #selector(importXDAction(_:)), #selector(importRenderedHTMLAction(_:)),
             #selector(importCodePenPackageAction(_:)), #selector(importStorybookPackageAction(_:)),
             #selector(importFigmaAction(_:)),
             #selector(runGeometryAuditAction(_:)), #selector(saveDiagnosticReportAction(_:)),
             #selector(exportHandoffPackage(_:)), #selector(exportSemanticHTMLAction(_:)),
             #selector(exportCurrentArtboardToCodePen(_:)),
             #selector(exportDesignTokensAction(_:)):
            return document != nil
        case #selector(exportSelectedArtboard(_:)):
            return hasArtboards
        case #selector(exportAllArtboards(_:)):
            return !currentArtboards.isEmpty
        case #selector(roundToPixelAction(_:)):
            return hasNodes || hasArtboards
        case #selector(paste(_:)):
            let pb = NSPasteboard.general
            return pb.data(forType: Self.nodePasteboardType) != nil
                || pb.data(forType: Self.artboardPasteboardType) != nil
                || canDrop(pb)   // external SVG / PDF / image / component (⌘V was disabled for these)
        default:
            return true
        }
    }
}

@MainActor
private final class HTMLViewportSelectionController: NSObject {
    private let presets: [ArtboardPreset]
    private var buttons: [NSButton] = []
    private let summary = NSTextField(labelWithString: "")
    let view: NSView

    init(presets: [ArtboardPreset]) {
        self.presets = presets
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.frame = NSRect(x: 0, y: 0, width: 420,
                             height: CGFloat(70 + presets.count * 25))
        view = stack
        super.init()

        let label = NSTextField(labelWithString: "Browser widths")
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        stack.addArrangedSubview(label)
        for preset in presets {
            let button = NSButton(
                checkboxWithTitle: "\(preset.name) — \(Int(preset.width)) × \(Int(preset.height))",
                target: self, action: #selector(selectionChanged(_:)))
            button.state = preset.name == "Desktop" ? .on : .off
            button.setAccessibilityLabel("\(preset.name), \(Int(preset.width)) by \(Int(preset.height)) CSS pixels")
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        summary.textColor = .secondaryLabelColor
        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summary.maximumNumberOfLines = 2
        summary.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(summary)
        // Auto Layout requires both anchors to share a view hierarchy before a
        // constraint is activated. Activating this first raises NSGenericException;
        // AppKit catches it at the File-menu boundary and the import appears to
        // stop silently immediately after the folder chooser.
        summary.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        updateSummary()
    }

    var selectedViewports: [RenderedHTMLViewport] {
        zip(presets, buttons).compactMap { preset, button in
            guard button.state == .on else { return nil }
            return RenderedHTMLViewport(name: preset.name,
                                        width: preset.width,
                                        renderHeight: preset.height)
        }
    }

    @objc private func selectionChanged(_ sender: NSButton) {
        updateSummary()
    }

    private func updateSummary() {
        let count = buttons.filter { $0.state == .on }.count
        summary.stringValue = count == 0
            ? "No viewport selected. Choose at least one to import."
            : "This import will create \(count) artboard\(count == 1 ? "" : "s"). CSS media queries resolve separately at each selected size."
        summary.setAccessibilityLabel(summary.stringValue)
    }
}

@MainActor
private final class StorybookStorySelectionController: NSObject,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let stories: [StorybookStorySummary]
    private var filtered: [StorybookStorySummary]
    private let maximumSelection: Int
    private var selected = Set<String>()
    private let table = NSTableView()
    private let search = NSSearchField()
    private let summary = NSTextField(labelWithString: "")
    weak var importButton: NSButton? { didSet { updateSummary() } }
    let view: NSView

    init(stories: [StorybookStorySummary], maximumSelection: Int) {
        self.stories = stories
        self.filtered = stories
        self.maximumSelection = maximumSelection
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 440))
        super.init()

        search.frame = NSRect(x: 0, y: 404, width: 640, height: 28)
        search.placeholderString = "Search stories, components, tags, or source paths"
        search.delegate = self
        search.setAccessibilityLabel("Search Storybook stories")
        search.autoresizingMask = [.width, .minYMargin]
        view.addSubview(search)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("story"))
        column.width = 620
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 28
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.dataSource = self
        table.delegate = self
        table.selectionHighlightStyle = .none
        table.setAccessibilityLabel("Available Storybook stories")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 52, width: 640, height: 344))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]
        view.addSubview(scroll)

        let selectVisible = NSButton(title: "Select Visible (up to \(maximumSelection))",
                                     target: self,
                                     action: #selector(selectVisibleStories(_:)))
        selectVisible.frame = NSRect(x: 0, y: 14, width: 190, height: 28)
        selectVisible.bezelStyle = .rounded
        selectVisible.setAccessibilityHelp(
            "Selects matching stories in catalog order until the per-import limit is reached.")
        view.addSubview(selectVisible)

        let clear = NSButton(title: "Clear", target: self,
                             action: #selector(clearSelection(_:)))
        clear.frame = NSRect(x: 196, y: 14, width: 72, height: 28)
        clear.bezelStyle = .rounded
        view.addSubview(clear)

        summary.frame = NSRect(x: 278, y: 11, width: 362, height: 34)
        summary.alignment = .right
        summary.textColor = .secondaryLabelColor
        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summary.maximumNumberOfLines = 2
        summary.lineBreakMode = .byWordWrapping
        summary.autoresizingMask = [.width, .maxYMargin]
        view.addSubview(summary)
        updateSummary()
    }

    var selectedStoryIDs: Set<String> { selected }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let story = filtered[row]
        let identifier = NSUserInterfaceItemIdentifier("storybook-story-row")
        let button: NSButton
        if let reused = tableView.makeView(withIdentifier: identifier,
                                           owner: self) as? NSButton {
            button = reused
        } else {
            button = NSButton(checkboxWithTitle: "", target: self,
                              action: #selector(storyToggled(_:)))
            button.identifier = identifier
            button.lineBreakMode = .byTruncatingMiddle
        }
        button.title = story.displayName
        button.toolTip = [story.id, story.importPath].compactMap { $0 }
            .joined(separator: "\n")
        button.tag = row
        button.state = selected.contains(story.id) ? .on : .off
        button.setAccessibilityLabel("\(story.displayName), story id \(story.id)")
        button.setAccessibilityValue(button.state == .on ? "Selected" : "Not selected")
        return button
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = search.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines).localizedLowercase
        filtered = query.isEmpty ? stories : stories.filter {
            $0.searchableText.contains(query)
        }
        table.reloadData()
        updateSummary()
    }

    @objc private func storyToggled(_ sender: NSButton) {
        guard filtered.indices.contains(sender.tag) else { return }
        let id = filtered[sender.tag].id
        if sender.state == .on {
            guard selected.count < maximumSelection else {
                sender.state = .off
                NSSound.beep()
                updateSummary(limitReached: true)
                return
            }
            selected.insert(id)
        } else {
            selected.remove(id)
        }
        sender.setAccessibilityValue(sender.state == .on ? "Selected" : "Not selected")
        updateSummary()
    }

    @objc private func selectVisibleStories(_ sender: NSButton) {
        for story in filtered where selected.count < maximumSelection {
            selected.insert(story.id)
        }
        table.reloadData()
        updateSummary(limitReached: filtered.count > maximumSelection)
    }

    @objc private func clearSelection(_ sender: NSButton) {
        selected.removeAll()
        table.reloadData()
        updateSummary()
    }

    private func updateSummary(limitReached: Bool = false) {
        importButton?.isEnabled = !selected.isEmpty
        let visible = "\(filtered.count) shown of \(stories.count)"
        if limitReached || selected.count == maximumSelection {
            summary.stringValue = "\(selected.count) selected · \(visible) · \(maximumSelection) per-import limit reached"
        } else if selected.isEmpty {
            summary.stringValue = "None selected · \(visible) · choose 1–20 for a quick first import"
        } else {
            summary.stringValue = "\(selected.count) selected · \(visible) · \(maximumSelection) maximum"
        }
        summary.setAccessibilityLabel(summary.stringValue)
    }
}

@MainActor
private final class InteropImportProgressController {
    enum Outcome {
        case success(InteropImportResult)
        case failure(String)
    }

    private let alert = NSAlert()
    private let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 360, height: 18))
    private let detail = NSTextField(labelWithString: "Opening package…")
    private var modalStarted = false
    private(set) var outcome: Outcome?

    init(format: InteropFormat, sourceName: String) {
        alert.messageText = "Importing \(format.rawValue)"
        alert.informativeText = sourceName
        alert.addButton(withTitle: "Cancel")

        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        detail.lineBreakMode = .byTruncatingMiddle
        detail.setAccessibilityLabel("Import progress")
        let stack = NSStackView(views: [indicator, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 48)
        indicator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        detail.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        alert.accessoryView = stack
    }

    func update(_ progress: InteropProgress) {
        guard outcome == nil else { return }
        detail.stringValue = progress.detail.isEmpty ? progress.phase.rawValue
            : "\(progress.phase.rawValue): \(progress.detail)"
        if progress.total > 1 {
            indicator.isIndeterminate = false
            indicator.minValue = 0
            indicator.maxValue = Double(progress.total)
            indicator.doubleValue = Double(progress.completed)
        }
    }

    func finish(_ result: Outcome) {
        guard outcome == nil else { return }
        outcome = result
        if modalStarted { NSApp.abortModal() }
    }

    func runModal() -> NSApplication.ModalResponse {
        if outcome != nil { return .abort }
        modalStarted = true
        defer { modalStarted = false }
        return alert.runModal()
    }
}

// MARK: - Color bridge (UI layer keeps the model UI-free)

private extension RGBAColor {
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

// MARK: - Clipboard payloads

/// Copied shapes plus the origin of the board they came from (when they share
/// one), so paste can land on a different board at the same relative position.
struct NodeClipboard: Codable {
    var nodes: [Node]
    var sourceOrigin: CGPoint?
}

/// Copied artboards plus the shapes they own (document coordinates).
private struct ArtboardClipboard: Codable {
    var artboards: [Artboard]
    var nodes: [Node]
}

// MARK: - Perf meter (Testing Mode)

/// A tiny, allocation-light instrument for the canvas. It aggregates timing
/// sections and gauges, then prints ONE summary line to the console at most a few
/// times a second — so the log is readable and the measuring itself doesn't become
/// the bottleneck. Entirely inert unless `enabled` is set (driven by
/// `AppState.testingMode`); callers also guard hot loops on `enabled` so there's no
/// per-node cost when Testing Mode is off.
final class PerfMeter {
    var enabled = false

    private struct Stat { var n = 0; var total = 0.0; var mx = 0.0 }
    private var timers: [String: Stat] = [:]
    /// Last + max value seen for a named gauge since the previous flush.
    private var gauges: [String: (last: Int, mx: Int)] = [:]
    private var lastFlush = CFAbsoluteTimeGetCurrent()
    /// Stable print order — set on first sight of each key.
    private var timerOrder: [String] = []
    private var gaugeOrder: [String] = []

    /// Record an elapsed time (ms) for a named section.
    func record(_ name: String, ms: Double) {
        guard enabled else { return }
        if timers[name] == nil { timerOrder.append(name) }
        var s = timers[name] ?? Stat()
        s.n += 1; s.total += ms; s.mx = Swift.max(s.mx, ms)
        timers[name] = s
    }

    /// Note the current value of a named gauge (e.g. node count this frame).
    func gauge(_ name: String, _ value: Int) {
        guard enabled else { return }
        if gauges[name] == nil { gaugeOrder.append(name) }
        let prev = gauges[name] ?? (0, 0)
        gauges[name] = (value, Swift.max(prev.mx, value))
    }

    /// Convenience: time `body`, recording its duration under `name`.
    @discardableResult
    func measure<T>(_ name: String, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { record(name, ms: (CFAbsoluteTimeGetCurrent() - t0) * 1000) }
        return body()
    }

    /// Print a summary line and reset, but no more often than `every` seconds.
    func flushIfNeeded(every: Double = 0.5) {
        guard enabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFlush >= every, !timers.isEmpty || !gauges.isEmpty else { return }
        var parts: [String] = []
        for k in timerOrder {
            guard let s = timers[k], s.n > 0 else { continue }
            parts.append(String(format: "%@ avg %.1fms max %.1fms (%d×)", k, s.total / Double(s.n), s.mx, s.n))
        }
        for k in gaugeOrder {
            guard let g = gauges[k] else { continue }
            parts.append("\(k) \(g.last) (max \(g.mx))")
        }
        if !parts.isEmpty {
            let summary = "[EXP perf] " + parts.joined(separator: "  |  ")
            DiagnosticLog.shared.log(summary)
        }
        timers.removeAll(keepingCapacity: true)
        gauges.removeAll(keepingCapacity: true)
        timerOrder.removeAll(keepingCapacity: true)
        gaugeOrder.removeAll(keepingCapacity: true)
        lastFlush = now
    }

    func reset() {
        timers.removeAll(); gauges.removeAll()
        timerOrder.removeAll(); gaugeOrder.removeAll()
        lastFlush = CFAbsoluteTimeGetCurrent()
    }
}
