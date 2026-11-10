import Flutter
import StoreKit
import UIKit

public class FlutterStoreListingPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_store_listing",
      binaryMessenger: registrar.messenger()
    )
    let instance = FlutterStoreListingPlugin()
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
  /// * `noActiveScene` — there was no foreground-active window scene to
  ///   present in, so nothing was asked for. Dart reports
  ///   `inAppReviewNotNow` and deliberately runs **no** fallback: the state is
  ///   transient, and sending the user to the App Store because the app was
  ///   mid-launch is worse than doing nothing.
  ///
  /// A missing plugin registration is the case that *should* fall back, and it
  /// never reaches this method — Dart sees `MissingPluginException` instead.
  private func requestReview(result: @escaping FlutterResult) {
    Task { @MainActor in
      guard let scene = Self.activeWindowScene() else {
        result("noActiveScene")
        return
      }
      if #available(iOS 16.0, *) {
        AppStore.requestReview(in: scene)
      } else {
        Self.legacyRequestReview(in: scene)
      }
      result("requested")
    }
  }

  /// `SKStoreReviewController` is deprecated as of iOS 18 in favour of
  /// `AppStore.requestReview(in:)`, which needs iOS 16. This is the fallback
  /// for iOS 15, the oldest version Flutter itself supports.
  ///
  /// `introduced:` must not claim anything below 14.0 — `requestReview(in:)` is
  /// itself iOS 14.0+ (`API_DEPRECATED(..., ios(14.0, 18.0))`), so a lower
  /// bound here is a compile error rather than a wider floor.
  ///
  /// Marking the helper deprecated is what keeps the deprecation warning from
  /// propagating to the caller: an availability check alone does not silence
  /// it, because the symbol is deprecated at every version it is available at.
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
  @MainActor
  private static func activeWindowScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive }
  }
}
