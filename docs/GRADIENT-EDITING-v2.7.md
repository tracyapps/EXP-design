# Gradient editing refinement — October 19, 2026

Development 2.7/build 18. The owner accepts the initial Mesh functionality
(“that works nicely”) and requests these refinements. This revision needs owner
review; full accessibility/display/stress and component/library gates stay open.

October 19 follow-up: the persistent paint surfaces now use normal app ordering,
dismiss on app deactivation and hand off cleanly to pattern editors. This supersedes
the earlier high-window-level behavior. `PATTERN-POLISH-v2.7.md` has fresh receipts
and the remaining physical multi-display/app-switch owner gate.

## Observable changes

- Mesh point buttons use the same filled accent / on-accent foreground as the
  panel's selected segments, with a decorative color dot beside each number.
  Native selected-state traits and stable point names remain present.
- The paint editor stays open during canvas clicks and drags, including across
  floating inspector/canvas windows. Done closes it; Escape closes it when the
  palette has keyboard focus. Escape during a canvas gradient drag restores that
  drag's baseline. The canvas stop-color editor also stays open and follows the
  selected stop; opening the main paint editor replaces that secondary editor.
  Only one primary paint/stop editor is registered at a time. The nested color
  well remains a standard transient color picker.
- Canvas selection updates the Mesh point/gradient stop color and numeric fields.
  External color changes reload color-picker channels; self-authored writes retain
  their authoring coordinates and OKLCH gamut explanation.
- Radial gradients have center, horizontal-radius and vertical-radius handles,
  a dashed ellipse, and stops on the horizontal radius. Center X/Y and Radius X/Y
  percentages provide the keyboard route. Center/end clicks select the first/last
  stop for color editing. Gradient stop context actions work for both kinds.
- Fill navigation uses equally spaced icons and the existing General preference,
  now named **Toolbar and fill-type labels**. Icons-only is compact; labeled mode
  shows icons plus text. Automatic follows the existing VoiceOver policy.
  Popup width accounts for the widest segment and interface type scale; 16-point
  outer padding and additional navigation inset remain in both modes.

## Geometry and persistence

`GradientFill.radial` is optional center/radii in fractions of the fill box.
Absent geometry retains the old centered circle-to-corner native appearance.
Authored radii are independent, so resizing the artwork scales the ellipse with
its bounds. Finite/range checks reject invalid explicit geometry in its decoder.
Linear start/end/angle and existing Paint cases are unchanged.

Native, thumbnail and PDF color/alpha masks share the same radial geometry.
Explicit radial SVG uses standard object-bounding-box coordinates plus an axis
scale/translation matrix; the SVG reader retains those supported axes and stops.
CSS emits an ordinary ellipse with explicit radii/center percentages. Native
appearance copy and document save retain the data.

Boundaries: arbitrary rotated/skewed radial axes, independent focal points and
user-space gradient import remain unsupported and reported. CSS output is checked;
the rendered-HTML reader still does not reconstruct arbitrary radial CSS as an
editable gradient. Design Tokens' existing standard gradient stop export does not
encode geometry; native EXP JSON retains it. The existing SVG omission of artboard
backgrounds is unchanged. No new ARIA or semantic host mapping was introduced.

## Fresh verification

- Unsigned app **and EXPThumbnail** build pass:
  `/tmp/exp-gradient-build-final-20261019.log`.
- `bash scripts/verify_mesh_fill.sh output/a11y/visual-features-20261019/mesh-radial.json`:
  all 14 prior Mesh foundation cases, integrated Mesh/outline/curve checks and new
  off-center elliptical radial checks pass. Radial native/PDF versus browser SVG:
  4/255 opaque, 2/255 translucent; CSS on white: 1/255 for both. SVG own import
  retains geometry. Legacy missing geometry and invalid negative radius are checked.
  `/tmp/exp-gradient-render-final-20261019.log`.
- Existing semantic Handoff goldens, appearance copy/codec and interface preference
  persistence/override checks pass:
  `/tmp/exp-gradient-semantic-20261019.log`,
  `/tmp/exp-gradient-appearance-20261019.log`,
  `/tmp/exp-gradient-preferences-20261019.log`.
- Existing effect export coverage and SVG pattern checks:
  `/tmp/exp-gradient-effects-20261019.log`,
  `/tmp/exp-gradient-patterns-20261019.log` (results checked before handoff).
- `verify_transient_surface_levels.sh` passes its source contract. Its old four
  transient-popover expectation was updated for three plus the explicit paint
  host. Its obsolete floating-tray assertion now matches the already-shipped
  document-level tray policy; the separate floating snap indicator is unchanged.
- **Actual isolated native app:** clicking Mesh point 3 while the popup is open
  selects button 3 and displays X25/Y90/radius0.65/opacity0.8. A physical point drag
  updates X/Y; one Undo restores both. Radial center dragging updates center fields;
  one Undo restores 50/50. Dragging the Y radius selects the last color stop,
  changes Radius Y, and one Undo restores it. The editor stays visible throughout.
  Its existing nested color/session grouping and full VO/FKA matrix need owner review.
- Visual inspection caught wrapped fill labels, then confirmed the spacing fix in
  icons-only, icons/text and Extra Large + larger-target modes. Evidence:
  `output/a11y/visual-features-20261019/paint-icons.png`,
  `paint-labels-and-points.png`, `paint-extra-large.png` and `paint-ax.txt`.
  The final color write/reload guard subsequently compiles; gamut interaction is
  source-reviewed, not claimed as a new full native gamut test.

The sandboxed fixture used a separate bundle/preferences identity, generated
artwork, disabled updater/network access and no document type registration. Only
that agent-owned app process was stopped. Owner app, documents and preferences
were not changed. No push, deployment or release actions.

## Official API/naming references

Apple says an application-defined popover makes the app responsible for closing
it; the explicit Done action and scoped cancellation provide that route:
https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum/applicationdefined

Native descriptive names and selected state follow:
https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-1d7jv
https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected

These were checked from Apple's documentation JSON; this is not full AT certification.

## Owner review

Rebuild in Xcode. Try Mesh and linear/radial canvas selection with the popup open,
change colors and numbers, drag both radial radii, Undo/Escape and save/reopen.
Compare your exports and check the preference in General, including your normal
panel arrangement, display sizes and keyboard/VoiceOver workflow.
