# Image Download & Merge Script

## Overview

```bash
# podman saveコマンド同等の処理をPowertShellで実行する.
docker pull docker.io/library/nginx:1.31.1
docker save -o docker_io_library_nginx_1_31_1.tar docker.io/library/nginx:1.31.1

# docker/podman loadができるtarファイルを生成する.
podman load -i docker_io_library_nginx_1_31_1.tar
```

## Requirements

- Windows 11
- WSL2無し
- Docker Desktop無し
- 管理者権限無し
- regctl.exe, crane.exe使用禁止
- 引数指定したサイズまでLayerを分割ダウンロードできる
  - ディレクトリごと別マシンにコピーしたのち、`merge.sh`スクリプトで`podman load -i docker_io_library_nginx_1_31_1.tar`で読み込めるtarファイルを生成する。
- どのLayerまでダウンロードしたかを`state.json`で管理する。
- アーカイブ形式は、docker-dir形式とする。
  - [イメージの保存および読み込み](https://docs.redhat.com/ja/documentation/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/proc_saving-and-loading-images_assembly_working-with-container-images)

```bash
docker-dir/
├── blobs           # blobs
│   └── sha256
│       ├── 0e760fdfbc48ba8041e7c6db999bb40bfca508b4be580ac75d32c4e29d202ce1
│       ├── 4cc5f49f1578d3d9c4b5f32f6ef7a37d7fadccd4a20f3e29e3bb0ee6cd159f52
│       ├── 4f55086f7dd096d48b0e49be066971a8ed996521c2e190aa21b2435a847198b4
│       ├── 8e752a1cddeafc02597e756f4a0ec96e29f63ac4bc4af87682daf3f1de843bb7
│       ├── d1a8d0a4eeb63aff09f5f34d4d80505e0ba81905f36158cc3970d8e07179e59e
│       ├── d5e71e642bf52fab99f7dc2746472b824e89b393f60846d6594e7e71aa11c006
│       └── e2ac70e7319a02c5a477f5825259bd118b94e8b02c279c67afa63adab6d8685b
├── index.json      # index
├── manifest.json   # manifest
├── oci-layout      # OCI layout
└── state.json      # download state
```

## Usage

```powershell
#
.\scripts\Download-Podman-Image.ps1 -imageName "docker.io/library/nginx:1.31.1" -maxGB 5
```

## Coding Rules

### Comments

- 関数には日本語の comment-based help を付ける。
- 関数コメントは PowerShell の [about_Comment_Based_Help](https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_comment_based_help?view=powershell-7.6#syntax-for-comment-based-help-in-functions) に準拠する。
- 関数コメントでは `<# ... #>` ブロック内に `.SYNOPSIS`、必要に応じて `.PARAMETER`、`.OUTPUTS` などを記述する。
- 複雑な処理には適宜日本語コメントを入れる。
