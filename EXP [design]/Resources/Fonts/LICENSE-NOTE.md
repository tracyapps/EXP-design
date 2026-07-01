# Bundled fonts — license note

These are **Apple SF Compact Display** weights (Ultralight, Light, Regular,
Medium, Semibold), embedded so EXP's condensed "layer name" voice renders the
same on every Mac (SF Compact is not guaranteed system-installed; SF Pro / SF
Mono are, and are NOT bundled).

⚠ **Apple's SF font license** permits using the system fonts to design and build
UIs for Apple platforms, but **restricts redistributing the font files**.
Embedding them in a shipping app is redistribution. This is fine for a personal
build; **before distributing EXP**, either confirm an acceptable license path or
swap the condensed voice to an open-licensed (SIL OFL) condensed face.

**Single switch-point:** `EXPType.layerFont(size:)` in `UI/DesignTokens.swift`.
Change that one function (and remove these files + the registration call in
`UI/FontRegistration.swift`) to move off the bundled Apple face.

Source: `design/EXP [design] Design System/fonts/` (the design-system export).
