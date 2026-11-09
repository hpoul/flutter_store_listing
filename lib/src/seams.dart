/// Opens a store listing.
///
/// Named for the job rather than the mechanism, deliberately. A
/// `Future<bool> Function(Uri)` seam shaped like `url_launcher` was the
/// obvious design while every platform went through `url_launcher`; since
/// 1.4.0 Android does not — it goes through this package's own method channel,
/// which restricts the intent's package to the Play Store app. Naming the seam
/// for the job keeps that difference, and any future change to it, out of the
/// public API.
abstract interface class StoreListingLauncher {
  /// Opens [uri] externally, reporting whether it was opened.
  ///
  /// **Implementations must not throw**; a platform refusal is `false`. The
  /// facade catches nothing, so an exception from here propagates out of
  /// [FlutterStoreListing.openStoreListing], which returns an outcome rather
  /// than throwing.
  Future<bool> openStoreListing(Uri uri);
}

/// Resolves the store id of the running app where the platform can report it.
///
/// Only Android can: with the iTunes lookup deleted in 2.0, the App Store id
/// is a configuration value rather than something to discover at runtime.
abstract interface class StoreIdentity {
  /// The running app's own Android package name.
  ///
  /// Null on platforms with no package name to report, and on a failure to
  /// read it. **Must not throw**, for the reason given on
  /// [StoreListingLauncher.openStoreListing].
  Future<String?> androidPackageName();
}

/// An in-app review prompt.
///
/// The extension point for Android in-app review: a separate package can ship
/// an implementation backed by Play's review API and you pass it to
/// [FlutterStoreListing.configure] once, so that the proprietary Play
/// dependency stays out of this package and out of F-Droid builds.
///
/// The iOS StoreKit prompt is an implementation of this interface too, not a
/// hardcoded channel call, so there is exactly one contract to honour and the
/// iOS path is reachable from a test.
abstract interface class InAppReviewPrompt {
  /// Whether a prompt can be shown right now.
  ///
  /// Asynchronous because Play's availability depends on the Play Store being
  /// installed and current, which is only knowable at runtime.
  ///
  /// **Must not throw**, and must report unavailability as `false`.
  Future<bool> isAvailable();

  /// Asks for the prompt, reporting whether the request reached the OS.
  ///
  /// A `true` means the request was accepted, **not** that a prompt appeared —
  /// neither StoreKit nor Play reports that back.
  ///
  /// **Must not throw** either: a failed request is `false`. This matters
  /// because the first implementation outside this package will wrap Play's
  /// review flow, which reports failure rather than returning cleanly, and an
  /// interface whose only expected implementation violates an unstated rule is
  /// not a contract.
  Future<bool> requestReview();
}
