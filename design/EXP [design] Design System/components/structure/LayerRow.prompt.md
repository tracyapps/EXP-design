A Layers-panel row. Compose many under a Panel to build the tree; use `depth` for nesting and `expandable`/`expanded` for groups.

```jsx
<LayerRow name="Artboard name" kind="artboard" expandable expanded selected />
<LayerRow name="a text layer." kind="text" depth={1} />
<LayerRow name="expanded group" kind="group" depth={1} expandable expanded />
<LayerRow name="image layer" kind="image" depth={2} locked />
```
