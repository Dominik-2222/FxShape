//
//  FxShapePlugIn.m
//  PlugIn
//
//  Created by Apple on 10/3/18.
//  Copyright © 2019-2023 Apple Inc. All rights reserved.
//

#import "FxShapePlugIn.h"
#import "FxMTLDeviceCache.h"
#import "FxShapeShaderTypes.h"


enum {
    kFxShape_NoCommandQueue = kFxError_ThirdPartyDeveloperStart + 1000
};

typedef struct Shapes {
    FxPoint2D   lowerLeft;
    FxPoint2D   upperRight;
    FxPoint2D   circleCenter;
    double  circleRadius;
} Shapes;

@implementation FxShapePlugIn
{
    id<MTLTexture>global_sourceTexture;
    long global_width;
    long global_height;
}
//---------------------------------------------------------
// initWithAPIManager:
//
// This method is called when a plug-in is first loaded, and
// is a good point to conduct any checks for anti-piracy or
// system compatibility. Returning NULL means that a plug-in
// chooses not to be accessible for some reason.
//---------------------------------------------------------



- (id)initWithAPIManager:(id)apiManager
{
    self = [super init];

    if (self != nil)
    {
        _apiManager		= apiManager;
    }

    return self;
}


//---------------------------------------------------------
// dealloc
//
// Override of standard NSObject dealloc. Called when plug-in
// instance is deallocated.
//---------------------------------------------------------

- (void)dealloc
{
    // Clean up
    [super dealloc];
}


- (BOOL)addParametersWithError:(NSError * _Nullable * _Nullable)error
{
    id<FxParameterCreationAPI_v5>   parmsApi;
    
    parmsApi = [_apiManager apiForProtocol:@protocol(FxParameterCreationAPI_v5)];
    if (parmsApi == nil)
    {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_APIUnavailable
                                     userInfo:@{ NSLocalizedFailureReasonErrorKey :
                                                     @"Unable to get the FxParameterCreationAPI_v5 in -addParametersWithError:" }];
        }
        
        return NO;
    }
    
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    
    [parmsApi addPointParameterWithName:[bundle localizedStringForKey:@"FxShape::Lower Left"
                                                                value:nil
                                                                table:nil]
                            parameterID:kLowerLeftID
                               defaultX:0.25
                               defaultY:0.25
                         parameterFlags:kFxParameterFlag_DEFAULT];
    
    [parmsApi addPointParameterWithName:[bundle localizedStringForKey:@"FxShape::Upper Right"
                                                                value:nil
                                                                table:nil]
                            parameterID:kUpperRightID
                               defaultX:0.5
                               defaultY:0.5
                         parameterFlags:kFxParameterFlag_DEFAULT];
    
//    [parmsApi addPointParameterWithName:[bundle localizedStringForKey:@"FxShape::Circle Center"
//                                                                value:nil
//                                                                table:nil]
//                            parameterID:kCircleCenter
//                               defaultX:0.0
//                               defaultY:0.0
//                         parameterFlags:kFxParameterFlag_DEFAULT];
    
//    [parmsApi addFloatSliderWithName:[bundle localizedStringForKey:@"FxShape::Circle Radius"
//                                                             value:nil
//                                                             table:nil]
//                         parameterID:kCircleRadius
//                        defaultValue:0.0
//                        parameterMin:0.0
//                        parameterMax:4000.0
//                           sliderMin:0.0
//                           sliderMax:1000.0
//                               delta:1.0
//                      parameterFlags:kFxParameterFlag_DEFAULT];

    return YES;
}

- (BOOL)properties:(NSDictionary * _Nonnull * _Nullable)properties
             error:(NSError * _Nullable * _Nullable)error
{
    *properties = @{
                    kFxPropertyKey_MayRemapTime : @NO,
                    kFxPropertyKey_PixelTransformSupport : [NSNumber numberWithInt:kFxPixelTransform_ScaleTranslate]
                    };
    
    return YES;
}


#pragma mark Calculating Source and Destination Rectangles

- (BOOL)destinationImageRect:(nonnull FxRect *)destinationImageRect
                sourceImages:(nonnull NSArray<FxImageTile *> *)sourceImages
            destinationImage:(nonnull FxImageTile *)destinationImage
                 pluginState:(nullable NSData *)pluginState
                      atTime:(CMTime)renderTime
                       error:(NSError * _Nullable * _Nullable)outError
{
    if (pluginState == nil)
    {
        if (outError != nil)
        {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedFailureReasonErrorKey : @"pluginState is nil in -destinationImageRect:" }];
        }
        return NO;
    }
    
    Shapes  shapeState;
    [pluginState getBytes:&shapeState
                   length:sizeof(shapeState)];
    
    // Convert the source into image space
    FxRect  srcRect = sourceImages [ 0 ].imagePixelBounds;
    FxMatrix44* srcInvPixTrans  = sourceImages [ 0 ].inversePixelTransform;
    FxPoint2D   srcLowerLeft    = { srcRect.left, srcRect.bottom };
    FxPoint2D   srcUpperRight   = { srcRect.right, srcRect.top };
    srcLowerLeft = [srcInvPixTrans transform2DPoint:srcLowerLeft];
    srcUpperRight = [srcInvPixTrans transform2DPoint:srcUpperRight];
    CGSize  srcImageSize    = CGSizeMake(srcUpperRight.x - srcLowerLeft.x, srcUpperRight.y - srcLowerLeft.y);
    
    // Union the various objects
    CGRect  imageBounds = CGRectMake(srcLowerLeft.x, srcLowerLeft.y, srcImageSize.width, srcImageSize.height);
    CGRect  rectBounds  = CGRectMake(shapeState.lowerLeft.x * srcImageSize.width,
                                     shapeState.lowerLeft.y * srcImageSize.height,
                                     (shapeState.upperRight.x - shapeState.lowerLeft.x) * srcImageSize.width,
                                     (shapeState.upperRight.y - shapeState.lowerLeft.y) * srcImageSize.height);
    rectBounds = CGRectOffset(rectBounds, srcLowerLeft.x, srcLowerLeft.y);
    CGRect  circleBounds    = CGRectMake((shapeState.circleCenter.x * srcImageSize.width - shapeState.circleRadius),
                                         (shapeState.circleCenter.y * srcImageSize.height - shapeState.circleRadius),
                                         shapeState.circleRadius * 2.0, shapeState.circleRadius * 2.0);
    circleBounds = CGRectOffset(circleBounds, srcLowerLeft.x, srcLowerLeft.y);
    
    imageBounds = CGRectUnion(imageBounds, rectBounds);
    imageBounds = CGRectUnion(imageBounds, circleBounds);
    
    // Convert back into pixel space
    FxPoint2D   dstLowerLeft    = imageBounds.origin;
    FxPoint2D   dstUpperRight   = { imageBounds.origin.x + imageBounds.size.width, imageBounds.origin.y + imageBounds.size.height };
    
    FxMatrix44* dstPixelTrans   = destinationImage.pixelTransform;
    dstLowerLeft = [dstPixelTrans transform2DPoint:dstLowerLeft];
    dstUpperRight = [dstPixelTrans transform2DPoint:dstUpperRight];
    
    destinationImageRect->left = floor(dstLowerLeft.x);
    destinationImageRect->bottom = floor(dstLowerLeft.y);
    destinationImageRect->right = ceil(dstUpperRight.x);
    destinationImageRect->top = ceil(dstUpperRight.y);
    
    return YES;
}

- (BOOL)sourceTileRect:(nonnull FxRect *)sourceTileRect
      sourceImageIndex:(NSUInteger)sourceImageIndex
          sourceImages:(nonnull NSArray<FxImageTile *> *)sourceImages
   destinationTileRect:(FxRect)destinationTileRect
      destinationImage:(nonnull FxImageTile *)destinationImage
           pluginState:(nullable NSData *)pluginState
                atTime:(CMTime)renderTime
                 error:(NSError * _Nullable * _Nullable)outError
{
    if (pluginState == nil)
    {
        if (outError != nil)
        {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedFailureReasonErrorKey : @"pluginState is nil in -destinationImageRect:" }];
        }
        return NO;
    }
    
    *sourceTileRect = destinationTileRect;
    
    return YES;
}

#pragma mark Rendering

- (BOOL)pluginState:(NSData * _Nonnull * _Nullable)pluginState
             atTime:(CMTime)renderTime
            quality:(FxQuality)qualityLevel
              error:(NSError * _Nullable * _Nullable)error
{
    id<FxParameterRetrievalAPI_v6>  paramAPI    = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramAPI == nil)
    {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_APIUnavailable
                                     userInfo:@{ NSLocalizedFailureReasonErrorKey : @"Unable to retrieve the FxParameterRetrievalAPI_v6" }];
        }
        
        return NO;
    }
    
    Shapes  shapeState  = {
        { 0.0, 0.0 },
        { 1.0, 1.0 },
        { 0.5, 0.5 },
        500.0
    };
    
    [paramAPI getXValue:&shapeState.lowerLeft.x
                 YValue:&shapeState.lowerLeft.y
          fromParameter:kLowerLeftID
                 atTime:renderTime];
    
    [paramAPI getXValue:&shapeState.upperRight.x
                 YValue:&shapeState.upperRight.y
          fromParameter:kUpperRightID
                 atTime:renderTime];
    
    [paramAPI getXValue:&shapeState.circleCenter.x
                 YValue:&shapeState.circleCenter.y
          fromParameter:kCircleCenter
                 atTime:renderTime];
    
    [paramAPI getFloatValue:&shapeState.circleRadius
              fromParameter:kCircleRadius
                     atTime:renderTime];
    
    *pluginState = [NSData dataWithBytes:&shapeState
                                  length:sizeof(shapeState)];
    
    return YES;
}

- (BOOL)areVerticesEmpty:(Vertex2D[4])vertices
{
    if ((vertices [ 0 ].position.x == 0.0) && (vertices [ 0 ].position.y == 0.0) &&
        (vertices [ 1 ].position.x == 0.0) && (vertices [ 1 ].position.y == 0.0) &&
        (vertices [ 2 ].position.x == 0.0) && (vertices [ 2 ].position.y == 0.0) &&
        (vertices [ 3 ].position.x == 0.0) && (vertices [ 3 ].position.y == 0.0))
    {
        return YES;
    }
    
    return NO;
}

- (BOOL)renderDestinationImage:(nonnull FxImageTile *)destinationImage
                  sourceImages:(nonnull NSArray<FxImageTile *> *)sourceImages
                   pluginState:(nullable NSData *)pluginState
                        atTime:(CMTime)renderTime
                         error:(NSError * _Nullable * _Nullable)outError
{
    // Set up our Metal command queue
    uint64_t            deviceRegistryID    = destinationImage.deviceRegistryID;
    FxMTLDeviceCache*   deviceCache         = [FxMTLDeviceCache deviceCache];
    MTLPixelFormat      pixelFormat         = [FxMTLDeviceCache MTLPixelFormatForImageTile:destinationImage];
    id<MTLCommandQueue> commandQueue        = [deviceCache commandQueueWithRegistryID:deviceRegistryID
                                                                          pixelFormat:pixelFormat];
    if (commandQueue == nil)
    {
        if (outError != nil)
        {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxShape_NoCommandQueue
                                        userInfo:@{ NSLocalizedDescriptionKey : @"Unable to get command queue in -render. May need to increase cache size." }];
        }
        
        return NO;
    }
    
    // Make a command buffer
    id<MTLCommandBuffer>    commandBuffer   = [commandQueue commandBuffer];
    commandBuffer.label = @"FxShape Command Buffer";
    [commandBuffer enqueue];
    
    // Setup the color attachment to draw to our output texture
    id<MTLTexture>  outputTexture   = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:deviceRegistryID]];
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
    id<MTLRenderPipelineState>  pipelineState   = [deviceCache imagePipelineStateWithRegistryID:deviceRegistryID
                                                   pixelFormat:pixelFormat];
    [commandEncoder setRenderPipelineState:pipelineState];
    
    // Get MTLTextures of our source and overlay images
    id<MTLTexture>  sourceTexture   = [sourceImages [ 0 ] metalTextureForDevice:[deviceCache deviceWithRegistryID:deviceRegistryID]];
    
    // Do the actual rendering
    [self renderImageWithDestinationTexture:outputTexture
                              sourceTexture:sourceTexture
                             commandEncoder:commandEncoder
                           destinationImage:destinationImage
                                sourceImage:sourceImages [ 0 ]
                                pluginState:pluginState];
    
    id<MTLRenderPipelineState>  shapePipelineState = [deviceCache shapePipelineStateWithRegistryID:deviceRegistryID
                                                      pixelFormat:pixelFormat];
    [commandEncoder setRenderPipelineState:shapePipelineState];
    [self renderShapesWithDestinationTexture:outputTexture
                              commandEncoder:commandEncoder
                            destinationImage:destinationImage
                                 sourceImage:sourceImages [ 0 ]
                                 pluginState:pluginState];
    
    // Clean up
    [commandEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilScheduled];
    
    [colorAttachmentDescriptor release];
    
    [deviceCache returnCommandQueueToCache:commandQueue];
    
    return YES;
}

- (void)fxMatrix:(FxMatrix44*)fxMatrix
 toMatrixFloat44:(matrix_float4x4*)floatMatrix
{
    Matrix44Data*   matrix = [fxMatrix matrix];
    for (int i = 0; i < 4; i++)
    {
        for (int j = 0; j < 4; j++)
        {
            floatMatrix->columns[j][i] = (*matrix)[i][j];
        }
    }
}

- (void)renderImageWithDestinationTexture:(id<MTLTexture>)destinationTexture
                            sourceTexture:(id<MTLTexture>)sourceTexture
                           commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder
                         destinationImage:(FxImageTile*)destinationImage
                              sourceImage:(FxImageTile*)sourceImage
                              pluginState:(NSData*)pluginState
{
    Shapes  shapeState;
    [pluginState getBytes:&shapeState
                   length:sizeof(shapeState)];
    
    float   outputWidth     = (float)(destinationImage.tilePixelBounds.right -
                                      destinationImage.tilePixelBounds.left);
    float   outputHeight    = (float)(destinationImage.tilePixelBounds.top -
                                      destinationImage.tilePixelBounds.bottom);
    global_width=sourceTexture.width;
    global_height=sourceTexture.height;
    Vertex2D vertices[4];
    // Lower Right
    vertices [ 0 ].position.x = outputWidth / 2.0;
    vertices [ 0 ].position.y = outputHeight / -2.0;
    vertices [ 0 ].textureCoordinate.x = 1.0;
    vertices [ 0 ].textureCoordinate.y = 1.0;
    
    // Lower Left
    vertices [ 1 ].position.x = outputWidth / -2.0;
    vertices [ 1 ].position.y = outputHeight / -2.0;
    vertices [ 1 ].textureCoordinate.x = 0.0;
    vertices [ 1 ].textureCoordinate.y = 1.0;

    // Upper Right
    vertices [ 2 ].position.x = outputWidth / 2.0;
    vertices [ 2 ].position.y = outputHeight / 2.0;
    vertices [ 2 ].textureCoordinate.x = 1.0;
    vertices [ 2 ].textureCoordinate.y = 0.0;

    // Upper Left
    vertices [ 3 ].position.x = outputWidth / -2.0;
    vertices [ 3 ].position.y = outputHeight / 2.0;
    vertices [ 3 ].textureCoordinate.x = 0.0;
    vertices [ 3 ].textureCoordinate.y = 0.0;


    // Because of Metal's Y-down orientation, we need to start at the top of the
    // viewport instead of the bottom.
    float   ioSurfaceHeight = [destinationImage.ioSurface height];
    MTLViewport viewport    = {
        0, ioSurfaceHeight - outputHeight, outputWidth, outputHeight, -1.0, 1.0
    };
    [commandEncoder setViewport:viewport];
    
    simd_uint2  viewportSize = {
        (unsigned int)(outputWidth),
        (unsigned int)(outputHeight)
    };
    global_sourceTexture=sourceTexture;
    // Draw the source image in the background if this tile contains it
    if ((sourceTexture != nil) && (![self areVerticesEmpty:vertices]))
    {
        [commandEncoder setVertexBytes:vertices
                                length:sizeof(vertices)
                               atIndex:FSVI_Vertices];
        
        [commandEncoder setVertexBytes:&viewportSize
                                length:sizeof(viewportSize)
                               atIndex:FSVI_ViewportSize];
        
        [commandEncoder setFragmentTexture:sourceTexture
                                   atIndex:FSTI_InputImage];
        
        [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                           vertexStart:0
                           vertexCount:4];
    }
}

- (matrix_float4x4)createModelViewMatrixWithSourceImage:(FxImageTile*)sourceImage
                                       destinationImage:(FxImageTile*)destinationImage;
{
    float left = destinationImage.tilePixelBounds.left;
    float right = destinationImage.tilePixelBounds.right;
    float bottom = destinationImage.tilePixelBounds.bottom;
    float top = destinationImage.tilePixelBounds.top;
    simd_float2  destTileCenter  = {
        (left + right) / 2.0,
        (bottom + top) / 2.0
    };
    float   imageLeft   = destinationImage.imagePixelBounds.left;
    float   imageRight  = destinationImage.imagePixelBounds.right;
    float   imageBottom = destinationImage.imagePixelBounds.bottom;
    float   imageTop    = destinationImage.imagePixelBounds.top;
    simd_float2 imageCenter = {
        (imageLeft + imageRight) / 2.0,
        (imageBottom + imageTop) / 2.0
    };
    
    // Put in the scale and translate from the pixel transform into the model matrix
    matrix_float4x4 pt;
    [self fxMatrix:sourceImage.pixelTransform
   toMatrixFloat44:&pt];
    pt.columns[0][3] += sourceImage.imagePixelBounds.left;
    pt.columns[1][3] -= sourceImage.imagePixelBounds.bottom;
    
    // Adjust for offset of this tile within the image
    matrix_float4x4 modelView = {
        {
            { 1.0, 0.0, 0.0, (imageCenter.x - destTileCenter.x) / pt.columns[0][0] },
            { 0.0, 1.0, 0.0, (imageCenter.y - destTileCenter.y) / pt.columns[1][1] },
            { 0.0, 0.0, 1.0, 0.0 },
            { 0.0, 0.0, 0.0, 1.0 }
        }
    };
    
    // Metal is Y-down by default, but all of the host app's coords are Y-up
    matrix_float4x4 yUp = {
        {
            { 1.0, 0.0, 0.0, 0.0 },
            { 0.0, -1.0, 0.0, 0.0 },
            { 0.0, 0.0, 1.0, 0.0 },
            { 0.0, 0.0, 0.0, 1.0 }
        }
    };
    modelView = matrix_multiply(modelView, yUp);
    modelView = matrix_multiply(modelView, pt);
    
    return modelView;
}

- (matrix_float4x4)createProjectionMatrixWithSourceImage:(FxImageTile*)sourceImage
                                        destinationImage:(FxImageTile*)destinationImage;
{
    float left = destinationImage.tilePixelBounds.left;
    float right = destinationImage.tilePixelBounds.right;
    float bottom = destinationImage.tilePixelBounds.bottom;
    float top = destinationImage.tilePixelBounds.top;
    float far = 1.0;
    float near = 0.0;
    
    matrix_float4x4 projection = {
        {
            { 2.0 / (right - left), 0.0, 0.0, 0.0 },
            { 0.0, 2.0 / (top - bottom), 0.0, 0.0 },
            { 0.0, 0.0, -2.0 / (far - near), 0.0 },
            { - (right + left) / (right - left), - (top + bottom) / (top - bottom), - (far + near) / (far - near), 1.0}
        }
    };
    
    return projection;
}

- (void)drawCircle:(Shapes)shapeState
   withSourceImage:(FxImageTile*)sourceImage
  destinationImage:(FxImageTile*)destinationImage
         modelView:(matrix_float4x4)modelView
        projection:(matrix_float4x4)projection
    commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder;
{
    // Get the circle center in image space
    float   inputImageWidth     = sourceImage.imagePixelBounds.right - sourceImage.imagePixelBounds.left;
    float   inputImageHeight    = sourceImage.imagePixelBounds.top - sourceImage.imagePixelBounds.bottom;
    FxPoint2D imageCircleCenter    = {
        shapeState.circleCenter.x * inputImageWidth,
        shapeState.circleCenter.y * inputImageHeight
    };
    imageCircleCenter = [sourceImage.inversePixelTransform transform2DPoint:imageCircleCenter];
    
    // Create the vertices of the circle
    const size_t kNumCircleVertices = 24;
    ShapeVertex circleVertices [ kNumCircleVertices * 3 ];  // Times 3 because we're drawing triangles
    float circleRadius = shapeState.circleRadius;
    float theta = 0.0;
    float deltaTheta = M_PI * 2.0 / (float)kNumCircleVertices;
    for (size_t nextVertexIndex = 0; nextVertexIndex < kNumCircleVertices; nextVertexIndex++)
    {
        // Circle center
        circleVertices [ nextVertexIndex * 3 + 0 ].position.x = imageCircleCenter.x;
        circleVertices [ nextVertexIndex * 3 + 0 ].position.y = imageCircleCenter.y;
        
        // Point on the circle
        circleVertices [ nextVertexIndex * 3 + 1 ].position.x = circleRadius * cos(theta) + imageCircleCenter.x;
        circleVertices [ nextVertexIndex * 3 + 1 ].position.y = circleRadius * sin(theta) + imageCircleCenter.y;
        
        // Advance the angle
        theta += deltaTheta;
        
        // Next point on the circle
        circleVertices [ nextVertexIndex * 3 + 2 ].position.x = circleRadius * cos(theta) + imageCircleCenter.x;
        circleVertices [ nextVertexIndex * 3 + 2 ].position.y = circleRadius * sin(theta) + imageCircleCenter.y;
    }
    
    // Send everything to the shaders for drawing
    [commandEncoder setVertexBytes:&circleVertices[0]
                            length:sizeof(circleVertices)
                           atIndex:FSSI_Vertices];
    
    [commandEncoder setVertexBytes:&modelView
                            length:sizeof(modelView)
                           atIndex: FSSI_ModelView];
    
    [commandEncoder setVertexBytes:&projection
                            length:sizeof(projection)
                           atIndex:FSSI_Projection];
    
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                       vertexStart:0
                       vertexCount:kNumCircleVertices * 3];
}

- (void)drawRectangle:(Shapes)shapeState
    withSourceImage:(FxImageTile*)sourceImage
   destinationImage:(FxImageTile*)destinationImage
        
          modelView:(matrix_float4x4)modelView
         projection:(matrix_float4x4)projection
     commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder;
{
    // Get the rectangle corners in image space
    float   inputImageWidth     = sourceImage.imagePixelBounds.right - sourceImage.imagePixelBounds.left;
    float   inputImageHeight    = sourceImage.imagePixelBounds.top - sourceImage.imagePixelBounds.bottom;
    if(global_width<inputImageWidth){
        global_width=inputImageWidth;
        
    }
    if(global_height<inputImageWidth){
        global_height=inputImageWidth;
        
    }
    
    FxPoint2D   rectLowerLeft = {
        shapeState.lowerLeft.x * inputImageWidth,
        shapeState.lowerLeft.y * inputImageHeight
    };
    FxPoint2D   rectUpperRight  = {
        shapeState.upperRight.x * inputImageWidth,
        shapeState.upperRight.y * inputImageHeight
    };
    rectLowerLeft = [sourceImage.inversePixelTransform transform2DPoint:rectLowerLeft];
    rectUpperRight = [sourceImage.inversePixelTransform transform2DPoint:rectUpperRight];
    
    // Create the vertices out of them
//    ShapeVertex vertices[4];
//    // Lower Right
//    vertices [ 0 ].position.x = outputWidth / 2.0;
//    vertices [ 0 ].position.y = outputHeight / -2.0;
//    vertices [ 0 ].textureCoordinate.x = 1.0;
//    vertices [ 0 ].textureCoordinate.y = 1.0;
//    
//    // Lower Left
//    vertices [ 1 ].position.x = outputWidth / -2.0;
//    vertices [ 1 ].position.y = outputHeight / -2.0;
//    vertices [ 1 ].textureCoordinate.x = 0.0;
//    vertices [ 1 ].textureCoordinate.y = 1.0;
//
//    // Upper Right
//    vertices [ 2 ].position.x = outputWidth / 2.0;
//    vertices [ 2 ].position.y = outputHeight / 2.0;
//    vertices [ 2 ].textureCoordinate.x = 1.0;
//    vertices [ 2 ].textureCoordinate.y = 0.0;
//
//    // Upper Left
//    vertices [ 3 ].position.x = outputWidth / -2.0;
//    vertices [ 3 ].position.y = outputHeight / 2.0;
//    vertices [ 3 ].textureCoordinate.x = 0.0;
//    vertices [ 3 ].textureCoordinate.y = 0.0;

    float tex_c[4][2];
    
    tex_c[0][0]=0.0; tex_c[0][1]=0.0;
    tex_c[1][0]=0.0; tex_c[1][1]=1.0;
    tex_c[2][0]=1.0; tex_c[2][1]=0.0;
    tex_c[3][0]=1.0; tex_c[3][1]=1.0;
    
    tex_c[0][0]=shapeState.upperRight.x; tex_c[0][1]=shapeState.lowerLeft.y;
    tex_c[1][0]=shapeState.upperRight.x; tex_c[1][1]=shapeState.upperRight.y;
    tex_c[2][0]=shapeState.lowerLeft.x; tex_c[2][1]=shapeState.lowerLeft.y;
    tex_c[3][0]=shapeState.lowerLeft.x; tex_c[3][1]=shapeState.upperRight.y;


  
    ShapeVertex rectVertices[] = {
        // First triangle
   
        { { rectUpperRight.x, rectLowerLeft.y },{ tex_c[0][0], tex_c[0][1]} }, // Górny lewy róg
         { { rectUpperRight.x, rectUpperRight.y },{ tex_c[1][0], tex_c[1][1]} }, // Dolny prawy róg
         { { rectLowerLeft.x, rectLowerLeft.y   },{ tex_c[2][0], tex_c[2][1]} }, // Dolny lewy róg
         // Drugi trójkąt
         { { rectLowerLeft.x, rectLowerLeft.y   },{ tex_c[2][0], tex_c[2][1]} }, // Dolny lewy róg
         { { rectLowerLeft.x, rectUpperRight.y },{ tex_c[3][0], tex_c[3][1]} }, // Górny prawy róg
         { { rectUpperRight.x, rectUpperRight.y },{ tex_c[1][0], tex_c[1][1]} } // Dolny prawy róg

    };
NSLog(@"x: %g, y: %g, x: %g, y: %g", rectUpperRight.x, rectLowerLeft.y, tex_c[0][0], tex_c[0][1]); // Top-left
NSLog(@"x: %g, y: %g, x: %g, y: %g", rectUpperRight.x, rectUpperRight.y, tex_c[1][0], tex_c[1][1]); // Bottom-right
NSLog(@"x: %g, y: %g, x: %g, y: %g", rectLowerLeft.x, rectLowerLeft.y, tex_c[2][0], tex_c[2][1]); // Bottom-left
NSLog(@"x: %g, y: %g, x: %g, y: %g", rectLowerLeft.x, rectLowerLeft.y, tex_c[2][0], tex_c[2][1]); // Bottom-left
NSLog(@"x: %g, y: %g, x: %g, y: %g", rectLowerLeft.x, rectUpperRight.y, tex_c[3][0], tex_c[3][1]); // Top-right
NSLog(@"x: %g, y: %g, x: %g, y: %g", rectUpperRight.x, rectUpperRight.y, tex_c[1][0], tex_c[1][1]);// Bottom-right

    size_t numRectVertices = sizeof(rectVertices) / sizeof (rectVertices[0]);
    
    // Pass everything to the shaders for drawing
    [commandEncoder setVertexBytes:&rectVertices
                            length:numRectVertices * sizeof(rectVertices[0])
                           atIndex:FSSI_Vertices];
    
    [commandEncoder setVertexBytes:&modelView
                            length:sizeof(modelView)
                           atIndex:FSSI_ModelView];
    
    [commandEncoder setVertexBytes:&projection
                            length:sizeof(projection)
                           atIndex:FSSI_Projection];
    [commandEncoder setFragmentTexture:global_sourceTexture
                               atIndex:FSTI_InputImage2];
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                       vertexStart:0
                       vertexCount:numRectVertices];
}
//Shape fragmentshader data
- (void)renderShapesWithDestinationTexture:(id<MTLTexture>)outputTexture
                            commandEncoder:(id<MTLRenderCommandEncoder>)commandEncoder
                          destinationImage:(FxImageTile*)destinationImage
                               sourceImage:(FxImageTile*)sourceImage
                               pluginState:(NSData*)pluginState
{
    Shapes  shapeState;
    [pluginState getBytes:&shapeState
                   length:sizeof(shapeState)];

    // Create the model view matrix accounting for which tile we're drawing
    matrix_float4x4 modelView = [self createModelViewMatrixWithSourceImage:sourceImage
                                                          destinationImage:destinationImage];

    // Create an orthographic projection
    matrix_float4x4 projection = [self createProjectionMatrixWithSourceImage:sourceImage
                                                            destinationImage:destinationImage];
    
    // Draw the circle
    [self drawCircle:shapeState
     withSourceImage:sourceImage
    destinationImage:destinationImage
           modelView:modelView
          projection:projection
      commandEncoder:commandEncoder];
    
    // Draw the rectangle
    [self drawRectangle:shapeState
        withSourceImage:sourceImage
       destinationImage:destinationImage
              modelView:modelView
             projection:projection
         commandEncoder:commandEncoder];
}

@end
