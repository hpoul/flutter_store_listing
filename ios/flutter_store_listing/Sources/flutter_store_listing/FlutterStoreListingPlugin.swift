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
    case "isSupportedRequestReview":
      // Every deployment target this plugin supports can request a review.
      result(true)
    case "requestReview":
      requestReview(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Asks StoreKit to show the review prompt.
  ///
  /// Reports `false` only when there is no window scene to present in. A `true`
  /// result means the request was handed to StoreKit, not that a prompt was
  /// actually shown: StoreKit decides that, and rate-limits it per user and
  /// per app version without telling the caller either way.
  private func requestReview(result: @escaping FlutterResult) {
    Task { @MainActor in
      guard let scene = Self.activeWindowScene() else {
        result(false)
        return
      }
      if #available(iOS 16.0, *) {
        AppStore.requestReview(in: scene)
      } else {
        Self.legacyRequestReview(in: scene)
      }
      result(true)
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

  /// The scene to present the prompt in: the foreground-active one where
  /// possible, otherwise any connected window scene.
  @MainActor
  private static func activeWindowScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
  }
}
