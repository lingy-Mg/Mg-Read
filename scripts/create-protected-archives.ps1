<#
.SYNOPSIS
  Create password-protected archives for build artifacts.

.DESCRIPTION
  Recursively scans the input directory for `.exe` / `.apk` / `.tar.gz` / `.dmg` / `.hap` files and packs
  them into password-protected `.zip` archives with 7-Zip.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [string[]]$ExpectedKinds = @()
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

function Resolve-ArtifactKind([System.IO.FileInfo]$File) {
    $name = $File.Name.ToLowerInvariant()
    if ($name.EndsWith(".tar.gz") -or $name.EndsWith(".gz")) {
        if ($name -match 'linux-arm64') {
            return "linux-arm64"
        }
        if ($name -match 'linux-x64') {
            return "linux-x64"
        }
    }

    switch ($File.Extension.ToLowerInvariant()) {
        ".exe" { return "windows" }
        ".apk" { return "android" }
        ".dmg" { return "macos" }
        ".hap" { return "harmony" }
        default { return "" }
    }
}

if (-not (Test-Path $InputDir)) {
    throw "Input directory does not exist: $InputDir"
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    throw "Archive password cannot be empty."
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$sevenZip = Resolve-SevenZip
$files = Get-ChildItem -Path $InputDir -Recurse -File |
    Where-Object { Resolve-ArtifactKind -File $_ } |
    Sort-Object FullName

if (-not $files) {
    throw "No .apk, .dmg, .exe, .hap, or .tar.gz artifacts were found under $InputDir"
}

$foundKinds = @($files |
    ForEach-Object { Resolve-ArtifactKind -File $_ } |
    Where-Object { $_ } |
    Sort-Object -Unique)

# A previous public release silently dropped Harmony assets even though the
# build job succeeded. Fail fast here instead of publishing a partial release.
$normalizedExpectedKinds = @($ExpectedKinds |
    ForEach-Object { $_ -split "," } |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ } |
    Sort-Object -Unique)

$missingKinds = @($normalizedExpectedKinds |
    Where-Object { $foundKinds -notcontains $_ })

if ($missingKinds.Count -gt 0) {
    throw "Expected release artifacts were not found under ${InputDir}: $($missingKinds -join ', ')"
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
