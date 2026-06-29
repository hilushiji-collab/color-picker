#!/bin/bash
set -e

# 构建并打包 ColorPicker（通用二进制：Apple 芯片 + Intel 都能跑）
# 一条龙：编译 → 签名 → 安装到「应用程序」 → 产出 build/ColorPicker.zip 和 build/ColorPicker.dmg
# 用法：bash build.sh

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ColorPicker"
SRC="$DIR/ColorPicker"
BUILD="$DIR/build"
APP="$BUILD/$APP_NAME.app"
SIGN_ID="Qusheqi Code Signing"   # 固定自签名证书（见 ColorPicker/.signing/README.txt）

echo "🔨 构建通用版 $APP_NAME ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 分别编译两种架构（部署目标 macOS 14，ScreenCaptureKit 截图 API 要求），再合并成通用二进制
echo "   编译 arm64 ..."
swiftc -O -target arm64-apple-macos14  "$SRC/main.swift" -o "$BUILD/.cp_arm64"
echo "   编译 x86_64 ..."
swiftc -O -target x86_64-apple-macos14 "$SRC/main.swift" -o "$BUILD/.cp_x86"
lipo -create "$BUILD/.cp_arm64" "$BUILD/.cp_x86" -output "$APP/Contents/MacOS/ColorPicker"
rm -f "$BUILD/.cp_arm64" "$BUILD/.cp_x86"

# 资源
cp "$SRC/Info.plist"   "$APP/Contents/Info.plist"
cp "$SRC/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# 用固定自签名证书签名（指纹稳定 → 改代码重编后系统授权依然有效，无需重新授权）
codesign --force --deep --sign "$SIGN_ID" "$APP"
echo "🧩 架构: $(lipo -info "$APP/Contents/MacOS/ColorPicker" | sed 's/.*are: //')"
codesign --verify "$APP" && echo "✅ 签名校验通过"
echo "📦 构建完成：$APP"

# 安装到「应用程序」
DEST="/Applications/$APP_NAME.app"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "✅ 已安装到：$DEST"

# 打包 zip（放进 build/，ditto 能正确保留 .app 结构）
cd "$BUILD"
rm -f "$APP_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip"
echo "✅ zip：$BUILD/$APP_NAME.zip （$(ls -lh "$APP_NAME.zip" | awk '{print $5}')）"

# 打包 dmg（放进 build/，拖拽安装：带「应用程序」软链）
echo "💿 制作 dmg ..."
STAGE="$(mktemp -d)/dmgroot"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$BUILD/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$BUILD/$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"
echo "✅ dmg：$BUILD/$APP_NAME.dmg （$(ls -lh "$BUILD/$APP_NAME.dmg" | awk '{print $5}')）"

echo "👉 分发到其他 Mac（需 macOS 14+）：dmg 拖入「应用程序」，或 zip 解压后右键「打开」绕过 Gatekeeper，再授权一次屏幕录制 + 辅助功能即可。"
