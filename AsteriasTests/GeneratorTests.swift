import Foundation
import Testing
@testable import Asterias_Studio

@Suite("Generators")
struct GeneratorTests {
    @Test func generatorMetadataIsStable() {
        #expect(GeneratorKind.sortedByName.map(\.label) == [
            "Bubble",
            "Coswave",
            "Flame",
            "Flatwave",
            "Julia",
            "Rangefrac",
            "Spinflake",
            "Voronoi"
        ])
        #expect(PackMethod.scaleToFit.metalValue == 0)
        #expect(PackMethod.flipSignToFit.metalValue == 1)
        #expect(PackMethod.truncateToFit.metalValue == 2)
        #expect(PackMethod.slopeToFit.metalValue == 3)
    }

    @Test func emptyAllowedGeneratorSetFallsBackToAllGenerators() {
        let options = AsteriasRenderOptions(
            area: AsteriasArea(width: 1, height: 1),
            layerCount: nil,
            palette: .random,
            isTilingEnabled: true,
            allowedGenerators: [],
            seed: nil
        )

        #expect(options.effectiveAllowedGenerators == Set(GeneratorKind.allCases))
    }

    @Test func packedCosMethodsReturnUnitRangeValues() {
        for method in [PackMethod.scaleToFit, .flipSignToFit, .truncateToFit, .slopeToFit] {
            let value = AsteriasGenerators.packedCos(distance: 0.75, scale: 3.5, packMethod: method)
            #expect(value.isFinite)
            #expect((0.0...1.0).contains(value))
        }
    }

    @Test func handcraftedGeneratorsReturnFiniteClampableValues() {
        let point = GeneratorPoint(x: 0.35, y: 0.62)
        let values = [
            Coswave.generate(point, params: handmadeParams.coswave),
            Spinflake.generate(point, params: handmadeParams.spinflake),
            Rangefrac.generate(point, params: handmadeParams.rangefrac),
            Flatwave.generate(point, params: handmadeParams.flatwave),
            BubbleGenerator.generate(point, params: handmadeParams.bubble),
            JuliaGenerator.generate(point, params: handmadeParams.julia),
            VoronoiGenerator.generate(point, params: handmadeParams.voronoi),
            FlameGenerator.generate(point, params: handmadeParams.flame)
        ]

        for value in values {
            #expect(value.isFinite)
            #expect((0.0...1.0).contains(value.clamped(to: 0...1)))
        }
    }

    @Test func randomFactoriesCreateValidCollections() {
        var generator = SeededRandomNumberGenerator(seed: 123)

        let rangefrac = RangefracParams.random(using: &generator)
        let flatwave = FlatwaveParams.random(using: &generator)
        let bubble = BubbleParams.random(using: &generator)
        let voronoi = VoronoiParams.random(using: &generator)
        let flame = FlameParams.random(using: &generator)

        #expect(rangefrac.data.count == RangefracParams.matrixSize * RangefracParams.matrixSize)
        #expect((2...4).contains(flatwave.packets.count))
        #expect((8..<32).contains(bubble.bubbles.count))
        #expect((12...48).contains(voronoi.cells.count))
        #expect((3...7).contains(flame.transforms.count))
    }
}

private let handmadeParams = GeneratorParams(
    coswave: CoswaveParams(
        origin: GeneratorPoint(x: 0.2, y: 0.4),
        waveScale: 6,
        squish: 1.2,
        squareAngle: 0.3,
        distortion: 1.1,
        packMethod: .scaleToFit,
        accelerationMethod: .none,
        acceleration: 0
    ),
    spinflake: SpinflakeParams(
        origin: GeneratorPoint(x: 0.5, y: 0.5),
        radius: 0.7,
        squish: 0.6,
        twist: 0.4,
        averageFlorets: false,
        florets: [
            Floret(
                sineMethod: .compress,
                backward: false,
                spines: 6,
                spineRadius: 0.25,
                twirl: Twirl(base: 0.1, speed: 0, amplitude: 0, method: .none)
            )
        ]
    ),
    rangefrac: RangefracParams(data: [Double](repeating: 0.5, count: RangefracParams.matrixSize * RangefracParams.matrixSize)),
    flatwave: FlatwaveParams(
        interferenceMethod: .average,
        packets: [
            WavePacket(
                origin: GeneratorPoint(x: 0.2, y: 0.3),
                angle: 0.8,
                wave: FlatwaveWave(
                    scale: 5,
                    packMethod: .scaleToFit,
                    acceleration: FlatwaveAcceleration(scale: 2, amplitude: 0, pack: .scaleToFit, method: .disabled)
                )
            )
        ]
    ),
    bubble: BubbleParams(
        bubbles: [
            Bubble(scale: 0.3, squish: 1.2, angle: 0.4, origin: GeneratorPoint(x: 0.45, y: 0.45))
        ]
    ),
    julia: JuliaParams(
        constantX: -0.4,
        constantY: 0.6,
        centerX: 0,
        centerY: 0,
        zoom: 1.4,
        maxIterations: 80,
        stripeScale: 8,
        packMethod: .scaleToFit,
        isInverted: false
    ),
    voronoi: VoronoiParams(
        distanceMethod: .euclidean,
        outputMethod: .cells,
        cells: [
            VoronoiCell(origin: GeneratorPoint(x: 0.2, y: 0.2), value: 0.2),
            VoronoiCell(origin: GeneratorPoint(x: 0.8, y: 0.8), value: 0.8)
        ],
        contrast: 4,
        ridgeScale: 20,
        isInverted: false
    ),
    flame: FlameParams(
        transforms: [
            FlameTransform(
                origin: GeneratorPoint(x: 0.5, y: 0.5),
                angle: 0.2,
                scale: 1.2,
                twist: 1.0,
                symmetry: 5,
                ridgeScale: 12,
                sharpness: 2.5,
                weight: 0.8,
                phase: 0.3,
                variation: .linear
            )
        ],
        contrast: 1.1,
        glow: 0.9,
        isInverted: false
    )
)
