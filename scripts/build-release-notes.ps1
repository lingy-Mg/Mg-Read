<#
.SYNOPSIS
  Build GitHub release notes for the public build bridge.

.DESCRIPTION
  Resolves the previous public release's `build-manifest.json`, compares its
  `source_sha` with the current private-source commit, and writes a Markdown
  changelog that includes the commit count since the last packaged version.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublicRepo,

    [Parameter(Mandatory = $true)]
    [string]$CurrentTag,

    [Parameter(Mandatory = $true)]
    [string]$CurrentVersion,

    [Parameter(Mandatory = $true)]
    [string]$SourceRepository,

    [Parameter(Mandatory = $true)]
    [string]$SourceRef,

    [Parameter(Mandatory = $true)]
    [string]$SourceSha,

    [Parameter(Mandatory = $true)]
    [string]$Targets,

    [Parameter(Mandatory = $true)]
    [string]$WindowsResult,

    [Parameter(Mandatory = $true)]
    [string]$AndroidResult,

    [Parameter(Mandatory = $true)]
    [string]$HarmonyResult,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowUrl,

    [Parameter(Mandatory = $true)]
    [string]$SourceDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$MaxCommitLines = 200
)

$ErrorActionPreference = "Stop"

function Invoke-GhJson([string[]]$Arguments) {
    $output = & gh @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }

    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    return $output | ConvertFrom-Json -Depth 20
}

function Get-PreviousReleaseManifest {
    param(
        [string]$Repo,
        [string]$ExcludedTag
    )

    $releases = Invoke-GhJson @("api", "repos/$Repo/releases?per_page=20")
    if (-not $releases) {
        return $null
    }

    $previousRelease = $releases |
        Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -ne $ExcludedTag } |
        Sort-Object -Property published_at -Descending |
        Select-Object -First 1

    if (-not $previousRelease) {
        return $null
    }

    $tempDir = Join-Path ($env:RUNNER_TEMP ?? $env:TEMP) ("release-manifest-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        & gh release download $previousRelease.tag_name `
            --repo $Repo `
            --pattern build-manifest.json `
            --dir $tempDir `
            --clobber *> $null
        if ($LASTEXITCODE -ne 0) {
            return @{
                Release = $previousRelease
                Manifest = $null
            }
        }

        $manifestPath = Join-Path $tempDir "build-manifest.json"
        if (-not (Test-Path $manifestPath)) {
            return @{
                Release = $previousRelease
                Manifest = $null
            }
        }

        return @{
            Release = $previousRelease
            Manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json -Depth 20
        }
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force
        }
    }
}

function Test-GitCommitExists {
    param(
        [string]$RepositoryPath,
        [string]$CommitSha
    )

    & git -C $RepositoryPath cat-file -e "$CommitSha^{commit}" 2>$null
    return $LASTEXITCODE -eq 0
}

function Get-CommitLines {
    param(
        [string]$RepositoryPath,
        [string]$Range,
        [int]$MaxLines
    )

    $lines = & git -C $RepositoryPath log $Range --pretty=format:%H%x09%s --max-count=$MaxLines
    if ($LASTEXITCODE -ne 0) {
        throw "git log failed for range $Range"
    }

    if ([string]::IsNullOrWhiteSpace($lines)) {
        return @()
    }

    return @($lines -split "`r?`n" | Where-Object { $_ })
}

function Get-CommitCount {
    param(
        [string]$RepositoryPath,
        [string]$Range
    )

    $count = & git -C $RepositoryPath rev-list --count $Range
    if ($LASTEXITCODE -ne 0) {
        throw "git rev-list failed for range $Range"
    }

    return [int]$count
}

if (-not (Test-Path $SourceDir)) {
    throw "Source directory does not exist: $SourceDir"
}

if (-not (Test-GitCommitExists -RepositoryPath $SourceDir -CommitSha $SourceSha)) {
    throw "Current source SHA does not exist in the checked out repository: $SourceSha"
}

$previousInfo = Get-PreviousReleaseManifest -Repo $PublicRepo -ExcludedTag $CurrentTag
$previousRelease = $previousInfo?.Release
$previousManifest = $previousInfo?.Manifest
$previousSourceSha = $previousManifest?.source_sha
$previousTag = $previousManifest?.release_tag
$previousVersion = $previousManifest?.release_version

$changeSummary = @()
$commitLines = @()
$commitCount = 0

if (-not $previousRelease) {
    $changeSummary += "- 未找到上一版公开 Release，本次视为首次发布。"
} elseif ([string]::IsNullOrWhiteSpace($previousSourceSha)) {
    $fallbackTag = if ($previousTag) { $previousTag } else { $previousRelease.tag_name }
    $changeSummary += ('- 上一版 Release (`{0}`) 缺少 build-manifest source sha，无法统计从上次打包以来的提交数。' -f $fallbackTag)
} elseif (-not (Test-GitCommitExists -RepositoryPath $SourceDir -CommitSha $previousSourceSha)) {
    $fallbackTag = if ($previousTag) { $previousTag } else { $previousRelease.tag_name }
    $changeSummary += ('- 上一版 Release (`{0}`) 的 source sha `{1}` 不在当前拉取的 git 历史中，无法直接生成增量提交列表。' -f $fallbackTag, $previousSourceSha)
} else {
    & git -C $SourceDir merge-base --is-ancestor $previousSourceSha $SourceSha 2>$null
    $isAncestor = $LASTEXITCODE -eq 0
    if (-not $isAncestor) {
        $changeSummary += ('- 找到了上一版 source sha `{0}`，但它不是本次 source sha `{1}` 的祖先提交，无法按线性历史统计。' -f $previousSourceSha, $SourceSha)
    } else {
        $range = "$previousSourceSha..$SourceSha"
        $commitCount = Get-CommitCount -RepositoryPath $SourceDir -Range $range
        $commitLines = Get-CommitLines -RepositoryPath $SourceDir -Range $range -MaxLines $MaxCommitLines

        $changeSummary += "- 上次发布标签：$($previousTag ?? $previousRelease.tag_name)"
        if ($previousVersion) {
            $changeSummary += "- 上次发布版本：$previousVersion"
        }
        $changeSummary += "- 上次发布 source sha：$previousSourceSha"
        $changeSummary += "- 自上次打包以来新增提交：$commitCount 个"

        if ($commitCount -eq 0) {
            $changeSummary += "- 本次发布与上一版使用相同的 source sha。"
        } elseif ($commitCount -gt $MaxCommitLines) {
            $changeSummary += "- 下方仅展示最近 $MaxCommitLines 条提交标题，完整数量以上面的统计为准。"
        }
    }
}

$noteLines = @(
    "## 构建信息",
    "- 来源仓库：$SourceRepository",
    "- Source ref：$SourceRef",
    "- Source sha：$SourceSha",
    "- 构建目标：$Targets",
    "- Windows：$WindowsResult",
    "- Android：$AndroidResult",
    "- Harmony：$HarmonyResult",
    "- 工作流运行：$WorkflowUrl",
    "",
    "## 更新日志"
)

$noteLines += $changeSummary

if ($commitLines.Count -gt 0) {
    $noteLines += ""
    $noteLines += "### 提交列表"

    foreach ($line in $commitLines) {
        $parts = $line.Split("`t", 2)
        $shortSha = $parts[0].Substring(0, [Math]::Min(7, $parts[0].Length))
        $subject = if ($parts.Count -gt 1) { $parts[1] } else { "" }
        $noteLines += "- ``$shortSha`` $subject"
    }
}

$content = ($noteLines -join "`r`n").Trim() + "`r`n"
Set-Content -Path $OutputPath -Value $content -Encoding utf8
Write-Host "Release notes written to $OutputPath"
