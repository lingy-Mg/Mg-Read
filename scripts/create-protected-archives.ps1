<#
.SYNOPSIS
  Create password-protected archives for build artifacts.

.DESCRIPTION
  Recursively scans the input directory for `.exe` / `.apk` files and packs
  them into password-protected `.zip` archives with 7-Zip.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$Password
)

$ErrorActionPreference = "Stop"

function Resolve-SevenZip() {
    $candidates = @(
        (Get-Command 7z -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    ) | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "7z/7-Zip was not found in PATH or the default install directories."
}

if (-not (Test-Path $InputDir)) {
    throw "Input directory does not exist: $InputDir"
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    throw "Archive password cannot be empty."
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$sevenZip = Resolve-SevenZip
$files = Get-ChildItem -Path $InputDir -Recurse -File | Where-Object {
    $_.Extension.ToLowerInvariant() -in @(".apk", ".exe")
}

if (-not $files) {
    throw "No .apk or .exe artifacts were found under $InputDir"
}

foreach ($file in $files) {
    $archivePath = Join-Path $OutputDir ($file.BaseName + ".zip")
    if (Test-Path $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    & $sevenZip a -tzip "-p$Password" -mem=AES256 $archivePath $file.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed while archiving $($file.FullName)"
    }

    Write-Host "[archive] $($file.Name) -> $archivePath"
}
