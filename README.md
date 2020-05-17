# flutter_store_listing

Flutter plugin to open store listings for iOS App Store and Google Play store and
handle reviews, and on iOS ask for reviews using `SKStoreReviewController`

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
