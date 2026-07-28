# リモート開発・TestFlight自動配布

このリポジトリは、`main` へのPushを自宅Macで検知し、次の順で処理します。

```
GitHub更新検知 → git pull --ff-only → Build → Archive → IPA Export
                 → App Store Connect Upload → TestFlight内部配布
```

Apple公式の `xcodebuild` と `altool` を使用します。常駐方式は、ログインユーザーの
Keychain（署名証明書）とmacOS通知を利用できるLaunchAgentです。

## 1. 一度だけ必要なApple側の準備

1. Apple Developer Programに加入する。
2. App Store ConnectでBundle ID `com.malatanglog.app` のアプリを作成する。
3. Xcodeの **Settings > Accounts > Manage Certificates** で
   `Apple Distribution` 証明書を作成し、このMacのKeychainへ保存する。
4. App Store Connectの **Users and Access > Integrations** でAPIキーを作成する。
   - 推奨ロール: `App Manager`
   - Key ID、Issuer ID、ダウンロードした `.p8` を保存する。
   - `.p8` は一度しかダウンロードできないため、Gitには絶対に追加しない。
5. App Store Connectの **TestFlight > Internal Testing** で内部グループを作成する。
   - **Enable automatic distribution** を有効にする。
   - iPhoneで使うApple Accountを内部テスターとして追加する。

このアプリは独自暗号機能を使用していないため、`Info.plist` に
`ITSAppUsesNonExemptEncryption = false` を設定済みです。

## 2. GitHubとの同期

このフォルダでGitを初期化し、GitHub上に作成した非公開リポジトリを登録します。
SSH URLの利用を推奨します。

```bash
git init -b main
git add .
git commit -m "Initial commit"
git remote add origin git@github.com:YOUR_ACCOUNT/MalatangLog.git
git push -u origin main
```

LaunchAgentを有効にする前に、同じmacOSユーザーで一度 `git fetch origin` を実行し、
SSHホスト鍵とGitHub認証を確認してください。

## 3. ローカル設定とLaunchAgent

最初の実行で、Git管理外の設定ファイルを作成します。

```bash
./Scripts/install-launch-agent.sh
```

作成された次のファイルを編集します。

```text
~/Library/Application Support/MalatangLogCI/config.env
```

APIキーは次へ配置します。

```text
~/Library/Application Support/MalatangLogCI/private_keys/AuthKey_<KEY_ID>.p8
```

推奨パーミッション:

```bash
chmod 600 "$HOME/Library/Application Support/MalatangLogCI/config.env"
chmod 600 "$HOME/Library/Application Support/MalatangLogCI/private_keys/"*.p8
```

設定後、もう一度実行するとLaunchAgentが登録され、直ちに初回確認を行います。

```bash
./Scripts/install-launch-agent.sh
```

標準の確認間隔は5分です。変更する場合は登録時に秒数を指定します。

```bash
POLL_INTERVAL_SECONDS=60 ./Scripts/install-launch-agent.sh
```

## 4. 動作確認

まずGit同期を行わず、Buildだけを確認できます。

```bash
SKIP_GIT_SYNC=true ./Scripts/build.sh
```

ArchiveとIPA Export:

```bash
./Scripts/archive.sh
```

最新IPAの検証とUpload:

```bash
./Scripts/upload.sh
```

全工程:

```bash
./Scripts/pipeline.sh
```

LaunchAgentの状態:

```bash
launchctl print "gui/$(id -u)/com.malatanglog.autobuild"
```

解除:

```bash
./Scripts/uninstall-launch-agent.sh
```

## 5. ログと失敗時の扱い

| 工程 | ログ |
|---|---|
| Build | `logs/build.log` |
| Archive / Export | `logs/archive.log` |
| Upload | `logs/upload.log` |
| 全体 | `logs/pipeline.log` |
| 更新監視 | `logs/watcher.log` / `logs/launchagent.log` |

失敗したコミットは自動的に何度も再アップロードしません。ログを確認して修正をPush
するか、同じコミットを再試行する場合は `./Scripts/pipeline.sh` を手動実行します。
ローカル変更や履歴分岐がある場合、データ保護のため自動resetは行わず停止します。

Apple側でBuildの処理が完了すると、automatic distributionを有効にした内部グループへ
配布されます。TestFlightアプリで自動更新を有効にするか、更新ボタンを押してください。

## 6. 各スクリプトの責務

- `build.sh`: 最新取得、依存解決、Release Build
- `archive.sh`: Archive、App Store Connect用IPA Export、Build番号生成
- `upload.sh`: IPA検証、App Store Connect Upload
- `pipeline.sh`: 排他制御、全工程実行、成功/失敗通知
- `check-for-updates.sh`: GitHub更新検知、コミット単位の実行制御

## 公式資料

- [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)

