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

  group('launchStoreListing on a non-iOS, non-Android platform', () {
    // The test VM reports `macos`, so these exercise the url_launcher branch.
    //
    // Neither of the other two branches is reachable from `flutter test`: the
    // iOS one needs a real iOS host and the Android one goes through the
    // method channel to the native implementation, and the platform itself is
    // resolved through a conditional import rather than an injectable seam, so
    // a test cannot fake it either. The Kotlin side has its own unit tests in
    // `android/src/test`; making the platform injectable is 2.0's job.

    test('opens the https play store URL', () async {
      final launcher = _RecordingLauncher(canLaunch: false);
      final result = await _subject(
        launcher,
        androidPackageName: 'design.codeux.authpass',
      ).launchStoreListing();

      expect(result, isTrue);
      expect(launcher.launched, [
        'https://play.google.com/store/apps/details?id=design.codeux.authpass',
      ]);
    });

    test('makes no canLaunch probe', () async {
      // Regression test for the `market://` probe dropped in 1.4.0. It could
      // not succeed without a `<queries>` entry in the app's manifest, which
      // this package does not ship, so it cost a platform channel round trip
      // to answer false every time. `canLaunch: true` here is what used to
      // divert the user to `market://details?id=...`.
      final launcher = _RecordingLauncher(canLaunch: true);
      await _subject(
        launcher,
        androidPackageName: 'design.codeux.authpass',
      ).launchStoreListing();

      expect(launcher.canLaunchQueries, isEmpty);
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
