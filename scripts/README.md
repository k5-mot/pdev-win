# 🧰 Scripts

`scripts` 配下のスクリプト一覧です。各スクリプトの詳しい使い方は用途別の `USAGE.*.md` を参照してください。

## 🐳 Image Download

- `Download-Image-Dir.ps1`
  - Docker/OCI registry から image を取得し、OCI layout の `docker-dir` と `merge.sh` を作成します。
  - 詳細: [`USAGE.DIR.md`](USAGE.DIR.md)
- `Download-Image-Archive.ps1`
  - Docker/OCI registry から image を取得し、`docker load -i` / `podman load -i` で読み込める image 名付き tar archive を直接作成します。
  - 詳細: [`USAGE.ARCHIVE.md`](USAGE.ARCHIVE.md)

## 🌲 Utility

- `Tree.ps1`
  - ディレクトリツリーを表示する補助スクリプトです。
