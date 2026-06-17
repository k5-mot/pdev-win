# 🧰 Scripts

`scripts` 配下のスクリプト一覧です。

## 🐳 Docker Image Download

Docker/OCI registry から image を取得するスクリプトは `docker` ディレクトリに集約しています。

- [`docker/Download-Image.ps1`](docker/Download-Image.ps1)
  - 推奨の統合版です。
  - `-OutputFormat Dir` で OCI layout ディレクトリを作成します。
  - `-OutputFormat Tar` で `docker load -i` / `podman load -i` 可能な tar archive を作成します。
- [`docker/Download-Image-Dir.ps1`](docker/Download-Image-Dir.ps1)
  - OCI layout の `docker-dir` と `merge.sh` を作成します。
- [`docker/Download-Image-Archive.ps1`](docker/Download-Image-Archive.ps1)
  - image 名付き tar archive を直接作成します。

詳しい使い方は [`docker/README.md`](docker/README.md) を参照してください。

## 🌲 Utility

- [`CheckDisk.ps1`](CheckDisk.ps1)
  - 指定したディレクトリ直下でサイズが大きいファイルまたはフォルダを Top 10 形式で特定します。
- [`Tree.ps1`](Tree.ps1)
  - ディレクトリツリーを表示する補助スクリプトです。
