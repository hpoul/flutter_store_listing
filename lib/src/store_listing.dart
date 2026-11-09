import 'package:flutter/foundation.dart' show visibleForTesting;

import 'defaults.dart';
import 'outcomes.dart';
import 'seams.dart';
import 'store_platform.dart';

/// Opens an app's store listing, and asks for a review.
///
/// Use [instance] and configure it once in `main()`:
///
/// ```dart
/// void main() {
///   FlutterStoreListing.configure(appStoreId: '1479297675');
///   runApp(const MyApp());
/// }
/// ```
///
/// There is deliberately **no unnamed constructor**. Up to 1.4.0
/// `FlutterStoreListing()` was a factory returning the shared instance; a
/// generative constructor here would keep compiling for every existing caller
/// while quietly returning an object [configure] had never touched. Making it
/// a compile error instead is the point. Use [instance], or [custom] to build
/// your own.
class FlutterStoreListing {
  /// Every external dependency injectable, for tests and unusual hosts.
  ///
  /// The seams are nullable rather than defaulted because a Dart default must
  /// be a compile-time constant and [StorePlatform.current] is a getter. A
  /// value given here wins over [configure]; a null falls through to it, and
  /// then to the real implementation — resolved per call, never captured in an
  /// initializer list.
  FlutterStoreListing.custom({
    String? appStoreId,
    String? macAppStoreId,
    String? androidPackageName,
    InAppReviewPrompt? inAppReview,
    StorePlatform? platform,
    StoreIdentity? identity,
    StoreListingLauncher? launcher,
  }) : _appStoreId = appStoreId,
       _macAppStoreId = macAppStoreId,
       _androidPackageName = androidPackageName,
       _inAppReview = inAppReview,
       _platform = platform,
       _identity = identity,
       _launcher = launcher;

  /// What [instance] is made of: nothing set, everything resolved per call
  /// from whatever [configure] holds at that moment.
  FlutterStoreListing._shared() : this.custom();

  // What this particular instance was given.
  final String? _appStoreId;
  final String? _macAppStoreId;
  final String? _androidPackageName;
  final InAppReviewPrompt? _inAppReview;
  final StorePlatform? _platform;
  final StoreIdentity? _identity;
  final StoreListingLauncher? _launcher;

  // What configure() set. Static, because instance is shared.
  static String? _configuredAppStoreId;
  static String? _configuredMacAppStoreId;
  static String? _configuredAndroidPackageName;
  static InAppReviewPrompt? _configuredInAppReview;
  static StorePlatform? _configuredPlatform;
  static StoreIdentity? _configuredIdentity;
  static StoreListingLauncher? _configuredLauncher;

  /// The shared instance, so UI code can call
  /// `FlutterStoreListing.instance.requestReview()` without threading
  /// configuration through it.
  ///
  /// Configure it with [configure]; it is never replaced. Because it reads
  /// that configuration on each call rather than capturing it, a reference
  /// taken before [configure] runs — a `State` field initialiser, say — is
  /// configured afterwards all the same.
  static final FlutterStoreListing instance = FlutterStoreListing._shared();

  /// Configures [instance]. Call in `main()`.
  ///
  /// [appStoreId] is the numeric App Store id — for
  /// `https://apps.apple.com/app/id1479297675` it is `1479297675`. It is a
  /// build-time constant; there is no runtime lookup, so without it Apple
  /// platforms cannot build a URL at all. A **debug** build asserts, which
  /// throws rather than returning — the outcome is for shipped code, and a
  /// missing build-time constant is a mistake worth a red screen. A **release**
  /// build reports [StoreListingOutcome.storeIdUnavailable], because an app
  /// may legitimately run unconfigured. Both reach that assert through
  /// [requestReview] too, whose default fallback opens the listing.
  ///
  /// [macAppStoreId] defaults to [appStoreId], which is correct under
  /// universal purchase. Apps with separate iOS and Mac SKUs have two ids, and
  /// passing only [appStoreId] would otherwise send Mac users to the iOS
  /// listing.
  ///
  /// [androidPackageName] defaults to the running app's own package name.
  ///
  /// **Merges; it does not replace.** An argument left out keeps its current
  /// value, so an app's own `configure(appStoreId: …)` in `main()` and a later
  /// `configure(inAppReview: …)` from a review package compose, instead of the
  /// second wiping the ids. Nothing clears a value back to unset except
  /// [resetConfiguration]; to change one, pass the new value.
  static void configure({
    String? appStoreId,
    String? macAppStoreId,
    String? androidPackageName,
    InAppReviewPrompt? inAppReview,
    // The seams too, so that `instance` — the object every consumer actually
    // calls — is reachable from a test. Without them the per-call resolution
    // below would be the one novel part of this design with no test seam.
    StorePlatform? platform,
    StoreIdentity? identity,
    StoreListingLauncher? launcher,
  }) {
    _configuredAppStoreId = appStoreId ?? _configuredAppStoreId;
    _configuredMacAppStoreId = macAppStoreId ?? _configuredMacAppStoreId;
    _configuredAndroidPackageName =
        androidPackageName ?? _configuredAndroidPackageName;
    _configuredInAppReview = inAppReview ?? _configuredInAppReview;
    _configuredPlatform = platform ?? _configuredPlatform;
    _configuredIdentity = identity ?? _configuredIdentity;
    _configuredLauncher = launcher ?? _configuredLauncher;
  }

  /// Drops whatever [configure] set, so one test cannot leak into the next.
  @visibleForTesting
  static void resetConfiguration() {
    _configuredAppStoreId = null;
    _configuredMacAppStoreId = null;
    _configuredAndroidPackageName = null;
    _configuredInAppReview = null;
    _configuredPlatform = null;
    _configuredIdentity = null;
    _configuredLauncher = null;
  }

  // Per-call resolution: what this instance was given, else what configure()
  // holds right now, else the real implementation. Nothing is resolved in an
  // initializer list, which is the one shape that cannot work — `instance` is
  // built lazily on first touch, so an initializer list would freeze whatever
  // defaults existed at that moment and configure() could never reach it.
  StorePlatform get _effectivePlatform =>
      _platform ?? _configuredPlatform ?? StorePlatform.current;

  String? get _effectiveAppStoreId => _appStoreId ?? _configuredAppStoreId;

  /// Falls back to the App Store id, which is correct under universal
  /// purchase. The reverse default would silently send Mac users to the iOS
  /// listing.
  ///
  /// Both of this instance's own ids are consulted before either configured
  /// one, rather than chaining to [_effectiveAppStoreId] at the end. Chaining
  /// interleaved the two levels: a global `configure(macAppStoreId: 'M')` beat
  /// an instance built with `custom(appStoreId: 'B')`, so an explicit argument
  /// lost to a default the caller never asked about — which is the opposite of
  /// what [custom] documents.
  String? get _effectiveMacAppStoreId =>
      _macAppStoreId ??
      _appStoreId ??
      _configuredMacAppStoreId ??
      _configuredAppStoreId;

  String? get _effectiveAndroidPackageName =>
      _androidPackageName ?? _configuredAndroidPackageName;

  StoreIdentity get _effectiveIdentity =>
      _identity ?? _configuredIdentity ?? const PackageInfoStoreIdentity();

  StoreListingLauncher get _effectiveLauncher =>
      _launcher ??
      _configuredLauncher ??
      DefaultStoreListingLauncher(_effectivePlatform);

  /// A prompt given to [custom] wins outright, as [custom] documents. A prompt
  /// given to [configure] is *preferred* instead of substituted, because
  /// [configure] is global while a prompt is usually platform-specific: the
  /// Play-backed prompt §2.5 exists for would otherwise have displaced
  /// StoreKit on iOS for every app that ships on both stores. See
  /// [PreferredInAppReview].
  InAppReviewPrompt get _effectiveInAppReview {
    final explicit = _inAppReview;
    if (explicit != null) {
      return explicit;
    }
    final builtIn = StoreKitInAppReview(_effectivePlatform);
    final configured = _configuredInAppReview;
    if (configured == null) {
      return builtIn;
    }
    return PreferredInAppReview(preferred: configured, builtIn: builtIn);
  }

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
  bool get isStoreListingSupported => switch (_effectivePlatform) {
    StorePlatform.android => true,
    StorePlatform.iOS => _effectiveAppStoreId != null,
    StorePlatform.macOS => _effectiveMacAppStoreId != null,
    StorePlatform.unsupported => false,
  };

  /// Whether this platform can show an in-app review prompt at all.
  ///
  /// True on iOS, and on any platform where an [InAppReviewPrompt] has been
  /// configured. Whether one is available *right now* is resolved when you
  /// call [requestReview], and reported as
  /// [StoreListingOutcome.inAppReviewUnavailable].
  bool get isInAppReviewSupported {
    if ((_inAppReview ?? _configuredInAppReview) != null) {
      return true;
    }
    return _effectivePlatform == StorePlatform.iOS;
  }

  /// Asks for a review: the in-app prompt where available, otherwise
  /// [fallback].
  ///
  /// The prompt and the store listing are mutually exclusive. Up to 1.2.0 a
  /// successful prompt on iOS *also* opened the store listing, ejecting the
  /// user to the App Store straight after the in-app dialog.
  ///
  /// A [StoreListingOutcome.inAppReviewRequested] means the request reached
  /// the OS, not that a prompt appeared — StoreKit rate-limits it per user and
  /// per app version and never reports back.
  Future<StoreListingOutcome> requestReview({
    ReviewFallback fallback = ReviewFallback.writeReviewPage,
  }) async {
    final prompt = _effectiveInAppReview;
    if (await prompt.isAvailable() && await prompt.requestReview()) {
      return StoreListingOutcome.inAppReviewRequested;
    }
    switch (fallback) {
      case ReviewFallback.none:
        // Still distinguish "no store at all" from "a store but no prompt":
        // reporting the former on Android, where the listing works perfectly,
        // is the conflation this enum exists to remove.
        //
        // `isInAppReviewSupported` guards it because a prompt can be
        // configured on a platform that has no store — a web prompt, say. The
        // platform check alone then reported `unsupportedPlatform` about a
        // configuration whose own getter answered true, so the two
        // contradicted each other.
        return _effectivePlatform == StorePlatform.unsupported &&
                !isInAppReviewSupported
            ? StoreListingOutcome.unsupportedPlatform
            : StoreListingOutcome.inAppReviewUnavailable;
      case ReviewFallback.writeReviewPage:
        return await openStoreListing(writeReview: true);
      case ReviewFallback.storeListing:
        return await openStoreListing();
    }
  }

  /// Opens the app's store listing externally.
  ///
  /// [writeReview] opens the write-a-review page instead of the plain listing.
  /// It is Apple-only — Play has no write-review deep link, so on Android it
  /// is ignored. It defaults to false, inverting 1.4.0's default: a method
  /// named for the listing should open the listing.
  Future<StoreListingOutcome> openStoreListing({
    bool writeReview = false,
  }) async {
    final platform = _effectivePlatform;
    if (platform == StorePlatform.unsupported) {
      return StoreListingOutcome.unsupportedPlatform;
    }
    final uri = await storeListingUri(writeReview: writeReview);
    if (uri == null) {
      assert(
        platform == StorePlatform.android,
        'No App Store id is configured, so the store listing cannot be '
        'opened on $platform. Pass appStoreId to '
        'FlutterStoreListing.configure() in main(). Release builds report '
        'StoreListingOutcome.storeIdUnavailable instead of asserting, '
        'because an app may legitimately run unconfigured.',
      );
      return StoreListingOutcome.storeIdUnavailable;
    }
    final launched = await _effectiveLauncher.openStoreListing(uri);
    return launched
        ? StoreListingOutcome.storeListingOpened
        : StoreListingOutcome.launchRefused;
  }

  /// The URL [openStoreListing] would open.
  ///
  /// On Android that is the https `play.google.com` one: restricting the
  /// intent's package is what sends it to the Play Store app, so there is only
  /// ever one URL to describe.
  ///
  /// [writeReview] is Apple-only, as on [openStoreListing]: on Android it is
  /// ignored and the plain listing comes back.
  ///
  /// Null when this platform has no store, or the store id is unknown —
  /// [openStoreListing] distinguishes those two; this convenience for building
  /// your own UI does not.
  Future<Uri?> storeListingUri({bool writeReview = false}) async {
    final id = await storeId();
    if (id == null) {
      return null;
    }
    return switch (_effectivePlatform) {
      StorePlatform.android => playStoreWebUri(packageName: id),
      StorePlatform.iOS || StorePlatform.macOS => appStoreUri(
        appStoreId: id,
        writeReview: writeReview,
      ),
      StorePlatform.unsupported => null,
    };
  }

  /// The store id for the current platform: the App Store id on iOS, the Mac
  /// App Store id on macOS, the package name on Android, null where none
  /// applies.
  ///
  /// Asynchronous because Android's default package name needs a channel call.
  /// On Apple platforms the answer is known synchronously, but one method that
  /// always needs an `await` is a better API than two that differ only in what
  /// they can answer.
  Future<String?> storeId() async {
    switch (_effectivePlatform) {
      case StorePlatform.android:
        return _effectiveAndroidPackageName ??
            await _effectiveIdentity.androidPackageName();
      case StorePlatform.iOS:
        return _effectiveAppStoreId;
      case StorePlatform.macOS:
        return _effectiveMacAppStoreId;
      case StorePlatform.unsupported:
        return null;
    }
  }

  /// The App Store listing URL for [appStoreId], on both iOS and macOS.
  ///
  /// No storefront is pinned — the App Store redirects to the viewer's own
  /// region. Up to 1.2.0 this was the legacy `itunes.apple.com/us/app/id…`
  /// form, which held every user to the US store.
  static Uri appStoreUri({
    required String appStoreId,
    bool writeReview = false,
  }) => Uri.https(
    'apps.apple.com',
    '/app/id$appStoreId',
    writeReview ? const {'action': 'write-review'} : null,
  );

  /// The Play Store listing URL for [packageName].
  ///
  /// There is no `market://` counterpart to publish: Google no longer
  /// documents that scheme among its store-listing link formats, and this is
  /// the URL the Android implementation views with the intent's package
  /// restricted to the store app.
  static Uri playStoreWebUri({required String packageName}) =>
      Uri.https('play.google.com', '/store/apps/details', {'id': packageName});
}
