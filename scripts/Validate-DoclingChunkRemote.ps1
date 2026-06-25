
[CmdletBinding()]
param(
  [string]$BaseUrl = 'http://192.168.1.100:50000',

  [string]$ApiKey = $env:DOCLING_SERVE_API_KEY,

  [string]$Python = 'python',

  [string]$DocumentPath = '',

  [string]$OutputDir = '',

  [string]$Chunker = 'hierarchical',

  [string]$FromFormat = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

<#
.SYNOPSIS
指定されたディレクトリを必要に応じて作成します。
.PARAMETER Path
作成するディレクトリのパスです。
#>
function New-Directory {
    param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

<#
.SYNOPSIS
外部コマンドを実行し、終了コードを検証します。
.PARAMETER FilePath
実行するファイルのパスです。
.PARAMETER Arguments
コマンド引数です。
#>
function Invoke-Checked {
    param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @()
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with ExitCode=${LASTEXITCODE}: $FilePath"
  }
}

<#
.SYNOPSIS
検証用の小さな Markdown ファイルを作成します。
.PARAMETER Path
作成先ファイルパスです。
#>
function New-SampleMarkdown {
    param([Parameter(Mandatory)][string]$Path)

  $body = @'
# Remote Chunk Validation

This file verifies docling-serve remote chunking.

The validator submits this Markdown file to the async chunk endpoint and checks that a chunks manifest is created.
'@
  Set-Content -LiteralPath $Path -Value $body -Encoding UTF8
}

<#
.SYNOPSIS
chunks-manifest.json の最低限の内容を検証します。
.PARAMETER ManifestPath
検証する manifest のパスです。
#>
function Test-ChunkManifest {
    param([Parameter(Mandatory)][string]$ManifestPath)

  if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest was not created: $ManifestPath"
  }

  $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
  if ($null -eq $manifest.chunks -or @($manifest.chunks).Count -lt 1) {
    throw "Manifest does not contain chunks: $ManifestPath"
  }

  foreach ($chunk in @($manifest.chunks)) {
    $chunkPath = Join-Path (Split-Path -Parent $ManifestPath) $chunk.path
    if (-not (Test-Path -LiteralPath $chunkPath)) {
      throw "Chunk file was not created: $chunkPath"
    }
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$chunkScript = Join-Path $repoRoot '.agents/skills/translate-ja/scripts/chunk_text_remote.py'
if (-not (Test-Path -LiteralPath $chunkScript)) {
  throw "chunk_text_remote.py was not found: $chunkScript"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $repoRoot '.tmp/docling-chunk-remote'
}
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
New-Directory $OutputDir

if ([string]::IsNullOrWhiteSpace($DocumentPath)) {
  $DocumentPath = Join-Path $OutputDir 'sample.md'
  New-SampleMarkdown -Path $DocumentPath
}
$DocumentPath = [IO.Path]::GetFullPath($DocumentPath)
if (-not (Test-Path -LiteralPath $DocumentPath)) {
  throw "Document was not found: $DocumentPath"
}
if ([string]::IsNullOrWhiteSpace($FromFormat)) {
  $extension = [IO.Path]::GetExtension($DocumentPath).TrimStart('.').ToLowerInvariant()
  $FromFormat = if ($extension -eq 'pdf') { 'pdf' } else { 'md' }
}

$arguments = @(
  $chunkScript,
  $DocumentPath,
  $OutputDir,
  '--base-url', $BaseUrl.TrimEnd('/'),
  '--chunker', $Chunker,
  '--from-format', $FromFormat,
  '--max-words', '120',
  '--request-timeout', '60',
  '--poll-interval', '2',
  '--timeout', '300'
)
if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
  $arguments += @('--api-key', $ApiKey)
}

Invoke-Checked -FilePath $Python -Arguments $arguments
$manifestPath = Join-Path $OutputDir 'chunks-manifest.json'
Test-ChunkManifest -ManifestPath $manifestPath
Write-Host "docling-serve remote chunk validation OK: $manifestPath"
