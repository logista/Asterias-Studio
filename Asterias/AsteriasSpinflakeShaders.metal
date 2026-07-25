#include <metal_stdlib>
using namespace metal;

struct SpinflakeUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    uint floretCount;
    uint averageFlorets;
    float originX;
    float originY;
    float radius;
    float squish;
    float twistCosine;
    float twistSine;
    float fudge;
};

struct SpinflakeFloret {
    uint sineMethod;
    uint backward;
    float spines;
    float spineRadius;
    float twirlBase;
    float twirlSpeed;
    float twirlAmplitude;
    uint twirlMethod;
};

static inline float spinflakeChopSin(float theta, constant SpinflakeFloret& floret) {
    float output = sin(theta);
    switch (floret.sineMethod) {
        case 0:
            output = (output + 1.0f) / 2.0f;
            break;
        case 2:
            output = fabs(output);
            break;
        case 1:
            output = output < 0.0f ? output + 1.0f : output;
            break;
        default: {
            float adjustedTheta = fmod(theta / 4.0f, float(M_PI_F) / 2.0f);
            if (adjustedTheta < 0.0f) {
                adjustedTheta += float(M_PI_F) / 2.0f;
            }
            output = sin(adjustedTheta);
            break;
        }
    }
    return floret.backward == 1 ? 1.0f - output : output;
}

static inline float spinflakeCalcWave(float theta, float distance, constant SpinflakeFloret& floret) {
    float cosParameter;
    switch (floret.twirlMethod) {
        case 1:
            cosParameter = theta * floret.spines + floret.twirlBase + (distance * (floret.twirlSpeed + (distance * floret.twirlAmplitude)));
            break;
        case 2:
            cosParameter = (theta * floret.spines + floret.twirlBase) + (sin(distance * floret.twirlSpeed) * (floret.twirlAmplitude + (distance * floret.twirlAmplitude)));
            break;
        default:
            cosParameter = theta * floret.spines + floret.twirlBase;
            break;
    }
    return spinflakeChopSin(cosParameter, floret) * floret.spineRadius;
}

static inline float spinflakeRawPoint(float x, float y, constant SpinflakeUniforms& uniforms, constant SpinflakeFloret* florets) {
    float relativeX = x - uniforms.originX;
    float relativeY = y - uniforms.originY;
    float baseX = fabs(relativeX);
    float baseY = relativeX < 0.0f ? -relativeY : relativeY;
    float rotatedX = (baseX * uniforms.twistCosine) - (baseY * uniforms.twistSine);
    float rotatedY = (baseX * uniforms.twistSine) + (baseY * uniforms.twistCosine);
    float squishedX = rotatedX * uniforms.squish;
    float squishedY = rotatedY / uniforms.squish;
    float squishedDistance = sqrt((squishedX * squishedX) + (squishedY * squishedY));

    if (squishedDistance == 0.0f) {
        return 1.0f;
    }

    float pointAngle = atan(rotatedY / rotatedX);
    float edgeDistance = uniforms.radius;
    for (uint index = 0; index < uniforms.floretCount; ++index) {
        edgeDistance += spinflakeCalcWave(pointAngle, squishedDistance, florets[index]);
    }
    if (uniforms.averageFlorets == 1) {
        edgeDistance /= float(uniforms.floretCount);
    }

    float proportionDistance = (edgeDistance - squishedDistance) / edgeDistance;
    if (proportionDistance >= 0.0f) {
        return sqrt(proportionDistance);
    }
    return 1.0f - (1.0f / (1.0f - proportionDistance));
}

static inline float spinflakeVerticalTiledPoint(float x, float y, constant SpinflakeUniforms& uniforms, constant SpinflakeFloret* florets) {
    float point = spinflakeRawPoint(x, y, uniforms, florets);
    if (y > 0.5f) {
        float farPoint = spinflakeRawPoint(x, y - 1.0f, uniforms, florets);
        float farWeight = (y - 0.5f) * 2.0f;
        return (point * (1.0f - farWeight)) + (farPoint * farWeight);
    }
    return point;
}

static inline float spinflake(float2 point, constant SpinflakeUniforms& uniforms, constant SpinflakeFloret* florets) {
    float value = spinflakeVerticalTiledPoint(point.x, point.y, uniforms, florets);
    if (point.x > 0.5f) {
        float farPoint = spinflakeVerticalTiledPoint(point.x - 1.0f, point.y, uniforms, florets);
        float farWeight = (point.x - 0.5f) * 2.0f;
        return (value * (1.0f - farWeight)) + (farPoint * farWeight);
    }
    return value;
}

static inline uint wrappedCoordinate(uint value, uint limit) {
    return value < limit ? value : value - limit;
}

kernel void asteriasSpinflakeKernel(
    device float* output [[buffer(0)]],
    constant SpinflakeUniforms& uniforms [[buffer(1)]],
    constant SpinflakeFloret* florets [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    uint mappedX = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.x + uniforms.rollX, uniforms.width) : gid.x;
    uint mappedY = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.y + uniforms.rollY, uniforms.height) : gid.y;
    float2 point = float2(float(mappedX) / float(uniforms.width), float(mappedY) / float(uniforms.height));

    float value = spinflake(point, uniforms, florets);
    value += spinflake(float2(point.x + uniforms.fudge, point.y), uniforms, florets);
    value += spinflake(float2(point.x, point.y + uniforms.fudge), uniforms, florets);
    value += spinflake(float2(point.x + uniforms.fudge, point.y + uniforms.fudge), uniforms, florets);

    output[gid.y * uniforms.width + gid.x] = clamp(value / 4.0f, 0.0f, 1.0f);
}
