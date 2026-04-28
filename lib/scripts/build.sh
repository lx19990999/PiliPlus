#!/bin/bash

# 获取参数，默认为空
ARG="${1:-}"

# 错误处理函数
error_exit() {
    echo "Prebuild Error: $1" >&2
    exit 1
}

# 获取版本代码（git 提交数量）
VERSION_CODE=$(git rev-list --count HEAD 2>/dev/null)
if [ -z "$VERSION_CODE" ]; then
    error_exit "无法获取 git 提交数量"
fi
VERSION_CODE=$(echo "$VERSION_CODE" | tr -d '[:space:]')

# 获取提交哈希
COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$COMMIT_HASH" ]; then
    error_exit "无法获取 git 提交哈希"
fi
COMMIT_HASH=$(echo "$COMMIT_HASH" | tr -d '[:space:]')

# 从 pubspec.yaml 读取版本号
VERSION_LINE=$(grep '^version:' pubspec.yaml 2>/dev/null)
if [ -z "$VERSION_LINE" ]; then
    error_exit "在 pubspec.yaml 中未找到版本行"
fi

# 提取版本号（在 - 或 + 之前的部分，去除空格）
VERSION_NAME=$(echo "$VERSION_LINE" | cut -d: -f2 | cut -d- -f1 | cut -d+ -f1 | tr -d '[:space:]')
if [ -z "$VERSION_NAME" ]; then
    error_exit "在 pubspec.yaml 中未找到版本号"
fi

# 如果是 android 参数，在版本名后添加提交哈希的前9位
if [ "$ARG" = "android" ]; then
    VERSION_NAME="${VERSION_NAME}-${COMMIT_HASH:0:9}"
fi

# 更新 pubspec.yaml 中的版本行
if [ -f "pubspec.yaml" ]; then
    # 使用 sed 更新版本行
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 使用 -i '' 而不是 -i
        sed -i '' "s/^[[:space:]]*version:.*/version: ${VERSION_NAME}+${VERSION_CODE}/" pubspec.yaml
    else
        # Linux 使用 -i
        sed -i "s/^[[:space:]]*version:.*/version: ${VERSION_NAME}+${VERSION_CODE}/" pubspec.yaml
    fi
else
    error_exit "找不到 pubspec.yaml 文件"
fi

# 获取构建时间（Unix 时间戳）
BUILD_TIME=$(date +%s)

# 生成 pili_release.json
cat > pili_release.json <<EOF
{
  "pili.name": "${VERSION_NAME}",
  "pili.code": ${VERSION_CODE},
  "pili.hash": "${COMMIT_HASH}",
  "pili.time": ${BUILD_TIME}
}
EOF

# 只在 GitHub Actions 环境中设置环境变量
if [ -n "$GITHUB_ENV" ]; then
    echo "version=${VERSION_NAME}+${VERSION_CODE}" >> "$GITHUB_ENV"
fi

