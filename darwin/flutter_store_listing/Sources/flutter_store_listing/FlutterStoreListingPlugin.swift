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
    /// The view controller itself is deliberately **not** stored: the
    /// registrar's own header says a plugin should not hold a strong reference
    /// to it, and it can be attached after registration or replaced while the
    /// app runs.
    ///
    /// Holding the registrar strongly is safe and costs nothing. The engine
    /// retains every registrar it creates, and `FlutterEngineRegistrar` holds
    /// its engine *weakly*, so the chain engine → channel handler → plugin →
    /// registrar is not a cycle.
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
  /// Answers with a status string rather than a bool, because the ways this
  /// can fail want different handling on the Dart side and a bool could only
  /// carry one of them:
  ///
  /// * `requested` — handed to StoreKit. Not a promise that a prompt appeared:
  ///   StoreKit decides that, and rate-limits it per user and per app version
  ///   without telling the caller either way.
  /// * `noActiveScene` (iOS) — no window scene was foreground-active, so
  ///   nothing was asked for. Dart reports `inAppReviewNotNow` and runs **no**
  ///   fallback: the state is transient — a launch transition, a system alert,
  ///   an unfocused iPad window — and sending the user to the App Store
  ///   because the app was still waking up is worse than doing nothing.
  /// * `noPresenter` (macOS) — there is no visible window to present into.
  ///   Dart reports `inAppReviewUnavailable` and the fallback **does** run.
  ///
  /// The two failures are spelled differently because they mean different
  /// things, which is easy to miss: both describe "nowhere to present", but
  /// only the iOS one is transient. A Mac app with no visible window may never
  /// grow one, and the macOS fallback opens the Mac App Store — a separate
  /// process that needs no window in this app — so suppressing it would leave
  /// such a host with no way to ask for a review at all.
  ///
  /// A missing plugin registration is a third case that should fall back, and
  /// it never reaches this method — Dart sees `MissingPluginException`.
  private func requestReview(result: @escaping FlutterResult) {
    Task { @MainActor in
      #if os(macOS)
        guard let controller = Self.visiblePresenter(for: registrar) else {
          result("noPresenter")
          return
        }
        if #available(macOS 13.0, *) {
          AppStore.requestReview(in: controller)
        } else {
          // The pre-scene API, available since macOS 10.14 and deprecated at
          // 15. It takes no presenter and finds the key window itself, but it
          // is reached through the same guard as the modern call so that the
          // two macOS paths answer the same question about the same state.
          //
          // No `@available` dance is needed to keep the deprecation warning
          // quiet: the `else` branch of an `#available` check narrows the
          // availability context to below macOS 13, where this symbol is not
          // yet deprecated, so the call is silent even when a consuming app
          // raises its deployment target past 15.
          SKStoreReviewController.requestReview()
        }
      #else
        guard let scene = Self.activeWindowScene() else {
          result("noActiveScene")
          return
        }
        if #available(iOS 16.0, *) {
          AppStore.requestReview(in: scene)
        } else {
          // Silent for the same reason as the macOS call above: inside this
          // branch the context is below iOS 16, and this is deprecated at 18.
          SKStoreReviewController.requestReview(in: scene)
        }
      #endif
      result("requested")
    }
  }

  #if os(macOS)
    /// The view controller to present into, or nil when there is no visible
    /// window.
    ///
    /// Both halves of that matter. `viewController` is nil only when the
    /// Flutter view controller was never attached or has been deallocated — a
    /// headless engine — and it stays non-nil for a window that is closed,
    /// hidden or minimised. Presenting into one of those and reporting success
    /// is the iOS bug `activeWindowScene()` below exists to avoid, so macOS
    /// checks the window too rather than trusting the controller's existence.
    ///
    /// `isViewLoaded` is checked before `view` so that reading the window
    /// cannot force `loadView` on a controller that has not loaded one.
    /// AppKit's `viewIfLoaded` says that in one expression, but it is macOS
    /// 14+ — unlike the UIKit property of the same name, which is iOS 9+ —
    /// and this has to work at the macOS 12 floor.
    @MainActor
    private static func visiblePresenter(
      for registrar: FlutterPluginRegistrar
    ) -> NSViewController? {
      guard let controller = registrar.viewController,
        controller.isViewLoaded,
        controller.view.window?.isVisible == true
      else {
        return nil
      }
      return controller
    }
  #else
    /// The foreground-active window scene, or nil.
    ///
    /// Deliberately *only* the foreground-active one. This used to fall back to
    /// `scenes.first`, and `connectedScenes` is a `Set`, so that was an
    /// arbitrary member — the prompt was then presented into a possibly
    /// background scene and success reported for it. Returning nil instead makes
    /// the caller report `noActiveScene`, which Dart answers by doing nothing and
    /// saying so, rather than by substituting the store listing.
    @MainActor
    private static func activeWindowScene() -> UIWindowScene? {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      return scenes.first { $0.activationState == .foregroundActive }
    }
  #endif
}
