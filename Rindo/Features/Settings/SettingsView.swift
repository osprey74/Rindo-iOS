import CoreLocation
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    var offlineMapManager: OfflineMapManager?
    var homeCoordinate: CLLocationCoordinate2D?
    var onSelectImportedRoute: ((ImportedRoute) -> Void)?

    // 走行モード・リマインダー
    @AppStorage("rideMode") private var rideModeRaw = RideMode.leisure.rawValue
    @AppStorage("breakIntervalMinutes") private var breakIntervalMinutes = 60
    @AppStorage("refuelIntervalKm") private var refuelIntervalKm = 50.0

    var body: some View {
        NavigationStack {
            List {
                // 走行モード
                Section {
                    Picker("走行モード", selection: $rideModeRaw) {
                        ForEach(RideMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                } header: {
                    Text("走行モード")
                } footer: {
                    if let mode = RideMode(rawValue: rideModeRaw) {
                        Text(mode.description)
                    }
                }

                // リマインダー
                Section {
                    Picker("休憩リマインダー", selection: $breakIntervalMinutes) {
                        Text("なし").tag(0)
                        Text("30分ごと").tag(30)
                        Text("60分ごと").tag(60)
                        Text("90分ごと").tag(90)
                    }
                    Picker("補給リマインダー", selection: $refuelIntervalKm) {
                        Text("なし").tag(0.0)
                        Text("30kmごと").tag(30.0)
                        Text("50kmごと").tag(50.0)
                        Text("80kmごと").tag(80.0)
                    }
                } header: {
                    Text("リマインダー")
                } footer: {
                    Text("通勤モードではリマインダーは無効になります")
                }

                // オフラインマップ
                if let manager = offlineMapManager {
                    Section {
                        NavigationLink {
                            OfflineMapView(manager: manager, homeCoordinate: homeCoordinate)
                        } label: {
                            Label("オフラインマップ", systemImage: "arrow.down.circle")
                        }
                    } header: {
                        Text("オフライン")
                    }
                }

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
