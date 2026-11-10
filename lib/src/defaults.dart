/// The implementations of the three seams that ship with this package.
///
/// @docImport 'store_listing.dart';
library;

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import 'seams.dart';
import 'store_platform.dart';

final _logger = Logger('flutter_store_listing');

const MethodChannel _channel = MethodChannel('flutter_store_listing');

/// The Play Store app's package name.
///
/// Internal in 2.0. It was briefly public in 1.4.0, but the only thing that
/// needs it is the launcher below: setting the intent's package is what sends
/// the listing to the store app, and that is this package's job rather than
/// its caller's.
const _playStorePackageName = 'com.android.vending';

/// Opens the listing the way each platform wants it opened: this package's own
/// Android channel, and `url_launcher` on Apple platforms.
///
/// Every §2.6 error mapping lives here rather than in the facade, so that the
/// facade can catch nothing at all and a caller-supplied
/// [StoreListingLauncher] that throws is not silently absorbed.
class DefaultStoreListingLauncher implements StoreListingLauncher {
  const DefaultStoreListingLauncher(this.platform);

  final StorePlatform platform;

  @override
  Future<bool> openStoreListing(Uri uri) async {
    if (platform == StorePlatform.android) {
      final native = await _openOnAndroid(uri);
      if (native != null) {
        return native;
      }
    }
    return await _openWithUrlLauncher(uri);
  }

  /// Views [uri] with the intent's package restricted to the Play Store app,
  /// which is what Google's "Linking to Google Play" guide documents and what
  /// `url_launcher` cannot express.
  ///
  /// Returns null when the native side could not answer at all, so the caller
  /// falls back to `url_launcher`; true or false when it did answer.
  Future<bool?> _openOnAndroid(Uri uri) async {
    try {
      // `Object?`, not `String`. `invokeMethod<String>` casts the reply, so a
      // native side answering with anything else — a bool, a map, a future
      // Kotlin change — throws a `TypeError` that is neither of the exceptions
      // caught below, straight out of a method whose contract forbids
      // throwing. An unrecognised reply *type* is an unrecognised reply, and
      // §2.6 says those degrade to url_launcher rather than failing. The
      // switch below already has that branch; this makes it reachable.
      final result = await _channel.invokeMethod<Object?>('openStoreListing', {
        'url': uri.toString(),
        'preferredPackage': _playStorePackageName,
      });
      switch (result) {
        // Whether the store app or something else took the URL is logged, not
        // surfaced: the user is gone either way, so a caller cannot act on the
        // difference.
        case 'storeApp':
        case 'external':
          _logger.finer(() => 'Opened the store listing via $result.');
          return true;
        case 'unavailable':
          return false;
      }
      // Null rather than false, so a version skew between Dart and the native
      // side degrades to `url_launcher` instead of showing the user nothing.
      _logger.severe('Unexpected openStoreListing result: $result');
      return null;
    } on MissingPluginException catch (error, stackTrace) {
      // Not "this platform has no store" — the channel is never called on a
      // platform that has none. It means the plugin failed to register on a
      // platform that does, typically a host that has not been rebuilt since
      // this package was upgraded. So fall back rather than report failure.
      _logger.warning(
        'No native openStoreListing implementation; falling back to '
        'url_launcher. Rebuild the app if this persists.',
        error,
        stackTrace,
      );
      return null;
    } on PlatformException catch (error, stackTrace) {
      // Deliberately *not* a route to `url_launcher`. The reachable case is
      // `no_activity`, and `url_launcher` is `ActivityAware` too and detached
      // in the same window, so its own `ensureActivity` would throw. 1.4.0
      // retried anyway and reached the same `false` by a longer route.
      _logger.severe(
        'Unable to open the store listing natively.',
        error,
        stackTrace,
      );
      return false;
    } catch (error, stackTrace) {
      // `seams.dart` states the no-throw rule absolutely, so it cannot rest on
      // having enumerated every exception type a channel can produce. Null, so
      // anything unforeseen degrades to url_launcher exactly like a reply the
      // Dart side cannot read.
      _logger.severe(
        'Unexpected error opening the store listing natively.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<bool> _openWithUrlLauncher(Uri uri) async {
    try {
      return await url_launcher.launchUrl(
        uri,
        mode: url_launcher.LaunchMode.externalApplication,
      );
    } on MissingPluginException catch (error, stackTrace) {
      // Separately from `PlatformException`, which it does *not* extend — so
      // catching only that one let this escape and broke the launcher's own
      // "must not throw" contract. Reachable on a host that has not been
      // rebuilt since `url_launcher` was added, and there is nothing further
      // to fall back to from here.
      _logger.severe(
        'No url_launcher implementation; cannot open $uri.',
        error,
        stackTrace,
      );
      return false;
    } on PlatformException catch (error, stackTrace) {
      // `launchUrl` is documented to either return false or throw, and this
      // method promises a bool. The reachable case on Android is a detached
      // activity: `url_launcher` is `ActivityAware` too.
      _logger.severe('Unable to open $uri.', error, stackTrace);
      return false;
    } catch (error, stackTrace) {
      // Nothing further to fall back to from here, so the no-throw contract is
      // the only thing left to honour. `launchUrl` also throws `ArgumentError`
      // for a scheme no handler claims, which neither clause above catches.
      _logger.severe('Unexpected error opening $uri.', error, stackTrace);
      return false;
    }
  }
}

/// Reads the running app's package name from `package_info_plus`.
class PackageInfoStoreIdentity implements StoreIdentity {
  const PackageInfoStoreIdentity();

  @override
  Future<String?> androidPackageName() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      // A closure, so the string is not built when logging is off. The call
      // itself memoizes in a static, so this is not repeated channel work.
      _logger.finer(
        () =>
            'Resolved package name ${packageInfo.packageName} '
            '(${packageInfo.appName} ${packageInfo.version}+'
            '${packageInfo.buildNumber}).',
      );
      return packageInfo.packageName;
    } catch (error, stackTrace) {
      _logger.severe('Unable to read the package name.', error, stackTrace);
      return null;
    }
  }
}

/// The iOS StoreKit review prompt, behind the same interface an Android
/// implementation would use.
class StoreKitInAppReview implements InAppReviewPrompt {
  const StoreKitInAppReview(this.platform);

  final StorePlatform platform;

  /// True on iOS and macOS.
  ///
  /// There is no channel round trip to learn this: the native side answers
  /// unconditionally on every version of either platform this package
  /// supports, so asking it only cost an `await`.
  ///
  /// macOS answers true as of 2.1, and 2.0 had already named the reason it
  /// could not: the native side needs a view controller rather than a window
  /// scene. The SDK turns out to say exactly that —
  /// `AppStore.requestReview(in:)` takes a `UIWindowScene` on iOS and an
  /// `NSViewController` on macOS. False→true is a widening, so no caller that
  /// gated UI on this breaks.
  ///
  @override
  Future<bool> isAvailable() async => supportsPlatform(platform);

  /// Whether this package ships a StoreKit prompt for [platform].
  ///
  /// Static and synchronous because [FlutterStoreListing.isInAppReviewSupported]
  /// is a synchronous getter and used to answer this with its own
  /// `platform == StorePlatform.iOS`. Two places encoded one fact, and 2.1
  /// found out the hard way: widening [isAvailable] to macOS left the getter
  /// still saying iOS, and the whole suite stayed green, because no test
  /// compared them. One source of truth, and a test below that holds the two
  /// together.
  ///
  /// A `switch` rather than two comparisons, because [StorePlatform] is closed
  /// and this is the pattern the package recommends to its own callers: if a
  /// value is ever added, this is a compile error instead of a silent `false`.
  static bool supportsPlatform(StorePlatform platform) => switch (platform) {
    StorePlatform.iOS || StorePlatform.macOS => true,
    StorePlatform.android || StorePlatform.unsupported => false,
  };

  /// The native side answers with a status string rather than a bool, so that
  /// "StoreKit took it" and "there was no scene to present in" are two
  /// answers instead of one.
  ///
  /// `Object?` and a switch, not a cast, for the reason the launcher gives: a
  /// reply this version cannot read must degrade, not throw.
  @override
  Future<InAppReviewRequest> requestReview() async {
    try {
      final result = await _channel.invokeMethod<Object?>('requestReview');
      switch (result) {
        case 'requested':
          return InAppReviewRequest.requested;
        // Two spellings, one meaning: there was nothing to present the prompt
        // in. iOS says `noActiveScene` (no foreground-active window scene),
        // macOS says `noPresenter` (no view controller, so no window).
        //
        // The iOS spelling is kept rather than unified under the neutral name,
        // because this branch has to keep reading it either way: upgrading the
        // package without rebuilding the host leaves an older compiled plugin
        // answering this newer Dart code. Accepting a value only newer native
        // code sends is safe in that direction; renaming one would make a
        // transient condition look like an unreadable reply and run the
        // fallback.
        case 'noActiveScene':
        case 'noPresenter':
          _logger.info(
            'Nothing to present a review prompt in ($result), so StoreKit was '
            'not asked. Nothing was shown and no fallback ran; ask again '
            'later.',
          );
          return InAppReviewRequest.notNow;
      }
      _logger.severe('Unexpected requestReview result: $result');
      return InAppReviewRequest.unavailable;
    } on MissingPluginException catch (error, stackTrace) {
      // Unavailable, not `notNow`: this is a host that was not rebuilt, which
      // no amount of waiting fixes, so the fallback *should* run. Telling it
      // apart from a missing scene is what the third value is for — §2.6 asks
      // for both behaviours and a bool could only express one.
      _logger.warning(
        'No native requestReview implementation; treating the prompt as '
        'unavailable so the fallback runs. Rebuild the app if this persists.',
        error,
        stackTrace,
      );
      return InAppReviewRequest.unavailable;
    } on PlatformException catch (error, stackTrace) {
      _logger.severe('Unable to request a review.', error, stackTrace);
      return InAppReviewRequest.unavailable;
    } catch (error, stackTrace) {
      _logger.severe(
        'Unexpected error requesting a review.',
        error,
        stackTrace,
      );
      return InAppReviewRequest.unavailable;
    }
  }
}

/// Tries [preferred] and keeps [builtIn] for where the preferred prompt
/// reports itself unavailable.
///
/// This exists because of what the obvious resolution order did to an app
/// shipping on both stores. `InAppReviewPrompt` is documented as the Android
/// extension point — you pass a Play-backed prompt to
/// [FlutterStoreListing.configure] once, in `main()` — but `configure` is
/// global and the platform is not a parameter of it, so that one call also
/// replaced the iOS StoreKit prompt. A Play prompt reports itself unavailable
/// on iOS, so `requestReview()` skipped StoreKit entirely and ran the
/// fallback: the user who should have seen the native rating dialog was sent
/// to the App Store write-review page instead, while
/// `isInAppReviewSupported` still answered true.
///
/// Composing rather than dispatching on the platform keeps §2.5's promise that
/// there is exactly one contract to honour, and keeps the configured prompt
/// first on every platform rather than silently ignoring it on one.
class PreferredInAppReview implements InAppReviewPrompt {
  const PreferredInAppReview({required this.preferred, required this.builtIn});

  /// The prompt passed to [FlutterStoreListing.configure].
  final InAppReviewPrompt preferred;

  /// The prompt this package ships for the running platform.
  final InAppReviewPrompt builtIn;

  @override
  Future<bool> isAvailable() async =>
      await preferred.isAvailable() || await builtIn.isAvailable();

  /// Asks whichever prompt is available, preferring [preferred].
  ///
  /// Re-asks [InAppReviewPrompt.isAvailable] rather than remembering what the
  /// facade's own availability check found: both answers are cheap — StoreKit's
  /// is a platform comparison with no channel call — and a stateless resolution
  /// cannot answer for one prompt and then request from the other.
  @override
  Future<InAppReviewRequest> requestReview() async {
    if (await preferred.isAvailable()) {
      final result = await preferred.requestReview();
      // Only [InAppReviewRequest.unavailable] hands over. A preferred prompt
      // that said "not now" has answered — retrying through a second prompt
      // would show the user two dialogs' worth of attempts for one request.
      if (result != InAppReviewRequest.unavailable) {
        return result;
      }
    }
    if (await builtIn.isAvailable()) {
      return await builtIn.requestReview();
    }
    return InAppReviewRequest.unavailable;
  }
}
