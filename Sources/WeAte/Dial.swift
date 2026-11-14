//
//  Dial.swift
//  WeAte
//
//  Created by Aarav Gupta on 14/11/26.
//  https://github.com/atpugvaraa
//  https://x.com/atpugvaraa
//

import SwiftUI

/// A car-style analogue dial: 270° sweep, ticks, numbers, a redline zone and a needle.
struct Dial: View {
    let value: Float
    let max: Float
    let labelStep: Float          // a number every this many units
    var ticksPerLabel = 4         // small ticks between numbers
    var redline: Float? = nil     // start of the red zone, if any
    let title: String
    let readout: String

    // 0 sits bottom-left, max sits bottom-right, sweeping clockwise over the top
    let startAngle: Double = 135
    let sweep: Double = 270

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 8

            // Track
            context.stroke(arc(center, radius - 6, from: 0, to: max),
                           with: .color(.white.opacity(0.12)), lineWidth: 6)

            // Redline zone
            if let redline {
                context.stroke(arc(center, radius - 6, from: redline, to: max),
                               with: .color(.red), lineWidth: 6)
            }

            // Ticks and numbers
            let tickStep = labelStep / Float(ticksPerLabel)
            let tickCount = Int((max / tickStep).rounded())
            for i in 0...tickCount {
                let v = Float(i) * tickStep
                let isLabel = i % ticksPerLabel == 0
                let inRed = redline.map { v >= $0 } ?? false
                let a = angle(for: v)
                let outer = point(center, radius - 12, a)
                let inner = point(center, radius - (isLabel ? 30 : 20), a)

                var tick = Path()
                tick.move(to: outer)
                tick.addLine(to: inner)
                context.stroke(tick,
                               with: .color(inRed ? .red : .white.opacity(isLabel ? 0.9 : 0.4)),
                               lineWidth: isLabel ? 3 : 1.5)

                if isLabel {
                    let label = Text("\(Int(v))")
                        .font(.system(size: radius * 0.11, weight: .semibold, design: .rounded))
                        .foregroundStyle(inRed ? .red : .white)
                    context.draw(label, at: point(center, radius - 50, a))
                }
            }

            // Needle, with a soft glow
            let needleAngle = angle(for: Swift.min(Swift.max(value, 0), max))
            var needle = Path()
            needle.move(to: point(center, radius * 0.12, needleAngle + .degrees(180)))
            needle.addLine(to: point(center, radius - 16, needleAngle))
            var glow = context
            glow.addFilter(.shadow(color: .orange.opacity(0.8), radius: 8))
            glow.stroke(needle, with: .color(.orange), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // Hub
            let hub = CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)
            context.fill(Path(ellipseIn: hub), with: .color(.white.opacity(0.9)))
            context.fill(Path(ellipseIn: hub.insetBy(dx: 5, dy: 5)), with: .color(.black))
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Text(readout)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.bottom, 24)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func angle(for v: Float) -> Angle {
        .degrees(startAngle + sweep * Double(v / max))
    }

    private func point(_ center: CGPoint, _ r: CGFloat, _ a: Angle) -> CGPoint {
        CGPoint(x: center.x + r * cos(a.radians), y: center.y + r * sin(a.radians))
    }

    private func arc(_ center: CGPoint, _ r: CGFloat, from: Float, to: Float) -> Path {
        var p = Path()
        p.addArc(center: center, radius: r, startAngle: angle(for: from), endAngle: angle(for: to), clockwise: false)
        return p
    }
}
