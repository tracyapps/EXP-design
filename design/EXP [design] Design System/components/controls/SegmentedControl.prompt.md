Pill toggle for 2–4 mutually exclusive options — Selection/Artboard, row/column, Gap/Space-Between.

```jsx
<SegmentedControl
  options={[{value:"selection",label:"Selection"},{value:"artboard",label:"Artboard"}]}
  value={target} onChange={setTarget} />
<SegmentedControl options={[{value:"row",icon:"arrow-right"},{value:"col",icon:"arrow-down"}]}
  value={dir} onChange={setDir} />
```

`fill="accent"` (default) selects with the blue fill; `fill="neutral"` uses a gray fill. Options can carry an `icon` (Phosphor name) instead of/with a label.
