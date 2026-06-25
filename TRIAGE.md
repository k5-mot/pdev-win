# TRIAGE

このリポジトリの改善候補を、現時点の影響度順に並べる。

## P0

### launcher に固定APIキー風の値が入っている

- 対象: `setup.ps1`
- 内容: `VSCode.cmd` と `PowerShell.cmd` に `LITELLM_API_KEY=sk-litellm-master-key` を固定で書き込んでいる。
- 影響: ダミー値でも秘密情報に見え、利用者が本物のキーを同じ場所へ書く運用を誘発しやすい。
- 推奨: launcher からは削除し、必要なら `.env.sample` や明示的な設定手順へ移す。
- 方式案:
  - 環境変数を既に持っている場合だけ継承する。launcher では `if defined LITELLM_API_KEY (...)` のような判定だけ行い、値は書かない。
  - `$Root\.config\pdev\env.cmd` のような gitignore 済みローカル設定ファイルを任意で読み込む。サンプルは `env.cmd.sample` として置く。
  - `.env` を使うツールだけが `.env` を読む。launcher は `CODEX_HOME` など非秘密の portable path だけ設定する。
  - 初回セットアップ時に `-LiteLLMApiKey` のような明示引数で受け取る。ただしコマンド履歴に残りやすいため、優先度は低い。

## P1

### 古い `setup_v*.ps1` が追跡されている

- 対象: `setup_v1.ps1` から `setup_v6.ps1`
- 内容: 現行の `setup.ps1` と同じ階層に過去版が残っている。
- 影響: 入口が分かりにくく、古い仕様を誤って実行する可能性がある。
- 推奨: 必要なら `docs/history/` へ移動し、不要なら削除する。履歴はGitに任せる。

## P2

### setup系スクリプトで共通関数が重複している

- 対象: `setup.ps1`, `setup_cygwin.ps1`
- 内容: logging、Root検証、download、外部コマンド実行などの関数が重複している。
- 影響: 今後の修正漏れが起きやすい。
- 推奨: `scripts/lib/PortableDev.ps1` のような共通モジュールへ切り出す。

### `translate-ja` と `translate-jaja` のスクリプトが重複している

- 対象: `.agents/skills/translate-ja`, `.agents/skills/translate-jaja`
- 内容: 日本語版skillを独立メンテナンスしやすくした一方で、実行スクリプトが複製になっている。
- 影響: bug fixを片方にだけ入れる事故が起きやすい。
- 推奨: 共通スクリプトを1か所へ寄せ、各skillから参照する構成を検討する。

### workflowの検証が重い

- 対象: `.github/workflows/validate-portable-dev.yml`
- 内容: push/pull_requestでPython、Node.js、VS Code、Cygwinまで実インストールする。
- 影響: CI時間が長く、外部ミラー障害の影響を受けやすい。
- 推奨: parse/static check と smoke install を分け、full bootstrap は `workflow_dispatch` または定期実行へ寄せる。
