//
//  FxShape.metal
//  PlugIn
//
//  Created by Apple on 10/4/18.
//  Copyright © 2019-2023 Apple Inc. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

#include "FxShapeShaderTypes.h"

typedef struct
{
    // The [[position]] attribute of this member indicates that this value is the clip space
    // position of the vertex when this structure is returned from the vertex function
    float4 clipSpacePosition [[position]];
    
    // Since this member does not have a special attribute, the rasterizer interpolates
    // its value with the values of the other triangle vertices and then passes
    // the interpolated value to the fragment shader for each fragment in the triangle
    float2 textureCoordinate;
    
} RasterizerData;

vertex RasterizerData
OSCVertexShader(uint vertexID [[vertex_id]],
             constant Vertex2D *vertexArray [[buffer(FSVI_Vertices)]],
             constant vector_uint2 *viewportSizePointer [[buffer(FSVI_ViewportSize)]])
{
    RasterizerData out;
    
    // Index into our array of positions to get the current vertex
    //   Our positions are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from
    //   the origin)
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    
    // Get the size of the drawable so that we can convert to normalized device coordinates,
    float2 viewportSize = float2(*viewportSizePointer);
    
    // The output position of every vertex shader is in clip space (also known as normalized device
    //   coordinate space, or NDC). A value of (-1.0, -1.0) in clip-space represents the
    //   lower-left corner of the viewport whereas (1.0, 1.0) represents the upper-right corner of
    //   the viewport.
    
    // In order to convert from positions in pixel space to positions in clip space we divide the
    //   pixel coordinates by half the size of the viewport.
    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);
    
    // Set the z component of our clip space position 0 (since we're only rendering in
    //   2-Dimensions for this sample)
    out.clipSpacePosition.z = 0.0;
    
    // Set the w component to 1.0 since we don't need a perspective divide, which is also not
    //   necessary when rendering in 2-Dimensions
    out.clipSpacePosition.w = 1.0;
    
    // Pass our input textureCoordinate straight to our output RasterizerData. This value will be
    //   interpolated with the other textureCoordinate values in the vertices that make up the
    //   triangle.
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    
    return out;
}

// Fragment function
fragment float4 OSCFragmentShader(RasterizerData in [[stage_in]],
                                  constant float4 *color [[buffer(FSFI_DrawColor)]])
{

    
    
    return *color;
}
