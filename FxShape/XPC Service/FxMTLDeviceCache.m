//
//  FxMTLDeviceCache.m
//  PlugIn
//
//  Created by Apple on 1/24/18.
//  Copyright © 2019-2023 Apple Inc. All rights reserved.
//

#import "FxMTLDeviceCache.h"

const NSUInteger    kMaxCommandQueues   = 5;
static NSString*    kKey_InUse          = @"InUse";
static NSString*    kKey_CommandQueue   = @"CommandQueue";

static FxMTLDeviceCache*   gDeviceCache    = nil;

@interface FxMTLDeviceCacheItem : NSObject

@property (readonly)    id<MTLDevice>                           gpuDevice;
@property (readonly)    id<MTLRenderPipelineState>              imagePipelineState;
@property (readonly)    id<MTLRenderPipelineState>              shapePipelineState;
@property (readonly)    id<MTLRenderPipelineState>              oscPipelineState;
@property (retain)      NSMutableArray<NSMutableDictionary*>*   commandQueueCache;
@property (readonly)    NSLock*                                 commandQueueCacheLock;
@property (readonly)    MTLPixelFormat                          pixelFormat;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                   pixelFormat:(MTLPixelFormat)pixFormat;
- (id<MTLCommandQueue>)getNextFreeCommandQueue;
- (void)returnCommandQueue:(id<MTLCommandQueue>)commandQueue;
- (BOOL)containsCommandQueue:(id<MTLCommandQueue>)commandQueue;

@end

@implementation FxMTLDeviceCacheItem

- (instancetype)initWithDevice:(id<MTLDevice>)device
                   pixelFormat:(MTLPixelFormat)pixFormat;
{
    self = [super init];
    
    if (self != nil)
    {
        _gpuDevice = [device retain];
        
        _commandQueueCache = [[NSMutableArray alloc] initWithCapacity:kMaxCommandQueues];
        for (NSUInteger i = 0; (_commandQueueCache != nil) && (i < kMaxCommandQueues); i++)
        {
            NSMutableDictionary*   commandDict = [NSMutableDictionary dictionary];
            [commandDict setObject:[NSNumber numberWithBool:NO]
                            forKey:kKey_InUse];
            
            id<MTLCommandQueue> commandQueue    = [_gpuDevice newCommandQueue];
            [commandDict setObject:commandQueue
                            forKey:kKey_CommandQueue];
            
            [_commandQueueCache addObject:commandDict];
        }
        
        // Load all the shader files with a .metal file extension in the project
        id<MTLLibrary> defaultLibrary = [[_gpuDevice newDefaultLibrary] autorelease];
        
        // Load the vertex function from the library
        id<MTLFunction> vertexFunction = [[defaultLibrary newFunctionWithName:@"vertexShader"] autorelease];
        
        // Load the fragment function from the library
        id<MTLFunction> fragmentFunction = [[defaultLibrary newFunctionWithName:@"fragmentShader"] autorelease];
        
        id<MTLFunction> shapeVertexFunction = [[defaultLibrary newFunctionWithName:@"shapeVertexShader"] autorelease];
        id<MTLFunction> shapeFragmentFunction = [[defaultLibrary newFunctionWithName:@"shapeFragmentShader"] autorelease];
        
        id<MTLFunction> oscVertexFunction = [[defaultLibrary newFunctionWithName:@"OSCVertexShader"] autorelease];
        id<MTLFunction> oscFragmentFunction = [[defaultLibrary newFunctionWithName:@"OSCFragmentShader"] autorelease];
        
        // Configure a pipeline descriptor that is used to create a pipeline state for the image
        // drawing
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
        pipelineStateDescriptor.label = @"Image Pipeline State";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = pixFormat;
        _pixelFormat = pixFormat;
        
        NSError*    error = nil;
        _imagePipelineState = [_gpuDevice newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                    error:&error];
        if (_imagePipelineState == nil)
        {
            NSLog (@"Error generating image pipeline state: %@", error);
        }
        
        // Now make one for the shape drawing
        MTLRenderPipelineDescriptor *shapeStateDescriptor   = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
        shapeStateDescriptor.label = @"Shape Pipeline State";
        shapeStateDescriptor.vertexFunction = shapeVertexFunction;
        shapeStateDescriptor.fragmentFunction = shapeFragmentFunction;
        shapeStateDescriptor.colorAttachments[0].pixelFormat = pixFormat;
        
        _shapePipelineState = [_gpuDevice newRenderPipelineStateWithDescriptor:shapeStateDescriptor
                                                                         error:&error];
        if (_shapePipelineState == nil)
        {
            NSLog (@"Error generating shape pipeline state: %@", error);
        }
        
        // Now make one for the OSC drawing
        MTLRenderPipelineDescriptor *oscStateDescriptor = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
        oscStateDescriptor.label = @"Shape OSC Pipeline State";
        oscStateDescriptor.vertexFunction = oscVertexFunction;
        oscStateDescriptor.fragmentFunction = oscFragmentFunction;
        oscStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
        
        _oscPipelineState = [_gpuDevice newRenderPipelineStateWithDescriptor:oscStateDescriptor
                                                                       error:&error];
        
        if (_oscPipelineState == nil)
        {
            NSLog (@"Error generating OSC pipeline state: %@", error);
        }
        
        if (_commandQueueCache != nil)
        {
            _commandQueueCacheLock = [[NSLock alloc] init];
        }
        
        if ((_gpuDevice == nil) || (_commandQueueCache == nil) || (_commandQueueCacheLock == nil) ||
            (_imagePipelineState == nil) || (_shapePipelineState == nil) || (_oscPipelineState == nil))
        {
            [self release];
            self = nil;
        }
    }
    
    return self;
}

- (void)dealloc
{
    [_gpuDevice release];
    [_commandQueueCache release];
    [_commandQueueCacheLock release];
    [_imagePipelineState release];
    [_shapePipelineState release];
    [_oscPipelineState release];
    
    [super dealloc];
}

- (id<MTLCommandQueue>)getNextFreeCommandQueue
{
    id<MTLCommandQueue> result  = nil;
    
    [_commandQueueCacheLock lock];
    NSUInteger  index   = 0;
    while ((result == nil) && (index < kMaxCommandQueues))
    {
        NSMutableDictionary*    nextCommandQueue    = [_commandQueueCache objectAtIndex:index];
        NSNumber*               inUse               = [nextCommandQueue objectForKey:kKey_InUse];
        if (![inUse boolValue])
        {
            [nextCommandQueue setObject:[NSNumber numberWithBool:YES]
                                 forKey:kKey_InUse];
            result = [nextCommandQueue objectForKey:kKey_CommandQueue];
        }
        index++;
    }
    [_commandQueueCacheLock unlock];
    
    return result;
}

- (void)returnCommandQueue:(id<MTLCommandQueue>)commandQueue
{
    [_commandQueueCacheLock lock];
    
    BOOL        found   = false;
    NSUInteger  index   = 0;
    while ((!found) && (index < kMaxCommandQueues))
    {
        NSMutableDictionary*    nextCommandQueuDict = [_commandQueueCache objectAtIndex:index];
        id<MTLCommandQueue>     nextCommandQueue    = [nextCommandQueuDict objectForKey:kKey_CommandQueue];
        if (nextCommandQueue == commandQueue)
        {
            found = YES;
            [nextCommandQueuDict setObject:[NSNumber numberWithBool:NO]
                                    forKey:kKey_InUse];
        }
        index++;
    }
    
    [_commandQueueCacheLock unlock];
}

- (BOOL)containsCommandQueue:(id<MTLCommandQueue>)commandQueue
{
    BOOL        found   = NO;
    NSUInteger  index   = 0;
    while ((!found) && (index < kMaxCommandQueues))
    {
        NSMutableDictionary*    nextCommandQueuDict = [_commandQueueCache objectAtIndex:index];
        id<MTLCommandQueue>     nextCommandQueue    = [nextCommandQueuDict objectForKey:kKey_CommandQueue];
        if (nextCommandQueue == commandQueue)
        {
            found = YES;
        }
        index++;
    }
    
    return found;
}

@end

@implementation FxMTLDeviceCache

+ (FxMTLDeviceCache*)deviceCache;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDeviceCache = [[FxMTLDeviceCache alloc] init];
    });
    
    return gDeviceCache;
}

+ (MTLPixelFormat)MTLPixelFormatForImageTile:(FxImageTile*)imageTile
{
    MTLPixelFormat  result  = MTLPixelFormatRGBA16Float;
    
    switch (imageTile.ioSurface.pixelFormat)
    {
        case kCVPixelFormatType_64RGBAHalf:
            break;
            
        case kCVPixelFormatType_128RGBAFloat:
            result = MTLPixelFormatRGBA32Float;
            break;
            
        case kCVPixelFormatType_32BGRA:
            result = MTLPixelFormatBGRA8Unorm;
            break;
            
        default:
            NSLog (@"Got an unexpected pixel format in the IOSurface: %c%c%c%c",
                   (imageTile.ioSurface.pixelFormat >> 24) & 0x000000FF,
                   (imageTile.ioSurface.pixelFormat >> 16) & 0x000000FF,
                   (imageTile.ioSurface.pixelFormat >> 8) & 0x000000FF,
                   (imageTile.ioSurface.pixelFormat & 0x000000FF));
            break;
    }
    
    return result;
}

- (instancetype)init
{
    self = [super init];
    
    if (self != nil)
    {
        NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
        
        deviceCaches = [[NSMutableArray alloc] initWithCapacity:devices.count];
        
        for (id<MTLDevice> nextDevice in devices)
        {
            FxMTLDeviceCacheItem*  newCacheItem    = [[[FxMTLDeviceCacheItem alloc] initWithDevice:nextDevice
                                                                                       pixelFormat:MTLPixelFormatRGBA16Float]
                                                      autorelease];
            [deviceCaches addObject:newCacheItem];
        }
        
        [devices release];
    }
    
    return self;
}

- (void)dealloc
{
    [deviceCaches release];
    
    [super dealloc];
}

- (id<MTLDevice>)deviceWithRegistryID:(uint64_t)registryID
{
    for (FxMTLDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if (nextCacheItem.gpuDevice.registryID == registryID)
        {
            return nextCacheItem.gpuDevice;
        }
    }
    
    return nil;
}

- (id<MTLRenderPipelineState>)imagePipelineStateWithRegistryID:(uint64_t)registryID
                                                   pixelFormat:(MTLPixelFormat)pixelFormat
{
    for (FxMTLDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if ((nextCacheItem.gpuDevice.registryID == registryID) &&
            (nextCacheItem.pixelFormat == pixelFormat))
        {
            return nextCacheItem.imagePipelineState;
        }
    }
    
    // Didn't find one, so create one with the right settings
    NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
    id<MTLDevice>   device  = nil;
    for (id<MTLDevice> nextDevice in devices)
    {
        if (nextDevice.registryID == registryID)
        {
            device = nextDevice;
        }
    }
    
    id<MTLRenderPipelineState>  result  = nil;
    if (device != nil)
    {
        FxMTLDeviceCacheItem*   newCacheItem    = [[[FxMTLDeviceCacheItem alloc] initWithDevice:device
                                                                                    pixelFormat:pixelFormat]
                                                   autorelease];
        if (newCacheItem != nil)
        {
            [deviceCaches addObject:newCacheItem];
            result = newCacheItem.imagePipelineState;
        }
    }
    [devices release];
    
    return result;
}

- (id<MTLRenderPipelineState>)shapePipelineStateWithRegistryID:(uint64_t)registryID
                                                   pixelFormat:(MTLPixelFormat)pixelFormat
{
    for (FxMTLDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if ((nextCacheItem.gpuDevice.registryID == registryID) &&
            (nextCacheItem.pixelFormat == pixelFormat))
        {
            return nextCacheItem.shapePipelineState;
        }
    }
   
    // Didn't find one, so create one with the right settings
    NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
    id<MTLDevice>   device  = nil;
    for (id<MTLDevice> nextDevice in devices)
    {
        if (nextDevice.registryID == registryID)
        {
            device = nextDevice;
        }
    }
    
    id<MTLRenderPipelineState>  result  = nil;
    if (device != nil)
    {
        FxMTLDeviceCacheItem*   newCacheItem    = [[[FxMTLDeviceCacheItem alloc] initWithDevice:device
                                                                                    pixelFormat:pixelFormat]
                                                   autorelease];
        if (newCacheItem != nil)
        {
            [deviceCaches addObject:newCacheItem];
            result = newCacheItem.shapePipelineState;
        }
    }
    [devices release];

    return result;
}

- (id<MTLRenderPipelineState>)oscPipelineStateWithRegistryID:(uint64_t)registryID
{
    for (FxMTLDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if (nextCacheItem.gpuDevice.registryID == registryID)
        {
            return nextCacheItem.oscPipelineState;
        }
    }
    
    return nil;
}

- (id<MTLCommandQueue>)commandQueueWithRegistryID:(uint64_t)registryID
                                      pixelFormat:(MTLPixelFormat)pixelFormat;
{
    for (FxMTLDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if ((nextCacheItem.gpuDevice.registryID == registryID) &&
            (nextCacheItem.pixelFormat == pixelFormat))
        {
            return [nextCacheItem getNextFreeCommandQueue];
        }
    }
    
    // Didn't find one, so create one with the right settings
    NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
    id<MTLDevice>   device  = nil;
    for (id<MTLDevice> nextDevice in devices)
    {
        if (nextDevice.registryID == registryID)
        {
            device = nextDevice;
        }
    }
    
    id<MTLCommandQueue>  result  = nil;
    if (device != nil)
    {
        FxMTLDeviceCacheItem*   newCacheItem    = [[[FxMTLDeviceCacheItem alloc] initWithDevice:device
                                                                                    pixelFormat:pixelFormat]
                                                   autorelease];
        if (newCacheItem != nil)
        {
            [deviceCaches addObject:newCacheItem];
            result = [newCacheItem getNextFreeCommandQueue];
        }
    }
    [devices release];
    
    return result;
}

- (void)returnCommandQueueToCache:(id<MTLCommandQueue>)commandQueue;
{
    for (FxMTLDeviceCacheItem* nextCacheItem in deviceCaches)
    {
        if ([nextCacheItem containsCommandQueue:commandQueue])
        {
            [nextCacheItem returnCommandQueue:commandQueue];
            break;
        }
    }
}

@end
