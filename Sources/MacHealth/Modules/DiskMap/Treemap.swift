import CoreGraphics

/// Squarified treemap yerleşimi (Bruls, Huizing, van Wijk).
enum Treemap {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }

        var result = [CGRect](repeating: .zero, count: values.count)
        var remaining = rect
        var row: [Int] = []
        var i = 0

        func worst(_ row: [Int], _ side: Double) -> Double {
            let s = row.reduce(0) { $0 + areas[$1] }
            guard s > 0, side > 0 else { return .infinity }
            let mx = row.map { areas[$0] }.max()!, mn = row.map { areas[$0] }.min()!
            return max(side * side * mx / (s * s), (s * s) / (side * side * mn))
        }

        func place(_ row: [Int]) {
            let s = row.reduce(0) { $0 + areas[$1] }
            if remaining.width >= remaining.height {
                let w = CGFloat(s / Double(remaining.height))
                var y = remaining.minY
                for idx in row {
                    let h = CGFloat(areas[idx] / Double(w))
                    result[idx] = CGRect(x: remaining.minX, y: y, width: w, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: remaining.width - w, height: remaining.height)
            } else {
                let h = CGFloat(s / Double(remaining.width))
                var x = remaining.minX
                for idx in row {
                    let w = CGFloat(areas[idx] / Double(h))
                    result[idx] = CGRect(x: x, y: remaining.minY, width: w, height: h)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: remaining.height - h)
            }
        }

        while i < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [i], side) <= worst(row, side) {
                row.append(i); i += 1
            } else {
                place(row); row = []
            }
        }
        if !row.isEmpty { place(row) }
        return result
    }
}
