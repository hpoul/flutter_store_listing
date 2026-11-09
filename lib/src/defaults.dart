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
      final result = await _channel.invokeMethod<String>('openStoreListing', {
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

  /// True on iOS alone.
  ///
  /// There is no channel round trip to learn this: the native side answers
  /// unconditionally on every iOS version this package supports, so asking it
  /// only cost an `await`. macOS has no prompt here yet — the native side
  /// needs a view controller rather than a window scene, which is 2.1 work.
  @override
  Future<bool> isAvailable() async => platform == StorePlatform.iOS;

  @override
  Future<bool> requestReview() async {
    try {
      // `?? false` rather than a cast: a null reply used to throw a TypeError.
      return await _channel.invokeMethod<bool>('requestReview') ?? false;
    } on MissingPluginException catch (error, stackTrace) {
      _logger.warning(
        'No native requestReview implementation; treating the prompt as '
        'unavailable so the fallback runs. Rebuild the app if this persists.',
        error,
        stackTrace,
      );
      return false;
    } on PlatformException catch (error, stackTrace) {
      _logger.severe('Unable to request a review.', error, stackTrace);
      return false;
    }
  }
}
