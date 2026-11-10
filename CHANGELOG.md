## 2.1.0

**The StoreKit review prompt now works on macOS, and the package declares the
macOS platform.** 2.0 gave macOS the store listing in Dart and deferred the
prompt, on the grounds that the native side needs a view controller rather
than a window scene. That premise was right, and the SDK says so exactly:
`AppStore.requestReview(in:)` takes a `UIWindowScene` on iOS and an
`NSViewController` on macOS.

* **`isInAppReviewSupported` answers true on macOS**, where it answered false.
  A widening, which is what makes this a minor release: UI that gated on the
  getter gains a working prompt, and a caller that was relying on
  `ReviewFallback.writeReviewPage` gets the native dialog instead of a web
  page. If you want the old behaviour on macOS, pass
  `ReviewFallback.writeReviewPage` to `openStoreListing` rather than
  `requestReview`.
* **One Swift source tree for both Apple platforms.** `ios/` is now `darwin/`,
  with `sharedDarwinSource: true` on both platform entries, one podspec and one
  `Package.swift`. Nothing changes for consumers — Flutter resolves the new
  path itself, under CocoaPods and Swift Package Manager alike — and the two
  platforms differ in a single `#if os(macOS)`.
* **macOS 12 is still supported.** The modern API needs macOS 13; below that
  the prompt falls back to the deprecated no-argument
  `SKStoreReviewController.requestReview()`, rather than the package raising
  Flutter's own floor for one call.
* **A new `noPresenter` reply maps to `inAppReviewNotNow`**, macOS's version of
  iOS's `noActiveScene`: no view controller, so no window to present in, so no
  fallback. The iOS spelling is still read rather than renamed, because
  upgrading this package without rebuilding the host leaves an older compiled
  plugin answering newer Dart code.

### One bug found on the way

**`isInAppReviewSupported` kept its own copy of the platform list.** The getter
is synchronous and `InAppReviewPrompt.isAvailable()` is not, so the same fact
was written twice — and teaching the prompt about macOS left the getter saying
`platform == StorePlatform.iOS` with the whole suite still green, because
nothing compared the two. The getter now asks
`StoreKitInAppReview.supportsPlatform`, and a test holds them to the same
answer for every `StorePlatform` value, including ones added later.

## 2.0.0

**Breaking: every method returns a `StoreListingOutcome` instead of a `bool`,
the platform is a value rather than a compile-time global, and the iTunes
lookup is gone.** The design and its reasoning are in
[`doc/api-2.0-design.md`](doc/api-2.0-design.md).

### What this fixes

* **macOS, Windows, Linux and web used to take the Android branch.** A macOS
  build opened a Google Play web page for a macOS bundle id and returned
  `true`. macOS now opens its own App Store listing — in the Mac App Store
  app, verified on macOS 27.0.1, with `?action=write-review` bringing up the
  store's *Write a Review* sheet; the rest report `unsupportedPlatform`.
* **A bare `bool` could not tell "no app store here" from "could not resolve
  the id" from "the launcher refused"** — or, when the id resolved to the
  string `"null"`, from success. `StoreListingOutcome` distinguishes all of
  them, and `outcome.isSuccess` is there when you do not care which.
* **`getIosAppId()` did a network call to discover a build-time constant.** It
  hit the iTunes `/lookup` endpoint on every launch, passed no `country` so it
  searched the US storefront only — an app not published in the US failed
  permanently, not just offline — and `results[0]['trackId'].toString()`
  yielded the literal string `"null"` on a missing field, which then launched
  `/idnull`. Deleted. `appStoreId` is a configuration value, and the `http`
  dependency is gone from every consumer's tree with it.
* **Nothing was testable.** The platform came from a conditional import, and
  the iOS prompt was a `static const MethodChannel` with no seam, so neither
  could be faked. Both are injectable now and the suite covers every outcome.
* **iOS could claim a prompt it had not shown.** The Swift side fell back to an
  arbitrary member of `connectedScenes` when none was foreground-active, then
  reported success. It now says so, and you get the new
  `inAppReviewNotNow` — **no fallback runs**, because that state is transient
  and the user never asked to leave the app. An app requesting a review from a
  post-frame callback at startup sees this sometimes; ask again later.

### Migration

| 1.4.0 | 2.0.0 |
|---|---|
| `FlutterStoreListing()` | `FlutterStoreListing.instance` — **there is no unnamed constructor**, deliberately |
| `FlutterStoreListing.customize(…)` | `FlutterStoreListing.custom(…)` |
| `forceIosAppId` | `appStoreId`, a `configure()`/`custom()` argument; no public field |
| `forceAndroidPackageName` | `androidPackageName`, likewise argument-only |
| `isSupported()` | `isStoreListingSupported` — synchronous |
| `isSupportedNativeRequestReview()` | `isInAppReviewSupported` — synchronous |
| `launchStoreListing({iosWriteReview})` | `openStoreListing({writeReview})` — **default flipped to false** |
| `launchRequestReview({onlyNative})` | `requestReview({fallback})` |
| `getIosAppId()`, `getAndroidPackageName()` | `storeId()` |
| `getIosStoreListing()`, `getAndroidStoreListing()` | `appStoreUri()`, `playStoreWebUri()` — static, returning `Uri` |
| `urlCanLaunch`, `defaultUrlCanLaunch` | removed; unused since 1.4.0 |
| `urlLaunch`, `defaultUrlLaunch` | the `StoreListingLauncher` seam |
| `playStorePackageName` | removed; the default launcher is the only thing that needed it |
| — | `configure()`, `storeListingUri()`, `StorePlatform`, `ReviewFallback` |

Most of that is a compile error if you miss it, which is why the unnamed
constructor was removed rather than kept as a generative one: it would have
gone on compiling while quietly returning an instance `configure()` never
touched.

**Two changes are silent, so check them.**

1. **Configure `appStoreId`, or Apple platforms report `storeIdUnavailable`.**
   The iTunes lookup that used to find it is gone. Debug builds assert; release
   builds report the outcome, because an app may legitimately run unconfigured.
   Verify the id before you ship.
2. **Desktop and web flip from `true` to false.** A call site that branched on
   the old `bool` sees `isSuccess == false` where it used to see success after
   opening a Google Play page. That is the first bug above being fixed, but no
   compiler will point at it.

```dart
// Before
FlutterStoreListing().launchRequestReview(onlyNative: true);
await FlutterStoreListing().launchStoreListing();

// After — note writeReview: true to keep 1.4.0's behaviour, since the
// default is now the plain listing.
FlutterStoreListing.configure(appStoreId: '1479297675');
await FlutterStoreListing.instance
    .requestReview(fallback: ReviewFallback.none);
await FlutterStoreListing.instance.openStoreListing(writeReview: true);
```

### Also

* **`StoreListingOutcome` may gain values in a minor release**, which is a
  breaking change by Dart's rules and so is said here rather than implied to be
  free. Keep a `default` clause in a switch statement, or a wildcard `_` case
  in a switch expression — `default` is a compile-time error in an expression.
  `ReviewFallback`, `StorePlatform` and `InAppReviewRequest` are closed.
* **The review fallback runs when there is no prompt, not when there is one
  that cannot be shown yet.** `InAppReviewPrompt.requestReview()` returns
  `InAppReviewRequest` rather than a `bool` so those two are distinguishable:
  `unavailable` runs your `ReviewFallback`, `notNow` reports
  `inAppReviewNotNow` and does nothing. A `bool` could not carry it, because
  `isAvailable()` answers from the platform alone on iOS and so reads `true`
  both for an inactive scene and for a plugin that never registered — and those
  want opposite handling. If you implement the seam, note that
  **`unavailable` is the value for a failure**, which is what `false` used to
  mean.
* **`InAppReviewPrompt` is the Android in-app review seam.** A separate package
  can implement it against Play's review API and you wire it in with
  `configure(inAppReview: …)`, so the proprietary Play dependency stays out of
  this package and out of F-Droid builds. No such package is published yet.
* **A prompt passed to `configure()` is *preferred*, not substituted.**
  `configure()` is global and a prompt is usually platform-specific, so the one
  call above would otherwise have replaced StoreKit on iOS for every app that
  ships on both stores — and a Play-backed prompt reports itself unavailable on
  iOS, so the user who should have seen the native rating dialog got the App
  Store write-review page instead. The configured prompt is asked first on
  every platform and this package's own prompt stays behind it
  (`PreferredInAppReview`). A prompt passed to `custom()` still wins outright.
* **The bundled implementations are exported**
  (`DefaultStoreListingLauncher`, `PackageInfoStoreIdentity`,
  `StoreKitInAppReview`, `PreferredInAppReview`), so you can decorate the
  default behaviour — log a launch, confirm before leaving the app — instead of
  reimplementing the Android store intent to get at it.
* **macOS support is Dart-only and `pubspec.yaml` declares no macOS platform**,
  so pub.dev badges this package Android and iOS. The macOS path builds an
  `apps.apple.com` URL and hands it to `url_launcher`, so there is no native
  implementation here to register; declaring the platform means shipping a
  `macos/` directory, which lands with the native macOS prompt. The listing
  works on macOS with no extra step on your side. The example app now has a
  macOS target, so this is reproducible rather than asserted.
* `configure()` **merges**: an argument left out keeps its current value, so an
  app's own call and a review package's compose rather than overwriting.
* The shared instance reads its configuration **per call**, so a reference
  captured in a `State` field initialiser before `main()` configures it still
  works.
* The Android Kotlin implementation is unchanged from 1.4.0 apart from the
  `no_activity` comment, which described the Dart retry this release removes.
  The Dart side now distinguishes `MissingPluginException` (fall back to
  `url_launcher`) from a `PlatformException` such as `no_activity` (do not —
  `url_launcher` is `ActivityAware` too and detached in the same window), and a
  reply it cannot read — a wrong type included — falls back rather than
  throwing out of a method that promises an outcome.

## 1.4.0

**Android gets a native implementation, and the `market://` probe is gone.**
`launchStoreListing` used to ask `canLaunchUrl('market://')` and open
`market://details?id=…` when that said yes. On a device where the app was
installed from the Play Store it generally did say yes: Android makes "the app
that installed your app" visible automatically, with no `<queries>` entry and
whatever the `targetSdk`. **For most users, then, `market://details?id=…` is
what actually opened, and this release changes the route rather than the
destination** — both it and the https URL with the package set land in the
Play Store app.

The probe did fail for installs from outside the Play Store — sideloaded, or
from another store — on an app targeting API 30 or higher with no `<queries>`
entry of its own, because `com.android.vending` is then not automatically
visible. Those users got the https URL in a browser, and still do whenever the
Play Store app is absent.

It now opens the listing the way Google's "Linking to Google Play" guide
documents: an `ACTION_VIEW` intent for the `play.google.com` URL with the
package set to `com.android.vending`, which `url_launcher` cannot express.
When the Play Store app is absent or disabled the same URL is viewed without
the restriction, so devices without Play — F-Droid installs among them — still
reach the listing in a browser. **No `<queries>` entry is needed**: the
implementation attempts the intent and handles `ActivityNotFoundException`
rather than querying, which package visibility does not filter.

For most users this is the behaviour they already had, now arrived at on
purpose and by the route Google documents, rather than through a probe whose
answer depended on how the app had been installed. On a device without the
Play Store app, the listing still opens in whatever claims Play links.

* The package declares `android` in `flutter.plugin.platforms` for the first
  time, so pub.dev lists Android support that was always there in practice.
  Every consumer's Android build therefore gains a Gradle module and a Kotlin
  compile step, and the module declares `minSdk 24` — Flutter's own floor, and
  the same value `url_launcher_android` declares, so an app already pulling
  `url_launcher` is at 24 regardless.
* The Android side has **no `implementation` dependencies**: no androidx, and
  in particular no Play Core, so Play's in-app review API is still deliberately
  out of this package and it stays clean in F-Droid builds. JUnit, Mockito and
  Robolectric are `testImplementation` only, resolved when the module's own
  tests are run.
* `FlutterStoreListing.customize(urlCanLaunch: …)` still compiles but is no
  longer called by this package. It is removed in 2.0.
* `FlutterStoreListing.playStorePackageName` is exposed for callers building
  their own intents.

## 1.3.0

**Requires Flutter 3.44 / Dart 3.10.** Swift Package Manager support needs the
generated `FlutterFramework` Swift package, which Flutter only produces from
3.44.0 on.

**Behaviour change: `launchRequestReview` no longer contradicts its own
documentation.** It was inverted in both branches, so iOS callers got the
opposite of what the API said:

* A *successful* native prompt also opened the App Store write-review page,
  ejecting the user to the App Store immediately after the in-app dialog. The
  two are now exclusive — the store listing is the fallback for when the
  native dialog is unavailable, which is what the doc comment always claimed.
* `onlyNative: true` returned `false` precisely when the prompt *had* been
  shown, and the iOS branch returned `true` when the native call had failed
  and nothing at all had happened. Both are now the right way round: `true`
  means a review was asked for, `false` means it was not.

If you branch on the return value of `launchRequestReview()`, re-check it. If
you call it for its side effect only, the visible change is that iOS users are
no longer sent to the App Store after being shown the in-app prompt.

* Allow `package_info_plus` 10.x (widened to `>=1.0.3 <11.0.0`). This was the
  only thing making version solving fail for apps that need
  `package_info_plus` 10.x.
* Add **Swift Package Manager support**. The plugin ships
  `ios/flutter_store_listing/Package.swift` alongside the podspec, so it no
  longer appears in Flutter's "plugins do not support Swift Package Manager"
  warning. CocoaPods consumers are unaffected; both build the same sources.
* Rewrite the iOS plugin in **Swift**. This is a prerequisite for the item
  below: `AppStore.requestReview(in:)` is a Swift-only StoreKit 2 API and
  cannot be called from Objective-C.
* iOS: use **`AppStore.requestReview(in:)`** on iOS 16+. The whole
  `SKStoreReviewController` class is deprecated as of iOS 18; the deprecated
  `requestReview(in:)` remains the fallback for iOS 15. The old
  `@available(iOS 10.3, *)` guards and the no-scene `requestReview()` call are
  gone.
* **Remove the Android platform entry.** Its `onMethodCall` only ever returned
  `notImplemented()`, and the Dart side never invoked the channel off iOS, so
  consumers were building an AAR for nothing. Nothing changes at runtime:
  Android still opens the Play listing through `url_launcher`. Play's in-app
  review API is deliberately left out so this package stays free of
  proprietary dependencies, which would otherwise reach F-Droid builds.
* Fix `forceAndroidPackageName` being ignored by `launchStoreListing()`, which
  read the package name straight from `package_info_plus`.
* The package is now **WebAssembly-compatible**: `dart:io` is behind a
  conditional import instead of being imported unconditionally for `Platform`.
* Remove the discontinued `pedantic` dependency (it was unused, and declared
  as a runtime instead of a dev dependency).
* iOS: use `https` for the iTunes lookup API — App Transport Security blocks
  cleartext `http` by default, so this likely failed on device unless the host
  app carried an ATS exception.
* iOS: generate store listing URLs for `apps.apple.com` without a hardcoded
  `/us/` storefront, instead of the legacy `itunes.apple.com/us/app/id…` form.
* Give the iOS podspec real metadata (it was unedited template boilerplate)
  and a 15.0 deployment target, matching the oldest iOS that Flutter 3.44
  itself supports.
* Add an actual test suite — the previous one was an empty `main()` — and a
  GitHub Actions workflow that analyzes, formats, tests and builds the example
  for iOS.

## 1.2.0

* Update AGB Version, Android SDK Version, etc.

## 1.1.0

* Compatibility with Flutter 3.29

## 1.0.0

* Upgrade `package_info_plus` dependency.

## 0.3.1

* Upgrade dependencies.

## 0.3.0

* Upgrade dependencies
* Android: Upgrade to AGP 8.1, migrate namespace, etc.

## 0.2.2

* Update dependencies, dart 3.0

## 0.2.1+1

* Update dependencies.

## 0.2.1

* update to dependency `package_info_plus`

## 0.2.0+1

* Remove unnecessary casts.

## 0.2.0

* Nullsafety migration.

## 0.1.1+2

* More documentation, updated links.
* No longer a singleton, override app store id and android package name.
* Add isSupported() methods.
* Made API more consistent.
* Added simple example.

## 0.1.0

* First release

## 0.0.1

* Initial version

