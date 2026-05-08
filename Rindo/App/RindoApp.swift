import SwiftData
import SwiftUI

@main
struct RindoApp: App {
    @State private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environment(auth)
                .task {
                    ReminderManager.requestPermissionIfNeeded()
                }
        }
        .modelContainer(for: [ImportedRoute.self, RideLog.self])
    }
}
