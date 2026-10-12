import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Push needs GoogleService-Info.plist. Without it the app still works, just without notifications.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        application.registerForRemoteNotifications()
        return true
    }

    // Show notifications while the app is open, like the Android app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

enum PushToken {
    /// The FCM token passed to the portal as `&fcm=`, same as Android.
    /// Returns nil if Firebase isn't configured or no token arrives in time (the portal still loads).
    @MainActor
    static func fetch(timeout: TimeInterval = 6) async -> String? {
        guard FirebaseApp.app() != nil else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        // token() fails until APNs has handed us a device token, so retry briefly.
        while Date() < deadline {
            if let token = try? await Messaging.messaging().token() { return token }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }
}
