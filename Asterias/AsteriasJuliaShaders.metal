#include <metal_stdlib>
using namespace metal;

struct JuliaUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    float constantX;
    float constantY;
    float centerX;
    float centerY;
    float zoom;
    uint maxIterations;
    float stripeScale;
    uint packMethod;
    uint isInverted;
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

static inline float julia(float2 point, constant JuliaUniforms& uniforms) {
    float scale = 3.0f / uniforms.zoom;
    float zx = uniforms.centerX + ((point.x - 0.5f) * scale);
    float zy = uniforms.centerY + ((point.y - 0.5f) * scale);
    uint iteration = 0;
    float radiusSquared = (zx * zx) + (zy * zy);

    while (iteration < uniforms.maxIterations && radiusSquared <= 16.0f) {
        float nextX = (zx * zx) - (zy * zy) + uniforms.constantX;
        zy = (2.0f * zx * zy) + uniforms.constantY;
        zx = nextX;
        radiusSquared = (zx * zx) + (zy * zy);
        iteration += 1;
    }

    float value;
    if (iteration == uniforms.maxIterations) {
        value = 1.0f;
    } else {
        float magnitude = sqrt(radiusSquared);
        float smoothIteration = float(iteration) + 1.0f - (log(log(magnitude)) / log(2.0f));
        float normalized = clampUnit(smoothIteration / float(uniforms.maxIterations));
        float bands = packedCos(normalized, uniforms.stripeScale, uniforms.packMethod);
        value = ((1.0f - normalized) * 0.35f) + (bands * 0.65f);
    }

    return uniforms.isInverted == 1 ? 1.0f - value : value;
}

static inline float sampledPoint(float2 point, constant JuliaUniforms& uniforms) {
    if (uniforms.isTilingEnabled == 0) {
        return clampUnit(julia(point, uniforms));
    }

    float value = julia(point, uniforms);
    float farH = point.x + 1.0f;
    float farV = point.y + 1.0f;
    float farValue1 = julia(float2(point.x, farV), uniforms);
    float farValue2 = julia(float2(farH, point.y), uniforms);
    float farValue3 = julia(float2(farH, farV), uniforms);
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

kernel void asteriasJuliaKernel(
    device float* output [[buffer(0)]],
    constant JuliaUniforms& uniforms [[buffer(1)]],
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
