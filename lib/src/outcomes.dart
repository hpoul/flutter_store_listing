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

  /// This platform has a store, but no review prompt was shown — and you asked
  /// for no fallback.
  ///
  /// Three causes, which this value does not distinguish: Android with no
  /// [InAppReviewPrompt] configured; a prompt that reported itself unavailable
  /// at request time; or **a prompt that was available and refused the
  /// request**. The third is the signal 2.0 added on iOS, where StoreKit has
  /// no foreground-active scene to present into — so it is not safe to read
  /// this as "this platform will never have a prompt" and hide the row for
  /// good.
  inAppReviewUnavailable,

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
