//
//  FxMTLDeviceCache.h
//  PlugIn
//
//  Created by Apple on 1/24/18.
//  Copyright © 2019-2023 Apple Inc. All rights reserved.
//

#import <Metal/Metal.h>
#import <FxPlug/FxPlugSDK.h>

@class FxMTLDeviceCacheItem;

@interface FxMTLDeviceCache : NSObject
{
    NSMutableArray<FxMTLDeviceCacheItem*>*    deviceCaches;
}

+ (FxMTLDeviceCache*)deviceCache;
+ (MTLPixelFormat)MTLPixelFormatForImageTile:(FxImageTile*)imageTile;

- (id<MTLDevice>)deviceWithRegistryID:(uint64_t)registryID;
- (id<MTLRenderPipelineState>)imagePipelineStateWithRegistryID:(uint64_t)registryID
                                                   pixelFormat:(MTLPixelFormat)pixelFormat;
- (id<MTLRenderPipelineState>)shapePipelineStateWithRegistryID:(uint64_t)registryID
                                                   pixelFormat:(MTLPixelFormat)pixelFormat;
- (id<MTLRenderPipelineState>)oscPipelineStateWithRegistryID:(uint64_t)registryID;
- (id<MTLCommandQueue>)commandQueueWithRegistryID:(uint64_t)registryID
                                      pixelFormat:(MTLPixelFormat)pixelFormat;
- (void)returnCommandQueueToCache:(id<MTLCommandQueue>)commandQueue;

@end
