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
    })();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(_appId),
            RaisedButton(
                child: const Text('Open Store Listing'),
                onPressed: () async {
                  await _fsl.launchStoreListing();
                }),
          ],
        ),
      ),
    );
  }
}
