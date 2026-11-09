import 'package:flutter_store_listing/flutter_store_listing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the plugin asked the launcher to do, so tests can assert on it
/// without a method channel or a real browser.
class _RecordingLauncher {
  _RecordingLauncher({this.canLaunch = true});

  /// What [FlutterStoreListing.urlCanLaunch] should answer.
  final bool canLaunch;

  final launched = <String>[];
  final canLaunchQueries = <String>[];

  Future<bool> urlCanLaunch(String url) async {
    canLaunchQueries.add(url);
    return canLaunch;
  }

  Future<bool> urlLaunch(String url) async {
    launched.add(url);
    return true;
  }
}

FlutterStoreListing _subject(
  _RecordingLauncher launcher, {
  String? iosAppId,
  String? androidPackageName,
}) => FlutterStoreListing.customize(
  forceIosAppId: iosAppId,
  forceAndroidPackageName: androidPackageName,
  urlCanLaunch: launcher.urlCanLaunch,
  urlLaunch: launcher.urlLaunch,
);

void main() {
  group('store listing URLs', () {
    final subject = FlutterStoreListing.customize();

    test('iOS uses apps.apple.com without a hardcoded storefront', () {
      // Regression test: this used to be the legacy
      // `itunes.apple.com/us/app/id...` form, which pinned every user to the
      // US store.
      expect(
        subject.getIosStoreListing('1479297675'),
        'https://apps.apple.com/app/id1479297675',
      );
    });

    test('iOS listing honours a custom protocol', () {
      expect(
        subject.getIosStoreListing('1479297675', protocol: 'itms-apps'),
        'itms-apps://apps.apple.com/app/id1479297675',
      );
    });

    test('android uses the play store details URL', () {
      expect(
        subject.getAndroidStoreListing('design.codeux.authpass'),
        'https://play.google.com/store/apps/details?id=design.codeux.authpass',
      );
    });
  });

  group('launchStoreListing on a non-iOS platform', () {
    // The test VM reports `macos`, so these exercise the non-iOS branch.
    // The iOS branch needs a real iOS host, since the platform is resolved
    // through a conditional import rather than an injectable seam.

    test(
      'prefers the market:// URL when the play store can handle it',
      () async {
        final launcher = _RecordingLauncher(canLaunch: true);
        final result = await _subject(
          launcher,
          androidPackageName: 'design.codeux.authpass',
        ).launchStoreListing();

        expect(result, isTrue);
        expect(launcher.canLaunchQueries, ['market://']);
        expect(launcher.launched, [
          'market://details?id=design.codeux.authpass',
        ]);
      },
    );

    test('falls back to the https URL when market:// cannot launch', () async {
      final launcher = _RecordingLauncher(canLaunch: false);
      await _subject(
        launcher,
        androidPackageName: 'design.codeux.authpass',
      ).launchStoreListing();

      expect(launcher.launched, [
        'https://play.google.com/store/apps/details?id=design.codeux.authpass',
      ]);
    });

    test('honours forceAndroidPackageName', () async {
      // Regression test: launchStoreListing used to read the package name
      // straight from package_info_plus, silently ignoring this override.
      final launcher = _RecordingLauncher(canLaunch: false);
      await _subject(
        launcher,
        androidPackageName: 'com.example.override',
      ).launchStoreListing();

      expect(launcher.launched, [
        'https://play.google.com/store/apps/details?id=com.example.override',
      ]);
    });
  });

  group('platform support', () {
    test('native review requests are iOS-only', () async {
      // macOS on the test VM, so this is the "not iOS" answer.
      expect(
        await FlutterStoreListing().isSupportedNativeRequestReview(),
        isFalse,
      );
    });

    test('isSupported is limited to the two mobile stores', () async {
      expect(await FlutterStoreListing().isSupported(), isFalse);
    });

    test('launchRequestReview with onlyNative does nothing off iOS', () async {
      final launcher = _RecordingLauncher();
      final result = await _subject(
        launcher,
        androidPackageName: 'design.codeux.authpass',
      ).launchRequestReview(onlyNative: true);

      expect(result, isFalse);
      expect(launcher.launched, isEmpty);
    });

    test('launchRequestReview without onlyNative opens the store', () async {
      final launcher = _RecordingLauncher(canLaunch: false);
      final result = await _subject(
        launcher,
        androidPackageName: 'design.codeux.authpass',
      ).launchRequestReview();

      expect(result, isTrue);
      // Exactly one launch, not two: the native prompt and the store listing
      // are exclusive. This is the testable half of that guarantee — the iOS
      // half (a successful native prompt must *not* also open the store) needs
      // a host reporting `ios`, which the conditional-import platform global
      // does not allow a test to fake.
      expect(launcher.launched, [
        'https://play.google.com/store/apps/details?id=design.codeux.authpass',
      ]);
    });
  });

  group('getIosAppId', () {
    test('returns the forced id without hitting the network', () async {
      expect(
        await FlutterStoreListing.customize(
          forceIosAppId: '1479297675',
        ).getIosAppId(),
        '1479297675',
      );
    });
  });

  group('getAndroidPackageName', () {
    test('returns the forced package name', () async {
      expect(
        await FlutterStoreListing.customize(
          forceAndroidPackageName: 'com.example.app',
        ).getAndroidPackageName(),
        'com.example.app',
      );
    });
  });
}
