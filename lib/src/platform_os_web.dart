/// The web counterpart of `platform_os_io.dart`, which exists so that
/// `lib/flutter_store_listing.dart` need not import `dart:io`
/// unconditionally. That import is what made the whole package report as
/// WebAssembly-incompatible.
///
/// Returns a value rather than throwing. `'web'` is neither `ios` nor
/// `android`, so it degrades the way the callers already expect:
/// [FlutterStoreListing.isSupported] and
/// [FlutterStoreListing.isSupportedNativeRequestReview] report `false`, and
/// `launchRequestReview`/`launchStoreListing` take their non-iOS branch
/// without ever touching the iOS-only method channel. Throwing here would
/// instead turn a supported-platform check into a crash.
String get operatingSystem => 'web';
