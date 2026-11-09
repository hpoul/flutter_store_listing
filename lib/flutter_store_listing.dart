import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as default_url_launcher;
import 'package:url_launcher/url_launcher_string.dart';

// Not `dart:io` directly: importing it here unconditionally is what made the
// whole package report as WebAssembly-incompatible. The io branch still uses
// `dart:io`.
import 'src/platform_os_io.dart'
    if (dart.library.js_interop) 'src/platform_os_web.dart';

final _logger = Logger('flutter_store_listing');

bool get _isIOS => operatingSystem == 'ios';

bool get _isAndroid => operatingSystem == 'android';

class FlutterStoreListing {
  FlutterStoreListing.customize({
    this.forceIosAppId,
    this.forceAndroidPackageName,
    this.urlCanLaunch = defaultUrlCanLaunch,
    this.urlLaunch = defaultUrlLaunch,
  });

  factory FlutterStoreListing() => _instance;

  /// Allows overriding of the App Store App ID.
  /// for example for https://apps.apple.com/app/id1479297675 this would be
  /// `1479297675`. If not given, will try to resolve it through the
  /// bundle identifier.
  final String? forceIosAppId;

  /// Override android package, if null it will be retrieved from the current
  /// apk package.
  final String? forceAndroidPackageName;

  static Future<bool> defaultUrlCanLaunch(String url) async =>
      await default_url_launcher.canLaunchUrl(Uri.parse(url));

  static Future<bool> defaultUrlLaunch(String url) async =>
      await default_url_launcher.launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

  /// No longer called by this package.
  ///
  /// It backed the `market://` probe that [launchStoreListing] dropped in
  /// 1.4.0. From Android 11 `canLaunchUrl`'s answer for a non-http scheme
  /// depends on package visibility, so it varied with how the app had been
  /// installed rather than with whether the URL could be opened. Kept so that
  /// existing `FlutterStoreListing.customize` calls keep compiling; it is gone
  /// in 2.0.
  final Future<bool> Function(String url) urlCanLaunch;

  final Future<bool> Function(String url) urlLaunch;

  static const MethodChannel _channel = MethodChannel('flutter_store_listing');

  /// The Play Store app's package name.
  ///
  /// Passed to the native Android implementation so the listing opens in the
  /// store app rather than a browser. Setting an intent's package is what
  /// Google's own "Linking to Google Play" guide documents, and it is the
  /// reason this package has an Android implementation at all — `url_launcher`
  /// cannot set one.
  static const playStorePackageName = 'com.android.vending';

  static final _instance = FlutterStoreListing.customize();

  /// Generates iOS Store listing for the given bundle identifier.
  ///
  /// Uses the current `apps.apple.com` host without a hardcoded storefront
  /// (the App Store redirects to the viewer's own region).
  String getIosStoreListing(String? appId, {String protocol = 'https'}) =>
      '$protocol://apps.apple.com/app/id$appId';

  /// Generates Android Store listing for the given package name.
  String getAndroidStoreListing(String appId) =>
      'https://play.google.com/store/apps/details?id=$appId';

  /// Whether launching store listing at all is supported;
  Future<bool> isSupported() async {
    return _isAndroid || _isIOS;
  }

  /// Whether review requests are supported
  /// (ie. iOS review dialog, since iOS 10.3)
  Future<bool> isSupportedNativeRequestReview() async {
    if (!_isIOS) {
      return false;
    }
    return _invokeIsSupportedRequestReview();
  }

  Future<bool> _invokeIsSupportedRequestReview() async =>
      (await _channel.invokeMethod<bool>('isSupportedRequestReview')) as bool;

  Future<bool> _invokeRequestReview() async =>
      (await _channel.invokeMethod<bool>('requestReview')) as bool;

  /// Opens [url] through the native Android implementation, which views it
  /// with the intent restricted to [playStorePackageName] and retries without
  /// the restriction when the store app is absent.
  ///
  /// Returns null when the native side is not there to answer at all — a host
  /// that has not been rebuilt since this package was upgraded, for instance —
  /// so that the caller can still fall back to [urlLaunch] rather than failing
  /// outright. A false means the device genuinely could not open it.
  Future<bool?> _invokeOpenStoreListing(String url) async {
    try {
      final result = await _channel.invokeMethod<String>('openStoreListing', {
        'url': url,
        'preferredPackage': playStorePackageName,
      });
      switch (result) {
        case 'storeApp':
        case 'external':
          return true;
        case 'unavailable':
          return false;
      }
      // Null rather than false, so an unrecognised reply degrades to the
      // url_launcher fallback instead of silently showing the user nothing.
      _logger.severe('Unexpected openStoreListing result: $result');
      return null;
    } on MissingPluginException catch (error, stackTrace) {
      _logger.warning(
        'No native openStoreListing implementation; falling back to '
        'url_launcher. Rebuild the app if this persists.',
        error,
        stackTrace,
      );
      return null;
    } on PlatformException catch (error, stackTrace) {
      _logger.severe(
        'Unable to open the store listing natively.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// Asks the user for a review: the native in-app dialog on iOS, otherwise
  /// the store listing opened externally.
  ///
  /// Returns true when a review was asked for by one route or the other. A
  /// true from the native dialog means the request reached StoreKit, not that
  /// a prompt appeared — StoreKit rate-limits it per user and per app version
  /// and never reports back either way.
  ///
  /// When the native dialog is not available — any non-iOS platform, or iOS
  /// with no window scene to present in — this falls back to
  /// [launchStoreListing]. Set [onlyNative] to true to do nothing and return
  /// false in that case instead.
  ///
  /// The native prompt and the store listing are deliberately exclusive: up to
  /// 1.2.0 a successful native prompt on iOS *also* opened the store listing,
  /// ejecting the user to the App Store straight after the in-app dialog, and
  /// returned false for `onlyNative: true` precisely when the prompt had been
  /// shown. Both were inversions of this doc comment; see CHANGELOG 1.3.0.
  Future<bool> launchRequestReview({bool onlyNative = false}) async {
    // Short-circuits before the channel call off iOS, where there is no
    // native implementation to invoke.
    if (_isIOS && await _invokeRequestReview()) {
      return true;
    }
    if (onlyNative) {
      return false;
    }
    return await launchStoreListing(iosWriteReview: true);
  }

  /// Launches the URL for reviewing.
  /// * Android: opens `play.google.com/store/apps/details` in the Play Store
  ///     app, falling back to whatever else handles the URL — a browser — when
  ///     the store app is absent.
  /// * iOS: Open `apps.apple.com` - set [iosWriteReview] to true to
  ///     use `?action=write-review`
  ///
  /// Up to 1.3.0 Android asked `canLaunchUrl('market://')` first and opened a
  /// `market:` URL when that said yes. Where the app had been installed from
  /// the Play Store it generally did say yes, because Android makes the app
  /// that installed your app visible automatically — no `<queries>` entry,
  /// whatever the `targetSdk`. So for most users `market://` is what opened,
  /// and 1.4.0 changes the route rather than the destination: both it and the
  /// https URL with the package set reach the Play Store app.
  ///
  /// The probe did fail for an install from outside the Play Store on an app
  /// targeting API 30 or higher with no `<queries>` entry of its own, since
  /// `com.android.vending` is then not automatically visible. Those users got
  /// the https URL in a browser, and still do when the store app is absent.
  ///
  /// 1.4.0 drops the probe and asks the native implementation to view the https
  /// URL with the intent restricted to the Play Store app, which is what Google
  /// documents and what needs no manifest entry from anybody.
  Future<bool> launchStoreListing({bool iosWriteReview = true}) async {
    if (_isIOS) {
      final appId = await getIosAppId();
      // https://developer.apple.com/documentation/storekit/skstorereviewcontroller/requesting_app_store_reviews?language=objc
      final urlPostfix = iosWriteReview ? '?action=write-review' : '';
      return await urlLaunch('${getIosStoreListing(appId)}$urlPostfix');
    }
    // getAndroidPackageName(), not _getPackageName(): the former honours the
    // documented [forceAndroidPackageName] override, which this method used
    // to ignore.
    final url = getAndroidStoreListing(await getAndroidPackageName());
    if (_isAndroid) {
      final launched = await _invokeOpenStoreListing(url);
      if (launched != null) {
        return launched;
      }
    }
    // Either not Android — macOS, Windows, Linux and web still land here, and
    // 2.0 is where that becomes an explicit "unsupported" rather than a Play
    // listing — or the native implementation could not answer.
    try {
      return await urlLaunch(url);
    } on PlatformException catch (error, stackTrace) {
      // `launchUrl` is documented to either return false or throw, and this
      // method promises a bool. The reachable case is a detached activity:
      // url_launcher is `ActivityAware` too, so when the native side above
      // reported `no_activity`, url_launcher's own `ensureActivity` throws
      // here rather than providing the fallback it looks like.
      _logger.severe('Unable to open $url.', error, stackTrace);
      return false;
    }
  }

  Future<String> _getPackageName() async {
    final packageInfo = await PackageInfo.fromPlatform();

    final appName = packageInfo.appName;
    final packageName = packageInfo.packageName;
    final version = packageInfo.version;
    final buildNumber = packageInfo.buildNumber;

    _logger.finer(
      'App Name: $appName\nPackage Name: $packageName\nVersion: $version\nBuild Number: $buildNumber',
    );

    return packageName;
  }

  Future<String> getAndroidPackageName() async {
    return forceAndroidPackageName ?? await _getPackageName();
  }

  Future<String?> getIosAppId() async {
    if (forceIosAppId != null) {
      return forceIosAppId;
    }
    final packageName = await _getPackageName();
    try {
      // Must be https: iOS App Transport Security blocks cleartext http
      // requests by default.
      final response = await http.get(
        Uri.parse('https://itunes.apple.com/lookup?bundleId=$packageName'),
      );
      final responseJson = json.decode(response.body) as Map<String, dynamic>;
      final results = responseJson['results'] as List;
      if (results.isEmpty) {
        _logger.severe('Unable to load app id, empty results for $packageName');
        return null;
      }
      return results[0]['trackId'].toString();
    } catch (error, stackTrace) {
      _logger.severe(
        'Unable to load app id for $packageName',
        error,
        stackTrace,
      );
      return null;
    }
  }
}
