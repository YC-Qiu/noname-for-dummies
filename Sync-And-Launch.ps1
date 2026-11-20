[CmdletBinding()]
param(
    [string]$ClientRoot = 'E:\download\noname-for-dummies-Windows-v1.10.11.3\noname',
    [switch]$Preview,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

try {
    $sourceRoot = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath.TrimEnd('\')
    $clientPath = (Resolve-Path -LiteralPath $ClientRoot).ProviderPath.TrimEnd('\')
    $targetRoot = (Resolve-Path -LiteralPath (Join-Path $clientPath 'resources\app')).ProviderPath.TrimEnd('\')
    $gameExe = Join-Path $clientPath '无名杀.exe'
    $robocopy = (Get-Command robocopy.exe -ErrorAction Stop).Source

    if ($sourceRoot -eq $targetRoot -or
        $targetRoot.StartsWith($sourceRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $sourceRoot.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw '源码和客户端目录不能相同或互相包含。'
    }

    # Only these game directories and entry files are deployed. The client shell,
    # UserData, Git metadata and launcher scripts stay outside the sync scope.
    $sourceDirectories = @(
        'audio', 'card', 'character', 'docs', 'extension', 'font', 'game',
        'image', 'layout', 'mode', 'node_modules', 'noname', 'theme'
    )
    $entryFiles = @('index.html', 'noname.js', 'service-worker.js')

    foreach ($relative in ($sourceDirectories + $entryFiles)) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative))) {
            throw "源码不完整，缺少：$relative"
        }
    }
    foreach ($required in @($gameExe, (Join-Path $targetRoot 'main.js'), (Join-Path $targetRoot 'package.json'))) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "客户端不完整，缺少：$required"
        }
    }

    # Do not overwrite a running game's files or terminate a user's active match.
    if (-not $Preview) {
        $running = @(Get-CimInstance Win32_Process -Filter "Name = '无名杀.exe'" | Where-Object {
            -not $_.ExecutablePath -or $_.ExecutablePath -eq $gameExe
        })
        if ($running.Count -gt 0) {
            throw '请先正常退出 E 盘的无名杀，再双击启动脚本。'
        }
    }

    $logDirectory = Join-Path $env:LOCALAPPDATA 'NonameSourceLauncher\Logs'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $logPath = Join-Path $logDirectory ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
    $copyOptions = @('/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:1', '/XJ', '/NP', '/NFL', '/NDL', "/UNILOG+:$logPath")
    if ($Preview) { $copyOptions += '/L' }

    Write-Host "源码（主版本）：$sourceRoot"
    Write-Host "客户端运行目录：$targetRoot"
    if ($Preview) { Write-Host '预览模式：不会复制文件，也不会启动游戏。' }

    foreach ($relative in $sourceDirectories) {
        Write-Host "检查并同步：$relative"
        $sourceDirectory = Join-Path $sourceRoot $relative
        $targetDirectory = Join-Path $targetRoot $relative
        # /E copies additions and changes, including older source files. Do not
        # use /XO or /MIR: D is authoritative, but E-only files are preserved.
        & $robocopy $sourceDirectory $targetDirectory /E @copyOptions | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "同步 $relative 失败（代码 $LASTEXITCODE），详见：$logPath"
        }
    }
    & $robocopy $sourceRoot $targetRoot @entryFiles @copyOptions | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "同步入口文件失败（代码 $LASTEXITCODE），详见：$logPath"
    }

    Write-Host "日志：$logPath"
    if ($Preview) {
        Write-Host '预览完成。'
    } elseif ($NoLaunch) {
        Write-Host '同步完成，未启动游戏。'
    } else {
        Write-Host '同步完成，正在启动无名杀……'
        Start-Process -FilePath $gameExe -WorkingDirectory $clientPath | Out-Null
    }
    exit 0
} catch {
    Write-Host ("失败：" + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
