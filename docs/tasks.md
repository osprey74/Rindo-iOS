# Rindo iOS — タスク管理

設計書: [HANDOFF_rindo-ios.md](../HANDOFF_rindo-ios.md)
マスター仕様: [Rindo-web/HANDOFF_cycling-nav.md](https://github.com/osprey74/Rindo-web/blob/main/HANDOFF_cycling-nav.md)

## 進捗サマリー

- 現在のフェーズ: **Phase iOS-2 着手前**（Phase iOS-1 完了）
- 残課題: 大規模自転車道（large_scale）の強調表示は iOS-1 では見送り、必要に応じて後続フェーズで対応

## フェーズ別ステータス

| Phase | 内容 | ステータス |
|---|---|---|
| iOS-1 | プロジェクト初期化・地図表示 | ✅ 完了 |
| iOS-2 | 認証・ルート取り込み・地点表示 | 未着手 |
| iOS-3 | リアルタイム走行情報・GPS ログ記録 | 未着手 |
| iOS-4 | ナビゲーション + 音声案内 | 未着手 |
| iOS-5 | オフラインマップ・走行モード・リマインダー | 未着手 |
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

### サイクリングロード描画

- [x] `APIClient` 雛形（actor ベース、URLSession ラッパ）
- [x] `GET /api/cycling-roads` で Layer 3 取得
- [x] Layer 1（OSM cycleway）— バンドル済み GeoJSON（`sapporo-osm-cycleways.geojson`）から表示。Overpass API 経由は採用せず（実装簡素化・オフライン対応のためバンドル方式）
- [x] Layer 2（OSM bicycle routes）— バンドル済み GeoJSON（`dosou-osm-bicycle-routes.geojson`）から表示
- [x] MLNShapeSource + MLNLineStyleLayer で描画（`MapLayerStyle.swift` で Web 版と同一の色・幅・破線パターンを定義）
  - [x] Layer 1（緑 #1D9E75、幅 3、不透明度 0.85）
  - [x] Layer 2（青 #3C7B91、幅 4、不透明度 0.9）
  - [x] Layer 3 専用（オレンジ #E65C00 実線、幅 4、`road_type == 'exclusive'`）
  - [x] Layer 3 共用（オレンジ #E65C00 破線 [4,2]、幅 2、`road_type == 'shared'`）
  - [ ] 大規模自転車道フラグ（large_scale）の強調表示（後続フェーズに送り）

### 出典・ライセンス画面

- [x] AttributionView（モーダル）
- [x] © OpenStreetMap、北海道建設部土木局、札幌市建設局、Valhalla、JMA、SRTM の表記

### 動作確認

- [x] シミュレータで地図表示
- [x] 実機（Tailscale 経由）でサイクリングロードが表示される

---

## Phase iOS-2: 認証・ルート取り込み・地点表示

### 認証基盤

- [ ] `AuthService`（@Observable）
- [ ] `KeychainStore`（トークン保存）
- [ ] `AppConfig.swift` で開発/本番 URL 切替（`#if DEBUG`）

### ログイン

- [ ] `LoginView`（「ログイン」ボタンのみのシンプル UI）
- [ ] `POST /api/auth/login` でセッショントークン取得
- [ ] レスポンスのセッショントークンを Keychain に保存
- [ ] 起動時に Keychain から復元 → `GET /api/auth/me` で検証
- [ ] `POST /api/auth/logout` 実装

### ルート取り込み

- [ ] `SavedRoutesView`（一覧画面）
- [ ] `GET /api/routes`
- [ ] タップで地図に表示（waypoints を MLNShapeSource に投入）
- [ ] ルート詳細（距離・所要時間・標高プロファイル）

### 標高プロファイル

- [ ] ElevationChart（Swift Charts 使用、横向き全ルート確認）
- [ ] `GET /api/elevation` で 100 サンプル取得 + 線形補間

### 地点表示

- [ ] `SavedLocationsView`（一覧）
- [ ] `GET /api/locations`
- [ ] 地図上に SymbolStyleLayer で🏠/🏢/⭐/📍 アイコン表示
- [ ] タップでポップオーバー（名前・カテゴリ・備考）

### 動作確認

- [ ] 実機でログインボタンを押すとセッショントークンが Keychain に保存される
- [ ] Web 版で保存したルートが iOS で表示される
- [ ] Web 版で登録した地点が地図に表示される

---

## Phase iOS-3: リアルタイム走行情報・GPS ログ記録

### 位置情報基盤

- [ ] `LocationProvider`（CLLocationManager ラッパ、@Observable）
- [ ] バックグラウンド継続設定
- [ ] 権限リクエスト（`requestAlwaysAuthorization`）

### 走行記録

- [ ] `RideRecorder`（@Observable）
- [ ] 速度（CLLocation.speed → km/h）
- [ ] 距離（Haversine 累積）
- [ ] 経過時間（Timer）
- [ ] 方向（CLLocation.course）
- [ ] 標高（CLLocation.altitude or OpenTopoData）
- [ ] 勾配（10 秒窓ローリング平均）

### 消費カロリー

- [ ] HealthKit 権限リクエスト
- [ ] 体重取得（HKQuantityTypeIdentifier.bodyMass）
- [ ] 取得失敗時の手入力フォールバック画面
- [ ] MET ベース計算（HANDOFF 仕様準拠）

### UI

- [ ] 走行中ダッシュボード（速度・距離・経過時間・勾配・カロリーを大きく表示）
- [ ] スタート/一時停止/停止ボタン
- [ ] 地図上に現在地マーカー + 走行軌跡

### 永続化

- [ ] SwiftData モデル: `RideLog`, `TrackPoint`
- [ ] 走行終了時に保存
- [ ] 走行履歴一覧画面

### GPX エクスポート

- [ ] GPX 1.1 生成（trkpt + ele + time + speed extension）
- [ ] iOS 共有シート経由で出力（UIDocumentPickerViewController）
- [ ] `POST /api/rides` でサーバアップロード（オプション）

### HealthKit 書き戻し

- [ ] `HKWorkout`（cycling）として記録
- [ ] 距離・カロリー・所要時間を含める

### 動作確認

- [ ] 実走行テスト（自転車で 30 分以上）
- [ ] バックグラウンド継続を画面ロックして検証
- [ ] GPX が Garmin Connect / Strava に取り込めること

---

## Phase iOS-4: ナビゲーション + 音声案内

### Valhalla 連携

- [ ] `POST /api/valhalla/route` でナビ用ルート取得
- [ ] レスポンスから `legs[].maneuvers[]` を解析
- [ ] `ManeuverParser` で日本語インストラクション抽出

### 詳細ナビ画面

- [ ] 進行方向に地図を回転（bearing アニメーション）
- [ ] 次の分岐までの距離（リアルタイム）
- [ ] マニューバアイコン（直進・右折・左折・Uターン等）
- [ ] 残り距離・残り時間

### 簡易ナビ画面

- [ ] OLED 黒背景
- [ ] 大きな矢印 + 距離のみ
- [ ] 切替ボタン（地図 ⇄ 簡易）

### 音声案内

- [ ] AVSpeechSynthesizer + ja-JP voice
- [ ] AVAudioSession `.playback` で背景再生
- [ ] 50m / 100m / 200m 前トリガ + 重複防止フラグ
- [ ] ミュート / 音量設定

### ルート逸脱検出

- [ ] 現在地と最寄りルート点の距離を毎秒計算
- [ ] 30m 超で「ルートを再検索しています」音声 + Valhalla 再呼び出し
- [ ] 連続再ルート抑制（最低 30 秒間隔）

### 動作確認

- [ ] 実走行で分岐通知タイミングが適切
- [ ] 逸脱からの再ルートが正常動作
- [ ] BGM 再生中でも音声案内がダッキング

---

## Phase iOS-5: オフラインマップ・走行モード・リマインダー

### オフラインマップ

- [ ] MLNOfflineStorage で範囲指定ダウンロード UI
- [ ] プリセット: 「自宅から 30km」「お気に入りルート周辺 10km」
- [ ] ストレージ容量管理画面（合計サイズ表示・個別削除）

### 走行モード

- [ ] モード切替（通勤 / レジャー / トレーニング）
- [ ] モード別設定: 音声頻度・地図ズーム初期値・通知の有無

### リマインダー

- [ ] 休憩リマインダー（30 分・60 分・90 分から選択）
- [ ] 補給リマインダー（時間または距離トリガ）
- [ ] 通知センターと音声両方で通知

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

- [ ] rindo-api の `POST /api/rides` エンドポイント設計確定（GPX or JSON track points）
- [ ] HealthKit 用 Capability 申請（Apple Developer Program 契約時のみ）
- [ ] iOS から Tailscale 経由 `https://home-mac-mini.taila6ea.ts.net/api/auth/login` 疎通確認

---

## メモ

- 最低 iOS バージョン: 17.0（@Observable, SwiftData, Swift Charts, Sensitive Content Analysis を活用するため）
- 推奨実機: iPhone 14 以降（CMMotionManager 衝突検出センサー精度のため）
- Apple Watch 対応は Series 6 以降（常時表示ディスプレイ前提）
