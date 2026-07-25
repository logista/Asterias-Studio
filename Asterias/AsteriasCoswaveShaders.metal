#include <metal_stdlib>
using namespace metal;

struct CoswaveUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    float originX;
    float originY;
    float waveScale;
    float squish;
    float squareAngle;
    float distortion;
    uint packMethod;
    uint accelerationMethod;
    float acceleration;
    float fudge;
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

static inline float coswave(float2 point, constant CoswaveUniforms& uniforms) {
    float relativeX = point.x - uniforms.originX;
    float relativeY = point.y - uniforms.originY;
    float hypotenuse = sqrt((relativeX * relativeX) + (relativeY * relativeY));
    float hypAngle = atan((relativeY / relativeX) * uniforms.distortion) + uniforms.squareAngle;
    float x = cos(hypAngle) * hypotenuse;
    float y = sin(hypAngle) * hypotenuse;
    float squishedX = x * uniforms.squish;
    float squishedY = y / uniforms.squish;
    float squishedDistance = sqrt((squishedX * squishedX) + (squishedY * squishedY));
    float scale = uniforms.accelerationMethod == 0 ? uniforms.waveScale : pow(uniforms.waveScale, squishedDistance * uniforms.acceleration);
    float rawCos = packedCos(squishedDistance, scale, uniforms.packMethod);
    return (rawCos + 1.0f) / 2.0f;
}

static inline float sampledPoint(float2 point, constant CoswaveUniforms& uniforms) {
    if (uniforms.isTilingEnabled == 0) {
        return clampUnit(coswave(point, uniforms));
    }

    float value = coswave(point, uniforms);
    float farH = point.x + 1.0f;
    float farV = point.y + 1.0f;
    float farValue1 = coswave(float2(point.x, farV), uniforms);
    float farValue2 = coswave(float2(farH, point.y), uniforms);
    float farValue3 = coswave(float2(farH, farV), uniforms);
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

kernel void asteriasCoswaveKernel(
    device float* output [[buffer(0)]],
    constant CoswaveUniforms& uniforms [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    uint mappedX = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.x + uniforms.rollX, uniforms.width) : gid.x;
    uint mappedY = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.y + uniforms.rollY, uniforms.height) : gid.y;
    float2 point = float2(float(mappedX) / float(uniforms.width), float(mappedY) / float(uniforms.height));

    float value = sampledPoint(point, uniforms);
    value += sampledPoint(float2(point.x + uniforms.fudge, point.y), uniforms);
    value += sampledPoint(float2(point.x, point.y + uniforms.fudge), uniforms);
    value += sampledPoint(float2(point.x + uniforms.fudge, point.y + uniforms.fudge), uniforms);

    output[gid.y * uniforms.width + gid.x] = clampUnit(value / 4.0f);
}
