import 'package:flutter/services.dart';
import 'package:flutter_store_listing/flutter_store_listing.dart';
// Not exported: the default implementations are reachable through the seams,
// but their mapping of the native replies is specified behaviour and belongs
// under test.
import 'package:flutter_store_listing/src/defaults.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the facade asked the launcher to do, so tests can assert on it
/// without a method channel or a real browser.
class _FakeLauncher implements StoreListingLauncher {
  _FakeLauncher({this.opens = true});

  /// What [openStoreListing] should answer.
  final bool opens;

  final opened = <Uri>[];

  @override
  Future<bool> openStoreListing(Uri uri) async {
    opened.add(uri);
    return opens;
  }
}

class _FakeIdentity implements StoreIdentity {
  _FakeIdentity(this.packageName);

  final String? packageName;

  @override
  Future<String?> androidPackageName() async => packageName;
}

class _FakePrompt implements InAppReviewPrompt {
  _FakePrompt({this.available = true, this.accepts = true});

  final bool available;
  final bool accepts;

  var availableCalls = 0;
  var requestCalls = 0;

  @override
  Future<bool> isAvailable() async {
    availableCalls++;
    return available;
  }

  @override
  Future<bool> requestReview() async {
    requestCalls++;
    return accepts;
  }
}

FlutterStoreListing _subject({
  StorePlatform platform = StorePlatform.android,
  String? appStoreId,
  String? macAppStoreId,
  String? androidPackageName = 'design.codeux.authpass',
  StoreListingLauncher? launcher,
  StoreIdentity? identity,
  InAppReviewPrompt? inAppReview,
}) => FlutterStoreListing.custom(
  platform: platform,
  appStoreId: appStoreId,
  macAppStoreId: macAppStoreId,
  androidPackageName: androidPackageName,
  launcher: launcher,
  identity: identity,
  inAppReview: inAppReview,
);

void main() {
  // Every test builds its own instance, but `configure()` writes to statics,
  // so one test could otherwise leak into the next.
  setUp(FlutterStoreListing.resetConfiguration);
  tearDown(FlutterStoreListing.resetConfiguration);

  group('URL builders', () {
    test('App Store URL pins no storefront', () {
      // Regression test: up to 1.2.0 this was the legacy
      // `itunes.apple.com/us/app/id...` form, which held every user to the US
      // store.
      expect(
        FlutterStoreListing.appStoreUri(appStoreId: '1479297675').toString(),
        'https://apps.apple.com/app/id1479297675',
      );
    });

    test('App Store URL can ask for the write-review page', () {
      expect(
        FlutterStoreListing.appStoreUri(
          appStoreId: '1479297675',
          writeReview: true,
        ).toString(),
        'https://apps.apple.com/app/id1479297675?action=write-review',
      );
    });

    test('Play Store URL is the documented details URL', () {
      expect(
        FlutterStoreListing.playStoreWebUri(
          packageName: 'design.codeux.authpass',
        ).toString(),
        'https://play.google.com/store/apps/details?id=design.codeux.authpass',
      );
    });
  });

  group('storeId', () {
    test('iOS reports the App Store id', () async {
      expect(
        await _subject(
          platform: StorePlatform.iOS,
          appStoreId: '1479297675',
        ).storeId(),
        '1479297675',
      );
    });

    test('macOS reports its own id when the app has two SKUs', () async {
      expect(
        await _subject(
          platform: StorePlatform.macOS,
          appStoreId: '1479297675',
          macAppStoreId: '1478552452',
        ).storeId(),
        '1478552452',
      );
    });

    test(
      'macOS falls back to the App Store id under universal purchase',
      () async {
        // The fallback direction matters: the reverse default would silently
        // send Mac users to the iOS listing, which is the bug macAppStoreId
        // exists to prevent.
        expect(
          await _subject(
            platform: StorePlatform.macOS,
            appStoreId: '1479297675',
          ).storeId(),
          '1479297675',
        );
      },
    );

    test('Android asks the identity for the package name', () async {
      expect(
        await _subject(
          androidPackageName: null,
          identity: _FakeIdentity('com.example.resolved'),
        ).storeId(),
        'com.example.resolved',
      );
    });

    test(
      'Android honours a configured package name over the identity',
      () async {
        // Regression test: launchStoreListing used to read the package name
        // straight from package_info_plus, ignoring the documented override.
        expect(
          await _subject(
            androidPackageName: 'com.example.override',
            identity: _FakeIdentity('com.example.resolved'),
          ).storeId(),
          'com.example.override',
        );
      },
    );

    test('an unsupported platform has no store id', () async {
      expect(
        await _subject(platform: StorePlatform.unsupported).storeId(),
        isNull,
      );
    });
  });

  group('capability getters', () {
    test('are synchronous, so they are usable in build()', () {
      // The point of the change: up to 1.4.0 both were Future<bool>, so a
      // widget needed a FutureBuilder to learn a compile-time constant.
      expect(_subject().isStoreListingSupported, isA<bool>());
      expect(_subject().isInAppReviewSupported, isA<bool>());
    });

    test('Android can always open its listing', () {
      expect(_subject().isStoreListingSupported, isTrue);
    });

    test('iOS without an App Store id cannot', () {
      // Regression test for the design's own review: this used to return true
      // on iOS while openStoreListing reported storeIdUnavailable, so UI
      // gating a "Rate this app" row on it rendered one that did nothing.
      expect(
        _subject(platform: StorePlatform.iOS).isStoreListingSupported,
        isFalse,
      );
    });

    test('iOS with an App Store id can', () {
      expect(
        _subject(
          platform: StorePlatform.iOS,
          appStoreId: '1479297675',
        ).isStoreListingSupported,
        isTrue,
      );
    });

    test('an unsupported platform cannot', () {
      expect(
        _subject(platform: StorePlatform.unsupported).isStoreListingSupported,
        isFalse,
      );
    });

    test('in-app review is iOS-only by default', () {
      expect(
        _subject(platform: StorePlatform.iOS).isInAppReviewSupported,
        isTrue,
      );
      expect(_subject().isInAppReviewSupported, isFalse);
    });

    test('a configured prompt makes Android support in-app review', () {
      // What the InAppReviewPrompt seam is for: a separate Play package ships
      // an implementation and the capability getter has to notice.
      expect(
        _subject(inAppReview: _FakePrompt()).isInAppReviewSupported,
        isTrue,
      );
    });
  });

  group('openStoreListing', () {
    test('opens the App Store listing on iOS', () async {
      final launcher = _FakeLauncher();
      final outcome = await _subject(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
        launcher: launcher,
      ).openStoreListing();

      expect(outcome, StoreListingOutcome.storeListingOpened);
      expect(outcome.isSuccess, isTrue);
      expect(
        launcher.opened.single.toString(),
        'https://apps.apple.com/app/id1479297675',
      );
    });

    test('defaults to the listing rather than the write-review page', () async {
      // The default is inverted from 1.4.0's `iosWriteReview = true`: a method
      // named for the listing should open the listing.
      final launcher = _FakeLauncher();
      await _subject(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
        launcher: launcher,
      ).openStoreListing();

      expect(launcher.opened.single.query, isEmpty);
    });

    test('can open the write-review page on iOS', () async {
      final launcher = _FakeLauncher();
      await _subject(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
        launcher: launcher,
      ).openStoreListing(writeReview: true);

      expect(launcher.opened.single.queryParameters['action'], 'write-review');
    });

    test('opens the Play listing on Android', () async {
      final launcher = _FakeLauncher();
      final outcome = await _subject(launcher: launcher).openStoreListing();

      expect(outcome, StoreListingOutcome.storeListingOpened);
      expect(
        launcher.opened.single.toString(),
        'https://play.google.com/store/apps/details?id=design.codeux.authpass',
      );
    });

    test('ignores writeReview on Android, which has no such page', () async {
      final launcher = _FakeLauncher();
      await _subject(launcher: launcher).openStoreListing(writeReview: true);

      expect(launcher.opened.single.queryParameters, {
        'id': 'design.codeux.authpass',
      });
    });

    test(
      'reports an unsupported platform without touching the launcher',
      () async {
        // This is the bug 2.0 exists to fix: up to 1.4.0 macOS, Windows, Linux
        // and web all fell into the Android branch and returned true after
        // opening a Google Play web page for a non-Android bundle id.
        final launcher = _FakeLauncher();
        final outcome = await _subject(
          platform: StorePlatform.unsupported,
          launcher: launcher,
        ).openStoreListing();

        expect(outcome, StoreListingOutcome.unsupportedPlatform);
        expect(outcome.isSuccess, isFalse);
        expect(launcher.opened, isEmpty);
      },
    );

    test(
      'reports an unknown store id when the identity cannot answer',
      () async {
        final launcher = _FakeLauncher();
        final outcome = await _subject(
          androidPackageName: null,
          identity: _FakeIdentity(null),
          launcher: launcher,
        ).openStoreListing();

        expect(outcome, StoreListingOutcome.storeIdUnavailable);
        expect(launcher.opened, isEmpty);
      },
    );

    test(
      'asserts in debug when an Apple platform has no id configured',
      () async {
        // The one silent breakage in the migration: missing appStoreId is a
        // runtime outcome rather than a compile error, so debug builds make it
        // loud. Release builds still report storeIdUnavailable, because an app
        // may legitimately run unconfigured.
        await expectLater(
          _subject(platform: StorePlatform.iOS).openStoreListing(),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('reports a refusal when the launcher will not open the URL', () async {
      final launcher = _FakeLauncher(opens: false);
      final outcome = await _subject(launcher: launcher).openStoreListing();

      expect(outcome, StoreListingOutcome.launchRefused);
      expect(outcome.isSuccess, isFalse);
      expect(launcher.opened, hasLength(1));
    });
  });

  group('requestReview', () {
    test('uses the in-app prompt and does not also open the store', () async {
      // Regression test: up to 1.2.0 a successful native prompt on iOS *also*
      // opened the store listing, ejecting the user to the App Store straight
      // after the in-app dialog.
      final launcher = _FakeLauncher();
      final prompt = _FakePrompt();
      final outcome = await _subject(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
        launcher: launcher,
        inAppReview: prompt,
      ).requestReview();

      expect(outcome, StoreListingOutcome.inAppReviewRequested);
      expect(outcome.isSuccess, isTrue);
      expect(prompt.requestCalls, 1);
      expect(launcher.opened, isEmpty);
    });

    test(
      'falls back to the write-review page when no prompt is available',
      () async {
        final launcher = _FakeLauncher();
        final outcome = await _subject(
          platform: StorePlatform.iOS,
          appStoreId: '1479297675',
          launcher: launcher,
          inAppReview: _FakePrompt(available: false),
        ).requestReview();

        expect(outcome, StoreListingOutcome.storeListingOpened);
        expect(
          launcher.opened.single.queryParameters['action'],
          'write-review',
        );
      },
    );

    test(
      'falls back when the prompt is available but refuses the request',
      () async {
        // This is the signal the iOS scene fix creates: with no
        // foreground-active scene StoreKit now reports false rather than
        // claiming a prompt it did not show, so the fallback runs.
        final launcher = _FakeLauncher();
        final prompt = _FakePrompt(accepts: false);
        final outcome = await _subject(
          platform: StorePlatform.iOS,
          appStoreId: '1479297675',
          launcher: launcher,
          inAppReview: prompt,
        ).requestReview();

        expect(prompt.requestCalls, 1);
        expect(outcome, StoreListingOutcome.storeListingOpened);
        expect(launcher.opened, hasLength(1));
      },
    );

    test('can fall back to the plain listing instead', () async {
      final launcher = _FakeLauncher();
      await _subject(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
        launcher: launcher,
        inAppReview: _FakePrompt(available: false),
      ).requestReview(fallback: ReviewFallback.storeListing);

      expect(launcher.opened.single.query, isEmpty);
    });

    test('reports the prompt unavailable when asked for no fallback', () async {
      // `ReviewFallback.none` replaces `onlyNative: true`. On Android — where
      // the store listing works perfectly — this must not say "unsupported
      // platform", which is the conflation the outcome enum exists to remove.
      final launcher = _FakeLauncher();
      final outcome = await _subject(
        launcher: launcher,
        inAppReview: _FakePrompt(available: false),
      ).requestReview(fallback: ReviewFallback.none);

      expect(outcome, StoreListingOutcome.inAppReviewUnavailable);
      expect(launcher.opened, isEmpty);
    });

    test(
      'an unsupported platform says so rather than blaming the prompt',
      () async {
        final outcome = await _subject(
          platform: StorePlatform.unsupported,
          inAppReview: _FakePrompt(available: false),
        ).requestReview(fallback: ReviewFallback.none);

        expect(outcome, StoreListingOutcome.unsupportedPlatform);
      },
    );

    test('never asks an unavailable prompt to show itself', () async {
      final prompt = _FakePrompt(available: false);
      await _subject(
        launcher: _FakeLauncher(),
        inAppReview: prompt,
      ).requestReview(fallback: ReviewFallback.none);

      expect(prompt.availableCalls, 1);
      expect(prompt.requestCalls, 0);
    });
  });

  group('storeListingUri', () {
    test('describes what openStoreListing would open', () async {
      expect(
        (await _subject().storeListingUri()).toString(),
        'https://play.google.com/store/apps/details?id=design.codeux.authpass',
      );
    });

    test('is null when the platform has no store', () async {
      expect(
        await _subject(platform: StorePlatform.unsupported).storeListingUri(),
        isNull,
      );
    });

    test('is null when the store id is unknown', () async {
      expect(
        await _subject(
          androidPackageName: null,
          identity: _FakeIdentity(null),
        ).storeListingUri(),
        isNull,
      );
    });
  });

  group('configure and the shared instance', () {
    test('instance reads configuration per call, not at construction', () async {
      // The hazard this removes: Dart static initialisers are lazy, so a read
      // before configure() does not throw — it constructs an unconfigured
      // default. A reference captured at that moment used to stay unconfigured
      // forever, and the example app constructs in a State field initialiser.
      final captured = FlutterStoreListing.instance;

      // Configured in two steps, both after the reference was taken, so each
      // assertion needs the read to happen at call time. The platform is
      // injected rather than left to the host: `flutter test` reports `macos`
      // locally and `linux` in CI, and a test whose result depends on which is
      // the thing this redesign set out to make impossible.
      FlutterStoreListing.configure(platform: StorePlatform.iOS);
      expect(captured.isStoreListingSupported, isFalse);
      expect(await captured.storeId(), isNull);

      FlutterStoreListing.configure(appStoreId: '1479297675');
      expect(captured.isStoreListingSupported, isTrue);
      expect(await captured.storeId(), '1479297675');
    });

    test('merges rather than replacing', () async {
      // The Play package's wiring is a second configure() call, so under
      // replace semantics it would wipe the ids set in main().
      FlutterStoreListing.configure(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
      );
      FlutterStoreListing.configure(inAppReview: _FakePrompt());

      expect(await FlutterStoreListing.instance.storeId(), '1479297675');
      expect(FlutterStoreListing.instance.isInAppReviewSupported, isTrue);
    });

    test('the last call wins for a value that is passed twice', () async {
      FlutterStoreListing.configure(
        platform: StorePlatform.iOS,
        appStoreId: '1',
      );
      FlutterStoreListing.configure(appStoreId: '2');

      expect(await FlutterStoreListing.instance.storeId(), '2');
    });

    test('resetConfiguration clears it', () async {
      FlutterStoreListing.configure(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
      );
      FlutterStoreListing.resetConfiguration();

      expect(await FlutterStoreListing.instance.storeId(), isNull);
    });

    test('a value given to .custom wins over configure', () async {
      FlutterStoreListing.configure(appStoreId: 'configured');

      expect(
        await _subject(
          platform: StorePlatform.iOS,
          appStoreId: 'explicit',
        ).storeId(),
        'explicit',
      );
    });
  });

  group('the default launcher maps the Android replies', () {
    // The Kotlin has its own unit tests under `android/src/test`; what is
    // covered here is the Dart side's mapping of its replies, which is where
    // the 1.4.0 review found real defects.
    TestWidgetsFlutterBinding.ensureInitialized();

    const channel = MethodChannel('flutter_store_listing');
    const launcher = DefaultStoreListingLauncher(StorePlatform.android);
    final uri = FlutterStoreListing.playStoreWebUri(packageName: 'com.example');

    void mockNative(Future<Object?>? Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    tearDown(() => mockNative(null));

    test('the store app taking the URL is a success', () async {
      mockNative((call) async => 'storeApp');
      expect(await launcher.openStoreListing(uri), isTrue);
    });

    test('something else taking it is a success too', () async {
      // Deliberately not distinguished: the user is gone either way, so a
      // caller cannot act on the difference.
      mockNative((call) async => 'external');
      expect(await launcher.openStoreListing(uri), isTrue);
    });

    test('nothing handling it is a refusal', () async {
      mockNative((call) async => 'unavailable');
      expect(await launcher.openStoreListing(uri), isFalse);
    });

    test(
      'a detached activity is a refusal, not a url_launcher retry',
      () async {
        // url_launcher is ActivityAware too and detached in the same window, so
        // its own ensureActivity would throw. 1.4.0 retried anyway and reached
        // the same false by a longer route.
        mockNative(
          (call) async => throw PlatformException(code: 'no_activity'),
        );
        expect(await launcher.openStoreListing(uri), isFalse);
      },
    );

    test(
      'it passes the URL and the Play Store package to the native side',
      () async {
        MethodCall? received;
        mockNative((call) async {
          received = call;
          return 'storeApp';
        });
        await launcher.openStoreListing(uri);

        expect(received?.method, 'openStoreListing');
        expect((received?.arguments as Map)['url'], uri.toString());
        expect(
          (received?.arguments as Map)['preferredPackage'],
          'com.android.vending',
        );
      },
    );

    test('it does not call the native side on Apple platforms', () async {
      var called = false;
      mockNative((call) async {
        called = true;
        return 'storeApp';
      });
      // Apple platforms go through url_launcher, which has no mock in this
      // test, so this also exercises the case below.
      final opened = await const DefaultStoreListingLauncher(
        StorePlatform.iOS,
      ).openStoreListing(uri);

      expect(called, isFalse);
      expect(opened, isFalse);
    });

    test('a missing url_launcher is a refusal, not an exception', () async {
      // Regression test, and the implementation was wrong when this was
      // written: `MissingPluginException` does not extend `PlatformException`,
      // so catching only the latter let it escape `openStoreListing` and broke
      // the StoreListingLauncher contract that implementations must not throw.
      // No url_launcher mock is installed here, so its channel is missing.
      await expectLater(
        const DefaultStoreListingLauncher(
          StorePlatform.macOS,
        ).openStoreListing(uri),
        completion(isFalse),
      );
    });
  });

  group('StoreKitInAppReview', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    const channel = MethodChannel('flutter_store_listing');

    void mockNative(Future<Object?>? Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    tearDown(() => mockNative(null));

    test('is available on iOS and nowhere else', () async {
      // The iOS prompt is behind the same interface the Play package would
      // implement, which is what makes it reachable from a test at all — up
      // to 1.4.0 it was a static const MethodChannel with no seam.
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).isAvailable(),
        isTrue,
      );
      expect(
        await const StoreKitInAppReview(StorePlatform.macOS).isAvailable(),
        isFalse,
      );
      expect(
        await const StoreKitInAppReview(StorePlatform.android).isAvailable(),
        isFalse,
      );
    });

    test('reports whether the request reached StoreKit', () async {
      mockNative((call) async => true);
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
        isTrue,
      );
    });

    test('a null reply is false rather than a TypeError', () async {
      // Regression test: 1.4.0 cast the reply with `as bool`, so a null threw.
      mockNative((call) async => null);
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
        isFalse,
      );
    });

    test(
      'a missing native implementation is false, so the fallback runs',
      () async {
        // Not an exception out of requestReview: up to 1.4.0 this propagated,
        // because _invokeRequestReview had no try/catch at all.
        mockNative((call) async => throw MissingPluginException());
        expect(
          await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
          isFalse,
        );
      },
    );

    test('a platform exception is false too', () async {
      mockNative((call) async => throw PlatformException(code: 'whatever'));
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
        isFalse,
      );
    });
  });

  group('the outcome enum', () {
    test('only the two success values report isSuccess', () {
      // Guards the enum against a future value being added as a success by
      // accident, which is the risk the "values may be added in a minor"
      // policy takes on.
      const successes = {
        StoreListingOutcome.inAppReviewRequested,
        StoreListingOutcome.storeListingOpened,
      };
      for (final outcome in StoreListingOutcome.values) {
        expect(
          outcome.isSuccess,
          successes.contains(outcome),
          reason: '$outcome',
        );
      }
    });

    test('every value is reachable from the public API', () {
      // §4's target. Each of these is asserted in a test above; this records
      // the mapping so a new value cannot be added without a home.
      expect(StoreListingOutcome.values, hasLength(6));
    });
  });
}
