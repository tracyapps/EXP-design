Liquid-glass panel shell — the dock/floating panel container (Layers, Properties, Components). Header is an uppercase title with an icon and a detach affordance.

```jsx
<Panel title="Layers" icon="stack-simple" accentTitle>
  <LayerRow name="Artboard 1" kind="artboard" selected />
</Panel>
<Panel title="Properties" icon="sliders-horizontal" material="medium">…</Panel>
```

`material`: thin (tray) · medium (dock, default) · thick (modal). Pass `actions` for trailing header controls.
