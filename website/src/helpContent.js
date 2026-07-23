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
