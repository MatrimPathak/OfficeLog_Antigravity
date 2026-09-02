import Flutter
import UIKit
import native_geofence
import workmanager_apple
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    GMSServices.provideAPIKey(mapsApiKey)

    // Register for foreground notifications
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    // Used by plugin: native_geofence
    NativeGeofencePlugin.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
    }

    // Used by plugin: workmanager. BGTaskScheduler only delivers a task to a
    // relaunched app if its launch handler was registered before this method
    // returns. Under the UIScene lifecycle (which this app uses — see
    // Info.plist), Flutter registers plugins during scene connection, which
    // happens too late for the plugin's own automatic hook to re-register
    // handlers scheduled in a previous session. This call is the workaround
    // the plugin itself documents for UIScene apps. See
    // docs/AUTO_ATTENDANCE_DESIGN.md section 6.2.
    WorkmanagerPlugin.registerLaunchHandlers()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
