import Foundation
import Metal

final class AsteriasMetalVoronoiRenderer: @unchecked Sendable {
    static let shared = AsteriasMetalVoronoiRenderer()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    private init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let function = library.makeFunction(name: "asteriasVoronoiKernel"),
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
        params: VoronoiParams,
        isTilingEnabled: Bool,
        rollX: Int,
        rollY: Int
    ) -> PixelMap? {
        let pixelCount = area.width * area.height
        guard pixelCount > 0, !params.cells.isEmpty else { return nil }

        var uniforms = MetalVoronoiUniforms(
            width: UInt32(area.width),
            height: UInt32(area.height),
            rollX: UInt32(rollX),
            rollY: UInt32(rollY),
            isTilingEnabled: isTilingEnabled ? 1 : 0,
            cellCount: UInt32(params.cells.count),
            distanceMethod: UInt32(params.distanceMethod.metalValue),
            outputMethod: UInt32(params.outputMethod.metalValue),
            contrast: Float(params.contrast),
            ridgeScale: Float(params.ridgeScale),
            isInverted: params.isInverted ? 1 : 0
        )
        var cells = params.cells.map(MetalVoronoiCell.init(cell:))

        guard
            let outputBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.stride, options: .storageModeShared),
            let uniformBuffer = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<MetalVoronoiUniforms>.stride, options: .storageModeShared),
            let cellBuffer = device.makeBuffer(bytes: &cells, length: cells.count * MemoryLayout<MetalVoronoiCell>.stride, options: .storageModeShared),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setBuffer(cellBuffer, offset: 0, index: 2)

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

private struct MetalVoronoiUniforms {
    var width: UInt32
    var height: UInt32
    var rollX: UInt32
    var rollY: UInt32
    var isTilingEnabled: UInt32
    var cellCount: UInt32
    var distanceMethod: UInt32
    var outputMethod: UInt32
    var contrast: Float
    var ridgeScale: Float
    var isInverted: UInt32
}

private struct MetalVoronoiCell {
    var originX: Float
    var originY: Float
    var value: Float

    init(cell: VoronoiCell) {
        originX = Float(cell.origin.x)
        originY = Float(cell.origin.y)
        value = Float(cell.value)
    }
}

private extension VoronoiDistanceMethod {
    var metalValue: Int {
        switch self {
        case .euclidean: 0
        case .manhattan: 1
        case .chebyshev: 2
        }
    }
}

private extension VoronoiOutputMethod {
    var metalValue: Int {
        switch self {
        case .cells: 0
        case .edges: 1
        case .ridges: 2
        }
    }
}
