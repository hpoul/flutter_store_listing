# flutter_store_listing 2.0 — API design, for review

Status: **proposal, nothing implemented.** Written after the PR #3 review, which
turned up more design problems than bugs.

The whole package is 190 lines of Dart plus 68 of Swift, so an overhaul is
cheap. The expensive part is the public API, because it is published, so this
document is about getting that right before any code moves.

---

## 0. Sequencing — the one decision that blocks the rest

1.3.0 exists to unblock AuthPass, it is reviewed, and CI is green on it. An API
overhaul is a breaking change and therefore 2.0.0.

**Recommendation: publish 1.3.0 first, from the current branch tip, then land
2.0.0 on top in this same PR.** `dart pub publish` publishes the working tree,
so nothing stops you publishing 1.3.0 today and continuing here. The reason to
split is that AuthPass is blocked *now*, and coupling its unblock to an API
redesign means AuthPass also has to rewrite its two call sites before it can
move — for a change that has nothing to do with `package_info_plus`.

The alternative — one PR, one release, 2.0.0 only — is simpler bookkeeping and
fine if AuthPass is not in a hurry. Your call; everything below is unaffected.

---

## 1. What is actually wrong today

Not style. Each of these has a concrete failure or a concrete cost.

| # | Problem | Consequence |
|---|---|---|
| 1 | `_isIOS` / `_isAndroid` come from a compile-time conditional import | No test can choose a platform. Five existing tests reach the Android branch only because the test VM says `macos` |
| 2 | `if (_isIOS) … else …` | web, macOS, Windows and Linux all fall into the **Android** branch. On web it opens a Play Store page for a package that does not exist, and returns `true` |
| 3 | `getIosAppId()` does an **iTunes network lookup** on every iOS `launchStoreListing()` | A network round trip to discover a build-time constant. Fails offline — exactly when someone might be reviewing. No caching |
| 4 | that lookup returns `String?`, and `getIosStoreListing` takes `String?` | `https://apps.apple.com/app/idnull?action=write-review` gets launched, and `true` is returned |
| 5 | every method returns bare `bool` | "unsupported platform", "could not resolve the app id" and "the launcher refused" are indistinguishable from each other and, in case 4, from success |
| 6 | `isSupported()` / `isSupportedNativeRequestReview()` are `Future<bool>` | an `await` and a method-channel round trip to learn a compile-time constant. Awkward in `build()` |
| 7 | `launchStoreListing({bool iosWriteReview = true})` | a method named "open store listing" opens the **write-a-review** page by default |
| 8 | `FlutterStoreListing()` is a factory over a static singleton built with defaults | the injection seam on `customize()` cannot be used to configure the instance everyone actually calls |
| 9 | `_getPackageName()` calls `PackageInfo.fromPlatform()` and logs four fields every call | repeated platform channel work per launch, and log noise |
| 10 | `getIosStoreListing(appId, {String protocol = 'https'})` | stringly-typed scheme. `itms-apps://apps.apple.com/…` is also unverified — Apple documented that scheme against the old `itunes.apple.com` host |
| 11 | `results[0]['trackId']` | untyped dynamic indexing on a parsed JSON response |
| 12 | no seam for Android in-app review | the agreed `flutter_store_listing_play_review` package has nothing to plug into |

Items 1, 2 and 5 are the ones worth redesigning for. The rest fall out.

---

## 2. Proposed API

### 2.1 Outcomes instead of `bool`

```dart
/// What happened when a review prompt or store listing was requested.
enum StoreListingOutcome {
  /// The native in-app review prompt was handed to the OS. The OS decides
  /// whether it is actually shown, and never reports back.
  nativeReviewRequested,

  /// An external store URL was opened.
  storeListingOpened,

  /// This platform has no app store to open. Web, Windows, Linux.
  unsupportedPlatform,

  /// The app's own store identity could not be determined, so no URL could be
  /// built. Pass [FlutterStoreListing.appleAppId] to rule this out.
  appIdUnavailable,

  /// A URL was built, but the platform refused to open it.
  launchRefused,
}

extension StoreListingOutcomeSuccess on StoreListingOutcome {
  /// Whether the user was actually taken somewhere, or a prompt requested.
  bool get isSuccess =>
      this == StoreListingOutcome.nativeReviewRequested ||
      this == StoreListingOutcome.storeListingOpened;
}
```

`isSuccess` keeps the migration for existing `bool` call sites to one word,
which matters: AuthPass returns these values straight out of a `customActions`
handler.

### 2.2 Review fallback instead of `onlyNative`

```dart
/// What to do when the native in-app review prompt is not available.
enum ReviewFallback {
  /// Open the store's write-a-review page. The default.
  writeReviewPage,

  /// Open the plain store listing.
  storeListing,

  /// Do nothing, and report [StoreListingOutcome.unsupportedPlatform].
  none,
}
```

`onlyNative: true` becomes `ReviewFallback.none`; `onlyNative: false` becomes
`ReviewFallback.writeReviewPage`. The boolean could only ever express two of
these three, and which two was not obvious from the name.

### 2.3 The platform, as a value rather than a global

```dart
/// The platforms this package distinguishes.
enum StorePlatform {
  appleIos,
  appleMacos,
  android,

  /// Everything with no app store: web, Windows, Linux.
  none;

  /// The platform the app is running on. Resolved through a conditional
  /// import so that importing this package does not pull in `dart:io`.
  static StorePlatform get current => resolveStorePlatform();
}
```

This is the fix for problems 1 and 2 at once: a value can be injected, and
`none` makes the web and desktop cases explicit rather than "whatever the
`else` branch does".

### 2.4 The class

```dart
class FlutterStoreListing {
  /// The normal constructor.
  ///
  /// Pass [appleAppId] whenever you know it — it is a build-time constant, and
  /// supplying it avoids a network lookup and makes
  /// [StoreListingOutcome.appIdUnavailable] impossible.
  FlutterStoreListing({String? appleAppId, String? androidPackageName});

  /// Every external dependency injectable, for tests and unusual hosts.
  FlutterStoreListing.custom({
    String? appleAppId,
    String? androidPackageName,
    StorePlatform platform,
    AppIdentity identity,
    UrlLauncher urlLauncher,
    NativeReviewRequester nativeReview,
  });

  /// Whether this platform has a store listing to open. Synchronous.
  bool get isStoreListingSupported;

  /// Whether a native in-app review prompt is available. Synchronous.
  bool get isNativeReviewSupported;

  /// Asks for a review: the native in-app prompt where available, otherwise
  /// [fallback]. The prompt and the store listing are mutually exclusive.
  Future<StoreListingOutcome> requestReview({
    ReviewFallback fallback = ReviewFallback.writeReviewPage,
  });

  /// Opens the app's store listing externally.
  Future<StoreListingOutcome> openStoreListing({bool writeReview = false});

  /// The URL [openStoreListing] would open, or null if it cannot be built.
  /// For building your own UI.
  Future<Uri?> storeListingUri({bool writeReview = false});

  // Pure, static, no I/O.
  static Uri appleStoreUri({required String appId, bool writeReview = false});
  static Uri playStoreUri({required String packageName});
  static Uri playStoreAppUri({required String packageName}); // market://
}
```

Deliberate choices:

* **`writeReview` defaults to `false`** on `openStoreListing`, inverting
  today's default. A method named for the listing should open the listing.
  `requestReview`'s *fallback* still defaults to the write-review page, which
  is where that behaviour belongs.
* **`Uri`, not `String`.** `url_launcher` wants a `Uri`, the current code
  builds strings and parses them back, and `protocol: 'itms-apps'` disappears
  as a concept — pass the `Uri` you want to `storeListingUri`'s caller side, or
  use the static builders.
* **The capability getters are synchronous.** No channel round trip, usable
  directly in `build()`.
* **No singleton.** `FlutterStoreListing(appleAppId: …)` is cheap to construct;
  the factory-over-static-instance is what made the existing injection seam
  unusable.

### 2.5 Seams

```dart
/// Resolves the app's own store identity.
abstract interface class AppIdentity {
  Future<String?> appleAppId();
  Future<String> androidPackageName();
}

/// The default: `package_info_plus`, plus an iTunes lookup for the Apple app
/// id when it was not supplied. Caches both for the process lifetime.
class PackageInfoAppIdentity implements AppIdentity { … }

/// A native in-app review prompt.
abstract interface class NativeReviewRequester {
  bool get isAvailable;
  Future<bool> requestReview();
}
```

`NativeReviewRequester` is the extension point item 12 wanted:
`flutter_store_listing_play_review` ships a `PlayReviewRequester` and you pass
it in, so the proprietary Play dependency stays out of this package and out of
F-Droid builds. No platform-interface ceremony — this package is too small to
earn it.

The iTunes lookup moves behind `PackageInfoAppIdentity` and becomes
*opt-out by supplying `appleAppId`*, rather than the unavoidable default it is
today. It also gets typed JSON handling and a cache.

---

## 3. Platform support

| | listing | native review | today |
|---|---|---|---|
| iOS | ✅ | ✅ StoreKit | both |
| Android | ✅ | via `NativeReviewRequester` | listing only |
| macOS | ✅ | ✅ `AppStore.requestReview(in:)` takes an `NSViewController` | **nothing** |
| web / Windows / Linux | `unsupportedPlatform` | `unsupportedPlatform` | falls into the Android branch |

**macOS is a real question, not a freebie.** It needs a second native target
(SPM target, podspec, `NSViewController` plumbing) and a macOS example. It is
worth asking because AuthPass ships on macOS, so it would actually get used —
but it is the single biggest chunk of work here, and it is separable. See the
open questions.

---

## 4. Testability

The point of §2.3 and §2.5 is that after this, every branch is reachable from
`flutter test` with no device:

* platform — injected `StorePlatform`, so iOS, Android, macOS and `none` paths
  all get tests, including the ones that are currently unreachable and the
  web/desktop behaviour that is currently wrong.
* identity — a fake `AppIdentity` covers `appIdUnavailable`, which today can
  only be produced by taking the device offline.
* launcher — the existing `_RecordingLauncher` pattern in the current tests
  carries over unchanged.
* the iTunes lookup — a fake `http.Client`, so the JSON parsing and the
  empty-results path get tested instead of being exercised in production.

Target: every `StoreListingOutcome` value asserted at least once, and no test
whose result depends on what the host VM reports.

---

## 5. Migration

Complete, for both known consumers.

```dart
// AuthPass lib/main.dart:622, inside a customActions handler returning bool
- return await FlutterStoreListing().launchStoreListing();
+ return (await FlutterStoreListing().openStoreListing()).isSuccess;

// AuthPass lib/main.dart:626
- return await FlutterStoreListing().launchRequestReview(onlyNative: true);
+ return (await FlutterStoreListing()
+     .requestReview(fallback: ReviewFallback.none)).isSuccess;

// example/lib/main.dart:33
- _requestReviewSupported = await _fsl.isSupportedNativeRequestReview();
+ _requestReviewSupported = _fsl.isNativeReviewSupported; // no await

// example/lib/main.dart:56, 63
- await _fsl.launchStoreListing();
+ await _fsl.openStoreListing();
- await _fsl.launchRequestReview(onlyNative: true);
+ await _fsl.requestReview(fallback: ReviewFallback.none);
```

Note the behaviour change hiding in the first line: AuthPass's `launchReview`
currently opens the **write-review** page, because `iosWriteReview` defaults to
`true`. With the new default it opens the listing. If that action is meant to
be "write a review", it becomes
`openStoreListing(writeReview: true)` — worth checking which was intended,
since today the name and the behaviour disagree.

CHANGELOG will carry this table verbatim.

---

## 6. What I would not do

* **No federated platform-interface split.** `flutter_store_listing_platform_interface`
  plus per-platform packages is the right shape for something the size of
  `url_launcher`. Here it would be more boilerplate than code, and the
  `NativeReviewRequester` seam already buys the one extension point needed.
* **No `freezed` / `json_serializable`.** One JSON field (`trackId`) does not
  justify `build_runner` in a plugin's dependency tree.
* **No retry or caching policy beyond a process-lifetime memo** for the iTunes
  lookup. If you supply `appleAppId` there is no lookup at all, which is the
  real fix.
* **No change to the Swift side's behaviour**, beyond whatever macOS needs. The
  iOS native path was just reviewed and is correct: scene selection, the
  `@MainActor` hop, calling `FlutterResult` exactly once, and the iOS 16
  `AppStore.requestReview(in:)` split with the iOS 15 fallback.
* **Not fixing the unordered scene fallback** as part of this. It is real
  (`connectedScenes` is a `Set`, so with no foreground-active scene an
  arbitrary one is chosen and `true` is still reported) but it is a small
  independent Swift fix, not an API question.

---

## 7. Open questions

1. **Sequencing** — publish 1.3.0 first and then 2.0.0 (recommended), or go
   straight to 2.0.0 only? §0.
2. **macOS** — in or out? It is the largest single piece, it is separable, and
   AuthPass would use it. §3.
3. **`StoreListingOutcome` as an enum, or a sealed class** carrying the `Uri`
   that was opened or refused? The enum is simpler and `isSuccess` keeps
   migration to one word; the sealed version is more idiomatic Dart 3 and makes
   logging easier. Enum recommended unless you want the `Uri`.
4. **`appleAppId`: encourage, or require?** As designed it stays optional with
   the iTunes lookup as fallback. Requiring it would delete that network path
   entirely and make `appIdUnavailable` impossible — simpler and strictly more
   reliable, at the cost of a mandatory argument for everyone.
5. **Does `itms-apps://apps.apple.com/app/id…` actually open the App Store
   app?** Apple documented that scheme against `itunes.apple.com`. If it does
   not work with the new host, the static builders should not offer it. Needs a
   device check, which I cannot do here.
