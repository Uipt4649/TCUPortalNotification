# TCUPortalNotification
![Platform](https://img.shields.io/badge/Platform-iOS-0A84FF?style=for-the-badge&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=for-the-badge)
![Backend](https://img.shields.io/badge/Backend-Python-3776AB?style=for-the-badge&logo=python)
![Firebase](https://img.shields.io/badge/BaaS-Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![License](https://img.shields.io/badge/License-Private-black?style=for-the-badge)

東京都市大学ポータルの更新を見逃さないための iOS 通知アプリです。  
ポータルから取得したお知らせを Firestore 経由で表示し、新着時に通知します。

## 主な機能

- 受信箱表示（タイトル検索つき）
- 種別ごとの横スワイプ切り替え表示
- 重要タブ（休講 / 教室変更 / 課題を自動抽出）
- ポータル再認証が必要なときの復旧フロー表示

## ディレクトリ構成

- `TCUPortalNotification/` iOS アプリ（SwiftUI）
- `backend/` ポータル取得・Firestore同期（Python + Playwright）

## 動かし方（最短）

### 1) iOS アプリ

```bash
cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification
open TCUPortalNotification.xcodeproj
```

Xcode で `Cmd + R` を実行してください。

### 2) バックエンド同期

```bash
cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m playwright install chromium
cp .env.example .env
python src/run_once.py
```

詳細は [backend/README.md](./backend/README.md) を参照してください。

## 再認証が必要なとき

Microsoft SSO のセッションが切れると取得が止まります。次を実行して再開します。

```bash
cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend
source .venv/bin/activate
python src/run_once.py --init-session
python src/run_once.py
```

## セキュリティ注意

- `.env` / `backend/.env` / `backend/secrets/` は Git に含めない
- `GoogleService-Info.plist` は公開リポジトリに含めない
- 認証情報を画面共有・スクリーンショットに出さない

## 免責

本プロジェクトの利用は、大学ポータルの利用規約と法令に従ってください。  
取得間隔はサーバー負荷を考慮し、短くしすぎない運用（10〜15分以上推奨）を行ってください。
