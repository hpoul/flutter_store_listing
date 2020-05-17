#import "FlutterStoreListingPlugin.h"

#import <StoreKit/StoreKit.h>

@implementation FlutterStoreListingPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"flutter_store_listing"
            binaryMessenger:[registrar messenger]];
  FlutterStoreListingPlugin* instance = [[FlutterStoreListingPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"requestReview" isEqualToString:call.method]) {
      if (@available(iOS 10.3, *)) {
          [SKStoreReviewController requestReview];
          result(@YES);
      } else {
          // Fallback on earlier versions
          result(@NO);
      }
  } else if ([@"isSupportedRequestReview" isEqualToString:call.method]) {
      if (@available(iOS 10.3, *)) {
          result(@YES);
      } else {
          // Fallback on earlier versions
          result(@NO);
      }
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
