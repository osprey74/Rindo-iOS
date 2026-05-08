import Foundation

enum AppConfig {
    /// 本番 URL（Tailscale 経由、実機・Release 共通）
    private static let prodURL = URL(string: "https://home-mac-mini.taila6ea.ts.net")!

    /// rindo-api 直接（認証・ルート・地点・サイクリングロード・プロフィール）
    static let apiBaseURL = prodURL

    /// Caddy 経由（Valhalla・標高・Overpass・天気）
    static let caddyBaseURL = prodURL
}
