import Foundation
import Testing
@testable import Asterias_Studio

@Suite("Pattern")
struct PatternTests {
    @Test func pixelMapInitializesAndSubscripts() {
        var map = PixelMap(width: 2, height: 2)

        map[1, 1] = 0.75

        #expect(map.width == 2)
        #expect(map.height == 2)
        #expect(map.values.count == 4)
        #expect(map[1, 1] == 0.75)
    }

    @Test func renderRGBADataMapsImageValueBetweenLayerColors() {
        let pattern = AsteriasPattern(
            area: AsteriasArea(width: 1, height: 1),
            cutoffThreshold: 0,
            layers: [
                ColorLayer(
                    image: PixelMap(width: 1, height: 1, values: [0.5]),
                    foreground: AsteriasColor(red: 1, green: 1, blue: 1, alpha: 0),
                    background: AsteriasColor(red: 0, green: 0, blue: 0, alpha: 0),
                    mask: PixelMap(width: 1, height: 1, values: [1]),
                    invertMask: false
                )
            ],
            generatorMetrics: []
        )

        #expect(Array(pattern.renderRGBAData()) == [127, 127, 127, 255])
    }

    @Test func invertedMaskCanRevealLaterLayers() {
        let first = ColorLayer(
            image: PixelMap(width: 1, height: 1, values: [1]),
            foreground: AsteriasColor(red: 1, green: 0, blue: 0, alpha: 0),
            background: AsteriasColor.zero,
            mask: PixelMap(width: 1, height: 1, values: [1]),
            invertMask: true
        )
        let second = ColorLayer(
            image: PixelMap(width: 1, height: 1, values: [1]),
            foreground: AsteriasColor(red: 0, green: 0, blue: 1, alpha: 0),
            background: AsteriasColor.zero,
            mask: PixelMap(width: 1, height: 1, values: [1]),
            invertMask: false
        )
        let pattern = AsteriasPattern(
            area: AsteriasArea(width: 1, height: 1),
            cutoffThreshold: 0,
            layers: [first, second],
            generatorMetrics: []
        )

        #expect(Array(pattern.renderRGBAData()) == [0, 0, 255, 255])
    }

    @Test func paletteSamplesFromFixedColors() {
        var generator = SeededRandomNumberGenerator(seed: 3)
        let palette = AsteriasColorPalette(colors: [
            AsteriasColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0)
        ])

        let color = palette.sample(using: &generator)

        #expect(color.red == 0.2)
        #expect(color.green == 0.3)
        #expect(color.blue == 0.4)
    }

    @Test func metricSummariesIncludeLayerRoleAndGenerator() {
        let metric = AsteriasGeneratorMetric(layerIndex: 1, role: .mask, kind: .julia, seconds: 0.125)

        #expect(metric.formattedSummary == "L2 Mask Julia: 125 ms")
    }
}
