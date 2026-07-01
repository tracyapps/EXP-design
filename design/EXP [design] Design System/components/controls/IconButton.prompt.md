Borderless square glyph button — toolbars, inspector affordances, the left tools strip. `active` gives the accent-tinted highlight (and switches the glyph to Phosphor "fill").

```jsx
<IconButton icon="cursor" active title="Select" />
<IconButton icon="magnifying-glass-plus" title="Zoom in" />
<IconButton icon="sidebar-simple" title="Toggle panel" />
```

Sizes `sm | md | lg`. Always pass `title` (becomes tooltip + aria-label). For the tools strip use `lg`.
