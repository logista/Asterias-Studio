import CoreGraphics
import Foundation

/*
 Ported from jelatofish / xasterias-inspired Asterias algorithms.
 Copyright (C) 2021 Amane Katagiri
 Copyright (C) 1999 Mars Saxman
 Licensed under GPL-2.0-or-later, matching the source project lineage.
 */

/// Pixel dimensions for a generated pattern.
struct AsteriasArea: Sendable {
    let width: Int
    let height: Int
}

/// User-facing render inputs after settings and UI choices have been resolved.
struct AsteriasRenderOptions: Sendable {
    let area: AsteriasArea
    let layerCount: Int?
    let palette: AsteriasColorPalette
    let isTilingEnabled: Bool
    let allowedGenerators: Set<GeneratorKind>
    var seed: UInt64?

    /// An empty selection means "use every generator" so the app can never
    /// render with no image source.
    var effectiveAllowedGenerators: Set<GeneratorKind> {
        allowedGenerators.isEmpty ? Set(GeneratorKind.allCases) : allowedGenerators
    }
}

/// Complete render output used by the preview, export pipeline, and tests.
struct RenderedAsteriasPattern: Sendable {
    let width: Int
    let height: Int
    let seed: UInt64
    let rgbaData: Data
    let cgImage: CGImage
    let metrics: AsteriasRenderMetrics
}

/// Timings captured for debugging expensive pattern generations.
struct AsteriasRenderMetrics: Sendable {
    let patternSeconds: TimeInterval
    let rgbaSeconds: TimeInterval
    let imageSeconds: TimeInterval
    let totalSeconds: TimeInterval
    let width: Int
    let height: Int
    let layerCount: Int
    let generatorMetrics: [AsteriasGeneratorMetric]

    var formattedSummary: String {
        "total \(Self.format(totalSeconds)) | pattern \(Self.format(patternSeconds)) | rgba \(Self.format(rgbaSeconds)) | image \(Self.format(imageSeconds))"
    }

    var slowestGeneratorMetric: AsteriasGeneratorMetric? {
        generatorMetrics.max { $0.seconds < $1.seconds }
    }

    var generatorBreakdownSummary: String {
        generatorMetrics.map(\.formattedSummary).joined(separator: " | ")
    }

    static func format(_ seconds: TimeInterval) -> String {
        if seconds < 1.0 {
            return "\(Int((seconds * 1000.0).rounded())) ms"
        }
        return String(format: "%.2f s", seconds)
    }
}

/// High-level render facade that turns options into RGBA bytes and a CGImage.
struct AsteriasRenderer: Sendable {
    static let minimumLayerCount = 2
    static let maximumLayerCount = 6
    static let maximumCutoffThreshold = 1.0 / 16.0

    nonisolated static func render(size: Int, layerCount: Int?) throws -> RenderedAsteriasPattern {
        try render(
            options: AsteriasRenderOptions(
                area: AsteriasArea(width: size, height: size),
                layerCount: layerCount,
                palette: .random,
                isTilingEnabled: true,
                allowedGenerators: Set(GeneratorKind.allCases),
                seed: nil
            )
        )
    }

    nonisolated static func render(options: AsteriasRenderOptions) throws -> RenderedAsteriasPattern {
        let totalStart = Date()
        // Clamp dimensions at the boundary so lower-level math never has to
        // handle zero-sized images or divide by zero.
        let area = AsteriasArea(width: max(1, options.area.width), height: max(1, options.area.height))
        let seed = options.seed ?? UInt64.random(in: UInt64.min...UInt64.max)
        var generator = SeededRandomNumberGenerator(seed: seed)

        let patternStart = Date()
        let pattern = try AsteriasPattern.random(
            area: area,
            layerCount: options.layerCount,
            palette: options.palette,
            isTilingEnabled: options.isTilingEnabled,
            allowedGenerators: options.effectiveAllowedGenerators,
            using: &generator
        )
        let patternSeconds = Date().timeIntervalSince(patternStart)

        let rgbaStart = Date()
        let data = pattern.renderRGBAData()
        let rgbaSeconds = Date().timeIntervalSince(rgbaStart)

        let imageStart = Date()
        guard let image = makeImage(width: area.width, height: area.height, data: data) else {
            throw AsteriasError.imageCreationFailed
        }
        let imageSeconds = Date().timeIntervalSince(imageStart)

        let metrics = AsteriasRenderMetrics(
            patternSeconds: patternSeconds,
            rgbaSeconds: rgbaSeconds,
            imageSeconds: imageSeconds,
            totalSeconds: Date().timeIntervalSince(totalStart),
            width: area.width,
            height: area.height,
            layerCount: pattern.layers.count,
            generatorMetrics: pattern.generatorMetrics
        )
        print("Asterias render [\(area.width)x\(area.height), layers \(pattern.layers.count), seed \(seed)]: \(metrics.formattedSummary)")
        if !metrics.generatorBreakdownSummary.isEmpty {
            print("Asterias generators: \(metrics.generatorBreakdownSummary)")
        }

        return RenderedAsteriasPattern(width: area.width, height: area.height, seed: seed, rgbaData: data, cgImage: image, metrics: metrics)
    }

    nonisolated static func makeImage(width: Int, height: Int, data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

/// Small deterministic generator used to make pattern output reproducible from
/// an exported seed. This is SplitMix64, which is fast and stable across runs.
struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

/// Errors surfaced to the UI when render or import inputs are invalid.
enum AsteriasError: LocalizedError {
    case invalidLayerCount
    case invalidSeed
    case imageCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidLayerCount:
            return "Layer count must be between 2 and 6."
        case .invalidSeed:
            return "Seed must be a number between 0 and 18446744073709551615."
        case .imageCreationFailed:
            return "Could not create a preview image."
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
