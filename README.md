# flutter_store_listing

Flutter plugin to open store listings for the iOS App Store and the Google Play
store, and on iOS to ask for a review in-app using StoreKit's review API
(`AppStore.requestReview(in:)` on iOS 16+, falling back to
`SKStoreReviewController` on iOS 13–15).

Supports both Swift Package Manager and CocoaPods.

## Platforms

| | Store listing | In-app review prompt |
| --- | --- | --- |
| iOS | ✅ `apps.apple.com` | ✅ StoreKit |
| Android | ✅ `market://`, else Play web | ❌ see below |

There is no native Android code: the Play listing is opened with
`url_launcher`, so nothing is needed on the platform side. Play's in-app review
API is deliberately left out of this package to keep it free of proprietary
dependencies, which would otherwise end up in F-Droid builds.

`launchRequestReview(onlyNative: true)` therefore does nothing on Android.
Without `onlyNative` it opens the Play store listing instead.

StoreKit decides whether the iOS prompt is actually shown — it is rate-limited
per user and per app version, and it never reports back either way.

# Usage

see [API Documentation for details](https://pub.dev/documentation/flutter_store_listing/latest/flutter_store_listing/FlutterStoreListing-class.html):
https://pub.dev/documentation/flutter_store_listing/latest/flutter_store_listing/FlutterStoreListing-class.html

```dart
void main() {
  // If available, display the review request dialog.
  // Does nothing when not on iOS.
  FlutterStoreListing().launchRequestReview(onlyNative: true);

  // Use URL Launcher to open play store / itunes store listing for review.
  FlutterStoreListing().launchStoreListing();
}
```

# Notes

Heavily based on https://github.com/AppleEducate/plugins/tree/master/packages/app_review
