import CoreGraphics
import Foundation
import Testing
@testable import Asterias_Studio

@Suite("Renderer")
struct RendererTests {
    @Test func seededGeneratorIsStable() {
        var generator = SeededRandomNumberGenerator(seed: 1)

        #expect(generator.next() == 10_451_216_379_200_822_465)
        #expect(generator.next() == 13_757_245_211_066_428_519)
        #expect(generator.next() == 17_911_839_290_282_890_590)
    }

    @Test func renderClampsDimensionsAndPreservesExplicitSeed() throws {
        let options = AsteriasRenderOptions(
            area: AsteriasArea(width: 0, height: -4),
            layerCount: AsteriasRenderer.minimumLayerCount,
            palette: fixedPalette,
            isTilingEnabled: true,
            allowedGenerators: [.rangefrac],
            seed: 42
        )

        let rendered = try AsteriasRenderer.render(options: options)

        #expect(rendered.width == 1)
        #expect(rendered.height == 1)
        #expect(rendered.seed == 42)
        #expect(rendered.rgbaData.count == 4)
        #expect(rendered.cgImage.width == 1)
        #expect(rendered.cgImage.height == 1)
        #expect(rendered.metrics.layerCount == AsteriasRenderer.minimumLayerCount)
    }

    @Test func renderRejectsInvalidLayerCounts() {
        let options = AsteriasRenderOptions(
            area: AsteriasArea(width: 2, height: 2),
            layerCount: AsteriasRenderer.minimumLayerCount - 1,
            palette: fixedPalette,
            isTilingEnabled: true,
            allowedGenerators: [.rangefrac],
            seed: 7
        )

        #expect(throws: AsteriasError.invalidLayerCount) {
            _ = try AsteriasRenderer.render(options: options)
        }
    }

    @Test func renderWithFixedSeedIsRepeatable() throws {
        let options = AsteriasRenderOptions(
            area: AsteriasArea(width: 4, height: 4),
            layerCount: AsteriasRenderer.minimumLayerCount,
            palette: fixedPalette,
            isTilingEnabled: true,
            allowedGenerators: [.rangefrac],
            seed: 99
        )

        let first = try AsteriasRenderer.render(options: options)
        let second = try AsteriasRenderer.render(options: options)

        #expect(first.rgbaData == second.rgbaData)
        #expect(first.metrics.generatorMetrics.map(\.kind) == second.metrics.generatorMetrics.map(\.kind))
        #expect(first.metrics.generatorMetrics.map(\.role) == second.metrics.generatorMetrics.map(\.role))
    }
}

private let fixedPalette = AsteriasColorPalette(colors: [
    AsteriasColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
    AsteriasColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
])
