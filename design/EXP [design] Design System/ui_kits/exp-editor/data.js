// Sample document model for the EXP [design] editor UI kit. Mirrors the app's
// Node/Artboard shape closely enough for a cosmetic recreation.
window.EXP_DOC = {
  docName: "awesome document #5",
  zoom: 94,
  artboards: [
    { id: "ab1", name: "Artboard 1", x: 0, y: 0, w: 393, h: 852, bg: "#ffffff" },
  ],
  // Flat list with depth for the layers tree.
  layers: [
    { id: "ab", name: "Artboard name", kind: "artboard", depth: 0, expandable: true, expanded: true },
    { id: "t1", name: "a text layer.", kind: "text", depth: 1,
      X: 32, Y: 64, W: 240, H: 38, rot: 0, opacity: 100, blend: "Normal",
      fill: "#1a1a1c", stroke: "#000000", strokeW: 0 },
    { id: "c1", name: "Some component name", kind: "component", depth: 1, expandable: true,
      X: 32, Y: 140, W: 290, H: 96, rot: 0, opacity: 100, blend: "Normal",
      fill: "#2b6fdb", stroke: "#000000", strokeW: 0 },
    { id: "i1", name: "image layer", kind: "image", depth: 1,
      X: 32, Y: 260, W: 290, H: 180, rot: 0, opacity: 100, blend: "Normal",
      fill: "#3a3a3e", stroke: "#000000", strokeW: 0 },
    { id: "g1", name: "another group", kind: "group", depth: 1, expandable: true, locked: true },
    { id: "g2", name: "expanded group", kind: "group", depth: 1, expandable: true, expanded: true },
    { id: "i2", name: "image layer", kind: "image", depth: 2,
      X: 48, Y: 470, W: 200, H: 130, rot: 0, opacity: 100, blend: "Normal",
      fill: "#4a4a50", stroke: "#000000", strokeW: 0 },
    { id: "p1", name: "another long layer name that…", kind: "path", depth: 2, hidden: true,
      X: 60, Y: 620, W: 120, H: 80, rot: 12, opacity: 80, blend: "Multiply",
      fill: "#4ce62e", stroke: "#000000", strokeW: 0 },
    { id: "e1", name: "some shape. huzzah", kind: "ellipse", depth: 1,
      X: 120, Y: 700, W: 100, H: 100, rot: 0, opacity: 100, blend: "Normal",
      fill: "#d9d9de", stroke: "#000000", strokeW: 0 },
  ],
  blendModes: ["Normal", "Multiply", "Screen", "Overlay", "Soft Light", "Hard Light",
               "Color Dodge", "Color Burn", "Difference", "Exclusion", "Hue",
               "Saturation", "Color", "Luminosity"],
};
