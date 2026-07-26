#include <metal_stdlib>
using namespace metal;

struct BranchfracUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    uint rayCount;
};

struct BranchfracRay {
    float originX;
    float originY;
    float length;
    float directionX;
    float directionY;
};

static inline uint wrappedCoordinate(uint value, uint limit) {
    return value < limit ? value : value - limit;
}

static inline float rayDistanceSquared(float2 point, constant BranchfracRay& ray) {
    float2 relative = point - float2(ray.originX, ray.originY);
    float2 direction = float2(ray.directionX, ray.directionY);
    float projectedLength = dot(relative, direction);

    if (projectedLength <= 0.0f) {
        return dot(relative, relative);
    }
    if (projectedLength >= ray.length) {
        float2 endpoint = float2(ray.originX, ray.originY) + direction * ray.length;
        float2 endRelative = point - endpoint;
        return dot(endRelative, endRelative);
    }

    float2 perpendicular = relative - direction * projectedLength;
    return dot(perpendicular, perpendicular);
}

static inline float branchfrac(float2 point, constant BranchfracUniforms& uniforms, constant BranchfracRay* rays) {
    float nearestSquared = INFINITY;

    for (uint index = 0; index < uniforms.rayCount; ++index) {
        float distanceSquared = rayDistanceSquared(point, rays[index]);
        if (distanceSquared < nearestSquared) {
            nearestSquared = distanceSquared;
            if (nearestSquared <= 0.00000001f) {
                return 1.0f;
            }
        }
    }

    float distance = sqrt(nearestSquared);
    return 1.0f / ((distance * 10.0f) + 1.0f);
}

kernel void asteriasBranchfracKernel(
    device float* output [[buffer(0)]],
    constant BranchfracUniforms& uniforms [[buffer(1)]],
    constant BranchfracRay* rays [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    uint mappedX = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.x + uniforms.rollX, uniforms.width) : gid.x;
    uint mappedY = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.y + uniforms.rollY, uniforms.height) : gid.y;
    float2 point = float2(float(mappedX) / float(uniforms.width), float(mappedY) / float(uniforms.height));

    output[gid.y * uniforms.width + gid.x] = clamp(branchfrac(point, uniforms, rays), 0.0f, 1.0f);
}
