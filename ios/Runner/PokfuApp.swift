import SwiftUI
import UserNotifications

@main
struct PokfuApp: App {
    @UIApplicationDelegateAdaptor(PokfuAppDelegate.self) private var delegate
    @StateObject private var state = PokfuAppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(defaultTab: state.settings.int(SettingKey.defaultTab))
                .environmentObject(state)
                .task { state.start() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { state.start() }
        }
    }
}

final class PokfuAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
