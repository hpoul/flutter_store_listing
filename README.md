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
| macOS | ✅ `apps.apple.com` | ❌ not yet |
| web, Windows, Linux | ❌ `unsupportedPlatform` | ❌ `unsupportedPlatform` |

macOS gained the listing in 2.0. Up to 1.4.0 it fell into the Android branch
and opened a Google Play web page for a macOS bundle id. Its in-app prompt
needs a view controller rather than a window scene and is deferred; when it
arrives, `isInAppReviewSupported` going false→true on macOS breaks nobody.

**The macOS listing is Dart-only, and `pubspec.yaml` declares no macOS
platform**, so pub.dev badges this package Android and iOS. That is not an
oversight: the macOS path builds an `apps.apple.com` URL and hands it to
`url_launcher`, which declares macOS itself, so there is no native
implementation here to register. Declaring the platform means shipping a
`macos/` directory, and that lands with the native in-app prompt above rather
than before it. Nothing to do on your side — add the dependency and the macOS
listing works.

Web and desktop report `unsupportedPlatform` rather than silently doing
something wrong, which is the other half of the same fix.

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

So `requestReview(fallback: ReviewFallback.none)` reports
`inAppReviewUnavailable` on Android unless you configure an
`InAppReviewPrompt`. With a fallback — the default — it opens the Play listing
instead.

StoreKit decides whether the iOS prompt is actually shown — it is rate-limited
per user and per app version, and it never reports back either way. A
`StoreListingOutcome.inAppReviewRequested` means the request reached the OS,
not that anything appeared on screen.

**The fallback runs when there is no prompt, not when there is one that cannot
be shown yet.** iOS needs a foreground-active window scene to present into,
and there is none during the launch transition, while a system alert is up, or
for a visible but unfocused iPad window. That reports
`inAppReviewNotNow` and runs **no** fallback: the user never asked to leave the
app, so sending them to the App Store because it was still waking up would be
worse than doing nothing. If you ask for a review from a post-frame callback at
startup, expect this outcome sometimes and ask again later.

# Usage

See the [API documentation](https://pub.dev/documentation/flutter_store_listing/latest/flutter_store_listing/FlutterStoreListing-class.html)
for details.

Configure the shared instance once, in `main()`:

```dart
void main() {
  FlutterStoreListing.configure(
    // The numeric App Store id: for https://apps.apple.com/app/id1479297675
    // it is 1479297675. There is no runtime lookup, so Apple platforms need
    // this. Android resolves its own package name.
    appStoreId: '1479297675',
    // Only if your Mac app has its own SKU. Under universal purchase the
    // appStoreId above is already correct.
    macAppStoreId: '1478552452',
  );
  runApp(const MyApp());
}
```

Then ask for a review, or open the listing:

```dart
final listing = FlutterStoreListing.instance;

// The in-app prompt where there is one, otherwise the write-a-review page.
final outcome = await listing.requestReview();

// Or just the listing.
await listing.openStoreListing();

// Every call reports what happened, rather than a bool that cannot tell
// "no app store here" from "the launcher refused".
switch (outcome) {
  case StoreListingOutcome.inAppReviewRequested:
  case StoreListingOutcome.storeListingOpened:
    // outcome.isSuccess is true for exactly these two.
    break;
  case StoreListingOutcome.inAppReviewNotNow:
    // A prompt exists but could not be shown this instant — on iOS, no
    // foreground-active scene. Nothing happened and no fallback ran, on
    // purpose. This is the one failure worth retrying unchanged.
    break;
  default:
    // unsupportedPlatform, inAppReviewUnavailable, storeIdUnavailable or
    // launchRefused. New values may be added in a minor release, so keep a
    // `default` here — or a wildcard `_` case in a switch *expression*, where
    // `default` is not allowed.
    break;
}
```

To gate UI on whether there is anything to open, both capability getters are
synchronous and usable directly in `build()`:

```dart
if (FlutterStoreListing.instance.isStoreListingSupported) ...[
  const RateThisAppTile(),
],
```

# Notes

Heavily based on https://github.com/AppleEducate/plugins/tree/master/packages/app_review
