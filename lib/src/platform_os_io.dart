import 'dart:io' as io;

/// The host operating system, in the spelling `dart:io` uses:
/// `android`, `ios`, `macos`, `linux`, `windows`, `fuchsia`.
///
/// Deliberately `dart:io`'s own value rather than Flutter's
/// `defaultTargetPlatform`. The question this answers is "which store, and is
/// there a method channel on the other side" — and `defaultTargetPlatform`
/// answers a different one, since it reports the platform Flutter is
/// *emulating*. An app that sets `debugDefaultTargetPlatformOverride` would
/// otherwise make us invoke an iOS-only method channel on Android.
///
/// See `platform_os_web.dart` for the counterpart the web build gets.
String get operatingSystem => io.Platform.operatingSystem;
