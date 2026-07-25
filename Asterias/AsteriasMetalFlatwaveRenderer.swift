import Foundation
import Metal

final class AsteriasMetalFlatwaveRenderer: @unchecked Sendable {
    static let shared = AsteriasMetalFlatwaveRenderer()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    private init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let function = library.makeFunction(name: "asteriasFlatwaveKernel"),
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
        params: FlatwaveParams,
        isTilingEnabled: Bool,
        rollX: Int,
        rollY: Int
    ) -> PixelMap? {
        let pixelCount = area.width * area.height
        guard pixelCount > 0, !params.packets.isEmpty else { return nil }

        var uniforms = MetalFlatwaveUniforms(
            width: UInt32(area.width),
            height: UInt32(area.height),
            rollX: UInt32(rollX),
            rollY: UInt32(rollY),
            isTilingEnabled: isTilingEnabled ? 1 : 0,
            packetCount: UInt32(params.packets.count),
            interferenceMethod: UInt32(params.interferenceMethod.metalValue),
            fudge: Float(1.0 / Double(area.width + area.height))
        )
        var packets = params.packets.map(MetalFlatwavePacket.init(packet:))

        guard
            let outputBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.stride, options: .storageModeShared),
            let uniformBuffer = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<MetalFlatwaveUniforms>.stride, options: .storageModeShared),
            let packetBuffer = device.makeBuffer(bytes: &packets, length: packets.count * MemoryLayout<MetalFlatwavePacket>.stride, options: .storageModeShared),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setBuffer(packetBuffer, offset: 0, index: 2)

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

private struct MetalFlatwaveUniforms {
    var width: UInt32
    var height: UInt32
    var rollX: UInt32
    var rollY: UInt32
    var isTilingEnabled: UInt32
    var packetCount: UInt32
    var interferenceMethod: UInt32
    var fudge: Float
}

private struct MetalFlatwavePacket {
    var originX: Float
    var originY: Float
    var cosine: Float
    var sine: Float
    var scale: Float
    var accelerationScale: Float
    var accelerationAmplitude: Float
    var packMethod: UInt32
    var accelerationPackMethod: UInt32
    var isAccelerationEnabled: UInt32

    init(packet: WavePacket) {
        originX = Float(packet.origin.x)
        originY = Float(packet.origin.y)
        cosine = Float(packet.cosine)
        sine = Float(packet.sine)
        scale = Float(packet.wave.scale)
        accelerationScale = Float(packet.wave.acceleration.scale)
        accelerationAmplitude = Float(packet.wave.acceleration.amplitude)
        packMethod = UInt32(packet.wave.packMethod.metalValue)
        accelerationPackMethod = UInt32(packet.wave.acceleration.pack.metalValue)
        isAccelerationEnabled = packet.wave.acceleration.method == .enabled ? 1 : 0
    }
}

private extension InterferenceMethod {
    var metalValue: Int {
        switch self {
        case .mostExtreme: 0
        case .leastExtreme: 1
        case .max: 2
        case .min: 3
        case .average: 4
        }
    }
}
