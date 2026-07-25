#include <metal_stdlib>
using namespace metal;

struct FlameUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    uint transformCount;
    float contrast;
    float glow;
    uint isInverted;
    float fudge;
};

struct FlameTransform {
    float originX;
    float originY;
    float cosine;
    float sine;
    float scale;
    float twist;
    float ridgeScale;
    float sharpness;
    float weight;
    float phase;
    uint symmetry;
    uint variation;
};

static inline float clampUnit(float value) {
    return clamp(value, 0.0f, 1.0f);
}

static inline float packedCos(float distance, float scale) {
    return (cos(distance * scale) + 1.0f) / 2.0f;
}

static inline float wrappedSignedDelta(float value) {
    if (value > 0.5f) {
        return value - 1.0f;
    }
    if (value < -0.5f) {
        return value + 1.0f;
    }
    return value;
}

static inline float2 variedPoint(float x, float y, constant FlameTransform& transform) {
    switch (transform.variation) {
        case 1:
            return float2(
                sin((x * transform.scale) + transform.phase),
                sin((y * transform.scale) - transform.phase)
            );
        case 2: {
            float radiusSquared = (x * x) + (y * y);
            float amount = (radiusSquared * transform.twist) + transform.phase;
            return float2(
                (x * sin(amount)) - (y * cos(amount)),
                (x * cos(amount)) + (y * sin(amount))
            );
        }
        case 3: {
            float radius = max(0.0001f, sqrt((x * x) + (y * y)));
            return float2(((x - y) * (x + y)) / radius, (2.0f * x * y) / radius);
        }
        case 4: {
            float radius = sqrt((x * x) + (y * y));
            float theta = atan2(y, x);
            float fanWidth = float(M_PI_F) / float(transform.symmetry);
            float adjustedTheta = theta + (sin((radius * transform.twist) + transform.phase) * fanWidth);
            return float2(cos(adjustedTheta) * radius, sin(adjustedTheta) * radius);
        }
        default:
            return float2(x, y);
    }
}

static inline float transformValue(float2 point, constant FlameTransform& transform) {
    float deltaX = wrappedSignedDelta(point.x - transform.originX) * 2.0f;
    float deltaY = wrappedSignedDelta(point.y - transform.originY) * 2.0f;
    float rotatedX = (deltaX * transform.cosine) - (deltaY * transform.sine);
    float rotatedY = (deltaX * transform.sine) + (deltaY * transform.cosine);
    float2 varied = variedPoint(rotatedX, rotatedY, transform);
    float radius = max(0.0001f, sqrt((varied.x * varied.x) + (varied.y * varied.y)));
    float theta = atan2(varied.y, varied.x);
    float angular = pow(fabs(cos((theta * float(transform.symmetry)) + transform.phase + (radius * transform.twist))), transform.sharpness);
    float radial = packedCos(radius, transform.ridgeScale);
    float falloff = 1.0f / (1.0f + pow(radius * transform.scale, transform.sharpness + 1.0f));
    return ((angular * 0.72f) + (radial * 0.28f)) * falloff;
}

static inline float flame(float2 point, constant FlameUniforms& uniforms, constant FlameTransform* transforms) {
    float inverseOutput = 1.0f;

    for (uint index = 0; index < uniforms.transformCount; ++index) {
        float value = transformValue(point, transforms[index]);
        inverseOutput *= 1.0f - clampUnit(value * transforms[index].weight);
    }

    float value = pow(clampUnit(1.0f - inverseOutput), uniforms.glow) * uniforms.contrast;
    float clampedValue = clampUnit(value);
    return uniforms.isInverted == 1 ? 1.0f - clampedValue : clampedValue;
}

static inline uint wrappedCoordinate(uint value, uint limit) {
    return value < limit ? value : value - limit;
}

kernel void asteriasFlameKernel(
    device float* output [[buffer(0)]],
    constant FlameUniforms& uniforms [[buffer(1)]],
    constant FlameTransform* transforms [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    uint mappedX = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.x + uniforms.rollX, uniforms.width) : gid.x;
    uint mappedY = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.y + uniforms.rollY, uniforms.height) : gid.y;
    float2 point = float2(float(mappedX) / float(uniforms.width), float(mappedY) / float(uniforms.height));

    float value = flame(point, uniforms, transforms);
    value += flame(float2(point.x + uniforms.fudge, point.y), uniforms, transforms);
    value += flame(float2(point.x, point.y + uniforms.fudge), uniforms, transforms);
    value += flame(float2(point.x + uniforms.fudge, point.y + uniforms.fudge), uniforms, transforms);

    output[gid.y * uniforms.width + gid.x] = clampUnit(value / 4.0f);
}
