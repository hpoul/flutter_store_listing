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

export 'src/outcomes.dart' show ReviewFallback, StoreListingOutcome;
export 'src/seams.dart'
    show InAppReviewPrompt, StoreIdentity, StoreListingLauncher;
export 'src/store_listing.dart' show FlutterStoreListing;
export 'src/store_platform.dart' show StorePlatform;
