import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    let channel = FlutterMethodChannel(
      name: "asa/notifications",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "openNotificationSettings" || call.method == "openAppSettings" || call.method == "getTimeZoneId" else {
        result(FlutterMethodNotImplemented)
        return
      }

      if call.method == "getTimeZoneId" {
        result(TimeZone.current.identifier)
        return
      }

      let settingsURL: URL?
      if call.method == "openNotificationSettings", #available(iOS 15.4, *) {
        settingsURL = URL(string: UIApplication.openNotificationSettingsURLString)
      } else {
        settingsURL = URL(string: UIApplication.openSettingsURLString)
      }
      guard let settingsURL else {
        result(false)
        return
      }
      UIApplication.shared.open(settingsURL, options: [:]) { opened in
        result(opened)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
