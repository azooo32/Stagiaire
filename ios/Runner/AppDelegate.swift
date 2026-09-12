import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  // نگه‌داری فیلدهای secure برای هر UIWindow جداگانه
  private var secureFields: [UIWindow: UITextField] = [:]
  private var isSecureEnabled: Bool = false
  private var pollTimer: Timer?
  private var securityChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.invetstecur.stagiaire/security",
      binaryMessenger: controller.binaryMessenger
    )
    self.securityChannel = channel

    channel.setMethodCallHandler({ [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "enableSecure":
        DispatchQueue.main.async {
          self.enableSecureOnAllWindows()
          result(true)
        }
      case "disableSecure":
        DispatchQueue.main.async {
          self.disableSecureOnAllWindows()
          result(true)
        }
      case "isCaptured":
        if #available(iOS 11.0, *) {
          result(UIScreen.main.isCaptured)
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    // --- الإشعار الرسمي من iOS ---
    if #available(iOS 11.0, *) {
      NotificationCenter.default.addObserver(
        forName: UIScreen.capturedDidChangeNotification,
        object: nil,
        queue: OperationQueue.main
      ) { [weak self] _ in
        self?.handleCaptureChange()
      }
    }

    // --- استمع لإنشاء UIWindows جديدة (مثلاً عند Split View) ---
    if #available(iOS 13.0, *) {
      NotificationCenter.default.addObserver(
        forName: UIWindow.didBecomeVisibleNotification,
        object: nil,
        queue: OperationQueue.main
      ) { [weak self] notification in
        guard let self = self, self.isSecureEnabled else { return }
        if let newWindow = notification.object as? UIWindow {
          self.addSecureField(to: newWindow)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - تفعيل الحماية على جميع الـ UIWindows

  private func enableSecureOnAllWindows() {
    isSecureEnabled = true

    // أضف secureField لكل UIWindow موجود حالياً
    for window in getAllWindows() {
      addSecureField(to: window)
    }

    // ابدأ Polling كل ثانية كخط دفاع ثانٍ (يغطي Split View / Slide Over)
    startPolling()
  }

  private func disableSecureOnAllWindows() {
    isSecureEnabled = false
    stopPolling()

    // أزل جميع secureFields من جميع الـ windows
    for (window, field) in secureFields {
      _ = window  // suppress unused warning
      field.removeFromSuperview()
    }
    secureFields.removeAll()
  }

  // MARK: - إضافة/إزالة secureField من UIWindow معيّن

  private func addSecureField(to window: UIWindow) {
    // تجنّب التكرار
    guard secureFields[window] == nil else { return }

    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.frame = CGRect.zero
    window.addSubview(field)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
    field.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true

    secureFields[window] = field
  }

  // MARK: - جلب جميع UIWindows (iOS 13+ يستخدم UIWindowScene)

  private func getAllWindows() -> [UIWindow] {
    if #available(iOS 13.0, *) {
      return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
    } else {
      return UIApplication.shared.windows
    }
  }

  // MARK: - Polling كخط دفاع ثانٍ

  private func startPolling() {
    stopPolling()
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.handleCaptureChange()
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
  }

  private func stopPolling() {
    pollTimer?.invalidate()
    pollTimer = nil
  }

  private func handleCaptureChange() {
    guard #available(iOS 11.0, *) else { return }
    let isCaptured = UIScreen.main.isCaptured
    DispatchQueue.main.async { [weak self] in
      self?.securityChannel?.invokeMethod("onScreenCaptureChanged", arguments: isCaptured)
    }
  }
}
