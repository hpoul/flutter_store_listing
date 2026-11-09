# flutter_store_listing

Flutter plugin to open store listings for the iOS App Store and the Google Play
store, and on iOS to ask for a review in-app using StoreKit's review API
(`AppStore.requestReview(in:)` on iOS 16+, falling back to
`SKStoreReviewController` on iOS 15).

Supports both Swift Package Manager and CocoaPods.

## Platforms

| | Store listing | In-app review prompt |
| --- | --- | --- |
| iOS | ✅ `apps.apple.com` | ✅ StoreKit |
| Android | ✅ Play Store app, else browser | ❌ see below |

On Android the listing opens the way Google's own [Linking to Google
Play](https://developer.android.com/distribute/marketing-tools/linking-to-google-play)
guide documents: an `ACTION_VIEW` intent for the
`play.google.com/store/apps/details` URL with the package set to
`com.android.vending`, so the Play Store app handles it instead of a browser or
a chooser. When that app is absent or disabled, the same URL is viewed without
the package restriction, and whatever else handles Play links takes it.

**Your app needs no `<queries>` manifest entry for this.** The implementation
attempts the intent and handles `ActivityNotFoundException`, which Android's
package visibility rules do not filter — unlike `canLaunchUrl` and
`queryIntentActivities`, which they do.

Up to 1.3.0 this package probed `canLaunchUrl('market://')` and opened a
`market://` URL when that said yes. On a device where your app was installed
from the Play Store it generally did say yes, because Android makes [the app
that installed your app](https://developer.android.com/training/package-visibility/automatic)
visible automatically — no `<queries>` entry, whatever the `targetSdk`. So for
most users that path was live, and 1.4.0 changes the route rather than the
destination: `market://details?id=…` and the https URL with the package set
both land in the Play Store app.

Where the probe did fail was an install from outside the Play Store —
sideloaded, or from another store — on an app targeting API 30 or higher with
no `<queries>` entry of its own, since then `com.android.vending` is not
automatically visible. Those users got the https URL in a browser, and still
do whenever the Play Store app is absent.

So the reason for the native implementation is not a dead code path. It is
that `setPackage` is not expressible through `url_launcher` at all, and that
Google no longer documents `market://` among its store-listing link formats
(`market://launch?id=…` survives for Play Instant, which this package does
not do).

The Android side has no Gradle dependencies at all. Play's in-app review API
is deliberately left out of this package to keep it free of proprietary
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
