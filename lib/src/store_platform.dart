// Not `dart:io` directly: importing it here unconditionally is what made the
// whole package report as WebAssembly-incompatible before 1.3.0. The io branch
// still uses `dart:io`.
import 'platform_os_io.dart'
    if (dart.library.js_interop) 'platform_os_web.dart';

/// The platforms this package distinguishes.
///
/// Up to 1.4.0 the platform came from a compile-time conditional import, so no
/// test could choose one and `macOS`, Windows, Linux and web all fell into the
/// Android branch — which is why a macOS build opened a Google Play web page
/// for a macOS bundle id. A value can be injected, and [unsupported] makes
/// web and desktop explicit rather than "whatever the `else` branch does".
///
/// Spelled `iOS` and `macOS` to match Flutter's own `TargetPlatform`.
///
/// This set is **closed**: no value will be added in a minor release. Writing
/// `switch (StorePlatform.current)` is the pattern this package recommends, so
/// growing it would break the recommendation. If a desktop store ever
/// justifies another value, it is a major release.
enum StorePlatform {
  android,
  iOS,
  macOS,

  /// Everything with no app store: web, Windows, Linux.
  unsupported;

  /// The platform the app is running on.
  ///
  /// Resolved through a conditional import so that importing this package does
  /// not pull in `dart:io`.
  static StorePlatform get current => resolveStorePlatform();
}

/// Maps the host operating system onto a [StorePlatform].
///
/// Reads `dart:io`'s `operatingSystem` rather than Flutter's
/// `defaultTargetPlatform`, deliberately. The question being answered is
/// "which store, and is there a method channel on the other side", while
/// `defaultTargetPlatform` reports the platform Flutter is *emulating*. An app
/// setting `debugDefaultTargetPlatformOverride` would otherwise make this
/// package invoke an iOS-only method channel on Android.
StorePlatform resolveStorePlatform() => switch (operatingSystem) {
  'android' => StorePlatform.android,
  'ios' => StorePlatform.iOS,
  'macos' => StorePlatform.macOS,
  _ => StorePlatform.unsupported,
};
