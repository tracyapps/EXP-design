//
//  DesignTokensProof.swift
//  EXP [design]
//
//  Phase 17a PROOF STEP (DEBUG-only). A tiny self-contained view that exercises
//  the token layer before mass adoption: a tokenized primary button + a panel
//  section header + the text tiers + a layer-name row (to confirm SF Compact
//  resolves) + the accent (which follows the system accent / override). Open the
//  Xcode canvas preview and flip the appearance switch to verify light + dark.
//
//  This ships in DEBUG only and is wired nowhere — it's scaffolding for the eye
//  check described in ROADMAP 17a. Safe to delete once 17c lands.
//

#if DEBUG
import SwiftUI

struct DesignTokensProof: View {
    @State private var on = true

    var body: some View {
        VStack(alignment: .leading, spacing: EXPMetric.lg) {

            // Panel title + section label (tracking + uppercase via the modifiers)
            Text("Layers").expPanelTitle()
            Text("Effects").expSectionLabel()

            // Text tiers — hierarchy from opacity
            VStack(alignment: .leading, spacing: EXPMetric.sm) {
                Text("primary — a text layer.").font(.expLabel).foregroundStyle(EXPColor.textPrimary)
                Text("secondary — some shape. huzzah").font(.expLabel).foregroundStyle(EXPColor.textSecondary)
                Text("tertiary — another long layer name…").font(.expLabel).foregroundStyle(EXPColor.textTertiary)
            }

            // Layer-name rows (SF Compact; active = heavier + selection fill)
            VStack(spacing: 0) {
                layerRow("a text layer.", active: false)
                layerRow("layer name", active: true)
                layerRow("expanded group", active: false)
            }
            .background(EXPColor.surfacePanel)
            .clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusRow))

            // Primary button (token accent — follows system accent / override)
            HStack(spacing: EXPMetric.md) {
                primaryButton
                segmentedSample
            }

            Toggle("sample switch", isOn: $on)
                .toggleStyle(.switch)
                .tint(EXPColor.accent)
                .font(.expLabel)
                .foregroundStyle(EXPColor.textSecondary)
        }
        .padding(EXPMetric.panelPadH)
        .frame(width: 280)
        .background(EXPColor.surfaceWindow)
    }

    private func layerRow(_ name: String, active: Bool) -> some View {
        HStack(spacing: EXPMetric.sm) {
            Image(systemName: "eye").font(.system(size: 12)).foregroundStyle(EXPColor.textTertiary)
            Text(name).expLayerName(active: active).foregroundStyle(EXPColor.textPrimary)
            Spacer()
            Image(systemName: "lock.open").font(.system(size: 12)).foregroundStyle(EXPColor.textTertiary)
        }
        .padding(.horizontal, EXPMetric.md)
        .frame(height: 28)               // EXPMetric: layer row height
        .background(active ? EXPColor.rowSelected : Color.clear)
        .overlay(alignment: .leading) {  // active-layer: thick accent bar on the left edge
            if active {
                Rectangle().fill(EXPColor.accent).frame(width: EXPMetric.strokeSelection)
            }
        }
    }

    private var primaryButton: some View {
        Text("New Artboard")
            .font(.system(size: EXPType.base, weight: .medium))
            .foregroundStyle(EXPColor.accentOn)
            .padding(.horizontal, EXPMetric.lg)
            .frame(height: EXPMetric.controlHLg)
            .background(EXPColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusButton))
    }

    private var segmentedSample: some View {
        HStack(spacing: 2) {
            ForEach(["Selection", "Artboard"], id: \.self) { label in
                let isOn = label == "Selection"
                Text(label)
                    .font(.expLabel)
                    .foregroundStyle(isOn ? EXPColor.accentOn : EXPColor.textSecondary)
                    .padding(.horizontal, EXPMetric.sm)
                    .frame(height: EXPMetric.controlH)
                    .background(isOn ? EXPColor.accent : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusField))
            }
        }
        .padding(2)
        .background(EXPColor.surfaceField)
        .clipShape(RoundedRectangle(cornerRadius: EXPMetric.radiusControl))
    }
}

#Preview("Tokens — Dark") {
    DesignTokensProof().preferredColorScheme(.dark)
}
#Preview("Tokens — Light") {
    DesignTokensProof().preferredColorScheme(.light)
}
#endif
