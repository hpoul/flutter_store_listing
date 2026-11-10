import 'package:flutter/material.dart';
import 'package:flutter_store_listing/flutter_store_listing.dart';
import 'package:logging_appenders/logging_appenders.dart';

void main() {
  PrintAppender.setupLogging();
  // Real ids, so this example demonstrates the working path rather than the
  // failure mode. With no appStoreId, Apple platforms would report
  // storeIdUnavailable and the id display below would read "no store id"
  // forever — there is no runtime lookup in 2.0.
  //
  // Two different ids because AuthPass is not a universal purchase: the Mac
  // app has its own SKU. An app with one SKU passes appStoreId alone.
  FlutterStoreListing.configure(
    appStoreId: '1479297675',
    macAppStoreId: '1478552452',
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // The shared instance, like any app would use. Capturing it in a field
  // initialiser is safe: it reads its configuration on each call rather than
  // at construction, so this is configured even though main() runs after the
  // field is first touched.
  final _storeListing = FlutterStoreListing.instance;

  String _storeId = 'resolving…';
  StoreListingOutcome? _lastOutcome;

  @override
  void initState() {
    super.initState();
    (() async {
      final storeId = await _storeListing.storeId();
      if (!mounted) {
        return;
      }
      setState(() {
        _storeId = storeId ?? 'no store id on this platform';
      });
    })();
  }

  Future<void> _run(Future<StoreListingOutcome> Function() action) async {
    final outcome = await action();
    if (!mounted) {
      return;
    }
    setState(() {
      _lastOutcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The platform as a value, rather than branching on `Platform.isIOS` and
    // contradicting what the package itself reports.
    final platform = StorePlatform.current;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Align(
          alignment: const Alignment(0, -0.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text('Platform: ${platform.name}'),
              Text('Store id: $_storeId'),
              const SizedBox(height: 8),
              Text(switch (platform) {
                StorePlatform.android ||
                StorePlatform.iOS ||
                StorePlatform.macOS => 'This platform has a store listing.',
                StorePlatform.unsupported =>
                  'No app store here — every call reports '
                      'unsupportedPlatform.',
              }),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _run(_storeListing.openStoreListing),
                child: const Text('Open store listing'),
              ),
              ElevatedButton(
                onPressed: () => _run(
                  () => _storeListing.openStoreListing(writeReview: true),
                ),
                child: const Text('Open write-review page'),
              ),
              ElevatedButton(
                onPressed: () => _run(_storeListing.requestReview),
                child: const Text('Request review (with fallback)'),
              ),
              ...[
                if (_storeListing.isInAppReviewSupported) ...[
                  ElevatedButton(
                    onPressed: () => _run(
                      () => _storeListing.requestReview(
                        fallback: ReviewFallback.none,
                      ),
                    ),
                    child: const Text('Request review (native only)'),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              // The whole point of returning an outcome rather than a bool:
              // "unsupported platform", "no store id" and "the launcher
              // refused" are now distinguishable, and from success too.
              Text('Last outcome: ${_lastOutcome?.name ?? '—'}'),
            ],
          ),
        ),
      ),
    );
  }
}
