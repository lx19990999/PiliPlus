# 构建脚本 - 带实时日志输出
$ErrorActionPreference = "Continue"

$logFile = "build.log"
$startTime = Get-Date

# 清空日志文件
"" | Out-File $logFile -Encoding UTF8

function Write-BuildLog {
    param($message, $color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logMessage = "[$timestamp] $message"
    Write-Host $logMessage -ForegroundColor $color
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
}

Write-BuildLog "========================================" "Cyan"
Write-BuildLog "开始构建 PiliPlus Windows 和 Android" "Cyan"
Write-BuildLog "代理: $proxy" "Cyan"
Write-BuildLog "开始时间: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Cyan"
Write-BuildLog "日志文件: $logFile" "Cyan"
Write-BuildLog "========================================" "Cyan"
Write-BuildLog ""

# 清理
Write-BuildLog "[1/6] 清理之前的构建..." "Yellow"
flutter clean 2>&1 | ForEach-Object { 
    Write-Host $_ -ForegroundColor Gray
    Add-Content -Path $logFile -Value $_ -Encoding UTF8
}
# 清理可能损坏的 mpv 下载文件
Remove-Item -Path "build\windows\x64\mpv-dev-*.7z" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "build\windows\*\mpv-dev-*.7z" -Force -ErrorAction SilentlyContinue
Write-BuildLog "清理完成（包括损坏的下载文件）" "Green"
Write-BuildLog ""

# 获取依赖
Write-BuildLog "[2/6] 获取 Flutter 依赖..." "Yellow"
flutter pub get 2>&1 | ForEach-Object { 
    Write-Host $_ -ForegroundColor Gray
    Add-Content -Path $logFile -Value $_ -Encoding UTF8
}
if ($LASTEXITCODE -ne 0) {
    Write-BuildLog "获取依赖失败！退出码: $LASTEXITCODE" "Red"
    exit 1
}
Write-BuildLog "依赖获取完成" "Green"
Write-BuildLog ""

# 设置 Windows 版本
Write-BuildLog "[3/6] 设置 Windows 版本信息..." "Yellow"
$versionResult = pwsh -ExecutionPolicy Bypass -NoProfile -File lib/scripts/build.ps1 2>&1
$versionResult | ForEach-Object { 
    # 过滤掉 PowerShell profile 警告
    if ($_ -notmatch "Set-PSReadLineOption|The predictive suggestion") {
        Write-Host $_ -ForegroundColor Gray
        Add-Content -Path $logFile -Value $_ -Encoding UTF8
    }
}
if ($LASTEXITCODE -ne 0) {
    Write-BuildLog "版本信息设置失败，退出码: $LASTEXITCODE" "Red"
    exit 1
}
if (-not (Test-Path "pili_release.json")) {
    Write-BuildLog "版本信息设置失败：找不到 pili_release.json" "Red"
    exit 1
}
Write-BuildLog "版本信息设置完成" "Green"
Write-BuildLog ""

# 构建 Windows
Write-BuildLog "[4/6] 构建 Windows 客户端..." "Yellow"
Write-BuildLog "开始时间: $(Get-Date -Format 'HH:mm:ss')" "Gray"
$windowsStart = Get-Date

flutter build windows --release 2>&1 | ForEach-Object { 
    Write-Host $_ -ForegroundColor Gray
    Add-Content -Path $logFile -Value $_ -Encoding UTF8
    # 高亮显示关键信息
    if ($_ -match "Running Gradle|Building|Compiling|Linking|Generating|Downloading") {
        Write-Host $_ -ForegroundColor Cyan
    }
}

$windowsTime = [math]::Round(((Get-Date) - $windowsStart).TotalMinutes, 1)

if ($LASTEXITCODE -eq 0) {
    $exePath = "build\windows\x64\runner\Release\PiliPlus.exe"
    if (Test-Path $exePath) {
        $exe = Get-Item $exePath
        Write-BuildLog "Windows 构建成功！" "Green"
        Write-BuildLog "  文件: $($exe.FullName)" "Green"
        Write-BuildLog "  大小: $([math]::Round($exe.Length/1MB, 2)) MB" "Green"
        Write-BuildLog "  耗时: $windowsTime 分钟" "Green"
    } else {
        Write-BuildLog "Windows 构建完成但找不到输出文件" "Red"
        exit 1
    }
} else {
    Write-BuildLog "Windows 构建失败！退出码: $LASTEXITCODE" "Red"
    exit 1
}
Write-BuildLog ""

# 设置 Android 版本
Write-BuildLog "[5/6] 设置 Android 版本信息..." "Yellow"
$versionResult = pwsh -ExecutionPolicy Bypass -NoProfile -File lib/scripts/build.ps1 android 2>&1
$versionResult | ForEach-Object { 
    # 过滤掉 PowerShell profile 警告
    if ($_ -notmatch "Set-PSReadLineOption|The predictive suggestion") {
        Write-Host $_ -ForegroundColor Gray
        Add-Content -Path $logFile -Value $_ -Encoding UTF8
    }
}
if ($LASTEXITCODE -ne 0) {
    Write-BuildLog "版本信息设置失败，退出码: $LASTEXITCODE" "Red"
    exit 1
}
if (-not (Test-Path "pili_release.json")) {
    Write-BuildLog "版本信息设置失败：找不到 pili_release.json" "Red"
    exit 1
}
Write-BuildLog "版本信息设置完成" "Green"
Write-BuildLog ""

# 构建 Android
Write-BuildLog "[6/6] 构建 Android 客户端..." "Yellow"
Write-BuildLog "开始时间: $(Get-Date -Format 'HH:mm:ss')" "Gray"
$androidStart = Get-Date

flutter build apk --release --split-per-abi 2>&1 | ForEach-Object { 
    Write-Host $_ -ForegroundColor Gray
    Add-Content -Path $logFile -Value $_ -Encoding UTF8
    # 高亮显示关键信息
    if ($_ -match "Running Gradle|Building|Compiling|Linking|Generating|Downloading|Installing") {
        Write-Host $_ -ForegroundColor Cyan
    }
}

$androidTime = [math]::Round(((Get-Date) - $androidStart).TotalMinutes, 1)

if ($LASTEXITCODE -eq 0) {
    $apkDir = "build\app\outputs\flutter-apk"
    $apks = Get-ChildItem -Path $apkDir -Filter "*.apk" -ErrorAction SilentlyContinue
    if ($apks) {
        Write-BuildLog "Android 构建成功！" "Green"
        foreach ($apk in $apks) {
            Write-BuildLog "  文件: $($apk.Name)" "Green"
            Write-BuildLog "  大小: $([math]::Round($apk.Length/1MB, 2)) MB" "Green"
        }
        Write-BuildLog "  耗时: $androidTime 分钟" "Green"
    } else {
        Write-BuildLog "Android 构建完成但找不到输出文件" "Red"
        exit 1
    }
} else {
    Write-BuildLog "Android 构建失败！退出码: $LASTEXITCODE" "Red"
    exit 1
}

$totalTime = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
Write-BuildLog ""
Write-BuildLog "========================================" "Cyan"
Write-BuildLog "所有构建完成！" "Green"
Write-BuildLog "总耗时: $totalTime 分钟" "Green"
Write-BuildLog "========================================" "Cyan"
Write-BuildLog ""
Write-BuildLog "输出文件位置:" "Yellow"
Write-BuildLog "  Windows: build\windows\x64\runner\Release\PiliPlus.exe" "White"
Write-BuildLog "  Android: build\app\outputs\flutter-apk\*.apk" "White"
Write-BuildLog ""
Write-BuildLog "完整日志已保存到: $logFile" "Cyan"

