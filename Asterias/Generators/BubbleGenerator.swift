import Foundation

/// Randomizable numeric range used to keep bubbles in a related family.
struct ValueRange: Sendable {
    let minimum: Double
    let maximum: Double

    init(_ first: Double, _ second: Double) {
        minimum = min(first, second)
        maximum = max(first, second)
    }

    static func random(minimumRange: Range<Double>, maximumRange: Range<Double>, using generator: inout SeededRandomNumberGenerator) -> ValueRange {
        ValueRange(Double.random(in: minimumRange, using: &generator), Double.random(in: maximumRange, using: &generator))
    }

    func sample(using generator: inout SeededRandomNumberGenerator) -> Double {
        minimum == maximum ? minimum : Double.random(in: minimum..<maximum, using: &generator)
    }
}

/// One mirrored, rotated, and squashed ellipse-like bubble field.
struct Bubble: Sendable {
    let scale: Double
    let squish: Double
    let angle: Double
    let origin: GeneratorPoint
    let cosine: Double
    let sine: Double

    init(scale: Double, squish: Double, angle: Double, origin: GeneratorPoint) {
        self.scale = scale
        self.squish = squish
        self.angle = angle
        self.origin = origin
        cosine = cos(angle)
        sine = sin(angle)
    }

    static func random(scale: ValueRange, squish: ValueRange, angle: ValueRange, using generator: inout SeededRandomNumberGenerator) -> Bubble {
        Bubble(
            scale: scale.sample(using: &generator),
            squish: squish.sample(using: &generator),
            angle: angle.sample(using: &generator),
            origin: GeneratorPoint.random(using: &generator)
        )
    }
}

/// Collection of bubbles whose maximum value forms rounded cell shapes.
struct BubbleParams: Sendable {
    let bubbles: [Bubble]

    static func random(using generator: inout SeededRandomNumberGenerator) -> BubbleParams {
        let scale = ValueRange.random(minimumRange: 0.0..<0.2, maximumRange: 0.0..<0.2, using: &generator)
        let squish = ValueRange(randomSquish(using: &generator), randomSquish(using: &generator))
        let angle = ValueRange.random(minimumRange: 0.0..<(Double.pi / 2.0), maximumRange: 0.0..<(Double.pi / 2.0), using: &generator)
        let count = Int.random(in: 8..<32, using: &generator)
        return BubbleParams(bubbles: (0..<count).map { _ in Bubble.random(scale: scale, squish: squish, angle: angle, using: &generator) })
    }

    private static func randomSquish(using generator: inout SeededRandomNumberGenerator) -> Double {
        guard Bool.random(using: &generator) else { return 1.0 }
        let value = Double.random(in: 1.0..<4.0, using: &generator)
        return Bool.random(using: &generator) ? value : 1.0 / value
    }
}

/// Produces soft overlapping bubble forms that are naturally tileable.
enum BubbleGenerator {
    static func generate(_ point: GeneratorPoint, params: BubbleParams) -> Double {
        var output = allBubblesValue(point, params: params)
        // Sample neighboring copies and fade them by edge distance so bubbles
        // crossing one side of the image continue on the other.
        output = max(output, allBubblesValue(GeneratorPoint(x: point.x + 1.0, y: point.y), params: params) * (1.0 - point.x))
        output = max(output, allBubblesValue(GeneratorPoint(x: point.x - 1.0, y: point.y), params: params) * point.x)
        output = max(output, allBubblesValue(GeneratorPoint(x: point.x, y: point.y + 1.0), params: params) * (1.0 - point.y))
        output = max(output, allBubblesValue(GeneratorPoint(x: point.x, y: point.y - 1.0), params: params) * point.y)
        output = max(output, allBubblesValue(GeneratorPoint(x: point.x + 1.0, y: point.y + 1.0), params: params) * (1.0 - point.x) * (1.0 - point.y))
        output = max(output, allBubblesValue(GeneratorPoint(x: point.x + 1.0, y: point.y - 1.0), params: params) * (1.0 - point.x) * point.y)
        output = max(output, allBubblesValue(GeneratorPoint(x: point.x - 1.0, y: point.y + 1.0), params: params) * point.x * (1.0 - point.y))
        output = max(output, allBubblesValue(GeneratorPoint(x: point.x - 1.0, y: point.y - 1.0), params: params) * point.x * point.y)
        return output
    }

    private static func allBubblesValue(_ point: GeneratorPoint, params: BubbleParams) -> Double {
        var output = 0.0
        for bubble in params.bubbles {
            output = max(output, oneBubbleValue(point, bubble: bubble))
        }
        return output
    }

    private static func oneBubbleValue(_ point: GeneratorPoint, bubble: Bubble) -> Double {
        let relativeX = point.x - bubble.origin.x
        let relativeY = point.y - bubble.origin.y
        // Mirror around the origin before rotation so each bubble has the
        // lens-like bilateral symmetry of the original Asterias algorithm.
        let baseX = abs(relativeX)
        let baseY = relativeX < 0.0 ? -relativeY : relativeY
        let transverse = ((baseX * bubble.cosine) - (baseY * bubble.sine)) + bubble.origin.x
        let distance = ((baseX * bubble.sine) + (baseY * bubble.cosine)) + bubble.origin.y
        return squishedBubbleValue(transverse: transverse, distance: distance, bubble: bubble)
    }

    private static func squishedBubbleValue(transverse: Double, distance: Double, bubble: Bubble) -> Double {
        let adjustedTransverse = bubble.origin.x + ((transverse - bubble.origin.x) * bubble.squish)
        let adjustedDistance = bubble.origin.y + ((distance - bubble.origin.y) / bubble.squish)
        let hypotenuse = hypot(adjustedTransverse - bubble.origin.x, adjustedDistance - bubble.origin.y)
        return 1.0 - hypotenuse * hypotenuse / bubble.scale
    }
}
