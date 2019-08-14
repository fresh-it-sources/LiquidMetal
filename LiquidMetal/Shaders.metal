//
//  Shaders.metal
//  LiquidMetal
//
//  Created by majess on 14/08/2019.
//  Copyright © 2019 Fresh IT. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
};

struct Uniforms {
    float4x4 ndcMatrix;
    float ptmRatio;
    float pointSize;
};

vertex VertexOut particle_vertex(const device packed_float2* vertex_array[[buffer(0)]],
                                 const device Uniforms& uniforms [[buffer(1)]],
                                 unsigned int vid [[vertex_id]]) {
    VertexOut vertexOut;
    float2 position = vertex_array[vid];
    vertexOut.position = uniforms.ndcMatrix * float4(position.x * uniforms.ptmRatio, position.y * uniforms.ptmRatio, 0, 1);
    vertexOut.pointSize = uniforms.pointSize;
    return vertexOut;
}

fragment half4 basic_fragment() {
    return half4(1.0);
}
