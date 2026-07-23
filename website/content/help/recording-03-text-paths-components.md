# Help content draft 03 — text, paths, buttons, and components

Source: `a-whole-lotta-stuff-and-bugs.mov`  
Recorded: 2026-07-23  
Duration: 42:16  
Status: transcribed and curated; awaiting clean silent clips

The recording is very usable. It naturally divides into six task-oriented Help
pages rather than one long tutorial. The copy below is curated from the owner's
narration, corrected against the app source, and intentionally not verbatim.

Two demonstrations exposed real product bugs:

- **BUG-005 (P2):** Shift does not constrain a new Pen curve handle. Existing
  handles already snap to axis/45-degree increments when Shift is held.
- **BUG-006 (P1):** typography and opacity edits made in an active component
  state mutate the shared source instead of remaining local to that state.

The component-state clip should wait for BUG-006. The Pen-curves clip can either
omit Shift temporarily or, preferably, wait for BUG-005. Every other clip can be
recorded independently now.

## Editorial map

| Page | Source range | Suggested search terms |
| --- | --- | --- |
| Create and format text | 00:30–06:54 | text, type, point text, text box, wrap, overflow, font, weight, size, color, line height, tracking, case, alignment, semantic content |
| Draw shapes and lines | 07:30–10:14 | rectangle, ellipse, polygon, line, sides, stroke, draw, click, drag, shortcut |
| Draw and edit vector paths | 10:20–20:19 | outline stroke, pen, path, point, anchor, curve, Bézier, handle, add point, delete point, convert to path, edit points |
| Build an accessible responsive button | 20:35–27:26 | button, corner radius, border, stroke, shadow, contrast, accessibility, auto padding, margin, auto width |
| Create and reuse components | 27:40–34:50 | component, source, instance, override, create component, edit component, category, role, link, button, handoff |
| Add states and manage component instances | 34:53–42:00 | state, hover, pressed, focus, disabled, custom state, contrast, component panel, instances, select all, previous, next, center, drag instance |

### Exclude or defer

- 00:00–00:30: setup and choosing the first topic.
- 03:42–04:03: uncertainty while explaining the line-height controls. The
  corrected explanation appears in the draft below.
- 06:54–07:30 and 08:22–08:40: pauses and transitions between topics.
- 10:33–10:51: menu-search pause while locating Outline Stroke.
- 13:44–14:13: the failed Shift-constrain demonstration is the BUG-005 repro.
- 17:22–17:42 and 18:28–18:37: pauses and a restarted explanation.
- 20:19–21:18: setup for the button example.
- 22:32–22:48: temporary pan confusion, immediately self-corrected; not a bug.
- 27:26–27:40, 29:18–30:00, and 31:50–32:02: setup/repositioning pauses.
- 37:17–38:45: BUG-006 reproduction. Do not use it as instructional footage.
- 39:28–40:42 and 42:00–42:16: pauses and recording wrap-up.

## Clean clip recording plan

Aim for one visible outcome per clip, usually 8–25 seconds. A component source-
editing clip may run closer to 35 seconds. Start and end on stable frames and
leave a short settled beat after the result.

| Filename | Show this action | Raw reference | Readiness |
| --- | --- | --- | --- |
| `text-point-area.mp4` | Press T; click once for auto-width text, then drag a text box that wraps. Resize the box until the overflow `+` appears, then switch it back to Auto width. | 00:30–02:25 | Ready |
| `text-typeface-size-color.mp4` | Change the typeface; choose a face/weight when the family provides one; change size with typing and Shift-arrow; change text color. | 02:27–03:21 | Ready |
| `text-line-letter-spacing.mp4` | On multiline text, compare Auto, ×, px, and em line height; then use positive and negative Spacing values to loosen and tighten letters. | 03:24–05:12 | Ready |
| `text-case-alignment.mp4` | Cycle As typed, UPPERCASE, lowercase, Capitalize Each, and Sentence case; demonstrate left, center, and right alignment on a text box. | 05:13–05:55 | Ready |
| `text-semantic-content.mp4` | Change Content from Plain text to Heading 1 or Paragraph and state visually that this changes handoff semantics, not the appearance. | 06:07–06:54 | Ready |
| `shapes-basic-tools.mp4` | With Rectangle, Ellipse, and Line, show click-once defaults and click-drag custom dimensions; finish by changing the line's stroke width and color. | 08:40–10:14 | Ready |
| `polygon-sides.mp4` | Press G; click once for the default triangle; change Sides with the field and arrow keys. | 07:30–08:22 | Ready |
| `path-outline-stroke.mp4` | Draw a line, choose Object > Path > Outline Stroke, switch to Edit Points, and move one resulting point. | 10:20–11:19 | Ready |
| `pen-straight-path.mp4` | Press P; click several corner anchors; click the first anchor to close the path; switch between Select and Edit Points. | 11:30–13:07 | Ready |
| `pen-curved-path.mp4` | Click-drag anchors to pull Bézier handles, mix curved and corner anchors, then close and fill the path. Include Shift-constrained handles after BUG-005. | 13:11–15:26 | **Blocked by BUG-005** |
| `path-edit-points.mp4` | Select one anchor, Shift-select additional anchors, nudge or drag them together, clear the point selection, then convert a corner to smooth and back from the context menu. | 15:28–17:19 | Ready |
| `path-convert-shape.mp4` | Draw an ellipse or polygon, choose Object > Path > Convert to Path, move an anchor, then add and remove an anchor with Pen. | 17:42–20:19 | Ready |
| `button-style-contrast.mp4` | Give a rectangle rounded corners, a stroke, and a shadow; place text above it; use the contrast result to replace a failing text color with a passing one. | 21:18–23:32 | Ready |
| `button-auto-padding.mp4` | Center the label and background, group them, turn on Auto Padding, adjust the four padding values, and show the background re-hugging after the auto-width label changes. Briefly show Margin separately. | 23:42–27:26 | Ready |
| `component-create-overrides.mp4` | Select the button group, press Command-K, rename the source, create several instances, and give their public text override different labels. | 27:40–30:46 | Ready |
| `component-edit-source.mp4` | Open the component source, change shared padding and the background paint, close the editor, and show every instance updating while text overrides remain. | 30:50–33:15 | Ready |
| `component-semantics-states.mp4` | Set the source category to Link; create Hover and Disabled states; edit state-local styling; use the live contrast result; switch instances between states. | 33:17–39:28 | **Blocked by BUG-006** |
| `component-find-instances.mp4` | In Components list view, select all instances from the count, page previous/next through them (including an offscreen instance), drag out a new instance, single-click to open the source, and double-click to rename. | 40:42–42:00 | Ready |

This is eighteen short clips. If that feels like too much in one sitting, record
the five text clips first, then paths, then buttons/components. The filenames
are the organizing system; recording order does not matter.

---

## Draft page: Create and format text

**Summary:** Create a line that grows with its content or a fixed-width text box
that wraps, then control its visual styling and semantic purpose from Properties.

### Create auto-width text or a text box

Choose Text in the toolbar or press T.

- Click once to create **Auto width** text. Its width grows and shrinks with the
  characters you type.
- Click and drag to create a **Text box**. Its width remains fixed and the text
  wraps inside it.

Resize a text box to change where its lines wrap. A `+` overflow indicator means
the box contains text that does not currently fit. Increase the box height or
switch to Auto width to reveal the hidden content.

### Choose a typeface, face, size, and color

Select the text, then use the Type section in Properties. Choose a typeface
family first. When that family contains multiple faces or weights, a second
menu appears below it. Families without additional faces do not show that menu.

Enter an exact type size or use an arrow key to change the focused value by one.
Hold Shift while pressing an arrow key to change it by ten. Choose Color to set
the text color.

### Adjust line height and letter spacing

The **Line** control offers four ways to describe line height:

| Unit | Meaning |
| --- | --- |
| Auto | Use the font's natural line height. |
| × | Multiply the font's natural line height by a unitless value. |
| px | Use an exact line height in pixels. |
| em | Multiply the text's font size; `1em` equals the current font size. |

The **Spacing** field controls letter spacing, also called tracking, in pixels.
Use a positive value to spread characters apart or a negative value to bring
them closer together. It changes spacing between letters, not only between words.

### Change case and alignment

Case changes how text is displayed without requiring you to retype it: As typed,
UPPERCASE, lowercase, Capitalize Each, or Sentence case.

For a text box, choose left, center, or right alignment to position each line
inside the box.

### Describe the text for handoff

Use **Content** to describe the text's semantic purpose, such as Plain text,
Paragraph, or Heading 1. This does not change its visual styling. It gives HTML
handoff enough information to produce a more meaningful element instead of
making an implementer infer structure from font size alone.

**Related:** Build an accessible responsive button · Create and reuse components
· Create and transform shapes

---

## Draft page: Draw shapes and lines

**Summary:** Use the basic drawing tools for rectangles, ellipses, polygons, and
lines, then adjust the properties unique to polygons and lines.

### Draw a rectangle, ellipse, or line

Choose a tool or press its shortcut:

| Tool | Shortcut | Click once | Click and drag |
| --- | --- | --- | --- |
| Rectangle | R | Creates the default square. | Creates a rectangle at the dimensions you drag. |
| Ellipse | O | Creates the default circle. | Creates an ellipse at the dimensions you drag. |
| Line | L | Creates the default horizontal line. | Creates a line between the start and end points. |

A line has no fill. Use Stroke in Properties to change its color and width.

### Draw a polygon and change its sides

Choose Polygon or press G. A new polygon begins with three sides. Change **Sides**
in Properties to turn it into a quadrilateral, pentagon, or another regular
polygon. With the field focused, use the arrow keys to add or remove sides.

After drawing, polygons support the same selection, sizing, rotation, paint,
stroke, and effects controls as other closed shapes.

**Related:** Draw and edit vector paths · Create and transform shapes · Organize,
duplicate, and delete layers

---

## Draft page: Draw and edit vector paths

**Summary:** Draw straight and curved paths with Pen, edit individual anchors
and handles, or convert an existing shape or stroke into editable path geometry.

### Turn a stroke into a filled path

Select a stroked line or shape, then choose **Object > Path > Outline Stroke**.
EXP replaces the stroke with ordinary filled path geometry. Choose Edit Points
or press A to move its anchors individually.

Outline Stroke is useful when the former stroke needs to scale as geometry or
be edited as a custom silhouette.

### Draw a path with corner points

Choose Pen or press P. Click to place each corner anchor. Continue clicking to
build the path, then click the first anchor again to close it. A closed path can
use a fill like any other closed shape.

Use Select (V) to move the complete path. Use Edit Points (A) to change its
individual anchors.

### Draw curves with Bézier handles

With Pen active, click and drag while placing an anchor to pull a pair of curve
handles. The direction and length of the handles control how the curve enters
and leaves that anchor. A longer handle produces a stronger, broader bend.

Click without dragging when the next anchor should be a corner. Mix corner and
smooth anchors in the same path, then click the first anchor to close it.

After BUG-005 is fixed, hold Shift while pulling a new handle to constrain it
to axis/45-degree increments.

### Add, remove, and select points

With Pen active, the pointer shows a plus over a path segment and a minus over
an existing anchor. Click the segment to add an anchor or click the anchor to
remove it.

With Edit Points active, click an anchor to select it. Hold Shift while clicking
to select additional anchors, then drag or nudge the selected points together.
The filled anchors are selected; hollow anchors are not. Click away from the
path to clear the point selection.

Right-click an anchor to convert it between a corner and smooth point. Smooth
points expose curve handles; corner points do not.

### Convert a shape to a path

Select a rectangle, ellipse, polygon, or line, then choose **Object > Path >
Convert to Path**. Its appearance remains, but Edit Points can now reshape its
anchors and Pen can add or remove points.

**Related:** Draw shapes and lines · Create and transform shapes · Group and edit
objects

---

## Draft page: Build an accessible responsive button

**Summary:** Style a button surface, verify its text contrast, and use Auto
Padding so its background follows an auto-width label.

### Style the button surface

Draw a rectangle and increase its corner radius. Add a stroke for a border and
an effect for a shadow. Place an auto-width text label above the rectangle, then
select both objects and align their horizontal and vertical centers.

### Check text contrast

Select the text above its colored background. EXP reports the foreground and
background contrast in the accessibility result. If the current color is below
the required ratio, choose a lighter or darker text color until the result passes.

Contrast is not a substitute for testing every interaction state, text size,
and real implementation, but it catches a common accessibility failure while
the colors are still being chosen.

### Make the background follow its label

1. Select the label and background and press Command-G.
2. Turn on **Auto Padding** for the group.
3. Adjust the top, right, bottom, and left padding between the content and its
   background.
4. Edit the label and confirm the background re-hugs the new text width.

Keep the label in **Auto width** mode. A fixed text box will not grow and shrink
with the number of characters in the same way.

Margin adds invisible space outside the framed content. Use padding to control
space inside the background; use margin to describe the clear space the group
should keep around itself.

**Related:** Create and format text · Create and reuse components · Align and
distribute objects

---

## Draft page: Create and reuse components

**Summary:** Turn a finished group into a reusable component, customize public
content on each instance, and update every instance by editing its source once.

### Create and name a component

Select the finished group, then press Command-K, choose **Object > Component >
Create Component**, or choose Create Component from its context menu. The object
becomes an instance linked to a component source, and that source appears in the
Components panel.

Rename the component for its purpose, such as `Primary button`. A descriptive
source name is more useful than the group's original generic name.

### Customize an instance with overrides

Create or duplicate several instances. In Properties, change a public text
override to give each instance its own label. The instance remains connected to
the same source while its exposed content differs.

### Edit the shared source

Open the component source from an instance or the Components panel. Changes in
the source editor update every connected instance. For example, reduce shared
padding or replace the background paint once instead of editing every button.

Close the source editor when finished; changes are saved as you make them.
Instance text overrides remain intact when unrelated shared styling changes.

### Assign a meaningful category

Choose the category that matches what the component does. A control that submits,
saves, or closes is a **Button**; something that navigates to another location is
a **Link**.

The category supplies semantic intent for handoff and export. It does not turn a
static canvas object into an interactive control by itself, but it allows the
generated HTML and accessibility information to start with the correct role.

**Related:** Add states and manage component instances · Build an accessible
responsive button · Create and format text

---

## Draft page: Add states and manage component instances

**Summary:** Represent hover, pressed, focus, disabled, or custom component
states, check each state's contrast, and find every instance from Components.

### Add and edit a state

Open the component source. The states bar begins with Default. Use the add menu
to create Hover, Pressed, Focus, Disabled, or a custom state. Switch to a state
before changing the properties that should differ from Default.

State-local typography and opacity instructions must not be published until
BUG-006 is fixed. Today those edits can change the shared source and every state.

### Check every visual state

The source editor's contrast result updates as you switch states. Treat each
state as its own accessibility check: a passing Default color does not guarantee
that Hover, Focus, Pressed, or Disabled also passes.

Select an instance on the canvas and choose one of the source's states in
Properties to preview that state in the design.

### Select or page through every instance

In Components list view, the instance count shows how many copies of a source
exist on the canvas. Activate the count to select them all. Use the previous and
next controls to page through individual instances. When the next instance is
offscreen, EXP centers it in the viewport automatically.

Drag a component from the panel onto the canvas to create another instance.
Single-click a list row to open its source editor; double-click it to rename the
component.

**Related:** Create and reuse components · Build an accessible responsive button
· Pan, zoom, and center your work

---

## Checks resolved against the app source

- Text line-height `×` is a unitless multiplier of the font's natural line
  height; `em` is relative to the font size. The Spacing field is pixel tracking
  between characters, not word spacing.
- Text Content is explicitly labeled as semantic page-role information for HTML
  handoff and is independent of visual Type Style.
- Create Component is Command-K and lives under Object > Component.
- Existing Bézier-handle editing already Shift-snaps to axis/45-degree increments;
  only new-handle creation drops the modifier (BUG-005).
- Component state capture currently stores only text strings, fills, and layer
  visibility. Typography and opacity fall through to the shared base (BUG-006).
- The Components list row uses single-click to open and double-click to rename.
  Its count selects all instances; paging selects one and centers it only when it
  is outside the visible document rectangle.
