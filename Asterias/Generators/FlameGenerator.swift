import Foundation

/// Iterated-function-style variations used to bend flame transform space.
enum FlameVariation: Sendable {
    case linear
    case sinusoidal
    case swirl
    case horseshoe
    case fan

    static func random(using generator: inout SeededRandomNumberGenerator) -> FlameVariation {
        switch Int.random(in: 0...4, using: &generator) {
        case 0: .linear
        case 1: .sinusoidal
        case 2: .swirl
        case 3: .horseshoe
        default: .fan
        }
    }
}

/// One weighted transform contributing a luminous ridge field.
struct FlameTransform: Sendable {
    let origin: GeneratorPoint
    let angle: Double
    let scale: Double
    let twist: Double
    let symmetry: Int
    let ridgeScale: Double
    let sharpness: Double
    let weight: Double
    let phase: Double
    let variation: FlameVariation
    let cosine: Double
    let sine: Double

    init(
        origin: GeneratorPoint,
        angle: Double,
        scale: Double,
        twist: Double,
        symmetry: Int,
        ridgeScale: Double,
        sharpness: Double,
        weight: Double,
        phase: Double,
        variation: FlameVariation
    ) {
        self.origin = origin
        self.angle = angle
        self.scale = scale
        self.twist = twist
        self.symmetry = symmetry
        self.ridgeScale = ridgeScale
        self.sharpness = sharpness
        self.weight = weight
        self.phase = phase
        self.variation = variation
        cosine = cos(angle)
        sine = sin(angle)
    }

    static func random(using generator: inout SeededRandomNumberGenerator) -> FlameTransform {
        FlameTransform(
            origin: GeneratorPoint.random(using: &generator),
            angle: Double.random(in: 0..<(Double.pi * 2.0), using: &generator),
            scale: Double.random(in: 0.65...2.4, using: &generator),
            twist: Double.random(in: -8.0...8.0, using: &generator),
            symmetry: Int.random(in: 3...9, using: &generator),
            ridgeScale: Double.random(in: 5.0...26.0, using: &generator),
            sharpness: Double.random(in: 1.6...5.5, using: &generator),
            weight: Double.random(in: 0.35...1.0, using: &generator),
            phase: Double.random(in: 0..<(Double.pi * 2.0), using: &generator),
            variation: FlameVariation.random(using: &generator)
        )
    }
}

/// Parameters for a stacked procedural flame field.
struct FlameParams: Sendable {
    let transforms: [FlameTransform]
    let contrast: Double
    let glow: Double
    let isInverted: Bool

    static func random(using generator: inout SeededRandomNumberGenerator) -> FlameParams {
        FlameParams(
            transforms: (0..<Int.random(in: 3...7, using: &generator)).map { _ in FlameTransform.random(using: &generator) },
            contrast: Double.random(in: 0.85...1.8, using: &generator),
            glow: Double.random(in: 0.6...1.35, using: &generator),
            isInverted: Bool.random(using: &generator)
        )
    }
}

/// Builds luminous filaments by multiplying the inverse of several transforms.
enum FlameGenerator {
    static func generate(_ point: GeneratorPoint, params: FlameParams) -> Double {
        // Multiplying inverse brightness lets independent transforms carve
        // overlapping light into a single high-contrast field.
        var inverseOutput = 1.0

        for transform in params.transforms {
            let value = transformValue(point, transform: transform)
            inverseOutput *= 1.0 - (value * transform.weight).clamped(to: 0...1)
        }

        let value = pow((1.0 - inverseOutput).clamped(to: 0...1), params.glow) * params.contrast
        let clampedValue = value.clamped(to: 0...1)
        return params.isInverted ? 1.0 - clampedValue : clampedValue
    }

    private static func transformValue(_ point: GeneratorPoint, transform: FlameTransform) -> Double {
        // Use wrapped deltas so transforms continue smoothly across tile edges.
        let deltaX = wrappedSignedDelta(point.x - transform.origin.x) * 2.0
        let deltaY = wrappedSignedDelta(point.y - transform.origin.y) * 2.0
        let rotatedX = (deltaX * transform.cosine) - (deltaY * transform.sine)
        let rotatedY = (deltaX * transform.sine) + (deltaY * transform.cosine)
        let varied = variedPoint(x: rotatedX, y: rotatedY, transform: transform)
        let radius = max(0.0001, hypot(varied.x, varied.y))
        let theta = atan2(varied.y, varied.x)
        // Angular symmetry creates the star/flame spokes while the radial wave
        // adds smaller glowing ridges along each spoke.
        let angular = pow(abs(cos((theta * Double(transform.symmetry)) + transform.phase + (radius * transform.twist))), transform.sharpness)
        let radial = AsteriasGenerators.packedCos(distance: radius, scale: transform.ridgeScale, packMethod: .scaleToFit)
        let falloff = 1.0 / (1.0 + pow(radius * transform.scale, transform.sharpness + 1.0))
        return ((angular * 0.72) + (radial * 0.28)) * falloff
    }

    private static func variedPoint(x: Double, y: Double, transform: FlameTransform) -> (x: Double, y: Double) {
        switch transform.variation {
        case .linear:
            return (x, y)
        case .sinusoidal:
            return (sin((x * transform.scale) + transform.phase), sin((y * transform.scale) - transform.phase))
        case .swirl:
            let radiusSquared = (x * x) + (y * y)
            let amount = (radiusSquared * transform.twist) + transform.phase
            return ((x * sin(amount)) - (y * cos(amount)), (x * cos(amount)) + (y * sin(amount)))
        case .horseshoe:
            let radius = max(0.0001, hypot(x, y))
            return (((x - y) * (x + y)) / radius, (2.0 * x * y) / radius)
        case .fan:
            let radius = hypot(x, y)
            let theta = atan2(y, x)
            let fanWidth = Double.pi / Double(transform.symmetry)
            let adjustedTheta = theta + (sin((radius * transform.twist) + transform.phase) * fanWidth)
            return (cos(adjustedTheta) * radius, sin(adjustedTheta) * radius)
        }
    }

    private static func wrappedSignedDelta(_ value: Double) -> Double {
        if value > 0.5 { return value - 1.0 }
        if value < -0.5 { return value + 1.0 }
        return value
    }
}
