# Help content draft 02 — shapes, alignment, layers, and groups

Source: `shapes-groups-align-distribute-layers.mov`  
Recorded: 2026-07-23  
Duration: 16:34  
Status: edited clip set received and integrated 2026-07-23

## Edited clip follow-up

The owner supplied twelve clean, silent source clips. The Help site uses
thirteen visual guides because the two-minute `layers-rename.mp4` source was
split into a focused rename excerpt and a separate covered-object excerpt.

The final demonstrations intentionally differ from the first recording plan in
useful ways:

- The duplication clip shows four methods: keyboard copy/paste, menu
  copy/paste, Option-drag, and Option-Shift-drag to keep the copy aligned.
- Covered-object selection is included rather than deferred.
- Selecting a child inside a group and navigating nested groups are separate
  visual guides.
- Delete and Ungroup remain concise written instructions without dedicated
  clips.
- The supplied `align-section-artboard.mp4` filename is normalized to
  `align-selection-artboard.mp4` in the site assets.

The raw recording is clear and usable. It divides into five task-oriented Help
pages. The article copy below is curated from the narration rather than a
verbatim transcript.

## Editorial map

| Page | Source range | Suggested search terms |
| --- | --- | --- |
| Create and transform shapes | 00:18–03:57 | shape, rectangle, ellipse, polygon, line, pen, draw, resize, rotate, aspect ratio, dimensions, shortcut |
| Use guides and measure spacing | 04:00–05:30 | smart guide, alignment guide, measure, spacing, distance, Option, nudge, arrow key |
| Align and distribute objects | 05:31–06:24 and 10:53–12:21 | align, distribute, selection, artboard, top, bottom, center, horizontal, vertical, equal spacing |
| Organize, duplicate, and delete layers | 06:44–10:48 | layer, order, stack, front, back, duplicate, copy, paste, rename, delete, hidden, covered |
| Group and edit objects | 12:29–15:30 | group, ungroup, nested group, edit inside, select child, Command-click, double-click |

### Exclude or defer

- 00:00–00:18: recording setup and topic naming.
- 01:33–01:46: the Select and Edit Points tools are explained, but point editing
  is not demonstrated. Mention the shortcuts lightly here; cover point editing
  properly with the future Pen/path material.
- 06:24–06:44: color changes used only to prepare the next demonstration.
- 09:45–10:16: an overlapping-object demonstration contains a long pause. The
  concept is useful, but should be rerecorded cleanly.
- 15:31–16:34: pauses and recording wrap-up.

## Clean clip recording plan

All clips should begin on a stable frame, show one understandable result, and
end after the interface settles. Aim for roughly 8–25 seconds each. The longer
group-editing demonstration may run closer to 35 seconds.

### Essential first set

| Filename | Show this action | Raw reference |
| --- | --- | --- |
| `shapes-draw-resize.mp4` | Activate Rectangle with R; click once for a square, then drag another rectangle; resize from an edge and a corner; hold Shift once to preserve its aspect ratio. | 00:41–02:39 |
| `shapes-rotate.mp4` | Move just outside a corner until the rotate cursor appears; rotate freely, then hold Shift to demonstrate 15-degree increments. | 02:40–03:10 |
| `shapes-exact-transform.mp4` | Change position, size, and rotation in Properties; use an arrow key for one unit and Shift-arrow for ten. | 03:11–03:57 |
| `guides-measure-spacing.mp4` | Move one shape until smart alignment guides appear; select it, hold Option, inspect the distance to another shape, then nudge to a round value with an arrow key. | 04:00–04:54 |
| `align-selection-artboard.mp4` | Select two objects; align them to each other, then switch the alignment target to Artboard and align them to the artboard. | 05:31–06:24 |
| `distribute-objects.mp4` | Select three objects, align their centers or edges, then distribute them vertically; finish with a short horizontal-distribution example. | 10:53–12:21 |
| `layers-duplicate.mp4` | Show keyboard copy/paste, menu copy/paste, Option-drag, and Option-Shift-drag to duplicate while keeping the copy aligned. | 06:44–07:51 |
| `layers-reorder.mp4` | Move a layer by dragging it in Layers so the canvas stacking changes; demonstrate Command-] / Command-[ and the Shift variants for front/back. | 07:52–08:54 |
| `layers-rename.mp4` | Rename several layers from Properties so the names update in Layers. Deletion is covered in writing. | 08:55–09:44 and 10:16–10:48 |
| `layers-select-covered.mp4` | Overlap several shapes, then use Layers to select individual covered objects without changing the stacking order first. | 09:45–10:16 |
| `groups-create-move.mp4` | Select several objects, press Command-G, rename and expand the group in Layers, then drag a child on the canvas to move the whole group. | 12:29–13:26 |
| `selecting-items-in-a-group.mp4` | Select a child from Layers, double-click into the group, and Command-click a child directly. | 13:38–14:28 |
| `navigating-nested-groups.mp4` | Double-click through nested groups and use Command-click to reach a deeply nested object directly. Ungrouping is covered in writing. | 14:34–15:28 |

The final source set contains twelve clips; the site derives two focused guides
from the long layer-renaming source.

---

## Draft page: Create and transform shapes

**Summary:** Choose a drawing tool from the toolbar or its keyboard shortcut,
then draw, resize, rotate, and position shapes visually or with exact values.

### Choose a drawing tool

Drawing tools live in the toolbar on the left. Pause over a tool to see its
name and keyboard shortcut.

| Tool | Shortcut |
| --- | --- |
| Rectangle | R |
| Ellipse | O |
| Polygon | G |
| Line | L |
| Pen | P |
| Select | V |
| Edit Points | A |

The Select tool moves and transforms an entire object. Edit Points works with
the individual points that define a shape; point editing is covered separately
with paths.

### Draw a shape

1. Choose a drawing tool or press its shortcut.
2. Click once to create the tool’s default shape. With Rectangle, a single click
   creates a square.
3. Or click and drag to draw the dimensions you want.

After drawing, switch to Select or press V. The selection bounds and handles
appear around the object.

### Resize a shape

Drag an edge handle to change one dimension or a corner handle to change both.
Hold Shift while resizing to preserve the object’s aspect ratio.

### Rotate a shape

Move just outside a corner of the selection until the rotate cursor appears,
then drag around the object’s center. Hold Shift while rotating to snap the
angle to 15-degree increments.

### Enter exact values

Use Properties when the result needs exact position, size, or rotation values.
With a numeric field focused, press an arrow key to change it by one unit or
hold Shift while pressing an arrow key to change it by ten. Enter `0` for the
rotation to return an object to its unrotated angle.

**Related:** Use guides and measure spacing · Align and distribute objects ·
Organize, duplicate, and delete layers

---

## Draft page: Use guides and measure spacing

**Summary:** Smart guides reveal relationships while you move objects. Hold
Option to inspect the distance between a selected object and nearby work, then
nudge the selection to an exact position.

### Align visually with smart guides

Move an object near another object. EXP displays temporary guides when their
edges or centers align, so you can place related objects without calculating
their coordinates first.

### Measure the space between objects

1. Select an object.
2. Hold Option.
3. Move the pointer toward another object to see the distance between them.
4. Use the arrow keys to nudge the selection until the measurement reaches the
   value you want.

An arrow key moves a selected object by one pixel. Hold Shift with the arrow key
to move it by ten pixels.

Measurements are temporary canvas feedback; they do not add permanent guides
or labels to the document.

**Related:** Align and distribute objects · Create and transform shapes · Show
the document grid and snap to it

---

## Draft page: Align and distribute objects

**Summary:** Align selected objects to one another or to their artboard, then
distribute three or more objects with equal spacing.

### Select the objects

Drag a selection rectangle around several objects, or hold Shift while clicking
each object you want to include. Alignment and distribution controls appear in
Properties when multiple objects are selected.

### Align to the selection

With **Selection** as the alignment target, choose an edge or center alignment.
EXP moves the selected objects so their top, bottom, left, right, horizontal
center, or vertical center positions match.

### Align to the artboard

Switch the alignment target to **Artboard** when the selected objects should use
the artboard rather than one another as their reference. Choose the appropriate
edge or center control to position the selection within that artboard.

### Distribute objects evenly

Select three or more objects, then choose horizontal or vertical distribution.
EXP keeps the outer objects in place and gives the objects between them equal
spacing.

Align first when the objects should also share an edge or centerline; distribute
afterward to make their spacing consistent.

**Related:** Use guides and measure spacing · Create and transform shapes ·
Group and edit objects

---

## Draft page: Organize, duplicate, and delete layers

**Summary:** Layers determine what draws in front, provide a reliable way to
select covered objects, and keep growing documents understandable when they are
named deliberately.

### Duplicate an object

Copy and paste places the duplicate in the same position as the original. Use
Command-C and Command-V, or choose Copy and Paste from the Edit menu, then move
the copy to reveal it.

For a visible duplicate-and-move gesture, hold Option while dragging an object;
the plus sign beside the pointer confirms that you are creating a copy. Hold
Shift with Option to constrain the drag horizontally or vertically, keeping the
copy aligned with the original.

### Change the stacking order

Objects higher in Layers draw in front of objects below them. Drag a layer up
or down to change the stacking order, or use these shortcuts:

| Action | Shortcut |
| --- | --- |
| Bring forward one position | Command-] |
| Send backward one position | Command-[ |
| Bring to front | Shift-Command-] |
| Send to back | Shift-Command-[ |

### Rename a layer

Double-click a layer’s name in Layers, or edit its name in Properties. The new
name appears everywhere. Descriptive names make covered objects and complex
documents much easier to navigate.

### Select a covered object

When an object is completely hidden behind another, select its layer in Layers.
You can then edit or nudge it without first changing the stacking order.

### Delete an object

Select an object and press Delete, or choose Delete from the Edit menu. Press
Command-Z or choose Edit > Undo if you remove it accidentally.

**Related:** Group and edit objects · Create and transform shapes · Align and
distribute objects

---

## Draft page: Group and edit objects

**Summary:** Group related objects so they select and move together, while still
keeping each child available for direct editing—even inside nested groups.

### Create a group

1. Select two or more objects.
2. Press Command-G or choose Object > Group.
3. Rename the group in Layers so its purpose remains clear.

Expand the group in Layers to see its children. Clicking a member of the group
on the canvas normally selects the group, allowing the whole set to move as one
object.

### Edit an object inside a group

Use whichever method fits the situation:

- Click the child directly in the expanded Layers list.
- Double-click a child on the canvas to enter the group and select it.
- Hold Command while clicking a child to select it directly through the group.

After selecting the child, move or edit it without moving the entire group.

### Work with nested groups

A group can contain another group. Double-click once to enter the outer group,
then double-click again to reach an object deeper inside it. Command-click is
the shortcut when you want to select the deeply nested object directly.

### Ungroup objects

Select the group and press Shift-Command-G or choose Object > Ungroup. Its
children return to individual layers while keeping their current appearance and
positions.

**Related:** Organize, duplicate, and delete layers · Align and distribute
objects · Create and transform shapes

---

## Editorial questions before publication

1. Confirm whether “Properties” should also index the synonym “Inspector.”
2. The narration describes Command-click as reaching the “root” item; the Help
   draft uses “deeply nested object,” which more accurately describes the
   behavior shown.

## Checks resolved against the app source

- The public tool label is **Edit Points**, and its shortcut is A.
- Distribution requires at least three selected objects, uses the selection’s
  span, and intentionally keeps the two outermost objects fixed.
- The z-order shortcuts in the draft match the Arrange menu definitions.
