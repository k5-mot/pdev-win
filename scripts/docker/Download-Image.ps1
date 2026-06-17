<#
.SYNOPSIS
Docker/OCI registry から image を取得し、OCI layout ディレクトリまたは OCI archive tar として保存します。

.DESCRIPTION
Docker Desktop、WSL2、管理者権限、regctl.exe、crane.exe に依存せず、Docker Registry HTTP API v2 を直接使用します。
-OutputFormat Dir では OCI layout ディレクトリを保存し、merge.sh を生成します。
-OutputFormat Tar では一時的に作成した OCI layout を、docker/podman load -i で読み込める tar にまとめます。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Image,

    [ValidateScript({ $_ -gt 0 })]
    [double]$maxGB = 5,

    [string]$OutputRoot,

    [ValidateSet("Dir", "Tar")]
    [string]$OutputFormat = "Tar",

    [string]$Platform = "linux/amd64",

    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch {
    Write-Warning "Could not force TLS 1.2. Continuing with the current defaults."
}

$ScriptDirectory = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = $ScriptDirectory
}

<#
.SYNOPSIS
ログメッセージをレベル別の色付きでコンソールに出力します。
.PARAMETER Message
出力するメッセージです。
.PARAMETER Level
ログレベルです。
#>
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "OK", "WARN", "ERROR", "STEP")]
        [string]$Level = "INFO"
    )

    $color = switch ($Level) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "STEP" { "Cyan" }
        default { "Gray" }
    }

    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $color
}

<#
.SYNOPSIS
イメージ参照から Windows で扱いやすい安全なファイル名を生成します。
.PARAMETER Value
変換対象の文字列です。
.OUTPUTS
安全なファイル名文字列を返します。
#>
function ConvertTo-SafeName {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = $Value -replace "^https?://", ""
    $safe = $safe -replace "@sha256:", "_sha256_"
    $safe = $safe -replace "[\\/:\*\?`"<>|]+", "_"
    $safe = $safe.Trim(" ", ".")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw "Could not create a safe file name from: $Value"
    }

    return $safe
}

<#
.SYNOPSIS
Docker/OCI イメージ参照を registry、repository、tag/digest に分解します。
.PARAMETER Reference
解析するイメージ参照です。
.OUTPUTS
registry 接続情報と出力ファイル名ベースを含むオブジェクトを返します。
#>
function Split-ImageReference {
    param([Parameter(Mandatory = $true)][string]$Reference)

    $digest = $null
    $nameAndTag = $Reference
    if ($Reference.Contains("@")) {
        $pair = $Reference.Split("@", 2)
        $nameAndTag = $pair[0]
        $digest = $pair[1]
    }

    $tag = "latest"
    $lastSlash = $nameAndTag.LastIndexOf("/")
    $lastColon = $nameAndTag.LastIndexOf(":")
    if ($lastColon -gt $lastSlash) {
        $tag = $nameAndTag.Substring($lastColon + 1)
        $nameAndTag = $nameAndTag.Substring(0, $lastColon)
    }

    $parts = $nameAndTag.Split("/")
    $registryDisplay = "docker.io"
    $repositoryParts = @()
    if ($parts.Count -gt 1 -and ($parts[0].Contains(".") -or $parts[0].Contains(":") -or $parts[0] -eq "localhost")) {
        $registryDisplay = $parts[0]
        $repositoryParts = $parts[1..($parts.Count - 1)]
    }
    else {
        $repositoryParts = $parts
    }

    if ($registryDisplay -eq "docker.io" -and $repositoryParts.Count -eq 1) {
        $repositoryParts = @("library", $repositoryParts[0])
    }

    $registryHost = if ($registryDisplay -eq "docker.io") { "registry-1.docker.io" } else { $registryDisplay }
    $repository = $repositoryParts -join "/"
    $referenceForManifest = if ([string]::IsNullOrWhiteSpace($digest)) { $tag } else { $digest }
    $repoTag = if ([string]::IsNullOrWhiteSpace($digest)) {
        "{0}/{1}:{2}" -f $registryDisplay, $repository, $tag
    }
    else {
        ('{0}/{1}@{2}' -f $registryDisplay, $repository, $digest)
    }

    return [pscustomobject]@{
        RegistryDisplay = $registryDisplay
        RegistryHost = $registryHost
        Repository = $repository
        Tag = $tag
        Digest = $digest
        ManifestReference = $referenceForManifest
        RepoTag = $repoTag
        FileBase = ConvertTo-SafeName -Value $repoTag
    }
}

<#
.SYNOPSIS
Registry の WWW-Authenticate Bearer challenge を解析します。
.PARAMETER Header
WWW-Authenticate ヘッダー値です。
.OUTPUTS
realm、service、scope などを含む hashtable を返します。
#>
function ConvertFrom-WwwAuthenticate {
    param([Parameter(Mandatory = $true)][string]$Header)

    if ($Header -notmatch "^Bearer\s+(.+)$") {
        throw "Unsupported registry challenge. Bearer authentication was expected: $Header"
    }

    $result = @{}
    foreach ($match in [regex]::Matches($Matches[1], '(\w+)="([^"]*)"')) {
        $result[$match.Groups[1].Value] = $match.Groups[2].Value
    }

    return $result
}

<#
.SYNOPSIS
Registry pull 用の Bearer token を取得します。
.PARAMETER RegistryHost
Registry のホスト名です。
.PARAMETER Repository
取得対象の repository 名です。
.OUTPUTS
認証不要なら null、必要なら token 文字列を返します。
#>
function Get-RegistryToken {
    param(
        [Parameter(Mandatory = $true)][string]$RegistryHost,
        [Parameter(Mandatory = $true)][string]$Repository
    )

    $pingUri = "https://$RegistryHost/v2/$Repository/manifests/latest"
    try {
        Invoke-WebRequest -Uri $pingUri -Method Head -UseBasicParsing -ErrorAction Stop | Out-Null
        return $null
    }
    catch {
        $response = $_.Exception.Response
        if ($null -eq $response -or [int]$response.StatusCode -ne 401) {
            throw
        }

        $challengeHeader = Get-HeaderValue -Response $response -Name "WWW-Authenticate"

        $challenge = ConvertFrom-WwwAuthenticate -Header $challengeHeader
        $realm = $challenge["realm"]
        $service = $challenge["service"]
        $scope = if ($challenge.ContainsKey("scope")) { $challenge["scope"] } else { "repository:$Repository:pull" }
        $tokenUri = "{0}?service={1}&scope={2}" -f $realm, [uri]::EscapeDataString($service), [uri]::EscapeDataString($scope)
        $tokenResponse = Invoke-RestMethod -Uri $tokenUri -UseBasicParsing
        if ($null -ne $tokenResponse.token) {
            return [string]$tokenResponse.token
        }
        if ($null -ne $tokenResponse.access_token) {
            return [string]$tokenResponse.access_token
        }

        throw "Could not get a registry token."
    }
}

<#
.SYNOPSIS
Registry API 呼び出し用の HTTP ヘッダーを作成します。
.PARAMETER Token
Bearer token です。
.PARAMETER Accept
Accept ヘッダー値です。
.OUTPUTS
Invoke-WebRequest に渡す hashtable を返します。
#>
function New-RegistryHeaders {
    param(
        [AllowNull()][string]$Token,
        [AllowNull()][string]$Accept
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }
    if (-not [string]::IsNullOrWhiteSpace($Accept)) {
        $headers["Accept"] = $Accept
    }

    return $headers
}

<#
.SYNOPSIS
Registry API へ HTTP リクエストを送信します。
.PARAMETER Uri
アクセス先 URI です。
.PARAMETER Token
Bearer token です。
.PARAMETER Accept
Accept ヘッダー値です。
.PARAMETER OutFile
指定時はレスポンス本文をファイルに保存します。
#>
function Invoke-RegistryWebRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Token,
        [AllowNull()][string]$Accept,
        [AllowNull()][string]$OutFile
    )

    $headers = New-RegistryHeaders -Token $Token -Accept $Accept
    if ([string]::IsNullOrWhiteSpace($OutFile)) {
        return Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing
    }

    return Invoke-WebRequest -Uri $Uri -Headers $headers -OutFile $OutFile -UseBasicParsing
}

<#
.SYNOPSIS
Invoke-WebRequest のレスポンスからヘッダー値を 1 つ取り出します。
.PARAMETER Response
Invoke-WebRequest のレスポンスです。
.PARAMETER Name
取得するヘッダー名です。
.OUTPUTS
ヘッダー値の文字列を返します。
#>
function Get-HeaderValue {
    param(
        [Parameter(Mandatory = $true)]$Response,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $headers = $Response.Headers
    $value = $null

    if ($headers -is [System.Collections.IDictionary]) {
        $value = $headers[$Name]
    }
    elseif ($headers -is [System.Collections.Specialized.NameValueCollection]) {
        $value = $headers[$Name]
    }
    elseif ($null -ne $headers) {
        try {
            $value = $headers[$Name]
        }
        catch {
            foreach ($header in $headers) {
                if ($null -ne $header.PSObject.Properties['Key'] -and [string]$header.Key -eq $Name) {
                    $value = $header.Value
                    break
                }
            }
        }
    }

    if ($null -eq $value) {
        return $null
    }

    if ($value -is [array]) {
        return [string]$value[0]
    }
    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
        foreach ($item in $value) {
            return [string]$item
        }
    }
    return [string]$value
}

<#
.SYNOPSIS
JSON オブジェクトから存在確認付きでプロパティ値を取得します。
.PARAMETER Object
対象オブジェクトです。
.PARAMETER Name
取得するプロパティ名です。
.OUTPUTS
存在する場合は値、存在しない場合は null を返します。
#>
function Get-JsonProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = @($Object.PSObject.Properties.Match($Name))
    if ($property.Count -eq 0) {
        return $null
    }

    return $property[0].Value
}

<#
.SYNOPSIS
Registry から image manifest または manifest list を取得します。
.PARAMETER Image
Split-ImageReference が返したイメージ情報です。
.PARAMETER Token
Bearer token です。
.PARAMETER Reference
tag または digest です。
.OUTPUTS
manifest JSON、digest、media type を含むオブジェクトを返します。
#>
function Get-RegistryManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Image,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$Reference
    )

    $accept = @(
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json"
    ) -join ", "
    $uri = "https://$($Image.RegistryHost)/v2/$($Image.Repository)/manifests/$Reference"
    $response = Invoke-RegistryWebRequest -Uri $uri -Token $Token -Accept $accept -OutFile $null
    $content = if ($response.Content -is [byte[]]) {
        [System.Text.Encoding]::UTF8.GetString($response.Content)
    }
    else {
        [string]$response.Content
    }
    $json = $content | ConvertFrom-Json

    return [pscustomobject]@{
        Json = $json
        Content = $content
        Digest = Get-HeaderValue -Response $response -Name "Docker-Content-Digest"
        MediaType = Get-HeaderValue -Response $response -Name "Content-Type"
    }
}

<#
.SYNOPSIS
manifest list から指定 platform の image manifest を選択します。
.PARAMETER Image
イメージ情報です。
.PARAMETER Token
Bearer token です。
.PARAMETER ManifestResult
取得済み manifest 情報です。
.PARAMETER Platform
os/architecture[/variant] 形式の platform 指定です。
.OUTPUTS
単一 image manifest の取得結果を返します。
#>
function Resolve-PlatformManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Image,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][object]$ManifestResult,
        [Parameter(Mandatory = $true)][string]$Platform
    )

    $jsonMediaType = Get-JsonProperty -Object $ManifestResult.Json -Name "mediaType"
    $mediaType = if ($null -ne $jsonMediaType) { [string]$jsonMediaType } else { [string]$ManifestResult.MediaType }
    if ($mediaType -notmatch "manifest\.list|image\.index" -or $null -eq (Get-JsonProperty -Object $ManifestResult.Json -Name "manifests")) {
        return $ManifestResult
    }

    $platformParts = $Platform.Split("/")
    if ($platformParts.Count -lt 2) {
        throw "-Platform must use os/architecture format: $Platform"
    }

    $os = $platformParts[0]
    $arch = $platformParts[1]
    $variant = if ($platformParts.Count -ge 3) { $platformParts[2] } else { $null }
    $matches = @($ManifestResult.Json.manifests | Where-Object {
        $_.platform.os -eq $os -and $_.platform.architecture -eq $arch -and
        ([string]::IsNullOrWhiteSpace($variant) -or $_.platform.variant -eq $variant)
    })

    if ($matches.Count -eq 0) {
        throw "Could not find a manifest for platform: $Platform"
    }

    Write-Log ("Platform manifest: {0}" -f $matches[0].digest) "OK"
    return Get-RegistryManifest -Image $Image -Token $Token -Reference ([string]$matches[0].digest)
}

<#
.SYNOPSIS
ファイルの SHA256 digest を小文字 hex で計算します。
.PARAMETER Path
対象ファイルパスです。
.OUTPUTS
SHA256 の hex 文字列を返します。
#>
function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

<#
.SYNOPSIS
入力ストリームから出力ストリームへ内容をコピーします。
.PARAMETER InputStream
読み込み元ストリームです。
.PARAMETER OutputStream
書き込み先ストリームです。
#>
function Copy-Stream {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$InputStream,
        [Parameter(Mandatory = $true)][System.IO.Stream]$OutputStream
    )

    $buffer = New-Object byte[] 1048576
    while ($true) {
        $read = $InputStream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) {
            break
        }
        $OutputStream.Write($buffer, 0, $read)
    }
}

<#
.SYNOPSIS
Registry から取得した layer blob を未圧縮 tar に展開します。
.PARAMETER BlobPath
取得済み layer blob のパスです。
.PARAMETER OutputPath
未圧縮 tar の出力先です。
.PARAMETER MediaType
layer の media type です。
#>
function Expand-LayerBlob {
    param(
        [Parameter(Mandatory = $true)][string]$BlobPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [AllowNull()][string]$MediaType
    )

    $input = [System.IO.File]::OpenRead($BlobPath)
    $output = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        if ($MediaType -match "zstd") {
            throw "zstd-compressed layers are not supported: $MediaType"
        }

        if ($MediaType -match "gzip" -or $BlobPath.EndsWith(".gz", [System.StringComparison]::OrdinalIgnoreCase)) {
            $gzip = New-Object System.IO.Compression.GzipStream($input, [System.IO.Compression.CompressionMode]::Decompress)
            try {
                Copy-Stream -InputStream $gzip -OutputStream $output
            }
            finally {
                $gzip.Dispose()
            }
        }
        else {
            Copy-Stream -InputStream $input -OutputStream $output
        }
    }
    finally {
        $output.Dispose()
        $input.Dispose()
    }
}

<#
.SYNOPSIS
文字列を ASCII byte 配列に変換します。
.PARAMETER Value
変換する文字列です。
.OUTPUTS
ASCII byte 配列を返します。
#>
function ConvertTo-AsciiBytes {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ,([System.Text.Encoding]::ASCII.GetBytes($Value))
}

<#
.SYNOPSIS
tar ヘッダーの固定長文字列フィールドへ値を書き込みます。
.PARAMETER Header
512 byte の tar ヘッダーです。
.PARAMETER Offset
書き込み開始位置です。
.PARAMETER Length
フィールド長です。
.PARAMETER Value
書き込む文字列です。
#>
function Write-TarStringField {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Header,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Length,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $bytes = ConvertTo-AsciiBytes -Value $Value
    if ($bytes.Length -gt $Length) {
        throw "tar header field is too long: $Value"
    }
    [Array]::Copy($bytes, 0, $Header, $Offset, $bytes.Length)
}

<#
.SYNOPSIS
tar ヘッダーの octal 数値フィールドへ値を書き込みます。
.PARAMETER Header
512 byte の tar ヘッダーです。
.PARAMETER Offset
書き込み開始位置です。
.PARAMETER Length
フィールド長です。
.PARAMETER Value
書き込む数値です。
#>
function Write-TarOctalField {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Header,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Length,
        [Parameter(Mandatory = $true)][Int64]$Value
    )

    $text = [Convert]::ToString($Value, 8)
    if ($text.Length -gt ($Length - 1)) {
        throw "tar octal field is too long: $Value"
    }

    $field = $text.PadLeft($Length - 1, "0") + [char]0
    Write-TarStringField -Header $Header -Offset $Offset -Length $Length -Value $field
}

<#
.SYNOPSIS
tar ヘッダーの size フィールドへ値を書き込みます。
.PARAMETER Header
512 byte の tar ヘッダーです。
.PARAMETER Size
エントリサイズです。
#>
function Write-TarSizeField {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Header,
        [Parameter(Mandatory = $true)][Int64]$Size
    )

    if ($Size -lt [Convert]::ToInt64("77777777777", 8)) {
        Write-TarOctalField -Header $Header -Offset 124 -Length 12 -Value $Size
        return
    }

    $value = $Size
    for ($i = 135; $i -ge 124; $i--) {
        $Header[$i] = [byte]($value -band 0xFF)
        $value = [Math]::Floor($value / 256)
    }
    $Header[124] = $Header[124] -bor 0x80
}

<#
.SYNOPSIS
Docker archive 用 tar エントリのヘッダーを作成します。
.PARAMETER Name
tar 内のパスです。
.PARAMETER Size
エントリサイズです。
.PARAMETER TypeFlag
tar typeflag です。
.OUTPUTS
512 byte の tar ヘッダーを返します。
#>
function New-TarHeader {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][Int64]$Size,
        [string]$TypeFlag = "0"
    )

    $header = New-Object byte[] 512
    $path = $Name.Replace("\", "/").TrimStart("/")
    if ($path.Length -gt 100) {
        $split = $path.LastIndexOf("/")
        if ($split -le 0) {
            throw "tar path is too long: $Name"
        }
        $prefix = $path.Substring(0, $split)
        $leaf = $path.Substring($split + 1)
        Write-TarStringField -Header $header -Offset 0 -Length 100 -Value $leaf
        Write-TarStringField -Header $header -Offset 345 -Length 155 -Value $prefix
    }
    else {
        Write-TarStringField -Header $header -Offset 0 -Length 100 -Value $path
    }

    Write-TarOctalField -Header $header -Offset 100 -Length 8 -Value 420
    Write-TarOctalField -Header $header -Offset 108 -Length 8 -Value 0
    Write-TarOctalField -Header $header -Offset 116 -Length 8 -Value 0
    Write-TarSizeField -Header $header -Size $Size
    Write-TarOctalField -Header $header -Offset 136 -Length 12 -Value ([int][double]::Parse((Get-Date -UFormat %s)))
    for ($i = 148; $i -lt 156; $i++) {
        $header[$i] = 32
    }
    Write-TarStringField -Header $header -Offset 156 -Length 1 -Value $TypeFlag
    Write-TarStringField -Header $header -Offset 257 -Length 6 -Value "ustar"
    Write-TarStringField -Header $header -Offset 263 -Length 2 -Value "00"

    [Int64]$checksum = 0
    foreach ($byte in $header) {
        $checksum += $byte
    }
    $checksumText = ([Convert]::ToString($checksum, 8)).PadLeft(6, "0") + [char]0 + " "
    Write-TarStringField -Header $header -Offset 148 -Length 8 -Value $checksumText

    return ,$header
}

$script:MaxWorkDirBytes = [Int64][Math]::Ceiling($maxGB * 1GB)
$script:MaxDockerDirBytes = [Int64][Math]::Ceiling($maxGB * 1GB)
$script:TarFileBase = $null
$script:OutputDir = $null

<#
.SYNOPSIS
UTF-8 no BOM でテキストファイルを書き込みます。
.PARAMETER Path
出力先ファイルパスです。
.PARAMETER Text
書き込むテキストです。
#>
function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

<#
.SYNOPSIS
不要になった _work 配下の一時ファイルを削除します。
.PARAMETER Path
削除対象ファイルです。
#>
function Remove-WorkFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
merge.sh のテキストを返します。
#>
function New-MergeScriptContent {
    return @'
#!/usr/bin/env bash
set -euo pipefail

state_file="state.json"
legacy_manifest_file="download-manifest.json"
docker_dir="docker-dir"

color_ok=$'\033[32m'
color_warn=$'\033[33m'
color_error=$'\033[31m'
color_step=$'\033[36m'
color_reset=$'\033[0m'

log() {
  local level="$1"
  local message="$2"
  local color="$color_reset"
  case "$level" in
    OK) color="$color_ok" ;;
    WARN) color="$color_warn" ;;
    ERROR) color="$color_error" ;;
    STEP) color="$color_step" ;;
  esac
  printf '%s[%s]%s %s\n' "$color" "$level" "$color_reset" "$message"
}

json_value() {
  local file="$1"
  local key="$2"
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1
}

if [[ -f "$state_file" ]]; then
  file_base="$(json_value "$state_file" "FileBase")"
  output_tar="$(json_value "$state_file" "OutputTar")"
  parsed_docker_dir="$(json_value "$state_file" "DockerDir")"
  if [[ -n "$parsed_docker_dir" ]]; then
    docker_dir="$parsed_docker_dir"
  fi
elif [[ -f "$legacy_manifest_file" ]]; then
  file_base="$(json_value "$legacy_manifest_file" "FileBase")"
  output_tar="$(json_value "$legacy_manifest_file" "OutputTar")"
  parsed_docker_dir="$(json_value "$legacy_manifest_file" "DockerDir")"
  if [[ -n "$parsed_docker_dir" ]]; then
    docker_dir="$parsed_docker_dir"
  fi
else
  if [[ ! -d "$docker_dir" ]]; then
    log ERROR "state.json or docker-dir was not found."
    exit 1
  fi
  file_base="$(basename "$PWD")"
  output_tar="${file_base}.tar"
fi

if [[ -z "${file_base:-}" || -z "${output_tar:-}" ]]; then
  log ERROR "Could not determine output tar name."
  exit 1
fi

if [[ -e "$output_tar" ]]; then
  log ERROR "Output already exists: $output_tar"
  exit 1
fi

if [[ ! -d "$docker_dir" ]]; then
  log ERROR "docker-dir was not found: $docker_dir"
  exit 1
fi

blobs_dir="${docker_dir}/blobs/sha256"
if [[ ! -d "$blobs_dir" ]]; then
  log ERROR "OCI blobs directory was not found: $blobs_dir"
  exit 1
fi

index_file="${docker_dir}/index.json"
if [[ ! -f "${docker_dir}/oci-layout" || ! -f "$index_file" ]]; then
  log ERROR "OCI layout files are missing in: $docker_dir"
  exit 1
fi

log STEP "Creating OCI archive directly from: $docker_dir"
(
  cd "$docker_dir"
  tar -cf "../$output_tar" oci-layout index.json blobs
)

if [[ ! -f "$output_tar" ]]; then
  log ERROR "Failed to create output tar: $output_tar"
  exit 1
fi

if command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
  log OK "docker/podman command was found."
else
  log WARN "docker/podman was not found in PATH; load was not tested."
fi

log OK "Created: $output_tar"
log OK "Load with: docker load -i $output_tar"
'@
}

<#
.SYNOPSIS
出力先の image 名付き作業ルートを作成します。
.PARAMETER OutputRootPath
tar archive を作成する出力先ディレクトリです。
.PARAMETER FileBase
作業ルート名に含める安全な image 名です。
.OUTPUTS
作成した作業ルートの絶対パスを返します。
#>
function New-ArchiveWorkRoot {
    param(
        [Parameter(Mandatory = $true)][string]$OutputRootPath,
        [Parameter(Mandatory = $true)][string]$FileBase
    )

    $workRoot = Join-Path -Path $OutputRootPath -ChildPath ("_work_{0}" -f $FileBase)
    $created = New-Item -ItemType Directory -Path $workRoot -Force

    return $created.FullName
}

<#
.SYNOPSIS
tar エントリの 512 byte 境界まで padding を書き込みます。
.PARAMETER OutputStream
書き込み先の tar ストリームです。
.PARAMETER Size
padding 計算に使うエントリサイズです。
#>
function Write-TarPadding {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$OutputStream,
        [Parameter(Mandatory = $true)][Int64]$Size
    )

    $paddingSize = (512 - ($Size % 512)) % 512
    if ($paddingSize -gt 0) {
        $padding = New-Object byte[] $paddingSize
        $OutputStream.Write($padding, 0, $padding.Length)
    }
}

<#
.SYNOPSIS
tar archive にディレクトリエントリを追加します。
.PARAMETER OutputStream
書き込み先の tar ストリームです。
.PARAMETER ArchivePath
tar 内のディレクトリパスです。
#>
function Add-TarDirectoryEntry {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$OutputStream,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    $path = $ArchivePath.Replace("\", "/").TrimEnd("/") + "/"
    $header = New-TarHeader -Name $path -Size 0 -TypeFlag "5"
    $OutputStream.Write($header, 0, $header.Length)
}

<#
.SYNOPSIS
tar archive にファイルエントリを追加します。
.PARAMETER OutputStream
書き込み先の tar ストリームです。
.PARAMETER SourcePath
追加する実ファイルのパスです。
.PARAMETER ArchivePath
tar 内のファイルパスです。
#>
function Add-TarFileEntry {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$OutputStream,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    $file = Get-Item -LiteralPath $SourcePath
    $header = New-TarHeader -Name $ArchivePath -Size ([Int64]$file.Length)
    $OutputStream.Write($header, 0, $header.Length)

    $input = [System.IO.File]::OpenRead($file.FullName)
    try {
        Copy-Stream -InputStream $input -OutputStream $OutputStream
    }
    finally {
        $input.Dispose()
    }

    Write-TarPadding -OutputStream $OutputStream -Size ([Int64]$file.Length)
}

<#
.SYNOPSIS
tar archive の終端ブロックを書き込みます。
.PARAMETER OutputStream
書き込み先の tar ストリームです。
#>
function Complete-TarArchive {
    param([Parameter(Mandatory = $true)][System.IO.Stream]$OutputStream)

    $endBlocks = New-Object byte[] 1024
    $OutputStream.Write($endBlocks, 0, $endBlocks.Length)
}

<#
.SYNOPSIS
OCI layout ディレクトリから docker/podman load 可能な tar archive を作成します。
.PARAMETER DockerDir
oci-layout、index.json、blobs を含む OCI layout ディレクトリです。
.PARAMETER OutputTar
作成する tar archive のパスです。
#>
function New-OciArchiveTar {
    param(
        [Parameter(Mandatory = $true)][string]$DockerDir,
        [Parameter(Mandatory = $true)][string]$OutputTar
    )

    $ociLayoutPath = Join-Path -Path $DockerDir -ChildPath "oci-layout"
    $indexPath = Join-Path -Path $DockerDir -ChildPath "index.json"
    $blobsDir = Join-Path -Path $DockerDir -ChildPath "blobs\sha256"
    if (-not (Test-Path -LiteralPath $ociLayoutPath -PathType Leaf)) {
        throw "OCI layout file was not found: $ociLayoutPath"
    }
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        throw "OCI index file was not found: $indexPath"
    }
    if (-not (Test-Path -LiteralPath $blobsDir -PathType Container)) {
        throw "OCI blobs directory was not found: $blobsDir"
    }

    $outputParent = Split-Path -Parent $OutputTar
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    $tarStream = [System.IO.File]::Open($OutputTar, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        Add-TarDirectoryEntry -OutputStream $tarStream -ArchivePath "blobs"
        Add-TarDirectoryEntry -OutputStream $tarStream -ArchivePath "blobs/sha256"
        Add-TarFileEntry -OutputStream $tarStream -SourcePath $ociLayoutPath -ArchivePath "oci-layout"
        Add-TarFileEntry -OutputStream $tarStream -SourcePath $indexPath -ArchivePath "index.json"

        Get-ChildItem -LiteralPath $blobsDir -File | Sort-Object Name | ForEach-Object {
            Add-TarFileEntry -OutputStream $tarStream -SourcePath $_.FullName -ArchivePath ("blobs/sha256/{0}" -f $_.Name)
        }

        Complete-TarArchive -OutputStream $tarStream
    }
    finally {
        $tarStream.Dispose()
    }
}

<#
.SYNOPSIS
ディレクトリ配下のファイルサイズ合計を取得します。
.PARAMETER Path
確認対象ディレクトリです。
.OUTPUTS
byte 単位の合計サイズを返します。
#>
function Get-DirectorySizeBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [Int64]0
    }

    [Int64]$total = 0
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File | ForEach-Object {
        $total += [Int64]$_.Length
    }
    return $total
}

<#
.SYNOPSIS
一時作業ディレクトリのサイズ上限を超えそうか確認します。
.PARAMETER WorkDir
確認対象の一時作業ディレクトリです。
.PARAMETER IncomingSizeBytes
これから追加する blob の byte 数です。
.PARAMETER ItemName
ログへ表示する対象名です。
#>
function Confirm-WorkDirCapacity {
    param(
        [Parameter(Mandatory = $true)][string]$WorkDir,
        [Parameter(Mandatory = $true)][Int64]$IncomingSizeBytes,
        [Parameter(Mandatory = $true)][string]$ItemName
    )

    if ($IncomingSizeBytes -gt $script:MaxWorkDirBytes) {
        Write-Log ("{0} is larger than the configured limit. item={1:N2} GB limit={2:N2} GB" -f $ItemName, ($IncomingSizeBytes / 1GB), ($script:MaxWorkDirBytes / 1GB)) "WARN"
        Write-Log "Increase -maxGB for this image, or use an output location that can accept this single blob." "STEP"
        return $false
    }

    $currentSize = Get-DirectorySizeBytes -Path $WorkDir
    if (($currentSize + $IncomingSizeBytes) -le $script:MaxWorkDirBytes) {
        return $true
    }

    Write-Log ("Temporary work directory will exceed the configured limit. current={0:N2} GB incoming={1:N2} GB limit={2:N2} GB" -f ($currentSize / 1GB), ($IncomingSizeBytes / 1GB), ($script:MaxWorkDirBytes / 1GB)) "WARN"
    Write-Log "Increase -maxGB or use an output location whose parent has enough free space." "STEP"
    return $false
}

<#
.SYNOPSIS
docker-dir のサイズ上限を超えそうな場合に退避を促します。
.PARAMETER DockerDir
確認対象の docker-dir です。
.PARAMETER IncomingSizeBytes
これから追加する blob の byte 数です。
.PARAMETER ItemName
ログへ表示する対象名です。
#>
function Confirm-DockerDirCapacity {
    param(
        [Parameter(Mandatory = $true)][string]$DockerDir,
        [Parameter(Mandatory = $true)][Int64]$IncomingSizeBytes,
        [Parameter(Mandatory = $true)][string]$ItemName
    )

    if ($IncomingSizeBytes -gt $script:MaxDockerDirBytes) {
        Write-Log ("{0} is larger than the configured limit. item={1:N2} GB limit={2:N2} GB" -f $ItemName, ($IncomingSizeBytes / 1GB), ($script:MaxDockerDirBytes / 1GB)) "WARN"
        Write-Log "Increase -maxGB for this image, or use an output location that can accept this single blob." "STEP"
        return $false
    }

    $currentSize = Get-DirectorySizeBytes -Path $DockerDir
    if (($currentSize + $IncomingSizeBytes) -le $script:MaxDockerDirBytes) {
        return $true
    }

    Write-Log ("docker-dir will exceed the configured limit. current={0:N2} GB incoming={1:N2} GB limit={2:N2} GB" -f ($currentSize / 1GB), ($IncomingSizeBytes / 1GB), ($script:MaxDockerDirBytes / 1GB)) "WARN"
    Write-Log "Copy this image directory to the file server, delete local docker-dir/blobs/sha256 blobs, then run the same command again." "STEP"
    return $false
}

<#
.SYNOPSIS
OCI layout の blob ファイルを分割せずに保存します。
.PARAMETER SourcePath
保存元ファイルです。
.PARAMETER BlobsDirectory
docker-dir/blobs/sha256 ディレクトリです。
.PARAMETER DigestHex
sha256 digest の hex 文字列です。
.OUTPUTS
作成した blob ファイル名を返します。
#>
function Save-OciBlobFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$BlobsDirectory,
        [Parameter(Mandatory = $true)][string]$DigestHex
    )

    $destinationPath = Join-Path -Path $BlobsDirectory -ChildPath $DigestHex
    Copy-Item -LiteralPath $SourcePath -Destination $destinationPath -Force
    return @((Split-Path -Leaf $destinationPath))
}

<#
.SYNOPSIS
ダウンロード進捗を記録する state オブジェクトを作成します。
.PARAMETER Image
イメージ情報です。
.PARAMETER Platform
対象 platform です。
.PARAMETER FileBase
出力ファイル名のベースです。
.OUTPUTS
state.json に保存するオブジェクトを返します。
#>
function New-DownloadState {
    param(
        [Parameter(Mandatory = $true)][object]$Image,
        [Parameter(Mandatory = $true)][string]$Platform,
        [Parameter(Mandatory = $true)][string]$FileBase,
        [Parameter(Mandatory = $true)][string]$Format
    )

    return [pscustomobject]@{
        Version = 1
        Image = $Image.RepoTag
        Platform = $Platform
        FileBase = $FileBase
        OutputTar = "$FileBase.tar"
        DockerDir = "docker-dir"
        Format = $Format
        MaxWorkDirBytes = $script:MaxWorkDirBytes
        MaxDockerDirBytes = $script:MaxDockerDirBytes
        ManifestDigest = $null
        Manifest = $null
        ConfigDigest = $null
        ConfigDownloaded = $false
        Config = $null
        Layers = @()
        ArchiveCompleted = $false
        CreatedAt = [DateTime]::UtcNow.ToString("o")
        UpdatedAt = [DateTime]::UtcNow.ToString("o")
    }
}

<#
.SYNOPSIS
state オブジェクトを UTF-8 no BOM の state.json として保存します。
.PARAMETER State
保存する state オブジェクトです。
.PARAMETER Path
state.json の出力先です。
#>
function Save-DownloadState {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $State.UpdatedAt = [DateTime]::UtcNow.ToString("o")
    Write-Utf8NoBomFile -Path $Path -Text ($State | ConvertTo-Json -Depth 10)
}

<#
.SYNOPSIS
既存の state.json を読み込みます。
.PARAMETER Path
state.json のパスです。
.OUTPUTS
読み込んだ state オブジェクト、または null を返します。
#>
function Read-DownloadState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

<#
.SYNOPSIS
指定 digest が state 上で完了済みかどうかを判定します。
.PARAMETER State
確認対象の state オブジェクトです。
.PARAMETER Digest
sha256: 付き digest です。
.OUTPUTS
完了済みなら true を返します。
#>
function Test-StateDigestCompleted {
    param(
        [AllowNull()]$State,
        [Parameter(Mandatory = $true)][string]$Digest
    )

    if ($null -eq $State) {
        return $false
    }
    if ($null -ne $State.Manifest -and $State.Manifest.Digest -eq $Digest) {
        return $true
    }
    if ($null -ne $State.Config -and $State.Config.Digest -eq $Digest) {
        return $true
    }
    foreach ($layer in @($State.Layers)) {
        if ($layer.Digest -eq $Digest -and $layer.Status -eq "completed") {
            return $true
        }
    }

    return $false
}

<#
.SYNOPSIS
state.json の Layers 配列に layer の進捗を追加または更新します。
.PARAMETER State
更新対象の state オブジェクトです。
.PARAMETER Index
1 始まりの layer 番号です。
.PARAMETER Digest
registry layer digest です。
.PARAMETER DiffId
未圧縮 layer tar の SHA256 digest です。
.PARAMETER Status
layer の状態です。
.PARAMETER MediaType
layer の media type です。
.PARAMETER Size
layer blob の byte 数です。
.PARAMETER Files
保存した blob ファイル名です。
#>
function Set-LayerState {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$Digest,
        [AllowNull()][string]$DiffId,
        [Parameter(Mandatory = $true)][string]$Status,
        [AllowNull()][string]$MediaType,
        [AllowNull()][Nullable[Int64]]$Size,
        [string[]]$Files = @()
    )

    $layers = @($State.Layers)
    $existing = @($layers | Where-Object { [int]$_.Index -eq $Index })
    if ($existing.Count -eq 0) {
        $layers += [pscustomobject]@{
            Index = $Index
            Digest = $Digest
            DiffId = $DiffId
            Status = $Status
            MediaType = $MediaType
            Size = $Size
            Files = @($Files)
            UpdatedAt = [DateTime]::UtcNow.ToString("o")
        }
    }
    else {
        $existing[0].Digest = $Digest
        $existing[0].DiffId = $DiffId
        $existing[0].Status = $Status
        $existing[0].MediaType = $MediaType
        $existing[0].Size = $Size
        $existing[0].Files = @($Files)
        $existing[0].UpdatedAt = [DateTime]::UtcNow.ToString("o")
    }

    $State.Layers = @($layers | Sort-Object Index)
}

<#
.SYNOPSIS
イメージ取得、state 更新、OCI layout 出力までの主処理を実行します。
#>
function Invoke-Main {
    $image = Split-ImageReference -Reference $Image
    $resolvedOutputRoot = (New-Item -ItemType Directory -Path $OutputRoot -Force).FullName
    $isTarOutput = $OutputFormat -eq "Tar"
    $workRoot = $null
    $outputTar = $null
    $outputTarName = "$($image.FileBase).tar"
    $resumeState = $null

    if ($isTarOutput) {
        $outputTar = Join-Path -Path $resolvedOutputRoot -ChildPath $outputTarName
        if (Test-Path -LiteralPath $outputTar -PathType Leaf) {
            if ($Force) {
                Remove-Item -LiteralPath $outputTar -Force
            }
            else {
                throw "Output archive already exists. Remove it or pass -Force: $outputTar"
            }
        }

        $workRoot = New-ArchiveWorkRoot -OutputRootPath $resolvedOutputRoot -FileBase $image.FileBase
        $outputDir = Join-Path -Path $workRoot -ChildPath ([guid]::NewGuid().ToString("N"))
        $created = New-Item -ItemType Directory -Path $outputDir -Force
        $statePath = Join-Path -Path $created.FullName -ChildPath "state.json"
        $state = New-DownloadState -Image $image -Platform $Platform -FileBase $image.FileBase -Format "oci-archive"
        $state.OutputTar = $outputTarName
    }
    else {
        $outputDir = Join-Path -Path $resolvedOutputRoot -ChildPath $image.FileBase
        $statePath = Join-Path -Path $outputDir -ChildPath "state.json"
        $resumeState = Read-DownloadState -Path $statePath
        if ((Test-Path -LiteralPath $outputDir) -and $Force -and $null -eq $resumeState) {
            Remove-Item -LiteralPath $outputDir -Recurse -Force
        }
        elseif ((Test-Path -LiteralPath $outputDir) -and $null -eq $resumeState) {
            $existing = @(Get-ChildItem -LiteralPath $outputDir -Force -ErrorAction SilentlyContinue)
            if ($existing.Count -gt 0) {
                throw "Existing output files were found. Remove them or pass -Force: $outputDir"
            }
        }

        $created = New-Item -ItemType Directory -Path $outputDir -Force
        $statePath = Join-Path -Path $created.FullName -ChildPath "state.json"
        $resumeState = Read-DownloadState -Path $statePath
        $state = if ($null -ne $resumeState) {
            Write-Log "Resuming from state.json" "STEP"
            $resumeState
        }
        else {
            New-DownloadState -Image $image -Platform $Platform -FileBase $image.FileBase -Format "oci-layout"
        }
    }

    $tempDir = Join-Path -Path $created.FullName -ChildPath "_work"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $dockerDir = Join-Path -Path $created.FullName -ChildPath "docker-dir"
    New-Item -ItemType Directory -Path $dockerDir -Force | Out-Null
    $blobsDir = Join-Path -Path $dockerDir -ChildPath "blobs\sha256"
    New-Item -ItemType Directory -Path $blobsDir -Force | Out-Null
    if (-not $isTarOutput) {
        $mergeDest = Join-Path -Path $created.FullName -ChildPath "merge.sh"
        Write-Utf8NoBomFile -Path $mergeDest -Text ((New-MergeScriptContent) -replace "`r`n", "`n")
    }
    Save-DownloadState -State $state -Path $statePath

    $script:OutputDir = $created.FullName
    $script:TarFileBase = $image.FileBase

    Write-Log ("Image: {0}" -f $image.RepoTag) "STEP"
    Write-Log ("Registry: {0}, Repository: {1}" -f $image.RegistryHost, $image.Repository) "INFO"
    $token = Get-RegistryToken -RegistryHost $image.RegistryHost -Repository $image.Repository

    $manifestResult = Get-RegistryManifest -Image $image -Token $token -Reference $image.ManifestReference
    $manifestResult = Resolve-PlatformManifest -Image $image -Token $token -ManifestResult $manifestResult -Platform $Platform
    $manifest = $manifestResult.Json
    $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($manifestResult.Content)
    $manifestDigestHex = -join ([System.Security.Cryptography.SHA256]::Create().ComputeHash($manifestBytes) | ForEach-Object { $_.ToString("x2") })
    if (-not [string]::IsNullOrWhiteSpace($manifestResult.Digest) -and $manifestResult.Digest -ne "sha256:$manifestDigestHex") {
        throw "manifest digest mismatch: expected=$($manifestResult.Digest) actual=sha256:$manifestDigestHex"
    }
    $manifestMediaType = if ($null -ne (Get-JsonProperty -Object $manifest -Name "mediaType")) {
        [string](Get-JsonProperty -Object $manifest -Name "mediaType")
    }
    elseif (-not [string]::IsNullOrWhiteSpace($manifestResult.MediaType)) {
        [string]$manifestResult.MediaType
    }
    else {
        "application/vnd.oci.image.manifest.v1+json"
    }

    if ($null -eq $manifest.config -or $null -eq $manifest.layers) {
        throw "Unsupported manifest. Specify a schema2 or OCI image manifest."
    }

    $manifestBlobPath = Join-Path -Path $tempDir -ChildPath ($manifestDigestHex + ".manifest.json")
    Write-Utf8NoBomFile -Path $manifestBlobPath -Text $manifestResult.Content
    if (Test-StateDigestCompleted -State $state -Digest "sha256:$manifestDigestHex") {
        Write-Log "Skipping completed manifest blob: sha256:$manifestDigestHex" "OK"
        Remove-WorkFile -Path $manifestBlobPath
    }
    else {
        $hasCapacity = if ($isTarOutput) {
            Confirm-WorkDirCapacity -WorkDir $created.FullName -IncomingSizeBytes ([Int64]$manifestBytes.Length) -ItemName "manifest blob"
        }
        else {
            Confirm-DockerDirCapacity -DockerDir $dockerDir -IncomingSizeBytes ([Int64]$manifestBytes.Length) -ItemName "manifest blob"
        }
        if (-not $hasCapacity) {
            Save-DownloadState -State $state -Path $statePath
            Remove-WorkFile -Path $manifestBlobPath
            return
        }
        $manifestBlobFiles = Save-OciBlobFile -SourcePath $manifestBlobPath -BlobsDirectory $blobsDir -DigestHex $manifestDigestHex
        Remove-WorkFile -Path $manifestBlobPath
        $state.ManifestDigest = "sha256:$manifestDigestHex"
        $state.Manifest = [pscustomobject]@{
            Digest = "sha256:$manifestDigestHex"
            Files = @($manifestBlobFiles)
        }
        Save-DownloadState -State $state -Path $statePath
    }

    $configDigest = [string]$manifest.config.digest
    $configHex = $configDigest.Replace("sha256:", "")
    $configPath = Join-Path -Path $tempDir -ChildPath ($configHex + ".json")
    $configUri = "https://$($image.RegistryHost)/v2/$($image.Repository)/blobs/$configDigest"
    $configSize = [Int64](Get-JsonProperty -Object $manifest.config -Name "size")
    if (Test-StateDigestCompleted -State $state -Digest $configDigest) {
        Write-Log "Skipping completed config blob: $configDigest" "OK"
    }
    else {
        $hasCapacity = if ($isTarOutput) {
            Confirm-WorkDirCapacity -WorkDir $created.FullName -IncomingSizeBytes $configSize -ItemName "config blob"
        }
        else {
            Confirm-DockerDirCapacity -DockerDir $dockerDir -IncomingSizeBytes $configSize -ItemName "config blob"
        }
        if (-not $hasCapacity) {
            Save-DownloadState -State $state -Path $statePath
            return
        }
        Write-Log "Downloading config blob." "STEP"
        Invoke-RegistryWebRequest -Uri $configUri -Token $token -Accept $null -OutFile $configPath | Out-Null
        $actualConfigHash = Get-FileSha256 -Path $configPath
        if ($actualConfigHash -ne $configHex) {
            throw "config digest mismatch: expected=$configHex actual=$actualConfigHash"
        }
        $configBlobFiles = Save-OciBlobFile -SourcePath $configPath -BlobsDirectory $blobsDir -DigestHex $configHex
        Remove-WorkFile -Path $configPath
        $state.ConfigDigest = $configDigest
        $state.ConfigDownloaded = $true
        $state.Config = [pscustomobject]@{
            Digest = $configDigest
            Files = @($configBlobFiles)
        }
        Save-DownloadState -State $state -Path $statePath
    }

    $layerIndex = 0
    foreach ($layer in @($manifest.layers)) {
        $layerIndex++
        $digest = [string]$layer.digest
        $digestHex = $digest.Replace("sha256:", "")
        $mediaType = [string](Get-JsonProperty -Object $layer -Name "mediaType")
        $layerSize = [Int64](Get-JsonProperty -Object $layer -Name "size")
        $blobPath = Join-Path -Path $tempDir -ChildPath ("layer-{0}-{1}.blob" -f $layerIndex, $digestHex)
        $blobUri = "https://$($image.RegistryHost)/v2/$($image.Repository)/blobs/$digest"

        if (Test-StateDigestCompleted -State $state -Digest $digest) {
            Write-Log ("Skipping completed layer {0}/{1}: {2}" -f $layerIndex, @($manifest.layers).Count, $digest) "OK"
            continue
        }

        Set-LayerState -State $state -Index $layerIndex -Digest $digest -DiffId $null -Status "downloading" -MediaType $mediaType -Size $layerSize
        Save-DownloadState -State $state -Path $statePath
        $hasCapacity = if ($isTarOutput) {
            Confirm-WorkDirCapacity -WorkDir $created.FullName -IncomingSizeBytes $layerSize -ItemName ("layer {0}" -f $layerIndex)
        }
        else {
            Confirm-DockerDirCapacity -DockerDir $dockerDir -IncomingSizeBytes $layerSize -ItemName ("layer {0}" -f $layerIndex)
        }
        if (-not $hasCapacity) {
            Save-DownloadState -State $state -Path $statePath
            return
        }
        Write-Log ("Downloading layer {0}/{1}: {2}" -f $layerIndex, @($manifest.layers).Count, $digest) "STEP"
        Invoke-RegistryWebRequest -Uri $blobUri -Token $token -Accept $null -OutFile $blobPath | Out-Null
        $actualLayerHash = Get-FileSha256 -Path $blobPath
        if ($actualLayerHash -ne $digestHex) {
            throw "layer digest mismatch: expected=$digestHex actual=$actualLayerHash"
        }
        $downloadedLayerSize = [Int64](Get-Item -LiteralPath $blobPath).Length
        $layerBlobFiles = Save-OciBlobFile -SourcePath $blobPath -BlobsDirectory $blobsDir -DigestHex $digestHex
        Remove-WorkFile -Path $blobPath
        Set-LayerState -State $state -Index $layerIndex -Digest $digest -DiffId $null -Status "completed" -MediaType $mediaType -Size $downloadedLayerSize -Files @($layerBlobFiles)
        Save-DownloadState -State $state -Path $statePath

    }

    $ociLayout = [ordered]@{
        imageLayoutVersion = "1.0.0"
    }
    Write-Utf8NoBomFile -Path (Join-Path -Path $dockerDir -ChildPath "oci-layout") -Text ($ociLayout | ConvertTo-Json -Depth 5)

    $indexManifest = [ordered]@{
        mediaType = $manifestMediaType
        digest = "sha256:$manifestDigestHex"
        size = [Int64]$manifestBytes.Length
        annotations = [ordered]@{
            "org.opencontainers.image.ref.name" = $image.RepoTag
        }
    }
    $index = [ordered]@{
        schemaVersion = 2
        manifests = @($indexManifest)
    }
    Write-Utf8NoBomFile -Path (Join-Path -Path $dockerDir -ChildPath "index.json") -Text ($index | ConvertTo-Json -Depth 10)

    if ($isTarOutput) {
        Write-Log ("OCI layout created in a temporary work directory. Limit={0:N2} GB." -f $maxGB) "OK"
        Write-Log ("Creating archive: {0}" -f $outputTar) "STEP"
        New-OciArchiveTar -DockerDir $dockerDir -OutputTar $outputTar
        $state.ArchiveCompleted = $true
        Save-DownloadState -State $state -Path $statePath

        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue

        Write-Log ("Created: {0}" -f $outputTar) "OK"
        Write-Log ("Load with: docker load -i {0}" -f $outputTar) "OK"
    }
    else {
        Write-Log ("OCI docker-dir created. Keep each transferred docker-dir copy within {0:N2} GB." -f $maxGB) "OK"
        $state.ArchiveCompleted = $true
        Save-DownloadState -State $state -Path $statePath

        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Log ("Complete: {0}" -f $created.FullName) "OK"
        Write-Log ("Run 'bash merge.sh' in the copied directory to create {0}.tar." -f $image.FileBase) "OK"
    }
}

try {
    Invoke-Main
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    if ($null -ne $_.InvocationInfo -and $null -ne $_.InvocationInfo.ScriptLineNumber) {
        Write-Log ("Line: {0}" -f $_.InvocationInfo.ScriptLineNumber) "ERROR"
    }
    exit 1
}
