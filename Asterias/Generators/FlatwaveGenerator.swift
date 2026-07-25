import Foundation

/// Layer-compositing modes for combining several linear wave packets.
enum InterferenceMethod: Sendable {
    case mostExtreme
    case leastExtreme
    case max
    case min
    case average

    static func random(using generator: inout SeededRandomNumberGenerator) -> InterferenceMethod {
        switch Int.random(in: 0...4, using: &generator) {
        case 0: .mostExtreme
        case 1: .leastExtreme
        case 2: .max
        case 3: .min
        default: .average
        }
    }
}

/// Controls whether a wave packet's local frequency varies across space.
enum FlatwaveAccelerationMethod: Sendable {
    case enabled
    case disabled

    static func random(using generator: inout SeededRandomNumberGenerator) -> FlatwaveAccelerationMethod {
        Bool.random(using: &generator) ? .enabled : .disabled
    }
}

/// Secondary modulation applied to a flat wave's base scale.
struct FlatwaveAcceleration: Sendable {
    let scale: Double
    let amplitude: Double
    let pack: PackMethod
    let method: FlatwaveAccelerationMethod

    static func random(using generator: inout SeededRandomNumberGenerator) -> FlatwaveAcceleration {
        FlatwaveAcceleration(
            scale: Double.random(in: 2...30, using: &generator),
            amplitude: Double.random(in: 0...0.1, using: &generator),
            pack: PackMethod.random(using: &generator),
            method: FlatwaveAccelerationMethod.random(using: &generator)
        )
    }
}

/// Cosine wave definition shared by a packet.
struct FlatwaveWave: Sendable {
    let scale: Double
    let packMethod: PackMethod
    let acceleration: FlatwaveAcceleration

    static func random(using generator: inout SeededRandomNumberGenerator) -> FlatwaveWave {
        let packMethod = PackMethod.random(using: &generator)
        return FlatwaveWave(
            scale: Double.random(in: 2...30, using: &generator) * (packMethod == .scaleToFit ? 2.0 : 1.0),
            packMethod: packMethod,
            acceleration: FlatwaveAcceleration.random(using: &generator)
        )
    }
}

/// Oriented line wave with cached sine/cosine for fast sampling.
struct WavePacket: Sendable {
    let origin: GeneratorPoint
    let angle: Double
    let wave: FlatwaveWave
    let cosine: Double
    let sine: Double

    init(origin: GeneratorPoint, angle: Double, wave: FlatwaveWave) {
        self.origin = origin
        self.angle = angle
        self.wave = wave
        cosine = cos(angle)
        sine = sin(angle)
    }

    static func random(using generator: inout SeededRandomNumberGenerator) -> WavePacket {
        WavePacket(
            origin: GeneratorPoint.random(using: &generator),
            angle: Double.random(in: 0..<Double.pi, using: &generator),
            wave: FlatwaveWave.random(using: &generator)
        )
    }
}

/// Parameters for layered linear waves and interference.
struct FlatwaveParams: Sendable {
    let interferenceMethod: InterferenceMethod
    let packets: [WavePacket]

    static func random(using generator: inout SeededRandomNumberGenerator) -> FlatwaveParams {
        FlatwaveParams(
            interferenceMethod: InterferenceMethod.random(using: &generator),
            packets: (0..<Int.random(in: 2...4, using: &generator)).map { _ in WavePacket.random(using: &generator) }
        )
    }
}

/// Generates line-based wave interference fields.
enum Flatwave {
    @inline(__always)
    static func generate(_ point: GeneratorPoint, params: FlatwaveParams) -> Double {
        // Each method keeps the same packet samples but changes how they
        // interfere, producing bands, folds, or accumulated ridges.
        var output: Double
        switch params.interferenceMethod {
        case .min:
            output = 1.0
        case .mostExtreme:
            output = 0.5
        default:
            output = 0.0
        }

        for packet in params.packets {
            let layer = calcWavePacket(point, packet: packet)
            switch params.interferenceMethod {
            case .mostExtreme:
                output = abs(layer - 0.5) > abs(output - 0.5) ? layer : output
            case .leastExtreme:
                output = abs(layer - 0.5) < abs(output - 0.5) ? layer : output
            case .max:
                output = max(layer, output)
            case .min:
                output = min(layer, output)
            case .average:
                output += layer
            }
        }

        return params.interferenceMethod == .average ? output / Double(params.packets.count) : output
    }

    @inline(__always)
    private static func calcWavePacket(_ point: GeneratorPoint, packet: WavePacket) -> Double {
        let relativeX = point.x - packet.origin.x
        let relativeY = point.y - packet.origin.y
        // Rotate into packet-local coordinates. Distance runs along the wave
        // normal while transverse offsets modulate acceleration.
        let transverse = (relativeX * packet.cosine) - (relativeY * packet.sine)
        let distance = (relativeX * packet.sine) + (relativeY * packet.cosine)
        return calcWave(distance: distance, transverse: transverse, wave: packet.wave)
    }

    @inline(__always)
    private static func calcWave(distance: Double, transverse: Double, wave: FlatwaveWave) -> Double {
        let acceleration = wave.acceleration.method == .enabled
            ? AsteriasGenerators.packedCos(distance: transverse, scale: wave.acceleration.scale, packMethod: wave.acceleration.pack) * wave.acceleration.amplitude
            : 0.0
        return AsteriasGenerators.packedCos(distance: distance + acceleration, scale: wave.scale, packMethod: wave.packMethod)
    }
}
