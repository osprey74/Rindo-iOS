# Rindo Android 移植ハンドオフ

> iOS 版 Rindo (v1.0.0) の全ロジック・UI・データ構造をまとめたドキュメント。
> Android 版を iOS 版と同等の機能で実装するための仕様書として使用する。

---

## 1. アプリ概要

Rindo は札幌・道央圏向けサイクリングナビゲーションアプリ。地図をロングプレスして目的地を設定し、現在地からのルートを自動計算、ターンバイターン音声ナビゲーションで案内する。コース逸脱時は自動リルート。

### コア機能

| 機能 | 概要 |
|------|------|
| 目的地設定 | 地図ロングプレス → ルート自動計算 |
| ナビゲーション | ターンバイターン音声案内、ヘッドアップ表示 |
| 自動リルート | 30m逸脱で自動再計算（30秒クールダウン） |
| 走行記録 | GPS トラック・速度・距離・標高・カロリー |
| 2つのルーティング | 標準（Google Directions相当）/ Valhalla（自転車専用） |
| 簡易ナビ | 黒背景 + 大きい矢印（OLED 省電力） |
| GPX インポート/エクスポート | 外部ルート取り込み・走行ログ書き出し |
| オフラインマップ | タイルキャッシュ（zoom 8-15） |

---

## 2. アーキテクチャ

### iOS → Android 対応表

| iOS | Android |
|-----|---------|
| SwiftUI | Jetpack Compose |
| @Observable | StateFlow / MutableStateFlow |
| @AppStorage | DataStore / SharedPreferences |
| SwiftData | Room Database |
| MapLibre Native iOS | MapLibre GL Android SDK |
| MKDirections (.walking) | Google Directions API (walking) |
| AVSpeechSynthesizer | Android TextToSpeech |
| HealthKit | Health Connect (Google) |
| CoreLocation | FusedLocationProviderClient |
| Keychain | Android Keystore / EncryptedSharedPreferences |
| URLSession | Retrofit + OkHttp |
| UNNotification | NotificationCompat |

### プロジェクト構成（推奨）

```
app/src/main/java/com/osprey74/rindo/
├── RindoApp.kt                    # Application class
├── MainActivity.kt                # Single Activity (Compose)
├── core/
│   ├── routing/
│   │   ├── RouteProvider.kt       # インターフェース
│   │   ├── GoogleRouteProvider.kt # 標準モード
│   │   ├── ValhallaRouteProvider.kt
│   │   ├── NavigationRoute.kt     # 共通データクラス
│   │   └── PolylineDecoder.kt
│   ├── location/
│   │   └── LocationService.kt
│   ├── ride/
│   │   ├── RideRecorder.kt
│   │   ├── RideLog.kt             # Room Entity
│   │   ├── RideMode.kt
│   │   └── ReminderManager.kt
│   ├── api/
│   │   ├── ApiClient.kt           # Retrofit interface
│   │   └── models/                # DTO classes
│   ├── storage/
│   │   ├── TokenStore.kt
│   │   └── OfflineMapManager.kt
│   ├── gpx/
│   │   ├── GpxParser.kt
│   │   ├── GpxExporter.kt
│   │   └── ImportedRoute.kt       # Room Entity
│   └── health/
│       └── HealthConnectService.kt
├── features/
│   ├── map/
│   │   ├── MapScreen.kt           # メイン画面（Composable）
│   │   └── RindoMapView.kt        # MapLibre wrapper
│   ├── navigation/
│   │   ├── NavigationManager.kt
│   │   ├── VoiceGuide.kt
│   │   ├── TurnByTurnPanel.kt
│   │   ├── SimpleNavView.kt
│   │   ├── NavigationInfoPanel.kt
│   │   └── ManeuverParser.kt
│   ├── settings/
│   │   ├── SettingsScreen.kt
│   │   └── OfflineMapScreen.kt
│   ├── routes/
│   │   ├── SavedRoutesPanel.kt
│   │   └── ImportedRoutesPanel.kt
│   ├── locations/
│   │   └── SavedLocationsPanel.kt
│   ├── ride/
│   │   └── RideHistoryPanel.kt
│   ├── elevation/
│   │   ├── ElevationService.kt
│   │   └── ElevationChart.kt
│   └── auth/
│       ├── AuthService.kt
│       └── LoginScreen.kt
└── ui/
    └── theme/                     # Colors, Typography
```

---

## 3. ルーティングエンジン

### RouteProvider インターフェース

```kotlin
interface RouteProvider {
    suspend fun fetchRoute(
        from: LatLng,
        to: LatLng
    ): NavigationRoute

    suspend fun fetchRoute(
        waypoints: List<LatLng>
    ): NavigationRoute
}
```

### 共通データモデル

```kotlin
data class NavigationRoute(
    val coordinates: List<LatLng>,
    val maneuvers: List<NavigationManeuver>,
    val totalDistanceKm: Double,
    val totalTimeSeconds: Double
)

data class NavigationManeuver(
    val type: Int,              // Valhalla maneuver type (0-27)
    val instruction: String,
    val voiceInstruction: String,
    val distanceKm: Double,
    val timeSeconds: Double,
    val coordinate: LatLng,
    val bearingAfter: Int       // 0-359°
)
```

### 標準モード（Google Directions 相当）

iOS では `MKDirections (.walking)` を使用。Android では Google Directions API の walking モードを使用する。

**アルゴリズム：**
1. ウェイポイントが2点以上であることを検証
2. 各セグメントペアごとに walking ルートを取得
3. ステップを `NavigationManeuver` に変換（型推定ロジック後述）
4. セグメントを結合（2番目以降の最初の座標は重複するので除去）
5. 所要時間を自転車速度で補正: `totalTime × (5.0 / 18.0)`（徒歩5km/h → 自転車18km/h）

**マニューバ型推定（日本語テキストから）：**

| テキスト | type | 意味 |
|---------|------|------|
| 「右に曲」「右折」 | 10 | Right |
| 「左に曲」「左折」 | 15 | Left |
| 「斜め右」「やや右」 | 9 | SlightRight |
| 「斜め左」「やや左」 | 16 | SlightLeft |
| 「Uターン」「折り返」 | 12 | UturnRight |
| 「直進」「まっすぐ」 | 8 | Continue |
| 「合流」 | 25 | Merge |

テキストで判別できない場合は、前後のポリライン座標から方位角変化を計算：

| 角度変化 (δ) | type |
|-------------|------|
| |δ| < 20° | 8 (Continue) |
| 0° < δ < 60° | 9 (SlightRight) |
| 60° ≤ δ < 130° | 10 (Right) |
| δ ≥ 130° | 12 (UturnRight) |
| -60° < δ < 0° | 16 (SlightLeft) |
| -130° < δ ≤ -60° | 15 (Left) |
| δ ≤ -130° | 13 (UturnLeft) |

**方位角計算（Haversine bearing）：**

```kotlin
fun calculateBearing(from: LatLng, to: LatLng): Int {
    val lat1 = Math.toRadians(from.latitude)
    val lat2 = Math.toRadians(to.latitude)
    val dLon = Math.toRadians(to.longitude - from.longitude)
    val y = sin(dLon) * cos(lat2)
    val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    val bearing = Math.toDegrees(atan2(y, x))
    return ((bearing + 360) % 360).toInt()
}
```

### Valhalla モード

**エンドポイント：** `POST {baseURL}/api/valhalla/route`

**リクエスト：**
```json
{
  "locations": [{"lon": 141.3468, "lat": 43.0686}, ...],
  "costing": "bicycle",
  "costing_options": {
    "bicycle": {
      "bicycle_type": "Road",
      "use_roads": 0.1,
      "use_trails": 1.0
    }
  },
  "directions_options": {"language": "ja"}
}
```

**レスポンス解析：**
- `trip.legs[0].shape` → Encoded Polyline（precision 6）をデコード
- `trip.legs[0].maneuvers[]` → 各マニューバの `type`, `instruction`, `verbal_pre_transition_instruction`, `bearing_after`, `length`(km), `time`(s), `begin_shape_index`
- `trip.summary.length`(km), `trip.summary.time`(s)

### PolylineDecoder（Valhalla encoded polyline）

```kotlin
fun decode(encoded: String, precision: Int = 6): List<LatLng> {
    val factor = 10.0.pow(precision)
    val result = mutableListOf<LatLng>()
    var index = 0
    var lat = 0
    var lng = 0
    while (index < encoded.length) {
        // lat
        var shift = 0; var b: Int; var result2 = 0
        do {
            b = encoded[index++].code - 63
            result2 = result2 or ((b and 0x1f) shl shift)
            shift += 5
        } while (b >= 0x20)
        lat += if (result2 and 1 != 0) (result2 shr 1).inv() else result2 shr 1
        // lng
        shift = 0; result2 = 0
        do {
            b = encoded[index++].code - 63
            result2 = result2 or ((b and 0x1f) shl shift)
            shift += 5
        } while (b >= 0x20)
        lng += if (result2 and 1 != 0) (result2 shr 1).inv() else result2 shr 1
        result.add(LatLng(lat / factor, lng / factor))
    }
    return result
}
```

---

## 4. ナビゲーション

### NavigationManager

**状態：**
```kotlin
data class NavigationState(
    val isActive: Boolean = false,
    val route: NavigationRoute? = null,
    val currentManeuverIndex: Int = 0,
    val distanceToNextManeuverM: Double = 0.0,
    val remainingDistanceKm: Double = 0.0,
    val remainingTimeSeconds: Double = 0.0,
    val isRerouting: Boolean = false
)
```

**定数：**

| 定数 | 値 | 用途 |
|------|-----|------|
| `REROUTE_COOLDOWN_SECONDS` | 30 | リルート間隔制限 |
| `DEVIATION_THRESHOLD_M` | 30 | 逸脱検知閾値 |
| `MIN_TRAVEL_RATIO` | 0.1 | ルート10%走行するまで逸脱判定しない |
| `ARRIVAL_TRAVEL_RATIO` | 0.5 | ルート50%走行するまで到着判定しない |
| `ARRIVAL_DISTANCE_M` | 30 | 到着判定距離 |
| `MANEUVER_PROXIMITY_M` | 20 | マニューバ通過判定距離 |
| `POST_SPEECH_DELAY_SEC` | 1.0 | 発話後クールダウン |

**start() ロジック：**
1. ルート・ウェイポイントを保持
2. 最初の非 Start マニューバを検索（type 1-3 をスキップ）
3. 走行距離・到着閾値をリセット
4. 開始音声：「目的地まで{距離}、約{分}分。ナビゲーションを開始します。」
5. 距離フォーマット：1km 未満は「{m}メートル」、1km 以上は「{x.x}キロメートル」

**updateLocation() ロジック（毎回の位置更新で呼ばれる）：**
1. 走行距離を累積
2. ルート上の最近接点を探索（全座標を線形探索）
3. 最近接点までの距離が30m超 かつ 走行距離がルートの10%超 → 逸脱 → `RerouteRequest` を返す
4. マニューバ進捗を更新（現在のマニューバ地点から20m以内なら次に進む）
5. 次マニューバまでの距離を計算
6. 音声トリガを判定

**triggerVoiceIfNeeded() ロジック：**
```
if 発話中またはクールダウン中 → スキップ

for threshold in voiceTriggerDistances:
    if distanceM <= threshold:
        key = "m{maneuverIndex}_{threshold}m"
        if threshold >= 100:
            text = "{threshold}メートル先、{voiceInstruction}"
        else:
            text = "まもなく、{voiceInstruction}"
        speak(text, key)
        break  // 最も近い閾値のみ

// 到着判定
if isDestination(type) && distanceM < 30 && traveled > 50%:
    speak("目的地に到着しました。", "arrival")
```

**音声トリガ距離（RideMode 別）：**

| モード | 閾値 (m) |
|--------|---------|
| 通勤 | [200, 100, 50] |
| レジャー | [500, 200, 100, 50] |
| トレーニング | [100, 50] |

**リルート：**
1. クールダウン（30秒）判定
2. 「ルートを再検索しています。」を発話
3. `RerouteRequest(from: 現在地, to: 最終目的地)` を返す
4. MapScreen が RouteProvider で新ルートを取得
5. `applyReroute()` で新ルートに切り替え、マニューバインデックスをリセット

### VoiceGuide

**Android 実装：** `TextToSpeech` エンジン

```kotlin
class VoiceGuide(context: Context) {
    private val tts = TextToSpeech(context) { status ->
        if (status == TextToSpeech.SUCCESS) {
            tts.language = Locale.JAPANESE
            tts.setSpeechRate(1.1f)
        }
    }
    private val spokenKeys = mutableSetOf<String>()
    private var isCoolingDown = false
    val isSpeaking: Boolean
        get() = tts.isSpeaking || isCoolingDown

    fun speak(text: String, key: String) {
        if (spokenKeys.contains(key)) return
        spokenKeys.add(key)
        tts.stop()  // 前の発話をキャンセル
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, key)
    }

    fun reset() {
        spokenKeys.clear()
        isCoolingDown = false
        tts.stop()
    }
}
```

**発話完了リスナー：** `UtteranceProgressListener.onDone()` でクールダウン（1秒）を開始

**Audio Focus：** `AudioManager.requestAudioFocus()` で他のアプリの音量を下げる（`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`）

### ManeuverParser（アイコンマッピング）

| type | 意味 | アイコン |
|------|------|---------|
| 0 | None | ↑ 直進 |
| 1-3 | Start | 🏁 旗 |
| 4-6 | Destination | 📍 ピン |
| 7-8 | Continue | ↑ 直進 |
| 9 | SlightRight | ↗ 右斜め |
| 10-11 | Right/SharpRight | ↱ 右折 |
| 12 | UturnRight | ↺ Uターン右 |
| 13 | UturnLeft | ↻ Uターン左 |
| 14-15 | SharpLeft/Left | ↰ 左折 |
| 16 | SlightLeft | ↖ 左斜め |
| 25 | Merge | ⇢ 合流 |
| 26-27 | Roundabout | ◎ ラウンドアバウト |

---

## 5. 地図表示

### MapLibre GL Android

**初期設定：**
- スタイル: バンドル `osm-style.json`（OpenStreetMap タイル）
- 初期中心: 43.0686°N, 141.3468°E（札幌）
- 初期ズーム: 12
- 回転: 無効（ナビ中のヘッドアップ以外）
- ティルト: 無効

**レイヤー構成：**

| レイヤー | 色 | 太さ | 備考 |
|---------|-----|------|------|
| ルート（白ハロー） | #FFFFFF | 8px | opacity 0.8 |
| ルート（青ライン） | #2563EB (systemBlue) | 5px | round join/cap |
| ウェイポイント | #2563EB | radius 8, stroke 2 | 円マーカー |
| 走行軌跡 | systemRed | 3px | opacity 0.8 |
| ナビ矢印 | #1925B2 | 32×32dp | 進行方向に回転 |
| 目的地線 | systemGray | 1.5px | ダッシュ [6,4], opacity 0.6 |
| 次マニューバピン | systemGreen | radius 10, stroke 3 | パルス: radius 18, opacity 0.3 |
| サイクリングロード（通常） | #E65C00 | 4px | オレンジ |
| サイクリングロード（大規模） | #6A5ACD | 5px | 紫 |

**目的地ピン（ロングプレス設定）：**
- 赤い丸（40dp）+ 白枠（3dp）+ 旗アイコン
- `centerOffset`: 上方向に半径分オフセット（ピンの下端が座標に合う）
- 影: 黒、offset (0, 3), blur 4, opacity 0.4

**地点マーカー（カテゴリ別）：**

| カテゴリ | 絵文字 | 背景色 |
|---------|--------|--------|
| home（自宅） | 🏠 | Blue |
| work（職場） | 🏢 | Purple |
| favorite（お気に入り） | ⭐ | Yellow |
| other（その他） | 📍 | Gray |

サイズ: 36dp、円形、白枠 2.5dp、影付き

**ナビ中のカメラ制御：**
- ヘッドアップ: `mapView.direction = course`（進行方向が上）
- 現在地を画面下 1/3 に配置: 画面中心を `mapHeight / 6` ピクセル分上にオフセット
- ナビ終了時: ノースアップ（direction = 0）に戻す

**ロングプレスジェスチャー：**
- 最小押下時間: 0.5秒
- ナビ中は無視
- タップ座標 → 地図座標変換 → `onDestinationSet` コールバック

**カメラフィット（ルート表示時）：**
- 全座標の bounding box を計算
- パディング: top 80, left 40, bottom 200, right 40（dp）

### ナビ矢印画像

- サイズ: 32×32dp（@3x = 96px）
- 色: 濃紺 #1925B2、白枠 2dp
- 形状: 上向き矢印、下部にくぼみ（BezierPath quadCurve）
- Canvas/Drawable で動的生成

---

## 6. 位置情報

### LocationService

**Android 実装：** `FusedLocationProviderClient`

**設定：**
- 精度: `PRIORITY_HIGH_ACCURACY`
- 更新間隔: 1秒
- 最小移動距離: 0m（全更新受信）
- バックグラウンド: Foreground Service で継続

**状態：**
```kotlin
data class LocationState(
    val currentLocation: Location? = null,
    val course: Double = 0.0,        // 0-359°
    val speedKmh: Double = 0.0,      // location.speed * 3.6
    val totalDistanceM: Double = 0.0, // 累積距離
    val isOffRoute: Boolean = false,
    val isTracking: Boolean = false
)
```

**コース更新条件：** `speed > 0.5 m/s` の場合のみ更新（停止時のノイズ防止）

**逸脱検知：**
- ルート座標列との最短距離を計算
- 30m 超で `isOffRoute = true`
- `onDeviation` コールバック → バイブレーション + サウンド

---

## 7. 走行記録

### RideRecorder

**状態：** `IDLE` → `RECORDING` ⇄ `PAUSED` → `IDLE`

**トラックポイント：**
```kotlin
data class RecordedTrackPoint(
    val latitude: Double,
    val longitude: Double,
    val altitude: Double,
    val timestamp: Long,     // epoch millis
    val speedMps: Double
)
```

**リアルタイム計測：**

| 項目 | 計算方法 |
|------|---------|
| 距離 | Haversine で前回地点からの距離を累積 |
| 速度 | `location.speed * 3.6`（km/h） |
| 標高 | `location.altitude` |
| 勾配 | 10秒間の高度変化 ÷ 水平距離 × 100（%） |
| カロリー | MET × 体重(kg) × 時間(h)。MET = 7.5 × (1 + max(0, grade%) × 0.1) |
| 獲得標高 | 正の高度変化の累積 |
| 経過時間 | `now - startTime - pausedDuration` |

**タイマー：** 1秒間隔で UI 更新（`Handler` / `Timer` / `coroutine delay`）

### RideLog（Room Entity）

```kotlin
@Entity(tableName = "ride_logs")
data class RideLog(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val name: String?,
    val startedAt: Long,           // epoch millis
    val endedAt: Long,
    val distanceKm: Double,
    val durationMin: Double,
    val ascentM: Double,
    val descentM: Double,
    val maxSpeedKmh: Double,
    val avgSpeedKmh: Double,
    val caloriesKcal: Double,
    val trackJson: String,         // JSON: [[lon, lat, ele, epoch_s, speed_mps], ...]
    val uploaded: Boolean = false
)
```

### RideMode

```kotlin
enum class RideMode(
    val displayName: String,
    val icon: String,
    val description: String,
    val navZoomLevel: Double,
    val voiceTriggerDistances: List<Double>,
    val remindersEnabled: Boolean
) {
    COMMUTE("通勤", "briefcase", "...", 18.0, listOf(200.0, 100.0, 50.0), false),
    LEISURE("レジャー", "bicycle", "...", 17.0, listOf(500.0, 200.0, 100.0, 50.0), true),
    TRAINING("トレーニング", "flame", "...", 19.0, listOf(100.0, 50.0), true)
}
```

### ReminderManager

- **休憩リマインダー：** 設定間隔（0/30/60/90分）ごとに音声 + 通知
- **補給リマインダー：** 設定間隔（0/30/50/80km）ごとに音声 + 通知
- **重複防止：** 発火済みマークで同じリマインダーを再発火しない
- **通勤モード：** リマインダー無効

---

## 8. API / 認証

### APIClient

**ベース URL：** `https://home-mac-mini.taila6ea.ts.net`
**タイムアウト：** 30秒

**エンドポイント：**

| メソッド | パス | 認証 | 用途 |
|---------|------|------|------|
| POST | `/api/auth/login` | 不要 | トークン取得 |
| POST | `/api/auth/logout` | 必要 | セッション無効化 |
| GET | `/api/auth/me` | 必要 | セッション検証 |
| GET | `/api/routes` | 必要 | 保存ルート一覧 |
| GET | `/api/locations` | 必要 | 保存地点一覧 |
| POST | `/api/rides` | 必要 | 走行ログアップロード |
| POST | `/api/valhalla/route` | 不要 | Valhalla ルーティング |

**認証：** `Authorization: Bearer {token}` ヘッダー
**JSON デコード：** snake_case → camelCase 自動変換

### データモデル

**SavedRoute：**
```kotlin
data class SavedRoute(
    val id: Int,
    val name: String,
    val description: String?,
    val waypoints: List<LonLat>,       // [{lon, lat}, ...]
    val geometry: GeoJSONLineString,   // {type, coordinates: [[lon, lat], ...]}
    val distanceKm: Double?,
    val durationMin: Double?,
    val ascentM: Double?,
    val descentM: Double?,
    val createdAt: String,
    val updatedAt: String
)
```

**SavedLocation：**
```kotlin
data class SavedLocation(
    val id: Int,
    val name: String,
    val notes: String?,
    val category: LocationCategory, // home, work, favorite, other
    val lon: Double,
    val lat: Double,
    val createdAt: String
)
```

---

## 9. 標高プロファイル

### ElevationService

**API エンドポイント：** `POST {baseURL}/api/elevation`（Caddy → OpenTopoData プロキシ）

**リクエスト：**
```json
{"locations": "lat,lon|lat,lon|..."}
```

**ダウンサンプリング：** ルート座標を最大60点に間引き（累積距離ベースの等間隔サンプリング）

**プロファイル計算：**
- 獲得標高：正の高度差の累積
- 損失標高：負の高度差の累積
- 最大勾配：`|dz / dx| × 100` の最大値

**ElevationProfile：**
```kotlin
data class ElevationProfile(
    val points: List<ElevationPoint>,  // {distanceKm, elevationM}
    val totalAscentM: Double,
    val totalDescentM: Double,
    val maxSlopePct: Double,
    val minElevationM: Double,
    val maxElevationM: Double
)
```

**チャート表示：** エリアチャート + ラインオーバーレイ、Y軸は min-10%〜max+10%（最低5mパディング）

---

## 10. GPX サポート

### GPXParser（XML パーサー）

**対応要素：**
- `<trk>/<trkseg>/<trkpt>` — トラック
- `<rte>/<rtept>` — ルート
- `<ele>` — 標高
- `<name>` — ルート名（デフォルト: 「インポートルート」）

**Android 実装：** `XmlPullParser` で SAX-like パース

### GPXExporter

**出力フォーマット：** GPX 1.1 XML
```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Rindo">
  <metadata><name>...</name><time>ISO8601</time></metadata>
  <trk><trkseg>
    <trkpt lat="..." lon="...">
      <ele>...</ele>
      <time>ISO8601</time>
      <extensions><speed>m/s</speed></extensions>
    </trkpt>
    ...
  </trkseg></trk>
</gpx>
```

### ImportedRoute（Room Entity）

```kotlin
@Entity(tableName = "imported_routes")
data class ImportedRoute(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val name: String,
    val importedAt: Long,
    val pointsJson: String,          // [[lon, lat, ele?], ...]
    val totalDistanceKm: Double
)
```

---

## 11. UI 画面仕様

### MapScreen（メイン画面）

**ボタンレイアウト（左上）：**

```
[縦列]        [横列（ルート有効時）]
現在地         ナビ / 簡易 / ナビ終了
ルート（※）    記録 / 一時停止 / 停止
地点（※）      履歴
設定

※ 認証済み時のみ表示
```

**ボタンスタイル：**
- サイズ: 48×48dp
- 背景: 黒 opacity 0.5、角丸 10dp
- テキスト: 白、9sp
- アイコン: 白、body サイズ

**情報バー（ナビ中、画面下部）：**
- 逸脱警告: 赤カプセル「ルートから外れています」
- 走行情報パネル: 速度 | 距離 | 経過時間（`ultraThinMaterial` 背景）
- ターンバイターンパネル（後述）
- ルート情報バー / 目的地情報バー

**目的地情報バー：**
- タイトル: 「目的地」
- ルート計算中: ProgressIndicator + 「ルート計算中...」
- 計算完了: 距離 + 所要時間 + 「ナビ開始」ボタン（青カプセル）
- ×ボタンでクリア

### TurnByTurnPanel

```
┌─────────────────────────────────┐
│ [アイコン]  279 m               │
│ 60×60      右方向です。         │
│ 青背景     その先南3条通です。   │
│─────────────────────────────────│
│ 残り 3.2 km    約 12 min       │
└─────────────────────────────────┘
```

- リルート中: `ProgressIndicator` + 「ルートを再検索中...」
- 距離フォーマット: 1km 未満は `{m} m`、1km 以上は `{x.x} km`
- 背景: `ultraThinMaterial`（Android: 半透明 + blur）

### SimpleNavView（全画面）

```
┌─────────────────────────────────┐
│                                 │
│           ➡ (120dp)            │
│                                 │
│          279 m (64sp)          │
│   右方向です。その先南3条通。    │
│                                 │
│                                 │
│  0 km/h     0.8 km残り    [🗺] │
└─────────────────────────────────┘
```

- 背景: 黒（OLED 省電力）
- タップで閉じてマップに戻る
- 矢印サイズ: 120dp
- 距離: 64sp、monospace

### NavigationInfoPanel

```
┌──────────────────────────────┐
│  0 km/h  │  38 m  │  02:17  │
└──────────────────────────────┘
```

- 3セル均等配置、区切り線あり
- 逸脱時: 赤枠
- 背景: `ultraThinMaterial`

### SettingsScreen

**セクション順：**
1. 走行モード（通勤/レジャー/トレーニング）
2. ルーティング（標準 Apple Maps / Valhalla）
   - Valhalla 選択時: URL 入力 + 接続テスト + 構築手順リンク
3. リマインダー（休憩/補給）
4. オフラインマップ
5. GPX ルート管理
6. サーバ接続（ログイン/ログアウト）
7. アプリ情報（バージョン）
8. 出典・ライセンス

---

## 12. オフラインマップ

### OfflineMapManager

**MapLibre Android Offline API：**
- タイルピラミッドリージョン: zoom 8-15
- コンテキスト: リージョン名を UTF-8 バイト配列で格納
- 容量上限: 500 MB

**容量見積もり：** `(radiusKm / 30)² × 100` MB

---

## 13. Health Connect（HealthKit 相当）

### HealthConnectService

**読み取り：**
- 体重（Weight record）→ カロリー計算に使用

**書き込み：**
- ExerciseSession（cycling）
- Distance（km）
- ActiveCaloriesBurned（kcal）

**権限：** ユーザー承認後のみアクセス

---

## 14. 設定の永続化

| 設定キー | 型 | デフォルト | 用途 |
|---------|-----|-----------|------|
| `rideMode` | String | "leisure" | 走行モード |
| `routingMode` | String | "apple" | ルーティング（"apple" or "valhalla"） |
| `valhallaServerURL` | String | "" | Valhalla サーバー URL |
| `breakIntervalMinutes` | Int | 60 | 休憩リマインダー間隔 |
| `refuelIntervalKm` | Double | 50.0 | 補給リマインダー間隔 |

Android: `DataStore<Preferences>` または `SharedPreferences`

---

## 15. バックグラウンド動作

### Foreground Service（Android 必須）

iOS ではバックグラウンドモード（location + audio）で動作。Android では以下が必要：

- `Foreground Service` with `FOREGROUND_SERVICE_TYPE_LOCATION`
- 常駐通知（ナビ中 or 走行記録中）
- `WakeLock`（画面消灯時もGPS継続）
- `TextToSpeech` はフォアグラウンドサービス内で発話

**Manifest 宣言：**
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

---

## 16. iOS → Android 主要な差異

| 項目 | iOS | Android |
|------|-----|---------|
| バックグラウンド位置情報 | Background Mode 宣言のみ | Foreground Service 必須 |
| 音声案内 | AVSpeechSynthesizer（システム内蔵） | TextToSpeech（エンジン依存） |
| 地図回転 | `mapView.direction = course` | `mapLibreMap.moveCamera(bearing)` |
| ヘルスデータ | HealthKit（Apple） | Health Connect（Google） |
| オフライン地図 | MLNOfflinePack | MapLibre OfflineManager |
| 画面ロック防止 | `UIApplication.isIdleTimerDisabled` | `FLAG_KEEP_SCREEN_ON` |
| 触覚フィードバック | UIImpactFeedbackGenerator | Vibrator / HapticFeedbackConstants |
| ファイル共有 | ShareLink + UIActivityViewController | Intent.ACTION_SEND + FileProvider |
| ルーティング（標準） | MKDirections (.walking) | Google Directions API (walking) |

---

## 17. ビルド・リリース

| 項目 | 値 |
|------|-----|
| アプリ名 | Rindo - Cycling Navi |
| パッケージ名 | com.osprey74.rindo |
| 最低 API | API 26 (Android 8.0) — Health Connect 要件 |
| ターゲット API | 最新（API 35） |
| 言語 | Kotlin |
| UI | Jetpack Compose |
| ビルドシステム | Gradle (Kotlin DSL) |
