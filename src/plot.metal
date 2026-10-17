#include <metal_stdlib>
using namespace metal;

struct Viewport {
    float2 minimum;
    float2 span;
    float2 pixels;
    float width;
    uint points;
    uint dark;
    float4 color;
};
struct Vertex {
    float4 position [[position]];
    float size [[point_size]];
};
float2 clip(float2 p, constant Viewport &v) {
    return (p - v.minimum) / v.span * 2.0f - 1.0f;
}
vertex Vertex plot_point(uint id [[vertex_id]], device const float2 *xy [[buffer(0)]],
                         constant Viewport &v [[buffer(1)]]) {
    float2 p = xy[id];
    if (!all(isfinite(p))) return {float4(2, 2, 0, 1), 1};
    return {float4(clip(p, v), 0, 1), v.width};
}
// Six procedural vertices per segment give lines an explicit width on every GPU.
// Invalid endpoints discard the entire segment, preserving gaps in scientific data.
vertex Vertex plot_line(uint id [[vertex_id]], device const float2 *xy [[buffer(0)]],
                        constant Viewport &v [[buffer(1)]]) {
    uint segment = id / 6, corner = id % 6;
    float2 a = xy[segment], b = xy[segment + 1];
    if (!all(isfinite(a)) || !all(isfinite(b))) return {float4(2, 2, 0, 1), 1};
    a = clip(a, v); b = clip(b, v);
    float2 direction = (b - a) * v.pixels;
    float length = max(metal::length(direction), 1e-12f);
    float2 normal = float2(-direction.y, direction.x) / length * v.width / v.pixels;
    const bool endpoint[6] = {false, true, false, false, true, true};
    const float side[6] = {-1, -1, 1, 1, -1, 1};
    return {float4((endpoint[corner] ? b : a) + normal * side[corner], 0, 1), 1};
}
fragment float4 plot_color(constant Viewport &v [[buffer(1)]]) { return v.color; }
fragment float4 plot_dot(float2 p [[point_coord]], constant Viewport &v [[buffer(1)]]) {
    if (distance(p, float2(0.5)) > 0.5) discard_fragment();
    return v.color;
}
