import Foundation

/// Distance metrics used to shape Voronoi cells.
enum VoronoiDistanceMethod: Sendable {
    case euclidean
    case manhattan
    case chebyshev

    static func random(using generator: inout SeededRandomNumberGenerator) -> VoronoiDistanceMethod {
        switch Int.random(in: 0...2, using: &generator) {
        case 0: .euclidean
        case 1: .manhattan
        default: .chebyshev
        }
    }
}

/// Output modes derived from nearest-cell distance information.
enum VoronoiOutputMethod: Sendable {
    case cells
    case edges
    case ridges

    static func random(using generator: inout SeededRandomNumberGenerator) -> VoronoiOutputMethod {
        switch Int.random(in: 0...2, using: &generator) {
        case 0: .cells
        case 1: .edges
        default: .ridges
        }
    }
}

/// Seed point and shade value for one Voronoi region.
struct VoronoiCell: Sendable {
    let origin: GeneratorPoint
    let value: Double

    static func random(using generator: inout SeededRandomNumberGenerator) -> VoronoiCell {
        VoronoiCell(
            origin: GeneratorPoint.random(using: &generator),
            value: Double.random(in: 0...1, using: &generator)
        )
    }
}

/// Parameters for cellular regions, borders, and ridges.
struct VoronoiParams: Sendable {
    let distanceMethod: VoronoiDistanceMethod
    let outputMethod: VoronoiOutputMethod
    let cells: [VoronoiCell]
    let contrast: Double
    let ridgeScale: Double
    let isInverted: Bool

    static func random(using generator: inout SeededRandomNumberGenerator) -> VoronoiParams {
        VoronoiParams(
            distanceMethod: VoronoiDistanceMethod.random(using: &generator),
            outputMethod: VoronoiOutputMethod.random(using: &generator),
            cells: (0..<Int.random(in: 12...48, using: &generator)).map { _ in VoronoiCell.random(using: &generator) },
            contrast: Double.random(in: 2.0...12.0, using: &generator),
            ridgeScale: Double.random(in: 18.0...64.0, using: &generator),
            isInverted: Bool.random(using: &generator)
        )
    }
}

/// Generates tileable cellular patterns from nearest seed points.
enum VoronoiGenerator {
    static func generate(_ point: GeneratorPoint, params: VoronoiParams) -> Double {
        var nearestDistance = Double.greatestFiniteMagnitude
        var secondNearestDistance = Double.greatestFiniteMagnitude
        var nearestValue = 0.0

        for cell in params.cells {
            let distance = distance(from: point, to: cell.origin, method: params.distanceMethod)
            if distance < nearestDistance {
                secondNearestDistance = nearestDistance
                nearestDistance = distance
                nearestValue = cell.value
            } else if distance < secondNearestDistance {
                secondNearestDistance = distance
            }
        }

        // The gap between first and second nearest cells is small near cell
        // borders and large near cell centers.
        let edgeDistance = max(0.0, secondNearestDistance - nearestDistance)
        let value: Double
        switch params.outputMethod {
        case .cells:
            let shade = (1.0 - (nearestDistance * params.contrast)).clamped(to: 0...1)
            value = (nearestValue * 0.65) + (shade * 0.35)
        case .edges:
            value = 1.0 - (edgeDistance * params.contrast).clamped(to: 0...1)
        case .ridges:
            value = AsteriasGenerators.packedCos(distance: nearestDistance, scale: params.ridgeScale, packMethod: .scaleToFit)
        }

        return params.isInverted ? 1.0 - value : value
    }

    private static func distance(from point: GeneratorPoint, to origin: GeneratorPoint, method: VoronoiDistanceMethod) -> Double {
        // Wrapped deltas measure across the nearest periodic copy, making the
        // cell layout tile cleanly.
        let deltaX = wrappedDelta(point.x - origin.x)
        let deltaY = wrappedDelta(point.y - origin.y)

        switch method {
        case .euclidean:
            return hypot(deltaX, deltaY)
        case .manhattan:
            return abs(deltaX) + abs(deltaY)
        case .chebyshev:
            return max(abs(deltaX), abs(deltaY))
        }
    }

    private static func wrappedDelta(_ value: Double) -> Double {
        let magnitude = abs(value)
        return min(magnitude, 1.0 - magnitude)
    }
}
