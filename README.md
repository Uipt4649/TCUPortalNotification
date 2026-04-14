# TCUPortalNotification

![Platform](https://img.shields.io/badge/Platform-iOS-0A84FF?style=for-the-badge&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-5E5CE6?style=for-the-badge)
![Backend](https://img.shields.io/badge/Backend-Python-3776AB?style=for-the-badge&logo=python)
![Firebase](https://img.shields.io/badge/Firebase-Firestore%20%2B%20FCM-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![License](https://img.shields.io/badge/License-Private-1F1F1F?style=for-the-badge)

東京都市大学ポータルの更新を見逃さないための、個人運用向け iOS 通知アプリです。  
ポータル情報を Firestore に同期し、アプリ側で見やすく整理して表示します。



https://github.com/user-attachments/assets/08686c0b-4ef9-44e6-bc15-2b77b03f2d5c










---

## どんなアプリ？

| できること | 内容 |
|---|---|
| 受信箱 | タイトル検索 + 種別ごとの横スワイプ切り替え |
| 重要タブ | 休講 / 教室変更 / 課題系キーワードを自動抽出 |
| 復旧導線 | セッション切れ時に「再認証が必要」と明確に表示 |
| ポータル導線 | 各お知らせからポータル詳細へ移動 |

---

## 画面の考え方

1. **受信箱**: 最新のお知らせを確認  
2. **重要**: 見逃しリスクが高い通知だけ確認  
3. **設定**: 再認証や運用状態を確認

---

## ディレクトリ構成

- `TCUPortalNotification/` iOS アプリ（SwiftUI）
- `backend/` 取得・同期処理（Python + Playwright + Firestore）

/Users/ui/Desktop/スクリーンショット 2026-04-14 15.14.27.png


---

## セットアップ（最短）

### 1) iOS アプリ

```bash
cd .
open TCUPortalNotification.xcodeproj
```

Xcode で `Cmd + R` を実行します。

### 2) バックエンド同期

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m playwright install chromium
cp .env.example .env
python src/run_once.py
```

詳細: [backend/README.md](./backend/README.md)

---

## 再認証フロー

Microsoft SSO のセッションが切れると取得が停止します。  
以下を実行して復旧します。

```bash
cd backend
source .venv/bin/activate
python src/run_once.py --init-session
python src/run_once.py
```

---

## セキュリティ

- `.env` / `backend/.env` / `backend/secrets/` は Git に含めない
- `GoogleService-Info.plist` は公開リポジトリに含めない
- 認証情報が写った画面共有・スクリーンショットは避ける

---

## 運用メモ

- 取得間隔は 10〜15 分以上を推奨（大学サーバー負荷配慮）
- 本プロジェクトの利用は大学ポータル規約・法令の範囲内で行う
