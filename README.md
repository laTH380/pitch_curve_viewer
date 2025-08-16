# pitch_curve_viewer

ピッチ情報をグラフ表示するWEBアプリケーションのフロントエンド

## ホスティングURL

https://victorious-moss-02f80d400.5.azurestaticapps.net/

## 機能
- 音声ファイルの取得,確認
- httpでバックエンドへ送信、結果を取得
- グラフ表示

## 使い方

### WEBアプリケーション版（推奨）
1. [こちらのURL](https://victorious-moss-02f80d400.5.azurestaticapps.net/) にアクセス
2. 「Upload Audio File」ボタンをクリック
3. 1MB以下のMP3ファイルを選択
4. 処理が完了すると、音声のピッチカーブがグラフで表示されます

### ローカル開発環境での実行
#### 前提条件
- Flutter SDK（3.4.0以上）がインストールされている
- Dartがインストールされている
- インターネット接続（バックエンドAPIとの通信に必要）

#### セットアップ手順
1. リポジトリをクローン
```bash
git clone https://github.com/laTH380/pitch_curve_viewer.git
cd pitch_curve_viewer
```

2. 依存関係をインストール
```bash
flutter pub get
```

3. アプリを起動
- Web版を起動する場合（Chrome）:
```bash
flutter run -d chrome
```
- Web版を起動する場合（Edge）:
```bash
flutter run -d edge
```
- デスクトップ版を起動する場合（Windows）:
```bash
flutter run -d windows
```

## 機能詳細

### 対応ファイル形式
- **MP3形式のみ** （1MB以下）
- WAVやその他の形式は [Convertio](https://convertio.co/ja/wav-mp3/) などで変換してください

### グラフの見方
- **横軸**: 時間（秒）
- **縦軸**: 周波数（Hz）- 対数スケール表示
- グラフの点にマウスをホバーすると、その時点での正確な周波数が表示されます
- 青い線がピッチカーブを表示します

### 用途
- 音声分析
- 調声の参考（「カタチをまねすれば同じような発音になる...かも?」）
- 音声のピッチパターンの可視化

## 技術仕様

### フロントエンド
- **Flutter** - クロスプラットフォーム対応
- **fl_chart** - グラフ表示
- **file_picker** - ファイル選択
- **http/dio** - バックエンド通信
- **audioplayers** - 音声再生機能

### バックエンド
- Python Flask
- 基本周波数（F0）推定アルゴリズム
- Azure App Service でホスティング

## 制限事項
- ファイルサイズ: 1MB以下のみ対応
- ファイル形式: MP3のみ対応
- 処理時間: ファイルサイズによって数秒〜数十秒かかる場合があります

## 開発者情報
© 2024 laTH　contact→https://lath-memorandum.netlify.app/profiel
