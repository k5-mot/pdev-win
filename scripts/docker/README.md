# 🐳 Docker Image Download Scripts

Docker/OCI registry から image を blob 単位で取得する PowerShell スクリプト群です。

Docker Desktop、WSL2、管理者権限、`regctl.exe`、`crane.exe` には依存しません。Docker Registry HTTP API v2 を直接使用します。

## 🧰 Scripts

- `Download-Image.ps1`
  - 推奨の統合版です。
  - `-OutputFormat Dir` で OCI layout ディレクトリを作成します。
  - `-OutputFormat Tar` で `docker load -i` / `podman load -i` 可能な tar archive を作成します。
- `Download-Image-Dir.ps1`
  - OCI layout の `docker-dir`、`state.json`、`merge.sh` を作成します。
  - `docker-dir` が `-MaxGB` の目安を超えそうな場合は、blob 退避を促して処理を終了します。
  - 再実行時は `state.json` を見て完了済み blob をスキップします。
- `Download-Image-Archive.ps1`
  - 一時的に OCI layout を作成し、image 名付き tar archive を直接作成します。
  - 作業ディレクトリは `OutputRoot/_work` です。
  - tar 作成後、`_work` は削除されます。

## 🚚 Examples

通常の container tool では、以下の操作に相当します。

```bash
# image を取得する。
docker pull docker.io/library/nginx:1.31.1

# image を tar として保存する。
docker save -o docker.io_library_nginx_1.31.1.tar docker.io/library/nginx:1.31.1

# tar を読み込む。
podman load -i docker.io_library_nginx_1.31.1.tar
```

### Tar Archive を直接作成する

```powershell
# image を取得し、out ディレクトリに tar archive を作成する。
.\scripts\docker\Download-Image.ps1 `
  -Image "docker.io/library/nginx:1.31.1" `
  -OutputFormat Tar `
  -OutputRoot ".\out"
```

作成した tar はそのまま読み込めます。

```bash
# 作成した archive を Docker に読み込む。
docker load -i docker.io_library_nginx_1.31.1.tar

# または Podman に読み込む。
podman load -i docker.io_library_nginx_1.31.1.tar
```

### OCI Layout ディレクトリを作成する

```powershell
# image を blob 単位で取得し、docker-dir と merge.sh を作成する。
.\scripts\docker\Download-Image.ps1 `
  -Image "docker.io/library/nginx:1.31.1" `
  -OutputFormat Dir `
  -OutputRoot ".\out"
```

`docker-dir` が指定サイズを超えそうな場合は、処理がいったん終了します。その場合は出力ディレクトリを別のファイルサーバなどへコピーし、ローカル側の `docker-dir/blobs/sha256` 配下の blob を削除してから同じコマンドを再実行します。

すべての blob を集めた環境で `merge.sh` を実行します。

```bash
# すべての blob を集めたディレクトリへ移動する。
cd docker.io_library_nginx_1.31.1

# load 可能な tar を作成する。
bash merge.sh

# 作成した tar を読み込む。
podman load -i docker.io_library_nginx_1.31.1.tar
```

## 🧾 Arguments

- `Image`
  - 取得する image 参照です。
  - 例: `docker.io/ollama/ollama:0.30.2`
- `OutputFormat`
  - `Download-Image.ps1` のみで指定します。
  - `Dir` または `Tar` を指定します。
- `MaxGB`
  - 一時作業ディレクトリまたは `docker-dir` のサイズ上限の目安です。
  - 既定値は `5` です。
  - 単一 blob または作業ディレクトリがこの値を超えそうな場合、処理を停止します。
- `OutputRoot`
  - 出力先ディレクトリです。
  - 未指定時はスクリプトの配置ディレクトリです。
- `Platform`
  - manifest list / image index から選ぶ platform です。
  - 既定値は `linux/amd64` です。
- `Force`
  - 既存の出力を上書きします。
- `KeepTemp`
  - `Download-Image-Dir.ps1` のみで指定できます。
  - 通常は削除される `_work` 配下の一時 json/blob を残します。

## 🗂️ Output

### Tar

`-OutputFormat Tar` または `Download-Image-Archive.ps1` は、`OutputRoot` に image 名付き tar archive を作成します。

```text
docker.io_library_nginx_1.31.1.tar
```

tar archive の中身は OCI layout 形式です。

```text
blobs/
  sha256/
    <blob>
index.json
oci-layout
```

### Dir

`-OutputFormat Dir` または `Download-Image-Dir.ps1` は、image 名付きディレクトリを作成します。

```text
docker.io_library_nginx_1.31.1/
  docker-dir/
    blobs/
      sha256/
        <blob>
    index.json
    oci-layout
  state.json
  merge.sh
```

`manifest.json` は `docker-dir` 直下には出力しません。OCI archive で必要な image manifest は `blobs/sha256/<digest>` として保存され、`index.json` から参照されます。

## ✅ Requirements

- Windows 11
- Windows PowerShell
- 管理者権限なし
- Docker Desktop なし
- WSL2 なし
- `regctl.exe` / `crane.exe` なし
- 復元先では必要に応じて `bash`、`tar`、`docker`、`podman`
