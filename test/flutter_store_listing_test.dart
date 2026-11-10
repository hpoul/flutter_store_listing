import 'package:flutter/services.dart';
import 'package:flutter_store_listing/flutter_store_listing.dart';
// The one thing still not exported, because a consumer has no use for it: the
// OS-name mapping behind `StorePlatform.current`.
import 'package:flutter_store_listing/src/store_platform.dart'
    show resolveStorePlatform;
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
  _FakePrompt({
    this.available = true,
    this.result = InAppReviewRequest.requested,
  });

  final bool available;

  /// What [requestReview] should answer. Three states rather than a bool,
  /// because `notNow` and `unavailable` are handled oppositely by the facade.
  final InAppReviewRequest result;

  var availableCalls = 0;
  var requestCalls = 0;

  @override
  Future<bool> isAvailable() async {
    availableCalls++;
    return available;
  }

  @override
  Future<InAppReviewRequest> requestReview() async {
    requestCalls++;
    return result;
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
      // What this asserts is the static type, and only that: up to 1.4.0 both
      // were Future<bool>, so a widget needed a FutureBuilder to learn a
      // compile-time constant. It therefore cannot fail for any code that
      // compiles — a regression to Future<bool> is what it catches, and the
      // answers themselves are asserted by the four tests below.
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

    test('in-app review is Apple-only by default', () {
      expect(
        _subject(platform: StorePlatform.iOS).isInAppReviewSupported,
        isTrue,
      );
      // New in 2.1, and the assertion that was missing: this getter kept its
      // own `platform == StorePlatform.iOS`, so teaching the prompt about
      // macOS left the capability getter answering false with a green suite.
      expect(
        _subject(platform: StorePlatform.macOS).isInAppReviewSupported,
        isTrue,
      );
      expect(_subject().isInAppReviewSupported, isFalse);
      expect(
        _subject(platform: StorePlatform.unsupported).isInAppReviewSupported,
        isFalse,
      );
    });

    test('the getter and the built-in prompt cannot drift apart', () async {
      // The structural half of that fix. The getter is synchronous and
      // `InAppReviewPrompt.isAvailable` is not, so the two cannot be one
      // member; this holds them to the same answer on every platform,
      // including a value added after this was written.
      for (final platform in StorePlatform.values) {
        expect(
          _subject(platform: platform).isInAppReviewSupported,
          await StoreKitInAppReview(platform).isAvailable(),
          reason: 'the getter and the prompt disagree about $platform',
        );
      }
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

    test('opens the Mac App Store listing on macOS', () async {
      // The bug 2.0 exists to fix, in the one shape no other test here caught:
      // up to 1.4.0 macOS fell into the Android branch and opened a Google Play
      // web page built from an App Store id. Nothing put macOS through the URL
      // switch, so changing its arm to `playStoreWebUri` passed all 54 tests.
      final launcher = _FakeLauncher();
      final outcome = await _subject(
        platform: StorePlatform.macOS,
        macAppStoreId: '1478552452',
        launcher: launcher,
      ).openStoreListing();

      expect(outcome, StoreListingOutcome.storeListingOpened);
      expect(
        launcher.opened.single.toString(),
        'https://apps.apple.com/app/id1478552452',
      );
    });

    test('can open the write-review page on macOS', () async {
      final launcher = _FakeLauncher();
      await _subject(
        platform: StorePlatform.macOS,
        macAppStoreId: '1478552452',
        launcher: launcher,
      ).openStoreListing(writeReview: true);

      expect(launcher.opened.single.queryParameters['action'], 'write-review');
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
      'falls back when an available prompt turns out to be broken',
      () async {
        // `unavailable` from a prompt that said it was available: a host that
        // was not rebuilt, so the native side is missing. No amount of waiting
        // fixes that, so the fallback is the right answer.
        final launcher = _FakeLauncher();
        final prompt = _FakePrompt(result: InAppReviewRequest.unavailable);
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

    test('does not fall back when the prompt says "not now"', () async {
      // The whole point of the third signal. An app asking for a review from a
      // post-frame callback on a cold start, before the scene reaches
      // .foregroundActive, used to be sent to the App Store write-review page
      // with no interaction at all — worse than 1.4.0, which showed nothing.
      final launcher = _FakeLauncher();
      final prompt = _FakePrompt(result: InAppReviewRequest.notNow);
      final outcome = await _subject(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
        launcher: launcher,
        inAppReview: prompt,
      ).requestReview();

      expect(prompt.requestCalls, 1);
      expect(outcome, StoreListingOutcome.inAppReviewNotNow);
      expect(outcome.isSuccess, isFalse);
      expect(launcher.opened, isEmpty);
    });

    test(
      '"not now" ignores the fallback, whichever one was asked for',
      () async {
        // Including the explicit ones: the fallback answers "there is no prompt
        // here", and this is not that.
        for (final fallback in ReviewFallback.values) {
          final launcher = _FakeLauncher();
          final outcome = await _subject(
            platform: StorePlatform.iOS,
            appStoreId: '1479297675',
            launcher: launcher,
            inAppReview: _FakePrompt(result: InAppReviewRequest.notNow),
          ).requestReview(fallback: fallback);

          expect(
            outcome,
            StoreListingOutcome.inAppReviewNotNow,
            reason: '$fallback',
          );
          expect(launcher.opened, isEmpty, reason: '$fallback');
        }
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
      'an unsupported platform with no prompt says so rather than blaming one',
      () async {
        // No `inAppReview`: the default StoreKit prompt reports itself
        // unavailable off iOS without touching a channel, so this is the real
        // web and desktop shape — nothing here at all.
        final outcome = await _subject(
          platform: StorePlatform.unsupported,
        ).requestReview(fallback: ReviewFallback.none);

        expect(outcome, StoreListingOutcome.unsupportedPlatform);
      },
    );

    test(
      'but a configured prompt on that platform is what gets reported',
      () async {
        // These two answers used to contradict each other: the getter counted
        // the configured prompt while the ReviewFallback.none arm looked only
        // at the platform and blamed it, so the same configuration was both
        // "review is supported here" and "this platform has no app store at
        // all". With a prompt configured, the store's absence is not what the
        // caller asked about.
        final subject = _subject(
          platform: StorePlatform.unsupported,
          inAppReview: _FakePrompt(available: false),
        );

        expect(subject.isInAppReviewSupported, isTrue);
        expect(
          await subject.requestReview(fallback: ReviewFallback.none),
          StoreListingOutcome.inAppReviewUnavailable,
        );
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

  group('a configured prompt is preferred, not substituted', () {
    // `configure(inAppReview: …)` is global and documented as *the* Android
    // extension point, so an app shipping on both stores makes that one call in
    // main(). It used to replace StoreKit on iOS too, where a Play-backed
    // prompt reports itself unavailable — so the user who should have seen the
    // native rating dialog was sent to the App Store write-review page, while
    // `isInAppReviewSupported` still answered true.
    test(
      'the built-in prompt runs when the configured one is unavailable',
      () async {
        final play = _FakePrompt(available: false);
        final storeKit = _FakePrompt();
        final outcome = await _subject(
          platform: StorePlatform.iOS,
          appStoreId: '1479297675',
          inAppReview: PreferredInAppReview(preferred: play, builtIn: storeKit),
        ).requestReview();

        expect(outcome, StoreListingOutcome.inAppReviewRequested);
        expect(play.requestCalls, 0);
        expect(storeKit.requestCalls, 1);
      },
    );

    test('the configured prompt wins wherever it is available', () async {
      final play = _FakePrompt();
      final storeKit = _FakePrompt();
      final outcome = await _subject(
        inAppReview: PreferredInAppReview(preferred: play, builtIn: storeKit),
      ).requestReview();

      expect(outcome, StoreListingOutcome.inAppReviewRequested);
      expect(play.requestCalls, 1);
      expect(storeKit.requestCalls, 0);
    });

    test('a preferred prompt saying "not now" is not retried', () async {
      // Only `unavailable` hands over. Retrying a "not now" through the second
      // prompt would make one request from the caller into two attempts at the
      // user — and on iOS both prompts would be looking at the same inactive
      // scene anyway.
      final play = _FakePrompt(result: InAppReviewRequest.notNow);
      final storeKit = _FakePrompt();
      final outcome = await _subject(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
        launcher: _FakeLauncher(),
        inAppReview: PreferredInAppReview(preferred: play, builtIn: storeKit),
      ).requestReview();

      expect(outcome, StoreListingOutcome.inAppReviewNotNow);
      expect(play.requestCalls, 1);
      expect(storeKit.requestCalls, 0);
    });

    test('neither available runs the fallback', () async {
      final launcher = _FakeLauncher();
      final outcome = await _subject(
        launcher: launcher,
        inAppReview: PreferredInAppReview(
          preferred: _FakePrompt(available: false),
          builtIn: _FakePrompt(available: false),
        ),
      ).requestReview(fallback: ReviewFallback.none);

      expect(outcome, StoreListingOutcome.inAppReviewUnavailable);
      expect(launcher.opened, isEmpty);
    });

    test('configure on iOS keeps StoreKit reachable', () async {
      // The bug end to end, through the real resolution rather than a
      // hand-built composite. Mocking the channel is what makes the assertion
      // sharp: before the fix the configured prompt's `false` ended the call
      // and *no channel call happened at all*, so both versions returned a
      // non-success outcome and only `calls` tells them apart.
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('flutter_store_listing');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return 'requested';
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      FlutterStoreListing.configure(
        platform: StorePlatform.iOS,
        appStoreId: '1479297675',
        inAppReview: _FakePrompt(available: false),
      );

      final outcome = await FlutterStoreListing.instance.requestReview(
        fallback: ReviewFallback.none,
      );

      expect(calls, ['requestReview']);
      expect(outcome, StoreListingOutcome.inAppReviewRequested);
    });

    test('macOS reaches StoreKit through the real resolution', () async {
      // The macOS counterpart of the test above. Until 2.1 the built-in prompt
      // reported itself unavailable here and the channel was never called.
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('flutter_store_listing');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return 'requested';
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final launcher = _FakeLauncher();
      final outcome = await _subject(
        platform: StorePlatform.macOS,
        macAppStoreId: '1478552452',
        launcher: launcher,
      ).requestReview();

      expect(calls, ['requestReview']);
      expect(outcome, StoreListingOutcome.inAppReviewRequested);
      // The prompt and the listing are mutually exclusive, which 1.2.0 got
      // wrong on iOS by doing both.
      expect(launcher.opened, isEmpty);
    });

    test('a windowless Mac still gets the write-review page', () async {
      // The whole macOS "no presenter" path, end to end, through the real
      // StoreKit prompt rather than a composite built by hand.
      //
      // Both halves of this were asserted separately — that `noPresenter`
      // maps to `unavailable`, and that `unavailable` runs the fallback — and
      // never together. That is the exact shape of the bug this release found,
      // so the path that the first draft of 2.1 got wrong is now covered as
      // one piece: had `noPresenter` stayed mapped to `notNow`, this would
      // report `inAppReviewNotNow` and open nothing.
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('flutter_store_listing');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => 'noPresenter');
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final launcher = _FakeLauncher();
      final outcome = await _subject(
        platform: StorePlatform.macOS,
        macAppStoreId: '1478552452',
        launcher: launcher,
      ).requestReview();

      expect(outcome, StoreListingOutcome.storeListingOpened);
      expect(
        launcher.opened.single,
        Uri.parse(
          'https://apps.apple.com/app/id1478552452?action=write-review',
        ),
      );
    });
  });

  group('storeListingUri', () {
    test('describes what openStoreListing would open', () async {
      expect(
        (await _subject().storeListingUri()).toString(),
        'https://play.google.com/store/apps/details?id=design.codeux.authpass',
      );
    });

    test('builds the App Store URL on macOS, not the Play one', () async {
      expect(
        (await _subject(
          platform: StorePlatform.macOS,
          macAppStoreId: '1478552452',
        ).storeListingUri(writeReview: true)).toString(),
        'https://apps.apple.com/app/id1478552452?action=write-review',
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
      //
      // Android rather than iOS for the prompt half: on iOS
      // `isInAppReviewSupported` is true because of the platform, so it would
      // answer true under replace semantics too and only the id assertion
      // would carry any weight.
      final prompt = _FakePrompt(available: false);
      FlutterStoreListing.configure(
        platform: StorePlatform.android,
        androidPackageName: 'design.codeux.authpass',
        appStoreId: '1479297675',
      );
      FlutterStoreListing.configure(inAppReview: prompt);

      expect(
        await FlutterStoreListing.instance.storeId(),
        'design.codeux.authpass',
      );
      expect(FlutterStoreListing.instance.isInAppReviewSupported, isTrue);

      // The App Store id from the first call also survived the second, which
      // switching only the platform reads back.
      FlutterStoreListing.configure(platform: StorePlatform.iOS);
      expect(await FlutterStoreListing.instance.storeId(), '1479297675');

      // And the prompt is the one actually asked, not merely counted by the
      // getter above.
      FlutterStoreListing.configure(platform: StorePlatform.android);
      await FlutterStoreListing.instance.requestReview(
        fallback: ReviewFallback.none,
      );
      expect(prompt.availableCalls, 1);
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
        macAppStoreId: '1478552452',
        inAppReview: _FakePrompt(),
      );
      FlutterStoreListing.resetConfiguration();

      // The platform has to be put back before anything is read, because reset
      // clears that too and `_effectivePlatform` then falls through to the
      // host. That made this the one host-dependent test in the file: on the
      // `linux` CI runner an unsupported platform returns a null store id
      // whether or not reset cleared the ids, so it passed on a
      // resetConfiguration that did nothing at all, while catching a real
      // failure on a `macos` developer machine.
      FlutterStoreListing.configure(platform: StorePlatform.iOS);
      expect(await FlutterStoreListing.instance.storeId(), isNull);

      FlutterStoreListing.configure(platform: StorePlatform.macOS);
      expect(await FlutterStoreListing.instance.storeId(), isNull);

      // Android, because `isInAppReviewSupported` is true on iOS from the
      // platform alone and would not notice the prompt still being there.
      FlutterStoreListing.configure(platform: StorePlatform.android);
      expect(FlutterStoreListing.instance.isInAppReviewSupported, isFalse);
    });

    test('an instance App Store id beats a configured macAppStoreId', () async {
      // The two levels used to interleave. The Mac fallback chained to the
      // *effective* App Store id, so the chain reached a global
      // `macAppStoreId` before the id this instance was built with — an
      // explicit argument losing to a default the caller never asked about,
      // which is the opposite of what `.custom` documents.
      FlutterStoreListing.configure(
        appStoreId: 'configured-ios',
        macAppStoreId: 'configured-mac',
      );

      expect(
        await _subject(
          platform: StorePlatform.macOS,
          appStoreId: 'explicit-ios',
        ).storeId(),
        'explicit-ios',
      );
    });

    test(
      'a configured macAppStoreId still wins where nothing is explicit',
      () async {
        FlutterStoreListing.configure(
          platform: StorePlatform.macOS,
          appStoreId: 'configured-ios',
          macAppStoreId: 'configured-mac',
        );

        expect(await FlutterStoreListing.instance.storeId(), 'configured-mac');
      },
    );

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

    test('a reply of the wrong type degrades instead of throwing', () async {
      // The call used to be `invokeMethod<String>`, which casts the reply — so
      // a native side answering `true` threw a TypeError past both catch
      // clauses and out of a method whose contract forbids throwing. That is
      // exactly the version-skew case the fall-back-on-unrecognised-reply
      // branch exists for; an unrecognised reply *type* is an unrecognised
      // reply. It falls through to url_launcher, unmocked here, hence false
      // rather than a throw.
      mockNative((call) async => true);
      await expectLater(launcher.openStoreListing(uri), completion(isFalse));
    });

    test('an unrecognised string also degrades', () async {
      mockNative((call) async => 'somethingNewFromAFutureKotlin');
      await expectLater(launcher.openStoreListing(uri), completion(isFalse));
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

    test('is available on both Apple platforms and nowhere else', () async {
      // The prompt is behind the same interface the Play package would
      // implement, which is what makes it reachable from a test at all — up
      // to 1.4.0 it was a static const MethodChannel with no seam.
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).isAvailable(),
        isTrue,
      );
      // False until 2.1, which added the native macOS implementation. The
      // widening is deliberately not hidden behind a flag: a caller gating UI
      // on `isInAppReviewSupported` gains a working prompt, and one that was
      // relying on the fallback gets the native dialog instead of a web page.
      expect(
        await const StoreKitInAppReview(StorePlatform.macOS).isAvailable(),
        isTrue,
      );
      expect(
        await const StoreKitInAppReview(StorePlatform.android).isAvailable(),
        isFalse,
      );
      expect(
        await const StoreKitInAppReview(
          StorePlatform.unsupported,
        ).isAvailable(),
        isFalse,
      );
    });

    test('reports that the request reached StoreKit', () async {
      mockNative((call) async => 'requested');
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
        InAppReviewRequest.requested,
      );
    });

    test('maps a missing scene to notNow, not to unavailable', () async {
      // The distinction the whole third signal exists for: nothing was shown,
      // but the prompt is there and will work once the app is foreground. The
      // facade must not substitute the store listing for this.
      mockNative((call) async => 'noActiveScene');
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
        InAppReviewRequest.notNow,
      );
    });

    test('maps macOS\'s missing presenter to unavailable, not notNow', () async {
      // The opposite of the test above, deliberately. macOS answers
      // `noPresenter` when there is no visible window to present into, and
      // that is *not* the transient state `noActiveScene` describes: a Mac app
      // with no window need never grow one. The fallback opens the Mac App
      // Store, a separate process that needs no window in this app, so it can
      // still do something — which `notNow` would have prevented, leaving such
      // a host worse off on 2.1 than it was on 2.0.
      mockNative((call) async => 'noPresenter');
      expect(
        await const StoreKitInAppReview(StorePlatform.macOS).requestReview(),
        InAppReviewRequest.unavailable,
      );
    });

    test('a null reply is unavailable rather than a TypeError', () async {
      // Regression test: 1.4.0 cast the reply with `as bool`, so a null threw.
      mockNative((call) async => null);
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
        InAppReviewRequest.unavailable,
      );
    });

    test('a reply this version cannot read is unavailable', () async {
      // Degrades like the launcher's, and `unavailable` rather than `notNow`
      // so the fallback still runs: a reply we cannot read is not a promise
      // that waiting will help.
      mockNative((call) async => true);
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
        InAppReviewRequest.unavailable,
      );
    });

    test(
      'a missing native implementation is unavailable, so the fallback runs',
      () async {
        // Not an exception out of requestReview: up to 1.4.0 this propagated,
        // because _invokeRequestReview had no try/catch at all.
        //
        // And `unavailable`, not `notNow`: a host that was not rebuilt is not
        // a transient condition, so this is exactly the case the fallback is
        // for. §2.6 asks for both behaviours, which is why a bool could not
        // carry them.
        mockNative((call) async => throw MissingPluginException());
        expect(
          await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
          InAppReviewRequest.unavailable,
        );
      },
    );

    test('a platform exception is unavailable too', () async {
      mockNative((call) async => throw PlatformException(code: 'whatever'));
      expect(
        await const StoreKitInAppReview(StorePlatform.iOS).requestReview(),
        InAppReviewRequest.unavailable,
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

    test('has exactly the seven values the suite asserts', () {
      // A tripwire on the count, and nothing more than that: it cannot tell
      // whether a value is reachable, and it still passes if one is renamed.
      // What establishes reachability is that each of the seven is asserted by
      // a test above — inAppReviewRequested, storeListingOpened,
      // unsupportedPlatform, inAppReviewUnavailable, inAppReviewNotNow,
      // storeIdUnavailable and launchRefused. Adding an eighth fails here,
      // which is the prompt to give it a home.
      expect(StoreListingOutcome.values, hasLength(7));
    });
  });

  group('the platform mapping behind StorePlatform.current', () {
    // The original bug's own site, and the last part of the library the
    // conditional import hid from the suite. `resolveStorePlatform` takes the
    // OS name so the mapping itself can be asserted.
    test('maps the three store platforms, and nothing else', () {
      expect(resolveStorePlatform('android'), StorePlatform.android);
      expect(resolveStorePlatform('ios'), StorePlatform.iOS);
      expect(resolveStorePlatform('macos'), StorePlatform.macOS);
      for (final os in ['linux', 'windows', 'fuchsia', 'web', '', 'iOS']) {
        expect(resolveStorePlatform(os), StorePlatform.unsupported, reason: os);
      }
    });

    test('nothing falls through to Android, which is what 1.4.0 did', () {
      // Up to 1.4.0 the `else` branch *was* Android, so each of these built a
      // Google Play URL — from an App Store id, on macOS.
      for (final os in ['macos', 'linux', 'windows', 'web']) {
        expect(
          resolveStorePlatform(os),
          isNot(StorePlatform.android),
          reason: os,
        );
      }
    });
  });
}
