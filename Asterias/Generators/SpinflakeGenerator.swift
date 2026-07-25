import Foundation

/// Ways to fold sine output into the positive radius contribution range.
enum SinePositivizingMethod: Sendable {
    case compress
    case truncate
    case absolute
    case sawblade

    static func random(using generator: inout SeededRandomNumberGenerator) -> SinePositivizingMethod {
        switch Int.random(in: 0...3, using: &generator) {
        case 0: .compress
        case 1: .truncate
        case 2: .absolute
        default: .sawblade
        }
    }
}

/// Controls how floret spokes twist as distance from the origin changes.
enum TwirlMethod: Sendable {
    case none
    case curve
    case sine

    static func random(using generator: inout SeededRandomNumberGenerator) -> TwirlMethod {
        switch Int.random(in: 0...2, using: &generator) {
        case 0: .none
        case 1: .curve
        default: .sine
        }
    }
}

/// Distance-dependent angular offset for floret wave shapes.
struct Twirl: Sendable {
    let base: Double
    var speed: Double
    var amplitude: Double
    let method: TwirlMethod

    static func random(using generator: inout SeededRandomNumberGenerator) -> Twirl {
        let method = TwirlMethod.random(using: &generator)
        var twirl = Twirl(base: Double.random(in: 0...Double.pi, using: &generator), speed: 0, amplitude: 0, method: method)
        switch method {
        case .sine:
            twirl.speed = Double.random(in: 0...(14.0 * Double.pi), using: &generator)
            twirl.amplitude = Double.random(in: -4.0...4.0, using: &generator)
        case .curve:
            twirl.speed = Double.random(in: -14.0...14.0, using: &generator)
            twirl.amplitude = Double.random(in: -4.0...4.0, using: &generator)
        case .none:
            break
        }
        return twirl
    }
}

/// One petal/spine contribution used to shape a spinflake edge.
struct Floret: Sendable {
    var sineMethod: SinePositivizingMethod
    let backward: Bool
    var spines: Int
    let spineRadius: Double
    let twirl: Twirl

    static func random(using generator: inout SeededRandomNumberGenerator) -> Floret {
        var floret = Floret(
            sineMethod: SinePositivizingMethod.random(using: &generator),
            backward: Bool.random(using: &generator),
            spines: Int.random(in: 1...16, using: &generator),
            spineRadius: Double.random(in: 0...0.5, using: &generator),
            twirl: Twirl.random(using: &generator)
        )
        if floret.sineMethod == .absolute && floret.spines % 2 == 1 {
            floret.spines += 1
        }
        return floret
    }
}

/// Parameters for spiky rotational forms.
struct SpinflakeParams: Sendable {
    let origin: GeneratorPoint
    let radius: Double
    let squish: Double
    let twist: Double
    let averageFlorets: Bool
    let florets: [Floret]
    let twistCosine: Double
    let twistSine: Double

    init(origin: GeneratorPoint, radius: Double, squish: Double, twist: Double, averageFlorets: Bool, florets: [Floret]) {
        self.origin = origin
        self.radius = radius
        self.squish = squish
        self.twist = twist
        self.averageFlorets = averageFlorets
        self.florets = florets
        twistCosine = cos(twist)
        twistSine = sin(twist)
    }

    static func random(using generator: inout SeededRandomNumberGenerator) -> SpinflakeParams {
        SpinflakeParams(
            origin: GeneratorPoint.random(using: &generator),
            radius: Double.random(in: 0...1, using: &generator),
            squish: Double.random(in: 0...2.75, using: &generator) * 0.25,
            twist: Double.random(in: 0...Double.pi, using: &generator),
            averageFlorets: Bool.random(using: &generator),
            florets: (0..<Int.random(in: 1...4, using: &generator)).map { _ in Floret.random(using: &generator) }
        )
    }
}

/// Generates flower-like forms from mirrored polar wave samples.
enum Spinflake {
    @inline(__always)
    static func generate(_ point: GeneratorPoint, params: SpinflakeParams) -> Double {
        let value = verticalTiledPoint(x: point.x, y: point.y, params: params)
        // Blend against translated copies near the right and top edges to keep
        // mirrored florets continuous in tiled renders.
        if point.x > 0.5 {
            let farPoint = verticalTiledPoint(x: point.x - 1.0, y: point.y, params: params)
            let farWeight = (point.x - 0.5) * 2.0
            return (value * (1.0 - farWeight)) + (farPoint * farWeight)
        }
        return value
    }

    @inline(__always)
    private static func verticalTiledPoint(x: Double, y: Double, params: SpinflakeParams) -> Double {
        let point = rawPoint(x: x, y: y, params: params)
        if y > 0.5 {
            let farPoint = rawPoint(x: x, y: y - 1.0, params: params)
            let farWeight = (y - 0.5) * 2.0
            return (point * (1.0 - farWeight)) + (farPoint * farWeight)
        }
        return point
    }

    @inline(__always)
    private static func rawPoint(x: Double, y: Double, params: SpinflakeParams) -> Double {
        let relativeX = x - params.origin.x
        let relativeY = y - params.origin.y
        // Mirror around the vertical axis before rotation, which gives each
        // floret its bilateral spine structure.
        let baseX = abs(relativeX)
        let baseY = relativeX < 0.0 ? -relativeY : relativeY
        let rotatedX = (baseX * params.twistCosine) - (baseY * params.twistSine)
        let rotatedY = (baseX * params.twistSine) + (baseY * params.twistCosine)
        let squishedDistance = hypot(rotatedX * params.squish, rotatedY / params.squish)

        guard squishedDistance != 0 else { return 1.0 }

        // Fold the point into polar space; each floret perturbs the edge radius
        // with a differently chopped sine wave.
        let pointAngle = atan(rotatedY / rotatedX)
        var edgeDistance = params.radius
        for floret in params.florets {
            edgeDistance += calcWave(theta: pointAngle, distance: squishedDistance, floret: floret)
        }
        if params.averageFlorets {
            edgeDistance /= Double(params.florets.count)
        }

        let proportionDistance = (edgeDistance - squishedDistance) / edgeDistance
        if proportionDistance >= 0.0 {
            return sqrt(proportionDistance)
        }
        return 1.0 - (1.0 / (1.0 - proportionDistance))
    }

    @inline(__always)
    private static func calcWave(theta: Double, distance: Double, floret: Floret) -> Double {
        let cosParameter: Double
        switch floret.twirl.method {
        case .curve:
            cosParameter = theta * Double(floret.spines) + floret.twirl.base + (distance * (floret.twirl.speed + (distance * floret.twirl.amplitude)))
        case .sine:
            cosParameter = (theta * Double(floret.spines) + floret.twirl.base) + (sin(distance * floret.twirl.speed) * (floret.twirl.amplitude + (distance * floret.twirl.amplitude)))
        case .none:
            cosParameter = theta * Double(floret.spines) + floret.twirl.base
        }
        return chopSin(cosParameter, floret: floret) * floret.spineRadius
    }

    @inline(__always)
    private static func chopSin(_ theta: Double, floret: Floret) -> Double {
        var output = sin(theta)
        switch floret.sineMethod {
        case .compress:
            output = (output + 1.0) / 2.0
        case .absolute:
            output = abs(output)
        case .truncate:
            output = output < 0.0 ? output + 1.0 : output
        case .sawblade:
            var adjustedTheta = (theta / 4.0).truncatingRemainder(dividingBy: Double.pi / 2.0)
            if adjustedTheta < 0.0 {
                adjustedTheta += Double.pi / 2.0
            }
            output = sin(adjustedTheta)
        }
        return floret.backward ? 1.0 - output : output
    }
}
