# 🐳 Image Download & Merge Scripts

`scripts` 配下には、Docker/OCI registry から image を blob 単位で取得し、別環境で `docker load` または `podman load` できる tar に変換するための補助スクリプトを置きます。

## 🧰 Scripts

- `Download-Image.ps1`
  - Docker Registry HTTP API v2 を直接使って image を取得する。
  - Docker Desktop、WSL2、管理者権限、`regctl.exe`、`crane.exe` には依存しない。
  - 指定したサイズを目安に、`docker-dir` が大きくなりすぎる前に blob 退避を促して処理を終了する。
  - `_work` 配下の一時 json/blob は `docker-dir` へ保存できた時点で削除する。
  - `state.json` で進捗と出力情報を管理する。
  - 再実行時は `state.json` を見て完了済み blob をスキップする。
  - 出力ディレクトリへ `merge.sh` を生成する。
- 生成される `merge.sh`
  - `docker-dir` 形式の内容を追加コピーなしで tar archive にまとめる。
  - `docker-dir` 形式の内容から `docker load -i` / `podman load -i` で読み込める tar を作成する。

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

このリポジトリでは、まず PowerShell で image を blob 単位で取得します。

```powershell
# image を blob 単位で取得する。
.\scripts\Download-Image.ps1 `
  -imageName "docker.io/library/nginx:1.31.1" `
  -maxGB 5
```

出力ディレクトリを指定する場合:

```powershell
# 出力先を指定して image を blob 単位で取得する。
.\scripts\Download-Image.ps1 `
  -imageName "docker.io/library/nginx:1.31.1" `
  -maxGB 5 `
  -OutputRoot ".\out"
```

`docker-dir` が指定サイズを超えそうな場合は、処理がいったん終了します。その場合は出力ディレクトリを別のファイルサーバなどへコピーし、ローカル側の `docker-dir/blobs/sha256` 配下の blob を削除してから同じコマンドを再実行します。すべての blob を集めた別環境で `merge.sh` を実行します。

`-Force` を付けなくても、出力ディレクトリに `state.json` がある場合は続きから再開します。ストレージに余裕がある場合や `-OutputRoot` にネットワークドライブを指定する場合は、退避せず同じディレクトリに取り続ける運用もできます。

```bash
# すべての blob を集めたディレクトリへ移動する。
cd docker_io_library_nginx_1_31_1

# load 可能な tar を作成する。
bash merge.sh

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
  index.json
  oci-layout
state.json
merge.sh
```

`manifest.json` は docker-dir 直下には出力しません。OCI archive で必要な image manifest は `blobs/sha256/<digest>` として保存され、`index.json` から参照されます。

`Download-Image.ps1` は blob 自体を分割しません。`docker-dir` が `-maxGB` の目安を超えそうな場合は、保存済み blob を別媒体へ退避するよう案内して終了します。単一 blob が `-maxGB` を超える場合も終了するため、その image では `-maxGB` を上げるか、十分な容量の出力先を指定してください。

`merge.sh` は `state.json` に記録された tar 名で archive を作成します。
