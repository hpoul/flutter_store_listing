import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_store_listing/flutter_store_listing.dart';
import 'package:logging_appenders/logging_appenders.dart';

void main() {
  PrintAppender.setupLogging();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _appId = 'unknown';
  bool _requestReviewSupported = false;
  final _fsl = FlutterStoreListing();

  @override
  void initState() {
    super.initState();
    (() async {
      if (Platform.isIOS) {
        _appId = await _fsl.getIosAppId() ?? 'app id not found';
      } else if (Platform.isAndroid) {
        _appId = await _fsl.getAndroidPackageName();
      }
      _requestReviewSupported = await _fsl.isSupportedNativeRequestReview();
      if (mounted) {
        setState(() {});
      }
    })();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Align(
          alignment: const Alignment(0, -0.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(_appId),
              ElevatedButton(
                  child: const Text('Open Store Listing'),
                  onPressed: () async {
                    await _fsl.launchStoreListing();
                  }),
              if (_requestReviewSupported)
                ElevatedButton(
                    child: const Text('Request Review'),
                    onPressed: () async {
                      await _fsl.launchRequestReview(onlyNative: true);
                    }),
            ],
          ),
        ),
      ),
    );
  }
}
