/// The outcome and fallback enums.
///
/// The `@docImport` directives are what make `[InAppReviewPrompt]` and
/// `[FlutterStoreListing.configure]` below render as links. This library has
/// no code-level import of either — the dependency runs the other way — and
/// dartdoc resolves a reference in the enclosing library's scope only, so
/// without these the two names a migrating caller reads first would render as
/// literal square brackets on pub.dev. `comment_references` is not in
/// `flutter_lints`, so nothing warns about it.
///
/// @docImport 'seams.dart';
/// @docImport 'store_listing.dart';
library;

/// What happened when a review or store listing was requested.
///
/// Replaces the bare `bool` that every method returned up to 1.4.0, where
/// "unsupported platform", "could not resolve the store id" and "the launcher
/// refused" were indistinguishable from each other and, in one case, from
/// success.
///
/// **New values may be added in a minor release.** Adding one is a breaking
/// change by Dart's rules — a non-exhaustive `switch` *statement* over an enum
/// does not compile — so this is said plainly rather than implied to be free.
/// The alternative was freezing the set for all of 2.x, and an outcome set
/// that cannot grow is worse than one that grows with a documented escape
/// hatch. To be safe against a minor release, handle the values you care about
/// and leave an escape hatch for the rest. It is spelled differently in the
/// two switch forms:
///
/// ```dart
/// // A switch statement takes `default`.
/// switch (outcome) {
///   case StoreListingOutcome.storeListingOpened:
///     showThanks();
///   default:
///     showSorry();
/// }
///
/// // A switch expression does NOT: `default` is a compile-time error there.
/// // Use a wildcard instead.
/// final message = switch (outcome) {
///   StoreListingOutcome.storeListingOpened => 'Thanks!',
///   _ => 'Sorry.',
/// };
/// ```
enum StoreListingOutcome {
  /// The in-app review prompt was handed to the OS.
  ///
  /// The OS decides whether it is actually shown — StoreKit rate-limits it per
  /// user and per app version — and never reports back either way.
  inAppReviewRequested,

  /// An external store URL was opened.
  storeListingOpened,

  /// This platform has no app store at all. Web, Windows, Linux.
  unsupportedPlatform,

  /// This platform has a store, but no review prompt — and you asked for no
  /// fallback.
  ///
  /// Android with no [InAppReviewPrompt] configured, or a prompt that reported
  /// itself unavailable. A prompt that exists but could not be shown *right
  /// now* is [inAppReviewNotNow] instead, so this value does mean "not here",
  /// and a UI may hide the row on it.
  inAppReviewUnavailable,

  /// A prompt exists but could not be shown right now, so nothing happened.
  ///
  /// On iOS, no window scene was foreground-active — true during the launch
  /// transition, while a system alert is up, and for a visible but unfocused
  /// iPad window. **Your [ReviewFallback] deliberately did not run**: the user
  /// never asked to leave the app, and sending them to the store because the
  /// app was still waking up is worse than doing nothing.
  ///
  /// So this is the one unsuccessful outcome worth retrying unchanged. Ask
  /// again on the next launch, or after the next frame.
  inAppReviewNotNow,

  /// The store id for this platform is not known, so no URL could be built.
  ///
  /// Pass `appStoreId` to [FlutterStoreListing.configure] to rule this out on
  /// Apple platforms.
  storeIdUnavailable,

  /// A URL was built, but the platform refused to open it.
  launchRefused;

  /// Whether the user was actually taken somewhere, or a prompt requested.
  ///
  /// A member rather than an extension, so it appears in the dartdoc for this
  /// enum, survives `show:`/`hide:` imports, and cannot collide with another
  /// package's extension of the same name.
  bool get isSuccess =>
      this == inAppReviewRequested || this == storeListingOpened;
}

/// What to do when the in-app review prompt is not available.
///
/// Replaces `onlyNative`, which could express only two of these three, and did
/// not say in its name which two.
///
/// Unlike [StoreListingOutcome] this set is **closed**: three fallbacks
/// exhaust the choice, so no value will be added in a minor release.
enum ReviewFallback {
  /// Open the store's write-a-review page.
  ///
  /// Apple only — Play has no write-review deep link, so on Android this is
  /// the plain listing.
  writeReviewPage,

  /// Open the plain store listing.
  storeListing,

  /// Do nothing, and report why.
  ///
  /// [StoreListingOutcome.inAppReviewUnavailable], except on a platform that
  /// has neither a store nor a configured prompt, where there is nothing to be
  /// unavailable and the outcome is
  /// [StoreListingOutcome.unsupportedPlatform]. Switch on both, or on
  /// `isSuccess`.
  none,
}
