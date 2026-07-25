#include <metal_stdlib>
using namespace metal;

struct RangefracUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    uint matrixSize;
    float tweaker;
};

static inline uint wrappedCoordinate(uint value, uint limit) {
    return value < limit ? value : value - limit;
}

static inline int wrapMatrixCoordinate(int coordinate, int size) {
    int value = coordinate % size;
    return value >= 0 ? value : value + size;
}

static inline float rangefracValue(float2 point, constant RangefracUniforms& uniforms, constant float* source) {
    int size = int(uniforms.matrixSize);
    float scaledX = point.x * float(size);
    float scaledY = point.y * float(size);
    int left = int(floor(scaledX - uniforms.tweaker));
    int top = int(floor(scaledY - uniforms.tweaker));

    int2 corners[4] = {
        int2(left, top),
        int2(left + 1, top),
        int2(left, top + 1),
        int2(left + 1, top + 1)
    };

    float totalSum = 0.0f;
    float totalWeight = 0.0f;
    for (uint index = 0; index < 4; ++index) {
        int wrappedX = wrapMatrixCoordinate(corners[index].x, size);
        int wrappedY = wrapMatrixCoordinate(corners[index].y, size);
        float value = source[wrappedY * size + wrappedX];
        float deltaX = float(corners[index].x) - scaledX;
        float deltaY = float(corners[index].y) - scaledY;
        float distance = sqrt((deltaX * deltaX) + (deltaY * deltaY));
        float weight = max(0.0f, 1.0f - distance);
        totalSum += value * weight;
        totalWeight += weight;
    }

    return totalWeight == 0.0f ? 0.0f : totalSum / totalWeight;
}

kernel void asteriasRangefracKernel(
    device float* output [[buffer(0)]],
    constant RangefracUniforms& uniforms [[buffer(1)]],
    constant float* source [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    uint mappedX = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.x + uniforms.rollX, uniforms.width) : gid.x;
    uint mappedY = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.y + uniforms.rollY, uniforms.height) : gid.y;
    float2 point = float2(float(mappedX) / float(uniforms.width), float(mappedY) / float(uniforms.height));

    output[gid.y * uniforms.width + gid.x] = clamp(rangefracValue(point, uniforms, source), 0.0f, 1.0f);
}
