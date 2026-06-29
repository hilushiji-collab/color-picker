# 取色器 ColorPicker

一个常驻 macOS 菜单栏的屏幕取色工具。鼠标移到哪，圆形放大镜就跟到哪，实时显示放大像素与中心点的 HEX 颜色值；一键取色并复制到剪贴板。

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-Cocoa%20%2B%20ScreenCaptureKit-orange)

## 功能特性

- **跟随鼠标的圆形放大镜**：放大 15×15 个像素，最近邻插值，像素清晰可数；外环用当前颜色实时描边。
- **实时 HEX 显示**：放大镜底部胶囊条显示中心像素的 `#RRGGBB` 与色块。
- **两种取色方式**（都不会误触屏幕上的按钮）：
  - `⌘ Command + 左键点击` —— 吞掉整个点击，下层控件收不到。
  - `⌃ Control + ⌥ Option + C` 热键 —— 完全不发送鼠标事件。
- **自动复制剪贴板**：取色后 HEX 值写入剪贴板，并显示在菜单栏图标右侧。
- **菜单栏常驻**：`LSUIElement` 后台运行，不占 Dock。
- **性能友好**：只截取鼠标周围 40×40 点的小块（而非整屏），避免打满 GPU / WindowServer。

## 系统要求

- macOS 14.0 及以上（依赖 ScreenCaptureKit 截图 API）
- 支持 Apple 芯片与 Intel（分发版为通用二进制）

## 权限

首次运行会请求两项权限，需在「系统设置 > 隐私与安全性」中授予：

| 权限 | 用途 |
| --- | --- |
| **屏幕录制** | 读取屏幕像素颜色 |
| **辅助功能** | 监听全局鼠标点击 / 热键 |

菜单里提供了「打开权限设置…」的快捷入口。授权后重新运行即可。

## 使用方法

启动「取色器」后：

1. 移动鼠标，放大镜会自动跟随并显示放大画面与 HEX。
2. 按住 `⌘` 点击目标位置，或按 `⌃⌥C`，即可取色并复制到剪贴板。
3. 菜单栏图标右侧会显示刚取到的颜色值。

### 菜单项

- **暂停 / 继续放大镜**（`p`）
- **打开「辅助功能」权限设置…**
- **打开「屏幕录制」权限设置…**
- **退出取色器**（`q`）

## 构建与打包

一条命令搞定（编译通用二进制 → 签名 → 安装到「应用程序」 → 产出分发包）：

```bash
bash build.sh
```

分别编译 arm64 / x86_64 再用 `lipo` 合并成通用二进制，产物统一放在 `build/`：

- `build/ColorPicker.app`（已安装到 `/Applications`）
- `build/ColorPicker.zip`
- `build/ColorPicker.dmg`（带「应用程序」软链，拖拽即装）

使用固定的自签名证书 `Qusheqi Code Signing`（见 `ColorPicker/.signing/`）。固定指纹的好处是：改代码重编后，系统已授予的权限依然有效，无需重新授权。

> 在另一台 Mac 上首次运行：dmg 拖入「应用程序」，或 zip 解压后右键「打开」绕过 Gatekeeper，再授权一次屏幕录制 + 辅助功能即可。

## 项目结构

```
colorPicker/
├── ColorPicker/
│   ├── main.swift          # 主程序（菜单栏 App + 放大镜 + 取色）
│   ├── Info.plist          # Bundle 配置（LSUIElement、最低系统版本等）
│   ├── AppIcon.icns        # 应用图标
│   └── .signing/           # 自签名证书与配置
├── build.sh                # 一条龙：构建通用版 + 签名 + 安装 + 打包 zip/dmg
├── colorpicker.swift       # 早期命令行版（screencapture 取单像素，可 swift 直接运行）
└── build/                  # 构建产物（ColorPicker.app / .zip / .dmg）
```

> `colorpicker.swift` 是早期的命令行原型：用系统 `screencapture` 截 1pt 像素取色，监听全局点击后打印并复制 HEX。可直接 `swift colorpicker.swift` 运行，无需打包。

## 实现要点

- 用 **ScreenCaptureKit** 的 `SCScreenshotManager.captureImage` 截取鼠标周围小块，30fps 刷新。
- 坐标换算：全局事件坐标是「左上原点」，Cocoa 窗口是「左下原点」，按主屏高度翻转。
- 放大镜窗口 `level = .screenSaver`、`ignoresMouseEvents`、可跨 Space，始终浮于最上层。
- 全局点击 / 热键通过 `CGEvent.tapCreate` 事件 tap 捕获；菜单展开时隐藏放大镜，避免盖住菜单项。
