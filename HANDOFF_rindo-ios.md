# HANDOFF: Rindo for iOS

> **マスター仕様書**: [Rindo-web/HANDOFF_cycling-nav.md](https://github.com/osprey74/Rindo-web/blob/main/HANDOFF_cycling-nav.md)
> 全体設計・データソース・Web 版との役割分担はそちらを参照。本ドキュメントは iOS 実装に特化したガイドです。

## プロジェクト概要

- **アプリ名**: Rindo（りんどう）
- **バンドル ID**: `com.osprey74.rindo`
- **GitHub**: `github.com/osprey74/Rindo-iOS`
- **役割**: 実走行ナビゲーション・走行ログ記録（ルート計画は Web 版担当）
- **対象エリア**: 道央圏（札幌市中心 + 北海道大規模自転車道）
- **対応 OS**: iOS 17.0 以降（推奨 iOS 18+）
- **言語**: 日本語（多言語化計画なし）

---

## 技術スタック

| 領域 | 採用技術 | 理由 |
|---|---|---|
| 言語 | Swift 5.9+ | 標準 |
| UI | SwiftUI | iOS 17+ 前提なら宣言的 UI のメリットが大きい |
| 地図 | MapLibre Native iOS | Web 版と同じ MapLibre 系列で GeoJSON レンダリング一貫性を確保 |
| 位置 | CoreLocation | 標準 |
| モーション | CoreMotion | 勾配計算・転倒検知 |
| ヘルス | HealthKit | 体重取得（消費カロリー）・ワークアウト記録 |
| 音声 | AVSpeechSynthesizer | 標準・追加課金なし |
| 認証 | シングルユーザー・セッショントークン | 個人利用・Tailnet 限定運用、AppStore 公開予定なし |
| API | URLSession + Codable | 軽量で十分 |
| 永続化 | SwiftData（iOS 17+）or Core Data | ローカルキャッシュ・走行ログ一時保存 |
| ウォッチ | WatchConnectivity + WatchKit | Apple Watch 連携 |
| 依存管理 | Swift Package Manager | CocoaPods 不採用 |

### MapLibre Native iOS の追加方法

```swift
// Package.swift（または Xcode の Package Dependencies）
.package(url: "https://github.com/maplibre/maplibre-native-distribution.git", from: "6.0.0")
// 製品: MapLibre
```

利用例:
```swift
import MapLibre
import SwiftUI

struct MapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = URL(string: "https://demotiles.maplibre.org/style.json")!  // 仮スタイル
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.setCenter(.init(latitude: 43.0686, longitude: 141.3468), zoomLevel: 12, animated: false)
        return map
    }
    func updateUIView(_ uiView: MLNMapView, context: Context) {}
}
```

---

## アプリ構成

### ディレクトリ構成（推奨）

```
Rindo/
├── Rindo.xcodeproj
├── Rindo/
│   ├── App/
│   │   ├── RindoApp.swift            // @main、AuthProvider、ルート
│   │   └── AppConfig.swift           // 環境別 API URL
│   ├── Features/
│   │   ├── Map/
│   │   │   ├── MapScreen.swift       // メイン地図画面
│   │   │   ├── MapView.swift         // MapLibre UIViewRepresentable
│   │   │   └── MapLayers.swift       // Layer 1/2/3 のスタイル定義
│   │   ├── Navigation/
│   │   │   ├── NavigationView.swift  // 詳細ナビ画面
│   │   │   ├── SimpleNavView.swift   // 簡易ナビ（省電力）
│   │   │   ├── VoiceGuide.swift      // 音声案内
│   │   │   └── ManeuverParser.swift  // Valhalla maneuvers の解釈
│   │   ├── RideLog/
│   │   │   ├── RideRecorder.swift    // GPS ログ収集
│   │   │   ├── RideStore.swift       // SwiftData 永続化
│   │   │   ├── GPXExporter.swift     // GPX 1.1 出力
│   │   │   └── CalorieCalculator.swift
│   │   ├── Auth/
│   │   │   ├── LoginView.swift       // 「ログイン」ボタンのみのシンプル UI
│   │   │   └── AuthService.swift     // セッショントークン管理（Keychain）
│   │   ├── Routes/
│   │   │   └── SavedRoutesView.swift // Web で保存したルート一覧・取り込み
│   │   ├── Locations/
│   │   │   └── SavedLocationsView.swift
│   │   ├── Weather/
│   │   │   └── WeatherCard.swift     // JMA API
│   │   ├── Facilities/
│   │   │   └── FacilitiesLayer.swift // Overpass コンビニ・駐車場
│   │   ├── Safety/
│   │   │   └── FallDetector.swift    // CoreMotion 転倒検知 + SOS
│   │   ├── Photos/
│   │   │   └── PhotoSpotRecorder.swift
│   │   ├── Watch/
│   │   │   └── WatchSession.swift    // WatchConnectivity
│   │   └── Attribution/
│   │       └── AttributionView.swift
│   ├── Core/
│   │   ├── API/
│   │   │   ├── APIClient.swift       // URLSession ラッパ
│   │   │   ├── Endpoints.swift
│   │   │   └── Models/               // Codable 型定義
│   │   ├── Location/
│   │   │   └── LocationProvider.swift
│   │   ├── Storage/
│   │   │   ├── KeychainStore.swift
│   │   │   └── ModelContainer+.swift
│   │   └── Geo/
│   │       ├── GeoJSON.swift         // GeoJSON Codable
│   │       └── Distance.swift        // Haversine、bearing 計算
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       └── Localizable.strings
├── RindoWatch/                       // watchOS ターゲット（Phase 6 で追加）
└── RindoTests/
```

### 状態管理方針

- 認証状態・現在ユーザは `@Observable`（iOS 17+）の `AuthService` を環境注入
- 走行中の状態（速度・距離・経過時間）は `RideRecorder` を `@Observable` で公開
- 画面ローカル状態は `@State` / `@Bindable`
- ルート一覧などのリストは `SwiftData` の `@Query` で直接バインド

---

## API 連携仕様（rindo-api 経由）

### ベース URL

| 環境 | URL |
|---|---|
| Mac mini ローカル開発 | `http://localhost:3000` |
| 実機（同一 Tailnet 内） | `https://home-mac-mini.taila6ea.ts.net` |

### 認証ヘッダ

- セッショントークン方式（Web 版と共通）
- iOS 側は `Authorization: Bearer <token>` で送信
- トークンは Keychain に保存（`KeychainStore.swift`）

### 主要エンドポイント

```
POST /api/auth/apple             { id_token } → { token, user }
POST /api/auth/dev-login         { handle }   → { token, user }       開発用のみ
POST /api/auth/logout
GET  /api/auth/me                              → { user }

GET  /api/routes                               → SavedRoute[]
GET  /api/routes/:id                           → SavedRoute（取り込み用）

GET  /api/locations                            → SavedLocation[]
POST /api/locations              { name, category, lon, lat, notes }
PUT  /api/locations/:id          { ... }
DEL  /api/locations/:id

POST /api/rides                  { gpx, summary } → 走行ログアップロード（iOS 専用）

GET  /api/cycling-roads                        → Layer 3（GeoJSON FeatureCollection）
POST /api/valhalla/route         { locations, costing: 'bicycle', ... }
GET  /api/elevation?coords=lat,lon|lat,lon
GET  /api/overpass?...                         → コンビニ・駐車場検索
GET  /api/weather/:areaCode                    → JMA 天気予報
```

### Codable モデル例

```swift
struct SavedRoute: Codable, Identifiable {
    let id: String
    let name: String
    let waypoints: [LonLat]            // [{lon, lat}, ...]
    let distance: Double               // m
    let duration: Double               // s
    let geometry: String               // encoded polyline or GeoJSON
    let createdAt: Date
    let updatedAt: Date
}

struct LonLat: Codable {
    let lon: Double
    let lat: Double
}

struct SavedLocation: Codable, Identifiable {
    let id: String
    let name: String
    let category: Category             // home / work / favorite / other
    let lon: Double
    let lat: Double
    let notes: String?
    enum Category: String, Codable { case home, work, favorite, other }
}
```

---

## 主要機能の実装方針

### 1. 地図表示（Phase iOS-1）

- MapLibre Native iOS で OSM 標準タイルを表示
- 起動時に `GET /api/cycling-roads` で Layer 3 を取得 → `MLNShapeSource` に投入
- Layer 1（OSM cycleway）・Layer 2（北海道大規模自転車道）も同様
- スタイル定義は Web 版 `mapStyles.ts` を Swift に移植
- カラー・幅は Web 版と完全一致させる（一貫性のため）

### 2. リアルタイム走行情報（Phase iOS-3）

```swift
@Observable
class RideRecorder {
    var speed: Double = 0           // km/h
    var distance: Double = 0        // m
    var elapsed: TimeInterval = 0
    var heading: Double = 0         // 度
    var elevation: Double = 0       // m
    var grade: Double = 0           // %
    var calories: Double = 0        // kcal

    private var trackPoints: [TrackPoint] = []
    private let location: LocationProvider
    private let timer: Timer?

    func start() { /* CLLocationManager.startUpdatingLocation */ }
    func pause() { ... }
    func stop() -> RideLog { /* SwiftData 保存 + GPX 生成 */ }
}
```

- `desiredAccuracy = kCLLocationAccuracyBest`
- `activityType = .fitness`
- `pausesLocationUpdatesAutomatically = false`（バックグラウンド継続用）
- 速度は `CLLocation.speed`（m/s）→ km/h
- 距離は連続位置間の Haversine 距離を加算
- 勾配は標高差/水平距離（10 秒窓のローリング平均で平滑化）

### 3. ナビゲーション（Phase iOS-4）

- 詳細ナビ: Valhalla の `/route` レスポンスから `legs[].maneuvers[]` を解釈
  - `instruction`, `verbal_pre_transition_instruction`, `length`, `time` を表示
  - 次の分岐までの距離をリアルタイム更新（現在地 → 次マニューバ起点の距離）
  - 50m 以内になったら音声案内 → トリガ済みフラグでループ防止
- 簡易ナビ: 地図を非表示にして矢印 + 距離のみ。OLED 黒背景で省電力
- 音声: `AVSpeechSynthesizer` + `AVSpeechSynthesisVoice(language: "ja-JP")`
- ルート逸脱検出: 現在地と最寄りルート点との距離が 30m 超 → 自動再ルート（Valhalla 再呼び出し）

### 4. 消費カロリー（Phase iOS-3）

```swift
// MET ベース計算（HANDOFF マスター仕様準拠）
func calorieBurn(weight: Double, hours: Double, gradePercent: Double) -> Double {
    let met = 7.5 * (1 + max(0, gradePercent) * 0.1)
    return met * weight * hours
}
```

- 体重は HealthKit から取得（`HKQuantityTypeIdentifier.bodyMass`）
- 取得失敗時はユーザ設定画面で手入力フォールバック
- 完走後は `HKWorkout` として HealthKit に書き戻し

### 5. オフラインマップ（Phase iOS-5）

- MapLibre Native の `MLNOfflineStorage` で事前ダウンロード
- ユーザが「自宅から半径 30km」「お気に入りルート周辺 10km」などを指定
- ストレージ容量上限: 500MB（設定で変更可）

### 6. Apple Watch 連携（Phase iOS-6）

- `WCSession` で iPhone ←→ Watch 通信
- Watch 側: 速度・距離・経過時間・心拍数（HealthKit Watch 経由）の常時表示
- Workout 開始/停止操作を Watch から行えるように
- 詳細ナビは iPhone 必須（Watch では分岐通知のハプティクスのみ）

### 7. 転倒検知 + SOS（Phase iOS-7）

- `CMMotionManager` で加速度データを 50Hz サンプリング
- 閾値: 3G 超の急峻な変化 + 5 秒間の静止
- 検知時: 30 秒カウントダウン UI + ハプティクス + 音声警告 → 解除なければ SOS 起動
- SOS: 緊急連絡先（事前登録）に SMS（`MFMessageComposeViewController`）+ 現在地 URL
- 既存の Apple 標準「衝突検出」とは別実装（iOS 標準は車両衝突向け）

### 8. 写真スポット記録（Phase iOS-7）

- 走行中に下タブから「📷」ボタン → カメラ起動 → 撮影 → 現在地と紐づけて保存
- EXIF に GPS タグ付与（`PHPhotoLibrary` + `CLLocation`）
- 走行ログ詳細画面で写真サムネを地図上にプロット

---

## 認証フロー

Rindo は個人利用・Tailnet 内限定運用の前提（AppStore 公開予定なし、不特定多数への公開予定なし）のため、マルチユーザー認証は採用しない。クライアントは「ログイン」ボタン一発で seeded 単一ユーザー（`users.id = 1`）のセッショントークンを取得し、以降の API 呼び出しに `Authorization: Bearer ...` で付加する。

```swift
@Observable
class AuthService {
    private(set) var token: String?

    func login() async throws {
        let body = try JSONSerialization.data(withJSONObject: [:])
        var req = URLRequest(url: URL(string: "\(AppConfig.apiBase)/api/auth/login")!)
        req.httpMethod = "POST"
        req.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(LoginResponse.self, from: data)
        token = resp.token
        try Keychain.save(key: "rindo.token", value: resp.token)
    }

    func logout() async {
        // POST /api/auth/logout (best-effort)
        token = nil
        try? Keychain.delete(key: "rindo.token")
    }

    struct LoginResponse: Decodable {
        let token: String
    }
}
```

将来的に AppStore 公開や複数ユーザー対応をする場合は、Sign in with Apple または OAuth プロバイダを別途追加する。バックエンド（rindo-api）にはその際の拡張余地として `users.apple_user_id` カラムが残してある。

---

## バックグラウンド動作

走行中はアプリがバックグラウンドでも GPS ログ収集を継続する必要がある。

**Capabilities**:
- Background Modes → `Location updates` + `Audio` を ON

**Info.plist**:
- `UIBackgroundModes`: `["location", "audio"]`
- `NSLocationAlwaysAndWhenInUseUsageDescription` 必須

**実装上の注意**:
- `allowsBackgroundLocationUpdates = true` を `CLLocationManager` に設定
- `pausesLocationUpdatesAutomatically = false`
- 走行終了時は明示的に `stopUpdatingLocation()` してバッテリ消費を止める
- バックグラウンド中の音声案内は `AVAudioSession` を `.playback` カテゴリで起動

---

## 実装フェーズ

詳細チェックリストは [docs/tasks.md](./docs/tasks.md) を参照。

### Phase iOS-1: プロジェクト初期化と地図表示

- Xcode プロジェクト作成（バンドル ID `com.osprey74.rindo`、SwiftUI、iOS 17.0）
- MapLibre Native iOS を SPM で追加
- 地図表示（OSM タイル）+ Layer 1/2/3 のサイクリングロード描画
- 出典・ライセンス画面

### Phase iOS-2: 認証・ルート取り込み・地点表示

- 「ログイン」ボタン → `POST /api/auth/login` 実装
- Keychain によるセッショントークン管理
- `GET /api/routes` 一覧画面 → タップで地図に表示
- 地点（自宅・職場・お気に入り）一覧と地図上アイコン表示

### Phase iOS-3: リアルタイム走行情報・GPS ログ記録

- `LocationProvider` + `RideRecorder`
- 速度・距離・経過時間・勾配・標高・消費カロリー表示
- バックグラウンド継続
- SwiftData で走行ログ保存
- GPX エクスポート + `POST /api/rides`

### Phase iOS-4: ナビゲーション + 音声案内

- Valhalla `/route` のマニューバ解釈
- 詳細ナビ（地図 + 次分岐距離）+ 簡易ナビ（矢印のみ）
- 音声案内（AVSpeechSynthesizer）
- ルート逸脱検出 + 自動再ルート

### Phase iOS-5: オフラインマップ・走行モード・リマインダー

- `MLNOfflineStorage` 事前ダウンロード
- 走行モード（通勤 / レジャー / トレーニング）切替
- 休憩・補給リマインダー（30 分・60 分など設定）

### Phase iOS-6: Apple Watch 連携

- watchOS ターゲット追加
- WatchConnectivity で速度・距離・心拍同期
- Watch 側で走行開始・停止操作

### Phase iOS-7: 安全機能・写真スポット

- CoreMotion 転倒検知 + 30 秒カウントダウン + 緊急連絡先 SMS
- 写真スポット記録（カメラ起動 + EXIF GPS）

---

## 既知の課題・制約

- HealthKit 利用には Apple Developer Program（$99/年）契約必須。HealthKit を諦めれば Personal Team でも開発可能（体重は手入力フォールバック）
- AppStore 公開予定なし（個人利用・Tailnet 限定）。Sign in with Apple は実装しない
- MapLibre Native iOS のオフライン機能はベータ含む。動作検証必要
- watchOS 連携は別ターゲット必要 + Watch 実機テスト推奨
- 道央圏 PBF（Valhalla）は Mac mini @ 自宅で稼働。インターネット切断時のオフラインルーティングは未対応（将来検討）

---

## 参考リンク

- MapLibre Native iOS: https://github.com/maplibre/maplibre-native
- MapLibre iOS Examples: https://maplibre.org/maplibre-native/ios/api/
- HealthKit: https://developer.apple.com/documentation/healthkit
- WatchConnectivity: https://developer.apple.com/documentation/watchconnectivity
- Valhalla `/route` レスポンス形式: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/
- Web 版マスター仕様: [Rindo-web/HANDOFF_cycling-nav.md](https://github.com/osprey74/Rindo-web/blob/main/HANDOFF_cycling-nav.md)
