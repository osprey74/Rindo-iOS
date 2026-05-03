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
                    await auth.restoreSession()
                }
        }
        .modelContainer(for: [ImportedRoute.self, RideLog.self])
    }
}
