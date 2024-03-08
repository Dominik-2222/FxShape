//
//  FxShapeOSC.h
//  PlugIn
//
//  Created by Apple on 10/3/18.
//  Copyright © 2019-2023 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>
#import <Metal/Metal.h>

@interface FxShapeOSC : NSObject <FxOnScreenControl_v4>
{
    id<PROAPIAccessing> apiManager;
    
    CGPoint lastObjectPosition;
}

@end
