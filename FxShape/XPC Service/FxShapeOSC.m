//
//  FxShapeOSC.m
//  PlugIn
//
//  Created by Apple on 10/3/18.
//  Copyright © 2019-2023 Apple Inc. All rights reserved.
//

#import "FxShapeOSC.h"
#import "FxShapePlugIn.h"
#import "FxMTLDeviceCache.h"
#import "FxShapeShaderTypes.h"

enum {
    kFSPart_Rectangle   = 1,
    kFSPart_Circle = 2,
};

const simd_float4   kUnselectedColor    = { 0.25, 0.25, 0.25, 0.25 };
const simd_float4   kSelectedColor      = { 0.5, 0.5, 0.5, 0.5 };
const simd_float4   kOutlineColor       = { 1.0, 1.0, 1.0, 1.0 };
const simd_float4   kShadowColor        = { 0.25, 0.25, 0.25, 1.0 };

@implementation FxShapeOSC
{
    NSLock* lastPositionLock;
}

- (instancetype)initWithAPIManager:(id<PROAPIAccessing>)newAPIManager
{
    self = [super init];
    
    if (self != nil)
    {
        apiManager = newAPIManager;
        lastPositionLock = [[NSLock alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [lastPositionLock release];
    [super dealloc];
}


#pragma mark -
#pragma mark Drawing

- (FxDrawingCoordinates)drawingCoordinates
{
    return kFxDrawingCoordinates_CANVAS;
}

- (void)drawRectangleWithImageSize:(NSSize)imageSize
                   commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder
                       activePart:(NSInteger)activePart
                           atTime:(CMTime)time;
{
    double  destImageWidth  = imageSize.width;
    double  destImageHeight = imageSize.height;
    // Get the rectangle's lower left and upper right coordinates
    CGPoint ll  = { 0.0, 0.0 };
    CGPoint ur  = { 0.0, 0.0 };
    id<FxParameterRetrievalAPI_v6>  paramAPI    = [apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    [paramAPI getXValue:&ll.x
                 YValue:&ll.y
          fromParameter:kLowerLeftID
                 atTime:time];
    [paramAPI getXValue:&ur.x
                 YValue:&ur.y
          fromParameter:kUpperRightID
                 atTime:time];

    // Convert from object to canvas space
    id<FxOnScreenControlAPI_v4> oscAPI  = [apiManager apiForProtocol:@protocol(FxOnScreenControlAPI_v4)];
    CGPoint canvasLL    = { 0.0, 0.0 };
    CGPoint canvasUR    = { 0.0, 0.0 };
    CGPoint canvasLR    = { 0.0, 0.0 };
    CGPoint canvasUL    = { 0.0, 0.0 };
    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_OBJECT
                            fromX:ll.x
                            fromY:ll.y
                          toSpace:kFxDrawingCoordinates_CANVAS
                              toX:&canvasLL.x
                              toY:&canvasLL.y];

    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_OBJECT
                            fromX:ur.x
                            fromY:ur.y
                          toSpace:kFxDrawingCoordinates_CANVAS
                              toX:&canvasUR.x
                              toY:&canvasUR.y];
    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_OBJECT
                            fromX:ll.x
                            fromY:ur.y
                          toSpace:kFxDrawingCoordinates_CANVAS
                              toX:&canvasUL.x
                              toY:&canvasUL.y];
    
    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_OBJECT
                            fromX:ur.x
                            fromY:ll.y
                          toSpace:kFxDrawingCoordinates_CANVAS
                              toX:&canvasLR.x
                              toY:&canvasLR.y];

    // Flip the Y since Metal is Y-down
    canvasLL.y = destImageHeight - canvasLL.y;
    canvasUR.y = destImageHeight - canvasUR.y;
    canvasUL.y = destImageHeight - canvasUL.y;
    canvasLR.y = destImageHeight - canvasLR.y;

    // The vertex shader has everything centered at the origin, so subtract off half the width
    // and height
    canvasLL.x -= destImageWidth / 2.0;
    canvasLL.y -= destImageHeight / 2.0;
    canvasUR.x -= destImageWidth / 2.0;
    canvasUR.y -= destImageHeight / 2.0;
    canvasUL.x -= destImageWidth / 2.0;
    canvasUL.y -= destImageHeight / 2.0;
    canvasLR.x -= destImageWidth / 2.0;
    canvasLR.y -= destImageHeight / 2.0;

    // Make vertices to send to the vertex shader
    Vertex2D    vertices[4] = {
        { { canvasLR.x, canvasLR.y }, { 1.0, 0.0 } },
        { { canvasLL.x, canvasLL.y }, { 0.0, 0.0 } },
        { { canvasUR.x, canvasUR.y }, { 1.0, 1.0 } },
        { { canvasUL.x, canvasUL.y }, { 0.0, 1.0 } }
    };

    simd_uint2  viewportSize = {
        (unsigned int)(destImageWidth),
        (unsigned int)(destImageHeight)
    };

    // Draw the inner rectangle
    [commandEncoder setVertexBytes:vertices
                            length:sizeof(vertices)
                           atIndex:FSVI_Vertices];

    [commandEncoder setVertexBytes:&viewportSize
                            length:sizeof(viewportSize)
                           atIndex:FSVI_ViewportSize];

    if (activePart == kFSPart_Rectangle)
    {
        [commandEncoder setFragmentBytes:&kSelectedColor
                                  length:sizeof(kSelectedColor)
                                 atIndex:FSFI_DrawColor];
    }
    else
    {
        [commandEncoder setFragmentBytes:&kUnselectedColor
                                  length:sizeof(kUnselectedColor)
                                 atIndex:FSFI_DrawColor];
    }

    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                       vertexStart:0
                       vertexCount:4];
    
    // Draw the outline of the rectangle
    
    // Shadow first
    Vertex2D    shadowVertices[] = {
        { { canvasLL.x + 1.0, canvasLL.y + 1.0 }, { 0.0, 0.0 } },
        { { canvasLR.x + 1.0, canvasLR.y + 1.0 }, { 1.0, 0.0 } },
        { { canvasUR.x + 1.0, canvasUR.y + 1.0 }, { 1.0, 1.0 } },
        { { canvasUL.x + 1.0, canvasUL.y + 1.0 }, { 0.0, 1.0 } },
        { { canvasLL.x + 1.0, canvasLL.y + 1.0 }, { 0.0, 0.0 } },
    };
    
    [commandEncoder setVertexBytes:shadowVertices
                            length:sizeof(shadowVertices)
                           atIndex:FSVI_Vertices];
    
    [commandEncoder setVertexBytes:&viewportSize
                            length:sizeof(viewportSize)
                           atIndex:FSVI_ViewportSize];
    
    [commandEncoder setFragmentBytes:&kShadowColor
                              length:sizeof(kShadowColor)
                             atIndex:FSFI_DrawColor];
    
    [commandEncoder drawPrimitives:MTLPrimitiveTypeLineStrip
                       vertexStart:0
                       vertexCount:5];

    // Regular outline
    Vertex2D    outlineVertices[] = {
        { { canvasLL.x, canvasLL.y }, { 0.0, 0.0 } },
        { { canvasLR.x, canvasLR.y }, { 1.0, 0.0 } },
        { { canvasUR.x, canvasUR.y }, { 1.0, 1.0 } },
        { { canvasUL.x, canvasUL.y }, { 0.0, 1.0 } },
        { { canvasLL.x, canvasLL.y }, { 0.0, 0.0 } },
    };
    
    [commandEncoder setVertexBytes:outlineVertices
                            length:sizeof(outlineVertices)
                           atIndex:FSVI_Vertices];
    
    [commandEncoder setVertexBytes:&viewportSize
                            length:sizeof(viewportSize)
                           atIndex:FSVI_ViewportSize];
    
    [commandEncoder setFragmentBytes:&kOutlineColor
                              length:sizeof(kOutlineColor)
                             atIndex:FSFI_DrawColor];

    [commandEncoder drawPrimitives:MTLPrimitiveTypeLineStrip
                       vertexStart:0
                       vertexCount:5];

}

- (void)canvasPoint:(CGPoint*)canvasPt
    forCircleCenter:(CGPoint)cc
              angle:(double)radians
   normalizedRadius:(CGPoint)normalizedRadius
         canvasSize:(NSSize)canvasSize
             oscAPI:(id<FxOnScreenControlAPI_v4>)oscAPI
{
    CGPoint objectPt;
    objectPt.x = cc.x + cos(radians) * normalizedRadius.x;
    objectPt.y = cc.y + sin(radians) * normalizedRadius.y;
    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_OBJECT
                            fromX:objectPt.x
                            fromY:objectPt.y
                          toSpace:kFxDrawingCoordinates_CANVAS
                              toX:&canvasPt->x
                              toY:&canvasPt->y];
    canvasPt->y = canvasSize.height - canvasPt->y;
    canvasPt->x -= canvasSize.width / 2.0;
    canvasPt->y -= canvasSize.height / 2.0;
}

- (void)drawCircleWithImageSize:(NSSize)canvasSize
                 commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder
                     activePart:(NSInteger)activePart
                         atTime:(CMTime)time
{
    double  destImageWidth  = canvasSize.width;
    double  destImageHeight = canvasSize.height;
    
    // Draw the circle
    id<FxParameterRetrievalAPI_v6>  paramAPI    = [apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    CGPoint cc  = { 0.0, 0.0 };
    [paramAPI getXValue:&cc.x
                 YValue:&cc.y
          fromParameter:kCircleCenter
                 atTime:time];
    
    double  radius  = 0.0;
    [paramAPI getFloatValue:&radius
              fromParameter:kCircleRadius
                     atTime:time];
    id<FxOnScreenControlAPI_v4> oscAPI  = [apiManager apiForProtocol:@protocol(FxOnScreenControlAPI_v4)];
    NSRect  imageBounds = [oscAPI inputBounds];
    CGPoint normalizedRadius;
    normalizedRadius.x = radius / imageBounds.size.width;
    normalizedRadius.y = radius / imageBounds.size.height;
    
    CGPoint canvasCC    = { 0.0, 0.0 };
    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_OBJECT
                            fromX:cc.x
                            fromY:cc.y
                          toSpace:kFxDrawingCoordinates_CANVAS
                              toX:&canvasCC.x
                              toY:&canvasCC.y];
    canvasCC.y = destImageHeight - canvasCC.y;
    canvasCC.x -= destImageWidth / 2.0;
    canvasCC.y -= destImageHeight / 2.0;
    
    
    const size_t    kNumAngles              = 24;
    const int       kDegreesPerIteration    = 360 / kNumAngles;
    const size_t    kNumCircleVertices      = 3 * kNumAngles;
    Vertex2D    circleVertices [ kNumCircleVertices ];
    simd_float2 zeroZero    = { 0.0, 0.0 };
    CGPoint     canvasPt;
    for (int i = 0; i < kNumAngles; ++i)
    {
        // Center point
        circleVertices [ i * 3 + 0 ].position.x = canvasCC.x;
        circleVertices [ i * 3 + 0 ].position.y = canvasCC.y;
        circleVertices [ i * 3 + 0 ].textureCoordinate = zeroZero;
        
        // Point at i degrees on the outer edge of the cirle
        double  radians = (double)(i * kDegreesPerIteration) * M_PI / 180.0;
        [self canvasPoint:&canvasPt
          forCircleCenter:cc
                    angle:radians
         normalizedRadius:normalizedRadius
               canvasSize:canvasSize
                   oscAPI:oscAPI];
        circleVertices [ i * 3 + 1 ].position.x = canvasPt.x;
        circleVertices [ i * 3 + 1 ].position.y = canvasPt.y;
        circleVertices [ i * 3 + 1 ].textureCoordinate = zeroZero;
        
        // Point at (i + 1) degrees on the outer edge of the circle
        radians = (double)((i + 1) * kDegreesPerIteration) * M_PI / 180.0;
        [self canvasPoint:&canvasPt
          forCircleCenter:cc
                    angle:radians
         normalizedRadius:normalizedRadius
               canvasSize:canvasSize
                   oscAPI:oscAPI];
        circleVertices [ i * 3 + 2 ].position.x = canvasPt.x;
        circleVertices [ i * 3 + 2 ].position.y = canvasPt.y;
        circleVertices [ i * 3 + 2 ].textureCoordinate = zeroZero;
    }
    
    Vertex2D    shadowVertices [ kNumAngles + 1 ];
    Vertex2D    outlineVertices [ kNumAngles + 1 ];
    for (int i = 0; i < kNumAngles; ++i)
    {
        outlineVertices [ i ] = circleVertices [ i * 3 + 1 ];
        shadowVertices [ i ].position.x = outlineVertices [ i ].position.x + 1.0;
        shadowVertices [ i ].position.y = outlineVertices [ i ].position.y + 1.0;
    }
    outlineVertices [ kNumAngles ] = outlineVertices [ 0 ];
    shadowVertices [ kNumAngles ] = shadowVertices [ 0 ];
    
    // Draw the circle
    [commandEncoder setVertexBytes:circleVertices
                            length:sizeof(circleVertices)
                           atIndex:FSVI_Vertices];
    
    simd_uint2  viewportSize = {
        (unsigned int)(destImageWidth),
        (unsigned int)(destImageHeight)
    };
    [commandEncoder setVertexBytes:&viewportSize
                            length:sizeof(viewportSize)
                           atIndex:FSVI_ViewportSize];
    
    if (activePart == kFSPart_Circle)
    {
        [commandEncoder setFragmentBytes:&kSelectedColor
                                  length:sizeof(kSelectedColor)
                                 atIndex:FSFI_DrawColor];
    }
    else
    {
        [commandEncoder setFragmentBytes:&kUnselectedColor
                                  length:sizeof(kUnselectedColor)
                                 atIndex:FSFI_DrawColor];
    }
    
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                       vertexStart:0
                       vertexCount:kNumCircleVertices];
    
    // Draw the shadow
    [commandEncoder setVertexBytes:shadowVertices
                            length:sizeof(shadowVertices)
                           atIndex:FSVI_Vertices];
    
    [commandEncoder setVertexBytes:&viewportSize
                            length:sizeof(viewportSize)
                           atIndex:FSVI_ViewportSize];
    
    [commandEncoder setFragmentBytes:&kShadowColor
                              length:sizeof(kShadowColor)
                             atIndex:FSFI_DrawColor];
    
    [commandEncoder drawPrimitives:MTLPrimitiveTypeLineStrip
                       vertexStart:0
                       vertexCount:kNumAngles + 1];
    
    // Draw the outline
    [commandEncoder setVertexBytes:outlineVertices
                            length:sizeof(outlineVertices)
                           atIndex:FSVI_Vertices];
    
    [commandEncoder setVertexBytes:&viewportSize
                            length:sizeof(viewportSize)
                           atIndex:FSVI_ViewportSize];
    
    [commandEncoder setFragmentBytes:&kOutlineColor
                              length:sizeof(kOutlineColor)
                             atIndex:FSFI_DrawColor];
    
    [commandEncoder drawPrimitives:MTLPrimitiveTypeLineStrip
                       vertexStart:0
                       vertexCount:kNumAngles + 1];
}

- (void)drawOSC:(FxImageTile*)destinationImage
 commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder
     activePart:(NSInteger)activePart
         atTime:(CMTime)time
{
    // Width and height of the canvas we're drawing to
    float   destImageWidth  = destinationImage.imagePixelBounds.right - destinationImage.imagePixelBounds.left;
    float   destImageHeight = destinationImage.imagePixelBounds.top - destinationImage.imagePixelBounds.bottom;
    
    // Because of Metal's Y-down orientation, we need to start at the top of the
    // viewport instead of the bottom.
    float   ioSurfaceHeight = [destinationImage.ioSurface height];
    MTLViewport viewport    = {
        0, ioSurfaceHeight - destImageHeight, destImageWidth, destImageHeight, -1.0, 1.0
    };
    [commandEncoder setViewport:viewport];
    
    [self drawRectangleWithImageSize:NSMakeSize(destImageWidth, destImageHeight)
                      commandEncoder:commandEncoder
                          activePart:activePart
                              atTime:time];
    
    [self drawCircleWithImageSize:NSMakeSize(destImageWidth, destImageHeight)
                   commandEncoder:commandEncoder
                       activePart:activePart
                           atTime:time];

}

- (void)drawOSCWithWidth:(NSInteger)width
                  height:(NSInteger)height
              activePart:(NSInteger)activePart
        destinationImage:(FxImageTile*)destinationImage
                  atTime:(CMTime)time
{
    // Set up our Metal command queue
    // Make a command buffer
    FxMTLDeviceCache*   deviceCache = [FxMTLDeviceCache deviceCache];
    id<MTLDevice>   gpuDevice = [deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID];
    id<MTLCommandQueue> commandQueue    = [deviceCache commandQueueWithRegistryID:destinationImage.deviceRegistryID
                                                                      pixelFormat:MTLPixelFormatRGBA16Float];
    id<MTLCommandBuffer>    commandBuffer   = [commandQueue commandBuffer];
    commandBuffer.label = @"FxShapeOSC Command Buffer";
    [commandBuffer enqueue];
    
    // Setup the color attachment to draw to our output texture
    id<MTLTexture>  outputTexture   = [destinationImage metalTextureForDevice:gpuDevice];
    MTLRenderPassColorAttachmentDescriptor* colorAttachmentDescriptor   = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
    colorAttachmentDescriptor.texture = outputTexture;
    colorAttachmentDescriptor.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    colorAttachmentDescriptor.loadAction = MTLLoadActionClear;
    
    // Create a render pass descriptor and attach the color attachment to it
    MTLRenderPassDescriptor*    renderPassDescriptor    = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments [ 0 ] = colorAttachmentDescriptor;
    
    // Create the render command encoder
    id<MTLRenderCommandEncoder>   commandEncoder  = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    // Get the pipeline state that contains our fragment and vertex shaders
    id<MTLRenderPipelineState>  pipelineState   = [deviceCache oscPipelineStateWithRegistryID:destinationImage.deviceRegistryID];
    [commandEncoder setRenderPipelineState:pipelineState];
    
    // Draw something here
    [self drawOSC:destinationImage
   commandEncoder:commandEncoder
       activePart:activePart
           atTime:time];
    
    // Clean up
    [commandEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilScheduled];
    
    [deviceCache returnCommandQueueToCache:commandQueue];
    
    [colorAttachmentDescriptor release];
}

- (void)hitTestOSCAtMousePositionX:(double)mousePositionX
                    mousePositionY:(double)mousePositionY
                        activePart:(NSInteger*)activePart
                            atTime:(CMTime)time;
{
    id<FxOnScreenControlAPI_v4>    oscAPI  = [apiManager apiForProtocol:@protocol(FxOnScreenControlAPI_v4)];
    CGPoint objectPosition  = { 0.0, 0.0 };
    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_CANVAS
                            fromX:mousePositionX
                            fromY:mousePositionY
                          toSpace:kFxDrawingCoordinates_OBJECT
                              toX:&objectPosition.x
                              toY:&objectPosition.y];
    
    id<FxParameterRetrievalAPI_v6>  paramAPI    = [apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    CGPoint ll  = { 0.0, 0.0 };
    CGPoint ur  = { 0.0, 0.0 };
    CGPoint cc  = { 0.0, 0.0 };
    double  circleRadius    = 0.0;
    [paramAPI getXValue:&ll.x
                 YValue:&ll.y
          fromParameter:kLowerLeftID
                 atTime:time];
    
    [paramAPI getXValue:&ur.x
                 YValue:&ur.y
          fromParameter:kUpperRightID
                 atTime:time];
    
    [paramAPI getXValue:&cc.x
                 YValue:&cc.y
          fromParameter:kCircleCenter
                 atTime:time];
    
    [paramAPI getFloatValue:&circleRadius
              fromParameter:kCircleRadius
                     atTime:time];
    
    NSRect  inputBounds = [oscAPI inputBounds];
    
    *activePart = 0;
    if ((ll.x <= objectPosition.x) && (objectPosition.x <= ur.x) &&
        (ll.y <= objectPosition.y) && (objectPosition.y <= ur.y))
    {
        *activePart = kFSPart_Rectangle;
    }
    else
    {
        double  objectRadius = circleRadius / inputBounds.size.width;
        
        CGPoint delta   = {
            objectPosition.x - cc.x,
            (objectPosition.y - cc.y) * inputBounds.size.height / inputBounds.size.width
        };
        double  dist    = sqrt(delta.x * delta.x + delta.y * delta.y);
        if (dist < objectRadius)
        {
            *activePart = kFSPart_Circle;
        }
    }
}

#pragma mark -
#pragma mark Key Events

- (void)keyDownAtPositionX:(double)mousePositionX
                 positionY:(double)mousePositionY
                keyPressed:(unsigned short)asciiKey
                 modifiers:(FxModifierKeys)modifiers
               forceUpdate:(BOOL *)forceUpdate
                 didHandle:(BOOL *)didHandle
                    atTime:(CMTime)time
{
    *didHandle = NO;
}

- (void)keyUpAtPositionX:(double)mousePositionX
               positionY:(double)mousePositionY
              keyPressed:(unsigned short)asciiKey
               modifiers:(FxModifierKeys)modifiers
             forceUpdate:(BOOL *)forceUpdate
               didHandle:(BOOL *)didHandle
                  atTime:(CMTime)time
{
    *didHandle = NO;
}

#pragma mark -
#pragma mark Mouse Events

- (void)mouseDownAtPositionX:(double)mousePositionX
                   positionY:(double)mousePositionY
                  activePart:(NSInteger)activePart
                   modifiers:(FxModifierKeys)modifiers
                 forceUpdate:(BOOL *)forceUpdate
                      atTime:(CMTime)time
{
    id<FxOnScreenControlAPI_v4> oscAPI  = [apiManager apiForProtocol:@protocol(FxOnScreenControlAPI_v4)];
    [lastPositionLock lock];
    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_CANVAS
                            fromX:mousePositionX
                            fromY:mousePositionY
                          toSpace:kFxDrawingCoordinates_OBJECT
                              toX:&lastObjectPosition.x
                              toY:&lastObjectPosition.y];
    [lastPositionLock unlock];
    *forceUpdate = NO;
}

- (void)mouseDraggedAtPositionX:(double)mousePositionX
                      positionY:(double)mousePositionY
                     activePart:(NSInteger)activePart
                      modifiers:(FxModifierKeys)modifiers
                    forceUpdate:(BOOL *)forceUpdate
                         atTime:(CMTime)time
{
    id<FxOnScreenControlAPI_v4> oscAPI  = [apiManager apiForProtocol:@protocol(FxOnScreenControlAPI_v4)];
    CGPoint objectPos = { 0.0, 0.0 };
    [oscAPI convertPointFromSpace:kFxDrawingCoordinates_CANVAS
                            fromX:mousePositionX
                            fromY:mousePositionY
                          toSpace:kFxDrawingCoordinates_OBJECT
                              toX:&objectPos.x
                              toY:&objectPos.y];
    
    [lastPositionLock lock];
    CGPoint delta   = { objectPos.x - lastObjectPosition.x, objectPos.y - lastObjectPosition.y };
    lastObjectPosition = objectPos;
    [lastPositionLock unlock];
    
    id<FxParameterSettingAPI_v5>    paramSetAPI = [apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    id<FxParameterRetrievalAPI_v6>  paramGetAPI = [apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    
    if (activePart == kFSPart_Rectangle)
    {
        CGPoint ll  = { 0.0, 0.0 };
        CGPoint ur  = { 0.0, 0.0 };
        [paramGetAPI getXValue:&ll.x
                        YValue:&ll.y
                 fromParameter:kLowerLeftID
                        atTime:time];
        [paramGetAPI getXValue:&ur.x
                        YValue:&ur.y
                 fromParameter:kUpperRightID
                        atTime:time];
        
        ll.x += delta.x;
        ll.y += delta.y;
        ur.x += delta.x;
        ur.y += delta.y;
        
        [paramSetAPI setXValue:ll.x
                        YValue:ll.y
                   toParameter:kLowerLeftID
                        atTime:time];
        [paramSetAPI setXValue:ur.x
                        YValue:ur.y
                   toParameter:kUpperRightID
                        atTime:time];
    }
    else if (activePart == kFSPart_Circle)
    {
        CGPoint cc  = { 0.0, 0.0 };
        [paramGetAPI getXValue:&cc.x
                        YValue:&cc.y
                 fromParameter:kCircleCenter
                        atTime:time];
        
        cc.x += delta.x;
        cc.y += delta.y;
        
        [paramSetAPI setXValue:cc.x
                        YValue:cc.y
                   toParameter:kCircleCenter
                        atTime:time];
    }
    
    *forceUpdate = YES;
}

- (void)mouseUpAtPositionX:(double)mousePositionX
                 positionY:(double)mousePositionY
                activePart:(NSInteger)activePart
                 modifiers:(FxModifierKeys)modifiers
               forceUpdate:(BOOL *)forceUpdate
                    atTime:(CMTime)time
{
    [self mouseDraggedAtPositionX:mousePositionX
                        positionY:mousePositionY
                       activePart:activePart
                        modifiers:modifiers
                      forceUpdate:forceUpdate
                           atTime:time];
    
    [lastPositionLock lock];
    lastObjectPosition = CGPointMake(-1.0, -1.0);
    [lastPositionLock unlock];
}

#pragma mark -
#pragma mark Mouse Moved Events

- (void)mouseEnteredAtPositionX:(double)mousePositionX
                      positionY:(double)mousePositionY
                      modifiers:(FxModifierKeys)modifiers
                    forceUpdate:(BOOL *)forceUpdate
                         atTime:(CMTime)time
{
    // TODO: Put any mouse-entered handling code here
}

- (void)mouseMovedAtPositionX:(double)mousePositionX
                    positionY:(double)mousePositionY
                   activePart:(NSInteger)activePart
                    modifiers:(FxModifierKeys)modifiers
                  forceUpdate:(BOOL *)forceUpdate
                       atTime:(CMTime)time
{
    // TODO: Put any mouse-moved handling code here
}

- (void)mouseExitedAtPositionX:(double)mousePositionX
                     positionY:(double)mousePositionY
                     modifiers:(FxModifierKeys)modifiers
                   forceUpdate:(BOOL *)forceUpdate
                        atTime:(CMTime)time
{
    // TODO: Put any mouse-exited handling code here
}

@end
