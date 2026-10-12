import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushToken.setAPNsToken(deviceToken)
    }

    // Show notifications while the app is open, like the Android app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

/// Each school keeps its existing Firebase project (the same one its Android app uses), so the server
/// sends iPhone notifications exactly as it does for Android. Firebase is configured for the selected
/// school's project the first time a token is needed; method swizzling is off (Info.plist), so the
/// APNs token is handed to Firebase here.
@MainActor
enum PushToken {
    private static var apnsToken: Data?

    static func setAPNsToken(_ token: Data) {
        apnsToken = token
        if FirebaseApp.app() != nil {
            Messaging.messaging().apnsToken = token
        }
    }

    /// The FCM token passed to the portal as `&fcm=`, same as Android.
    /// Returns nil if the school has no Firebase settings or no token arrives in time (the portal still loads).
    static func fetch(for school: School, timeout: TimeInterval = 6) async -> String? {
        guard let config = school.firebase else { return nil }

        if let app = FirebaseApp.app() {
            // Firebase can only be set up once per launch. After switching to a school in the other
            // project, notifications start working from the next app launch.
            guard app.options.gcmSenderID == config.gcmSenderId else { return nil }
        } else {
            let options = FirebaseOptions(googleAppID: config.googleAppId, gcmSenderID: config.gcmSenderId)
            options.apiKey = config.apiKey
            options.projectID = config.projectId
            FirebaseApp.configure(options: options)
            if let apnsToken {
                Messaging.messaging().apnsToken = apnsToken
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        // token() fails until APNs has handed us a device token, so retry briefly.
        while Date() < deadline {
            if let token = try? await Messaging.messaging().token() { return token }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }
}
