#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_store_listing.podspec` to validate before publishing.
#
# This podspec is for consumers still building with CocoaPods. Projects using
# Swift Package Manager resolve flutter_store_listing/Package.swift instead;
# both build the same sources.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_store_listing'
  s.version          = '1.3.0'
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
  s.dependency 'Flutter'
  s.frameworks = 'StoreKit'

  s.ios.deployment_target = '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
