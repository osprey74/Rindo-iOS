import Foundation

enum AppConfig {
    static var backendServerURL: URL? {
        guard let str = UserDefaults.standard.string(forKey: "backendServerURL"),
              !str.isEmpty,
              let url = URL(string: str) else { return nil }
        return url
    }
}
