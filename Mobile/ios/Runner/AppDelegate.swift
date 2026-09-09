import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private let pushMethodChannel = "com.hexing.zhilian/push"
  private let pushEventChannel = "com.hexing.zhilian/push/events"
  private let pushProviderKey = "mobile_push_provider"
  private let pushTokenKey = "mobile_push_token"
  private var pushEventSink: FlutterEventSink?
  private var initialTargetRoute: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let payload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      initialTargetRoute = targetRoute(payload)
    }
    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.delegate = self
    notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      guard granted else { return }
      DispatchQueue.main.async { application.registerForRemoteNotifications() }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MobilePushBridge")
    let methodChannel = FlutterMethodChannel(
      name: pushMethodChannel,
      binaryMessenger: registrar.messenger()
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "getToken":
        result(self.currentPushToken())
      case "getInitialNotification":
        result(self.initialTargetRoute)
        self.initialTargetRoute = nil
      case "getNotificationPermission":
        self.notificationPermissionState(result)
      case "requestNotificationPermission":
        self.requestNotificationPermission(result)
      case "openNotificationSettings":
        self.openNotificationSettings(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(
      name: pushEventChannel,
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(self)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    let defaults = UserDefaults.standard
    defaults.set("apns", forKey: pushProviderKey)
    defaults.set(token, forKey: pushTokenKey)
    pushEventSink?([
      "type": "token",
      "platform": "ios",
      "provider": "apns",
      "token": token,
    ])
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let route = targetRoute(response.notification.request.content.userInfo) {
      if pushEventSink == nil {
        initialTargetRoute = route
      } else {
        pushEventSink?(["type": "notification", "targetRoute": route])
      }
    }
    completionHandler()
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .badge, .sound])
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    pushEventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    pushEventSink = nil
    return nil
  }

  private func currentPushToken() -> [String: String]? {
    let defaults = UserDefaults.standard
    let provider = defaults.string(forKey: pushProviderKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let token = defaults.string(forKey: pushTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !provider.isEmpty, !token.isEmpty else { return nil }
    return ["platform": "ios", "provider": provider, "token": token]
  }

  private func notificationPermissionState(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let state: String
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        state = "granted"
      case .notDetermined:
        state = "notDetermined"
      case .denied:
        state = "denied"
      @unknown default:
        state = "unavailable"
      }
      DispatchQueue.main.async { result(state) }
    }
  }

  private func requestNotificationPermission(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      granted, _ in
      if granted {
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
      }
      DispatchQueue.main.async { result(granted ? "granted" : "denied") }
    }
  }

  private func openNotificationSettings(_ result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      return result(false)
    }
    DispatchQueue.main.async {
      UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
    }
  }

  private func targetRoute(_ payload: [AnyHashable: Any]) -> String? {
    let candidates = ["targetRoute", "target_route", "im_target_route"]
    for key in candidates {
      if let route = normalizeTargetRoute(payload[key] as? String) { return route }
    }
    if let data = payload["data"] as? [AnyHashable: Any] {
      return targetRoute(data)
    }
    return nil
  }

  private func normalizeTargetRoute(_ value: String?) -> String? {
    let route = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if ["/messages", "/todos", "/notifications"].contains(route) { return route }
    let uuid = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    guard route.range(of: "^/(chat|approval)/\(uuid)$", options: .regularExpression) != nil else {
      return nil
    }
    return route
  }
}
