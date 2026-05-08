# Rindo iOS — タスク管理

設計書: [HANDOFF_rindo-ios.md](../HANDOFF_rindo-ios.md)
マスター仕様: [Rindo-web/HANDOFF_cycling-nav.md](https://github.com/osprey74/Rindo-web/blob/main/HANDOFF_cycling-nav.md)

## 進捗サマリー

- 現在のフェーズ: **Phase iOS-6 着手前**（Phase iOS-1〜5 完了）
- Layer 1/2/3 は iOS から削除済み（2026-05）。サイクリングロード表示は Web 専用
- Phase iOS-2 の残課題すべて完了

## フェーズ別ステータス

| Phase | 内容 | ステータス |
|---|---|---|
| iOS-1 | プロジェクト初期化・地図表示 | ✅ 完了 |
| iOS-2 | 認証・ルート取り込み・地点表示 | ✅ 完了 |
| iOS-3 | リアルタイム走行情報・GPS ログ記録 | ✅ 完了 |
| iOS-4 | ナビゲーション + 音声案内 | ✅ 完了 |
| iOS-5 | オフラインマップ・走行モード・リマインダー | ✅ 完了 |
| iOS-6 | Apple Watch 連携 | 未着手 |
| iOS-7 | 安全機能・写真スポット | 未着手 |

---

## Phase iOS-1: プロジェクト初期化と地図表示 ✅

### セットアップ

- [x] Mac mini で `git clone` 完了
- [x] Xcode プロジェクト作成（XcodeGen ベース、`project.yml` + `Rindo.xcodeproj` 生成）
- [x] アプリ表示名 `Rindo`、Bundle ID `com.osprey74.rindo`、iOS 17.0、SwiftUI
- [x] アプリアイコン（竜胆の花モチーフ）
- [ ] Apple Developer Program 加入確認（HealthKit 利用予定なら $99 契約必須、HealthKit 諦めれば Personal Team で OK）
- [ ] Signing & Capabilities 設定（後続フェーズで追加）
  - [ ] HealthKit（Apple Developer Program 契約時のみ。Phase iOS-3）
  - [ ] Background Modes（Location updates + Audio。Phase iOS-3）
- Info.plist 必須キー追加
  - [x] `NSLocationWhenInUseUsageDescription`
  - [ ] `NSLocationAlwaysAndWhenInUseUsageDescription`（Phase iOS-3 でバックグラウンド位置情報を有効化する際に追加）
  - [ ] `NSMotionUsageDescription`（Phase iOS-3 / iOS-7 で必要）

### 依存追加

- [x] MapLibre Native iOS 6.26.0 を SPM で追加
- [x] `Package.resolved` を `.gitignore` 通り無視確認

### 地図表示

- [x] `RindoMapView`（UIViewRepresentable）で MLNMapView をラップ
- [x] OSM 標準タイル `osm-style.json` をバンドルしてロード
- [x] 札幌中心（lat: 43.0686, lon: 141.3468、zoom: 12）で初期表示
- [x] 現在地表示（`mapView.showsUserLocation = true`）
- [x] ピンチ回転を無効化（北固定）

### サイクリングロード描画 — 削除済み（2026-05）

> Layer 1（OSM cycleway）、Layer 2（OSM bicycle routes）、Layer 3（キュレーション済みサイクリングロード）はすべて iOS から削除。サイクリングロードの表示は Web 版専用機能に変更。iOS はベースマップ＋保存済みルート（ナビゲーション用）に特化。

- [x] `APIClient` 雛形（actor ベース、URLSession ラッパ）
- ~~`GET /api/cycling-roads` で Layer 3 取得~~ — 削除済み
- ~~Layer 1（OSM cycleway）バンドル GeoJSON~~ — 削除済み
- ~~Layer 2（OSM bicycle routes）バンドル GeoJSON~~ — 削除済み
- ~~Layer 3 描画（MLNShapeSource + MLNLineStyleLayer）~~ — 削除済み

### 出典・ライセンス画面

- [x] AttributionView（モーダル）
- [x] © OpenStreetMap、北海道建設部土木局、札幌市建設局、Valhalla、JMA、SRTM の表記

### 動作確認

- [x] シミュレータで地図表示
- [x] 実機（Tailscale 経由）でサイクリングロードが表示される

---

## Phase iOS-2: 認証・ルート取り込み・地点表示 ✅

### 認証基盤

- [x] `AuthService`（@Observable、@MainActor）
- [x] `KeychainStore`（Security framework、save/load/delete）
- [x] `AppConfig.swift` で開発/本番 URL 切替（`#if DEBUG`、apiBaseURL + caddyBaseURL）

### ログイン

- [x] `LoginView`（「ログイン」ボタンのみのシンプル UI）
- [x] `POST /api/auth/login` でセッショントークン取得
- [x] レスポンスのセッショントークンを Keychain に保存
- [x] 起動時に Keychain から復元 → `GET /api/auth/me` で検証
- [x] `POST /api/auth/logout` 実装
- [x] `RindoApp` で認証状態に応じて LoginView / MapScreen を切替

### ルート取り込み

- [x] `SavedRoutesPanel`（一覧画面、sheet で表示）
- [x] `GET /api/routes`
- [x] タップで地図にルートポリライン表示（青線 + 白ハロ + ウェイポイント円マーカー）
- [x] ルート詳細（距離・所要時間・上昇量をヘッダーに表示）
- [x] ルート選択時にカメラを自動フィット

### 標高プロファイル

- [x] `ElevationService`（OpenTopoData SRTM 30m、60 サンプルにダウンサンプリング）
- [x] `ElevationChart`（Swift Charts、AreaMark + LineMark、展開/折り畳み可）
- [x] 総距離・総上昇/下降・最大勾配・最低/最高標高の統計表示

### 地点表示

- [x] `SavedLocationsPanel`（カテゴリ別セクション、sheet で表示）
- [x] `GET /api/locations`
- [x] 地図上にカテゴリ別マーカー表示（CircleStyleLayer + emoji SymbolStyleLayer）
- [x] 地点選択で地図をフォーカス（zoom 15）
- [x] タップでポップオーバー（名前・カテゴリ・備考）

### Codable モデル

- [x] `AuthModels`（LoginResponse, UserResponse, User）
- [x] `SavedRoute`（GeoJSONLineString 含む、coordinates → CLLocationCoordinate2D 変換）
- [x] `SavedLocation`（LocationCategory enum: home/work/favorite/other + emoji/displayName）
- [x] `APIClient` 拡張（トークン管理、POST 対応、baseURL オーバーライド）

### 動作確認

- [ ] 実機でログインボタンを押すとセッショントークンが Keychain に保存される
- [ ] Web 版で保存したルートが iOS で表示される
- [ ] Web 版で登録した地点が地図に表示される

---

## Phase iOS-3: リアルタイム走行情報・GPS ログ記録 ✅

### 位置情報基盤

- [x] `LocationService`（CLLocationManager ラッパ、@Observable、バックグラウンド対応）
- [x] バックグラウンド継続設定（Info.plist: NSLocationAlwaysAndWhenInUseUsageDescription、UIBackgroundModes: location + audio）
- [x] `allowsBackgroundLocationUpdates = true`、`showsBackgroundLocationIndicator = true`

### 走行記録

- [x] `RideRecorder`（@Observable、start/pause/resume/stop）
- [x] 速度（CLLocation.speed → km/h、最高速度記録）
- [x] 距離（CLLocation.distance 累積）
- [x] 経過時間（Timer、一時停止中は除外）
- [x] 方向（CLLocation.course）
- [x] 標高（CLLocation.altitude）
- [x] 勾配（10 秒窓ローリング平均）

### 消費カロリー

- [x] MET ベース計算（HANDOFF 仕様準拠: MET = 7.5 × (1 + 勾配% × 0.1)）
- [x] 体重は RideRecorder.weightKg で設定（デフォルト 70kg）
- [ ] HealthKit 体重取得（Apple Developer Program 契約後に追加）
- [ ] HealthKit ワークアウト書き戻し（同上）

### UI

- [x] NavigationInfoPanel（速度・距離・経過時間）
- [x] 記録開始/一時停止/再開/停止ボタン（サイドボタン群）
- [x] 地図上に走行軌跡描画（赤線、MLNLineStyleLayer）
- [x] 矢印マーカー + 逸脱警告バナー

### 永続化

- [x] SwiftData モデル: `RideLog`（JSON トラックデータ含む）
- [x] 走行終了時に自動保存
- [x] `RideHistoryPanel`（走行履歴一覧、削除対応）

### GPX エクスポート

- [x] `GPXExporter` で GPX 1.1 生成（trkpt + ele + time + speed extension）
- [x] `ShareSheet`（UIActivityViewController）経由で出力
- [x] `POST /api/rides` でサーバアップロード（ログイン時のみ、バックグラウンド）

### rindo-api

- [x] `migrations/004_rides.sql`（rides テーブル）
- [x] `handlers/rides.ts`（GET /api/rides、GET /api/rides/:id、POST /api/rides、DELETE /api/rides/:id）

### HealthKit 書き戻し

- [ ] `HKWorkout`（cycling）として記録
- [ ] 距離・カロリー・所要時間を含める

### 動作確認

- [ ] 実走行テスト（自転車で 30 分以上）
- [ ] バックグラウンド継続を画面ロックして検証
- [ ] GPX が Garmin Connect / Strava に取り込めること

---

## Phase iOS-4: ナビゲーション + 音声案内 ✅

### Valhalla 連携

- [x] `ValhallaService`（POST /api/valhalla/route、bicycle プロファイル、日本語 directions）
- [x] `PolylineDecoder`（Valhalla encoded polyline、precision 6）
- [x] Codable モデル（ValhallaRouteResponse/Trip/Leg/Maneuver/Summary）
- [x] `NavigationRoute` + `NavigationManeuver`（解析済みナビ用構造体）

### ManeuverParser

- [x] マニューバ type → SF Symbol アイコンマッピング（37 種対応）
- [x] 目的地判定（type 4/5/6）

### 詳細ナビ画面（TurnByTurnPanel）

- [x] マニューバアイコン（青背景 60x60、SF Symbol）
- [x] 次の分岐までの距離（リアルタイム、m/km 自動切替）
- [x] 指示文（日本語、Valhalla `instruction`）
- [x] 残り距離・残り時間
- [x] 再ルート中インジケータ

### 簡易ナビ画面（SimpleNavView）

- [x] OLED 黒背景（fullScreenCover）
- [x] 大きなマニューバアイコン（120pt）+ 距離（64pt）
- [x] 下部バー（速度・残り距離・地図に戻るボタン）
- [x] `persistentSystemOverlays(.hidden)` で省電力

### 音声案内（VoiceGuide）

- [x] AVSpeechSynthesizer + ja-JP voice
- [x] AVAudioSession `.playback` + `.duckOthers` で BGM ダッキング
- [x] 200m / 100m / 50m 前トリガ + 重複防止（spokenKeys Set）
- [x] 到着判定（目的地 30m 以内）
- [x] `isEnabled` フラグでミュート可

### NavigationManager（進捗追跡 + 自動再ルート）

- [x] ルート上の最寄り点追跡
- [x] マニューバ通過判定（20m 以内で次に進む）
- [x] 音声トリガ距離計算
- [x] 30m 逸脱 → Valhalla 再ルート（30 秒クールダウン）
- [x] 再ルート結果適用（ルート・座標・逸脱検知を更新）

### MapScreen 統合

- [x] サーバルート選択時に Valhalla ルート自動取得
- [x] ナビ開始で NavigationManager + VoiceGuide 起動
- [x] 位置更新ごとに NavigationManager 更新
- [x] 簡易ナビ切替ボタン（「簡易」→ fullScreenCover）
- [x] GPX ルートはライン追従ナビ（Valhalla なし）、サーバルートはターンバイターンナビ

### 動作確認

- [ ] 実走行で分岐通知タイミングが適切
- [ ] 逸脱からの再ルートが正常動作
- [ ] BGM 再生中でも音声案内がダッキング

---

## Phase iOS-5: オフラインマップ・走行モード・リマインダー ✅

### オフラインマップ

- [x] MLNOfflineStorage で範囲指定ダウンロード UI
- [x] プリセット: 「自宅から 30km」「お気に入りルート周辺 10km」
- [x] ストレージ容量管理画面（合計サイズ表示・個別削除）

### 走行モード

- [x] モード切替（通勤 / レジャー / トレーニング）
- [x] モード別設定: 音声頻度・地図ズーム初期値・通知の有無

### リマインダー

- [x] 休憩リマインダー（30 分・60 分・90 分から選択）
- [x] 補給リマインダー（時間または距離トリガ）
- [x] 通知センターと音声両方で通知

### 動作確認

- [ ] 機内モードでオフライン地図が表示される
- [ ] 走行中にリマインダーが正しいタイミングで発火

---

## Phase iOS-6: Apple Watch 連携

### watchOS ターゲット追加

- [ ] Xcode で watchOS App 追加（`RindoWatch`）
- [ ] WatchKit + SwiftUI で UI 構築

### WatchConnectivity

- [ ] `WCSession` 起動（iPhone / Watch 双方）
- [ ] 走行データ同期（速度・距離・経過時間・心拍数）
- [ ] Watch → iPhone コマンド（スタート・停止・一時停止）

### Watch UI

- [ ] 常時表示ビュー（速度・距離・時間）
- [ ] HealthKit 心拍数表示
- [ ] 分岐通知ハプティクス（詳細ナビは iPhone のみ）

### 動作確認

- [ ] iPhone を取り出さず Watch だけで走行情報が見える
- [ ] iPhone 側の RideRecorder と完全同期

---

## Phase iOS-7: 安全機能・写真スポット

### 転倒検知

- [ ] CMMotionManager 50Hz サンプリング
- [ ] 3G 超 + 5 秒静止で発火
- [ ] 30 秒カウントダウン UI + ハプティクス + 警告音
- [ ] キャンセルボタン（誤検知対応）

### SOS

- [ ] 緊急連絡先設定画面（複数登録可）
- [ ] MFMessageComposeViewController で SMS 送信
- [ ] 現在地 URL（Apple Maps）+ 「Rindo で転倒検知」メッセージ

### 写真スポット記録

- [ ] 走行中の📷ボタンでカメラ起動
- [ ] 撮影 → EXIF に GPS タグ付与（PHAssetCreationRequest）
- [ ] 走行ログに紐づけて保存
- [ ] 走行履歴詳細画面で写真サムネを地図上に表示

### 動作確認

- [ ] 実機で揺れ・落下を再現して検知精度を確認（緊急連絡先送信は事前に通知）
- [ ] 撮影写真の EXIF に GPS 座標が含まれる

---

## 接続周りの先行整備（並行で進めて良い）

- [x] rindo-api の `POST /api/rides` エンドポイント設計確定・実装済み（JSON track points、`migrations/004_rides.sql`）
- [ ] HealthKit 用 Capability 申請（Apple Developer Program 契約時のみ）
- [ ] iOS から Tailscale 経由 `https://home-mac-mini.taila6ea.ts.net/api/auth/login` 疎通確認

---

## メモ

- 最低 iOS バージョン: 17.0（@Observable, SwiftData, Swift Charts, Sensitive Content Analysis を活用するため）
- 推奨実機: iPhone 14 以降（CMMotionManager 衝突検出センサー精度のため）
- Apple Watch 対応は Series 6 以降（常時表示ディスプレイ前提）
