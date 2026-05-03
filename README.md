# Rindo（りんどう）— iOS

札幌市・道央圏のサイクリングロード限定ナビゲーションアプリの **iOS 版** です。

名前の由来: 林道（サイクリングロード・自然の道）＋ 竜胆（北海道に自生する花）。

## 概要

- **対象エリア**: 道央圏（北海道）
- **役割**: 実走行ナビゲーション・走行ログ記録（ルート計画は [Web 版](https://github.com/osprey74/Rindo-web) で実施）
- **バンドル ID**: `com.osprey74.rindo`
- **最低 iOS バージョン**: iOS 17.0（推奨 iOS 18+）

### 運用前提

- **あくまで個人使用**。AppStore 公開・不特定多数公開の予定なし
- **Web/バックエンドは自宅 M2 Mac mini で稼働**し、iPhone から **Tailscale ネットワーク経由**でアクセスする
- **Apple ID 認証は採用しない**。シングルユーザー・セッショントークン方式（`POST /api/auth/login`）で十分

設計の全体像・データソース・Web 版との役割分担は [HANDOFF_rindo-ios.md](./HANDOFF_rindo-ios.md) を参照してください。マスター仕様書は Web 版リポジトリの [HANDOFF_cycling-nav.md](https://github.com/osprey74/Rindo-web/blob/main/HANDOFF_cycling-nav.md) です。

## 主要機能（実装計画）

実走行向けに特化した機能を中心に開発します。

- リアルタイム走行情報（速度・方向・経過時間・距離・勾配）
- 詳細ナビゲーション（現在地 + 進行方向 + 次の分岐案内）
- 簡易ナビゲーション（矢印 + 距離のみの省電力モード）
- GPS 走行ログ記録 → GPX エクスポート + サーバアップロード
- 消費カロリー（HealthKit 連携で体重取得 + MET ベース計算）
- オフラインマップ（事前ダウンロード）
- 音声案内（AVSpeechSynthesizer）
- 休憩・補給リマインダー
- Apple Watch 連携（走行情報のグランス表示）
- 転倒検知 + SOS（CMMotionManager + 緊急連絡先）
- 写真スポット記録
- 走行モード切替（通勤 / レジャー / トレーニング）

Web 版から取り込む機能（共通）:
- ベースマップ（OSM 標準タイル）+ サイクリングロード表示
  - Layer 1: OSM `highway=cycleway`（緑、バンドル GeoJSON）
  - Layer 2: OSM `route=bicycle` リレーション（青、バンドル GeoJSON）
  - Layer 3: 札幌市公式 13 路線 + 北海道大規模自転車道（オレンジ、`/api/cycling-roads` から取得）
- ルート取り込み（Web で計画したルートをログイン同期）
- 地点表示（自宅・職場・お気に入り）
- 標高プロファイル（横向き全ルート確認）
- 近隣施設表示（コンビニ・駐車場）
- 天気予報（気象庁 API）
- 出典・ライセンス画面

## 技術スタック

- **言語**: Swift 5.9+
- **UI**: SwiftUI
- **地図**: [MapLibre Native iOS](https://github.com/maplibre/maplibre-native)（Web 版と同じ MapLibre 系列で表示一貫性を確保）
- **位置情報**: CoreLocation（`CLLocationManager`）
- **モーション**: CoreMotion（転倒検知）
- **ヘルス連携**: HealthKit（体重取得・ワークアウト記録）
- **音声**: AVSpeechSynthesizer
- **認証**: シングルユーザー・セッショントークン（`POST /api/auth/login` で seeded 単一ユーザーのトークン取得 → Keychain に保存。Apple ID 認証は不採用）
- **API クライアント**: URLSession + Codable
- **バックエンド**: [rindo-api](https://github.com/osprey74/rindo-api)（Bun + Hono + SQLite、自宅 M2 Mac mini + Tailscale 経由）
- **依存管理**: Swift Package Manager（SPM）

## アーキテクチャ

```
[ iPhone（走行中）]
   ↓ Tailscale 経由 https://home-mac-mini.taila6ea.ts.net
[ M2 Mac mini @ 自宅 ]
   ├─ Caddy（リバースプロキシ）
   ├─ rindo-api（認証・ルート・地点・cycling-roads・profile）
   └─ Valhalla（bicycle ルーティング、Docker）
```

- iPhone → Tailscale 経由で API アクセス（自宅 LAN 外でも到達可能）
- ログイン: 「ログイン」ボタン → `POST /api/auth/login` で seeded 単一ユーザーのセッショントークン取得 → Keychain に保存（個人利用・Tailnet 内限定運用前提・Apple ID 認証不採用）
- ルート同期: Web で計画 → サーバ保存 → iOS が `GET /api/routes` で取り込み
- 走行ログ: iOS Phase 3 で実装予定。`POST /api/rides` は **rindo-api 未実装**。iOS Phase 3 着手時に rindo-api 側で `rides` テーブル＋ハンドラを新規実装する

## 開発環境セットアップ

### 前提条件

- macOS 14（Sonoma）以降
- Xcode 16+
- Apple Developer Program（HealthKit 利用に必須。AppStore 公開予定なし、Apple ID 認証も不採用なので、HealthKit を諦めれば Personal Team でもデバッグ可能）
- 実機テスト用 iPhone（iOS 17+）
- Tailscale クライアント（Mac mini と iPhone 双方）

### 手順

```bash
# Mac mini 上で
cd ~/dev
git clone git@github.com:osprey74/Rindo-iOS.git
cd Rindo-iOS

# 初回は Xcode で Rindo.xcodeproj を作成（または Package.swift ベース）
open .
```

Xcode プロジェクト作成時の設定:
- Product Name: `Rindo`
- Organization Identifier: `com.osprey74`
- Bundle Identifier: `com.osprey74.rindo`
- Interface: SwiftUI
- Language: Swift
- Minimum Deployments: iOS 17.0

Capabilities（Signing & Capabilities タブで追加）:
- HealthKit
- Background Modes（`Location updates` + `Audio` 走行中の音声案内）
- Push Notifications（将来用）

Info.plist 追加項目:
- `NSLocationWhenInUseUsageDescription`: "走行中のナビゲーションと現在地表示に使用します"
- `NSLocationAlwaysAndWhenInUseUsageDescription`: "バックグラウンドでも走行ログを記録します"
- `NSMotionUsageDescription`: "転倒検知と勾配計算に使用します"
- `NSHealthShareUsageDescription`: "体重を取得して消費カロリーを計算します"
- `NSHealthUpdateUsageDescription`: "ワークアウトとして走行ログを記録します"
- `NSPhotoLibraryUsageDescription`: "走行中の写真スポット記録に使用します"

### API 接続先

- **開発**（Mac mini ローカル）: `http://localhost:3000` / `http://localhost:8002`
- **実機テスト**（同一 Tailnet 内 iPhone）: `https://home-mac-mini.taila6ea.ts.net`
- 切替方法は `Config.swift`（または `.xcconfig`）で環境別管理する想定

## 実装フェーズ

詳細は [docs/tasks.md](./docs/tasks.md) を参照。

| Phase | 内容 |
|---|---|
| iOS-1 | プロジェクト初期化・地図表示（MapLibre + Layer 1/2 バンドル GeoJSON + Layer 3 API 取得） |
| iOS-2 | 認証（`POST /api/auth/login`）・ルート取り込み・地点表示 |
| iOS-3 | リアルタイム走行情報・GPS ログ記録（`POST /api/rides` を rindo-api に新規実装した上で連携） |
| iOS-4 | ナビゲーション（詳細・簡易）+ 音声案内 |
| iOS-5 | オフラインマップ・走行モード・リマインダー |
| iOS-6 | Apple Watch 連携 |
| iOS-7 | 転倒検知 + SOS・写真スポット記録 |

## ライセンス・出典表示

Web 版と同様の出典表示が必要です。

- © OpenStreetMap contributors（ODbL）
- 北海道建設部土木局提供（CC-BY、北海道大規模自転車道）
- 出典：札幌市建設局（さっぽろサイクリングマップ デジタイズデータ）
- NASA SRTM 30m / OpenTopoData（標高）
- Valhalla（BSD-3-Clause、ルーティング）
- 気象庁（天気予報）

## 関連リポジトリ

- [Rindo-web](https://github.com/osprey74/Rindo-web) — ルート計画・データ管理 Web フロントエンド
- [rindo-api](https://github.com/osprey74/rindo-api) — 認証・ルート・地点・走行ログ API
