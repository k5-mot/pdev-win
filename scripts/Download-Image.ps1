<#
.SYNOPSIS
Downloads an image from a Docker/OCI registry and writes a split OCI layout directory.

.DESCRIPTION
Uses Docker Registry HTTP API v2 directly without Docker Desktop, WSL2, administrator rights, regctl.exe, or crane.exe.
The generated docker-dir can be packed by scripts/merge.sh into a docker/podman load compatible OCI archive tar.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("ImageRef")]
    [string]$imageName,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ $_ -gt 0 })]
    [double]$maxGB,

    [string]$OutputRoot,

    [string]$Platform = "linux/amd64",

    [switch]$Force,

    [switch]$KeepTemp
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

$script:PartSizeBytes = [Int64][Math]::Ceiling($maxGB * 1GB)
$script:PartNumber = 0
$script:PartBytes = [Int64]0
$script:PartStream = $null
$script:PartPaths = New-Object System.Collections.Generic.List[string]
$script:TarFileBase = $null
$script:OutputDir = $null

<#
.SYNOPSIS
次の分割 Part ファイルを開きます。
#>
function Open-NextPart {
    if ($null -ne $script:PartStream) {
        $script:PartStream.Flush()
        $script:PartStream.Dispose()
    }

    $script:PartNumber++
    $script:PartBytes = 0
    $partPath = Join-Path -Path $script:OutputDir -ChildPath ("{0}_Part{1}.tar" -f $script:TarFileBase, $script:PartNumber)
    $script:PartPaths.Add($partPath) | Out-Null
    $script:PartStream = [System.IO.File]::Open($partPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    Write-Log ("Part{0} start: {1}" -f $script:PartNumber, $partPath) "STEP"
}

<#
.SYNOPSIS
Docker archive の byte 列を Part サイズで分割しながら書き込みます。
.PARAMETER Buffer
書き込む byte 配列です。
.PARAMETER Offset
書き込み開始位置です。
.PARAMETER Count
書き込む byte 数です。
#>
function Write-ArchiveBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Buffer,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Count
    )

    $written = 0
    while ($written -lt $Count) {
        if ($null -eq $script:PartStream -or $script:PartBytes -ge $script:PartSizeBytes) {
            Open-NextPart
        }

        $remainingPart = $script:PartSizeBytes - $script:PartBytes
        $toWrite = [int][Math]::Min([Int64]($Count - $written), $remainingPart)
        $script:PartStream.Write($Buffer, $Offset + $written, $toWrite)
        $script:PartBytes += $toWrite
        $written += $toWrite
    }
}

<#
.SYNOPSIS
ローカルファイルを tar エントリとして archive に書き込みます。
.PARAMETER ArchivePath
tar 内のパスです。
.PARAMETER SourcePath
書き込み元ファイルパスです。
#>
function Write-ArchiveFile {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $file = Get-Item -LiteralPath $SourcePath
    $header = New-TarHeader -Name $ArchivePath -Size $file.Length
    Write-ArchiveBytes -Buffer $header -Offset 0 -Count $header.Length

    $input = [System.IO.File]::OpenRead($SourcePath)
    $buffer = New-Object byte[] 1048576
    try {
        while ($true) {
            $read = $input.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) {
                break
            }
            Write-ArchiveBytes -Buffer $buffer -Offset 0 -Count $read
        }
    }
    finally {
        $input.Dispose()
    }

    $padding = (512 - ($file.Length % 512)) % 512
    if ($padding -gt 0) {
        $zeros = New-Object byte[] ([int]$padding)
        Write-ArchiveBytes -Buffer $zeros -Offset 0 -Count $zeros.Length
    }
}

<#
.SYNOPSIS
文字列を一時ファイル経由で tar エントリとして archive に書き込みます。
.PARAMETER ArchivePath
tar 内のパスです。
.PARAMETER Text
書き込むテキストです。
#>
function Write-ArchiveTextFile {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $temp = [System.IO.Path]::GetTempFileName()
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temp, $Text, $utf8)
        Write-ArchiveFile -ArchivePath $ArchivePath -SourcePath $temp
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

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
ファイルを指定サイズ以下の part ファイルへ分割します。
.PARAMETER SourcePath
分割元ファイルです。
.PARAMETER DestinationPath
分割しない場合の出力ファイル、または part 名の基準になるパスです。
.PARAMETER PartSizeBytes
1 part の最大 byte 数です。
.OUTPUTS
作成したファイル名の配列を返します。
#>
function Split-FileToParts {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][Int64]$PartSizeBytes
    )

    $source = Get-Item -LiteralPath $SourcePath
    $created = New-Object System.Collections.Generic.List[string]
    if ($source.Length -le $PartSizeBytes) {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
        $created.Add((Split-Path -Leaf $DestinationPath)) | Out-Null
        return @($created)
    }

    $input = [System.IO.File]::OpenRead($SourcePath)
    $buffer = New-Object byte[] 1048576
    try {
        $partNumber = 1
        while ($input.Position -lt $input.Length) {
            $partPath = "{0}.part{1:D4}" -f $DestinationPath, $partNumber
            $output = [System.IO.File]::Open($partPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                [Int64]$written = 0
                while ($written -lt $PartSizeBytes -and $input.Position -lt $input.Length) {
                    $toRead = [int][Math]::Min([Int64]$buffer.Length, $PartSizeBytes - $written)
                    $read = $input.Read($buffer, 0, $toRead)
                    if ($read -le 0) {
                        break
                    }
                    $output.Write($buffer, 0, $read)
                    $written += $read
                }
            }
            finally {
                $output.Dispose()
            }

            $created.Add((Split-Path -Leaf $partPath)) | Out-Null
            $partNumber++
        }
    }
    finally {
        $input.Dispose()
    }

    return @($created)
}

<#
.SYNOPSIS
OCI layout の blob ファイルを指定サイズ以下の part ファイルへ分割保存します。
.PARAMETER SourcePath
保存元ファイルです。
.PARAMETER BlobsDirectory
docker-dir/blobs/sha256 ディレクトリです。
.PARAMETER DigestHex
sha256 digest の hex 文字列です。
.PARAMETER PartSizeBytes
1 part の最大 byte 数です。
.OUTPUTS
作成した blob ファイル名または part ファイル名の配列を返します。
#>
function Save-OciBlobFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$BlobsDirectory,
        [Parameter(Mandatory = $true)][string]$DigestHex,
        [Parameter(Mandatory = $true)][Int64]$PartSizeBytes
    )

    $destinationPath = Join-Path -Path $BlobsDirectory -ChildPath $DigestHex
    return @(Split-FileToParts -SourcePath $SourcePath -DestinationPath $destinationPath -PartSizeBytes $PartSizeBytes)
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
        [Parameter(Mandatory = $true)][string]$FileBase
    )

    return [pscustomobject]@{
        Version = 1
        Image = $Image.RepoTag
        Platform = $Platform
        FileBase = $FileBase
        Format = "oci-layout"
        ManifestDigest = $null
        ConfigDigest = $null
        ConfigDownloaded = $false
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
#>
function Set-LayerState {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$Digest,
        [AllowNull()][string]$DiffId,
        [Parameter(Mandatory = $true)][string]$Status
    )

    $layers = @($State.Layers)
    $existing = @($layers | Where-Object { [int]$_.Index -eq $Index })
    if ($existing.Count -eq 0) {
        $layers += [pscustomobject]@{
            Index = $Index
            Digest = $Digest
            DiffId = $DiffId
            Status = $Status
            UpdatedAt = [DateTime]::UtcNow.ToString("o")
        }
    }
    else {
        $existing[0].Digest = $Digest
        $existing[0].DiffId = $DiffId
        $existing[0].Status = $Status
        $existing[0].UpdatedAt = [DateTime]::UtcNow.ToString("o")
    }

    $State.Layers = @($layers | Sort-Object Index)
}

<#
.SYNOPSIS
tar archive の終端ブロックを書き込み、現在の Part を閉じます。
#>
function Close-Archive {
    $zeros = New-Object byte[] 1024
    Write-ArchiveBytes -Buffer $zeros -Offset 0 -Count $zeros.Length
    if ($null -ne $script:PartStream) {
        $script:PartStream.Flush()
        $script:PartStream.Dispose()
        $script:PartStream = $null
    }
}

<#
.SYNOPSIS
イメージ取得、state 更新、OCI layout 分割出力までの主処理を実行します。
#>
function Invoke-Main {
    $image = Split-ImageReference -Reference $imageName
    $resolvedOutputRoot = (New-Item -ItemType Directory -Path $OutputRoot -Force).FullName
    $outputDir = Join-Path -Path $resolvedOutputRoot -ChildPath $image.FileBase
    if ((Test-Path -LiteralPath $outputDir) -and $Force) {
        Remove-Item -LiteralPath $outputDir -Recurse -Force
    }
    elseif (Test-Path -LiteralPath $outputDir) {
        $existing = @(Get-ChildItem -LiteralPath $outputDir -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw "Existing output files were found. Remove them or pass -Force: $outputDir"
        }
    }

    $created = New-Item -ItemType Directory -Path $outputDir -Force
    $tempDir = Join-Path -Path $created.FullName -ChildPath "_work"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $dockerDir = Join-Path -Path $created.FullName -ChildPath "docker-dir"
    New-Item -ItemType Directory -Path $dockerDir -Force | Out-Null
    $blobsDir = Join-Path -Path $dockerDir -ChildPath "blobs\sha256"
    New-Item -ItemType Directory -Path $blobsDir -Force | Out-Null
    $statePath = Join-Path -Path $dockerDir -ChildPath "state.json"
    $state = New-DownloadState -Image $image -Platform $Platform -FileBase $image.FileBase
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
    $manifestBlobFiles = Save-OciBlobFile -SourcePath $manifestBlobPath -BlobsDirectory $blobsDir -DigestHex $manifestDigestHex -PartSizeBytes $script:PartSizeBytes
    Copy-Item -LiteralPath $manifestBlobPath -Destination (Join-Path -Path $dockerDir -ChildPath "manifest.json") -Force
    $state.ManifestDigest = "sha256:$manifestDigestHex"
    Save-DownloadState -State $state -Path $statePath

    $configDigest = [string]$manifest.config.digest
    $configHex = $configDigest.Replace("sha256:", "")
    $configPath = Join-Path -Path $tempDir -ChildPath ($configHex + ".json")
    $configUri = "https://$($image.RegistryHost)/v2/$($image.Repository)/blobs/$configDigest"
    Write-Log "Downloading config blob." "STEP"
    Invoke-RegistryWebRequest -Uri $configUri -Token $token -Accept $null -OutFile $configPath | Out-Null
    $actualConfigHash = Get-FileSha256 -Path $configPath
    if ($actualConfigHash -ne $configHex) {
        throw "config digest mismatch: expected=$configHex actual=$actualConfigHash"
    }
    $configBlobFiles = Save-OciBlobFile -SourcePath $configPath -BlobsDirectory $blobsDir -DigestHex $configHex -PartSizeBytes $script:PartSizeBytes
    $state.ConfigDigest = $configDigest
    $state.ConfigDownloaded = $true
    Save-DownloadState -State $state -Path $statePath

    $layerEntries = New-Object System.Collections.Generic.List[object]
    $layerIndex = 0
    foreach ($layer in @($manifest.layers)) {
        $layerIndex++
        $digest = [string]$layer.digest
        $digestHex = $digest.Replace("sha256:", "")
        $mediaType = [string](Get-JsonProperty -Object $layer -Name "mediaType")
        $blobPath = Join-Path -Path $tempDir -ChildPath ("layer-{0}-{1}.blob" -f $layerIndex, $digestHex)
        $blobUri = "https://$($image.RegistryHost)/v2/$($image.Repository)/blobs/$digest"

        Set-LayerState -State $state -Index $layerIndex -Digest $digest -DiffId $null -Status "downloading"
        Save-DownloadState -State $state -Path $statePath
        Write-Log ("Downloading layer {0}/{1}: {2}" -f $layerIndex, @($manifest.layers).Count, $digest) "STEP"
        Invoke-RegistryWebRequest -Uri $blobUri -Token $token -Accept $null -OutFile $blobPath | Out-Null
        $actualLayerHash = Get-FileSha256 -Path $blobPath
        if ($actualLayerHash -ne $digestHex) {
            throw "layer digest mismatch: expected=$digestHex actual=$actualLayerHash"
        }
        $layerBlobFiles = Save-OciBlobFile -SourcePath $blobPath -BlobsDirectory $blobsDir -DigestHex $digestHex -PartSizeBytes $script:PartSizeBytes
        Set-LayerState -State $state -Index $layerIndex -Digest $digest -DiffId $null -Status "completed"
        Save-DownloadState -State $state -Path $statePath

        $layerEntries.Add([pscustomobject]@{
            Digest = $digest
            DigestHex = $digestHex
            MediaType = $mediaType
            Size = [Int64](Get-Item -LiteralPath $blobPath).Length
            Files = @($layerBlobFiles)
        }) | Out-Null
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

    # 仕様上の見通し用に manifest.json も docker-dir 直下へ置く。
    # podman load が参照する本体は blobs/sha256/<manifest digest> と index.json。
    $manifestSummaryLayers = @()
    foreach ($layerEntry in $layerEntries) {
        $manifestSummaryLayers += [ordered]@{
            digest = $layerEntry.Digest
            mediaType = $layerEntry.MediaType
            size = $layerEntry.Size
            files = @($layerEntry.Files)
        }
    }

    $manifestSummary = [ordered]@{
        schemaVersion = 2
        mediaType = $manifestMediaType
        digest = "sha256:$manifestDigestHex"
        config = [ordered]@{
            digest = $configDigest
            files = @($configBlobFiles)
        }
        layers = $manifestSummaryLayers
    }
    Write-Utf8NoBomFile -Path (Join-Path -Path $dockerDir -ChildPath "manifest.json") -Text ($manifestSummary | ConvertTo-Json -Depth 10)

    Write-Log ("OCI docker-dir created with blob part size {0:N2} GB." -f $maxGB) "OK"
    $state.ArchiveCompleted = $true
    Save-DownloadState -State $state -Path $statePath

    $metadata = [pscustomobject]@{
        Image = $image.RepoTag
        Platform = $Platform
        Format = "oci-layout"
        FileBase = $image.FileBase
        OutputTar = "$($image.FileBase).tar"
        DockerDir = "docker-dir"
        PartSizeBytes = $script:PartSizeBytes
        Manifest = [pscustomobject]@{
            Digest = "sha256:$manifestDigestHex"
            Files = @($manifestBlobFiles)
        }
        Config = [pscustomobject]@{
            Digest = $configDigest
            Files = @($configBlobFiles)
        }
        Layers = @($layerEntries | ForEach-Object {
            [pscustomobject]@{
                Digest = $_.Digest
                Files = @($_.Files)
            }
        })
        CreatedAt = [DateTime]::UtcNow.ToString("o")
    }
    Write-Utf8NoBomFile -Path (Join-Path -Path $created.FullName -ChildPath "download-manifest.json") -Text ($metadata | ConvertTo-Json -Depth 5)

    $mergeSource = Join-Path -Path $ScriptDirectory -ChildPath "merge.sh"
    $mergeDest = Join-Path -Path $created.FullName -ChildPath "merge.sh"
    if (Test-Path -LiteralPath $mergeSource -PathType Leaf) {
        Copy-Item -LiteralPath $mergeSource -Destination $mergeDest -Force
    }

    if (-not $KeepTemp) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Log ("Complete: {0}" -f $created.FullName) "OK"
    Write-Log ("Run 'bash merge.sh' in the copied directory to restore split blobs and create {0}.tar." -f $image.FileBase) "OK"
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
