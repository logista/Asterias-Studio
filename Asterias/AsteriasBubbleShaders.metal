#include <metal_stdlib>
using namespace metal;

struct BubbleUniforms {
    uint width;
    uint height;
    uint rollX;
    uint rollY;
    uint isTilingEnabled;
    uint bubbleCount;
};

struct BubbleValue {
    float scale;
    float squish;
    float originX;
    float originY;
    float cosine;
    float sine;
};

static inline float oneBubbleValue(float2 point, constant BubbleValue& bubble) {
    float relativeX = point.x - bubble.originX;
    float relativeY = point.y - bubble.originY;
    float baseX = fabs(relativeX);
    float baseY = relativeX < 0.0f ? -relativeY : relativeY;
    float transverse = ((baseX * bubble.cosine) - (baseY * bubble.sine)) + bubble.originX;
    float distance = ((baseX * bubble.sine) + (baseY * bubble.cosine)) + bubble.originY;
    float adjustedTransverse = bubble.originX + ((transverse - bubble.originX) * bubble.squish);
    float adjustedDistance = bubble.originY + ((distance - bubble.originY) / bubble.squish);
    float deltaX = adjustedTransverse - bubble.originX;
    float deltaY = adjustedDistance - bubble.originY;
    return 1.0f - ((deltaX * deltaX) + (deltaY * deltaY)) / bubble.scale;
}

static inline float allBubblesValue(float2 point, constant BubbleValue* bubbles, uint bubbleCount) {
    float output = 0.0f;
    for (uint index = 0; index < bubbleCount; ++index) {
        output = max(output, oneBubbleValue(point, bubbles[index]));
    }
    return output;
}

static inline float bubbleValue(float2 point, constant BubbleValue* bubbles, uint bubbleCount) {
    float output = allBubblesValue(point, bubbles, bubbleCount);
    output = max(output, allBubblesValue(float2(point.x + 1.0f, point.y), bubbles, bubbleCount) * (1.0f - point.x));
    output = max(output, allBubblesValue(float2(point.x - 1.0f, point.y), bubbles, bubbleCount) * point.x);
    output = max(output, allBubblesValue(float2(point.x, point.y + 1.0f), bubbles, bubbleCount) * (1.0f - point.y));
    output = max(output, allBubblesValue(float2(point.x, point.y - 1.0f), bubbles, bubbleCount) * point.y);
    output = max(output, allBubblesValue(float2(point.x + 1.0f, point.y + 1.0f), bubbles, bubbleCount) * (1.0f - point.x) * (1.0f - point.y));
    output = max(output, allBubblesValue(float2(point.x + 1.0f, point.y - 1.0f), bubbles, bubbleCount) * (1.0f - point.x) * point.y);
    output = max(output, allBubblesValue(float2(point.x - 1.0f, point.y + 1.0f), bubbles, bubbleCount) * point.x * (1.0f - point.y));
    output = max(output, allBubblesValue(float2(point.x - 1.0f, point.y - 1.0f), bubbles, bubbleCount) * point.x * point.y);
    return output;
}

static inline uint wrappedCoordinate(uint value, uint limit) {
    return value < limit ? value : value - limit;
}

kernel void asteriasBubbleKernel(
    device float* output [[buffer(0)]],
    constant BubbleUniforms& uniforms [[buffer(1)]],
    constant BubbleValue* bubbles [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    uint mappedX = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.x + uniforms.rollX, uniforms.width) : gid.x;
    uint mappedY = uniforms.isTilingEnabled == 1 ? wrappedCoordinate(gid.y + uniforms.rollY, uniforms.height) : gid.y;
    float2 point = float2(float(mappedX) / float(uniforms.width), float(mappedY) / float(uniforms.height));

    output[gid.y * uniforms.width + gid.x] = clamp(bubbleValue(point, bubbles, uniforms.bubbleCount), 0.0f, 1.0f);
}
