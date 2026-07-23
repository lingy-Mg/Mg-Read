<#
.SYNOPSIS
  Publish one completed public-build leaf artifact to a shared GitHub Release.

.DESCRIPTION
  Creates password-protected archives, then creates the visible Release with
  the first successful artifact or appends later artifacts to the same tag.
  Release creation is retried because independent matrix jobs can finish at
  the same time and race to create the shared tag.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$ArchivePassword,

    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag,

    [Parameter(Mandatory = $true)]
    [string]$ReleaseTitle,

    [Parameter(Mandatory = $true)]
    [string]$SourceRepository,

    [Parameter(Mandatory = $true)]
    [string]$SourceRef,

    [Parameter(Mandatory = $true)]
    [string]$SourceSha,

    [Parameter(Mandatory = $true)]
    [string]$Targets,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowUrl
)

$ErrorActionPreference = "Stop"

function Resolve-SevenZipCommand() {
    foreach ($commandName in @("7z", "7zz", "7za")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    if ($IsLinux) {
        & sudo apt-get update
        if ($LASTEXITCODE -ne 0) {
            throw "apt-get update failed while installing 7-Zip."
        }
        & sudo apt-get install -y p7zip-full
    } elseif ($IsMacOS) {
        & brew install sevenzip
    } elseif ($IsWindows) {
        & choco install 7zip -y --no-progress
    } else {
        throw "Unsupported runner platform for installing 7-Zip."
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install 7-Zip."
    }

    foreach ($commandName in @("7z", "7zz", "7za")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    throw "7-Zip was installed but no 7z/7zz/7za command is available."
}

if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    throw "GH_TOKEN is required to publish release assets."
}
if ([string]::IsNullOrWhiteSpace($ArchivePassword)) {
    throw "ArchivePassword cannot be empty."
}

$null = Resolve-SevenZipCommand
$archiveScript = Join-Path $PSScriptRoot "create-protected-archives.ps1"
if (-not (Test-Path -LiteralPath $archiveScript)) {
    throw "Archive helper does not exist: $archiveScript"
}

& $archiveScript `
    -InputDir $InputDir `
    -OutputDir $OutputDir `
    -Password $ArchivePassword

$archives = @(Get-ChildItem -LiteralPath $OutputDir -File -Filter "*.zip" | Sort-Object Name)
if ($archives.Count -eq 0) {
    throw "No protected archives were created from $InputDir"
}

$notesPath = Join-Path $OutputDir "release-in-progress.md"
$noteLines = @(
    "## 构建信息",
    "- 状态：构建进行中，成功成品正在陆续发布；全部任务结束后会自动更新最终结果。",
    "- 来源仓库：$SourceRepository",
    "- Source ref：$SourceRef",
    "- 本次打包提交 ID：``$SourceSha``",
    "- 构建目标：$Targets",
    "- 工作流运行：$WorkflowUrl"
)
Set-Content -LiteralPath $notesPath -Value (($noteLines -join "`r`n") + "`r`n") -Encoding utf8

$assetPaths = @($archives | ForEach-Object { $_.FullName })
$lastExitCode = 1
for ($attempt = 1; $attempt -le 6; $attempt++) {
    # Upload-first is both the common path and the concurrency primitive:
    # an existing release is updated directly; if it does not exist yet,
    # create it. A simultaneous creator may win the race, in which case the
    # next attempt uploads to the release it created.
    & gh release upload $ReleaseTag @assetPaths --repo $Repository --clobber
    $lastExitCode = $LASTEXITCODE
    if ($lastExitCode -eq 0) {
        break
    }

    & gh release create $ReleaseTag @assetPaths `
        --repo $Repository `
        --title $ReleaseTitle `
        --notes-file $notesPath
    $lastExitCode = $LASTEXITCODE
    if ($lastExitCode -eq 0) {
        break
    }

    if ($attempt -lt 6) {
        Write-Warning "Release publish attempt $attempt failed; retrying shared-tag publication."
        Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 10))
    }
}

if ($lastExitCode -ne 0) {
    throw "Failed to create or update release $ReleaseTag after retries."
}

Write-Host "[release] published $($archives.Count) archive(s) to $Repository@$ReleaseTag"
