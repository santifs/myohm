import Foundation

/// Cole model fitted to a sweep: Z(f) = R∞ + (R0 − R∞) / (1 + (j f / fc)^α).
/// Nelder–Mead on (R0, R∞, ln fc, α) minimising relative complex residuals.
public struct ColeFit: Sendable, Equatable {
    public let r0: Double
    public let rInf: Double
    /// Characteristic frequency (Hz)
    public let fc: Double
    public let alpha: Double
    /// Root-mean-square relative residual (%)
    public let errorPercent: Double

    public static func model(_ f: Double, r0: Double, rInf: Double, fc: Double, alpha: Double) -> (re: Double, x: Double) {
        let w = pow(f / fc, alpha)
        let a = alpha * .pi / 2
        let dr = 1 + w * cos(a), di = w * sin(a)
        let den = dr * dr + di * di
        // Reactance returned positive for capacitive tissue.
        return (rInf + (r0 - rInf) * dr / den, (r0 - rInf) * di / den)
    }

    public static func fit(_ sweep: SweepAnalysis) -> ColeFit? {
        let pts = sweep.points.filter { $0.magnitude.isFinite && $0.magnitude > 0 }
        guard pts.count >= 8 else { return nil }
        let rs = pts.map(\.resistance)
        guard let rMax = rs.max(), let rMin = rs.min(), rMax > 0 else { return nil }
        let peak = pts.max { $0.reactance < $1.reactance } ?? pts[pts.count / 2]

        func cost(_ p: [Double]) -> Double {
            let r0 = p[0], rInf = p[1], fc = exp(p[2]), alpha = p[3]
            guard r0 > rInf, rInf > 0, alpha > 0.3, alpha <= 1 else { return .infinity }
            var sum = 0.0
            for q in pts {
                let m = model(q.frequencyHz, r0: r0, rInf: rInf, fc: fc, alpha: alpha)
                let dr = m.re - q.resistance, dx = m.x - q.reactance
                sum += (dr * dr + dx * dx) / (q.magnitude * q.magnitude)
            }
            return sum / Double(pts.count)
        }

        var best: (p: [Double], c: Double)?
        for alpha0 in [0.65, 0.8, 0.95] {
            let start = [rMax * 1.08, rMin * 0.9, log(max(peak.frequencyHz, 1_000)), alpha0]
            let result = nelderMead(start: start, steps: [rMax * 0.1, rMin * 0.1, 0.5, 0.08], cost: cost)
            if best == nil || result.c < best!.c { best = result }
        }
        guard let b = best, b.c.isFinite else { return nil }
        return ColeFit(r0: b.p[0], rInf: b.p[1], fc: exp(b.p[2]), alpha: b.p[3], errorPercent: b.c.squareRoot() * 100)
    }

    static func nelderMead(start: [Double], steps: [Double], cost: ([Double]) -> Double, iterations: Int = 1_500) -> (p: [Double], c: Double) {
        let n = start.count
        var simplex = [start]
        for i in 0..<n {
            var v = start
            v[i] += steps[i]
            simplex.append(v)
        }
        var values = simplex.map(cost)
        for _ in 0..<iterations {
            let order = values.indices.sorted { values[$0] < values[$1] }
            simplex = order.map { simplex[$0] }
            values = order.map { values[$0] }
            if abs(values[n] - values[0]) < 1e-14 { break }
            var centroid = [Double](repeating: 0, count: n)
            for v in simplex.dropLast() { for i in 0..<n { centroid[i] += v[i] / Double(n) } }
            let worst = simplex[n]
            func along(_ t: Double) -> [Double] { (0..<n).map { centroid[$0] + t * (worst[$0] - centroid[$0]) } }
            let reflected = along(-1), fr = cost(reflected)
            if fr < values[0] {
                let expanded = along(-2), fe = cost(expanded)
                (simplex[n], values[n]) = fe < fr ? (expanded, fe) : (reflected, fr)
            } else if fr < values[n - 1] {
                (simplex[n], values[n]) = (reflected, fr)
            } else {
                let contracted = along(fr < values[n] ? -0.5 : 0.5), fcn = cost(contracted)
                if fcn < min(fr, values[n]) {
                    (simplex[n], values[n]) = (contracted, fcn)
                } else {
                    for k in 1...n {
                        simplex[k] = (0..<n).map { simplex[0][$0] + 0.5 * (simplex[k][$0] - simplex[0][$0]) }
                        values[k] = cost(simplex[k])
                    }
                }
            }
        }
        let i = values.indices.min { values[$0] < values[$1] }!
        return (simplex[i], values[i])
    }
}
