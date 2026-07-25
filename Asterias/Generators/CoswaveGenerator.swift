import Foundation

/// Controls whether radial waves keep a constant frequency or tighten outward.
enum WaveAccelerationMethod: Sendable {
    case none
    case linear
}

/// Parameters for warped concentric cosine bands.
struct CoswaveParams: Sendable {
    let origin: GeneratorPoint
    var waveScale: Double
    let squish: Double
    let squareAngle: Double
    let distortion: Double
    let packMethod: PackMethod
    var accelerationMethod: WaveAccelerationMethod
    var acceleration: Double

    static func random(using generator: inout SeededRandomNumberGenerator) -> CoswaveParams {
        var params = CoswaveParams(
            origin: GeneratorPoint.random(using: &generator),
            waveScale: Double.random(in: 0...25, using: &generator) + 1.0,
            squish: (Double.random(in: 0...2, using: &generator) + 0.5) * (Bool.random(using: &generator) ? 1.0 : -1.0),
            squareAngle: Double.random(in: 0...Double.pi, using: &generator),
            distortion: Double.random(in: 0...1.5, using: &generator) + 0.5,
            packMethod: PackMethod.random(using: &generator),
            accelerationMethod: .none,
            acceleration: 0
        )

        if Int.random(in: 0..<64, using: &generator) == 0 {
            params.accelerationMethod = .linear
            params.acceleration = Double.random(in: 0...2, using: &generator) + 1.0
        }

        if params.packMethod == .scaleToFit {
            params.waveScale *= 2.0
        }

        return params
    }
}

/// Generates radial rings that can be squashed, rotated, and distorted.
enum Coswave {
    static func generate(_ point: GeneratorPoint, params: CoswaveParams) -> Double {
        let relativeX = point.x - params.origin.x
        let relativeY = point.y - params.origin.y
        let hypotenuse = hypot(relativeX, relativeY)
        // Distort the polar angle before measuring distance; this turns simple
        // circles into squared-off or pinched wave bands.
        let hypAngle = atan((relativeY / relativeX) * params.distortion) + params.squareAngle
        let x = cos(hypAngle) * hypotenuse
        let y = sin(hypAngle) * hypotenuse
        let squishedDistance = hypot(x * params.squish, y / params.squish)
        let scale = params.accelerationMethod == .none ? params.waveScale : pow(params.waveScale, squishedDistance * params.acceleration)
        let rawCos = AsteriasGenerators.packedCos(distance: squishedDistance, scale: scale, packMethod: params.packMethod)
        return (rawCos + 1.0) / 2.0
    }
}
