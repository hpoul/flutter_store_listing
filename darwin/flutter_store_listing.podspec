#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_store_listing.podspec` to validate before publishing.
#
# This podspec is for consumers still building with CocoaPods. Projects using
# Swift Package Manager resolve flutter_store_listing/Package.swift instead;
# both build the same sources.
#
# One podspec covers iOS and macOS, which is what `sharedDarwinSource: true` in
# pubspec.yaml asks Flutter for: it looks for darwin/flutter_store_listing.podspec
# for both platforms instead of ios/… and macos/… separately.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_store_listing'
  s.version          = '2.1.0'
  s.summary          = 'Open store listings and request App Store reviews.'
  s.description      = <<-DESC
Flutter plugin to handle app reviews with the StoreKit review API, generate
app store links and open them for iOS or Android.
                       DESC
  s.homepage         = 'https://github.com/hpoul/flutter_store_listing'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Herbert Poul' => 'herbert@codeux.design' }
  s.source           = { :path => '.' }
  s.documentation_url = 'https://pub.dev/packages/flutter_store_listing'
  s.source_files     = 'flutter_store_listing/Sources/flutter_store_listing/**/*.swift'
  s.frameworks = 'StoreKit'

  # Different pods, same Swift module name on each platform: the source does
  # `import Flutter` on iOS and `import FlutterMacOS` on macOS.
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.ios.deployment_target = '15.0'
  # 12.0 is Flutter's own macOS floor. The review prompt needs macOS 13 for
  # `AppStore.requestReview(in:)` and falls back to the deprecated
  # `SKStoreReviewController.requestReview()` below that, rather than raising
  # the floor for a package whose other half is just a URL.
  s.osx.deployment_target = '12.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
