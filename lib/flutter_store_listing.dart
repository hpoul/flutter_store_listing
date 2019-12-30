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
  FlutterStoreListing._();
  factory FlutterStoreListing() => _instance;

  String forceIosAppId;
  String forceAndroidPackageName;

  Future<bool> Function(String url) urlCanLaunch =
      (url) async => await default_url_launcher.canLaunch(url);
  Future<bool> Function(String url) urlLauncher = (url) async =>
      await default_url_launcher.launch(url, forceSafariVC: false);

  static const MethodChannel _channel = MethodChannel('flutter_store_listing');

  static final _instance = FlutterStoreListing._();

  String getIosStoreListing(String appId, {String protocol = 'https'}) =>
      '$protocol://itunes.apple.com/us/app/id$appId';

  String getAndroidStoreListing(String appId) =>
      'https://play.google.com/store/apps/details?id=$appId';

  /// launches a 'requestReview' dialog on iOS. If not available launches store URL externally.
  /// If [onlyNative] is true, will do nothing if the native dialog is not available. (e.g. on android).
  Future<bool> launchRequestReview({bool onlyNative = false}) async {
    if (Platform.isIOS) {
      if (!await _channel.invokeMethod<bool>('requestReview')) {
        if (onlyNative) {
          return false;
        }
        return await launchStoreListing(requestReview: true);
      }
      return true;
    } else {
      if (onlyNative) {
        return false;
      }
      return await launchStoreListing();
    }
  }

  Future<bool> launchStoreListing({bool requestReview}) async {
    if (Platform.isIOS) {
      final _appID = await getIosAppId;
      // https://developer.apple.com/documentation/storekit/skstorereviewcontroller/requesting_app_store_reviews?language=objc
      final urlPostfix = requestReview ? '?action=write-review' : '';
      return await urlLauncher('${getIosStoreListing(_appID)}$urlPostfix');
    } else {
      final _appID = await _getPackageName();
      if (await urlCanLaunch('market://')) {
        return await urlLauncher('market://details?id=$_appID');
      } else {
        return await urlLauncher(getAndroidStoreListing(_appID));
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

  Future<String> get getIosAppId async {
    if (forceIosAppId != null) {
      return forceIosAppId;
    }
    final _appID = await _getPackageName();
    return await http
        .get('http://itunes.apple.com/lookup?bundleId=$_appID')
        .then((dynamic response) {
      final _json =
          json.decode(response.body as String) as Map<String, dynamic>;
      final _id = _json['results'][0]['trackId'].toString();
      return _id;
    });
  }
}
