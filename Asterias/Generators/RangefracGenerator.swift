import Foundation

/// Cached recursive terrain field sampled by the rangefrac generator.
struct RangefracParams: Sendable {
    static let matrixSize = 256
    let data: [Double]

    static func random(using generator: inout SeededRandomNumberGenerator) -> RangefracParams {
        let size = matrixSize
        var levels = [Int](repeating: 0, count: size * size)
        var data = [Double](repeating: 0, count: size * size)

        func index(_ x: Int, _ y: Int) -> Int { y * size + x }

        // Repeatedly refine random corner ranges from coarse to fine scales,
        // creating soft terrain-like variation without storing a tree.
        for scaleStep in 1...8 {
            let step = Int(pow(2.0, Double(8 - scaleStep)))
            var x = 0
            while x < size {
                var y = 0
                while y < size {
                    if levels[index(x, y)] < step {
                        let localValues = [
                            (x - step, y - step), (x, y - step), (x + step, y - step),
                            (x - step, y), (x + step, y),
                            (x - step, y + step), (x, y + step), (x + step, y + step)
                        ]
                        .filter { levels[index(wrap($0.0), wrap($0.1))] > step }
                        .map { data[index(wrap($0.0), wrap($0.1))] }

                        let minimum = localValues.min() ?? 1.0
                        let maximum = localValues.max() ?? 0.0
                        var value = minimum != maximum ? Double.random(in: Swift.min(minimum, maximum)...Swift.max(minimum, maximum), using: &generator) : minimum

                        if step >= size / 2 {
                            value = (value + (value > 0.5 ? 1.0 : 0.0)) / 2.0
                        }

                        data[index(x, y)] = value
                        levels[index(x, y)] = step
                    }
                    y += step
                }
                x += step
            }
        }

        return RangefracParams(data: data)
    }

    static func wrap(_ coordinate: Int) -> Int {
        let size = matrixSize
        return coordinate >= 0 ? coordinate % size : (coordinate % size + size) % size
    }
}

/// Samples the precomputed recursive field with corner-distance weighting.
enum Rangefrac {
    static func generate(_ point: GeneratorPoint, params: RangefracParams) -> Double {
        let size = RangefracParams.matrixSize
        let tweaker = 0.5 / Double(size)
        let left = Int(floor(point.x * Double(size) - tweaker))
        let top = Int(floor(point.y * Double(size) - tweaker))
        let corners = [(left, top), (left + 1, top), (left, top + 1), (left + 1, top + 1)]
        var totalSum = 0.0
        var totalWeight = 0.0

        for corner in corners {
            let value = params.data[RangefracParams.wrap(corner.1) * size + RangefracParams.wrap(corner.0)]
            let weight = max(0.0, 1.0 - hypot(Double(corner.0) - (point.x * Double(size)), Double(corner.1) - (point.y * Double(size))))
            totalSum += value * weight
            totalWeight += weight
        }

        return totalWeight == 0.0 ? 0.0 : totalSum / totalWeight
    }
}
