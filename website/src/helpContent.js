const helpAsset = (name) => `/assets/help/${name}`;

export const helpArticles = [
  {
    slug: "create-organize-artboards",
    category: "canvas + artboards",
    title: "Create and organize artboards",
    summary:
      "Resize artboards, add common device sizes, duplicate them with their contents, and arrange a working flow.",
    readTime: "4 min",
    updated: "July 23, 2026",
    keywords: [
      "artboard", "board", "page", "frame", "preset", "resize", "dimensions",
      "duplicate", "copy", "rename", "move", "delete", "undo", "properties",
    ],
    cardPoster: helpAsset("moving-artboards-poster.jpg"),
    sections: [
      {
        id: "resize",
        title: "Resize an artboard",
        paragraphs: [
          "Select an artboard on the canvas or in Layers, then drag a corner or edge handle to resize it visually.",
          "For an exact size, enter its width and height in Properties. When changing a numeric value with the keyboard, hold Shift to move in increments of 10.",
        ],
        video: {
          src: helpAsset("resize-artboards.mp4"),
          poster: helpAsset("resize-artboards-poster.jpg"),
          label: "Resize an artboard visually, then enter exact dimensions in Properties.",
        },
      },
      {
        id: "preset",
        title: "Add an artboard from a preset",
        paragraphs: [
          "Open the artboard preset menu and choose a phone, tablet, desktop, web, or paper size. EXP places the new artboard beside the existing one, ready to reposition or customize.",
        ],
        video: {
          src: helpAsset("preset-artboard-sizes.mp4"),
          poster: helpAsset("preset-artboard-sizes-poster.jpg"),
          label: "Choose several device sizes from the artboard preset menu.",
        },
      },
      {
        id: "duplicate",
        title: "Duplicate an artboard",
        paragraphs: [
          "Hold Option while dragging an artboard. A plus sign appears beside the pointer to show that you are creating a copy. Hold Shift as well to keep the copy aligned with the original.",
          "Objects on the artboard are duplicated with it, making this a quick way to create the next screen or variation in a flow.",
        ],
        video: {
          src: helpAsset("duplicating-artboards.mp4"),
          poster: helpAsset("duplicating-artboards-poster.jpg"),
          label: "Option-drag an artboard to duplicate it together with its contents.",
        },
      },
      {
        id: "rename",
        title: "Rename an artboard",
        paragraphs: [
          "Double-click the title above an artboard or its name in Layers, then type the new name. You can also edit the name in Properties. The change appears everywhere automatically.",
        ],
        video: {
          src: helpAsset("renaming-artboards.mp4"),
          poster: helpAsset("renaming-artboards-poster.jpg"),
          label: "Rename artboards from Layers and directly above the canvas.",
        },
      },
      {
        id: "move",
        title: "Move one or several artboards",
        paragraphs: [
          "Drag an artboard by its title to move it. To rearrange several together, drag a selection rectangle that fully encloses them, then drag any selected artboard to move the set.",
        ],
        video: {
          src: helpAsset("moving-artboards.mp4"),
          poster: helpAsset("moving-artboards-poster.jpg"),
          label: "Select several artboards and rearrange them as a group.",
        },
      },
      {
        id: "delete",
        title: "Delete an artboard",
        paragraphs: [
          "Select one or more artboards and press Delete. Deleting an artboard also deletes the objects it contains.",
        ],
        note: "Press Command-Z or choose Edit > Undo if you remove an artboard by mistake.",
        video: {
          src: helpAsset("delete-artboards.mp4"),
          poster: helpAsset("delete-artboards-poster.jpg"),
          label: "Delete selected artboards, including the objects they contain.",
        },
      },
    ],
    related: ["use-the-wall", "pan-zoom-center", "artboard-layout-grids"],
  },
  {
    slug: "use-the-wall",
    category: "canvas + artboards",
    title: "Use the wall as a thinking space",
    summary:
      "Keep labels, references, loose ideas, and project context near the work without forcing everything into an artboard.",
    readTime: "2 min",
    updated: "July 23, 2026",
    keywords: [
      "wall", "workspace", "pasteboard", "references", "inspiration", "moodboard",
      "labels", "organize", "branding", "wireframes", "exploration",
    ],
    cardPoster: helpAsset("using-the-wall-poster.jpg"),
    sections: [
      {
        id: "organize",
        title: "Give related work a visible home",
        paragraphs: [
          "The area around your artboards is the wall. Move related artboards near one another, then add a large text label such as Wireframes, Branding, or Inspiration to name the area.",
          "Place reference shapes, colors, images, or notes nearby. As the document grows, move the cluster to a comfortable part of the wall and keep only the context that helps you design and understand the project.",
        ],
        steps: [
          "Move related artboards near one another.",
          "Add a text label that describes the area.",
          "Place useful references and loose material nearby.",
          "Rearrange the area as the project changes.",
        ],
        video: {
          src: helpAsset("using-the-wall.mp4"),
          poster: helpAsset("using-the-wall-poster.jpg"),
          label: "Arrange wireframes, inspiration, and branding references into labeled areas on the wall.",
        },
      },
    ],
    related: ["create-organize-artboards", "pan-zoom-center"],
  },
  {
    slug: "pan-zoom-center",
    category: "canvas + artboards",
    title: "Pan, zoom, and center your work",
    summary:
      "Navigate with trackpad gestures or toolbar controls, then bring a distant object directly into view.",
    readTime: "2 min",
    updated: "July 23, 2026",
    keywords: [
      "pan", "zoom", "navigate", "trackpad", "hand tool", "pan tool", "percentage",
      "magnification", "center", "center in canvas", "center on canvas", "find object",
      "layers", "selection",
    ],
    cardPoster: helpAsset("center-in-canvas-poster.jpg"),
    sections: [
      {
        id: "pan-zoom",
        title: "Move around the canvas",
        paragraphs: [
          "On a trackpad, pinch to zoom and move two fingers to pan across the wall. Without a trackpad, select the Pan tool and drag anywhere on the canvas to move the view without moving an artboard or object.",
          "Use the zoom controls in the toolbar for quick changes. Open the zoom menu to choose a common percentage such as 50% or 100%, or enter a custom percentage.",
        ],
        video: {
          src: helpAsset("pan-zoom.mp4"),
          poster: helpAsset("pan-zoom-poster.jpg"),
          label: "Pan across the wall and zoom from an overview into a specific area.",
        },
      },
      {
        id: "center",
        title: "Center an object in the canvas",
        paragraphs: [
          "When an object is selected in Layers but is difficult to find on a large wall, right-click it and choose Center in Canvas. EXP moves the view so the object is centered without changing the object itself.",
        ],
        video: {
          src: helpAsset("center-in-canvas.mp4"),
          poster: helpAsset("center-in-canvas-poster.jpg"),
          label: "Use Center in Canvas from Layers to bring distant reference objects into view.",
        },
      },
    ],
    related: ["create-organize-artboards", "use-the-wall", "document-grid-snap"],
  },
  {
    slug: "document-grid-snap",
    category: "layout + alignment",
    title: "Show the document grid and snap to it",
    summary:
      "Display an evenly spaced grid across the document and make objects land directly on its lines.",
    readTime: "2 min",
    updated: "July 23, 2026",
    keywords: [
      "grid", "document grid", "global grid", "snap", "snap to grid", "spacing",
      "subdivisions", "show grid", "view menu", "align",
    ],
    cardPoster: helpAsset("snap-to-grid-poster.jpg"),
    sections: [
      {
        id: "configure",
        title: "Configure the document grid",
        paragraphs: [
          "Click an empty area of the wall so nothing is selected. In Properties, turn on Show grid, then set the grid size and number of subdivisions. Hold Shift while changing a numeric value to move in increments of 10.",
          "Turn on Snap to grid when objects should align to the grid as they move. The same Show Grid and Snap to Grid commands are available in the View menu, along with their keyboard shortcuts.",
        ],
        note: "Turn off Show grid when you want an unobstructed view. EXP keeps the grid size and subdivision settings for the next time you show it.",
        video: {
          src: helpAsset("snap-to-grid.mp4"),
          poster: helpAsset("snap-to-grid-poster.jpg"),
          label: "Show the document grid, adjust its spacing, and snap an object to the grid lines.",
        },
      },
    ],
    related: ["artboard-layout-grids", "pan-zoom-center"],
  },
  {
    slug: "artboard-layout-grids",
    category: "layout + alignment",
    title: "Add layout grids to an artboard",
    summary:
      "Use column, row, and baseline overlays to guide composition and text alignment on an individual artboard.",
    readTime: "3 min",
    updated: "July 23, 2026",
    keywords: [
      "layout grid", "artboard grid", "columns", "rows", "baseline", "gutter",
      "margin", "overlay", "grid color", "twelve column", "12 column",
    ],
    cardPoster: helpAsset("layout-grids-poster.jpg"),
    sections: [
      {
        id: "add",
        title: "Add and configure layout grids",
        paragraphs: [
          "Select an artboard. In Properties, find Layout grids, choose the add control, then select Columns, Rows, or Baseline.",
          "For columns or rows, adjust the count, gutter, and margin. EXP updates the overlay immediately. Use a baseline grid as a repeated alignment reference for text and other elements, and change grid colors when several overlays need to remain visually distinct.",
        ],
        steps: [
          "Select the artboard that needs a grid.",
          "Add a Columns, Rows, or Baseline grid from Properties.",
          "Adjust its count, spacing, gutter, margin, and color as applicable.",
          "Use the checkbox to hide a grid without losing its settings.",
        ],
        video: {
          src: helpAsset("layout-grids.mp4"),
          poster: helpAsset("layout-grids-poster.jpg"),
          label: "Add column, row, and baseline layout grids, adjust their settings, and combine several overlays.",
        },
      },
      {
        id: "manage",
        title: "Hide, combine, or remove grids",
        paragraphs: [
          "Turn off a grid’s checkbox to hide it without losing its settings. Add multiple grids when you want to compare systems or combine columns, rows, and baselines. Choose the remove control beside a grid to delete it from the artboard.",
        ],
        note: "Layout grids belong to an artboard. The document grid is a separate, document-wide alignment aid.",
      },
    ],
    related: ["document-grid-snap", "create-organize-artboards"],
  },
  {
    slug: "create-format-text",
    category: "text + handoff",
    title: "Create and format text",
    summary:
      "Create auto-width text or a wrapping text box, style its typography, and add semantic context for handoff.",
    readTime: "5 min",
    updated: "July 23, 2026",
    keywords: [
      "text", "type", "point text", "area text", "auto width", "text box",
      "wrap", "overflow", "font", "typeface", "weight", "size", "color",
      "alignment", "line height", "leading", "spacing", "tracking", "case",
      "content", "semantic", "heading", "paragraph", "handoff", "html",
    ],
    cardPoster: helpAsset("text-point-area-poster.jpg"),
    sections: [
      {
        id: "create",
        title: "Create auto-width text or a text box",
        paragraphs: [
          "Choose Text in the toolbar or press T. Click once to create Auto width text; its width grows and shrinks with its content. Click and drag to create a Text box with a fixed width that wraps onto additional lines.",
          "Resize a text box to change where its lines wrap. A plus-sign overflow indicator means the box contains text that does not currently fit. Increase its height or switch to Auto width to reveal the hidden content.",
        ],
        video: {
          src: helpAsset("text-point-area.mp4"),
          poster: helpAsset("text-point-area-poster.jpg"),
          label: "Create auto-width text and a wrapping text box, then change the box mode and dimensions.",
        },
      },
      {
        id: "font",
        title: "Choose Font, Weight, Size, and Color",
        paragraphs: [
          "Select the text, then choose its typeface family from Font. When that family provides several faces, a Weight row appears below it; fonts without additional faces do not show that row.",
          "Enter an exact Size, use an arrow key to change the focused value by one, or hold Shift while pressing an arrow key to change it by ten. Choose Color to set the text color.",
        ],
        video: {
          src: helpAsset("text-font-weight-size-color.mp4"),
          poster: helpAsset("text-font-weight-size-color-poster.jpg"),
          label: "Change a text layer’s Font, Weight, Size, and Color in Properties.",
        },
      },
      {
        id: "alignment-line",
        title: "Align text and set its line height",
        paragraphs: [
          "For a text box, choose left, center, or right alignment to position each line inside the box.",
          "Line can use the font’s natural height with Auto, multiply that natural height with ×, use an exact pixel value with px, or use em relative to the text’s font size. A value of 1em equals the current font size.",
        ],
        video: {
          src: helpAsset("text-alignment-line-spacing.mp4"),
          poster: helpAsset("text-alignment-line-spacing-poster.jpg"),
          label: "Change text alignment, then compare automatic, proportional, pixel, and em line-height settings.",
        },
      },
      {
        id: "spacing-case",
        title: "Adjust spacing and case",
        paragraphs: [
          "Spacing controls letter spacing, also called tracking, in pixels. Use a positive value to spread characters apart or a negative value to bring them closer together.",
          "Case changes how text is displayed without requiring you to retype it: As typed, UPPERCASE, lowercase, Capitalize Each, or Sentence case.",
        ],
        video: {
          src: helpAsset("text-spacing-case.mp4"),
          poster: helpAsset("text-spacing-case-poster.jpg"),
          label: "Loosen and tighten letter spacing, then apply the available non-destructive text-case options.",
        },
      },
      {
        id: "content",
        title: "Add semantic context for handoff",
        paragraphs: [
          "Below the visual text controls, a divider separates Content into its own handoff subsection. Use it to describe the text’s semantic purpose, such as Plain text, Paragraph, or Heading 1.",
          "Content does not change Font, Weight, Size, Color, or any other visual styling. It gives HTML handoff enough context to produce a meaningful element instead of making an implementer infer document structure from appearance alone.",
        ],
        video: {
          src: helpAsset("text-handoff-content.mp4"),
          poster: helpAsset("text-handoff-content-poster.jpg"),
          label: "Assign semantic Content to text after its visual typography settings are complete.",
        },
      },
    ],
    related: ["create-transform-shapes", "organize-layers", "group-edit-objects"],
  },
  {
    slug: "create-transform-shapes",
    category: "shapes + layers",
    title: "Create and transform shapes",
    summary:
      "Draw rectangles, ellipses, polygons, and lines, then resize, rotate, and position them visually or with exact values.",
    readTime: "5 min",
    updated: "July 23, 2026",
    keywords: [
      "shape", "rectangle", "ellipse", "polygon", "line", "pen", "draw",
      "resize", "rotate", "aspect ratio", "dimensions", "position", "properties",
      "inspector", "shortcut", "select", "edit points",
    ],
    cardPoster: helpAsset("shapes-basic-tools-poster.jpg"),
    sections: [
      {
        id: "tools",
        title: "Choose a drawing tool",
        paragraphs: [
          "Drawing tools live in the toolbar on the left. Pause over a tool to see its name and keyboard shortcut: Rectangle (R), Ellipse (O), Polygon (G), Line (L), Pen (P), Select (V), and Edit Points (A).",
          "The Select tool moves and transforms an entire object. Edit Points works with the individual points that define a shape; point editing is covered separately with paths.",
        ],
      },
      {
        id: "basic-tools",
        title: "Draw rectangles, ellipses, and lines",
        paragraphs: [
          "With Rectangle (R), Ellipse (O), or Line (L), click once to create the tool’s default shape or click and drag to choose its dimensions and direction.",
          "A line has no fill. Use Stroke in Properties to change its color and width.",
        ],
        video: {
          src: helpAsset("shapes-basic-tools.mp4"),
          poster: helpAsset("shapes-basic-tools-poster.jpg"),
          label: "Create rectangles, ellipses, and lines by clicking or dragging, then change a line’s stroke.",
        },
      },
      {
        id: "polygon",
        title: "Change a polygon’s sides",
        paragraphs: [
          "Choose Polygon or press G. A new polygon begins with three sides. Change Sides in Properties to create a quadrilateral, pentagon, or another regular polygon; use the arrow keys while the field is focused to add or remove sides.",
        ],
        video: {
          src: helpAsset("polygon-sides.mp4"),
          poster: helpAsset("polygon-sides-poster.jpg"),
          label: "Create the default triangle, then add sides to turn it into other regular polygons.",
        },
      },
      {
        id: "draw-resize",
        title: "Resize a shape",
        paragraphs: [
          "After drawing, switch to Select or press V. Drag an edge handle to change one dimension or a corner handle to change both. Hold Shift while resizing to preserve the object’s aspect ratio.",
        ],
        video: {
          src: helpAsset("shapes-draw-resize.mp4"),
          poster: helpAsset("shapes-draw-resize-poster.jpg"),
          label: "Draw rectangles by clicking and dragging, then resize them freely or with Shift to preserve their proportions.",
        },
      },
      {
        id: "rotate",
        title: "Rotate a shape",
        paragraphs: [
          "Move just outside a corner of the selection until the rotate cursor appears, then drag around the object’s center. Hold Shift while rotating to snap the angle to 15-degree increments.",
        ],
        video: {
          src: helpAsset("shapes-rotate.mp4"),
          poster: helpAsset("shapes-rotate-poster.jpg"),
          label: "Rotate a shape freely, then hold Shift to rotate in consistent angle increments.",
        },
      },
      {
        id: "exact-transform",
        title: "Enter exact values",
        paragraphs: [
          "Use Properties when the result needs exact position, size, or rotation values. With a numeric field focused, press an arrow key to change it by one unit or hold Shift while pressing an arrow key to change it by ten.",
          "Enter 0 for the rotation to return an object to its unrotated angle.",
        ],
        video: {
          src: helpAsset("shapes-exact-transform.mp4"),
          poster: helpAsset("shapes-exact-transform-poster.jpg"),
          label: "Adjust a shape’s position, dimensions, and rotation with exact values in Properties.",
        },
      },
    ],
    related: ["draw-edit-vector-paths", "guides-measure-spacing", "align-distribute-objects"],
  },
  {
    slug: "draw-edit-vector-paths",
    category: "shapes + layers",
    title: "Draw and edit vector paths",
    summary:
      "Draw straight and curved paths, add or remove anchors, and convert shapes or strokes into editable geometry.",
    readTime: "5 min",
    updated: "July 23, 2026",
    keywords: [
      "path", "vector", "pen", "bezier", "bézier", "curve", "anchor",
      "point", "handle", "straight", "corner", "smooth", "add point",
      "remove point", "delete point", "outline stroke", "convert to path",
      "edit points", "direct select", "shift", "45 degree",
    ],
    cardPoster: helpAsset("pen-curved-path-poster.jpg"),
    sections: [
      {
        id: "outline-stroke",
        title: "Turn a stroke into a filled path",
        paragraphs: [
          "Select a stroked line or shape, then choose Object > Path > Outline Stroke. EXP replaces the stroke with ordinary filled path geometry.",
          "Choose Edit Points or press A to move its anchors individually. Outlining is useful when a former stroke needs to scale as geometry or become a custom silhouette.",
        ],
        video: {
          src: helpAsset("path-outline-stroke.mp4"),
          poster: helpAsset("path-outline-stroke-poster.jpg"),
          label: "Outline a line’s stroke, then edit the resulting filled path geometry.",
        },
      },
      {
        id: "straight",
        title: "Draw a path with corner points",
        paragraphs: [
          "Choose Pen or press P. Click to place each corner anchor, then continue clicking to build the path. Click the first anchor again to close it; a closed path can use a fill like any other closed shape.",
          "Use Select (V) to move the complete path and Edit Points (A) to change its individual anchors.",
        ],
        video: {
          src: helpAsset("pen-straight-path.mp4"),
          poster: helpAsset("pen-straight-path-poster.jpg"),
          label: "Place corner anchors with Pen, close the path, apply a fill, and edit the resulting shape.",
        },
      },
      {
        id: "curves",
        title: "Draw curves with Bézier handles",
        paragraphs: [
          "With Pen active, click and drag while placing an anchor to pull a pair of curve handles. Their direction and length control how the curve enters and leaves the anchor. Click without dragging when the next anchor should be a corner.",
          "Hold Shift while pulling a handle to constrain it to axis and 45-degree increments. Mix corner and smooth anchors in the same path, then click the first anchor to close it.",
        ],
        video: {
          src: helpAsset("pen-curved-path.mp4"),
          poster: helpAsset("pen-curved-path-poster.jpg"),
          label: "Combine corner and curved anchors, constrain a handle with Shift, and close the finished path.",
        },
      },
      {
        id: "add-remove",
        title: "Add or remove an anchor",
        paragraphs: [
          "With Pen active, move over a path segment until the pointer shows a plus, then click to add an anchor. Move over an existing anchor until the pointer shows a minus, then click to remove it.",
          "Switch to Edit Points when you want to select and reposition the remaining anchors instead of changing the path’s point count.",
        ],
        video: {
          src: helpAsset("pen-add-remove-points.mp4"),
          poster: helpAsset("pen-add-remove-points-poster.jpg"),
          label: "Add anchors to a path segment and remove existing anchors with the Pen tool.",
        },
      },
      {
        id: "convert",
        title: "Convert a shape to a path",
        paragraphs: [
          "Select a rectangle, ellipse, polygon, or line, then choose Object > Path > Convert to Path. Its appearance remains, but Edit Points can now reshape its anchors and Pen can add or remove points.",
        ],
        video: {
          src: helpAsset("shape-to-path.mp4"),
          poster: helpAsset("shape-to-path-poster.jpg"),
          label: "Convert a regular shape into a path, then move its anchors to create custom geometry.",
        },
      },
    ],
    related: ["create-transform-shapes", "group-edit-objects", "organize-layers"],
  },
  {
    slug: "guides-measure-spacing",
    category: "layout + alignment",
    title: "Use guides and measure spacing",
    summary:
      "Use temporary alignment guides, inspect the distance between objects, and nudge a selection into place.",
    readTime: "2 min",
    updated: "July 23, 2026",
    keywords: [
      "smart guide", "alignment guide", "measure", "spacing", "distance", "option",
      "nudge", "arrow key", "pixels", "align", "measurement",
    ],
    cardPoster: helpAsset("guides-measure-spacing-poster.jpg"),
    sections: [
      {
        id: "guides-measure",
        title: "Align visually and inspect the distance",
        paragraphs: [
          "Move an object near another object. EXP displays temporary guides when their edges or centers align, so you can place related objects without calculating their coordinates first.",
          "To inspect spacing, select an object, hold Option, and move the pointer toward another object. Use an arrow key to nudge the selection by one pixel, or Shift-arrow to move it by ten pixels, until the measurement reaches the value you want.",
        ],
        note: "Measurements are temporary canvas feedback; they do not add permanent guides or labels to the document.",
        video: {
          src: helpAsset("guides-measure-spacing.mp4"),
          poster: helpAsset("guides-measure-spacing-poster.jpg"),
          label: "Use smart guides to align two shapes, then hold Option to measure and refine the space between them.",
        },
      },
    ],
    related: ["align-distribute-objects", "create-transform-shapes", "document-grid-snap"],
  },
  {
    slug: "align-distribute-objects",
    category: "layout + alignment",
    title: "Align and distribute objects",
    summary:
      "Align selected objects to one another or their artboard, then give three or more objects equal spacing.",
    readTime: "3 min",
    updated: "July 23, 2026",
    keywords: [
      "align", "distribute", "selection", "artboard", "top", "bottom", "left",
      "right", "center", "horizontal", "vertical", "equal spacing", "multiple select",
      "shift click", "marquee",
    ],
    cardPoster: helpAsset("align-selection-artboard-poster.jpg"),
    sections: [
      {
        id: "align",
        title: "Align to the selection or artboard",
        paragraphs: [
          "Drag a selection rectangle around several objects, or hold Shift while clicking each object you want to include. Alignment controls appear in Properties when multiple objects are selected.",
          "With Selection as the target, choose an edge or center alignment to align the objects to one another. Switch the target to Artboard when the selection should use its artboard as the reference instead.",
        ],
        video: {
          src: helpAsset("align-selection-artboard.mp4"),
          poster: helpAsset("align-selection-artboard-poster.jpg"),
          label: "Align objects to one another, then switch the alignment target and position them within their artboard.",
        },
      },
      {
        id: "distribute",
        title: "Distribute objects evenly",
        paragraphs: [
          "Select three or more objects, then choose horizontal or vertical distribution. EXP keeps the two outer objects fixed and gives the objects between them equal spacing.",
          "Align first when the objects should also share an edge or centerline; distribute afterward to make their spacing consistent.",
        ],
        video: {
          src: helpAsset("distribute-objects.mp4"),
          poster: helpAsset("distribute-objects-poster.jpg"),
          label: "Align several objects and distribute them with equal horizontal and vertical spacing.",
        },
      },
    ],
    related: ["guides-measure-spacing", "create-transform-shapes", "group-edit-objects"],
  },
  {
    slug: "organize-layers",
    category: "shapes + layers",
    title: "Organize, duplicate, and delete layers",
    summary:
      "Duplicate objects, control what draws in front, name layers clearly, and select work hidden underneath other objects.",
    readTime: "4 min",
    updated: "July 23, 2026",
    keywords: [
      "layer", "order", "stack", "front", "back", "duplicate", "copy", "paste",
      "command d", "option drag", "shift", "rename", "delete", "undo", "hidden",
      "covered", "select", "bring forward", "send backward",
    ],
    cardPoster: helpAsset("layers-reorder-poster.jpg"),
    sections: [
      {
        id: "duplicate",
        title: "Duplicate an object",
        paragraphs: [
          "Copy and paste with Command-C and Command-V, or choose Copy and Paste from the Edit menu. The duplicate begins in the same position as the original, so move it afterward to reveal it.",
          "For a visible duplicate-and-move gesture, hold Option while dragging an object. Hold Shift with Option to constrain the drag horizontally or vertically and keep the copy aligned with the original.",
        ],
        video: {
          src: helpAsset("layers-duplicate.mp4"),
          poster: helpAsset("layers-duplicate-poster.jpg"),
          label: "Duplicate objects with keyboard and menu copy-paste, Option-drag, and Option-Shift-drag for an aligned copy.",
        },
      },
      {
        id: "stacking",
        title: "Change the stacking order",
        paragraphs: [
          "Objects higher in Layers draw in front of objects below them. Drag a layer up or down to change the order.",
          "Use Command-] to bring an object forward one position and Command-[ to send it backward. Add Shift to bring it all the way to the front or send it all the way to the back.",
        ],
        video: {
          src: helpAsset("layers-reorder.mp4"),
          poster: helpAsset("layers-reorder-poster.jpg"),
          label: "Change which objects draw in front by dragging layers and using the forward, backward, front, and back shortcuts.",
        },
      },
      {
        id: "rename",
        title: "Rename a layer",
        paragraphs: [
          "Double-click a layer’s name in Layers, or edit its name in Properties. The new name appears everywhere. Descriptive names make covered objects and complex documents much easier to navigate.",
        ],
        video: {
          src: helpAsset("layers-rename.mp4"),
          poster: helpAsset("layers-rename-poster.jpg"),
          label: "Give several colored shapes descriptive names that update immediately in Layers.",
        },
      },
      {
        id: "covered",
        title: "Select a covered object",
        paragraphs: [
          "When an object is partially or completely hidden behind another, select its named layer in Layers. You can then move or edit it without first changing the stacking order.",
        ],
        video: {
          src: helpAsset("layers-select-covered.mp4"),
          poster: helpAsset("layers-select-covered-poster.jpg"),
          label: "Use descriptive layer names to select individual shapes in a tightly overlapping composition.",
        },
      },
      {
        id: "delete",
        title: "Delete an object",
        paragraphs: [
          "Select an object and press Delete, or choose Delete from the Edit menu.",
        ],
        note: "Press Command-Z or choose Edit > Undo if you remove an object accidentally.",
      },
    ],
    related: ["group-edit-objects", "create-transform-shapes", "align-distribute-objects"],
  },
  {
    slug: "group-edit-objects",
    category: "shapes + layers",
    title: "Group and edit objects",
    summary:
      "Make related objects move together while keeping every child available for direct editing—even inside nested groups.",
    readTime: "3 min",
    updated: "July 23, 2026",
    keywords: [
      "group", "ungroup", "nested group", "edit inside", "select child", "command click",
      "double click", "command g", "shift command g", "layers", "move together",
    ],
    cardPoster: helpAsset("groups-create-move-poster.jpg"),
    sections: [
      {
        id: "create",
        title: "Create and move a group",
        paragraphs: [
          "Select two or more objects, then press Command-G or choose Object > Group. Rename the group in Layers so its purpose remains clear.",
          "Expand the group in Layers to see its children. Clicking a member of the group on the canvas normally selects the group, allowing the whole set to move as one object.",
        ],
        video: {
          src: helpAsset("groups-create-move.mp4"),
          poster: helpAsset("groups-create-move-poster.jpg"),
          label: "Group several shapes, expand the new group in Layers, and move the complete group together.",
        },
      },
      {
        id: "edit-child",
        title: "Select an object inside a group",
        paragraphs: [
          "Click a child directly in the expanded Layers list, double-click a child on the canvas to enter the group, or hold Command while clicking a child to select it directly through the group.",
          "After selecting the child, move or edit it without moving the entire group.",
        ],
        video: {
          src: helpAsset("selecting-items-in-a-group.mp4"),
          poster: helpAsset("selecting-items-in-a-group-poster.jpg"),
          label: "Select individual objects inside a group from Layers, by double-clicking, and with Command-click.",
        },
      },
      {
        id: "nested",
        title: "Navigate nested groups",
        paragraphs: [
          "A group can contain another group. Double-click once to enter the outer group, then double-click again to reach an object deeper inside it. Command-click is the shortcut when you want to select the deeply nested object directly.",
        ],
        video: {
          src: helpAsset("navigating-nested-groups.mp4"),
          poster: helpAsset("navigating-nested-groups-poster.jpg"),
          label: "Move through a group nested inside another group, or use Command-click to reach a child directly.",
        },
      },
      {
        id: "ungroup",
        title: "Ungroup objects",
        paragraphs: [
          "Select the group and press Shift-Command-G or choose Object > Ungroup. Its children return to individual layers while keeping their current appearance and positions.",
        ],
      },
    ],
    related: ["organize-layers", "align-distribute-objects", "create-transform-shapes"],
  },
];

export const helpCategories = [...new Set(helpArticles.map((article) => article.category))];

export function findHelpArticle(slug) {
  return helpArticles.find((article) => article.slug === slug);
}

export function searchableHelpText(article) {
  return [
    article.title,
    article.summary,
    article.category,
    ...article.keywords,
    ...article.sections.flatMap((section) => [
      section.title,
      ...(section.paragraphs ?? []),
      ...(section.steps ?? []),
      section.note ?? "",
    ]),
  ]
    .join(" ")
    .toLocaleLowerCase();
}
