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

    // ルーティング
    @AppStorage("routingMode") private var routingMode = "apple"

    // バックエンドサーバ
    @AppStorage("backendServerURL") private var backendServerURL = ""
    @State private var loginError: String?

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

                // ルーティング
                Section {
                    Picker("ルーティングエンジン", selection: $routingMode) {
                        Label("標準（Apple Maps）", systemImage: "map")
                            .tag("apple")
                        Label("Valhalla（自転車専用）", systemImage: "bicycle")
                            .tag("valhalla")
                    }
                    .pickerStyle(.inline)

                    if routingMode == "valhalla" {
                        TextField("https://example.com", text: $backendServerURL)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        if auth.isAuthenticated {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("バックエンドサーバに接続中")
                            }

                            Button(role: .destructive) {
                                Task { await auth.logout() }
                            } label: {
                                Label("切断", systemImage: "xmark.circle")
                            }
                        } else {
                            Button {
                                Task {
                                    loginError = nil
                                    do {
                                        try await auth.login()
                                    } catch {
                                        loginError = error.localizedDescription
                                    }
                                }
                            } label: {
                                HStack {
                                    Label("バックエンドサーバに接続", systemImage: "server.rack")
                                    Spacer()
                                    if auth.isLoading {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                            }
                            .disabled(backendServerURL.isEmpty || auth.isLoading)

                            if let loginError {
                                Text(loginError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("ルーティング")
                } footer: {
                    if routingMode == "apple" {
                        Text("標準モードは徒歩ルートを自転車速度に換算してナビゲーションします")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("自転車専用ルーティングにはバックエンドサーバへの接続が必要です\nValhalla と OpenStreetMap によるバックエンドサーバを用意するとウェブアプリ上でコース設計・スマホアプリとのコース同期などが行えます")
                            Link("バックエンドサーバ接続手順", destination: URL(string: "https://github.com/osprey74/Rindo-iOS/blob/main/docs/valhalla-setup.md")!)
                        }
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
