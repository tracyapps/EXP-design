# Application typography

Layer titles and rename fields use the macOS system font through SwiftUI's
`.system(size:weight:)` API: 12 pt, standard width, Regular for ordinary rows
and Medium for the active row. The OS chooses the appropriate typeface and
language fallback (SF Pro for the Latin UI). No font binaries are bundled or
registered by EXP. Document font values are unchanged.

Apple supports system fonts through its font APIs and prohibits embedding
copies of downloadable Apple font files:
https://developer.apple.com/documentation/technologyoverviews/fonts

The SF Compact and Barlow trials were superseded by the owner's standard-width
system-font selection on October 16, 2026. Inspect new signed release artifacts;
historical release ZIPs remain immutable.
