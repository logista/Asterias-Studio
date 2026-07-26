import Foundation

/// One line segment in the branching fractal tree.
struct BranchfracRay: Sendable {
    let origin: GeneratorPoint
    let angle: Double
    let length: Double
    let ancestors: Int
    let children: [Int]
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
        guard let root = params.rays.first else { return 0 }
        let distance = valueFromRay(point, ray: root, params: params)
        return 1.0 / ((distance * 10.0) + 1.0)
    }

    private static func valueFromRay(_ point: GeneratorPoint, ray: BranchfracRay, params: BranchfracParams) -> Double {
        var output = tangentRayDistance(point, ray: ray)
        if output > 0.0001, ray.ancestors < BranchfracParams.maximumParents, !ray.children.isEmpty {
            output = min(output, valueFromBranches(point, ray: ray, params: params))
        }
        return output
    }

    private static func valueFromBranches(_ point: GeneratorPoint, ray: BranchfracRay, params: BranchfracParams) -> Double {
        var output = Double.greatestFiniteMagnitude
        for childIndex in ray.children where params.rays.indices.contains(childIndex) {
            output = min(output, valueFromRay(point, ray: params.rays[childIndex], params: params))
        }
        return output
    }

    private static func tangentRayDistance(_ point: GeneratorPoint, ray: BranchfracRay) -> Double {
        let deltaX = ray.origin.x - point.x
        let deltaY = ray.origin.y - point.y
        let ratioAngle = deltaX == 0.0 && deltaY == 0.0 ? 0.0 : atan(deltaY / deltaX)
        let pointAngle = ratioAngle + ray.angle
        let hypotenuse = hypot(deltaY, deltaX)
        var distance = abs(cos(pointAngle) * hypotenuse)
        var leg = sin(pointAngle) * hypotenuse

        if ray.origin.x < point.x {
            leg = -leg
        }
        if leg < 0.0 {
            distance = hypot(distance, leg)
        }
        if leg > ray.length {
            distance = hypot(distance, leg - ray.length)
        }
        return distance
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
                x: ray.origin.x - sin(ray.angle) * ray.length,
                y: ray.origin.y - cos(ray.angle) * ray.length
            ),
            angle: Double.random(in: 0..<Double.pi, using: &generator),
            length: ray.length * 0.7,
            ancestors: ray.ancestors + 1,
            children: []
        )
    }
}
