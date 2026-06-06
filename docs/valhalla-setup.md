# Valhalla サーバーの構築手順

Rindo の「Valhalla（自転車専用）」ルーティングモードを使うには、自分で Valhalla ルーティングサーバーを用意する必要があります。このドキュメントでは Mac での構築手順を説明します。

## 前提条件

- macOS（Apple Silicon / Intel 両対応）
- Homebrew がインストール済み
- ターミナル操作ができること

## 概要

Valhalla はオープンソースの経路探索エンジンで、OpenStreetMap データから自転車用ルートを計算できます。Docker コンテナとして動かすのが最も簡単です。

```
Rindo アプリ → (HTTPS) → Valhalla サーバー (:8002)
```

---

## Step 1: Docker 環境の準備

Mac では [Colima](https://github.com/abiosoft/colima)（軽量な Docker ランタイム）を使います。

```bash
brew install colima docker
colima start
```

> Colima はデフォルトで 4 CPU / 6GB RAM / 20GB Disk を割り当てます。
> Valhalla のタイル構築にはこの程度のリソースが必要です。

## Step 2: 地図データ（PBF）の準備

OpenStreetMap の地図データをダウンロードして、必要な地域を切り出します。

```bash
mkdir -p ~/valhalla/custom_files

# Geofabrik から北海道の地図データをダウンロード
curl -L -o hokkaido-latest.osm.pbf \
  https://download.geofabrik.de/asia/japan/hokkaido-latest.osm.pbf
```

### 地域の切り出し（任意）

全北海道データでも動作しますが、対象地域を限定するとタイル構築が高速になります。
道央圏（札幌周辺）のみ使う場合：

```bash
brew install osmium-tool

osmium extract \
  --bbox 140.8,42.4,142.6,43.6 \
  hokkaido-latest.osm.pbf \
  --output ~/valhalla/custom_files/dosou-latest.osm.pbf
```

全北海道をそのまま使う場合は、ダウンロードしたファイルをそのまま配置します。

```bash
mv hokkaido-latest.osm.pbf ~/valhalla/custom_files/
```

> 他の地域を使いたい場合は [Geofabrik ダウンロード](https://download.geofabrik.de/) から
> 該当地域の PBF ファイルをダウンロードしてください。

## Step 3: Valhalla コンテナの起動

```bash
docker run -d \
  --name valhalla \
  --restart unless-stopped \
  -p 8002:8002 \
  -v ~/valhalla/custom_files:/custom_files \
  -e build_elevation=False \
  -e build_admins=True \
  ghcr.io/valhalla/valhalla-scripted:latest
```

初回起動時にタイルデータの構築が行われます（30〜60 分程度）。進捗確認：

```bash
docker logs -f valhalla
```

`Listening on port 8002` と表示されたら準備完了です。

> **注意**: `build_elevation=False` は必須です。True にすると segfault が発生します。
> 標高データは Rindo アプリ側で別途取得しています。

## Step 4: 動作確認

```bash
curl -s -X POST http://localhost:8002/route \
  -H 'Content-Type: application/json' \
  -d '{
    "locations": [
      {"lon": 141.3468, "lat": 43.0686},
      {"lon": 141.3514, "lat": 43.0607}
    ],
    "costing": "bicycle"
  }' | head -c 200
```

JSON レスポンスが返ってくれば成功です。

## Step 5: 外部アクセスの設定

iPhone から Mac の Valhalla にアクセスするには、ネットワーク経由でポート 8002 を公開する必要があります。

### 方法 A: Tailscale（推奨）

[Tailscale](https://tailscale.com/) を使うと、iPhone と Mac を VPN で直接接続できます。

1. Mac と iPhone の両方に Tailscale をインストール
2. 同じアカウントでログイン
3. Mac の Tailscale IP（例: `100.x.x.x`）を確認

Rindo アプリの設定画面で以下を入力：
```
http://100.x.x.x:8002
```

### 方法 B: 同一 Wi-Fi ネットワーク

Mac と iPhone が同じ Wi-Fi に接続されている場合：

1. Mac の IP アドレスを確認（システム設定 → Wi-Fi → 詳細）
2. Docker のポートバインドを `0.0.0.0` に変更：

```bash
docker stop valhalla && docker rm valhalla
docker run -d \
  --name valhalla \
  --restart unless-stopped \
  -p 0.0.0.0:8002:8002 \
  -v ~/valhalla/custom_files:/custom_files \
  -e build_elevation=False \
  -e build_admins=True \
  ghcr.io/valhalla/valhalla-scripted:latest
```

Rindo アプリの設定画面で以下を入力：
```
http://192.168.x.x:8002
```

> **注意**: 方法 B は同一ネットワーク内でのみ動作し、外出先では使えません。

## Step 6: Rindo アプリでの設定

1. 設定 → ルーティング → **Valhalla（自転車専用）** を選択
2. サーバー URL にアドレスを入力
3. **接続テスト** をタップして動作確認

---

## 管理コマンド

```bash
# 状態確認
docker ps | grep valhalla

# ログ確認
docker logs --tail 50 valhalla

# 停止 / 再起動
docker stop valhalla
docker start valhalla

# 地図データの更新（新しい PBF を配置して再構築）
docker stop valhalla && docker rm valhalla
# → Step 2 の PBF を更新してから Step 3 を再実行
```

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| タイル構築中に segfault | `build_elevation=False` になっているか確認 |
| 接続テスト失敗 | Valhalla コンテナが起動しているか `docker ps` で確認 |
| ルートが見つからない | PBF データに目的地の地域が含まれているか確認 |
| Colima が起動しない | `colima delete && colima start` で再作成 |
