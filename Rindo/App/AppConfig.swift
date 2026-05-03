import Foundation

enum AppConfig {
    /// 本番 URL（Tailscale 経由、実機・Release 共通）
    private static let prodURL = URL(string: "https://home-mac-mini.taila6ea.ts.net")!

    /// rindo-api 直接（認証・ルート・地点・サイクリングロード・プロフィール）
    #if targetEnvironment(simulator)
    static let apiBaseURL = URL(string: "http://localhost:3000")!
    #else
    static let apiBaseURL = prodURL
    #endif

    /// Caddy 経由（Valhalla・標高・Overpass・天気）
    #if targetEnvironment(simulator)
    static let caddyBaseURL = URL(string: "http://localhost:8080")!
    #else
    static let caddyBaseURL = prodURL
    #endif
}
