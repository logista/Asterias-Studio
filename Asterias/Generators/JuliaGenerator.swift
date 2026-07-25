import Foundation

/// Parameters for a Julia-set escape-time field.
struct JuliaParams: Sendable {
    let constantX: Double
    let constantY: Double
    let centerX: Double
    let centerY: Double
    let zoom: Double
    let maxIterations: Int
    let stripeScale: Double
    let packMethod: PackMethod
    let isInverted: Bool

    static func random(using generator: inout SeededRandomNumberGenerator) -> JuliaParams {
        let angle = Double.random(in: 0..<(Double.pi * 2.0), using: &generator)
        let radius = Double.random(in: 0.2...0.85, using: &generator)

        return JuliaParams(
            constantX: cos(angle) * radius,
            constantY: sin(angle) * radius,
            centerX: Double.random(in: -0.2...0.2, using: &generator),
            centerY: Double.random(in: -0.2...0.2, using: &generator),
            zoom: Double.random(in: 0.85...2.6, using: &generator),
            maxIterations: Int.random(in: 48...160, using: &generator),
            stripeScale: Double.random(in: 4.0...28.0, using: &generator),
            packMethod: PackMethod.random(using: &generator),
            isInverted: Bool.random(using: &generator)
        )
    }
}

/// Generates fractal curls with smooth escape bands.
enum JuliaGenerator {
    static func generate(_ point: GeneratorPoint, params: JuliaParams) -> Double {
        let scale = 3.0 / params.zoom
        var zx = params.centerX + ((point.x - 0.5) * scale)
        var zy = params.centerY + ((point.y - 0.5) * scale)
        var iteration = 0
        var radiusSquared = (zx * zx) + (zy * zy)

        // Iterate z = z^2 + c until the orbit escapes. A larger escape radius
        // gives stable smoothing for the stripe calculation below.
        while iteration < params.maxIterations && radiusSquared <= 16.0 {
            let nextX = (zx * zx) - (zy * zy) + params.constantX
            zy = (2.0 * zx * zy) + params.constantY
            zx = nextX
            radiusSquared = (zx * zx) + (zy * zy)
            iteration += 1
        }

        let value: Double
        if iteration == params.maxIterations {
            value = 1.0
        } else {
            let magnitude = sqrt(radiusSquared)
            // Smooth escape time avoids hard integer iteration bands, then the
            // packed cosine reintroduces controlled contour stripes.
            let smoothIteration = Double(iteration) + 1.0 - (log(log(magnitude)) / log(2.0))
            let normalized = (smoothIteration / Double(params.maxIterations)).clamped(to: 0...1)
            let bands = AsteriasGenerators.packedCos(distance: normalized, scale: params.stripeScale, packMethod: params.packMethod)
            value = ((1.0 - normalized) * 0.35) + (bands * 0.65)
        }

        return params.isInverted ? 1.0 - value : value
    }
}
