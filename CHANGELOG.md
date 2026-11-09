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

