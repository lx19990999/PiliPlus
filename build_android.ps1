# Android 构建脚本 - 带实时日志输出
$ErrorActionPreference = "Continue"

$logFile = "build_android.log"
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
Write-BuildLog "开始构建 PiliPlus Android 客户端" "Cyan"
Write-BuildLog "开始时间: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Cyan"
Write-BuildLog "日志文件: $logFile" "Cyan"
Write-BuildLog "========================================" "Cyan"
Write-BuildLog ""

# 在脚本开始时立即清除所有代理环境变量，确保 Gradle 不会使用代理
Write-BuildLog "清除代理环境变量..." "Gray"
$proxyVars = @("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "NO_PROXY", "no_proxy")
foreach ($var in $proxyVars) {
    if (Get-Variable -Name "env:$var" -ErrorAction SilentlyContinue) {
        Remove-Item "Env:$var" -ErrorAction SilentlyContinue
        Write-BuildLog "  已清除: $var" "Gray"
    }
}

# 清除并重建 GRADLE_OPTS、JAVA_OPTS、JAVA_TOOL_OPTIONS，移除所有代理相关选项
if ($env:GRADLE_OPTS) { 
    $gradleOpts = $env:GRADLE_OPTS -replace '-Dhttp\.proxyHost=[^\s]+', '' -replace '-Dhttp\.proxyPort=[^\s]+', '' -replace '-Dhttps\.proxyHost=[^\s]+', '' -replace '-Dhttps\.proxyPort=[^\s]+', '' -replace '-Dhttp\.nonProxyHosts=[^\s]+', ''
    $gradleOpts = $gradleOpts -replace '\s+', ' ' -replace '^\s+|\s+$', ''
    if ([string]::IsNullOrWhiteSpace($gradleOpts)) { 
        Remove-Item Env:\GRADLE_OPTS -ErrorAction SilentlyContinue
    } else {
        $env:GRADLE_OPTS = $gradleOpts
    }
}

if ($env:JAVA_OPTS) { 
    $javaOpts = $env:JAVA_OPTS -replace '-Dhttp\.proxyHost=[^\s]+', '' -replace '-Dhttp\.proxyPort=[^\s]+', '' -replace '-Dhttps\.proxyHost=[^\s]+', '' -replace '-Dhttps\.proxyPort=[^\s]+', '' -replace '-Dhttp\.nonProxyHosts=[^\s]+', ''
    $javaOpts = $javaOpts -replace '\s+', ' ' -replace '^\s+|\s+$', ''
    if ([string]::IsNullOrWhiteSpace($javaOpts)) { 
        Remove-Item Env:\JAVA_OPTS -ErrorAction SilentlyContinue
    } else {
        $env:JAVA_OPTS = $javaOpts
    }
}

if ($env:JAVA_TOOL_OPTIONS) { 
    # 保留 file.encoding 等非代理选项
    $javaToolOpts = $env:JAVA_TOOL_OPTIONS -replace '-Dhttp\.proxyHost=[^\s]+', '' -replace '-Dhttp\.proxyPort=[^\s]+', '' -replace '-Dhttps\.proxyHost=[^\s]+', '' -replace '-Dhttps\.proxyPort=[^\s]+', '' -replace '-Dhttp\.nonProxyHosts=[^\s]+', ''
    $javaToolOpts = $javaToolOpts -replace '\s+', ' ' -replace '^\s+|\s+$', ''
    $env:JAVA_TOOL_OPTIONS = $javaToolOpts
}

# 显式设置不使用代理的系统属性
$env:GRADLE_OPTS = if ($env:GRADLE_OPTS) { "$env:GRADLE_OPTS -Dhttp.proxyHost= -Dhttp.proxyPort= -Dhttps.proxyHost= -Dhttps.proxyPort=" } else { "-Dhttp.proxyHost= -Dhttp.proxyPort= -Dhttps.proxyHost= -Dhttps.proxyPort=" }
$env:JAVA_OPTS = if ($env:JAVA_OPTS) { "$env:JAVA_OPTS -Dhttp.proxyHost= -Dhttp.proxyPort= -Dhttps.proxyHost= -Dhttps.proxyPort=" } else { "-Dhttp.proxyHost= -Dhttp.proxyPort= -Dhttps.proxyHost= -Dhttps.proxyPort=" }

Write-BuildLog "代理环境变量已清除" "Green"
Write-BuildLog ""

# 停止 Gradle daemon，确保使用新的环境变量配置
Write-BuildLog "[1/5] 停止 Gradle daemon..." "Yellow"
Push-Location android
try {
    if (Test-Path "gradlew.bat") {
        .\gradlew.bat --stop 2>&1 | Out-Null
    } elseif (Test-Path "gradlew") {
        .\gradlew --stop 2>&1 | Out-Null
    }
    Write-BuildLog "Gradle daemon 已停止" "Green"
} catch {
    Write-BuildLog "停止 Gradle daemon 时出错（可忽略）" "Gray"
} finally {
    Pop-Location
}
Write-BuildLog ""

# 清理
Write-BuildLog "[2/5] 清理之前的构建..." "Yellow"
flutter clean 2>&1 | ForEach-Object { 
    Write-Host $_ -ForegroundColor Gray
    Add-Content -Path $logFile -Value $_ -Encoding UTF8
}
Write-BuildLog "清理完成" "Green"
Write-BuildLog ""

# 获取依赖
Write-BuildLog "[3/5] 获取 Flutter 依赖..." "Yellow"
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

# 设置 Android 版本
Write-BuildLog "[4/5] 设置 Android 版本信息..." "Yellow"
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
Write-BuildLog "[5/5] 构建 Android 客户端..." "Yellow"
Write-BuildLog "开始时间: $(Get-Date -Format 'HH:mm:ss')" "Gray"

$androidStart = Get-Date
$retryCount = 0
$buildSuccess = $false

while (-not $buildSuccess) {
    if ($retryCount -gt 0) {
        Write-BuildLog "" "White"
        Write-BuildLog "========================================" "Yellow"
        Write-BuildLog "检测到下载失败，开始第 $retryCount 次重试..." "Yellow"
        Write-BuildLog "重试时间: $(Get-Date -Format 'HH:mm:ss')" "Yellow"
        Write-BuildLog "========================================" "Yellow"
        Write-BuildLog "" "White"
        
        # 等待一段时间再重试，避免立即重试
        Start-Sleep -Seconds 1
    }
    
    $buildOutput = @()
    $hasDownloadError = $false
    
    flutter build apk --release --split-per-abi 2>&1 | ForEach-Object { 
        $buildOutput += $_
        Write-Host $_ -ForegroundColor Gray
        Add-Content -Path $logFile -Value $_ -Encoding UTF8
        
        # 检测下载相关错误
        if ($_ -match "Connection refused|Downloading file from|Failed to download|java\.net\.|IOException|SocketException|ConnectException") {
            $hasDownloadError = $true
        }
        
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
            if ($retryCount -gt 0) {
                Write-BuildLog "  经过 $retryCount 次重试后成功" "Green"
            }
            foreach ($apk in $apks) {
                Write-BuildLog "  文件: $($apk.Name)" "Green"
                Write-BuildLog "  大小: $([math]::Round($apk.Length/1MB, 2)) MB" "Green"
            }
            Write-BuildLog "  耗时: $androidTime 分钟" "Green"
            $buildSuccess = $true
        } else {
            Write-BuildLog "Android 构建完成但找不到输出文件" "Red"
            exit 1
        }
    } else {
        # 检查是否是下载错误
        if ($hasDownloadError) {
            $retryCount++
            Write-BuildLog "检测到下载失败（退出码: $LASTEXITCODE），将自动重试..." "Yellow"
            Write-BuildLog "当前重试次数: $retryCount" "Yellow"
            # 继续循环重试
        } else {
            # 非下载错误，直接退出
            Write-BuildLog "Android 构建失败！退出码: $LASTEXITCODE" "Red"
            Write-BuildLog "错误类型: 非下载错误，不进行重试" "Red"
            exit 1
        }
    }
}

$totalTime = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
Write-BuildLog ""
Write-BuildLog "========================================" "Cyan"
Write-BuildLog "Android 构建完成！" "Green"
Write-BuildLog "总耗时: $totalTime 分钟" "Green"
Write-BuildLog "========================================" "Cyan"
Write-BuildLog ""
Write-BuildLog "输出文件位置:" "Yellow"
Write-BuildLog "  Android: build\app\outputs\flutter-apk\*.apk" "White"
Write-BuildLog ""
Write-BuildLog "完整日志已保存到: $logFile" "Cyan"

