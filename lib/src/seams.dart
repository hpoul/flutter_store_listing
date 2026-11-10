/// The three seams every external dependency goes through.
///
/// `@docImport` so that the `[FlutterStoreListing.…]` and `[ReviewFallback]`
/// references below resolve to links: this library deliberately has no import
/// of either, since both depend on it.
///
/// @docImport 'outcomes.dart';
/// @docImport 'store_listing.dart';
library;

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
  /// facade catches nothing, so an exception thrown here does *not* become an
  /// outcome: it propagates out of [FlutterStoreListing.openStoreListing],
  /// whose own contract is to report an outcome rather than throw. That is
  /// what makes this rule absolute rather than a preference, and why the
  /// bundled implementations each end in a bare `catch`.
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

  /// Asks for the prompt.
  ///
  /// [InAppReviewRequest.requested] means the request reached the OS, **not**
  /// that a prompt appeared — neither StoreKit nor Play reports that back.
  ///
  /// **Must not throw**: a failed request is
  /// [InAppReviewRequest.unavailable]. This matters because the first
  /// implementation outside this package will wrap Play's review flow, which
  /// reports failure rather than returning cleanly, and an interface whose only
  /// expected implementation violates an unstated rule is not a contract.
  Future<InAppReviewRequest> requestReview();
}

/// What an [InAppReviewPrompt] did with a request.
///
/// A `bool` here was not enough, which took a review round to notice. The two
/// ways a request can fail want opposite handling by the caller, and
/// [InAppReviewPrompt.isAvailable] cannot tell them apart beforehand: on iOS it
/// answers from the platform value alone, with no channel call, so it says
/// `true` on a device whose scene is inactive *and* on a host whose plugin
/// never registered.
///
/// This set is **closed**: no value will be added in a minor release.
enum InAppReviewRequest {
  /// The request reached the OS.
  requested,

  /// Nothing was shown, and nothing can be until something outside this
  /// package's view changes — on iOS, no window scene was foreground-active,
  /// which is true during the launch transition, while a system alert is up,
  /// and for a visible but unfocused iPad window.
  ///
  /// The caller's [ReviewFallback] **does not run** for this. The user did not
  /// ask to leave the app, and sending them to the store because the app was
  /// still waking up is worse than doing nothing. Ask again later.
  notNow,

  /// This prompt cannot show anything: the platform has none, or the
  /// implementation is missing or broken.
  ///
  /// The caller's [ReviewFallback] runs, which is the whole reason it exists.
  unavailable,
}
