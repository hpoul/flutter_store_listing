## 1.3.0

* Allow `package_info_plus` 10.x (widened to `>=1.0.3 <11.0.0`).
* Remove the discontinued `pedantic` dependency (it was unused, and declared
  as a runtime instead of a dev dependency).
* iOS: use `https` for the iTunes lookup API — App Transport Security blocks
  cleartext `http` by default.
* iOS: generate store listing URLs for `apps.apple.com` without a hardcoded
  `/us/` storefront, instead of the legacy `itunes.apple.com/us/app/id…` form.
* Declare honest `environment` minimums (Dart 3.8 / Flutter 3.32) and give the
  iOS podspec real metadata and a 13.0 deployment target.
* Android: raise `minSdkVersion` to the Flutter floor, use the AGP 8 `lint`
  block and drop the obsolete `android.enableJetifier`.

## 1.2.0

* Update AGB Version, Android SDK Version, etc.

## 1.1.0

* Compatibility with Flutter 3.29

## 1.0.0

* Upgrade `package_info_plus` dependency.

## 0.3.1

* Upgrade dependencies.

## 0.3.0

* Upgrade dependencies
* Android: Upgrade to AGP 8.1, migrate namespace, etc.

## 0.2.2

* Update dependencies, dart 3.0

## 0.2.1+1

* Update dependencies.

## 0.2.1

* update to dependency `package_info_plus`

## 0.2.0+1

* Remove unnecessary casts.

## 0.2.0

* Nullsafety migration.

## 0.1.1+2

* More documentation, updated links.
* No longer a singleton, override app store id and android package name.
* Add isSupported() methods.
* Made API more consistent.
* Added simple example.

## 0.1.0

* First release

## 0.0.1

* Initial version

