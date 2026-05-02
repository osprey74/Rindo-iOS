import Foundation

enum AppConfig {
    #if DEBUG
    static let apiBaseURL = URL(string: "http://localhost:3000")!
    #else
    static let apiBaseURL = URL(string: "https://home-mac-mini.taila6ea.ts.net")!
    #endif
}
