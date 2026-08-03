import FirebaseCore
import PushFire
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The SDK does not call this for you — configure Firebase in your own app.
        FirebaseApp.configure()
        return true
    }
}

@main
struct PushFireExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    do {
                        try await PushFire.configure(
                            PushFireConfiguration(
                                apiKey: ProcessInfo.processInfo
                                    .environment["PUSHFIRE_API_KEY"] ?? "",
                                enableLogging: true
                            )
                        )
                    } catch {
                        print("PushFire configure failed: \(error)")
                    }
                }
        }
    }
}
