#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'flutter_store_listing'
  s.version          = '1.3.0'
  s.summary          = 'Open store listings and request App Store reviews.'
  s.description      = <<-DESC
Flutter plugin to handle app reviews with SKStoreReviewController, generate
app store links and open them for iOS or Android.
                       DESC
  s.homepage         = 'https://github.com/hpoul/flutter_store_listing'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Herbert Poul' => 'herbert@codeux.design' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.frameworks = 'StoreKit'

  s.ios.deployment_target = '13.0'
end
