import Foundation
import Metal

final class AsteriasMetalSpinflakeRenderer: @unchecked Sendable {
    static let shared = AsteriasMetalSpinflakeRenderer()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    private init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let function = library.makeFunction(name: "asteriasSpinflakeKernel"),
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
        params: SpinflakeParams,
        isTilingEnabled: Bool,
        rollX: Int,
        rollY: Int
    ) -> PixelMap? {
        let pixelCount = area.width * area.height
        guard pixelCount > 0, !params.florets.isEmpty else { return nil }

        var uniforms = MetalSpinflakeUniforms(
            width: UInt32(area.width),
            height: UInt32(area.height),
            rollX: UInt32(rollX),
            rollY: UInt32(rollY),
            isTilingEnabled: isTilingEnabled ? 1 : 0,
            floretCount: UInt32(params.florets.count),
            averageFlorets: params.averageFlorets ? 1 : 0,
            originX: Float(params.origin.x),
            originY: Float(params.origin.y),
            radius: Float(params.radius),
            squish: Float(params.squish),
            twistCosine: Float(params.twistCosine),
            twistSine: Float(params.twistSine),
            fudge: Float(1.0 / Double(area.width + area.height))
        )
        var florets = params.florets.map(MetalSpinflakeFloret.init(floret:))

        guard
            let outputBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.stride, options: .storageModeShared),
            let uniformBuffer = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<MetalSpinflakeUniforms>.stride, options: .storageModeShared),
            let floretBuffer = device.makeBuffer(bytes: &florets, length: florets.count * MemoryLayout<MetalSpinflakeFloret>.stride, options: .storageModeShared),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setBuffer(floretBuffer, offset: 0, index: 2)

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

private struct MetalSpinflakeUniforms {
    var width: UInt32
    var height: UInt32
    var rollX: UInt32
    var rollY: UInt32
    var isTilingEnabled: UInt32
    var floretCount: UInt32
    var averageFlorets: UInt32
    var originX: Float
    var originY: Float
    var radius: Float
    var squish: Float
    var twistCosine: Float
    var twistSine: Float
    var fudge: Float
}

private struct MetalSpinflakeFloret {
    var sineMethod: UInt32
    var backward: UInt32
    var spines: Float
    var spineRadius: Float
    var twirlBase: Float
    var twirlSpeed: Float
    var twirlAmplitude: Float
    var twirlMethod: UInt32

    init(floret: Floret) {
        sineMethod = UInt32(floret.sineMethod.metalValue)
        backward = floret.backward ? 1 : 0
        spines = Float(floret.spines)
        spineRadius = Float(floret.spineRadius)
        twirlBase = Float(floret.twirl.base)
        twirlSpeed = Float(floret.twirl.speed)
        twirlAmplitude = Float(floret.twirl.amplitude)
        twirlMethod = UInt32(floret.twirl.method.metalValue)
    }
}

private extension SinePositivizingMethod {
    var metalValue: Int {
        switch self {
        case .compress: 0
        case .truncate: 1
        case .absolute: 2
        case .sawblade: 3
        }
    }
}

private extension TwirlMethod {
    var metalValue: Int {
        switch self {
        case .none: 0
        case .curve: 1
        case .sine: 2
        }
    }
}
