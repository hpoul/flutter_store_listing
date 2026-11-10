#if os(macOS)
  import AppKit
  import FlutterMacOS
#else
  import Flutter
  import UIKit
#endif

import StoreKit

/// The StoreKit review prompt for iOS and macOS.
///
/// One source file for both, which is what `sharedDarwinSource: true` in
/// `pubspec.yaml` is for. The alternative was a `macos/` directory holding a
/// symlink or a copy, and the review prompt is the one part of this package
/// where the two platforms genuinely differ — iOS presents into a
/// `UIWindowScene`, macOS into an `NSViewController` — so the difference is
/// worth having in one place where both halves are visible at once.
public class FlutterStoreListingPlugin: NSObject, FlutterPlugin {
  #if os(macOS)
    /// The registrar, kept so that `viewController` can be read when a review
    /// is actually requested.
    ///
    /// The view controller itself is deliberately **not** stored: the registrar
    /// documents that a plugin should not hold a strong reference to it, and it
    /// can legitimately change or go away while the app runs — on macOS a
    /// window can be closed without the app quitting.
    ///
    /// Holding the registrar strongly does form a retain cycle through the
    /// engine, which holds the method call handler that holds this instance.
    /// That is accepted rather than worked around with a `weak` reference: the
    /// cycle costs one object for the lifetime of a process that keeps the
    /// engine alive anyway, whereas a registrar that turned out not to be
    /// retained elsewhere would make the prompt silently stop working.
    private let registrar: FlutterPluginRegistrar

    private init(registrar: FlutterPluginRegistrar) {
      self.registrar = registrar
      super.init()
    }
  #endif

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
      // macOS declares `messenger` as a property where iOS declares it as a
      // method, and only macOS needs the registrar after this point.
      let messenger = registrar.messenger
      let instance = FlutterStoreListingPlugin(registrar: registrar)
    #else
      let messenger = registrar.messenger()
      let instance = FlutterStoreListingPlugin()
    #endif
    let channel = FlutterMethodChannel(
      name: "flutter_store_listing",
      binaryMessenger: messenger
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    // `isSupportedRequestReview` is gone: it answered `true` unconditionally,
    // so Dart paid a channel round trip for a constant. `isInAppReviewSupported`
    // is a synchronous getter there now, and whether a prompt can actually be
    // shown is resolved by `requestReview` below, which is the only place it
    // can honestly be known.
    case "requestReview":
      requestReview(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Asks StoreKit to show the review prompt.
  ///
  /// Answers with a status string rather than a bool, because the two ways
  /// this can fail want opposite handling on the Dart side and a bool could
  /// only carry one of them:
  ///
  /// * `requested` — handed to StoreKit. Not a promise that a prompt appeared:
  ///   StoreKit decides that, and rate-limits it per user and per app version
  ///   without telling the caller either way.
  /// * `noActiveScene` (iOS) / `noPresenter` (macOS) — there was nothing to
  ///   present in, so nothing was asked for. Dart reports `inAppReviewNotNow`
  ///   for either and deliberately runs **no** fallback: the state is
  ///   transient, and sending the user to the App Store because the app was
  ///   mid-launch is worse than doing nothing.
  ///
  /// The two spellings are kept apart rather than unified under one neutral
  /// name because the Dart half has to keep reading `noActiveScene` regardless:
  /// upgrading this package without rebuilding the host leaves an older
  /// compiled plugin answering a newer Dart side. Adding a value only the new
  /// native code sends is safe in that direction; renaming one is not.
  ///
  /// A missing plugin registration is the case that *should* fall back, and it
  /// never reaches this method — Dart sees `MissingPluginException` instead.
  private func requestReview(result: @escaping FlutterResult) {
    Task { @MainActor in
      #if os(macOS)
        if #available(macOS 13.0, *) {
          // Read now rather than at registration: see `registrar` above.
          guard let controller = registrar.viewController else {
            result("noPresenter")
            return
          }
          AppStore.requestReview(in: controller)
        } else {
          // No presenter is needed below macOS 13, so no guard either — the
          // deprecated API finds the key window itself.
          Self.legacyRequestReview()
        }
      #else
        guard let scene = Self.activeWindowScene() else {
          result("noActiveScene")
          return
        }
        if #available(iOS 16.0, *) {
          AppStore.requestReview(in: scene)
        } else {
          Self.legacyRequestReview(in: scene)
        }
      #endif
      result("requested")
    }
  }

  #if os(macOS)
    /// `SKStoreReviewController.requestReview()` is deprecated as of macOS 15
    /// in favour of `AppStore.requestReview(in:)`, which needs macOS 13. This
    /// is the fallback for macOS 12, the oldest version Flutter itself
    /// supports.
    ///
    /// Note that the macOS spelling takes no argument at all — it is the
    /// pre-scene `+requestReview`, available since macOS 10.14, and there has
    /// never been a `requestReviewInScene:` on this platform. So the upgrade to
    /// `AppStore.requestReview(in:)` is where macOS *gains* a presenter
    /// parameter, rather than exchanging one for another as iOS did.
    ///
    /// Marking the helper deprecated is what keeps the deprecation warning from
    /// propagating to the caller: an availability check alone does not silence
    /// it, because the symbol is deprecated at every version it is available
    /// at.
    @available(macOS, introduced: 12.0, deprecated: 13.0)
    @MainActor
    private static func legacyRequestReview() {
      SKStoreReviewController.requestReview()
    }
  #else
    /// `SKStoreReviewController` is deprecated as of iOS 18 in favour of
    /// `AppStore.requestReview(in:)`, which needs iOS 16. This is the fallback
    /// for iOS 15, the oldest version Flutter itself supports.
    ///
    /// `introduced:` must not claim anything below 14.0 — `requestReview(in:)`
    /// is itself iOS 14.0+ (`API_DEPRECATED(..., ios(14.0, 18.0))`), so a lower
    /// bound here is a compile error rather than a wider floor.
    ///
    /// Marking the helper deprecated is what keeps the deprecation warning from
    /// propagating to the caller: an availability check alone does not silence
    /// it, because the symbol is deprecated at every version it is available
    /// at.
    @available(iOS, introduced: 15.0, deprecated: 16.0)
    @MainActor
    private static func legacyRequestReview(in scene: UIWindowScene) {
      SKStoreReviewController.requestReview(in: scene)
    }

    /// The foreground-active window scene, or nil.
    ///
    /// Deliberately *only* the foreground-active one. This used to fall back to
    /// `scenes.first`, and `connectedScenes` is a `Set`, so that was an
    /// arbitrary member — the prompt was then presented into a possibly
    /// background scene and success reported for it. Returning nil instead makes
    /// the caller report `noActiveScene`, which Dart answers by doing nothing and
    /// saying so, rather than by substituting the store listing.
    ///
    /// macOS has no equivalent check. `NSViewController` carries no activation
    /// state, and the registrar's own view controller is the one hosting the
    /// Flutter content, so there is no set to pick the right member out of.
    @MainActor
    private static func activeWindowScene() -> UIWindowScene? {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      return scenes.first { $0.activationState == .foregroundActive }
    }
  #endif
}
