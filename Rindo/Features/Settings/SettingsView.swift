import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    var onSelectImportedRoute: ((ImportedRoute) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                // GPX ルート管理
                Section {
                    NavigationLink {
                        ImportedRoutesPanel { route in
                            onSelectImportedRoute?(route)
                            dismiss()
                        }
                    } label: {
                        Label("GPX ルート管理", systemImage: "doc.badge.plus")
                    }
                } header: {
                    Text("ルート")
                } footer: {
                    Text("GPX ファイルをインポートしてナビゲーションに使用できます")
                }

                // サーバ接続
                Section {
                    if auth.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("接続中")
                                    .font(.headline)
                                Text(AppConfig.apiBaseURL.host ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button(role: .destructive) {
                            Task { await auth.logout() }
                        } label: {
                            Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("未接続")
                                    .font(.headline)
                                Text("Tailscale 経由でサーバに接続するとルート同期等が使えます")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            Task { try? await auth.login() }
                        } label: {
                            Label("ログイン", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                } header: {
                    Text("サーバ接続")
                } footer: {
                    Text("ログインなしでも GPX インポートとナビゲーションは利用できます")
                }

                // アプリ情報
                Section("アプリ情報") {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }

                // 出典・ライセンス
                Section {
                    NavigationLink {
                        AttributionView()
                    } label: {
                        Label("データ出典・ライセンス", systemImage: "info.circle")
                    }

                    attribution(
                        title: "アプリアイコン",
                        detail: "Hibiscus icons created by popcic - Flaticon",
                        url: "https://www.flaticon.com/free-icons/hibiscus"
                    )
                } header: {
                    Text("出典・ライセンス")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func attribution(title: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if let link = URL(string: url) {
                Link(url, destination: link)
                    .font(.caption2)
            }
        }
        .padding(.vertical, 2)
    }
}
