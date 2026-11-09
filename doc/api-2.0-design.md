# flutter_store_listing 2.0 — API design, for review

Status: **proposal, nothing implemented. Not yet implementable — see §9.**
Revision 2, after an independent design review. §8 logs what changed and why.
§9 lists what a second review found still wrong in revision 2; those are not
yet fixed in the design below.

The whole package is 190 lines of Dart plus 68 of Swift, so an overhaul is
cheap. The expensive part is the public API, because it is published, so this
document is about getting that right before any code moves.

---

## 0. Sequencing

1.3.0 exists to unblock AuthPass, it is reviewed, and CI is green on it. An API
overhaul is a breaking change and therefore 2.0.0.

**Decided: 1.3.0 ships first.** PR #3 is the 1.3.0 release and carries none of
this; 2.0.0 is separate work on top of it. The reason is that AuthPass is
blocked on the `package_info_plus` widening *now*, and coupling that to an API
redesign would make AuthPass rewrite its call sites for a change it has no
stake in.

---

## 1. What is actually wrong today

Not style. Each of these has a concrete failure or a concrete cost. Verified
against the code on `modernize-1.3.0`.

| # | Problem | Consequence |
|---|---|---|
| 1 | `_isIOS` / `_isAndroid` come from a compile-time conditional import | No test can choose a platform. Five existing tests reach the Android branch only because the test VM says `macos` |
| 2 | `if (_isIOS) … else …` | web, macOS, Windows and Linux all fall into the **Android** branch. On macOS it opens a Play Store *web* page for a macOS bundle id — live today in AuthPass, which ships on macOS |
| 3 | `getIosAppId()` does an **iTunes `/lookup` call** on every iOS `launchStoreListing()` | A network round trip to discover a build-time constant, and it fails offline. Worse, see 3a–3c |
| 3a | that lookup passes no `country`, so it searches the **US storefront only** | an app not published in the US gets `results: []` → `null` → permanent failure, not just an offline one |
| 3b | `http` is used in **exactly one place** (`lib/flutter_store_listing.dart:5`, `:171`) — for that lookup | every consumer of a store-listing plugin carries an HTTP client in its dependency tree |
| 3c | it has no `entity=macSoftware` | it cannot resolve a Mac app id at all, which matters the moment macOS lands (§3) |
| 4 | the lookup returns `String?`, and `getIosStoreListing` takes `String?` | `https://apps.apple.com/app/idnull?action=write-review` gets launched, and `true` returned |
| 5 | every method returns bare `bool` | "unsupported platform", "could not resolve the id" and "the launcher refused" are indistinguishable from each other and, in case 4, from success |
| 6 | `isSupported()` / `isSupportedNativeRequestReview()` are `Future<bool>` | an `await` and a method-channel round trip to learn a compile-time constant. Awkward in `build()` |
| 7 | `launchStoreListing({bool iosWriteReview = true})` | a method named "open store listing" opens the **write-a-review** page by default |
| 8 | `FlutterStoreListing()` is a factory over a static built with defaults | the injection seam on `customize()` cannot configure the instance everyone actually calls |
| 9 | `_getPackageName()` eagerly interpolates four fields into a `finer` log on every call | log-string construction when logging is off. *Not* repeated channel work — `PackageInfo.fromPlatform()` memoizes in a static (verified, `package_info_plus` 10.2.2 `_fromPlatform`) |
| 10 | `getIosStoreListing(appId, {String protocol = 'https'})` | stringly-typed scheme, and `itms-apps://apps.apple.com/…` is unverified — Apple documented that scheme against the old `itunes.apple.com` host |
| 11 | `results[0]['trackId'].toString()` | on a missing field this yields the **literal string `"null"`** (verified), so `/idnull` happens by a second route that a non-null-id check can never catch |
| 12 | no seam for Android in-app review | the agreed `flutter_store_listing_play_review` package has nothing to plug into |
| 13 | `(await _channel.invokeMethod<bool>(…)) as bool` at `:85`, `:88` | a null reply throws `_TypeError` (verified) rather than returning false |
| 14 | `canLaunchUrl('market://')` at `:136` gates the `market://` path | url_launcher requires a `<queries>` manifest entry for this, "otherwise it will return false in most cases starting on Android 11". This package ships **no `android/` directory** and the example manifest has **no `<queries>`** (verified) — so the `market://` branch is dead by default, and the README documents a path that does not run |

Items 1, 2, 3 and 5 are the ones worth redesigning for. The rest fall out.

---

## 2. Proposed API

### 2.1 Outcomes instead of `bool`

```dart
/// What happened when a review or store listing was requested.
enum StoreListingOutcome {
  /// The in-app review prompt was handed to the OS. The OS decides whether it
  /// is actually shown, and never reports back.
  inAppReviewRequested,

  /// An external store URL was opened.
  storeListingOpened,

  /// This platform has no app store at all. Web, Windows, Linux.
  unsupportedPlatform,

  /// This platform has a store, but no in-app review prompt — and you asked
  /// for no fallback. Android without `flutter_store_listing_play_review`, or
  /// a prompt that reported itself unavailable at request time.
  inAppReviewUnavailable,

  /// The store id for this platform is not known, so no URL could be built.
  /// Pass `appStoreId` to rule this out on Apple platforms.
  storeIdUnavailable,

  /// A URL was built, but the platform refused to open it.
  launchRefused;

  /// Whether the user was actually taken somewhere, or a prompt requested.
  bool get isSuccess =>
      this == inAppReviewRequested || this == storeListingOpened;
}
```

`isSuccess` is a member, not an extension: it shows up in dartdoc on the enum
page, survives `show:`/`hide:` imports, and cannot collide with another
package's extension of the same name.

`inAppReviewUnavailable` is separate from `unsupportedPlatform` deliberately.
Reporting "this platform has no app store" on Android — where the store listing
works perfectly — would reintroduce exactly the conflation item 5 exists to
remove, and it is the path both known consumers take.

**One accepted lock-in:** returning a bare enum means the opened `Uri` can
never be added without another major. The alternative is a small wrapper class
(`share_plus` does this with `ShareResult(raw, status)`). Taking the enum,
because `storeListingUri` already hands callers the `Uri` when they want it.

### 2.2 Review fallback instead of `onlyNative`

```dart
/// What to do when the in-app review prompt is not available.
enum ReviewFallback {
  /// Open the store's write-a-review page. Apple only — Play has no
  /// write-review deep link, so on Android this is the plain listing.
  writeReviewPage,

  /// Open the plain store listing.
  storeListing,

  /// Do nothing, and report [StoreListingOutcome.inAppReviewUnavailable].
  none,
}
```

`onlyNative: true` becomes `ReviewFallback.none`; `onlyNative: false` becomes
`ReviewFallback.writeReviewPage`. The boolean could only express two of these
three, and which two was not evident from the name.

### 2.3 The platform, as a value rather than a global

```dart
/// The platforms this package distinguishes.
enum StorePlatform {
  android,
  iOS,
  macOS,

  /// Everything with no app store: web, Windows, Linux.
  unsupported;

  /// The platform the app is running on. Resolved through a conditional
  /// import so that importing this package does not pull in `dart:io`.
  static StorePlatform get current => resolveStorePlatform();
}
```

Spelled `iOS` / `macOS` to match Flutter's own `TargetPlatform` (verified in
`flutter/lib/src/foundation/platform.dart`).

This is the fix for items 1 and 2 at once: a value can be injected, and
`unsupported` makes web and desktop explicit rather than "whatever the `else`
branch does".

### 2.4 The class

```dart
class FlutterStoreListing {
  /// The normal constructor.
  ///
  /// [appStoreId] is the numeric App Store id — for
  /// `https://apps.apple.com/app/id1479297675` it is `1479297675`. It is a
  /// build-time constant; there is no runtime lookup, so without it Apple
  /// platforms report [StoreListingOutcome.storeIdUnavailable].
  ///
  /// [macAppStoreId] defaults to [appStoreId], which is correct under
  /// universal purchase. Apps with separate iOS and Mac SKUs have two ids.
  ///
  /// [androidPackageName] defaults to the running app's own package name.
  FlutterStoreListing({
    String? appStoreId,
    String? macAppStoreId,
    String? androidPackageName,
    InAppReviewPrompt? inAppReview,
  });

  /// The shared instance. Assign once in `main()` to configure the store ids
  /// and the in-app review prompt for the whole app, so that UI code can call
  /// `FlutterStoreListing.instance.requestReview()` without threading
  /// configuration through it.
  static FlutterStoreListing instance = FlutterStoreListing();

  /// Every external dependency injectable, for tests and unusual hosts.
  ///
  /// The seams are nullable rather than defaulted because a Dart default must
  /// be a compile-time constant, and `StorePlatform.current` is a getter. Each
  /// null is resolved to the real implementation in the initializer list.
  FlutterStoreListing.custom({
    String? appStoreId,
    String? macAppStoreId,
    String? androidPackageName,
    InAppReviewPrompt? inAppReview,
    StorePlatform? platform,
    StoreIdentity? identity,
    UrlLauncher? urlLauncher,
  });

  /// Whether this platform has a store listing to open.
  bool get isStoreListingSupported;

  /// Whether this platform can show an in-app review prompt at all. Whether
  /// one is available *right now* is resolved when you call [requestReview],
  /// and reported as [StoreListingOutcome.inAppReviewUnavailable].
  bool get isInAppReviewSupported;

  /// Asks for a review: the in-app prompt where available, otherwise
  /// [fallback]. The prompt and the store listing are mutually exclusive.
  Future<StoreListingOutcome> requestReview({
    ReviewFallback fallback = ReviewFallback.writeReviewPage,
  });

  /// Opens the app's store listing externally.
  Future<StoreListingOutcome> openStoreListing({bool writeReview = false});

  /// The URL [openStoreListing] would open. Null when this platform has no
  /// store, or the store id is unknown — [openStoreListing] distinguishes
  /// those two; this convenience for building your own UI does not.
  Future<Uri?> storeListingUri({bool writeReview = false});

  /// The store id for the current platform: the App Store id on Apple
  /// platforms, the package name on Android, null where neither applies.
  Future<String?> storeId();

  // Pure, static, no I/O.
  static Uri appStoreUri({required String appStoreId, bool writeReview = false});
  static Uri playStoreWebUri({required String packageName});
  static Uri playStoreAppUri({required String packageName}); // market://
}
```

Deliberate choices:

* **No iTunes lookup, and `appStoreId` stays optional.** Deleting the lookup
  removes the `http` dependency from every consumer (item 3b), the
  US-storefront failure (3a), the `"null"` string (11) and the offline
  failure. It is *not* promoted to a required argument: Android-only consumers
  would have to pass a dummy, and `storeIdUnavailable` already expresses the
  failure in the right place. **This breaks AuthPass**, which relies on the
  lookup today — see §5.
* **A configurable shared instance.** Item 8 is right that a factory over a
  static built with defaults is broken, but the fix is a shared instance you
  *can* configure, not none at all. Without it, every call site has to thread
  the `InAppReviewPrompt` in by hand, and the identity memo would have instance
  rather than process lifetime.

  **Correction, and now an open issue.** Revision 2 claimed
  "`InAppReview.instance` is the same shape". That is false, verified from
  source: `in_app_review` declares `static final InAppReview instance =
  InAppReview._();` — a private constructor and no setter. Its assignable seam
  lives one layer down on its platform-interface package and is token-guarded.
  So an *assignable* facade static has no precedent in either comparable
  package (`share_plus` is `static final` too), and a lazily-initialised
  mutable static has a real hazard: a read before assignment silently
  constructs an unconfigured default and any reference captured then stays
  stale forever, with no error. `example/lib/main.dart:22` already constructs
  in a `State` field initialiser, which is one step from exactly that. See
  item A in §9.
* **`writeReview` defaults to `false`** on `openStoreListing`, inverting
  today's default. A method named for the listing should open the listing.
  `requestReview`'s *fallback* still defaults to the write-review page.
* **`Uri`, not `String`**, which also retires `protocol: 'itms-apps'`.
* **`storeId()` replaces** `getIosAppId()` and `getAndroidPackageName()`, which
  are public today. One platform-aware method rather than two platform-specific
  ones.
* **The capability getters are synchronous**, usable directly in `build()`.

### 2.5 Seams

```dart
/// Opens a URL. Defaults to url_launcher in external-application mode.
typedef UrlLauncher = Future<bool> Function(Uri url);

/// Resolves the store id of the running app where the platform can report it.
abstract interface class StoreIdentity {
  /// Null on platforms with no package name to report.
  Future<String?> androidPackageName();
}

/// An in-app review prompt.
abstract interface class InAppReviewPrompt {
  /// Asynchronous because Play's availability depends on the Play Store being
  /// installed and current, which is only knowable at runtime.
  Future<bool> isAvailable();

  Future<bool> requestReview();
}
```

`InAppReviewPrompt` is the extension point item 12 wanted:
`flutter_store_listing_play_review` ships a `PlayInAppReviewPrompt` and you
assign it once via `FlutterStoreListing.instance`, so the proprietary Play
dependency stays out of this package and out of F-Droid builds.

`StoreIdentity` shrank to one method, because with the lookup gone the App
Store id is simply a constructor argument. `UrlLauncher` is one function rather
than a pair, because the `canLaunchUrl` probe goes away (item 14).

### 2.6 Errors

An outcome-returning API that also throws platform exceptions is the worst of
both, so this is settled explicitly:

* `launchUrl` returning false, or throwing `PlatformException` → `launchRefused`.
* `MissingPluginException` from the method channel → `unsupportedPlatform`.
* `invokeMethod<bool>` returning null → false, not a `_TypeError` (item 13).
* Nothing else is caught. A bug in a caller-supplied `UrlLauncher` or
  `InAppReviewPrompt` propagates.

---

## 3. Platform support

| | listing | in-app review | today |
|---|---|---|---|
| iOS | ✅ | ✅ StoreKit | both |
| Android | ✅ | via `InAppReviewPrompt` | listing only |
| macOS | ✅ **in 2.0** | deferred to 2.1 | **nothing** |
| web / Windows / Linux | `unsupportedPlatform` | `unsupportedPlatform` | falls into the Android branch |

**macOS splits in two, and the halves have very different costs.**

The **listing** is nearly free: the same `apps.apple.com/app/id…` URL,
`url_launcher` hands it to the Mac App Store, no native code, and
`StorePlatform.macOS` is already in the enum. It also fixes a live bug in
AuthPass, which today opens a Google Play web page on macOS. **In for 2.0.**

The **native prompt** needs a second SPM target, a podspec platform, an
`NSViewController` instead of a `UIWindowScene`, and a macOS example.
Separable, and adding it later is non-breaking —
`isInAppReviewSupported` going false→true on macOS in 2.1 breaks nobody.
**Deferred.**

Note that macOS is not merely "iOS with a different URL host": AuthPass has
separate iOS and Mac SKUs (`id1479297675` vs `id1478552452`), so supporting the
listing at all requires `macAppStoreId` from §2.4 rather than reusing
`appStoreId`.

---

## 4. Testability

The point of §2.3 and §2.5 is that afterwards every branch is reachable from
`flutter test` with no device:

* platform — injected `StorePlatform`, so iOS, Android, macOS and
  `unsupported` all get tests, including the currently unreachable ones and the
  web/desktop behaviour that is currently wrong.
* store id — `storeIdUnavailable` becomes a one-line test instead of something
  only reproducible by taking a device offline.
* launcher — the existing `_RecordingLauncher` pattern carries over, simplified
  to one method.
* in-app review — a fake `InAppReviewPrompt` covers `inAppReviewRequested`,
  `inAppReviewUnavailable`, and each `ReviewFallback`.

Target: every `StoreListingOutcome` value asserted at least once, and no test
whose result depends on what the host VM reports.

---

## 5. Migration

Complete, for both known consumers.

### AuthPass

```dart
// lib/main.dart — ONCE, in main(). Required: without appStoreId, Apple
// platforms report storeIdUnavailable, because the iTunes lookup AuthPass
// relies on today is gone.
//
// Note the two different ids: AuthPass is not a universal purchase, so the
// Mac app has its own SKU. Both are from AuthPass's own README.
+ FlutterStoreListing.instance = FlutterStoreListing(
+   appStoreId: '1479297675',
+   macAppStoreId: '1478552452',
+ );

// lib/main.dart:622 — a customActions handler returning Future<bool>.
// Note writeReview: true — the action is a review prompt, and today's
// iosWriteReview default of true means it opens the write-review page.
// The new default is false, so this must be passed explicitly to keep behaving
// the same.
- return await FlutterStoreListing().launchStoreListing();
+ return (await FlutterStoreListing.instance
+     .openStoreListing(writeReview: true)).isSuccess;

// lib/main.dart:626
- return await FlutterStoreListing().launchRequestReview(onlyNative: true);
+ return (await FlutterStoreListing.instance
+     .requestReview(fallback: ReviewFallback.none)).isSuccess;
```

**The `appStoreId` line is the one thing in this document that breaks a
consumer silently if missed**: everything else is a compile error, that is a
runtime `storeIdUnavailable`. Verify the id before migrating.

### example/lib/main.dart

```dart
// :1, :28, :30 — the example imports dart:io and branches on Platform.isIOS,
// which contradicts the value the package now exposes.
- import 'dart:io';
- if (Platform.isIOS) { … } else if (Platform.isAndroid) { … }
+ switch (StorePlatform.current) { … }

// :29, :31 — getIosAppId() and getAndroidPackageName() are public API today
// and are replaced by one platform-aware method.
- _appId = await _fsl.getIosAppId() ?? 'app id not found';
- _appId = await _fsl.getAndroidPackageName();
+ _appId = await _fsl.storeId() ?? 'store id not found';

// :33 — no await
- _requestReviewSupported = await _fsl.isSupportedNativeRequestReview();
+ _requestReviewSupported = _fsl.isInAppReviewSupported;

// :56, :63
- await _fsl.launchStoreListing();
+ await _fsl.openStoreListing();
- await _fsl.launchRequestReview(onlyNative: true);
+ await _fsl.requestReview(fallback: ReviewFallback.none);
```

### Renames at a glance

| 1.3.0 | 2.0.0 |
|---|---|
| `FlutterStoreListing.customize(…)` | `FlutterStoreListing.custom(…)` |
| `forceIosAppId` | `appStoreId` |
| `forceAndroidPackageName` | `androidPackageName` |
| `isSupported()` | `isStoreListingSupported` (sync) |
| `isSupportedNativeRequestReview()` | `isInAppReviewSupported` (sync) |
| `launchStoreListing({iosWriteReview})` | `openStoreListing({writeReview})`, default flipped |
| `launchRequestReview({onlyNative})` | `requestReview({fallback})` |
| `getIosAppId()`, `getAndroidPackageName()` | `storeId()` |
| `getIosStoreListing()`, `getAndroidStoreListing()` | `appStoreUri()`, `playStoreWebUri()` (static, `Uri`) |
| — | `playStoreAppUri()`, `storeListingUri()` |

The CHANGELOG will carry this table and the AuthPass warning verbatim.

---

## 6. What I would not do

* **No federated platform-interface split.** The usual argument — "too small to
  earn it" — is weak, since `in_app_review` ships a platform interface at
  roughly this size. The real argument is that federation's one concrete
  benefit is automatic registration through pubspec `implements:`, and the
  `InAppReviewPrompt` seam gives that up in exchange for being wireable from
  Dart. That trade only works *because* of the configurable
  `FlutterStoreListing.instance` in §2.4; without it, federation would be the
  better design.
* **No `freezed` / `json_serializable`.** With the lookup deleted there is no
  JSON left to parse at all.
* **No retry or caching policy.** With no network call there is nothing to
  retry.
* **No change to the Swift plugin's structure.** The iOS native path was just
  reviewed: scene selection, the `@MainActor` hop, calling `FlutterResult`
  exactly once, and the iOS 16 `AppStore.requestReview(in:)` split with the iOS
  15 fallback are all correct. The `isSupportedRequestReview` channel case
  becomes dead code and gets deleted — invisible to Dart.

### One Swift behaviour fix, which I previously meant to defer

`activeWindowScene()` picks `scenes.first` when no scene is
`.foregroundActive`, and `connectedScenes` is a `Set`, so that is an arbitrary
member — and `result(true)` is reported for a prompt presented into a
possibly-background scene. Shipping 2.0 with `inAppReviewRequested` still able
to lie would undercut the whole point of §2.1, so: when there is no
foreground-active scene, return false so the fallback runs. Three lines, in a
file this release already touches.

---

## 7. Open questions

Only one left. The other two resolved while writing revision 2.

1. **Does `itms-apps://apps.apple.com/app/id…` actually open the App Store
   app?** Apple documented that scheme against `itunes.apple.com`. Note that
   `test/flutter_store_listing_test.dart:51` asserts the `itms-apps` form
   today, so it is "tested" without being verified — which is how an unverified
   scheme survives review. **If it cannot be checked on a device, the static
   builder should not offer it**; a published `Uri` builder is API that cannot
   be taken back, and the https URL already opens the App Store app on iOS.

**Resolved:** `macAppStoreId` ships in 2.0. It was an open question only while
the separate-SKU case looked hypothetical. AuthPass's own README gives
`id1479297675` for iOS and `id1478552452` for the Mac App Store — different
ids, so the author's own app is the case a single `appStoreId` would silently
get wrong.

**Resolved:** the AuthPass ids above are confirmed from its README rather than
guessed, so §5's migration snippet is usable as written.

---

## 8. Review log — what changed in revision 2

An independent review of revision 1 produced eight changes. All were accepted;
three were corrections to claims revision 1 got wrong.

**Corrections to revision 1:**

* Item 9 claimed "repeated platform channel work per launch".
  `PackageInfo.fromPlatform()` memoizes in a static — verified. Only the eager
  log-string construction is real.
* Item 11 was understated. A missing `trackId` produces the literal string
  `"null"`, not `null`, so an id-not-null check cannot catch it.
* `StorePlatform.appleIos` / `appleMacos` was invented. Flutter spells these
  `iOS` and `macOS`.

**Design changes:**

* The iTunes lookup is **deleted**, not mitigated. Revision 1 framed open
  question 4 as keep-it vs require-`appStoreId`; the review's third answer —
  optional id, no network fallback — is better than either, and the
  US-storefront failure (3a) made the lookup indefensible rather than merely
  slow.
* `FlutterStoreListing.instance` added. Revision 1's "no singleton" would have
  forced every call site to thread the `InAppReviewPrompt` through, and its
  claim that identity caching had "process lifetime" was false for
  per-call-site construction.
* `inAppReviewUnavailable` added. Revision 1 mapped `ReviewFallback.none` to
  `unsupportedPlatform`, reintroducing on Android the exact conflation item 5
  exists to remove.
* `InAppReviewPrompt.isAvailable()` is async, because Play's availability is
  only knowable at runtime.
* The `canLaunchUrl('market://')` probe is dropped (new item 14) and the
  launcher seam collapses to one function.
* Error handling (§2.6) is specified rather than left implicit.
* Naming throughout: `appStoreId`, `InAppReviewPrompt`, `StoreIdentity`,
  `playStoreWebUri`, `appStoreUri`, `StorePlatform.unsupported`, and
  `isSuccess` as an enum member rather than an extension.
* macOS split: listing in 2.0, prompt deferred. Revision 1 treated it as one
  all-or-nothing question.
* The Swift scene fix is no longer deferred (§6).
* §5's migration table was incomplete: it missed `getIosAppId` /
  `getAndroidPackageName` (public API with no replacement), the
  `customize` → `custom` rename, and the example's own `dart:io` branching.

**Not taken:** the review suggested renaming `ReviewFallback.writeReviewPage`
to `reviewPage` because Play has no write-review deep link. Kept the explicit
name and documented the Android behaviour instead — the vaguer name would hide
the asymmetry rather than explain it.

---

## 9. Unresolved — second review of revision 2

Revision 2 was reviewed again. Verdict: **ship with changes, but not ready to
implement as it stands.** The three structural decisions (outcomes instead of
`bool`, platform-as-value, deleting the lookup) were judged right and are not
in question. What follows is **not yet applied to the design above** — it is
recorded so nobody implements from a document with known holes. Full reasoning
is on PR #4 as a comment.

**Blocking — a decision the document does not contain:**

* **A. Which URL does `openStoreListing` open on Android?** §2.4 publishes both
  `playStoreWebUri()` and `playStoreAppUri()`, §2.5 drops the `canLaunchUrl`
  probe, and `storeListingUri()` is documented as "the URL `openStoreListing`
  *would* open" — singular. Nothing says which. The two have opposite failure
  modes: `market://` hard-fails on a device with no Play Store, which is
  precisely the F-Droid audience this package deliberately serves, where 1.3.0
  degraded gracefully. The https URL works everywhere and the Play app claims
  it via app links. Recommendation: use https, and **drop `playStoreAppUri()`
  from the public API** — item 14 is this document's own argument that the
  `market://` path is dead by default, so publishing a new builder for it adds
  API that cannot be withdrawn and has no caller.

**Wrong as designed:**

* **B. `isStoreListingSupported` contradicts `storeIdUnavailable`.** On iOS with
  no `appStoreId` it returns true while `openStoreListing()` returns
  `storeIdUnavailable` — so UI that gates a "Rate this app" row on the getter
  renders a row that does nothing. That is item 5's conflation reappearing one
  level up, in the API built to remove it. It is also synchronously fixable,
  *because* deleting the lookup made the id a constructor argument: on Apple
  platforms `appStoreId != null` is known at construction time.
* **C. The assignable `static instance`** — see the correction in §2.4. Needs a
  getter with a lazy default plus either `configure()` or a setter that throws
  once the default has been handed out, so the silent stale-capture becomes
  loud, and a `@visibleForTesting` reset so one test cannot leak into the next.
* **D. `MissingPluginException` → `unsupportedPlatform` is wrong** (§2.6). Once
  the platform is a value the channel is never called off Apple platforms, so
  this exception can only mean the plugin failed to register *on a platform
  that does have a store*. Reporting "this platform has no app store" about an
  iPhone, and suppressing the store-listing fallback that would still have
  worked, is backwards. Map it to the in-app-review-unavailable path so the
  `ReviewFallback` runs.
* **E. The missing id should be loud in debug.** §5 identifies this as "the one
  thing that breaks a consumer silently if missed" and then ships it. Keep
  `storeIdUnavailable` as the release-mode outcome — an app can legitimately
  run unconfigured — but add `assert(appStoreId != null, …)` on the Apple path.

**Smaller, agreed:**

* **F.** Express the built-in iOS StoreKit path as an `InAppReviewPrompt`
  implementation rather than a hardcoded channel call, or §4's "every branch
  reachable from `flutter test`" stays aspirational: `static const
  MethodChannel _channel` has no seam, so no test can reach the iOS prompt.
* **G.** State in `InAppReviewPrompt`'s contract that implementations must not
  throw and must report unavailability as `false`. The first implementor is
  `flutter_store_listing_play_review`, and Play's `ReviewManager` does throw.
* **H.** Document that `StoreListingOutcome` may gain values in minor versions
  and that consumers should keep a `default`. Dart 3 makes an exhaustive switch
  a hard error, so a seventh outcome in 2.1 would break every consumer who
  switched exhaustively — a larger lock-in than the one §2.1 accepts.
* **I.** `storeListingUri()` is `Future<Uri?>` for a job that is synchronous on
  Apple platforms once `appStoreId` is a constructor argument. Only Android's
  default package name needs I/O. A sync overload would save a `FutureBuilder`.
* **J.** The Swift scene fix is **one** line (delete `?? scenes.first`), not
  three, and it has a user-visible consequence that belongs in the CHANGELOG:
  with no foreground-active scene, iOS now runs the `ReviewFallback`, so the
  default sends the user to the App Store where 1.3.0 showed nothing.
* **K.** §7's open question is already moot — `appStoreUri()` takes no scheme
  parameter, so the design has answered "no `itms-apps://`". Close it, and
  delete the assertion at `test/flutter_store_listing_test.dart:51` that
  "tests" that unverified form.

**Four more decisions an implementer would otherwise have to invent:** which
URL `storeListingUri()` describes; whether `storeId()` returns `appStoreId` or
`macAppStoreId` on macOS; whether the iOS StoreKit path goes through the seam
(F); and how `resolveStorePlatform()` preserves 1.3.0's deliberate choice of
`dart:io`'s `operatingSystem` over `defaultTargetPlatform` — the current
`lib/src/platform_os_io.dart` documents why, and nothing in §2.3 carries that
reasoning forward.

**§5's migration is incomplete in four more places:** the example app would
demonstrate the failure mode (it constructs with no `appStoreId`, so its id
display reads "store id not found" forever on iOS, and §5 never says what
`example/lib/main.dart:22` becomes); the README's usage block and platform
table are not mentioned at all; desktop and web flip from `true` to
`isSuccess == false`, which is a *second* silent behaviour change where §5
claims one; and `test/flutter_store_listing_test.dart` is a wholesale rewrite
that §5 does not list.

**One claim from the review not verified:** it quoted an
`ArgumentError.checkNotNull(appStoreId, …)` in `in_app_review`. That line is
not in the version of `in_app_review.dart` checked here, so it is not relied
on above. The argument for loudness (E) stands on its own.
