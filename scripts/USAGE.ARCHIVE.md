# 🐳 Download-Image-Archive.ps1

`Download-Image-Archive.ps1` は Docker/OCI registry から image を blob 単位で取得し、`docker load -i` または `podman load -i` で読み込める OCI archive tar を作成します。

Docker Desktop、WSL2、管理者権限、`regctl.exe`、`crane.exe` には依存しません。

## 🚚 Example

通常の container tool では、以下のような操作に相当します。

```bash
# 1. 通常の container tool で image を取得する。
docker pull docker.io/library/nginx:1.31.1

# 2. image を tar として保存する。
docker save -o docker.io_library_nginx_1.31.1.tar docker.io/library/nginx:1.31.1

# 3. tar を podman に読み込む。
podman load -i docker.io_library_nginx_1.31.1.tar
```

このスクリプトでは、PowerShell だけで archive を作成します。

```powershell
# image を取得し、既定の出力先に image 名付き tar を作成する。
.\scripts\Download-Image-Archive.ps1 `
  -imageName "docker.io/library/nginx:1.31.1" `
  -maxGB 5
```

出力ディレクトリを指定する場合:

```powershell
# out ディレクトリに image 名付き tar を作成する。
.\scripts\Download-Image-Archive.ps1 `
  -imageName "docker.io/library/nginx:1.31.1" `
  -maxGB 5 `
  -OutputRoot ".\out"
```

作成した archive は、そのまま読み込めます。

```bash
# 作成した archive を Docker に読み込む。
docker load -i docker.io_library_nginx_1.31.1.tar

# または Podman に読み込む。
podman load -i docker.io_library_nginx_1.31.1.tar
```

## 🧾 Arguments

- `imageName`
  - 取得する image 参照です。
  - `ImageRef` alias も利用できます。
- `maxGB`
  - 一時作業ディレクトリのサイズ上限の目安です。
  - 単一 blob または作業ディレクトリがこの値を超えそうな場合、処理を停止します。
- `OutputRoot`
  - image 名付き tar archive を作成するディレクトリです。
  - 未指定時はスクリプトの配置ディレクトリです。
- `Platform`
  - manifest list / image index から選ぶ platform です。
  - 既定値は `linux/amd64` です。
- `Force`
  - 既存の image 名付き tar archive を上書きします。

## 🗂️ Output

成功後、`$OutputRoot` には次のファイルだけが作成されます。

```text
docker.io_library_nginx_1.31.1.tar
```

処理中は `$OutputRoot` と同階層に `.download-image-archive-work` という隠し作業フォルダを作成し、その配下の実行ごとの一時ディレクトリで作業します。成功時は実行ごとの一時ディレクトリを削除します。

tar archive の中身は OCI layout 形式です。

```text
blobs/
  sha256/
    <blob>
index.json
oci-layout
```

## ✅ Requirements

- Windows 11
- Windows PowerShell
- 管理者権限なし
- Docker Desktop なし
- WSL2 なし
- `regctl.exe` / `crane.exe` なし
- 復元先では必要に応じて `docker` または `podman`
