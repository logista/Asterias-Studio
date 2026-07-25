import Foundation
import Metal

final class AsteriasMetalFlameRenderer: @unchecked Sendable {
    static let shared = AsteriasMetalFlameRenderer()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    private init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let function = library.makeFunction(name: "asteriasFlameKernel"),
            let pipelineState = try? device.makeComputePipelineState(function: function)
        else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
    }

    func generate(
        area: AsteriasArea,
        params: FlameParams,
        isTilingEnabled: Bool,
        rollX: Int,
        rollY: Int
    ) -> PixelMap? {
        let pixelCount = area.width * area.height
        guard pixelCount > 0, !params.transforms.isEmpty else { return nil }

        var uniforms = MetalFlameUniforms(
            width: UInt32(area.width),
            height: UInt32(area.height),
            rollX: UInt32(rollX),
            rollY: UInt32(rollY),
            isTilingEnabled: isTilingEnabled ? 1 : 0,
            transformCount: UInt32(params.transforms.count),
            contrast: Float(params.contrast),
            glow: Float(params.glow),
            isInverted: params.isInverted ? 1 : 0,
            fudge: Float(1.0 / Double(area.width + area.height))
        )
        var transforms = params.transforms.map(MetalFlameTransform.init(transform:))

        guard
            let outputBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.stride, options: .storageModeShared),
            let uniformBuffer = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<MetalFlameUniforms>.stride, options: .storageModeShared),
            let transformBuffer = device.makeBuffer(bytes: &transforms, length: transforms.count * MemoryLayout<MetalFlameTransform>.stride, options: .storageModeShared),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setBuffer(transformBuffer, offset: 0, index: 2)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadsPerGrid = MTLSize(width: area.width, height: area.height, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed else { return nil }

        let outputPointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: pixelCount)
        let values = Array(UnsafeBufferPointer(start: outputPointer, count: pixelCount))
        return PixelMap(width: area.width, height: area.height, values: values)
    }
}

private struct MetalFlameUniforms {
    var width: UInt32
    var height: UInt32
    var rollX: UInt32
    var rollY: UInt32
    var isTilingEnabled: UInt32
    var transformCount: UInt32
    var contrast: Float
    var glow: Float
    var isInverted: UInt32
    var fudge: Float
}

private struct MetalFlameTransform {
    var originX: Float
    var originY: Float
    var cosine: Float
    var sine: Float
    var scale: Float
    var twist: Float
    var ridgeScale: Float
    var sharpness: Float
    var weight: Float
    var phase: Float
    var symmetry: UInt32
    var variation: UInt32

    init(transform: FlameTransform) {
        originX = Float(transform.origin.x)
        originY = Float(transform.origin.y)
        cosine = Float(transform.cosine)
        sine = Float(transform.sine)
        scale = Float(transform.scale)
        twist = Float(transform.twist)
        ridgeScale = Float(transform.ridgeScale)
        sharpness = Float(transform.sharpness)
        weight = Float(transform.weight)
        phase = Float(transform.phase)
        symmetry = UInt32(transform.symmetry)
        variation = UInt32(transform.variation.metalValue)
    }
}

private extension FlameVariation {
    var metalValue: Int {
        switch self {
        case .linear: 0
        case .sinusoidal: 1
        case .swirl: 2
        case .horseshoe: 3
        case .fan: 4
        }
    }
}
