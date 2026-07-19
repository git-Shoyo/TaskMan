# taskman

TaskMan は Firebase/Firestore を使う Flutter 製のタスク管理アプリです。
組織、プロジェクト、タスク、Issue、分析、Gantt 表示、Microsoft Planner 取り込みを扱います。

## 開発環境

- Flutter stable
- Dart SDK 3.12 以降
- Firebase CLI
- Firebase Authentication: Email/Password を有効化
- Cloud Firestore を作成

## セットアップ

```powershell
flutter pub get
```

Firebase 設定は `lib/firebase_options.dart` と `firebase.json` に含まれています。
Firestore ルールを更新した場合は、次を実行してください。

```powershell
firebase deploy --only firestore:rules,firestore:indexes
```

## ローカル検証

```powershell
flutter analyze
flutter test
```

CI でも同じ検証を実行します。

## 対応プラットフォーム

- Android / iOS / macOS / Windows / Web は Firebase 設定済み
- Linux は Flutter プロジェクト自体はありますが、Firebase options が未設定です
- Windows では小窓 Gantt のネイティブ表示に対応しています

## 既知の制限

- Microsoft Planner 連携は接続直後または設定画面からの手動同期です。常駐の定期同期は未実装です。
- Firestore のユーザー検索はサインイン済みユーザーが公開プロフィールを検索できる前提です。

# commit規則
```git commit
<type>(scope): overview
```
| type     | 用途                     |
| -------- | ---------------------- |
| feat     | 新機能追加                  |
| fix      | バグ修正                   |
| docs     | ドキュメントのみ変更             |
| style    | フォーマット修正（コードの意味は変わらない） |
| refactor | リファクタリング               |
| perf     | 高速化・最適化                |
| test     | テスト追加・修正               |
| build    | ビルド設定変更                |
| ci       | GitHub ActionsなどCI変更   |
| chore    | その他雑務（ライブラリ更新など）       |
| revert   | コミット取り消し               |


# branch命名規則
```branch
<prefix>/<IssueNumber>-<overview>
```
| プレフィックス       | 用途                     | 例                           |
| ------------- | ---------------------- | --------------------------- |
| `feature/`    | 新機能追加                  | `feature/login`             |
| `bugfix/`     | 通常のバグ修正                | `bugfix/login-error`        |
| `fix/`        | バグ修正（GitHub Flowでよく使う） | `fix/header`                |
| `hotfix/`     | 本番環境の緊急修正              | `hotfix/security`           |
| `release/`    | リリース準備                 | `release/v1.2.0`            |
| `develop`     | 開発用メインブランチ             | `develop`                   |
| `main`        | 本番ブランチ                 | `main`                      |
| `test/`       | 動作確認                   | `test/new-ui`               |
| `experiment/` | 実験                     | `experiment/llm`            |
| `prototype/`  | 試作品                    | `prototype/gui`             |
| `docs/`       | ドキュメント修正               | `docs/readme`               |
| `refactor/`   | リファクタリング               | `refactor/audio-engine`     |
| `style/`      | コード整形・フォーマットのみ         | `style/clang-format`        |
| `perf/`       | 性能改善                   | `perf/render`               |
| `ci/`         | CI/CD設定変更              | `ci/github-actions`         |
| `build/`      | ビルド設定変更                | `build/cmake-update`        |
| `config/`     | 設定ファイル変更               | `config/firebase`           |
| `chore/`      | 雑多な保守作業                | `chore/update-dependencies` |
| `revert/`     | コミットの取り消し              | `revert/remove-cache`       |
| `spike/`      | 技術検証                   | `spike/flutter-web`         |
| `wip/`        | 作業途中（Work In Progress） | `wip/audio-filter`          |

# Microsoft 連携のビルド設定

Windows/macOS/Linux では Microsoft の device code flow を使います。TaskMan 用 Azure アプリ登録の Application (client) ID は既定値として埋め込み済みです。

埋め込み済み client ID:

```text
e89150a6-18fa-4ef0-9b1e-88aa85df3041
```

別の Azure アプリ登録を使う場合は、ビルド時に `MICROSOFT_CLIENT_ID` で上書きできます。

```powershell
flutter build windows --dart-define=MICROSOFT_CLIENT_ID=<Application client ID>
```

必要に応じてテナントも固定できます。既定値は `organizations` です。

```powershell
flutter build windows --dart-define=MICROSOFT_CLIENT_ID=<Application client ID> --dart-define=MICROSOFT_TENANT=organizations
```

Azure アプリ登録では公開クライアント フローを許可し、Microsoft Graph の `User.Read` と `Tasks.Read` を使えるようにしてください。
