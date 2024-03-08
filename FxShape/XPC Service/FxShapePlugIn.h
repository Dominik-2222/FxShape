//
//  FxShapePlugIn.h
//  PlugIn
//
//  Created by Apple on 10/3/18.
//  Copyright © 2019-2023 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>

// Parameter ID
enum {
    kLowerLeftID    = 1,
    kUpperRightID   = 2,
    kCircleCenter   = 3,
    kCircleRadius   = 4
};


@interface FxShapePlugIn : NSObject <FxTileableEffect>
{
	// The cached API Manager object, as passed to the -initWithAPIManager: method.
	id<PROAPIAccessing> _apiManager;
}

@end
