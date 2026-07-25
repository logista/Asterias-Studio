import Foundation

/// Procedural pattern recipe after all random choices have been made.
struct AsteriasPattern: Sendable {
    let area: AsteriasArea
    let cutoffThreshold: Double
    let layers: [ColorLayer]
    let generatorMetrics: [AsteriasGeneratorMetric]

    static func random(
        area: AsteriasArea,
        layerCount requestedLayerCount: Int?,
        palette: AsteriasColorPalette,
        isTilingEnabled: Bool,
        allowedGenerators: Set<GeneratorKind>,
        using generator: inout SeededRandomNumberGenerator
    ) throws -> AsteriasPattern {
        let layerCount: Int
        if let requestedLayerCount {
            guard AsteriasRenderer.minimumLayerCount...AsteriasRenderer.maximumLayerCount ~= requestedLayerCount else {
                throw AsteriasError.invalidLayerCount
            }
            layerCount = requestedLayerCount
        } else {
            layerCount = Int.random(in: AsteriasRenderer.minimumLayerCount...AsteriasRenderer.maximumLayerCount, using: &generator)
        }

        let cutoffThreshold = Double.random(in: 0...AsteriasRenderer.maximumCutoffThreshold, using: &generator)
        var layers: [ColorLayer] = []
        var generatorMetrics: [AsteriasGeneratorMetric] = []
        layers.reserveCapacity(layerCount)
        generatorMetrics.reserveCapacity(layerCount * 2)

        for layerIndex in 0..<layerCount {
            let background = palette.sample(using: &generator)
            var foreground = palette.sample(using: &generator)
            while foreground.hasSameRGB(as: background) {
                foreground = palette.sample(using: &generator)
            }

            // Image and mask generators for a layer share the same random
            // parameter bundle, which keeps paired masks visually related to
            // the colors they reveal.
            let params = GeneratorParams.random(using: &generator)
            let imageGenerator = GeneratorKind.random(from: allowedGenerators, using: &generator)
            let maskGenerator = GeneratorKind.random(from: allowedGenerators, using: &generator)
            let imageStart = Date()
            let image = AsteriasGenerators.generate(area: area, generator: imageGenerator, params: params, isTilingEnabled: isTilingEnabled, using: &generator)
            generatorMetrics.append(AsteriasGeneratorMetric(layerIndex: layerIndex, role: .image, kind: imageGenerator, seconds: Date().timeIntervalSince(imageStart)))

            let mask: PixelMap?
            if Bool.random(using: &generator) {
                let maskStart = Date()
                mask = AsteriasGenerators.generate(area: area, generator: maskGenerator, params: params, isTilingEnabled: isTilingEnabled, using: &generator)
                generatorMetrics.append(AsteriasGeneratorMetric(layerIndex: layerIndex, role: .mask, kind: maskGenerator, seconds: Date().timeIntervalSince(maskStart)))
            } else {
                mask = nil
            }

            layers.append(
                ColorLayer(
                    image: image,
                    foreground: foreground,
                    background: background,
                    mask: mask,
                    invertMask: Bool.random(using: &generator)
                )
            )
        }

        return AsteriasPattern(area: area, cutoffThreshold: cutoffThreshold, layers: layers, generatorMetrics: generatorMetrics)
    }

    func renderRGBAData() -> Data {
        var bytes = [UInt8](repeating: 0, count: area.width * area.height * 4)
        var byteIndex = 0
        // Precompute channel deltas once so the inner pixel loop only performs
        // simple interpolation and alpha accumulation.
        let compositeLayers = layers.map(CompositeLayer.init(layer:))

        for y in 0..<area.height {
            let rowOffset = y * area.width
            for x in 0..<area.width {
                let pixelIndex = rowOffset + x
                var outputRed: Float = 0
                var outputGreen: Float = 0
                var outputBlue: Float = 0
                var outputAlpha: Float = 0

                for layer in compositeLayers {
                    let imageValue = layer.imageValues[pixelIndex]
                    // A missing mask means the image field controls both color
                    // interpolation and layer opacity.
                    let rawMaskValue = layer.maskValues?[pixelIndex] ?? imageValue
                    let maskValue = layer.invertMask ? 1 - rawMaskValue : rawMaskValue
                    let inverseAlpha = 1 - outputAlpha
                    let layerRed = imageValue * layer.redDelta + layer.backgroundRed
                    let layerGreen = imageValue * layer.greenDelta + layer.backgroundGreen
                    let layerBlue = imageValue * layer.blueDelta + layer.backgroundBlue

                    outputRed = (outputRed * outputAlpha) + (layerRed * inverseAlpha)
                    outputGreen = (outputGreen * outputAlpha) + (layerGreen * inverseAlpha)
                    outputBlue = (outputBlue * outputAlpha) + (layerBlue * inverseAlpha)

                    // Layers accumulate until the pixel is fully opaque. The
                    // cutoff lets nearly-opaque stacks terminate early, which
                    // preserves the original Asterias-style hard layering.
                    let layerAlpha = maskValue * inverseAlpha
                    if layerAlpha + outputAlpha + Float(cutoffThreshold) >= 1 {
                        outputAlpha = 1
                        break
                    } else {
                        outputAlpha += layerAlpha
                    }
                }

                bytes[byteIndex] = UInt8(min(max(outputRed * 255, 0), 255))
                bytes[byteIndex + 1] = UInt8(min(max(outputGreen * 255, 0), 255))
                bytes[byteIndex + 2] = UInt8(min(max(outputBlue * 255, 0), 255))
                bytes[byteIndex + 3] = 255
                byteIndex += 4
            }
        }

        return Data(bytes)
    }

}

/// Render-time cache of a layer's colors and optional mask data.
private struct CompositeLayer {
    let imageValues: [Float]
    let maskValues: [Float]?
    let invertMask: Bool
    let backgroundRed: Float
    let backgroundGreen: Float
    let backgroundBlue: Float
    let redDelta: Float
    let greenDelta: Float
    let blueDelta: Float

    init(layer: ColorLayer) {
        imageValues = layer.image.values
        maskValues = layer.mask?.values
        invertMask = layer.invertMask
        backgroundRed = Float(layer.background.red)
        backgroundGreen = Float(layer.background.green)
        backgroundBlue = Float(layer.background.blue)
        redDelta = Float(layer.foreground.red - layer.background.red)
        greenDelta = Float(layer.foreground.green - layer.background.green)
        blueDelta = Float(layer.foreground.blue - layer.background.blue)
    }
}

/// Describes whether a generator was used as visible image data or as a mask.
enum AsteriasGeneratorRole: Sendable {
    case image
    case mask

    var label: String {
        switch self {
        case .image: "Image"
        case .mask: "Mask"
        }
    }
}

/// Timing record for one generator invocation within a rendered pattern.
struct AsteriasGeneratorMetric: Sendable {
    let layerIndex: Int
    let role: AsteriasGeneratorRole
    let kind: GeneratorKind
    let seconds: TimeInterval

    var formattedSummary: String {
        "L\(layerIndex + 1) \(role.label) \(kind.label): \(AsteriasRenderMetrics.format(seconds))"
    }
}

/// One composited layer: a grayscale image field mapped between two colors.
struct ColorLayer: Sendable {
    let image: PixelMap
    let foreground: AsteriasColor
    let background: AsteriasColor
    let mask: PixelMap?
    let invertMask: Bool
}

/// Finite palette source. An empty palette intentionally means random colors.
struct AsteriasColorPalette: Sendable {
    let colors: [AsteriasColor]

    static let random = AsteriasColorPalette(colors: [])

    func sample(using generator: inout SeededRandomNumberGenerator) -> AsteriasColor {
        guard !colors.isEmpty else {
            return AsteriasColor.random(using: &generator)
        }
        return colors[Int.random(in: 0..<colors.count, using: &generator)]
    }
}

/// Built-in palettes shown in the UI and stored in exported recipes.
enum AsteriasPalettePreset: String, CaseIterable, Identifiable, Sendable {
    case random
    case ocean
    case sunset
    case forest
    case neon
    case pastel
    case graphite
    case userDefined

    var id: String { rawValue }

    var label: String {
        switch self {
        case .random: "Random"
        case .ocean: "Ocean"
        case .sunset: "Sunset"
        case .forest: "Forest"
        case .neon: "Neon"
        case .pastel: "Pastel"
        case .graphite: "Graphite"
        case .userDefined: "User Defined"
        }
    }

    func palette(customColors: [AsteriasColor]) -> AsteriasColorPalette {
        switch self {
        case .random:
            return .random
        case .ocean:
            return AsteriasColorPalette(colors: [
                AsteriasColor(red: 0.02, green: 0.12, blue: 0.22, alpha: 0),
                AsteriasColor(red: 0.00, green: 0.42, blue: 0.58, alpha: 0),
                AsteriasColor(red: 0.18, green: 0.78, blue: 0.82, alpha: 0),
                AsteriasColor(red: 0.52, green: 0.88, blue: 0.70, alpha: 0),
                AsteriasColor(red: 0.86, green: 0.97, blue: 0.92, alpha: 0)
            ])
        case .sunset:
            return AsteriasColorPalette(colors: [
                AsteriasColor(red: 0.10, green: 0.04, blue: 0.14, alpha: 0),
                AsteriasColor(red: 0.48, green: 0.10, blue: 0.34, alpha: 0),
                AsteriasColor(red: 0.94, green: 0.26, blue: 0.19, alpha: 0),
                AsteriasColor(red: 1.00, green: 0.52, blue: 0.20, alpha: 0),
                AsteriasColor(red: 1.00, green: 0.72, blue: 0.28, alpha: 0)
            ])
        case .forest:
            return AsteriasColorPalette(colors: [
                AsteriasColor(red: 0.04, green: 0.12, blue: 0.07, alpha: 0),
                AsteriasColor(red: 0.13, green: 0.36, blue: 0.19, alpha: 0),
                AsteriasColor(red: 0.35, green: 0.54, blue: 0.24, alpha: 0),
                AsteriasColor(red: 0.58, green: 0.70, blue: 0.32, alpha: 0),
                AsteriasColor(red: 0.91, green: 0.86, blue: 0.58, alpha: 0)
            ])
        case .neon:
            return AsteriasColorPalette(colors: [
                AsteriasColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 0),
                AsteriasColor(red: 0.00, green: 0.95, blue: 0.95, alpha: 0),
                AsteriasColor(red: 1.00, green: 0.06, blue: 0.52, alpha: 0),
                AsteriasColor(red: 0.55, green: 0.16, blue: 1.00, alpha: 0),
                AsteriasColor(red: 0.95, green: 1.00, blue: 0.10, alpha: 0)
            ])
        case .pastel:
            return AsteriasColorPalette(colors: [
                AsteriasColor(red: 0.98, green: 0.72, blue: 0.78, alpha: 0),
                AsteriasColor(red: 0.73, green: 0.86, blue: 1.00, alpha: 0),
                AsteriasColor(red: 0.76, green: 0.94, blue: 0.76, alpha: 0),
                AsteriasColor(red: 0.86, green: 0.76, blue: 0.97, alpha: 0),
                AsteriasColor(red: 0.99, green: 0.92, blue: 0.62, alpha: 0)
            ])
        case .graphite:
            return AsteriasColorPalette(colors: [
                AsteriasColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0),
                AsteriasColor(red: 0.18, green: 0.19, blue: 0.20, alpha: 0),
                AsteriasColor(red: 0.38, green: 0.40, blue: 0.42, alpha: 0),
                AsteriasColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 0),
                AsteriasColor(red: 0.92, green: 0.92, blue: 0.88, alpha: 0)
            ])
        case .userDefined:
            return AsteriasColorPalette(colors: customColors)
        }
    }
}

/// Linear RGB color used by the renderer before conversion to 8-bit RGBA.
struct AsteriasColor: Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let zero = AsteriasColor(red: 0, green: 0, blue: 0, alpha: 0)

    static func random(using generator: inout SeededRandomNumberGenerator) -> AsteriasColor {
        AsteriasColor(
            red: Double.random(in: 0...1, using: &generator),
            green: Double.random(in: 0...1, using: &generator),
            blue: Double.random(in: 0...1, using: &generator),
            alpha: 0
        )
    }

    func scaled(by factor: Double) -> AsteriasColor {
        AsteriasColor(red: red * factor, green: green * factor, blue: blue * factor, alpha: alpha * factor)
    }

    func hasSameRGB(as other: AsteriasColor) -> Bool {
        red == other.red && green == other.green && blue == other.blue
    }
}

/// Single-channel floating point image used as generator output and masks.
struct PixelMap: Sendable {
    let width: Int
    let height: Int
    var values: [Float]

    init(width: Int, height: Int, values: [Float]? = nil) {
        self.width = width
        self.height = height
        self.values = values ?? [Float](repeating: 0, count: width * height)
    }

    subscript(x: Int, y: Int) -> Double {
        get { Double(values[y * width + x]) }
        set { values[y * width + x] = Float(newValue) }
    }
}
