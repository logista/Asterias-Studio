#include <metal_stdlib>
using namespace metal;

struct FlatwaveUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    uint packetCount;
    uint interferenceMethod;
    float fudge;
};

struct FlatwavePacket {
    float originX;
    float originY;
    float cosine;
    float sine;
    float scale;
    float accelerationScale;
    float accelerationAmplitude;
    uint packMethod;
    uint accelerationPackMethod;
    uint isAccelerationEnabled;
};

static inline float clampUnit(float value) {
    return clamp(value, 0.0f, 1.0f);
}

static inline float packedCos(float distance, float scale, uint packMethod) {
    float rawCos = cos(distance * scale);
    switch (packMethod) {
        case 1:
            return rawCos >= 0.0f ? rawCos : -rawCos;
        case 2:
            return rawCos >= 0.0f ? rawCos : rawCos + 1.0f;
        case 0:
            return (rawCos + 1.0f) / 2.0f;
        default:
            return (cos(fmod(distance * scale, float(M_PI_F))) + 1.0f) / 2.0f;
    }
}

static inline float calcWave(float distance, float transverse, constant FlatwavePacket& packet) {
    float acceleration = packet.isAccelerationEnabled == 1
        ? packedCos(transverse, packet.accelerationScale, packet.accelerationPackMethod) * packet.accelerationAmplitude
        : 0.0f;
    return packedCos(distance + acceleration, packet.scale, packet.packMethod);
}

static inline float calcWavePacket(float2 point, constant FlatwavePacket& packet) {
    float relativeX = point.x - packet.originX;
    float relativeY = point.y - packet.originY;
    float transverse = (relativeX * packet.cosine) - (relativeY * packet.sine);
    float distance = (relativeX * packet.sine) + (relativeY * packet.cosine);
    return calcWave(distance, transverse, packet);
}

static inline float flatwave(float2 point, constant FlatwaveUniforms& uniforms, constant FlatwavePacket* packets) {
    float output;
    switch (uniforms.interferenceMethod) {
        case 3:
            output = 1.0f;
            break;
        case 0:
            output = 0.5f;
            break;
        default:
            output = 0.0f;
            break;
    }

    for (uint index = 0; index < uniforms.packetCount; ++index) {
        float layer = calcWavePacket(point, packets[index]);
        switch (uniforms.interferenceMethod) {
            case 0:
                output = fabs(layer - 0.5f) > fabs(output - 0.5f) ? layer : output;
                break;
            case 1:
                output = fabs(layer - 0.5f) < fabs(output - 0.5f) ? layer : output;
                break;
            case 2:
                output = max(layer, output);
                break;
            case 3:
                output = min(layer, output);
                break;
            default:
                output += layer;
                break;
        }
    }

    return uniforms.interferenceMethod == 4 ? output / float(uniforms.packetCount) : output;
}

static inline float sampledPoint(float2 point, constant FlatwaveUniforms& uniforms, constant FlatwavePacket* packets) {
    if (uniforms.isTilingEnabled == 0) {
        return clampUnit(flatwave(point, uniforms, packets));
    }

    float value = flatwave(point, uniforms, packets);
    float farH = point.x + 1.0f;
    float farV = point.y + 1.0f;
    float farValue1 = flatwave(float2(point.x, farV), uniforms, packets);
    float farValue2 = flatwave(float2(farH, point.y), uniforms, packets);
    float farValue3 = flatwave(float2(farH, farV), uniforms, packets);
    float nearWeightX = point.x;
    float nearWeightY = point.y;
    float farWeightX = 1.0f - nearWeightX;
    float farWeightY = 1.0f - nearWeightY;

    value = (value * nearWeightX * nearWeightY)
        + (farValue1 * nearWeightX * farWeightY)
        + (farValue2 * farWeightX * nearWeightY)
        + (farValue3 * farWeightX * farWeightY);
    return clampUnit(value);
}

static inline uint wrappedCoordinate(uint value, uint limit) {
    return value < limit ? value : value - limit;
}

kernel void asteriasFlatwaveKernel(
    device float* output [[buffer(0)]],
    constant FlatwaveUniforms& uniforms [[buffer(1)]],
    constant FlatwavePacket* packets [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    uint mappedX = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.x + uniforms.rollX, uniforms.width) : gid.x;
    uint mappedY = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.y + uniforms.rollY, uniforms.height) : gid.y;
    float2 point = float2(float(mappedX) / float(uniforms.width), float(mappedY) / float(uniforms.height));

    float value = sampledPoint(point, uniforms, packets);
    value += sampledPoint(float2(point.x + uniforms.fudge, point.y), uniforms, packets);
    value += sampledPoint(float2(point.x, point.y + uniforms.fudge), uniforms, packets);
    value += sampledPoint(float2(point.x + uniforms.fudge, point.y + uniforms.fudge), uniforms, packets);

    output[gid.y * uniforms.width + gid.x] = clampUnit(value / 4.0f);
}
