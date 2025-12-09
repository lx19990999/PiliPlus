#!/bin/bash
# Android 构建脚本 - 带实时日志输出（Linux 版本）

set -e  # 遇到错误立即退出

logFile="build_android.log"
startTime=$(date +%s)

# 清空日志文件
> "$logFile"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 日志函数
write_build_log() {
    local message="$1"
    local color="${2:-$WHITE}"
    local timestamp=$(date +%H:%M:%S)
    local logMessage="[$timestamp] $message"
    
    echo -e "${color}${logMessage}${NC}"
    echo "$logMessage" >> "$logFile"
}

# 计算时间差（分钟）
calculate_time() {
    local start=$1
    local end=$(date +%s)
    local diff=$((end - start))
    # 使用 bash 内置算术运算，避免依赖 bc 命令
    # 计算分钟和秒数
    local minutes=$((diff / 60))
    local seconds=$((diff % 60))
    # 计算小数部分（保留一位小数）：秒数 * 10 / 60，四舍五入
    local decimal=$(( (seconds * 10 + 30) / 60 ))
    # 如果小数部分达到 10，进位到分钟
    if [ "$decimal" -ge 10 ]; then
        minutes=$((minutes + 1))
        decimal=0
    fi
    printf "%d.%d" "$minutes" "$decimal"
}

write_build_log "========================================" "$CYAN"
write_build_log "开始构建 PiliPlus Android 客户端" "$CYAN"
write_build_log "开始时间: $(date '+%Y-%m-%d %H:%M:%S')" "$CYAN"
write_build_log "日志文件: $logFile" "$CYAN"
write_build_log "========================================" "$CYAN"
write_build_log ""

# 清理
write_build_log "[1/6] 检查系统内存..." "$YELLOW"
gradleMem="4G"
if command -v free &> /dev/null; then
    # 尝试多种方式获取内存信息
    # 方法1: 使用 free -m (GNU/Linux)
    totalMem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "")
    availableMem=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo "")
    
    # 如果方法1失败，尝试使用 free -m 的另一种格式
    if [ -z "$availableMem" ] || [ -z "$totalMem" ]; then
        # 某些系统可能使用不同的列
        totalMem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "")
        availableMem=$(free -m 2>/dev/null | awk '/^Mem:/{print ($7>0)?$7:$4}' || echo "")
    fi
    
    # 如果还是失败，尝试使用 /proc/meminfo
    if [ -z "$availableMem" ] && [ -f /proc/meminfo ]; then
        totalMem=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}' || echo "")
        availableMem=$(grep MemAvailable /proc/meminfo | awk '{print int($2/1024)}' || echo "")
        # 如果没有 MemAvailable，使用 MemFree
        if [ -z "$availableMem" ]; then
            availableMem=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}' || echo "")
        fi
    fi
    
    # 验证获取到的值是否为有效数字
    if [ -n "$totalMem" ] && [ -n "$availableMem" ] && [ "$totalMem" -gt 0 ] 2>/dev/null && [ "$availableMem" -gt 0 ] 2>/dev/null; then
        write_build_log "  总内存: ${totalMem} MB" "$GRAY"
        write_build_log "  可用内存: ${availableMem} MB" "$GRAY"
        # 根据可用内存自动调整 Gradle 内存配置
        if [ "$availableMem" -lt 4096 ]; then
            gradleMem="2G"
            write_build_log "  可用内存不足 4GB，将 Gradle 内存调整为 2GB" "$YELLOW"
        elif [ "$availableMem" -lt 6144 ]; then
            gradleMem="3G"
            write_build_log "  可用内存不足 6GB，将 Gradle 内存调整为 3GB" "$YELLOW"
        elif [ "$availableMem" -lt 16384 ]; then
            gradleMem="4G"
            write_build_log "  可用内存充足，使用配置 4GB" "$GREEN"
        elif [ "$availableMem" -lt 24576 ]; then
            gradleMem="6G"
            write_build_log "  可用内存充足（16GB+），将 Gradle 内存调整为 6GB" "$GREEN"
        else
            gradleMem="8G"
            write_build_log "  可用内存非常充足（24GB+），将 Gradle 内存调整为 8GB" "$GREEN"
        fi
    else
        write_build_log "  无法检测内存信息，使用默认配置 4GB" "$YELLOW"
    fi
    
    # 更新 gradle.properties 中的内存配置
    if [ -f "android/gradle.properties" ]; then
        # 备份原文件
        cp "android/gradle.properties" "android/gradle.properties.bak" 2>/dev/null || true
        # 更新内存配置（兼容 GNU sed 和 BSD sed）
        if sed --version >/dev/null 2>&1; then
            # GNU sed
            sed -i "s/-Xmx[0-9]*[GM]/-Xmx${gradleMem}/g" "android/gradle.properties"
        else
            # BSD sed (macOS)
            sed -i '' "s/-Xmx[0-9]*[GM]/-Xmx${gradleMem}/g" "android/gradle.properties"
        fi
        write_build_log "  已更新 Gradle 内存配置为 ${gradleMem}" "$GREEN"
    fi
else
    write_build_log "  未找到 free 命令，使用默认配置 4GB" "$YELLOW"
fi
write_build_log ""

write_build_log "[2/6] 停止 Gradle daemon 并清理缓存..." "$YELLOW"
# 方法1: 使用 gradlew --stop
if [ -f "android/gradlew" ]; then
    cd android
    ./gradlew --stop 2>&1 | tee -a "../$logFile" || true
    cd ..
    write_build_log "已执行 gradlew --stop" "$GREEN"
fi
# 方法2: 等待并检查残留进程
sleep 3
# 检查并强制停止所有 Gradle 相关进程
if command -v pgrep &> /dev/null; then
    # 查找所有 Gradle daemon 进程
    gradlePids=$(pgrep -f "gradle.*daemon" 2>/dev/null || true)
    if [ -n "$gradlePids" ]; then
        write_build_log "检测到残留的 Gradle 进程，强制停止..." "$YELLOW"
        echo "$gradlePids" | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
    # 也检查 Java 进程（可能是卡住的 Gradle）
    javaGradlePids=$(pgrep -f "java.*gradle" 2>/dev/null || true)
    if [ -n "$javaGradlePids" ]; then
        write_build_log "检测到残留的 Java Gradle 进程，强制停止..." "$YELLOW"
        echo "$javaGradlePids" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
fi

# 清理 Gradle 缓存（解决 FileAccessTimeJournal 错误）
write_build_log "清理 Gradle 缓存..." "$YELLOW"
# 清理项目内的 Gradle 缓存
if [ -d "android/.gradle" ]; then
    rm -rf "android/.gradle" 2>/dev/null || true
    write_build_log "  已清理 android/.gradle" "$GREEN"
fi
if [ -d "android/build" ]; then
    rm -rf "android/build" 2>/dev/null || true
    write_build_log "  已清理 android/build" "$GREEN"
fi

# 检测是否在 WSL 环境中
isWSL=false
if [ -f /proc/version ] && grep -qi microsoft /proc/version; then
    isWSL=true
    write_build_log "  检测到 WSL 环境" "$YELLOW"
fi

# 清理用户主目录的 Gradle 缓存（更彻底的清理）
if [ -n "$HOME" ] && [ -d "$HOME/.gradle" ]; then
    write_build_log "  检测到用户 Gradle 目录: $HOME/.gradle" "$GRAY"
    
    # 清理可能损坏的 journal 和 lock 文件
    if [ -d "$HOME/.gradle/caches" ]; then
        find "$HOME/.gradle/caches" -name "*journal*" -type f -delete 2>/dev/null || true
        find "$HOME/.gradle/caches" -name "*.lock" -type f -delete 2>/dev/null || true
        write_build_log "  已清理损坏的 journal 和 lock 文件" "$GREEN"
    fi
    
    # 清理 Gradle daemon 目录（完全删除）
    if [ -d "$HOME/.gradle/daemon" ]; then
        write_build_log "  清理 Gradle daemon 目录..." "$GRAY"
        rm -rf "$HOME/.gradle/daemon" 2>/dev/null || true
        write_build_log "  已清理 Gradle daemon 目录" "$GREEN"
    fi
    
    # 在 WSL 环境中，清理整个 vfs 目录（文件监控系统）
    if [ "$isWSL" = true ] && [ -d "$HOME/.gradle/vfs" ]; then
        write_build_log "  WSL 环境：清理 Gradle VFS 目录..." "$YELLOW"
        rm -rf "$HOME/.gradle/vfs" 2>/dev/null || true
        write_build_log "  已清理 Gradle VFS 目录" "$GREEN"
    fi
    
    # 如果问题仍然存在，可以尝试清理整个 caches 目录（更彻底但会重新下载）
    # 注释掉以避免每次都重新下载，只在需要时手动启用
    # if [ -d "$HOME/.gradle/caches" ]; then
    #     write_build_log "  彻底清理 Gradle caches 目录..." "$YELLOW"
    #     rm -rf "$HOME/.gradle/caches" 2>/dev/null || true
    #     write_build_log "  已清理 Gradle caches 目录（将重新下载依赖）" "$GREEN"
    # fi
fi

# 在 WSL 环境中，禁用 Gradle 文件监控功能
if [ "$isWSL" = true ]; then
    write_build_log "  WSL 环境：配置 Gradle 禁用文件监控..." "$YELLOW"
    if [ -f "android/gradle.properties" ]; then
        # 检查是否已存在相关配置
        if ! grep -q "org.gradle.vfs.watch" "android/gradle.properties"; then
            echo "" >> "android/gradle.properties"
            echo "# 在 WSL 环境中禁用文件监控以避免 FileAccessTimeJournal 错误" >> "android/gradle.properties"
            echo "org.gradle.vfs.watch=false" >> "android/gradle.properties"
            write_build_log "  已在 gradle.properties 中禁用文件监控" "$GREEN"
        else
            write_build_log "  文件监控配置已存在" "$GRAY"
        fi
    fi
fi

write_build_log "Gradle daemon 和缓存清理完成" "$GREEN"
write_build_log ""

write_build_log "[3/6] 清理之前的构建..." "$YELLOW"
flutter clean 2>&1 | while IFS= read -r line; do
    echo "$line" | tee -a "$logFile"
done || true
write_build_log "清理完成" "$GREEN"
write_build_log ""

# 获取依赖
write_build_log "[4/6] 获取 Flutter 依赖..." "$YELLOW"
if flutter pub get 2>&1 | tee -a "$logFile"; then
    write_build_log "依赖获取完成" "$GREEN"
else
    write_build_log "获取依赖失败！退出码: $?" "$RED"
    exit 1
fi

# 修复 flutter_native_splash 插件注册问题
write_build_log "修复插件注册文件..." "$YELLOW"
PLUGIN_REGISTRANT="android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
if [ -f "$PLUGIN_REGISTRANT" ]; then
    # 检查并修复孤立的 try { 语句（没有对应的 catch，且与 flutter_native_splash 相关）
    # 模式1: try { 后面直接是注释，且注释包含 flutter_native_splash
    if grep -A2 "^[[:space:]]*try[[:space:]]*{[[:space:]]*$" "$PLUGIN_REGISTRANT" | grep -q "flutter_native_splash"; then
        write_build_log "  检测到孤立的 try { 语句，正在修复..." "$YELLOW"
        # 使用 awk 进行更可靠的修复
        awk '
        /^[[:space:]]*try[[:space:]]*{[[:space:]]*$/ {
            getline next_line
            if (next_line ~ /flutter_native_splash/) {
                # 移除 try {，保留注释
                print "    // flutter_native_splash is a dev-time tool and does not need runtime registration"
                print "    // try {"
                print "    //   flutterEngine.getPlugins().add(new net.jonhanson.flutter_native_splash.FlutterNativeSplashPlugin());"
                print "    // } catch (Exception e) {"
                print "    //   Log.e(TAG, \"Error registering plugin flutter_native_splash, net.jonhanson.flutter_native_splash.FlutterNativeSplashPlugin\", e);"
                print "    // }"
                # 跳过后续的注释行，直到找到下一个 try 或正常代码
                while ((getline line) > 0) {
                    if (line ~ /^[[:space:]]*try[[:space:]]*{/) {
                        print line
                        break
                    } else if (line ~ /^[[:space:]]*\/\/.*flutter_native_splash/ || line ~ /^[[:space:]]*\/\/.*catch/ || line ~ /^[[:space:]]*\/\/.*Log\.e/) {
                        # 跳过这些注释行
                        continue
                    } else if (line ~ /^[[:space:]]*\/\/[[:space:]]*}[[:space:]]*$/) {
                        # 跳过注释的结束大括号
                        continue
                    } else {
                        print line
                        break
                    }
                }
                next
            } else {
                print
                print next_line
            }
            next
        }
        { print }
        ' "$PLUGIN_REGISTRANT" > "$PLUGIN_REGISTRANT.tmp" && mv "$PLUGIN_REGISTRANT.tmp" "$PLUGIN_REGISTRANT"
        write_build_log "  已修复孤立的 try { 语句" "$GREEN"
    fi
    
    # 检查是否有未注释的 flutter_native_splash 插件注册
    if grep -q "flutterEngine.getPlugins().add(new net.jonhanson.flutter_native_splash.FlutterNativeSplashPlugin());" "$PLUGIN_REGISTRANT" && ! grep -q "// flutterEngine.getPlugins().add(new net.jonhanson.flutter_native_splash.FlutterNativeSplashPlugin());" "$PLUGIN_REGISTRANT"; then
        write_build_log "  检测到未注释的 flutter_native_splash 插件注册，正在修复..." "$YELLOW"
        if sed --version >/dev/null 2>&1; then
            # GNU sed: 注释掉整个 try-catch 块
            sed -i '/net.jonhanson.flutter_native_splash.FlutterNativeSplashPlugin/,/^[[:space:]]*}[[:space:]]*$/ {
                s/^\([[:space:]]*\)try {$/\1\/\/ flutter_native_splash is a dev-time tool and does not need runtime registration\n\1\/\/ try {/
                s/^\([[:space:]]*\)\(flutterEngine\.getPlugins()\)/\1\/\/   \2/
                s/^\([[:space:]]*\)} catch/\1\/\/ } catch/
                s/^\([[:space:]]*\)\(Log\.e\)/\1\/\/   \2/
                s/^\([[:space:]]*\)}$/\1\/\/ }/
            }' "$PLUGIN_REGISTRANT"
        else
            # BSD sed (macOS)
            sed -i '' '/net.jonhanson.flutter_native_splash.FlutterNativeSplashPlugin/,/^[[:space:]]*}[[:space:]]*$/ {
                s/^\([[:space:]]*\)try {$/\1\/\/ flutter_native_splash is a dev-time tool and does not need runtime registration\n\1\/\/ try {/
                s/^\([[:space:]]*\)\(flutterEngine\.getPlugins()\)/\1\/\/   \2/
                s/^\([[:space:]]*\)} catch/\1\/\/ } catch/
                s/^\([[:space:]]*\)\(Log\.e\)/\1\/\/   \2/
                s/^\([[:space:]]*\)}$/\1\/\/ }/
            }' "$PLUGIN_REGISTRANT"
        fi
        write_build_log "  已修复 flutter_native_splash 插件注册" "$GREEN"
    fi
    
    # 最终检查：确保没有孤立的 try { 语句
    if grep -q "^[[:space:]]*try[[:space:]]*{[[:space:]]*$" "$PLUGIN_REGISTRANT"; then
        # 检查每个 try { 后面是否有对应的 catch
        if ! awk '/^[[:space:]]*try[[:space:]]*{[[:space:]]*$/{found_try=1; next} found_try && /^[[:space:]]*} catch/{found_try=0; next} found_try && /^[[:space:]]*try/{exit 1}' "$PLUGIN_REGISTRANT"; then
            write_build_log "  警告: 检测到可能的语法问题，但已尝试修复" "$YELLOW"
        fi
    fi
    
    if ! grep -q "// flutter_native_splash is a dev-time tool" "$PLUGIN_REGISTRANT"; then
        write_build_log "  插件注册文件检查完成" "$GRAY"
    fi
else
    write_build_log "  插件注册文件不存在，将在构建时生成" "$GRAY"
fi
write_build_log ""

# 设置 Android 版本
write_build_log "[5/6] 设置 Android 版本信息..." "$YELLOW"
if [ -f "lib/scripts/build.sh" ]; then
    if bash lib/scripts/build.sh android 2>&1 | tee -a "$logFile"; then
        if [ -f "pili_release.json" ]; then
            write_build_log "版本信息设置完成" "$GREEN"
        else
            write_build_log "版本信息设置失败：找不到 pili_release.json" "$RED"
            exit 1
        fi
    else
        write_build_log "版本信息设置失败，退出码: $?" "$RED"
        exit 1
    fi
else
    write_build_log "警告: 未找到版本设置脚本 (lib/scripts/build.sh)，跳过版本设置" "$YELLOW"
fi
write_build_log ""

# 构建 Android
write_build_log "[6/6] 构建 Android 客户端..." "$YELLOW"
write_build_log "开始时间: $(date +%H:%M:%S)" "$GRAY"
androidStart=$(date +%s)

# 构建并实时显示输出，同时保存到日志
# 使用 --no-pub 避免重复解析依赖（已在第4步完成）
set +e  # 暂时关闭错误退出，以便捕获退出码
flutter build apk --release --split-per-abi --no-pub 2>&1 | tee -a "$logFile" | while IFS= read -r line; do
    echo "$line"
    # 高亮显示关键信息
    if echo "$line" | grep -qE "Running Gradle|Building|Compiling|Linking|Generating|Downloading|Installing"; then
        echo -e "${CYAN}${line}${NC}" >&2
    fi
done
buildExitCode=${PIPESTATUS[0]}
set -e  # 重新开启错误退出

if [ $buildExitCode -eq 0 ]; then
    androidTime=$(calculate_time $androidStart)
    
    apkDir="build/app/outputs/flutter-apk"
    if [ -d "$apkDir" ]; then
        apks=$(find "$apkDir" -name "*.apk" 2>/dev/null)
        if [ -n "$apks" ]; then
            write_build_log "Android 构建成功！" "$GREEN"
            echo "$apks" | while read -r apk; do
                apkName=$(basename "$apk")
                apkSize=$(du -h "$apk" | cut -f1)
                write_build_log "  文件: $apkName" "$GREEN"
                write_build_log "  大小: $apkSize" "$GREEN"
            done
            write_build_log "  耗时: ${androidTime} 分钟" "$GREEN"
        else
            write_build_log "Android 构建完成但找不到输出文件" "$RED"
            exit 1
        fi
    else
        write_build_log "Android 构建完成但找不到输出目录" "$RED"
        exit 1
    fi
else
    write_build_log "Android 构建失败！退出码: $buildExitCode" "$RED"
    exit 1
fi

totalTime=$(calculate_time $startTime)
write_build_log ""
write_build_log "========================================" "$CYAN"
write_build_log "Android 构建完成！" "$GREEN"
write_build_log "总耗时: ${totalTime} 分钟" "$GREEN"
write_build_log "========================================" "$CYAN"
write_build_log ""
write_build_log "输出文件位置:" "$YELLOW"
write_build_log "  Android: build/app/outputs/flutter-apk/*.apk" "$WHITE"
write_build_log ""
write_build_log "完整日志已保存到: $logFile" "$CYAN"
