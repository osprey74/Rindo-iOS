import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // アプリ名
            VStack(spacing: 8) {
                Image(systemName: "bicycle")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Rindo")
                    .font(.largeTitle.bold())
                Text("札幌・道央圏サイクリングナビ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // ログインボタン
            Button {
                Task { await login() }
            } label: {
                if auth.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                } else {
                    Text("ログイン")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(auth.isLoading)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text("Tailscale 接続が必要です")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()
                .frame(height: 48)
        }
        .padding(.horizontal, 40)
    }

    private func login() async {
        errorMessage = nil
        do {
            try await auth.login()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
