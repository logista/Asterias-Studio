import Foundation

/// One line segment in the branching fractal tree.
struct BranchfracRay: Sendable {
    let origin: GeneratorPoint
    let angle: Double
    let length: Double
    let ancestors: Int
    let children: [Int]
    let directionX: Double
    let directionY: Double

    init(origin: GeneratorPoint, angle: Double, length: Double, ancestors: Int, children: [Int]) {
        self.origin = origin
        self.angle = angle
        self.length = length
        self.ancestors = ancestors
        self.children = children
        directionX = -sin(angle)
        directionY = -cos(angle)
    }
}

/// Random tree of branching rays used by the branch fractal generator.
struct BranchfracParams: Sendable {
    static let maximumRayCount = 128
    static let maximumParents = 5

    let rays: [BranchfracRay]

    static func random(using generator: inout SeededRandomNumberGenerator) -> BranchfracParams {
        var builder = BranchfracTreeBuilder(generator: &generator)
        return BranchfracParams(rays: builder.build())
    }
}

/// Produces fern-like branching distance fields.
enum BranchfracGenerator {
    static func generate(_ point: GeneratorPoint, params: BranchfracParams) -> Double {
        guard !params.rays.isEmpty else { return 0 }
        let distance = nearestRayDistance(point, rays: params.rays)
        return 1.0 / ((distance * 10.0) + 1.0)
    }

    private static func nearestRayDistance(_ point: GeneratorPoint, rays: [BranchfracRay]) -> Double {
        var nearestSquared = Double.greatestFiniteMagnitude

        for ray in rays {
            let distanceSquared = rayDistanceSquared(point, ray: ray)
            if distanceSquared < nearestSquared {
                nearestSquared = distanceSquared
                if nearestSquared <= 0.00000001 {
                    return 0.0
                }
            }
        }

        return sqrt(nearestSquared)
    }

    private static func rayDistanceSquared(_ point: GeneratorPoint, ray: BranchfracRay) -> Double {
        let relativeX = point.x - ray.origin.x
        let relativeY = point.y - ray.origin.y
        let projectedLength = (relativeX * ray.directionX) + (relativeY * ray.directionY)

        if projectedLength <= 0.0 {
            return (relativeX * relativeX) + (relativeY * relativeY)
        }
        if projectedLength >= ray.length {
            let endX = ray.origin.x + ray.directionX * ray.length
            let endY = ray.origin.y + ray.directionY * ray.length
            let endRelativeX = point.x - endX
            let endRelativeY = point.y - endY
            return (endRelativeX * endRelativeX) + (endRelativeY * endRelativeY)
        }

        let perpendicularX = relativeX - ray.directionX * projectedLength
        let perpendicularY = relativeY - ray.directionY * projectedLength
        return (perpendicularX * perpendicularX) + (perpendicularY * perpendicularY)
    }
}

private struct BranchfracTreeBuilder {
    private var generator: SeededRandomNumberGenerator
    private var rays: [BranchfracRay] = []

    init(generator: inout SeededRandomNumberGenerator) {
        self.generator = generator
    }

    mutating func build() -> [BranchfracRay] {
        let root = BranchfracRay(
            origin: GeneratorPoint(x: 0.5, y: 0.5),
            angle: Double.random(in: 0..<(Double.pi * 2.0), using: &generator),
            length: 0.2,
            ancestors: 0,
            children: []
        )
        rays = [root]
        makeLeaves(for: 0)
        return rays
    }

    private mutating func makeLeaves(for rayIndex: Int) {
        guard rays.indices.contains(rayIndex) else { return }

        let childCount = Int.random(in: 2..<4, using: &generator)
        var childIndexes: [Int] = []
        childIndexes.reserveCapacity(childCount)

        for _ in 0..<childCount {
            guard rays.count < BranchfracParams.maximumRayCount else { break }
            let parent = rays[rayIndex]
            let child = makeBranch(from: parent)
            let childIndex = rays.count
            rays.append(child)
            childIndexes.append(childIndex)

            if child.ancestors < BranchfracParams.maximumParents {
                makeLeaves(for: childIndex)
            }
        }

        let ray = rays[rayIndex]
        rays[rayIndex] = BranchfracRay(
            origin: ray.origin,
            angle: ray.angle,
            length: ray.length,
            ancestors: ray.ancestors,
            children: childIndexes
        )
    }

    private mutating func makeBranch(from ray: BranchfracRay) -> BranchfracRay {
        BranchfracRay(
            origin: GeneratorPoint(
                x: ray.origin.x + ray.directionX * ray.length,
                y: ray.origin.y + ray.directionY * ray.length
            ),
            angle: Double.random(in: 0..<Double.pi, using: &generator),
            length: ray.length * 0.7,
            ancestors: ray.ancestors + 1,
            children: []
        )
    }
}
