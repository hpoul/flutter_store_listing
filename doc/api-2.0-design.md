# flutter_store_listing 2.0 — API design, for review

Status: **revision 3 — nothing implemented, but implementable.** Every item
the two design reviews raised is now applied below rather than listed as an
open hole, and the four points that were genuinely the author's call have been
decided. §8 logs revision 2; §9 logs revision 3.

The whole package is 303 lines of Dart, 72 of Swift and 183 of Kotlin, so an
overhaul is cheap. The expensive part is the public API, because it is
published, so this document is about getting that right before any code moves.

---

## 0. Sequencing

1.3.0 exists to unblock AuthPass, it is reviewed, and CI is green on it. An API
overhaul is a breaking change and therefore 2.0.0.

**Decided: 1.3.0 ships first.** PR #3 is the 1.3.0 release and carries none of
this; 2.0.0 is separate work on top of it. The reason is that AuthPass is
blocked on the `package_info_plus` widening *now*, and coupling that to an API
redesign would make AuthPass rewrite its call sites for a change it has no
stake in.

**1.4.0 then shipped the Android native implementation** (PR #5), ahead of this
design and for the same reason: it is a behaviour fix that consumers get
without rewriting anything. It changes what parts of this document have left to
decide — see §9 — and it settles the one blocking question revision 2 did not
contain, which URL Android opens. The answer is the https one, viewed with the
intent restricted to the Play Store app, and `market://` is gone.

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
| 14 | ~~`canLaunchUrl('market://')` at `:136` gates the `market://` path~~ | **Fixed in 1.4.0.** url_launcher requires a `<queries>` manifest entry for this, "otherwise it will return false in most cases starting on Android 11", and 1.3.0 shipped no `android/` directory to put one in — so for an app targeting API 30+ without its own entry the branch was dead and the README documented a path that did not run. 1.4.0 replaced it with the documented store intent in Kotlin. Note the premise was narrower than revision 1 claimed: apps on a lower `targetSdk`, apps holding `QUERY_ALL_PACKAGES` and apps declaring the query did reach `market://` |

Items 1, 2, 3 and 5 are the ones worth redesigning for. The rest fall out.

Item 14 is the only one 1.4.0 closed. Items 2, 3, 4, 10, 11 and 13 are all
still live in the published package — the `else` branch still catches macOS,
Windows, Linux and web, and the iTunes lookup is still there.

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

**Decided: new values may arrive in minor versions.** Dart 3 makes a
non-exhaustive switch on an enum a hard error, so a seventh outcome in 2.1
would break every consumer who switched exhaustively. Rather than freeze the
set for all of 2.x, the dartdoc on the enum will say that values may be added
in a minor release and that consumers should keep a `default` clause, and the
CHANGELOG will repeat it at 2.0.0. `ReviewFallback` is an input, so it has no
such problem and can be treated as closed.

**Deliberately not distinguished: which app opened the listing.** Since 1.4.0
the Android native layer reports whether the Play Store app took the URL or
something else did, and both collapse to `storeListingOpened` here. A caller
cannot act on the difference — the user is gone either way — and splitting it
would make `isSuccess` the only thing anyone reads. The native result is
logged, not surfaced.

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

**`resolveStorePlatform()` keeps reading `dart:io`'s `operatingSystem`, not
`defaultTargetPlatform`**, and the reasoning has to survive the move. It is in
`lib/src/platform_os_io.dart` today: the question being answered is "which
store, and is there a method channel on the other side", while
`defaultTargetPlatform` reports the platform Flutter is *emulating*. An app
setting `debugDefaultTargetPlatformOverride` would otherwise have this package
invoke an iOS-only method channel on Android. The conditional import also stays,
so importing this package still does not pull in `dart:io` on web — which is
what made the whole package report as WebAssembly-incompatible before 1.3.0.

### 2.4 The class

```dart
class FlutterStoreListing {
  /// The normal constructor, for an app that would rather pass configuration
  /// than set it globally.
  ///
  /// [appStoreId] is the numeric App Store id — for
  /// `https://apps.apple.com/app/id1479297675` it is `1479297675`. It is a
  /// build-time constant; there is no runtime lookup, so without it Apple
  /// platforms report [StoreListingOutcome.storeIdUnavailable] — and assert,
  /// in debug builds only.
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

  /// The shared instance, so UI code can call
  /// `FlutterStoreListing.instance.requestReview()` without threading
  /// configuration through it.
  ///
  /// Never replaced — configure what is beneath it with [configure].
  static final FlutterStoreListing instance = FlutterStoreListing._shared();

  /// Configures [instance]. Call once, in `main()`.
  ///
  /// [instance] reads this configuration on each call rather than capturing it,
  /// so a reference taken before this runs — a `State` field initialiser, say —
  /// is configured afterwards all the same. Calling it twice is allowed and the
  /// last call wins; it is global state, and pretending otherwise would only
  /// add a failure mode.
  static void configure({
    String? appStoreId,
    String? macAppStoreId,
    String? androidPackageName,
    InAppReviewPrompt? inAppReview,
  });

  /// Drops whatever [configure] set, so one test cannot leak into the next.
  @visibleForTesting
  static void resetConfiguration();

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
    StoreListingLauncher? launcher,
  });

  /// Whether this platform has a store listing *this app* can open.
  ///
  /// False on Apple platforms with no store id configured, where
  /// [openStoreListing] would report
  /// [StoreListingOutcome.storeIdUnavailable]. So UI that gates a "Rate this
  /// app" row on this getter cannot end up rendering one that does nothing.
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

  /// The URL [openStoreListing] would open. On Android that is the https
  /// `play.google.com` one: restricting the intent's package is what sends it
  /// to the Play Store app, so there is only ever one URL to describe.
  ///
  /// Null when this platform has no store, or the store id is unknown —
  /// [openStoreListing] distinguishes those two; this convenience for building
  /// your own UI does not.
  Future<Uri?> storeListingUri({bool writeReview = false});

  /// The store id for the current platform: [appStoreId] on iOS,
  /// [macAppStoreId] on macOS, the package name on Android, null where none
  /// applies.
  Future<String?> storeId();

  // Pure, static, no I/O.
  static Uri appStoreUri({required String appStoreId, bool writeReview = false});
  static Uri playStoreWebUri({required String packageName});
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
* **An immutable facade over a configurable layer — decided.** Item 8 is right
  that a factory over a static built with defaults is broken, but the fix is
  not an *assignable* static either. Revision 2 justified one by claiming
  "`InAppReview.instance` is the same shape", which is false: `in_app_review`
  declares `static final InAppReview instance = InAppReview._();` — private
  constructor, no setter — and `share_plus` is `static final` too. Their
  assignable seam lives one layer *down*, on a platform-interface package, and
  is token-guarded.

  That shape is the one taken here, in the form that fits a package with no
  federated split: `instance` is `static final` and never replaced, and
  `configure()` sets the layer it reads. The hazard this removes was
  reproduced: Dart static initialisers are lazy, so a read before an assignment
  does not throw — it silently constructs an unconfigured default, and a
  reference captured at that moment stays unconfigured forever.
  `example/lib/main.dart:22` already constructs in a `State` field initialiser,
  one ordering change from exactly that.

  Because the facade reads its configuration **per call** rather than capturing
  it, that failure cannot happen at all, which is better than the alternative
  revision 2's reviewer proposed — a setter that throws once the default has
  been handed out. There is nothing left to make loud.

* **`storeId()` on macOS returns `macAppStoreId`, falling back to
  `appStoreId` — decided.** An app with a universal purchase passes one id and
  it keeps working; an app with separate SKUs passes two and gets the right one
  per platform. The reverse default would silently send Mac users to the iOS
  listing, which is the bug `macAppStoreId` exists to prevent.

* **One async `storeListingUri()`, no sync overload — decided.** On Apple
  platforms the answer is known synchronously once `appStoreId` is a
  constructor argument, and only Android's default package name needs I/O, so a
  sync overload was on the table. Rejected: two methods that differ only in
  what they can answer is a worse API than one `await`, and the asymmetry would
  have to be explained in both doc comments forever. `storeId()` is async for
  the same reason.

* **No `playStoreAppUri()` — decided.** Revision 2 published builders for both
  the https and the `market://` URL without saying which `openStoreListing`
  used. 1.4.0 answered it: the https URL, with the intent's package restricted
  to the Play Store app, which is what Google's own guide documents and
  `url_launcher` cannot express. `market://` is not in Google's documented link
  formats any more, so there is no builder to publish for it — and a published
  `Uri` builder is API that cannot be withdrawn.
* **`writeReview` defaults to `false`** on `openStoreListing`, inverting
  today's default. A method named for the listing should open the listing.
  `requestReview`'s *fallback* still defaults to the write-review page.
* **`Uri`, not `String`**, which also retires `protocol: 'itms-apps'`.
* **`storeId()` replaces** `getIosAppId()` and `getAndroidPackageName()`, which
  are public today. One platform-aware method rather than two platform-specific
  ones.
* **The capability getters are synchronous**, usable directly in `build()`.
  `isStoreListingSupported` can be both synchronous *and* honest only because
  deleting the lookup made the App Store id a constructor argument: on Apple
  platforms `appStoreId != null` is known without I/O, and on Android the
  package name always resolves. Revision 2 had it returning true on iOS while
  `openStoreListing()` returned `storeIdUnavailable` — item 5's conflation
  reappearing one level up, inside the API built to remove it.

### 2.5 Seams

```dart
/// Opens a store listing.
abstract interface class StoreListingLauncher {
  /// Implementations must not throw; a platform refusal is `false`.
  Future<bool> openStoreListing(Uri uri);
}

/// Resolves the store id of the running app where the platform can report it.
abstract interface class StoreIdentity {
  /// Null on platforms with no package name to report.
  Future<String?> androidPackageName();
}

/// An in-app review prompt.
abstract interface class InAppReviewPrompt {
  /// Asynchronous because Play's availability depends on the Play Store being
  /// installed and current, which is only knowable at runtime.
  ///
  /// Implementations must not throw, and must report unavailability as `false`.
  Future<bool> isAvailable();

  /// Must not throw either: a failed request is `false`. A `true` means the
  /// request reached the OS, not that a prompt appeared — neither StoreKit nor
  /// Play reports that back.
  Future<bool> requestReview();
}
```

**`StoreListingLauncher` is an interface, not the `Future<bool> Function(Uri)`
typedef revision 2 proposed, and this is the one change 1.4.0 forced.** A
url_launcher-shaped seam was right while every platform went through
url_launcher. Since 1.4.0 Android does not: it goes through this package's own
method channel, which restricts the intent's package to the Play Store app and
reports back which app took the URL. Naming the seam for the *job* rather than
the mechanism keeps that difference — and any future change to it — out of the
public API entirely. The default implementation dispatches per platform:
url_launcher on Apple platforms, the native channel on Android.

**The iOS StoreKit path is an `InAppReviewPrompt` implementation too**, not a
hardcoded channel call. `static const MethodChannel _channel` has no seam, so
no test can reach the iOS prompt today and §4's "every branch reachable from
`flutter test`" would stay aspirational. A `StoreKitInAppReview` behind the
same interface the Play package implements also means there is exactly one
contract to honour rather than one interface and one special case.

`InAppReviewPrompt` is the extension point item 12 wanted:
`flutter_store_listing_play_review` ships a `PlayInAppReviewPrompt` and you
pass it to `FlutterStoreListing.configure()` once, so the proprietary Play
dependency stays out of this package and out of F-Droid builds. **Its contract
says implementations must not throw** because the first implementor is that
package and Play's `ReviewManager` does throw — an interface whose only known
implementation violates an unstated rule is not a contract.

`StoreIdentity` shrank to one method, because with the lookup gone the App
Store id is simply a constructor argument.

### 2.6 Errors

An outcome-returning API that also throws platform exceptions is the worst of
both, so this is settled explicitly:

* `launchUrl` returning false, or throwing `PlatformException` → `launchRefused`.
* The Android native launcher's replies map: `storeApp` and `external` both →
  `storeListingOpened`, `unavailable` → `launchRefused`. Its `no_activity`
  error is `launchRefused` as well, and specifically **not** a route to
  url_launcher: url_launcher is `ActivityAware` too and is detached in the same
  window, so its own `ensureActivity` throws. 1.4.0 shipped a comment claiming
  otherwise and the review caught it.
* `MissingPluginException` → **not** `unsupportedPlatform`. Revision 2 had this
  backwards. Once the platform is a value the channel is never called on a
  platform that has no store, so this exception can only mean the plugin failed
  to register on a platform that *does* — typically a host that has not been
  rebuilt since the package was upgraded. Reporting "this platform has no app
  store at all" about an iPhone is false, and it suppresses the store-listing
  fallback that would still have worked. So: from the review prompt it means
  the prompt is unavailable and the `ReviewFallback` runs; from the launcher it
  falls back to url_launcher. 1.4.0 already behaves this way.
* `invokeMethod<bool>` returning null → false, not a `_TypeError` (item 13).
* An unrecognised reply from the native side falls back rather than reporting
  failure, so a version skew between Dart and native degrades instead of
  showing the user nothing.
* Nothing else is caught. A bug in a caller-supplied `StoreListingLauncher` or
  `InAppReviewPrompt` propagates — which is the other half of why both
  contracts say implementations must not throw.

---

## 3. Platform support

| | listing | in-app review | in 1.4.0 |
|---|---|---|---|
| iOS | ✅ | ✅ StoreKit | both |
| Android | ✅ native store intent | via `InAppReviewPrompt` | listing only, natively since 1.4.0 |
| macOS | ✅ **in 2.0** | deferred to 2.1 | **nothing** — still falls into the Android branch |
| web / Windows / Linux | `unsupportedPlatform` | `unsupportedPlatform` | still falls into the Android branch |

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
* launcher — the existing `_RecordingLauncher` pattern carries over as a fake
  `StoreListingLauncher`, simplified to one method.
* in-app review — a fake `InAppReviewPrompt` covers `inAppReviewRequested`,
  `inAppReviewUnavailable`, and each `ReviewFallback`. This now includes the
  **iOS** prompt, because §2.5 puts StoreKit behind the same interface instead
  of a `static const MethodChannel` no test can reach.

Target: every `StoreListingOutcome` value asserted at least once, and no test
whose result depends on what the host VM reports.

What stays out of reach of `flutter test`, by nature: the Swift and Kotlin
sources themselves. Those keep their own tests — the Android module already has
11 under Robolectric as of 1.4.0 — and the Dart suite covers the mapping from
their replies, not the replies.

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
+ FlutterStoreListing.configure(
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
runtime `storeIdUnavailable`. Verify the id before migrating. A debug-mode
`assert` on the Apple path (§2.4) closes most of this gap — release builds
still report the outcome, because an app may legitimately run unconfigured, but
nobody discovers it in production first.

**A second silent change, which revision 2 missed while claiming there was
only one.** On macOS, Windows, Linux and web, `launchStoreListing()` today
returns `true` after opening a Google Play web page. In 2.0 those platforms
report `unsupportedPlatform`, so the same call site flips to
`isSuccess == false`. That is the bug in item 2 being fixed, but a caller that
branches on the result sees the change without a compile error — and AuthPass
ships on macOS.

### example/lib/main.dart

```dart
// :22 — the example constructs with no ids, so after the lookup is deleted its
// own id display would read "store id not found" forever on iOS: the migrated
// example would demonstrate the failure mode. It configures real ids instead,
// and uses the shared instance like any app would.
- final _fsl = FlutterStoreListing();
+ final _fsl = FlutterStoreListing.instance;   // configured in main()

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

### The rest of the repository

Revision 2 listed only the two Dart call sites. Three more things change with
the API and were not mentioned:

* **`README.md`'s usage block** calls `launchRequestReview(onlyNative: true)`
  and `launchStoreListing()`, neither of which exists in 2.0. Its platform
  table also gains macOS, and loses the "`launchRequestReview(onlyNative: true)`
  does nothing on Android" sentence in favour of
  `ReviewFallback.none`.
* **`test/flutter_store_listing_test.dart` is a wholesale rewrite**, not an
  edit. Every test constructs through `customize(…)`, and the two that assert
  URL strings become `Uri` assertions. This is not a cost — it is the point of
  §4 — but it is work the migration section should name.
* **`test/flutter_store_listing_test.dart:51`** asserts the `itms-apps://`
  form, which §7 lists as unverified. 2.0 has no scheme parameter, so the
  assertion goes with it rather than being ported.

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
| `urlCanLaunch`, `defaultUrlCanLaunch` | — (unused since 1.4.0, removed) |
| `urlLaunch` | `StoreListingLauncher` |
| — | `FlutterStoreListing.configure()`, `storeListingUri()` |

The CHANGELOG will carry this table and the AuthPass warning verbatim.

---

## 6. What I would not do

* **No federated platform-interface split.** The usual argument — "too small to
  earn it" — is weak, since `in_app_review` ships a platform interface at
  roughly this size. The real argument is that federation's one concrete
  benefit is automatic registration through pubspec `implements:`, and the
  `InAppReviewPrompt` seam gives that up in exchange for being wireable from
  Dart. That trade only works *because* `FlutterStoreListing.configure()`
  exists to wire it in one place; without it, every call site would have to
  thread the Play prompt through UI code that has no business knowing about
  Play Core, and federation would be the better design.

  Note this is also where the federated packages' own shape is borrowed
  without the packaging: §2.4's immutable facade over a configurable layer is
  exactly what `in_app_review` and `share_plus` do, minus the separate
  platform-interface package and its token guard.
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
foreground-active scene, return false so the fallback runs.

**It is one line** — deleting `?? scenes.first` — not the three revision 2
estimated. But it has a user-visible consequence that belongs in the CHANGELOG
rather than in a list of internal fixes: with no foreground-active scene, iOS
now runs the `ReviewFallback`, so the default behaviour sends the user to the
App Store write-review page where 1.4.0 showed them nothing at all.

* **No change to the Android implementation either.** It shipped in 1.4.0,
  was reviewed, and the two-attempt intent is exactly what 2.0 needs behind
  `StoreListingLauncher`. The only Dart-side change is that its reply is mapped
  to a `StoreListingOutcome` instead of a `bool`.

---

## 7. Open questions

**None left.** All four resolved across revisions 2 and 3.

**Resolved:** whether `itms-apps://apps.apple.com/app/id…` opens the App Store
app was listed as needing a device. It does not need one, because the design
had already answered it: `appStoreUri()` takes no scheme parameter, so 2.0
never emits `itms-apps://` and there is nothing to verify. The https URL opens
the App Store app on iOS regardless. What survives is a cleanup —
`test/flutter_store_listing_test.dart:51` asserts the `itms-apps` form today,
so that scheme is "tested" without ever having been verified, which is how it
survived this long. The assertion goes with the parameter.

**Resolved:** which URL Android opens, revision 2's one blocking gap. 1.4.0
answered it in code — the https URL with the intent's package restricted — and
§2.4 drops `playStoreAppUri()` accordingly.

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

## 9. Review log — what changed in revision 3

Revision 2 was reviewed again. Verdict: **ship with changes, but not ready to
implement as it stands** — one blocking gap, four things wrong as designed, six
smaller ones, four decisions left to whoever wrote the code, and four holes in
the migration. The three structural decisions (outcomes instead of `bool`,
platform-as-value, deleting the lookup) were judged right and were not in
question. Full reasoning is on PR #4 as a comment.

**All of it is applied above.** Revision 3 is the result, together with four
decisions that were the author's to make and the consequences of 1.4.0 shipping
ahead of this design.

**The four decisions, now made:**

| Question | Decision | Where |
|---|---|---|
| `storeId()` on macOS | `macAppStoreId`, falling back to `appStoreId` | §2.4 |
| The shared instance | Immutable facade, `configure()` for the layer beneath | §2.4 |
| New outcome values | Allowed in minor versions; consumers keep a `default` | §2.1 |
| `storeListingUri()` | Async only — the sync overload is rejected | §2.4 |

**Applied from the review:**

* **A — which URL Android opens**, the blocking gap. https, and
  `playStoreAppUri()` is not published. Settled in shipped code by 1.4.0; §2.4
  and §7.
* **B — `isStoreListingSupported` contradicted `storeIdUnavailable`**, so UI
  gating a "Rate this app" row on it could render one that does nothing. It now
  accounts for a missing store id, and §2.4 records why it can stay
  synchronous anyway.
* **C — the assignable `static instance`**, and the fabricated precedent that
  justified it. Replaced with the shape `in_app_review` and `share_plus`
  actually use; §2.4.
* **D — `MissingPluginException` mapped backwards.** §2.6.
* **E — a missing id broke consumers silently.** Debug assert; §2.4 and §5.
* **F — the StoreKit path had no seam**, so §4's claim was aspirational. It is
  an `InAppReviewPrompt` implementation now; §2.5.
* **G — `InAppReviewPrompt` implementations could throw**, and the first one
  will. The contract says they must not; §2.5.
* **H — a seventh outcome in 2.1 would break exhaustive switches.** §2.1.
* **I — a sync `storeListingUri()` overload.** Considered and rejected; §2.4.
* **J — the Swift fix is one line, with a CHANGELOG consequence.** §6.
* **K — §7's last open question was already moot.** §7, plus the test
  assertion that goes with it; §5.
* **The four decisions an implementer would otherwise have invented:** which
  URL `storeListingUri()` describes (§2.4), `storeId()` on macOS (§2.4),
  whether StoreKit goes through the seam (§2.5), and how
  `resolveStorePlatform()` carries forward 1.3.0's deliberate choice of
  `dart:io`'s `operatingSystem` over `defaultTargetPlatform` (§2.3).
* **§5's four migration gaps:** what `example/lib/main.dart:22` becomes and why
  the migrated example would otherwise demonstrate the failure mode; the
  README's usage block and platform table; the second silent behaviour change,
  on desktop and web; and the test file being a wholesale rewrite.

**What 1.4.0 changed about this document:**

* Item 14 is fixed, and its premise was narrower than revision 1 claimed — the
  `market://` branch was dead only for apps targeting API 30+ without a
  `<queries>` entry of their own (§1).
* **The launcher seam is an interface, not a url_launcher-shaped typedef**
  (§2.5). This is the one place where shipping 1.4.0 first changed the design
  rather than confirming it: Android no longer goes through url_launcher at
  all, so a `Future<bool> Function(Uri)` seam would have baked one platform's
  mechanism into the public API.
* §2.6 gains the native launcher's result and error mapping, including why
  `no_activity` is not a route to url_launcher.
* §2.1 records that `storeApp` and `external` deliberately collapse into one
  outcome, which only became a question once something could tell them apart.
* §3's table and §6 both assumed Android had no native code.

**One claim from the review of revision 2, still not verified:** it quoted an
`ArgumentError.checkNotNull(appStoreId, …)` in `in_app_review`. That line is
not in the version of `in_app_review.dart` checked here, so nothing above rests
on it. The argument for the debug assert (E) stands on its own.
