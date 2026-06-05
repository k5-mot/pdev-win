# 🐳 Image Download & Merge Scripts

`scripts` 配下には、Docker/OCI registry から image を分割ダウンロードし、別環境で `podman load` できる tar に復元するための補助スクリプトを置きます。

## 🧰 Scripts

- `Download-Image.ps1`
  - Docker Registry HTTP API v2 を直接使って image を取得する。
  - Docker Desktop、WSL2、管理者権限、`regctl.exe`、`crane.exe` には依存しない。
  - 指定したサイズを上限として layer blob を分割保存する。
  - `state.json` と `download-manifest.json` で進捗と出力情報を管理する。
- `merge.sh`
  - 分割保存された blob を復元する。
  - `docker-dir` 形式の内容から `podman load -i` で読み込める tar を作成する。

## 🚚 Example

通常の container tool では、以下のような操作に相当します。

```bash
# 1. 通常の container tool で image を取得する場合の例。
docker pull docker.io/library/nginx:1.31.1

# 2. image を tar として保存する場合の例。
docker save -o docker_io_library_nginx_1_31_1.tar docker.io/library/nginx:1.31.1

# 3. tar を podman に読み込む場合の例。
podman load -i docker_io_library_nginx_1_31_1.tar
```

このリポジトリでは、まず PowerShell で image を分割ダウンロードします。

```powershell
# image を分割ダウンロードする。
.\scripts\Download-Image.ps1 `
  -imageName "docker.io/library/nginx:1.31.1" `
  -maxGB 5
```

出力ディレクトリを指定する場合:

```powershell
# 出力先を指定して image を分割ダウンロードする。
.\scripts\Download-Image.ps1 `
  -imageName "docker.io/library/nginx:1.31.1" `
  -maxGB 5 `
  -OutputRoot ".\out"
```

別環境へディレクトリごとコピーした後、`merge.sh` を実行します。

```bash
# ダウンロード済みディレクトリへ移動する。
cd docker_io_library_nginx_1_31_1

# 分割 blob を復元し、load 可能な tar を作成する。
../scripts/merge.sh

# 作成した tar を podman に読み込む。
podman load -i docker_io_library_nginx_1_31_1.tar
```

## ✅ Requirements

- Windows 11
- Windows PowerShell
- 管理者権限なし
- Docker Desktop なし
- WSL2 なし
- `regctl.exe` / `crane.exe` なし
- 復元先では `bash`、`tar`、必要に応じて `podman`

## 🗂️ Output Layout

`Download-Image.ps1` は docker-dir 形式に近い OCI layout を作成します。

```text
docker-dir/
  blobs/
    sha256/
      <blob>
      <blob>.part0001
      <blob>.part0002
  index.json
  manifest.json
  oci-layout
  state.json
download-manifest.json
```

`merge.sh` は `.partNNNN` ファイルを元の blob に戻し、`download-manifest.json` に記録された tar 名で archive を作成します。
