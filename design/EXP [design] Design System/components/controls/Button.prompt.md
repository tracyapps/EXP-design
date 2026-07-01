Glass action button — the primary on-canvas/inspector action. Use for confirm/apply, "New Artboard", primary dialog actions.

```jsx
<Button>Apply</Button>
<Button variant="primary" icon="plus">New Artboard</Button>
<Button variant="secondary">Cancel</Button>
<Button variant="ghost" icon="trash">Delete</Button>
<Button variant="destructive">Delete forever</Button>
```

Variants: `primary` (accent glass, default), `secondary` (neutral glass), `ghost` (borderless), `destructive` (red). Sizes `sm | md | lg`. Pass `icon` (Phosphor name) for a leading glyph. Reserve one primary per view.
