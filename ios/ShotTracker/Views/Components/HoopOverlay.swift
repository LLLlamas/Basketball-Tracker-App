import SwiftUI

/// Draws the placed hoop ring + recent ball trail. Hit-testing disabled so it
/// never intercepts the camera area's tap gesture.
struct HoopOverlay: View {
    @ObservedObject var session: GameSession

    var body: some View {
        Canvas { ctx, size in
            // Hoop ring.
            if let hoop = session.hoop {
                let hx = hoop.x * size.width
                let hy = hoop.y * size.height
                let r = CGFloat(DetectionConstants.hoopRadiusNormalized) * size.width
                let rect = CGRect(x: hx - r, y: hy - r, width: r * 2, height: r * 2)
                ctx.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.orange),
                    lineWidth: 3
                )
                ctx.stroke(
                    Path(ellipseIn: rect.insetBy(dx: 4, dy: 4)),
                    with: .color(.orange.opacity(0.3)),
                    lineWidth: 1
                )
            }

            // Ball trail — fade old points.
            let trail = session.ballTrail.suffix(20)
            let now = Date().timeIntervalSince1970
            for sample in trail {
                let age = now - sample.timestamp
                let alpha = max(0, 1.0 - age / 1.5)
                if alpha <= 0 { continue }
                let cx = sample.position.x * size.width
                let cy = sample.position.y * size.height
                let r = max(6, sample.radius * size.width)
                let dot = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ctx.fill(
                    Path(ellipseIn: dot),
                    with: .color(.orange.opacity(alpha * 0.6))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
