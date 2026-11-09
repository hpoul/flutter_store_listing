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

  final Future<bool> Function(String url) urlCanLaunch;
  final Future<bool> Function(String url) urlLaunch;

  static const MethodChannel _channel = MethodChannel('flutter_store_listing');

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
  /// * Android: If play store installed, opens play store via `market:` url,
  ///     otherwise launches `https://play.google.com/`
  /// * iOS: Open `apps.apple.com` - set [iosWriteReview] to true to
  ///     use `?action=write-review`
  Future<bool> launchStoreListing({bool iosWriteReview = true}) async {
    if (_isIOS) {
      final appId = await getIosAppId();
      // https://developer.apple.com/documentation/storekit/skstorereviewcontroller/requesting_app_store_reviews?language=objc
      final urlPostfix = iosWriteReview ? '?action=write-review' : '';
      return await urlLaunch('${getIosStoreListing(appId)}$urlPostfix');
    } else {
      // getAndroidPackageName(), not _getPackageName(): the former honours the
      // documented [forceAndroidPackageName] override, which this method used
      // to ignore.
      final appId = await getAndroidPackageName();
      if (await urlCanLaunch('market://')) {
        return await urlLaunch('market://details?id=$appId');
      } else {
        return await urlLaunch(getAndroidStoreListing(appId));
      }
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
