import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:package_info/package_info.dart';
import 'package:url_launcher/url_launcher.dart' as defaultUrlLauncher;

final _logger = Logger('flutter_store_listing');

class FlutterStoreListing {
  FlutterStoreListing._();
  factory FlutterStoreListing() => _instance;

  String forceIosAppId;
  String forceAndroidPackageName;

  Future<bool> Function(String url) urlCanLaunch = (url) async => await defaultUrlLauncher.canLaunch(url);
  Future<bool> Function(String url) urlLauncher =
      (url) async => await defaultUrlLauncher.launch(url, forceSafariVC: false);

  static const MethodChannel _channel = MethodChannel('flutter_store_listing');

  static final _instance = FlutterStoreListing._();

  String getIosStoreListing(String appId, {String protocol = 'https'}) =>
      '$protocol://itunes.apple.com/us/app/id$appId';

  String getAndroidStoreListing(String appId) => 'https://play.google.com/store/apps/details?id=$appId';

  Future<bool> requestReview() async {
    if (Platform.isIOS) {
      if (!await _channel.invokeMethod<bool>('requestReview')) {
        return await launchStoreListing();
      }
      return true;
    } else {
      return await launchStoreListing();
    }
  }

  Future<bool> launchStoreListing({bool requestReview}) async {
    if (Platform.isIOS) {
      final String _appID = await getIosAppId;
      final String urlPostfix = requestReview ? '?mt=8&action=write-review' : '';
      return await urlLauncher('${getIosStoreListing(_appID)}$urlPostfix');
    } else {
      final String _appID = await _getPackageName();
      if (await urlCanLaunch('market://')) {
        return await urlLauncher('market://details?id=$_appID');
      } else {
        return await urlLauncher(getAndroidStoreListing(_appID));
      }
    }
  }

  Future<String> _getPackageName() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();

    final String appName = packageInfo.appName;
    final String packageName = packageInfo.packageName;
    final String version = packageInfo.version;
    final String buildNumber = packageInfo.buildNumber;

    _logger.finer('App Name: $appName\nPackage Name: $packageName\nVersion: $version\nBuild Number: $buildNumber');

    return packageName;
  }

  Future<String> getAndroidPackageName() async {
    return forceAndroidPackageName ?? await _getPackageName();
  }

  Future<String> get getIosAppId async {
    if (forceIosAppId != null) {
      return forceIosAppId;
    }
    final String _appID = await _getPackageName();
    String _id = '';
    return await http.get('http://itunes.apple.com/lookup?bundleId=$_appID').then((dynamic response) {
      final Map<String, dynamic> _json = json.decode(response.body as String) as Map<String, dynamic>;
      _id = _json['results'][0]['trackId'].toString();
      return _id;
    });
  }
}
