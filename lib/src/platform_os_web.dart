/// The host operating system, always `'web'` here.
///
/// The web counterpart of `platform_os_io.dart`, which exists so that this
/// package need not import `dart:io` unconditionally. That import is what made
/// the whole package report as WebAssembly-incompatible before 1.3.0.
///
/// Returns a value rather than throwing. `'web'` maps to
/// `StorePlatform.unsupported`, so every entry point reports
/// `StoreListingOutcome.unsupportedPlatform` and nothing touches a method
/// channel that has no native side here. Throwing would instead turn a
/// supported-platform check into a crash.
String get operatingSystem => 'web';
