# Inspector and tool-control accessibility audit

Last updated: 2026-08-21 (v2.3 / build 14)

This is the resumable FEAT-037 inventory. A tooltip is supplemental: every
icon-only or abbreviated control also needs a stable programmatic name. Repeated
rows are grouped by their shared component because fixing that component fixes
every instance.

Standards checked:

- [WCAG 2.1 SC 1.4.13 — Content on Hover or Focus](https://www.w3.org/WAI/WCAG21/Understanding/content-on-hover-or-focus.html)
- [WCAG 2.1 SC 1.4.11 — Non-text Contrast](https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html)
- [WCAG 2.1 SC 1.4.1 — Use of Color](https://www.w3.org/WAI/WCAG21/Understanding/use-of-color.html)
- [WAI-ARIA APG — Radio Group Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/radio/)

## Audit table

| Surface / control | Hover or focus help | Accessible name / state | Status |
|---|---|---|---|
| Tools strip buttons | Tool name + keyboard shortcut | Full `Tool.label`; selected trait on active mode | Done |
| Top zoom out / value / in / presets | Full names and shortcuts | Zoom out, Zoom percentage, Zoom in, Zoom presets | Done |
| Top left/right panel buttons | Show/hide description | Dynamic Show/Hide left/right panel names | Done |
| Workspace mode menu | Current workspace in help | Workspace mode + current value | Done |
| Layer lock | Lock/Unlock layer | Dynamic Lock/Unlock layer name | Done |
| X / Y / W / H fields (`DimField`) | Visible label | Programmatic X/Y/W/H name; combined row | Done |
| Layer rotation (`R`) | Rotation definition and degree behavior | Rotation | Done |
| Layer opacity | Opacity range | Layer opacity | Done |
| Flip actions | Full visible Horizontal / Vertical labels | Full action name, including multi-selection scope | Done |
| Align/distribute icon actions | Full operation name | Full operation name; disabled state native | Done |
| Text-alignment icon actions | Full left/center/right name | Full operation name + selected trait | Done |
| Auto Layout on/off | Layout behavior | Auto Layout + switch state | Done |
| Auto Layout direction icons | Horizontal / Vertical layout | Full names + selected state; arrow keys | Done |
| Auto Layout gap | Visible Gap mode | Gap between items | Done |
| Auto Padding on/off | Padding/background behavior | Auto Padding + switch state | Done |
| Padding and margin T/R/B/L fields | Top/Right/Bottom/Left padding or margin | Full side + property name | Done |
| Background corner / stroke width | Visible row labels | Background corner radius / stroke width | Done |
| Paint swatch | Edit fill/background | Edit + visible paint label | Done |
| Gradient stop bar / stop controls | Position, color, delete names | Shared selected stop; selected canvas stop also gets an accent ring | Done in code; live VoiceOver check pending |
| Layout-grid add / show / kind / remove | Full action names | Full grid-specific names | Done |
| Effect add | Add an effect | Add effect | Done |
| Effect enable | Enable/disable explanation | Enable effect + checkbox state | Done |
| Effect kind / color | Visible or picker value | Native picker / color-well semantics | Done |
| Effect shadow fields | Full unabbreviated labels and rich definitions | Horizontal offset, Vertical offset, Blur radius, Spread | Done |
| Effect disclosure / collapsed summary | Expand/Collapse effect; full live settings summary | Dynamic effect name, Expanded/Collapsed value, full summary as expand action | Done in code; live keyboard/VoiceOver check pending |
| Effect actions menu | Duplicate and Remove explanation | Actions for effect; destructive Remove separated from Duplicate | Done |
| Noise advanced fields | Full labels and rich definitions | Frequency, Octaves, Random seed, Monochrome | Done |
| Text-case segments | Per-segment full name | As typed, Uppercase, Lowercase, Capitalize each word, Sentence case; selected trait | Done |
| Font filter rail | Full names + counts | Native exclusive radio-group representation; current state and result count announcements | Done in code; live VoiceOver check pending |
| Font search / clear | Search / clear | Search fonts / Clear font search | Done |
| Font result rows | Family name | Family name + selected trait | Done |
| Point-selection rotation (`R`) | Point rotation definition | Point selection rotation | Done |
| Inspector reset/revert icons | Reset to source | Reset to source | Done |

## Tooltip behavior

`expFieldTip` is the one presenter used by the tools strip and rich Inspector
help. It now:

- appears from hover and keyboard focus;
- remains present while the pointer moves onto the bubble;
- closes immediately when the pointer reaches a different registered control,
  including one geometrically underneath the current bubble;
- dismisses with Escape without moving the pointer;
- remains until hover/focus ends or the control disappears;
- keeps the complete explanation as the VoiceOver accessibility hint at every
  verbosity level;
- supports Full / Standard / Minimal hover copy in Settings, with Option-hover
  temporarily revealing the full explanation.

The bubble is a nonactivating child panel, so making it hoverable does not steal
keyboard focus from the edited field.

## Measured dropdown boundary contrast

Custom popup labels use opaque `EXPColor.borderControl` rather than the former
soft translucent line. WCAG relative-luminance calculations:

| Appearance / adjacent surface | Ratio |
|---|---:|
| Dark panel `#1E1E21` | 5.11:1 |
| Dark raised `#232325` | 4.82:1 |
| Light panel `#FFFFFF` | 5.37:1 |
| Light raised `#F4F4F6` | 4.89:1 |

The same opaque boundary is retained under Increase Contrast, so these ratios do
not decrease. Focus rings remain system-owned.

## Still requires human assistive-technology verification

Static accessibility names, traits, keyboard handlers, announcements, and the
full app build are code-verifiable. The experiential pass still must be performed
with VoiceOver and Accessibility Inspector running: traversal order through Search
→ Filters → results, spoken radio state/counts, focus-triggered rich tips, and the
selected-text announcement when canvas text editing begins. Also visually check
Large interface type, Increase Contrast, light mode, and dark mode. Do not mark
those as verified from source inspection alone.
