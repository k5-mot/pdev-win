<#
.SYNOPSIS
指定したディレクトリ直下でサイズが大きいファイルまたはフォルダを特定します。
.PARAMETER Path
確認対象のディレクトリです。
.PARAMETER Top
表示する件数です。
.PARAMETER IncludeHidden
隠しファイルや隠しフォルダも集計対象に含めます。
.EXAMPLE
.\CheckDisk.ps1 -Path .
.EXAMPLE
.\CheckDisk.ps1 -Path C:\Temp -Top 10 -IncludeHidden
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Convert-Path .),

    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Top = 10,

    [Parameter()]
    [switch]$IncludeHidden
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
byte 数を読みやすい単位の文字列へ変換します。
.PARAMETER Bytes
変換する byte 数です。
.OUTPUTS
サイズ文字列を返します。
#>
function ConvertTo-ReadableSize {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [Int64]::MaxValue)]
        [Int64]$Bytes
    )

    $units = @("B", "KB", "MB", "GB", "TB", "PB")
    [double]$size = $Bytes
    $unitIndex = 0

    while ($size -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
        $size = $size / 1024
        $unitIndex++
    }

    if ($unitIndex -eq 0) {
        return ("{0:N0} {1}" -f $size, $units[$unitIndex])
    }

    return ("{0:N2} {1}" -f $size, $units[$unitIndex])
}

<#
.SYNOPSIS
指定したファイルまたはフォルダの合計サイズを byte 単位で取得します。
.PARAMETER Item
サイズを集計するファイルまたはフォルダです。
.PARAMETER IncludeHidden
隠しファイルや隠しフォルダも集計対象に含めます。
.OUTPUTS
byte 単位の合計サイズを返します。
#>
function Get-ItemSizeBytes {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter()]
        [switch]$IncludeHidden
    )

    if ($Item -is [System.IO.FileInfo]) {
        return [Int64]$Item.Length
    }

    [Int64]$total = 0
    $childItems = if ($IncludeHidden) {
        Get-ChildItem -LiteralPath $Item.FullName -Recurse -Force -File -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -LiteralPath $Item.FullName -Recurse -File -ErrorAction SilentlyContinue
    }

    foreach ($childItem in $childItems) {
        $total += [Int64]$childItem.Length
    }

    return $total
}

<#
.SYNOPSIS
指定したディレクトリ直下のファイルまたはフォルダごとのサイズ情報を取得します。
.PARAMETER DirectoryPath
確認対象のディレクトリです。
.PARAMETER IncludeHidden
隠しファイルや隠しフォルダも集計対象に含めます。
.OUTPUTS
サイズ情報を持つオブジェクトを返します。
#>
function Get-ChildItemSize {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,

        [Parameter()]
        [switch]$IncludeHidden
    )

    $items = if ($IncludeHidden) {
        Get-ChildItem -LiteralPath $DirectoryPath -Force
    }
    else {
        Get-ChildItem -LiteralPath $DirectoryPath
    }

    foreach ($item in $items) {
        $sizeBytes = Get-ItemSizeBytes -Item $item -IncludeHidden:$IncludeHidden
        [pscustomobject]@{
            Name = $item.Name
            Path = $item.FullName
            Type = if ($item.PSIsContainer) { "Directory" } else { "File" }
            SizeBytes = $sizeBytes
            Size = ConvertTo-ReadableSize -Bytes $sizeBytes
        }
    }
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
    throw "Directory was not found: $resolvedPath"
}

$itemsBySize = @(Get-ChildItemSize -DirectoryPath $resolvedPath -IncludeHidden:$IncludeHidden |
    Sort-Object SizeBytes -Descending |
    Select-Object -First $Top)

if ($itemsBySize.Count -eq 0) {
    Write-Host ("Target directory is empty: {0}" -f $resolvedPath)
    return
}

$rank = 0
$topItems = @($itemsBySize | ForEach-Object {
    $rank++
    [pscustomobject]@{
        Rank = $rank
        Type = $_.Type
        Size = $_.Size
        SizeBytes = $_.SizeBytes
        Name = $_.Name
        Path = $_.Path
    }
})

Write-Host ""
Write-Host "---------------------------------------"
Write-Host ("Target: {0}" -f $resolvedPath)
Write-Host ("Largest items: Top {0}" -f $topItems.Count)
Write-Host "---------------------------------------"

$topItems |
    Select-Object Rank, Size, Type, Name, Path |
    Format-Table -AutoSize
