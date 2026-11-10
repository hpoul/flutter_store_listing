# flutter_store_listing

Flutter plugin to open store listings for the iOS App Store, the Mac App Store
and the Google Play store, and on iOS and macOS to ask for a review in-app
using StoreKit's review API — `AppStore.requestReview(in:)` on iOS 16+ and
macOS 13+, falling back to `SKStoreReviewController` on iOS 15 and macOS 12.

Supports both Swift Package Manager and CocoaPods.

## Platforms

| | Store listing | In-app review prompt |
| --- | --- | --- |
| iOS | ✅ `apps.apple.com` | ✅ StoreKit |
| Android | ✅ Play Store app, else browser | ❌ see below |
| macOS | ✅ `apps.apple.com` | ✅ StoreKit |
| web, Windows, Linux | ❌ `unsupportedPlatform` | ❌ `unsupportedPlatform` |

macOS gained the listing in 2.0 and the review prompt in 2.1. Up to 1.4.0 it
fell into the Android branch and opened a Google Play web page for a macOS
bundle id.

2.0 deferred the prompt on the grounds that it needs a view controller rather
than a window scene, and that turned out to be exactly right:
`AppStore.requestReview(in:)` takes a `UIWindowScene` on iOS and an
`NSViewController` on macOS. It needs macOS 13, and falls back to the
deprecated `SKStoreReviewController.requestReview()` on macOS 12, so this
package's floor is still Flutter's own rather than one raised for a prompt.

`isInAppReviewSupported` answering true on macOS where it answered false is a
widening, which is why the prompt arrives in a minor release: UI that gated on
it gains a working prompt, and a caller that was relying on the fallback gets
the native dialog instead of a web page.

**On macOS the listing opens in the Mac App Store app, not a browser** —
verified on macOS 27.0.1 with Flutter 3.47.9, `?action=write-review` included,
which brings up the store's own *Write a Review* sheet. macOS routes
`apps.apple.com` to the store app as a universal link.

Worth knowing if you ever check this yourself: **`canLaunchUrl` will tell you
the opposite.** It reports the default handler for the `https` scheme — your
browser — because universal-link routing happens inside the open call, not in
the lookup. This package never calls `canLaunchUrl`, which is why that gap
costs you nothing here.

**2.1 declares the macOS platform**, because the prompt is native and there is
finally something to register. `pubspec.yaml` lists `ios` and `macos` with
`sharedDarwinSource: true`, so both resolve one Swift source tree, one podspec
and one `Package.swift` under `darwin/`. The platforms differ only in which
kind of window the prompt is presented into, across five `#if os(macOS)`
blocks in that one file — imports, the stored registrar, registration, the
request itself and the presenter lookup. With
CocoaPods the pod depends on `Flutter` for iOS and `FlutterMacOS` for macOS;
Swift Package Manager resolves `darwin/flutter_store_listing/Package.swift` for
both. Nothing to do on your side either way.

Up to 2.0 the macOS listing was Dart-only — an `apps.apple.com` URL handed to
`url_launcher`, which declares macOS itself — so pub.dev badged this package
Android and iOS. That badge was defensible then and is simply correct now.

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

StoreKit decides whether the prompt is actually shown — it is rate-limited per
user and per app version, and it never reports back either way. A
`StoreListingOutcome.inAppReviewRequested` means the request reached the OS,
not that anything appeared on screen. That applies on macOS exactly as on iOS,
and it is why this package cannot tell you whether your user saw a dialog.

**The fallback runs when there is no prompt, not when there is one that cannot
be shown yet.** iOS needs a foreground-active window scene to present into,
and there is none during the launch transition, while a system alert is up, or
for a visible but unfocused iPad window. That reports
`inAppReviewNotNow` and runs **no** fallback: the user never asked to leave the
app, so sending them to the App Store because it was still waking up would be
worse than doing nothing. If you ask for a review from a post-frame callback at
startup, expect this outcome sometimes and ask again later.

**macOS does not report that outcome**, although it has a condition that looks
like one: no visible window to present into. Two things make it different. The
iOS state passes on its own and the macOS one need not — a Mac app with no
window may never grow one — and the macOS fallback opens the Mac App Store, a
separate process that needs no window in your app. So a windowless Mac gets
`inAppReviewUnavailable` and the fallback runs, rather than nothing at all.

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
