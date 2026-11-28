import SwiftUI

struct MuscleSelectView: View {
    let person: Athlete?
    var onMeasure: (MeasurementKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State var view: MyohmMuscle.BodyView = .front
    @State var muscle: MyohmMuscle = .quadriceps
    @State var side: LimbSide = .right
    @State var band = 100

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(kicker: person.map { L("\($0.fullName) · local measurement") }, title: L("Which muscle?"), back: { dismiss() })

                VStack(spacing: 10) {
                    PillSegmented(options: [(MyohmMuscle.BodyView.front, L("Front")), (.back, L("Back"))], selection: $view)
                    ZStack(alignment: .top) {
                        BodyMap(view: view, muscle: muscle, side: side) { tapped, tappedSide in
                            withAnimation(.snappy) { pick(tapped, side: tappedSide) }
                        }
                        .frame(height: 360)
                        HStack {
                            Text(view == .front ? L("RIGHT") : L("LEFT"))
                            Spacer()
                            Text(view == .front ? L("LEFT") : L("RIGHT"))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MyohmColor.muted)
                        .padding(6)
                    }
                    PillSegmented(options: view == .front
                        ? [(LimbSide.right, LimbSide.right.name), (.left, LimbSide.left.name)]
                        : [(LimbSide.left, LimbSide.left.name), (.right, LimbSide.right.name)], selection: $side)
                }
                .myohmCard(padding: 14)

                FlowLayout(spacing: 8) {
                    ForEach(MyohmMuscle.allCases) { item in
                        ChipButton(title: item == .other ? L("Other…") : item.name, selected: muscle == item) {
                            withAnimation(.snappy) { pick(item, side: side) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L("Band")).font(MyohmFont.headline)
                        Spacer()
                        Text(L("Distance between V+ and V−")).font(.system(size: 12)).foregroundStyle(MyohmColor.muted)
                    }
                    HStack(spacing: 8) {
                        ForEach([50, 75, 100, 150], id: \.self) { mm in
                            bandButton(mm)
                        }
                    }
                    Text(bandHint).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                }
                .myohmCard()

                Button(muscle == .other ? L("Measure") : L("Measure · \(muscle.name.lowercased()) \(side.name.lowercased())")) {
                    onMeasure(.muscle(muscle, side, band: band))
                }
                .buttonStyle(MyohmPrimaryButton())
            }
            .padding(20)
        }
        .background(MyohmColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var bandHint: String {
        muscle == .other
            ? L("Choose the band that covers the muscle belly without reaching the tendon.")
            : L("Centre the band on the muscle belly. Always use the same band on this muscle to compare measurements.")
    }

    private func pick(_ item: MyohmMuscle, side newSide: LimbSide) {
        muscle = item
        side = newSide
        if let suggested = item.suggestedBand { band = suggested }
        if let v = item.view { view = v }
    }

    private func bandButton(_ mm: Int) -> some View {
        let selected = band == mm
        return Button { band = mm } label: {
            VStack(spacing: 0) {
                Text("\(mm)").font(.system(size: 18, weight: .bold))
                Text("mm").font(.system(size: 11)).opacity(0.8)
                if muscle.suggestedBand == mm {
                    Text(L("Suggested")).font(.system(size: 10, weight: .semibold)).padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(selected ? .white : MyohmColor.ink)
            .background(selected ? MyohmColor.brand : MyohmColor.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(MyohmPlainButton())
        .accessibilityLabel(L("\(String(mm)) millimetre band"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Anatomical illustration with tappable muscle zones.
struct BodyMap: View {
    let view: MyohmMuscle.BodyView
    let muscle: MyohmMuscle
    let side: LimbSide
    var onTap: (MyohmMuscle, LimbSide) -> Void

    private static let canvas = CGSize(width: 520, height: 1000)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.canvas.width, proxy.size.height / Self.canvas.height)
            let size = CGSize(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
            let origin = CGPoint(x: (proxy.size.width - size.width) / 2, y: (proxy.size.height - size.height) / 2)
            ZStack(alignment: .topLeading) {
                Image(view == .front ? "body-front" : "body-back", bundle: .module)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .accessibilityHidden(true)
                ForEach(MyohmMuscle.allCases.filter { $0.view == view }) { item in
                    ForEach(0..<item.outlines.count, id: \.self) { index in
                        ZoneView(
                            muscle: item,
                            side: index == 0 ? .right : .left,
                            outline: item.outlines[index],
                            scale: scale,
                            selected: item == muscle && (index == 0 ? LimbSide.right : .left) == side,
                            onTap: onTap
                        )
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .offset(x: origin.x, y: origin.y)
        }
    }
}

/// Smooth closed outline through the traced points (Catmull–Rom converted to Bézier).
struct MuscleOutline: Shape {
    let points: [CGPoint]
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p = points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        guard p.count > 2 else { return path }
        path.move(to: p[0])
        for i in 0..<p.count {
            let p0 = p[(i - 1 + p.count) % p.count], p1 = p[i], p2 = p[(i + 1) % p.count], p3 = p[(i + 2) % p.count]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}

private struct ZoneView: View {
    let muscle: MyohmMuscle
    let side: LimbSide
    let outline: [CGPoint]
    let scale: CGFloat
    let selected: Bool
    var onTap: (MyohmMuscle, LimbSide) -> Void

    var body: some View {
        let shape = MuscleOutline(points: outline, scale: scale)
        let fill: Color = selected ? MyohmColor.brand.opacity(0.55) : MyohmColor.chartBlue.opacity(0.12)
        let stroke: Color = selected ? .white : MyohmColor.chartBlue.opacity(0.35)
        shape
            .fill(fill)
            .overlay(shape.stroke(stroke, lineWidth: selected ? 2 : 1))
            .contentShape(shape)
            .onTapGesture { onTap(muscle, side) }
            .accessibilityElement()
            .accessibilityLabel(muscle.name + " " + side.name.lowercased())
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
