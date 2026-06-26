# taskman

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
