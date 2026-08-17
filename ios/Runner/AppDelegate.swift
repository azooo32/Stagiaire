import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var secureField: UITextField?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let securityChannel = FlutterMethodChannel(name: "com.invetstecur.stagiaire/security",
                                              binaryMessenger: controller.binaryMessenger)

    securityChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      if call.method == "enableSecure" {
        DispatchQueue.main.async {
          self.makeWindowSecure()
          result(true)
        }
      } else if call.method == "disableSecure" {
        DispatchQueue.main.async {
          self.makeWindowUnsecure()
          result(true)
        }
      } else if call.method == "isCaptured" {
        if #available(iOS 11.0, *) {
          result(UIScreen.main.isCaptured)
        } else {
          result(false)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    if #available(iOS 11.0, *) {
      NotificationCenter.default.addObserver(
        forName: UIScreen.capturedDidChangeNotification,
        object: nil,
        queue: OperationQueue.main
      ) { _ in
        let isCaptured = UIScreen.main.isCaptured
        securityChannel.invokeMethod("onScreenCaptureChanged", arguments: isCaptured)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func makeWindowSecure() {
    guard secureField == nil, let window = self.window else { return }

    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.frame = CGRect.zero
    window.addSubview(field)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
    field.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true

    self.secureField = field
  }

  private func makeWindowUnsecure() {
    guard let field = secureField else { return }

    field.removeFromSuperview()
    self.secureField = nil
  }

}

