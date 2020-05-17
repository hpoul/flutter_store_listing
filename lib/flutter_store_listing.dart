import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:package_info/package_info.dart';
import 'package:url_launcher/url_launcher.dart' as default_url_launcher;

final _logger = Logger('flutter_store_listing');

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
  final String forceIosAppId;

  /// Override android package, if null it will be retrieved from the current
  /// apk package.
  final String forceAndroidPackageName;

  static Future<bool> defaultUrlCanLaunch(String url) async =>
      await default_url_launcher.canLaunch(url);

  static Future<bool> defaultUrlLaunch(String url) async =>
      await default_url_launcher.launch(url, forceSafariVC: false);

  final Future<bool> Function(String url) urlCanLaunch;
  final Future<bool> Function(String url) urlLaunch;

  static const MethodChannel _channel = MethodChannel('flutter_store_listing');

  static final _instance = FlutterStoreListing.customize();

  /// Generates iOS Store listing for the given bundle identifier.
  String getIosStoreListing(String appId, {String protocol = 'https'}) =>
      '$protocol://itunes.apple.com/us/app/id$appId';

  /// Generates iOS Store listing for the given package name.
  String getAndroidStoreListing(String appId) =>
      'https://play.google.com/store/apps/details?id=$appId';

  /// Whether launching store listing at all is supported;
  Future<bool> isSupported() async {
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Whether review requests are supported
  /// (ie. iOS review dialog, since iOS 10.3)
  Future<bool> isSupportedNativeRequestReview() async {
    if (!Platform.isIOS) {
      return false;
    }
    return _channel.invokeMethod<bool>('isSupportedRequestReview');
  }

  /// launches a 'requestReview' dialog on iOS. If not available launches
  /// store URL externally.
  ///
  /// If [onlyNative] is true, will do nothing if the native dialog is not
  /// available. (e.g. on android).
  Future<bool> launchRequestReview({bool onlyNative = false}) async {
    if (Platform.isIOS) {
      if (!await _channel.invokeMethod<bool>('requestReview')) {
        if (onlyNative) {
          return false;
        }
        return await launchStoreListing(iosWriteReview: true);
      }
      return true;
    } else {
      if (onlyNative) {
        return false;
      }
      return await launchStoreListing();
    }
  }

  /// Launches a the URL for reviewing.
  /// * Android: If play store installed, opens play store via `market:` url,
  ///     otherwise launches `https://play.google.com/`
  /// * iOS: Open `itunes.apple.com` - set [iosWriteReview] to true to
  ///     use `?action=write-review`
  Future<bool> launchStoreListing({bool iosWriteReview = true}) async {
    if (Platform.isIOS) {
      final _appID = await getIosAppId();
      // https://developer.apple.com/documentation/storekit/skstorereviewcontroller/requesting_app_store_reviews?language=objc
      final urlPostfix = iosWriteReview ? '?action=write-review' : '';
      return await urlLaunch('${getIosStoreListing(_appID)}$urlPostfix');
    } else {
      final _appID = await _getPackageName();
      if (await urlCanLaunch('market://')) {
        return await urlLaunch('market://details?id=$_appID');
      } else {
        return await urlLaunch(getAndroidStoreListing(_appID));
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
        'App Name: $appName\nPackage Name: $packageName\nVersion: $version\nBuild Number: $buildNumber');

    return packageName;
  }

  Future<String> getAndroidPackageName() async {
    return forceAndroidPackageName ?? await _getPackageName();
  }

  Future<String> getIosAppId() async {
    if (forceIosAppId != null) {
      return forceIosAppId;
    }
    final packageName = await _getPackageName();
    try {
      final response = await http
          .get('http://itunes.apple.com/lookup?bundleId=$packageName');
      final responseJson = json.decode(response.body) as Map<String, dynamic>;
      final results = responseJson['results'] as List;
      if (results.isEmpty) {
        _logger.severe('Unable to load app id, empty results for $packageName');
        return null;
      }
      return results[0]['trackId'].toString();
    } catch (error, stackTrace) {
      _logger.severe(
          'Unable to load app id for $packageName', error, stackTrace);
      return null;
    }
  }
}
