# TCU Portal Integration (Backend)

このディレクトリは、東京都市大学ポータルの「お知らせ」を取得して Firestore に保存するための最小実装です。

## 0. 先に確認すること

- 大学ポータルの利用規約に反しない範囲で利用してください。
- 取得間隔は短くしすぎないでください（推奨: 10〜15分以上）。

## 1. セットアップ

```bash
cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m playwright install chromium
cp .env.example .env
```

## 2. `.env` を編集

`backend/.env` を開き、以下を設定します。

- `PORTAL_USER_ID`
- `PORTAL_PASSWORD`
- `FIREBASE_PROJECT_ID` (任意。運用時に便利)
- `GOOGLE_APPLICATION_CREDENTIALS` (`./secrets/service-account.json` を推奨)

### 重要: セレクタの更新

`.env.example` に入っているセレクタは仮値です。  
ポータルHTMLに合わせて次を更新してください。

- `PORTAL_USER_ID_SELECTOR`
- `PORTAL_PASSWORD_SELECTOR`
- `PORTAL_LOGIN_BUTTON_SELECTOR`
- `PORTAL_NOTICE_ITEM_SELECTOR`
- `PORTAL_NOTICE_TITLE_SELECTOR`
- `PORTAL_NOTICE_DATE_SELECTOR`
- `PORTAL_NOTICE_LINK_SELECTOR`
- `PORTAL_NOTICE_BODY_SELECTOR`

## 3. Firebase サービスアカウントJSONを配置

`backend/secrets/service-account.json` に配置します。

```bash
export GOOGLE_APPLICATION_CREDENTIALS=./secrets/service-account.json
```

`.env` に書いておけば `run_once.py` 実行時に読み込まれます。

## 4. 動作確認（1回実行）

```bash
cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend
source .venv/bin/activate
python src/run_once.py
```

成功時:
- `scraped notices: N`
- `created=X updated=Y`

が表示され、Firestore の `notices` コレクションにデータが入ります。

## 4.1 Microsoft SSOで自動取得が0件になる場合（推奨）

初回だけ手動ログインしてセッションを保存します。

```bash
cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend
source .venv/bin/activate
python src/run_once.py --init-session
```

ブラウザでログインを完了したら、ターミナルへ戻って Enter を押してください。  
`./secrets/portal_session.json` が作成され、以後の `python src/run_once.py` で再利用されます。

## 5. 次の実装

- Cloud Run Job へこのスクリプトを移す
- Cloud Scheduler で定期実行
- Firestore 追加時に FCM 通知（実装済み）

## 5.1 プッシュ通知（FCM）について

- iOSアプリ起動時、`device_tokens` コレクションへFCMトークンを保存します。
- `python src/run_once.py` 実行時に新規お知らせがあれば、登録済みトークンへプッシュ送信します。
- 送信結果はターミナルに `push sent=... failed=...` と表示されます。

### 注意

- iOSの実機プッシュには Apple Developer 側の Push 設定（APNs）と、Firebase Cloud Messaging 設定が必要です。
- シミュレータ環境では実機と同じプッシュ挙動にならない場合があります。

## 6. ここまで完了後の運用手順（あなたが毎回やること）

### 6.1 手動で1回実行

```bash
cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend
source .venv/bin/activate
python src/run_once.py
```

### 6.2 0件になるとき

1. セッションを作り直す
```bash
cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend
source .venv/bin/activate
rm -f secrets/portal_session.json
python src/run_once.py --init-session
```
2. ブラウザで手動ログイン
3. ターミナルで Enter
4. もう一度 `python src/run_once.py`

### 6.3 iOSアプリで確認

1. Xcodeで `Cmd + R`
2. 受信箱にFirestoreのデータが表示されることを確認
3. 表示が古い場合はもう一度 `python src/run_once.py`

## 7. 本番公開前チェックリスト

1. Firestore ルールをテストモードから制限付きへ変更
2. `.env` / `service-account.json` / `portal_session.json` をGitに含めない
3. 通知の重複送信防止（同一noticeIdのみ）
4. 取得間隔は10〜15分以上に設定
5. 利用規約に適合しているか最終確認
