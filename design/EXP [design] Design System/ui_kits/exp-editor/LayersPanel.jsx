// LayersPanel — the left dock: a Layers panel (tree) over a Components panel,
// the app's default left arrangement. Built from DS Panel + LayerRow + Badge.
const NS = window.EXPDesignDesignSystem_fb82b2;

function LayersPanel({ doc, selected, onSelect }) {
  const { Panel, LayerRow, Badge, IconButton } = NS;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10, height: "100%" }}>
      <Panel title="Layers" icon="stack-simple" accentTitle style={{ flex: 1, minHeight: 0 }}
        actions={<IconButton icon="dots-three" size="sm" title="Layer options" />}>
        <div style={{ padding: "4px 0" }}>
          {doc.layers.map((l) => (
            <LayerRow key={l.id} name={l.name} kind={l.kind} depth={l.depth}
              expandable={l.expandable} expanded={l.expanded} hidden={l.hidden} locked={l.locked}
              selected={selected === l.id} onSelect={() => onSelect(l.id)} />
          ))}
        </div>
      </Panel>

      <Panel title="Components" icon="squares-four" style={{ flex: "none", height: 132 }} detachable
        actions={<i className="ph ph-caret-down" style={{ fontSize: 13, color: "var(--text-tertiary)" }} />}>
        <div style={{ padding: 10, display: "flex", flexDirection: "column", gap: 8 }}>
          {[["Some component name", "290 × 328 · 2 layers"], ["file-icons", "12 × 11 · 8 layers"]].map(([n, m]) => (
            <div key={n} style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <span style={{ width: 26, height: 26, borderRadius: 5, background: "var(--surface-card)",
                border: "1px solid var(--border-soft)", display: "inline-flex", alignItems: "center",
                justifyContent: "center", color: "var(--text-accent)", flex: "none" }}>
                <i className="ph-fill ph-squares-four" style={{ fontSize: 14 }} />
              </span>
              <div style={{ display: "flex", flexDirection: "column", lineHeight: 1.3, minWidth: 0 }}>
                <span style={{ fontSize: 12, color: "var(--text-primary)", fontWeight: "var(--w-light)",
                  whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{n}</span>
                <span style={{ fontSize: 10, color: "var(--text-tertiary)", fontFamily: "var(--font-mono)" }}>{m}</span>
              </div>
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
}

window.LayersPanel = LayersPanel;
