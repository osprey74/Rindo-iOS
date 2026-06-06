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
    @AppStorage("valhallaServerURL") private var valhallaServerURL = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    private enum ConnectionTestResult {
        case success
        case failure(String)
    }

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
                        TextField("サーバー URL", text: $valhallaServerURL)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button {
                            Task { await testValhallaConnection() }
                        } label: {
                            HStack {
                                Label("接続テスト", systemImage: "antenna.radiowaves.left.and.right")
                                Spacer()
                                if isTestingConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if let result = connectionTestResult {
                                    switch result {
                                    case .success:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    case .failure:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .disabled(valhallaServerURL.isEmpty || isTestingConnection)

                        if case .failure(let message) = connectionTestResult {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Link(destination: URL(string: "https://github.com/user/Rindo-iOS/blob/main/docs/valhalla-setup.md")!) {
                            Label("Valhalla サーバーの構築手順", systemImage: "doc.text")
                        }
                    }
                } header: {
                    Text("ルーティング")
                } footer: {
                    if routingMode == "apple" {
                        Text("標準モードは徒歩ルートを自転車速度に換算してナビゲーションします")
                    } else {
                        Text("自転車専用ルーティングには Valhalla サーバーが必要です")
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

    private func testValhallaConnection() async {
        isTestingConnection = true
        connectionTestResult = nil
        defer { isTestingConnection = false }

        guard let baseURL = URL(string: valhallaServerURL) else {
            connectionTestResult = .failure("無効な URL です")
            return
        }

        // 札幌駅→大通公園の短距離テストルートをリクエスト
        do {
            let provider = ValhallaRouteProvider(baseURL: baseURL)
            let sapporoStation = CLLocationCoordinate2D(latitude: 43.0686, longitude: 141.3508)
            let odoriPark = CLLocationCoordinate2D(latitude: 43.0597, longitude: 141.3563)
            _ = try await provider.fetchRoute(from: sapporoStation, to: odoriPark)
            connectionTestResult = .success
        } catch {
            connectionTestResult = .failure(error.localizedDescription)
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
