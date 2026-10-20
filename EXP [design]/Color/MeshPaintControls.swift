import SwiftUI

/// The same stable point selection is shared with the on-object handles.
struct MeshPaintControls: View {
    @Binding var mesh: MeshFill
    @Binding var selection: UUID?
    var supportsOpacity = true
    var gesture: (Bool) -> Void = { _ in }
    private func value(_ id: UUID, _ key: WritableKeyPath<MeshPoint,Double>, range: ClosedRange<Double>) -> Binding<Double> {
        Binding(get: { mesh.points.first { $0.id == id }?[keyPath: key] ?? range.lowerBound },set: { value in
            guard value.isFinite, let i = mesh.points.firstIndex(where: { $0.id == id }) else { return }
            mesh.points[i][keyPath: key] = min(range.upperBound,max(range.lowerBound,value))
        })
    }
    private func coordinate(_ id: UUID, x: Bool) -> Binding<Double> {
        Binding(get: { let p = mesh.points.first { $0.id == id }?.position ?? .zero; return Double(x ? p.x : p.y) * 100 },set: { v in
            guard v.isFinite, let i = mesh.points.firstIndex(where: { $0.id == id }) else { return }
            let p = min(300,max(-200,v))/100
            if x { mesh.points[i].position.x = p } else { mesh.points[i].position.y = p }
        })
    }
    private func radius(_ id: UUID,y: Bool) -> Binding<Double> {
        Binding(get: {
            guard let p = mesh.points.first(where: { $0.id == id }) else { return 0 }
            return (y ? p.radiusY ?? p.radius : p.radius)*100
        },set: { value in
            guard value.isFinite,let i = mesh.points.firstIndex(where: { $0.id == id }) else { return }
            // Freeze the other axis before editing X so both controls are independent.
            var next = mesh
            if next.points[i].radiusY == nil { next.points[i].radiusY = next.points[i].radius }
            if y { next.points[i].radiusY = min(4,max(0.005,value/100)) }
            else { next.points[i].radius = min(4,max(0.005,value/100)) }
            mesh = next
        })
    }
    private func angle(_ id: UUID) -> Binding<Double> {
        Binding(get: { mesh.points.first(where: { $0.id == id })?.angle ?? 0 },set: { value in
            guard value.isFinite,let i = mesh.points.firstIndex(where: { $0.id == id }) else { return }
            mesh.points[i].angle = RadialGradientGeometry.wrappedAngle(value)
        })
    }
    private func field(_ label: String, _ binding: Binding<Double>, suffix: String = "",step: Double = 1) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer(minLength: 4)
            TextField(label,value: binding,format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.exp).frame(width: 88).numericStepping(binding,step: step)
                .accessibilityLabel(Text("Mesh point \(label)\(suffix == "%" ? ", percent" : suffix == "°" ? ", degrees" : "")"))
            Text(suffix).font(.caption)
        }
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            PaintSwatch(paint: .mesh(mesh)).frame(height: 70)
            ColorWell(label: "Base",color: $mesh.base,supportsOpacity: supportsOpacity,onEditingChanged: gesture)
            HStack {
                Text("Color points").font(.caption)
                Spacer()
                Button("Add") { add() }.disabled(mesh.points.count >= MeshFill.maximumPoints)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 4),count: 4),spacing: 4) {
                ForEach(Array(mesh.points.enumerated()),id: \.element.id) { i,p in
                    Button { selection = p.id } label: {
                        HStack(spacing: 6) {
                            Circle().fill(p.color.swiftUI).frame(width: 10,height: 10)
                                .overlay(Circle().strokeBorder(EXPColor.textSecondary.opacity(0.6),lineWidth: 1))
                                .accessibilityHidden(true)
                            Text("\(i+1)").font(.expLabel)
                        }
                        .frame(maxWidth: .infinity,minHeight: EXPInterfaceAccessibility.shared.targetHeight(24))
                        .foregroundStyle(selection == p.id ? EXPColor.accentForeground : EXPColor.textSecondary)
                        .background(selection == p.id ? EXPColor.accent : EXPColor.surfaceField,
                                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusControl-2))
                        .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Mesh point \(i+1)"))
                        .accessibilityAddTraits(selection == p.id ? .isSelected : [])
                }
            }
            if let id = selection, let i = mesh.points.firstIndex(where: { $0.id == id }) {
                ColorWell(label: "Point",color: Binding(get: { mesh.points.first { $0.id == id }?.color ?? .white },set: { c in
                    if let index = mesh.points.firstIndex(where: { $0.id == id }) { mesh.points[index].color = c }
                }),onEditingChanged: gesture)
                field("X",coordinate(id,x: true),suffix: "%")
                field("Y",coordinate(id,x: false),suffix: "%")
                field("Radius X",radius(id,y: false),suffix: "%")
                field("Radius Y",radius(id,y: true),suffix: "%")
                field("Angle",angle(id),suffix: "°")
                field("Opacity",value(id,\.opacity,range: 0...1),step: 0.01)
                HStack {
                    Button("Back") { move(id,by: -1) }.disabled(i == 0)
                    Button("Front") { move(id,by: 1) }.disabled(i == mesh.points.count-1)
                    Spacer(minLength: 2)
                    Button("Remove") { mesh.points.removeAll { $0.id == id }; selection = mesh.points.first?.id }
                }.font(.caption)
            }
            Text("Up to 8 layered radial points. Radii are percentages of width and height; angle turns the ellipse. Point order is back to front.")
                .font(.caption).foregroundStyle(EXPColor.textSecondary).fixedSize(horizontal: false,vertical: true)
        }.onDisappear { gesture(false) }
    }
    private func move(_ id: UUID,by delta: Int) {
        guard let i = mesh.points.firstIndex(where: { $0.id == id }),mesh.points.indices.contains(i+delta) else { return }
        mesh.points.swapAt(i,i+delta)
    }
    private func add() {
        guard mesh.points.count < MeshFill.maximumPoints else { return }
        let point = MeshPoint(position: CGPoint(x: 0.5,y: 0.5),radius: 0.65,color: RGBAColor(r: 0.6,g: 0.2,b: 1,a: 1))
        mesh.points.append(point); selection = point.id
    }
}
