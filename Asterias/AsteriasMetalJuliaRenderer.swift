import Foundation
import Metal

final class AsteriasMetalJuliaRenderer: @unchecked Sendable {
    static let shared = AsteriasMetalJuliaRenderer()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    private init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let function = library.makeFunction(name: "asteriasJuliaKernel"),
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
        params: JuliaParams,
        isTilingEnabled: Bool,
        rollX: Int,
        rollY: Int
    ) -> PixelMap? {
        let pixelCount = area.width * area.height
        guard pixelCount > 0 else { return nil }

        var uniforms = MetalJuliaUniforms(
            width: UInt32(area.width),
            height: UInt32(area.height),
            rollX: UInt32(rollX),
            rollY: UInt32(rollY),
            isTilingEnabled: isTilingEnabled ? 1 : 0,
            constantX: Float(params.constantX),
            constantY: Float(params.constantY),
            centerX: Float(params.centerX),
            centerY: Float(params.centerY),
            zoom: Float(params.zoom),
            maxIterations: UInt32(params.maxIterations),
            stripeScale: Float(params.stripeScale),
            packMethod: UInt32(params.packMethod.metalValue),
            isInverted: params.isInverted ? 1 : 0,
            fudge: Float(1.0 / Double(area.width + area.height))
        )

        guard
            let outputBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.stride, options: .storageModeShared),
            let uniformBuffer = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<MetalJuliaUniforms>.stride, options: .storageModeShared),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBuffer(uniformBuffer, offset: 0, index: 1)

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

private struct MetalJuliaUniforms {
    var width: UInt32
    var height: UInt32
    var rollX: UInt32
    var rollY: UInt32
    var isTilingEnabled: UInt32
    var constantX: Float
    var constantY: Float
    var centerX: Float
    var centerY: Float
    var zoom: Float
    var maxIterations: UInt32
    var stripeScale: Float
    var packMethod: UInt32
    var isInverted: UInt32
    var fudge: Float
}
