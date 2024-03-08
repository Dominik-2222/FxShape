//
//  FxSampleImage.metal
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



