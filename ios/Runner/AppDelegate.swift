import Flutter
import UIKit
import Stripe

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(_ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    STPAPIClient.shared.publishableKey = "pk_test_51TEACkDQs85qYTWQ..."
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
