#include <metal_stdlib>
using namespace metal;

struct VoronoiUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    uint cellCount;
    uint distanceMethod;
    uint outputMethod;
    float contrast;
    float ridgeScale;
    uint isInverted;
};

struct VoronoiCell {
    float originX;
    float originY;
    float value;
};

static inline float clampUnit(float value) {
    return clamp(value, 0.0f, 1.0f);
}

static inline float packedCos(float distance, float scale) {
    return (cos(distance * scale) + 1.0f) / 2.0f;
}

static inline float wrappedDelta(float value) {
    float magnitude = fabs(value);
    return min(magnitude, 1.0f - magnitude);
}

static inline float cellDistance(float2 point, constant VoronoiCell& cell, uint distanceMethod) {
    float deltaX = wrappedDelta(point.x - cell.originX);
    float deltaY = wrappedDelta(point.y - cell.originY);

    switch (distanceMethod) {
        case 1:
            return fabs(deltaX) + fabs(deltaY);
        case 2:
            return max(fabs(deltaX), fabs(deltaY));
        default:
            return sqrt((deltaX * deltaX) + (deltaY * deltaY));
    }
}

static inline float voronoi(float2 point, constant VoronoiUniforms& uniforms, constant VoronoiCell* cells) {
    float nearestDistance = INFINITY;
    float secondNearestDistance = INFINITY;
    float nearestValue = 0.0f;

    for (uint index = 0; index < uniforms.cellCount; ++index) {
        float distance = cellDistance(point, cells[index], uniforms.distanceMethod);
        if (distance < nearestDistance) {
            secondNearestDistance = nearestDistance;
            nearestDistance = distance;
            nearestValue = cells[index].value;
        } else if (distance < secondNearestDistance) {
            secondNearestDistance = distance;
        }
    }

    float edgeDistance = max(0.0f, secondNearestDistance - nearestDistance);
    float value;
    switch (uniforms.outputMethod) {
        case 1:
            value = 1.0f - clampUnit(edgeDistance * uniforms.contrast);
            break;
        case 2:
            value = packedCos(nearestDistance, uniforms.ridgeScale);
            break;
        default: {
            float shade = 1.0f - clampUnit(nearestDistance * uniforms.contrast);
            value = (nearestValue * 0.65f) + (shade * 0.35f);
            break;
        }
    }

    return uniforms.isInverted == 1 ? 1.0f - value : value;
}

static inline uint wrappedCoordinate(uint value, uint limit) {
    return value < limit ? value : value - limit;
}

kernel void asteriasVoronoiKernel(
    device float* output [[buffer(0)]],
    constant VoronoiUniforms& uniforms [[buffer(1)]],
    constant VoronoiCell* cells [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    uint mappedX = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.x + uniforms.rollX, uniforms.width) : gid.x;
    uint mappedY = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.y + uniforms.rollY, uniforms.height) : gid.y;
    float2 point = float2(float(mappedX) / float(uniforms.width), float(mappedY) / float(uniforms.height));

    output[gid.y * uniforms.width + gid.x] = clampUnit(voronoi(point, uniforms, cells));
}
