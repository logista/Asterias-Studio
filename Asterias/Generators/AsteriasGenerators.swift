import Foundation

/// Generator families available to the UI, settings, export recipes, and tests.
enum GeneratorKind: String, CaseIterable, Sendable {
    case coswave
    case spinflake
    case rangefrac
    case flatwave
    case bubble
    case branchfrac
    case julia
    case voronoi
    case flame

    var label: String {
        switch self {
        case .coswave: "Coswave"
        case .spinflake: "Spinflake"
        case .rangefrac: "Rangefrac"
        case .flatwave: "Flatwave"
        case .bubble: "Bubble"
        case .branchfrac: "Branchfrac"
        case .julia: "Julia"
        case .voronoi: "Voronoi"
        case .flame: "Flame"
        }
    }

    static var sortedByName: [GeneratorKind] {
        allCases.sorted { $0.label < $1.label }
    }

    var helpText: String {
        switch self {
        case .coswave: "Radial rings and warped wave bands."
        case .spinflake: "Spiky floral forms with rotational symmetry."
        case .rangefrac: "Soft recursive terrain-like fields."
        case .flatwave: "Layered linear waves and interference."
        case .bubble: "Rounded cells, blobs, and overlapping lenses."
        case .branchfrac: "Fern-like branching distance fields."
        case .julia: "Fractal curls and escape-time contours."
        case .voronoi: "Cellular regions, borders, and distance ridges."
        case .flame: "Luminous transformed geometric filaments."
        }
    }

    static func random(from allowedGenerators: Set<GeneratorKind>, using generator: inout SeededRandomNumberGenerator) -> GeneratorKind {
        let candidates = allowedGenerators.isEmpty ? Array(allCases) : Array(allCases).filter { allowedGenerators.contains($0) }
        return candidates[Int.random(in: 0..<candidates.count, using: &generator)]
    }

    var isAntiAliased: Bool {
        switch self {
        case .rangefrac, .bubble, .branchfrac, .voronoi: true
        case .coswave, .spinflake, .flatwave, .julia, .flame: false
        }
    }

    var isSeamless: Bool {
        switch self {
        case .spinflake, .rangefrac, .bubble, .branchfrac, .voronoi, .flame: true
        case .coswave, .flatwave, .julia: false
        }
    }
}

/// Strategies for mapping oscillating cosine output into the renderer's
/// expected 0...1 brightness range.
enum PackMethod: Sendable {
    case scaleToFit
    case flipSignToFit
    case truncateToFit
    case slopeToFit

    var metalValue: Int {
        switch self {
        case .scaleToFit: 0
        case .flipSignToFit: 1
        case .truncateToFit: 2
        case .slopeToFit: 3
        }
    }

    static func random(using generator: inout SeededRandomNumberGenerator) -> PackMethod {
        switch Int.random(in: 0...3, using: &generator) {
        case 0: .scaleToFit
        case 1: .flipSignToFit
        case 2: .truncateToFit
        default: .slopeToFit
        }
    }
}

/// Normalized sample coordinate. Generators usually expect x and y near 0...1,
/// but tiling can intentionally sample neighboring wrapped copies.
struct GeneratorPoint: Sendable {
    let x: Double
    let y: Double

    static func random(using generator: inout SeededRandomNumberGenerator) -> GeneratorPoint {
        GeneratorPoint(x: Double.random(in: 0...1, using: &generator), y: Double.random(in: 0...1, using: &generator))
    }
}

/// Random parameter bundle containing one configuration for every generator.
struct GeneratorParams: Sendable {
    let coswave: CoswaveParams
    let spinflake: SpinflakeParams
    let rangefrac: RangefracParams
    let flatwave: FlatwaveParams
    let bubble: BubbleParams
    let branchfrac: BranchfracParams
    let julia: JuliaParams
    let voronoi: VoronoiParams
    let flame: FlameParams

    static func random(using generator: inout SeededRandomNumberGenerator) -> GeneratorParams {
        GeneratorParams(
            coswave: CoswaveParams.random(using: &generator),
            spinflake: SpinflakeParams.random(using: &generator),
            rangefrac: RangefracParams.random(using: &generator),
            flatwave: FlatwaveParams.random(using: &generator),
            bubble: BubbleParams.random(using: &generator),
            branchfrac: BranchfracParams.random(using: &generator),
            julia: JuliaParams.random(using: &generator),
            voronoi: VoronoiParams.random(using: &generator),
            flame: FlameParams.random(using: &generator)
        )
    }
}

/// CPU generator dispatcher with optional Metal acceleration for large images.
enum AsteriasGenerators {
    static func generate(
        area: AsteriasArea,
        generator kind: GeneratorKind,
        params: GeneratorParams,
        isTilingEnabled: Bool,
        using generator: inout SeededRandomNumberGenerator
    ) -> PixelMap {
        // Tiled renders are randomly rolled so repeated seeds do not always
        // expose the same seam-alignment artifacts at the image edge.
        let rollX = isTilingEnabled ? Int.random(in: 0...area.width, using: &generator) : 0
        let rollY = isTilingEnabled ? Int.random(in: 0...area.height, using: &generator) : 0
        let pixelCount = area.width * area.height
        // Large images try the Metal path first. If Metal is unavailable or a
        // command fails, generation falls back to the same CPU implementation.
        if pixelCount >= 65_536 {
            switch kind {
            case .flatwave:
                if let map = AsteriasMetalFlatwaveRenderer.shared?.generate(
                    area: area,
                    params: params.flatwave,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            case .spinflake:
                if let map = AsteriasMetalSpinflakeRenderer.shared?.generate(
                    area: area,
                    params: params.spinflake,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            case .bubble:
                if let map = AsteriasMetalBubbleRenderer.shared?.generate(
                    area: area,
                    params: params.bubble,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            case .branchfrac:
                if let map = AsteriasMetalBranchfracRenderer.shared?.generate(
                    area: area,
                    params: params.branchfrac,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            case .rangefrac:
                if let map = AsteriasMetalRangefracRenderer.shared?.generate(
                    area: area,
                    params: params.rangefrac,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            case .coswave:
                if let map = AsteriasMetalCoswaveRenderer.shared?.generate(
                    area: area,
                    params: params.coswave,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            case .julia:
                if let map = AsteriasMetalJuliaRenderer.shared?.generate(
                    area: area,
                    params: params.julia,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            case .voronoi:
                if let map = AsteriasMetalVoronoiRenderer.shared?.generate(
                    area: area,
                    params: params.voronoi,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            case .flame:
                if let map = AsteriasMetalFlameRenderer.shared?.generate(
                    area: area,
                    params: params.flame,
                    isTilingEnabled: isTilingEnabled,
                    rollX: rollX,
                    rollY: rollY
                ) {
                    return map
                }
            }
        }

        if kind == .branchfrac,
           let map = BranchfracGenerator.generate(
               area: area,
               params: params.branchfrac,
               isTilingEnabled: isTilingEnabled,
               rollX: rollX,
               rollY: rollY
           ) {
            return map
        }

        var values = [Float](repeating: 0, count: pixelCount)

        if pixelCount < 65_536 {
            fillRows(
                0..<area.height,
                area: area,
                rollX: rollX,
                rollY: rollY,
                kind: kind,
                params: params,
                isTilingEnabled: isTilingEnabled,
                values: &values
            )
        } else {
            // Split large CPU fallbacks by row ranges. Each worker writes a
            // disjoint slice of the output buffer.
            let workerCount = min(max(1, ProcessInfo.processInfo.activeProcessorCount), area.height)
            let rowsPerWorker = Int(ceil(Double(area.height) / Double(workerCount)))
            values.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: workerCount) { workerIndex in
                    let startY = workerIndex * rowsPerWorker
                    let endY = min(startY + rowsPerWorker, area.height)
                    guard startY < endY else { return }
                    fillRows(
                        startY..<endY,
                        area: area,
                        rollX: rollX,
                        rollY: rollY,
                        kind: kind,
                        params: params,
                        isTilingEnabled: isTilingEnabled,
                        values: buffer
                    )
                }
            }
        }

        return PixelMap(width: area.width, height: area.height, values: values)
    }

    @inline(__always)
    private static func fillRows(
        _ rows: Range<Int>,
        area: AsteriasArea,
        rollX: Int,
        rollY: Int,
        kind: GeneratorKind,
        params: GeneratorParams,
        isTilingEnabled: Bool,
        values: inout [Float]
    ) {
        for y in rows {
            for x in 0..<area.width {
                let value = layerPixel(x: x, y: y, area: area, rollX: rollX, rollY: rollY, kind: kind, params: params, isTilingEnabled: isTilingEnabled)
                values[y * area.width + x] = Float(value.clamped(to: 0...1))
            }
        }
    }

    @inline(__always)
    private static func fillRows(
        _ rows: Range<Int>,
        area: AsteriasArea,
        rollX: Int,
        rollY: Int,
        kind: GeneratorKind,
        params: GeneratorParams,
        isTilingEnabled: Bool,
        values: UnsafeMutableBufferPointer<Float>
    ) {
        for y in rows {
            for x in 0..<area.width {
                let value = layerPixel(x: x, y: y, area: area, rollX: rollX, rollY: rollY, kind: kind, params: params, isTilingEnabled: isTilingEnabled)
                values[y * area.width + x] = Float(value.clamped(to: 0...1))
            }
        }
    }

    @inline(__always)
    private static func layerPixel(
        x: Int,
        y: Int,
        area: AsteriasArea,
        rollX: Int,
        rollY: Int,
        kind: GeneratorKind,
        params: GeneratorParams,
        isTilingEnabled: Bool
    ) -> Double {
        let mappedX = isTilingEnabled ? wrappedCoordinate(x + rollX, limit: area.width) : x
        let mappedY = isTilingEnabled ? wrappedCoordinate(y + rollY, limit: area.height) : y
        let point = GeneratorPoint(x: Double(mappedX) / Double(area.width), y: Double(mappedY) / Double(area.height))
        let fudge = 1.0 / Double(area.width + area.height)
        return antiAliasedPoint(point, fudge: fudge, kind: kind, params: params, isTilingEnabled: isTilingEnabled)
    }

    @inline(__always)
    private static func wrappedCoordinate(_ value: Int, limit: Int) -> Int {
        value < limit ? value : value - limit
    }

    @inline(__always)
    private static func antiAliasedPoint(_ point: GeneratorPoint, fudge: Double, kind: GeneratorKind, params: GeneratorParams, isTilingEnabled: Bool) -> Double {
        var value = sampledPoint(point, kind: kind, params: params, isTilingEnabled: isTilingEnabled)
        guard !kind.isAntiAliased else { return value }

        value += sampledPoint(GeneratorPoint(x: point.x + fudge, y: point.y), kind: kind, params: params, isTilingEnabled: isTilingEnabled)
        value += sampledPoint(GeneratorPoint(x: point.x, y: point.y + fudge), kind: kind, params: params, isTilingEnabled: isTilingEnabled)
        value += sampledPoint(GeneratorPoint(x: point.x + fudge, y: point.y + fudge), kind: kind, params: params, isTilingEnabled: isTilingEnabled)
        return value / 4.0
    }

    @inline(__always)
    private static func sampledPoint(_ point: GeneratorPoint, kind: GeneratorKind, params: GeneratorParams, isTilingEnabled: Bool) -> Double {
        guard isTilingEnabled else {
            return callGenerator(point, kind: kind, params: params).clamped(to: 0...1)
        }

        // Generators that are not naturally seamless are blended against
        // translated copies so the left/right and top/bottom edges meet.
        var value = callGenerator(point, kind: kind, params: params)
        guard !kind.isSeamless else { return value.clamped(to: 0...1) }

        let farH = point.x + 1.0
        let farV = point.y + 1.0
        let farValue1 = callGenerator(GeneratorPoint(x: point.x, y: farV), kind: kind, params: params)
        let farValue2 = callGenerator(GeneratorPoint(x: farH, y: point.y), kind: kind, params: params)
        let farValue3 = callGenerator(GeneratorPoint(x: farH, y: farV), kind: kind, params: params)
        let nearWeightX = point.x
        let nearWeightY = point.y
        let farWeightX = 1.0 - nearWeightX
        let farWeightY = 1.0 - nearWeightY

        value = (value * nearWeightX * nearWeightY)
            + (farValue1 * nearWeightX * farWeightY)
            + (farValue2 * farWeightX * nearWeightY)
            + (farValue3 * farWeightX * farWeightY)
        return value.clamped(to: 0...1)
    }

    @inline(__always)
    private static func callGenerator(_ point: GeneratorPoint, kind: GeneratorKind, params: GeneratorParams) -> Double {
        switch kind {
        case .coswave:
            Coswave.generate(point, params: params.coswave)
        case .spinflake:
            Spinflake.generate(point, params: params.spinflake)
        case .rangefrac:
            Rangefrac.generate(point, params: params.rangefrac)
        case .flatwave:
            Flatwave.generate(point, params: params.flatwave)
        case .bubble:
            BubbleGenerator.generate(point, params: params.bubble)
        case .branchfrac:
            BranchfracGenerator.generate(point, params: params.branchfrac)
        case .julia:
            JuliaGenerator.generate(point, params: params.julia)
        case .voronoi:
            VoronoiGenerator.generate(point, params: params.voronoi)
        case .flame:
            FlameGenerator.generate(point, params: params.flame)
        }
    }

    @inline(__always)
    static func packedCos(distance: Double, scale: Double, packMethod: PackMethod) -> Double {
        let rawCos = cos(distance * scale)
        switch packMethod {
        case .flipSignToFit:
            return rawCos >= 0.0 ? rawCos : -rawCos
        case .truncateToFit:
            return rawCos >= 0.0 ? rawCos : rawCos + 1.0
        case .scaleToFit:
            return (rawCos + 1.0) / 2.0
        case .slopeToFit:
            return (cos((distance * scale).truncatingRemainder(dividingBy: .pi)) + 1.0) / 2.0
        }
    }
}
