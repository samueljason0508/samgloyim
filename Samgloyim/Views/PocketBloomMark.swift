import SwiftUI

extension Palette {
    /// The logo's leaf green. Light enough to read as a second tone against cream, which
    /// `forest` is not — it sits only a shade off `ink`.
    static let sprout = Color(hex: 0x6B9457)
}

/// The PocketBloom mark: a leaf growing out of a back pocket.
///
/// Drawn rather than shipped as an image so it stays crisp at any size and can be recoloured
/// per placement. Geometry is authored on a 64×64 grid and scaled to whatever frame it is given.
struct PocketBloomMark: View {
    var pocket: Color = Palette.forest
    var leaf: Color = Palette.lime
    /// The hem and stitching read as cut-outs, so this should match what sits behind the mark.
    var cut: Color = Palette.background

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 64
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }

            var sprout = Path()
            sprout.move(to: point(32, 28))
            sprout.addCurve(to: point(48, 5), control1: point(31, 17), control2: point(37, 8))
            sprout.addCurve(to: point(32, 28), control1: point(49.5, 16.5), control2: point(42, 27.5))
            sprout.closeSubpath()
            context.fill(sprout, with: .color(leaf))

            // The vein is what makes the shape read as a leaf rather than a blob.
            var vein = Path()
            vein.move(to: point(32, 28))
            vein.addCurve(to: point(45, 9), control1: point(32.5, 20), control2: point(37, 13))
            context.stroke(vein, with: .color(pocket),
                           style: StrokeStyle(lineWidth: 1.9 * unit, lineCap: .round))

            // Tapered sides and a V bottom are what make this read as a pocket rather than a box.
            var body = Path()
            body.move(to: point(12, 28))
            body.addLine(to: point(52, 28))
            body.addLine(to: point(49.5, 46))
            body.addLine(to: point(32, 57))
            body.addLine(to: point(14.5, 46))
            body.closeSubpath()
            context.fill(body, with: .color(pocket))
            context.stroke(body, with: .color(pocket),
                           style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round, lineJoin: .round))

            var hem = Path()
            hem.move(to: point(13.5, 34.5))
            hem.addLine(to: point(50.5, 34.5))
            context.stroke(hem, with: .color(cut),
                           style: StrokeStyle(lineWidth: 2.6 * unit, lineCap: .round))

            // Topstitching is the last cue to survive shrinking, so it is drawn thinnest.
            var stitch = Path()
            stitch.move(to: point(17, 39.5))
            stitch.addLine(to: point(18.3, 45.2))
            stitch.addLine(to: point(32, 53.5))
            stitch.addLine(to: point(45.7, 45.2))
            stitch.addLine(to: point(47, 39.5))
            context.stroke(stitch, with: .color(cut),
                           style: StrokeStyle(lineWidth: 1.5 * unit, lineCap: .round, lineJoin: .round,
                                              dash: [2 * unit, 2.4 * unit]))
        }
        .accessibilityHidden(true)
    }
}

/// The app's name set the way the logo sets it: a serif, one word, second half in the accent tone.
/// `.serif` is New York, the closest system face to the Source Serif the logo lockup uses.
struct PocketBloomWordmark: View {
    var size: CGFloat
    var base: Color = Palette.ink
    var accent: Color = Palette.sprout

    var body: some View {
        (Text("Pocket").foregroundStyle(base) + Text("Bloom").foregroundStyle(accent))
            .font(.system(size: size, weight: .regular, design: .serif))
            .tracking(-0.4)
            .accessibilityLabel("PocketBloom")
    }
}
