/// Opens an app's App Store or Play Store listing, and asks for a review —
/// the native in-app prompt where there is one, the store's write-a-review
/// page otherwise.
///
/// Start with [FlutterStoreListing.instance], configured once in `main()`:
///
/// ```dart
/// void main() {
///   FlutterStoreListing.configure(appStoreId: '1479297675');
///   runApp(const MyApp());
/// }
/// ```
///
/// Then, from a settings row:
///
/// ```dart
/// final outcome = await FlutterStoreListing.instance.requestReview();
/// if (!outcome.isSuccess) {
///   // outcome says which of the several reasons it was.
/// }
/// ```
library;

// The bundled seam implementations, so that a consumer can *decorate* the
// default behaviour — log a launch, confirm before leaving the app, dispatch
// a prompt per platform — instead of reimplementing the Android store intent
// to get at it. Leaving them unexported made the one documented extension
// point unusable without copying library-private code, and made this
// package's own tests import `src/`.
export 'src/defaults.dart'
    show
        DefaultStoreListingLauncher,
        PackageInfoStoreIdentity,
        PreferredInAppReview,
        StoreKitInAppReview;
export 'src/outcomes.dart' show ReviewFallback, StoreListingOutcome;
export 'src/seams.dart'
    show
        InAppReviewPrompt,
        InAppReviewRequest,
        StoreIdentity,
        StoreListingLauncher;
export 'src/store_listing.dart' show FlutterStoreListing;
export 'src/store_platform.dart' show StorePlatform;
