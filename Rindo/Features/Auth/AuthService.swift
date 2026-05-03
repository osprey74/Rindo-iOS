import Foundation

private let keychainTokenKey = "rindo.session-token"

@Observable
@MainActor
final class AuthService {
    private(set) var token: String?
    private(set) var user: User?
    private(set) var isLoading = false

    var isAuthenticated: Bool { token != nil }

    init() {
        if let saved = KeychainStore.load(key: keychainTokenKey) {
            token = saved
        }
    }

    // MARK: - Login

    func login() async throws {
        isLoading = true
        defer { isLoading = false }

        let response = try await APIClient.shared.post(
            LoginResponse.self,
            path: "/api/auth/login"
        )
        token = response.token
        user = response.user
        try KeychainStore.save(key: keychainTokenKey, value: response.token)
        await APIClient.shared.setToken(response.token)
    }

    // MARK: - Logout

    func logout() async {
        if token != nil {
            try? await APIClient.shared.postIgnoringResponse(path: "/api/auth/logout")
        }
        token = nil
        user = nil
        KeychainStore.delete(key: keychainTokenKey)
        await APIClient.shared.setToken(nil)
    }

    // MARK: - Session Restore

    /// 起動時に Keychain のトークンを検証
    func restoreSession() async {
        guard let savedToken = token else { return }
        await APIClient.shared.setToken(savedToken)
        do {
            let response = try await APIClient.shared.fetch(UserResponse.self, path: "/api/auth/me")
            user = response.user
        } catch {
            // トークン失効 → ログアウト状態に戻す
            token = nil
            user = nil
            KeychainStore.delete(key: keychainTokenKey)
            await APIClient.shared.setToken(nil)
        }
    }
}
