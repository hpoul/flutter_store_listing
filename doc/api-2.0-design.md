# flutter_store_listing 2.0 — API design, for review

Status: **revision 4 — nothing implemented, but implementable.** Every item
the three design reviews raised is now applied below rather than listed as an
open hole, and the four points that were genuinely the author's call have been
decided. §8 logs revision 2, §9 revision 3, §10 revision 4.

The third review found one defect that outranks everything in §9: in 2.0 as
revision 3 drew it, `FlutterStoreListing()` still compiles and silently stops
being the configured instance. Both reviewers found it independently. See §5.

The whole package is 310 lines of Dart, 72 of Swift and 188 of Kotlin, so an
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
| 1 | `_isIOS` / `_isAndroid` come from a compile-time conditional import | No test can choose a platform. **Four** existing tests reach the Android branch, only because the host is neither iOS nor Android — `macos` locally but `linux` in CI, which runs `flutter test` on `ubuntu-latest`. Revision 3 said five, and said `macos` as though it were the only case; the test file's own comments said the same until #6 |
| 2 | `if (_isIOS) … else …` | web, macOS, Windows and Linux all fall into the **Android** branch. On macOS it opens a Play Store *web* page for a macOS bundle id — live today in AuthPass, which ships on macOS |
| 3 | `getIosAppId()` does an **iTunes `/lookup` call** on every iOS `launchStoreListing()` that did not pass `forceIosAppId` | A network round trip to discover a build-time constant, and it fails offline. Worse, see 3a–3c |
| 3a | that lookup passes no `country`, so it searches the **US storefront only** | an app not published in the US gets `results: []` → `null` → permanent failure, not just an offline one |
| 3b | `http` is used in **exactly one place** (`lib/flutter_store_listing.dart:5`, `:171`) — for that lookup | every consumer of a store-listing plugin carries an HTTP client in its dependency tree |
| 3c | it passes no `entity` at all | it cannot steer the lookup towards a Mac app id, which matters the moment macOS lands (§3). Revision 3 wrote `entity=macSoftware`; **that value does not exist** — Apple documents `software`, `iPadSoftware` and `desktopSoftware`. `bundleId` is not a documented `/lookup` parameter either, so the whole call is undocumented |
| 4 | the lookup returns `String?`, and `getIosStoreListing` takes `String?` | `https://apps.apple.com/app/idnull?action=write-review` gets launched, and `true` returned |
| 5 | every method returns bare `bool` | "unsupported platform", "could not resolve the id" and "the launcher refused" are indistinguishable from each other and, in case 4, from success |
| 6 | `isSupported()` / `isSupportedNativeRequestReview()` are `Future<bool>` | a needless `await` to learn a compile-time constant, awkward in `build()`. Only the second makes a channel round trip — `isSupported()` is `return _isAndroid \|\| _isIOS;` with no channel at all, which revision 3 conflated |
| 7 | `launchStoreListing({bool iosWriteReview = true})` | a method named "open store listing" opens the **write-a-review** page by default |
| 8 | `FlutterStoreListing()` is a factory over a static built with defaults | the injection seam on `customize()` cannot configure the instance everyone actually calls |
| 9 | `_getPackageName()` eagerly interpolates four fields into a `finer` log on every call | log-string construction when logging is off. *Not* repeated channel work — `PackageInfo.fromPlatform()` memoizes in a static (verified, `package_info_plus` 10.2.2 `_fromPlatform`) |
| 10 | `getIosStoreListing(appId, {String protocol = 'https'})` | stringly-typed scheme, and `itms-apps://apps.apple.com/…` is unverified — Apple documented that scheme against the old `itunes.apple.com` host |
| 11 | `results[0]['trackId'].toString()` | on a missing field this yields the **literal string `"null"`** (verified), so `/idnull` happens by a second route that a non-null-id check can never catch |
| 12 | no seam for Android in-app review | the agreed `flutter_store_listing_play_review` package has nothing to plug into |
| 13 | `(await _channel.invokeMethod<bool>(…)) as bool` at `:85`, `:88` | a null reply throws `_TypeError` (verified) rather than returning false |
| 14 | ~~`canLaunchUrl('market://')` at `:136` gates the `market://` path~~ | **Fixed in 1.4.0**, which replaced it with the documented store intent in Kotlin. **But the reason given for it has been wrong in all three revisions, in the same direction every time** — see §10. Android makes "the app that installed your app" visible automatically, with no `<queries>` entry and whatever the `targetSdk`, so on any Play-installed device `com.android.vending` was visible and the probe was *not* filtered. Revision 3's exception list (lower `targetSdk`, `QUERY_ALL_PACKAGES`, a declared query) omits the majority case. What survives: `setPackage` is not expressible through `url_launcher`, and `market://` is gone from Google's documented *store-listing* formats — and those, not a dead branch, are why the native route won |

Items 1, 2, 3 and 5 are the ones worth redesigning for. The rest fall out.

Item 14 is the only one 1.4.0 closed. Items 2, 3, 4, 10, 11 and 13 are all
still live in the released package — the `else` branch still catches macOS,
Windows, Linux and web, and the iTunes lookup is still there.

**Corrected before 1.4.0 shipped, in #6.** Item 14's wrong premise had been
repeated in `README.md`, the 1.4.0 `CHANGELOG.md` entry, the published dartdoc
on `launchStoreListing` and `urlCanLaunch`, and a test comment. All five are
fixed, and 1.4.0 then went to pub.dev, so no consumer ever saw the wrong
explanation.

The *conclusion* in the CHANGELOG — "for most users this is the behaviour they
already had" — was right all along, and more right than the reasoning offered
for it: a Play-installed app on 1.3.0 reached `market://details?id=…`, which the
Play Store app handles, and 1.4.0 sends the https URL to that same app. Nearly
every user lands in the same place by a different route. It was the explanation,
not the behaviour, that needed correcting.

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
  /// for no fallback. Android with no [InAppReviewPrompt] configured, or a
  /// prompt that reported itself unavailable.
  inAppReviewUnavailable,

  /// A prompt exists but could not be shown right now, so nothing happened
  /// and the `ReviewFallback` deliberately did not run. On iOS: no
  /// foreground-active window scene. The one failure worth retrying
  /// unchanged. Added in §11 — see "The fallback no longer runs for a
  /// transient failure".
  inAppReviewNotNow,

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

**Decided: new values may arrive in minor versions — and that is a breaking
change by Dart's own rules, stated rather than glossed.** A non-exhaustive
switch *statement* over an enum is a compile-time error
(`non_exhaustive_switch_statement`), so a seventh outcome in 2.1 stops a
consumer who switched exhaustively from compiling, and a dartdoc note does not
make that minor. The real choice is between freezing the set for all of 2.x and
accepting that a consumer pinning `^2.0.0` can be broken by a minor. This takes
the second, because an outcome set that cannot grow is worse than one that
grows with a documented escape hatch — but the CHANGELOG says so in those
words instead of implying the additions are free.

**The escape hatch has two forms, and revision 3 gave the one that does not
always work.** `default` is valid in a switch *statement*; in a switch
*expression* it is an error — `default_in_switch_expression`, "A switch
expression may not use the `default` keyword. Try replacing `default` with
`_`." Both diagnostics above were confirmed by running `dart analyze` over a
probe, not recalled. So the dartdoc and the CHANGELOG give both: a `default`
clause in a statement, a wildcard `_` case in an expression. Revision 3's
advice would have been a syntax error in the construct consumers increasingly
write.

**The policy has to cover all three enums.** Revision 3 said `ReviewFallback`
"is an input, so it has no such problem": Dart's exhaustiveness error does not
care which way a value flows, and a consumer switching over a persisted
`ReviewFallback` — a settings radio group, a log formatter — breaks
identically. Direction changes the likelihood, not the breakage. Both
`ReviewFallback` and `StorePlatform` are nonetheless **closed**: three
fallbacks exhaust the choice, and §5 tells the example to
`switch (StorePlatform.current)`, so growing that one would break the very
pattern this document recommends. If a desktop store ever justifies a
`StorePlatform` value, it is a major.

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
  // No unnamed constructor, deliberately. In 1.4.0 `FlutterStoreListing()` is
  // a factory returning the shared instance; a generative one here would keep
  // compiling for every existing caller and quietly stop being configured.
  // See §5, first silent breakage. Use `instance`, or `.custom` to build your
  // own. The private one is what `instance` is made from.
  FlutterStoreListing._shared();

  /// The shared instance, so UI code can call
  /// `FlutterStoreListing.instance.requestReview()` without threading
  /// configuration through it.
  ///
  /// Configure it with [configure]; it is never replaced.
  static final FlutterStoreListing instance = FlutterStoreListing._shared();

  /// Configures [instance]. Call in `main()`.
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
  ///
  /// [instance] reads this configuration on each call rather than capturing it,
  /// so a reference taken before this runs — a `State` field initialiser, say —
  /// is configured afterwards all the same.
  ///
  /// **Merges; it does not replace.** An argument left out keeps its current
  /// value, so an app's own `configure(appStoreId: …)` in `main()` and a later
  /// `configure(inAppReview: PlayInAppReviewPrompt())` compose, instead of the
  /// second wiping the ids and landing back on
  /// [StoreListingOutcome.storeIdUnavailable]. Nothing clears a value back to
  /// unset except [resetConfiguration]; to change one, pass the new value.
  static void configure({
    String? appStoreId,
    String? macAppStoreId,
    String? androidPackageName,
    InAppReviewPrompt? inAppReview,
    // The seams too, so that `instance` — the object every consumer actually
    // calls — is reachable from a test. Without them §4's promise holds only
    // for `.custom`, and the per-call resolution below would be the one novel
    // part of this design with no test seam at all.
    StorePlatform? platform,
    StoreIdentity? identity,
    StoreListingLauncher? launcher,
  });

  /// Drops whatever [configure] set, so one test cannot leak into the next.
  @visibleForTesting
  static void resetConfiguration();

  /// Every external dependency injectable, for tests and unusual hosts.
  ///
  /// The seams are nullable rather than defaulted because a Dart default must
  /// be a compile-time constant, and `StorePlatform.current` is a getter. A
  /// value given here wins over [configure]; a null falls through to it, and
  /// then to the real implementation — resolved per call, never in an
  /// initializer list.
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
  /// app" row on this getter does not render one that does nothing.
  ///
  /// On Android it assumes the package name resolves, which it does for the
  /// default [StoreIdentity]. That assumption is the one gap in a synchronous
  /// answer: a [StoreIdentity] reporting null — which the interface permits —
  /// would still give [StoreListingOutcome.storeIdUnavailable] from
  /// [openStoreListing] while this getter said true.
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
  /// [writeReview] is Apple-only: Play has no write-review deep link, so on
  /// Android it is ignored and the plain listing comes back. The same is true
  /// of [openStoreListing], and both doc comments say so, because these are
  /// the two places a caller looks.
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

  **The mechanism, spelled out, because revision 3 asserted the behaviour and
  then described one that contradicts it.** Its `.custom` doc comment said each
  null is "resolved to the real implementation in the initializer list", which
  is the single shape that cannot work: a `_shared()` instance is built lazily
  on first touch, so an initializer list would freeze whatever defaults existed
  at that moment and `configure()` could never reach it. An implementer taking
  the obvious reading — final fields — would have reintroduced exactly the
  capture-before-`configure()` bug this bullet says is impossible.

  So: every configurable value is a nullable field, and every read goes through
  an accessor that resolves at call time.

  ```dart
  final String? _appStoreId;             // what this instance was given
  static String? _configuredAppStoreId;  // what configure() set

  String? get _effectiveAppStoreId => _appStoreId ?? _configuredAppStoreId;

  StoreListingLauncher get _effectiveLauncher =>
      _launcher ??
      _configuredLauncher ??
      _defaultLauncherFor(_effectivePlatform);
  ```

  `.custom` still behaves as advertised — a value it was given wins, because it
  is the left operand — and `instance` simply has nulls in every field.

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
  `url_launcher` cannot express. `market://` is gone from Google's documented
  *store-listing* formats, so there is no builder to publish for it — and a
  published `Uri` builder is API that cannot be withdrawn. It is not gone from
  the guide altogether: `market://launch?id=…` is still documented for Play
  Instant, which this package does not do. `README.md` draws that line
  correctly; revision 3 said "documented link formats" and overshot.
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

  /// Must not throw either: a failed request is
  /// `InAppReviewRequest.unavailable`. A `requested` means the request reached
  /// the OS, not that a prompt appeared — neither StoreKit nor Play reports
  /// that back.
  Future<InAppReviewRequest> requestReview();
}

/// Three states, not a bool: the two ways a request can fail want opposite
/// handling, and `isAvailable()` cannot tell them apart beforehand. Added in
/// §11.
enum InAppReviewRequest { requested, notNow, unavailable }
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

`InAppReviewPrompt` is the extension point item 12 wanted: a
`flutter_store_listing_play_review` package *would* ship a
`PlayInAppReviewPrompt` that you pass to `FlutterStoreListing.configure()`
once, so the proprietary Play dependency stays out of this package and out of
F-Droid builds. **No such package is published** — `pubspec.yaml` says so in as
many words, and tells us not to point users at one — so both this document and
the committed dartdoc describe the seam instead of naming a package that does
not exist.

**Its contract says implementations must not throw**, because the first
implementor will be that package and Play's review flow reports failure rather
than returning cleanly — an interface whose only expected implementation
violates an unstated rule is not a contract. (Revision 3 said Play's
`ReviewManager` "does throw"; that it throws *synchronously* is not confirmed
from Google's documentation, which surfaces failure through a `Task`. The
contract does not depend on which way it fails.)

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
  window, so its own `ensureActivity` throws. **This is a change to the Dart
  dispatch, not a mapping of it.** 1.4.0 catches `PlatformException`
  wholesale, returns null, and the caller *does* then call `urlLaunch` — which
  throws and is caught, so the outcome is the same `false` by a longer route.
  2.0 has to tell `MissingPluginException` (fall back) from `PlatformException`
  (do not). The Kotlin comment there used to assert that the Dart side already
  distinguishes them — the second comment in that file to claim a Dart
  behaviour that was not present — and #6 corrected it to describe the retry
  that actually happens, so the code now documents the gap 2.0 closes rather
  than denying it.
* `MissingPluginException` → **not** `unsupportedPlatform`. Revision 2 had this
  backwards. Once the platform is a value the channel is never called on a
  platform that has no store, so this exception can only mean the plugin failed
  to register on a platform that *does* — typically a host that has not been
  rebuilt since the package was upgraded. Reporting "this platform has no app
  store at all" about an iPhone is false, and it suppresses the store-listing
  fallback that would still have worked. So: from the review prompt it means
  the prompt is unavailable and the `ReviewFallback` runs; from the launcher it
  falls back to url_launcher. **1.4.0 behaves this way for the launcher only**,
  though revision 3 claimed both: `_invokeRequestReview()` has no `try`/`catch`
  at all, so a `MissingPluginException` from the review channel propagates out
  of `launchRequestReview()` today and no fallback runs. The review-prompt half
  is new work in 2.0, not a description of what already happens.
* `invokeMethod<bool>` returning null → false, not a `_TypeError` (item 13).
* An unrecognised reply from the native side falls back rather than reporting
  failure, so a version skew between Dart and native degrades instead of
  showing the user nothing.
* `InAppReviewPrompt.isAvailable()` false, or `requestReview()` returning
  `unavailable` → the `ReviewFallback` runs, and under `ReviewFallback.none`
  the outcome is `inAppReviewUnavailable`. **`requestReview()` returning
  `notNow` runs no fallback at all** and reports `inAppReviewNotNow`; §11
  explains why this needed a third value rather than the `false` revision 4
  specified here.
* **Which layer catches all of this: the bundled implementations, not the
  facade.** Every mapping above is the documented behaviour of the
  `StoreKitInAppReview` and the default `StoreListingLauncher` that ship in
  this package. The facade itself catches nothing, so a *caller-supplied*
  `StoreListingLauncher` or `InAppReviewPrompt` that throws propagates out of
  `requestReview()` — which is the other half of why both contracts say
  implementations must not throw. Revision 3 put both rules in one list without
  saying they apply at different layers, and they read as a flat contradiction:
  an implementer would either wrap the facade in `try`/`catch`, violating the
  rule below, or honour it and ship an outcome-returning API that throws on the
  single most likely third-party failure.

---

## 3. Platform support

| | listing | in-app review | in 1.4.0 |
|---|---|---|---|
| iOS | ✅ | ✅ StoreKit | both |
| Android | ✅ native store intent | via `InAppReviewPrompt` | listing only, natively since 1.4.0 |
| macOS | ✅ **in 2.0** | deferred to 2.1 | **nothing** — still falls into the Android branch |
| web / Windows / Linux | `unsupportedPlatform` | `unsupportedPlatform` | still falls into the Android branch |

**macOS splits in two, and the halves have very different costs.**

The **listing** is nearly free: the same `apps.apple.com/app/id…` URL, no
native code, and `StorePlatform.macOS` is already in the enum. It also fixes a
live bug in AuthPass, which today opens a Google Play web page on macOS. **In
for 2.0.**

**One unverified premise here is load-bearing.** *(Checked after 2.0 merged;
it holds — see the three paragraphs below, kept separate so the decision reads
as it was made.)* That `url_launcher` hands that
URL to the Mac App Store *app* is not confirmed from Apple documentation —
`url_launcher_macos` opens through `NSWorkspace`, which goes to the default
https handler, i.e. a browser, unless the store app claims the domain. Check it
on a Mac before implementing. If it opens a browser, macOS support is still
worth shipping — a web listing beats a Google Play page for a Mac bundle id —
but "nearly free" and one `appStoreUri()` serving both Apple platforms are what
need revisiting, not the decision itself.

**Verified on 2026-11-10, after 2.0 merged — macOS 27.0.1, Flutter 3.47.9.**
The premise holds: it opens the Mac App Store *app*. The example app's
`requestReview()` reported `storeListingOpened` and the store came forward
with the **Write a Review** sheet over the *Mac* listing for `id1478552452` —
not a browser, and not the iOS SKU. So "nearly free" and one `appStoreUri()`
serving both Apple platforms stand, and nothing above needs revisiting.

**But it wins as a universal link, not as the default handler, and that
distinction has teeth.** `NSWorkspace`'s `urlForApplication(toOpen:)` — the
call behind `canLaunchUrl` — answers **Google Chrome** for the very same URL
on the same machine. The paragraph above was right about the mechanism and
wrong only about the conclusion: universal-link routing inside
`NSWorkspace.open` overrides the scheme's default handler. Anyone who tries to
re-confirm this with `canLaunchUrl` will be told "a browser" and conclude the
opposite. §2.6's choice not to gate on `canLaunchUrl` is load-bearing on macOS
for a reason it did not know it had.

**The sandbox is why this needed a Flutter app and not just a probe.** A
command-line tool calling `NSWorkspace.open` is unsandboxed; a Flutter macOS
app ships with `com.apple.security.app-sandbox`, and brokered LaunchServices
routing was the plausible way for this to differ in the real app. It does not:
the sandboxed example routes to the store app exactly as the probe did.
`example/macos` exists now so this stays reproducible, and 2.1's native prompt
needs a macOS example regardless.

The **native prompt** needs a second SPM target, a podspec platform, an
`NSViewController` instead of a `UIWindowScene`, and a macOS example.
Separable, and adding it later is non-breaking —
`isInAppReviewSupported` going false→true on macOS in 2.1 breaks nobody.
**Deferred.**

**Done in 2.1, and the list above was right about the hard part.**
`AppStore.requestReview(in:)` takes a `UIWindowScene` on iOS and an
`NSViewController` on macOS — the macOS SDK's own `StoreKit.swiftinterface`
states exactly that, so the reason given here for deferring was the real one.
The macOS example built for the verification above is what it presents into.

Two items were cheaper than estimated. The "second SPM target" is not a second
target at all: `sharedDarwinSource: true` points both platform entries at one
`darwin/` tree, so `ios/` was renamed and the two platforms now differ in a
handful of `#if os(macOS)` blocks. And the macOS 12 floor is kept rather than
raised —
the modern API needs macOS 13, so below that the prompt falls back to the
no-argument `SKStoreReviewController.requestReview()`, exactly as iOS 15 falls
back to the scene-taking one.

One cost this did not foresee, and it was not in the native code at all:
`isInAppReviewSupported` kept its own copy of the platform list, so teaching
the prompt about macOS left the capability getter still saying iOS, with the
whole suite green. §12 records it.

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

That holds for `instance` as well as for `.custom`, but only because §2.4's
`configure()` carries the three seams. Without them, the per-call resolution —
the novel part of this design, and the code path every consumer runs — would be
the one thing no test could drive, because `instance` would always take
`StorePlatform.current` from the host. Revision 3's `configure()` had only the
four configuration values, so §4's promise covered everything except the part
most likely to be got wrong.

What stays out of reach of `flutter test`, by nature: the Swift and Kotlin
sources themselves. Those keep their own tests — the Android module already has
11 under Robolectric as of 1.4.0 — and the Dart suite covers the mapping from
their replies, not the replies.

---

## 5. Migration

Complete for both known consumers, and for this repository. Revision 3 claimed
"complete" and was missing public API anyway; the renames table's baseline is
now **1.4.0**, which is how a member added in 1.4.0 came to be overlooked.

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

**There are three silent breakages, not one.** Revision 2 claimed one, revision
3 found a second and congratulated itself in those terms, and the third — found
independently by both reviewers of revision 3 — is the worst of them.

**1. `FlutterStoreListing()` would silently stop being the configured
instance.** Today it is a `factory` returning the shared `_instance`
(`lib/flutter_store_listing.dart:31`). Revision 3's §2.4 made the unnamed
constructor *generative*, with every argument optional and named — so
`FlutterStoreListing()` would still compile, still analyse clean, and hand back
a fresh instance that `configure()` had never touched. A consumer who migrated
mechanically, doing the renames the compiler forces and leaving the
construction alone, would lose every configured value: `storeIdUnavailable` on
Apple platforms, and an `InAppReviewPrompt` simply absent on Android, which the
§2.4 assert does not cover. Every migration snippet in this section changes
that line, and it is the load-bearing one.

> **Decided: 2.0 publishes no unnamed constructor.** `.instance` for the shared
> one, `.custom` to build your own. That turns this from a silent breakage into
> a compile error, which is the only reason the other two are tolerable. A
> `@Deprecated` unnamed constructor was the alternative and is worse: it still
> compiles, so the failure still reaches a user, just with a warning nobody
> reads in a release build.

**2. `appStoreId` must be configured.** Missing it is a runtime
`storeIdUnavailable`, not a compile error, because the iTunes lookup AuthPass
relies on today is gone. Verify the id before migrating. A debug-mode `assert`
on the Apple path (§2.4) closes most of this gap — release builds still report
the outcome, because an app may legitimately run unconfigured, but nobody
discovers it in production first.

**3. Desktop and web flip from `true` to false.** On macOS, Windows, Linux and
web, `launchStoreListing()` today returns `true` after opening a Google Play
web page. In 2.0 those platforms report `unsupportedPlatform`, so the same call
site flips to `isSuccess == false`. That is the bug in item 2 being fixed, but a
caller that branches on the result sees the change without a compile error —
and AuthPass ships on macOS.

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
  edit. Ten of its twelve tests construct through `customize(…)` and two
  through the `FlutterStoreListing()` factory (`:126`, `:132`) — which §2.4
  removes, so those two change shape rather than just names. Seven string
  assertions become `Uri` assertions: three on builder output (`:46`, `:53`,
  `:60`) and four on what the recording launcher was handed (`:84`, `:102`,
  `:116`, `:159`). Revision 3 said "every test" and "the two that assert URL
  strings"; the point of this bullet is to size the rewrite, so the numbers
  matter.
* **`lib/src/platform_os_web.dart:8-10`** carries dartdoc referencing
  `[FlutterStoreListing.isSupported]`,
  `[FlutterStoreListing.isSupportedNativeRequestReview]`, `launchRequestReview`
  and `launchStoreListing`. All four names go away, leaving dangling references
  in a file revision 3 never mentioned; `platform_os_io.dart` needs the same
  read.
* **`example/lib/main.dart:60`** uses a bare collection-`if`. The rewrite is
  the moment to make it a spread block, per this project's control-flow rule —
  `flutter analyze` never reports the collection form, so it will not be caught
  for us.
* **`test/flutter_store_listing_test.dart:51`** asserts the `itms-apps://`
  form, which §7 lists as unverified. 2.0 has no scheme parameter, so the
  assertion goes with it rather than being ported.

### Renames at a glance

| 1.4.0 | 2.0.0 |
|---|---|
| `FlutterStoreListing()` — a `factory` returning the shared instance | `FlutterStoreListing.instance`. **No unnamed constructor is published**, so this is a compile error rather than the silent breakage described above |
| `FlutterStoreListing.customize(…)` | `FlutterStoreListing.custom(…)` |
| `forceIosAppId` — a constructor argument **and** a public final field | `appStoreId`, an argument only; no public field reads it back |
| `forceAndroidPackageName` — likewise a public final field | `androidPackageName`, likewise argument-only |
| `isSupported()` | `isStoreListingSupported` (sync) |
| `isSupportedNativeRequestReview()` | `isInAppReviewSupported` (sync) |
| `launchStoreListing({iosWriteReview})` | `openStoreListing({writeReview})`, default flipped |
| `launchRequestReview({onlyNative})` | `requestReview({fallback})` |
| `getIosAppId()`, `getAndroidPackageName()` | `storeId()` |
| `getIosStoreListing()`, `getAndroidStoreListing()` | `appStoreUri()`, `playStoreWebUri()` (static, `Uri`) |
| `urlCanLaunch`, `defaultUrlCanLaunch` | — (unused since 1.4.0, removed) |
| `urlLaunch`, `defaultUrlLaunch` | `StoreListingLauncher` |
| `playStorePackageName` — public `static const`, added in 1.4.0 and advertised in its CHANGELOG as "exposed for callers building their own intents" | — removed. The package name moves inside the default `StoreListingLauncher`, the only thing that needs it |
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
foreground-active scene, do not claim success.

**Revision 4 said "return false so the fallback runs", and §11 reverses the
second half of that.** The scene check reports `noActiveScene` now, which Dart
maps to `inAppReviewNotNow` and runs *no* fallback. Everything below about the
CHANGELOG consequence is superseded by §11.

**It is one line of code** — deleting `?? scenes.first` — not the three
revision 2 estimated, plus two doc comments the deletion makes wrong:
`activeWindowScene()`'s "otherwise any connected window scene"
(`FlutterStoreListingPlugin.swift:64-66`) and `requestReview`'s "Reports
`false` only when there is no window scene to present in" (`:27-30`). Both
describe the behaviour being removed.

It also has a user-visible consequence that belongs in the CHANGELOG rather
than in a list of internal fixes: with no foreground-active scene, iOS now runs
the `ReviewFallback`, so the default behaviour sends the user to the App Store
write-review page where 1.4.0 showed them nothing at all. §2.6 carries the
mapping that makes that work.

And since §6 deletes the `isSupportedRequestReview` channel case,
`StoreKitInAppReview.isAvailable()` answers from the platform value and the iOS
version alone — true on iOS, false elsewhere — leaving scene availability to
`requestReview()`, which is the only place it can honestly be known.

* **No change to the Android *Kotlin* implementation.** It shipped in 1.4.0,
  was reviewed, and the two-attempt intent is exactly what 2.0 needs behind
  `StoreListingLauncher`. The Dart side is more than a reply mapping, though,
  which is what revision 3 said: §2.6 requires `no_activity` to stop routing to
  url_launcher, so `MissingPluginException` and `PlatformException` have to be
  caught separately instead of both returning null. Small, but it is a
  behaviour change rather than a translation, and the Kotlin comment there now
  describes the retry rather than denying it (#6), so the two will agree.

---

## 7. Open questions

**None left.** All four resolved across revisions 2 and 3.

**Resolved:** whether `itms-apps://apps.apple.com/app/id…` opens the App Store
app was listed as needing a device. It does not need one, because the design
had already answered it: `appStoreUri()` takes no scheme parameter, so 2.0
never emits `itms-apps://` and there is nothing to verify. What survives is a
cleanup — `test/flutter_store_listing_test.dart:51` asserts the `itms-apps`
form today, so that scheme is "tested" without ever having been verified, which
is how it survived this long. The assertion goes with the parameter.

Revision 3 also added "The https URL opens the App Store app on iOS
regardless", which both reviewers flagged as asserted without a source. It is
withdrawn rather than defended, because the resolution above rests on the
parameter's absence and does not need it. The same question for **macOS** is
live and load-bearing — see §3.

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

---

## 10. Review log — what changed in revision 4

Revision 3 went to two independent reviewers at once: one on the document's
internal consistency and whether the API is sound as drawn, one fact-checking
every claim against the 1.4.0 code and primary platform documentation. Both
read the whole document without seeing the other's work.

**They found the same top defect independently**, which is the strongest signal
in either report.

### The one that changes the API

**`FlutterStoreListing()` would have stopped being the configured instance,
silently.** Today it is a `factory` returning the shared instance; revision 3
turned the unnamed constructor generative with all-optional arguments, so it
kept compiling and started returning an unconfigured object. A consumer doing
only the renames the compiler forces would have shipped
`storeIdUnavailable` on Apple and a missing `InAppReviewPrompt` on Android.
**2.0 now publishes no unnamed constructor at all** (§5), which converts it to
a compile error. This is the third silent breakage in a section that claimed
one, then two.

### Wrong as designed

* **The per-call configuration mechanism did not exist, and the one described
  contradicted it.** `.custom`'s doc comment said nulls resolve "in the
  initializer list" — the single shape under which `configure()` can never
  reach `instance`. An implementer would have used final fields and
  reintroduced the capture bug §2.4 says is impossible. §2.4 now gives the
  accessor pattern in code.
* **`configure()` did not say whether it merges or replaces**, and §2.5's own
  Play wiring is a second `configure()` call. Under replace, it would have
  wiped the ids. Now specified as merge.
* **`configure()` exposed no seams**, so nothing could test `instance` — the
  object every consumer calls, running the one novel path. It now takes all
  three (§2.4, §4).
* **§2.6's mappings and its "nothing else is caught" rule contradicted each
  other** for a third-party prompt throwing `MissingPluginException`, which is
  that seam's most likely failure. Split by layer: bundled implementations map,
  the facade catches nothing.
* **`isStoreListingSupported` was still not honest on Android** — finding B
  from revision 3 was only half fixed. The assumption is now in the doc
  comment, not only in the rationale.
* **The enum-evolution advice was a syntax error** in switch *expressions*,
  where `default` is not permitted (`default_in_switch_expression` — confirmed
  by running the analyzer, not recalled). Both forms are now given, the policy
  covers all three enums, and adding a value is named as breaking rather than
  implied to be free.

### Claims that were wrong

Six of these, which is the fourth such round in this work. The pattern is
stable: the structural decisions survive review; the confident sentences around
them do not.

* **Item 14's premise is wrong for the third time, in the same direction.**
  Android makes "the app that installed your app" automatically visible, so on
  any Play-installed device the `market://` probe was *not* filtered and the
  branch was not dead. Revision 1 was too broad, revision 3 narrowed it and
  still omitted the majority case. The same reasoning had been shipped in
  `README.md`, the 1.4.0 `CHANGELOG.md`, the published dartdoc and a test
  comment; **#6 corrected all of them before 1.4.0 went to pub.dev**, so no
  consumer saw it. The CHANGELOG's conclusion was right and its explanation
  was not.
* **"1.4.0 already behaves this way" for `MissingPluginException`** — true of
  the launcher, false of the review prompt, which has no `try`/`catch` at all.
  The claim would have cost an implementer the handler 2.0 needs.
* **`no_activity` is a Dart-side change, not a mapping** — 1.4.0 does route it
  to url_launcher. §6's "the only Dart-side change" was wrong, and a Kotlin
  comment asserts the behaviour that is not there.
* **`entity=macSoftware` does not exist** (item 3c). Apple documents
  `software`, `iPadSoftware`, `desktopSoftware`.
* **`isSupported()` makes no channel call** (item 6) — it is a pure expression.
* **"Five tests" was four, and "the test VM says `macos`"** is true locally
  only; CI runs `flutter test` on `ubuntu-latest`.
* **"`market://` is not in Google's documented link formats"** overshot:
  `market://launch?id=…` is still documented for Play Instant. The README had
  this right and the design doc did not.
* **§5's sizing of the test rewrite** was wrong in both numbers.

### Now marked unverified instead of asserted

* **That `url_launcher` hands `apps.apple.com` to the Mac App Store app** (§3).
  `NSWorkspace` goes to the default https handler. This is load-bearing for
  "nearly free" and for one `appStoreUri()` serving both Apple platforms, so it
  needs a Mac before implementing — though not before deciding. **Verified
  2026-11-10 and it holds** (§3): the store app claims the domain, so
  `NSWorkspace.open` routes there by universal link even though
  `urlForApplication(toOpen:)` names a browser. It shipped unverified, which
  was the right call — but it shipped *right*, and that is luck, not method.
* **That the https URL opens the App Store app on iOS** (§7) — withdrawn, since
  nothing rests on it.
* **That Play's `ReviewManager` throws synchronously** (§2.5) — the contract
  does not depend on it.

### Also applied

* The committed dartdoc no longer names `flutter_store_listing_play_review`,
  which does not exist and which `pubspec.yaml` tells us not to point users at
  (§2.1, §2.5).
* `playStorePackageName`, `defaultUrlLaunch`, the `FlutterStoreListing()`
  factory and the two public `force…` *fields* were missing from the renames
  table, which §5 commits to the CHANGELOG verbatim. The table's baseline is
  now 1.4.0 rather than 1.3.0 — the reason a member added in 1.4.0 was missed.
* `lib/src/platform_os_web.dart`'s dartdoc references four removed names (§5).
* `writeReview` is documented as Apple-only on both methods that take it (§2.4).
* The Swift fix invalidates two doc comments, and
  `StoreKitInAppReview.isAvailable()` gets a defined answer (§6).

### Rejected

* **That §5's `example/lib/main.dart` line numbers had drifted.** Checked
  against the file: `:22`, `:28`, `:29`, `:30`, `:31`, `:33`, `:56` and `:63`
  are all correct as written. The second reviewer independently confirmed them.
* **That the per-call facade is "not implementable as written".** It is
  implementable; what was missing was the mechanism, now supplied. The
  conclusion was overstated, the underlying observation was right, and acting
  only on the latter is why §2.4 gained code rather than a caveat.

## 11. Review log — the implementation

Two reviewers read the implementation branch, one on runtime correctness and
one on whether the tests and the documented claims hold. 19 findings. The
pattern from the design rounds repeated exactly: the structural decisions
survived — outcomes, the platform as a value, the deleted iTunes lookup, no
unnamed constructor, per-call resolution — and the confident sentences around
them did not.

### §2.5 was wrong about precedence, and the code followed it

**`configure(inAppReview: …)` replaced the iOS prompt instead of being
preferred over it.** This section documents that seam as *the* Android
extension point and tells an app to wire a Play-backed prompt in with one
global call in `main()`. `configure` has no platform parameter, so that call
also took effect on iOS — where a Play prompt reports itself unavailable, so
`requestReview()` skipped StoreKit entirely and ran the fallback. An app
shipping on both stores, following this document exactly, would have sent its
iOS users to the App Store write-review page instead of showing the native
rating dialog, while `isInAppReviewSupported` still answered `true`.

The implementation now **prefers** a configured prompt rather than substituting
it: `PreferredInAppReview` asks it first on every platform and keeps this
package's own prompt behind it. A prompt passed to `custom()` still wins
outright, which is what §2.4 promises. This is the one place where the
implementation deliberately departs from the merged design, and it departs in
order to make §2.5's own instruction correct.

### Two cross-level resolution bugs

* **A global `macAppStoreId` beat an instance's own `appStoreId`.** The Mac
  fallback chained to the *effective* App Store id, so the two levels
  interleaved and an explicit `custom(appStoreId:)` lost to a `configure()`
  default it never asked about. Both instance ids are now consulted before
  either configured one.
* **`ReviewFallback.none` reported `unsupportedPlatform` where
  `isInAppReviewSupported` said `true`.** A prompt configured on a platform
  with no store — web — made the two answers contradict each other. The
  platform is now blamed only when there is no prompt to blame instead, which
  keeps the original intent for the case it was written for.

### The no-throw contract was aspirational in three places

`seams.dart` states it absolutely, so it cannot rest on having enumerated the
exception types a channel can produce. `invokeMethod<String>` *casts*, so a
native side replying with anything but a string threw a `TypeError` past both
clauses and out of a method §2.6 says degrades on an unrecognised reply — an
unrecognised reply *type* being an unrecognised reply. That call now takes
`Object?`, and each bundled implementation ends in a bare `catch`.

### Tests that could not fail

* **No test put macOS through the URL switch.** Changing its arm to
  `playStoreWebUri` passed all 54 tests — the suite could not detect the
  defect 2.0 exists to fix. Verified by making that mutation: it now fails
  three tests.
* **`resetConfiguration clears it` was host-dependent**, the one test in the
  file breaking §4's own rule. Reset clears the platform too, so the read fell
  through to the host: on the `linux` CI runner every id is null whether or not
  reset cleared it, so it passed on a reset that did nothing, while catching a
  real failure on a macOS developer machine.
* **The `configure()` merge test's prompt assertion passed under replace
  semantics**, because `isInAppReviewSupported` was true from the platform as
  well as the prompt.
* `resolveStorePlatform` — the original bug's own site — had no test at all.
  It now takes the OS name so the mapping can be asserted.

### Documentation that described other behaviour

* `inAppReviewUnavailable` listed two causes and omitted the third, which is
  the one 2.0 added: a prompt that was available and *refused*. Reading it as
  "no prompt here, ever" and hiding the row for good was the natural mistake.
* `ReviewFallback.none` promised `inAppReviewUnavailable` where the code
  returns `unsupportedPlatform`, and a passing test asserted the code.
* The launcher contract contradicted itself inside one sentence: "an exception
  propagates out of `openStoreListing`, which returns an outcome rather than
  throwing".
* `configure`'s "report `storeIdUnavailable` — and assert" cannot both happen.
  Debug throws; release reports.
* **Every `[…]` reference in `outcomes.dart` and `seams.dart` rendered as
  literal brackets**, because neither library imports the facade and dartdoc
  resolves in the enclosing library's scope only. `comment_references` is not
  in `flutter_lints`, so nothing warned. Fixed with `@docImport`.

### §3's macOS claim, narrowed again

`pubspec.yaml` declares no `macos` platform, so pub.dev badges this package
Android and iOS while the README advertised macOS support. Checked against
Flutter's own plugin documentation rather than assumed: `dartPluginClass` is
for federated implementations that subclass a platform interface and carry a
`registerWith()`, which this package is not, and `pluginClass: none` is not
documented at all. Declaring macOS therefore means shipping a `macos/`
directory, which belongs with the native macOS prompt in 2.1. The runtime
behaviour is fine — the macOS path is `url_launcher` only — so this is a
documentation fix, and README and CHANGELOG now say so.

**Resolved in 2.1**, and the conclusion held: the platform was declared once
there was native code to register, which is the prompt. The one correction is
the shape — `sharedDarwinSource: true` means the `macos/` directory this
paragraph anticipated is a shared `darwin/` one, and `ios/` moved into it
rather than a second tree appearing beside it. pub.dev now badges macOS
because the package really does implement it.

### Not taken

* **That a transient `.foregroundInactive` scene should not run the fallback**
  was raised for decision rather than applied, because it changes the design
  rather than the code's fidelity to it. It was then decided and applied — see
  below.
* **That the debug `assert` escaping `requestReview()` is a defect.** It is
  deliberate and documented: a missing build-time constant is worth a red
  screen in debug, and release builds report the outcome. Only the wording
  claiming both happen at once was wrong.

### Rejected

* Nothing. Every finding either held or was a design disagreement recorded
  above — the first round of this project where no claim was simply wrong.

### The fallback no longer runs for a transient failure

Decided after the review, and it reverses half of §6 and a bullet of §2.6.

**The problem.** §6 made the Swift scene check honest: with no
foreground-active scene, stop claiming a prompt was shown. §2.6 then routed
that `false` into the `ReviewFallback`, and §6 accepted the consequence in
writing — "the default behaviour sends the user to the App Store write-review
page where 1.4.0 showed them nothing at all". But a scene is not
foreground-active during the launch transition, while a system alert is up, or
for a visible but unfocused iPad window. So an app asking for a review from a
post-frame callback after a launch-count threshold — a common pattern — could
eject the user to the App Store **with no interaction at all**. That is worse
than the nothing 1.4.0 did, and it is a worse failure than the one §6 set out
to fix.

**Why a `bool` could not carry it.** The obvious fix is to use the two signals
already in the interface: fall back when `isAvailable()` is false, and report
rather than substitute when an available prompt returns false. That does not
work, because `StoreKitInAppReview.isAvailable()` answers from the platform
value alone — §6 deliberately deleted the channel round trip that used to ask —
so it says `true` both on a device whose scene is inactive and on a host whose
plugin never registered. Those two want opposite handling, and §2.6 explicitly
asks for both: `MissingPluginException` "means the prompt is unavailable and
the `ReviewFallback` runs", which is right, because no amount of waiting fixes
a host that was not rebuilt.

So the third state has to come from the prompt itself.

**What changed.**

* `InAppReviewPrompt.requestReview()` returns `InAppReviewRequest`
  — `requested`, `notNow`, `unavailable` — instead of `bool`. A closed enum:
  three states exhaust it.
* The native side answers `"requested"` or `"noActiveScene"` instead of a
  bool, which is also how the launcher channel already reports.
* `StoreListingOutcome.inAppReviewNotNow` is new, and is the only unsuccessful
  outcome worth retrying unchanged. `inAppReviewUnavailable` goes back to
  meaning "not here", so a UI may hide a row on it — which the review had just
  flagged as unsafe, and now is safe again.
* `requestReview`'s `fallback` runs for `unavailable` and not for `notNow`,
  whichever fallback was asked for.
* `PreferredInAppReview` hands over to the built-in prompt only on
  `unavailable`. A preferred prompt that said "not now" has answered; retrying
  through a second prompt would turn one request from the caller into two
  attempts at the user, and on iOS both would be looking at the same inactive
  scene.

**What this costs.** A seventh value in an enum documented as open to new
values, and a seam signature that is harder to implement than
`Future<bool>`. Both land before 2.0.0 is published, so neither is breaking.
The seam is also the honest shape: the first implementation outside this
package wraps Play's review flow, which distinguishes "the quota is exhausted
right now" from "Play is not installed" — the same distinction, arrived at from
the other platform.

## 12. 2.1 — the macOS review prompt

§3 deferred this with a list of what it would cost, and the list was accurate
about the hard part: `AppStore.requestReview(in:)` takes a `UIWindowScene` on
iOS and an `NSViewController` on macOS. That is not inferred — it is what the
macOS SDK's `StoreKit.swiftinterface` declares, and it is the whole reason the
prompt could not simply follow the listing in 2.0.

### What shipped

* **One Darwin source tree.** `sharedDarwinSource: true` on both Apple
  platform entries, so `ios/` became `darwin/` and both resolve one podspec,
  one `Package.swift` and one Swift file. The estimate said "a second SPM
  target"; there is none. The platforms differ across five `#if os(macOS)`
  blocks in that one file, which is where both halves of each difference are
  readable at once.
* **macOS 12 is still the floor.** `AppStore.requestReview(in:)` needs macOS
  13, so below it the prompt falls back to the no-argument
  `SKStoreReviewController.requestReview()` — deprecated at macOS 15, and the
  pre-scene API that has no presenter parameter at all. Structurally identical
  to the iOS 15 fallback.
* **A `noPresenter` reply**, meaning no visible window to present into,
  mapping to `inAppReviewUnavailable` so the fallback runs. It is *not* the
  analogue of `noActiveScene`, though the first draft of this section called
  it one — see the review round below.

### The bug this turned up, which was not in the native code

**`isInAppReviewSupported` kept its own copy of the platform list.** The
capability getter is synchronous and `InAppReviewPrompt.isAvailable()` is not,
so the two cannot be the same member — and the fact that this package has a
StoreKit prompt on exactly iOS was written down in both. Widening the prompt
to macOS left the getter returning `platform == StorePlatform.iOS`, so a macOS
app would have reported no in-app review while the prompt behind it worked.

Every test passed. 73 of them, including ones that assert the getter's value
and ones that assert the prompt's availability — and not one that compared the
two, because nothing had ever made them disagree.

The fix is `StoreKitInAppReview.supportsPlatform`, which both now call, plus a
test that walks `StorePlatform.values` and holds the getter and the prompt to
the same answer. That second test is a tautology while the getter delegates,
which is precisely what it is for: it fails the moment someone writes the
comparison out again.

**The general shape is worth naming**, because §11 has two of these already: a
fact stated in two places stays consistent only until one of them is edited,
and a suite that tests both places independently cannot see the drift. Tests
of agreement are a different category from tests of value, and this package
now has one.

### Verified, and not

Verified on macOS 27.0.1 with Flutter 3.47.9: the plugin compiles for
`arm64-apple-macos12.0` from `darwin/` with no warnings, the generated
registrant registers `FlutterStoreListingPlugin` on macOS, and the example
app — whose "Request review (native only)" button is gated on
`isInAppReviewSupported` — now renders that button on macOS where 2.0 hid it.

Pressing that button with `ReviewFallback.none`, so that nothing could stand
in for the native path, reported `inAppReviewRequested`.

**And StoreKit drew the dialog** — *"Enjoying flutter_store_listing_example?
Click a star to rate it on the App Store"*, five stars and a *Not Now*, over
the app's own window. This paragraph predicted the opposite before anyone
pressed the button: it said a locally built Mac app is not an App Store
installation, so an absent prompt would prove nothing. The reasoning was
sound and the premise was simply untested — a debug build signed to run
locally gets the dialog.

**Still not verified, and not verifiable: that any particular user sees it.**
StoreKit rate-limits per user and per app version and never reports back, so
`inAppReviewRequested` still means the request reached the OS and nothing
more. What changed is that the macOS path has now been watched working end to
end rather than inferred from a return value.

### Review round — three reviewers, and one decision reversed

Read on three axes: the Swift and the native reply contract, the Dart and the
documented claims, and the packaging. The pattern from §10 and §11 held for a
third time — the structure survived and the confident sentences around it did
not.

**`noPresenter` was mapped to the wrong outcome, and the argument for it was
refuted by this package's own README.** The first draft reasoned by analogy
with iOS: nothing to present in, so `inAppReviewNotNow`, so no fallback,
because "a store page is no more showable than a dialog when there is nowhere
to show it."

That last clause is false here, and §3 of this document is what proves it. The
macOS listing opens in the Mac App Store **app**, through `NSWorkspace` — a
separate process, which needs no window in the calling app at all. The
fallback works perfectly on a host that has no window.

So the draft would have made 2.1 a **regression** for exactly the hosts it
claimed to be helping. A status-item app, or any Mac app whose window has been
closed while it keeps running, got the write-review sheet on 2.0. On the draft
2.1 it would have got nothing, and gone on getting nothing, since such an app
need never grow a window. The release was described as a pure widening; for
those hosts it was not.

It is `inAppReviewUnavailable` now. Worth naming the error precisely, because
it is not a slip: the analogy to iOS was carried across without re-checking
whether its premise held on the other platform, and the premise — that the
fallback needs a window — was never true on macOS. §3 had already established
that, in this same document.

**The guard was also checking the wrong thing.** `registrar.viewController` is
nil only for a headless engine; it stays non-nil for a window that is closed,
hidden or minimised. So the draft would have presented into an invisible
window and reported success — which is precisely the iOS bug that §11 caught
and that `activeWindowScene()` exists to prevent, reintroduced on the other
platform by an author who had just read the comment explaining it. The macOS
guard now requires a visible window, and the macOS 12 path goes through the
same guard, so the two macOS branches answer the same question.

**Three comments argued for their code with false mechanisms.**

* The retain-cycle note claimed holding the registrar forms a cycle through
  the engine, accepted as a cost. `FlutterEngineRegistrar` holds its engine
  *weakly*, so there was never a cycle.
* Both legacy helpers claimed that an `@available(…, deprecated:)` marking is
  what silences the deprecation warning, "because an availability check alone
  does not". The opposite is true: the `else` branch of an `#available` check
  narrows the availability context to below the checked version, where the
  symbol is not yet deprecated. Verified at four deployment targets — the two
  floors and two raised past the deprecation — and the helpers were doing
  nothing in all four. They are gone and the calls are inlined.

Each of those comments was confident, specific, and wrong, which is the
failure mode this document keeps recording: the code was right and the
explanation attached to it was invented.

**"The platforms differ in a single `#if os(macOS)`"** appeared in five
places. There are five such blocks. Nobody counted.

**A test asserted nothing.** The "still reads the iOS spelling" case passed a
`StorePlatform` the code under test never reads, so it duplicated the iOS test
beside it; its stated scenario — an unrebuilt *macOS* host answering
`noActiveScene` — is impossible, because 2.0 shipped no macOS native code at
all. Deleted.

**And the one that is this section's own lesson repeating.** That
`noPresenter` maps to `unavailable` was asserted in one test, and that
`unavailable` runs the fallback in another; nothing drove the facade on macOS
through the real prompt to the channel. The same "asserted separately, never
together" shape that hid the capability-getter bug, in the code written to fix
it. There is now a test for the whole path, and it is the one that would have
caught the mapping error.
