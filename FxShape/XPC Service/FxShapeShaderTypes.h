//
//  FxShapeShaderTypes.h
//  PlugIn
//
//  Created by Apple on 10/4/18.
//  Copyright © 2019-2023 Apple Inc. All rights reserved.
//

#ifndef FxShapeShaderTypes_h
#define FxShapeShaderTypes_h

#import <simd/simd.h>

// Types for drawing the input image to the output

// These are the vertex shader attributes
typedef enum FxSampleImageVertexIndex {
    FSVI_Vertices = 0,
    FSVI_ViewportSize = 1
} FxSampleImageVertexIndex;

// Fragment shader uniforms
typedef enum FxSampleTextureIndex {
    FSTI_InputImage = 0,
    FSTI_InputImage2 = 1,
    select_opt=3
} FxSampleTextureIndex;

// Structures passed into the vertex shader. This is the memory
// layout of our vertices when drawing the input image to the
// output or when drawing the OSCs
typedef struct Vertex2D {
    vector_float2   position;
    vector_float2   textureCoordinate;
} Vertex2D;


// Fragment shader uniforms for drawing the OSCs
typedef enum FxShapeOSCBufferIndex {
    FSFI_DrawColor = 0
} FxShapeOSCBufferIndex;


// Types for drawing the shapes to the output

// Vertex attributes for drawing the shapes to the output
typedef enum FxShapeShaderVertex {
    FSSI_Vertices = 0,
    FSSI_ModelView = 1,
    FSSI_Projection = 2,

} FxShapeShaderVertex;

// Vertices for just drawing the shapes to the output
typedef struct ShapeVertex {
    vector_float2   position;
    vector_float2   textureCoordinate;
    
} ShapeVertex;

#endif /* FxShapeShaderTypes_h */
