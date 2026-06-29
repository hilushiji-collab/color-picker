import Cocoa

// MARK: - 取某个屏幕坐标的颜色
// 用系统自带的 screencapture 截取 1pt 的小块到临时文件再读像素，兼容 macOS 15+
func colorAt(_ point: CGPoint) -> NSColor? {
    let tmp = NSTemporaryDirectory() + "qusheqi_pixel.png"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-R\(Int(point.x)),\(Int(point.y)),1,1", "-t", "png", tmp]
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return nil
    }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: tmp)),
          let rep = NSBitmapImageRep(data: data) else {
        return nil
    }
    return rep.colorAt(x: 0, y: 0)
}

// MARK: - NSColor -> #RRGGBB
func hex(_ color: NSColor) -> String {
    let c = color.usingColorSpace(.sRGB) ?? color
    let r = Int(round(c.redComponent * 255))
    let g = Int(round(c.greenComponent * 255))
    let b = Int(round(c.blueComponent * 255))
    return String(format: "#%02X%02X%02X", r, g, b)
}

func copyToClipboard(_ s: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
}

// MARK: - 权限检查（首次运行会弹窗请求）
var authorized = true

if !CGPreflightScreenCaptureAccess() {
    CGRequestScreenCaptureAccess()
    print("⚠️  需要「屏幕录制」权限来读取像素颜色，已弹出请求。")
    authorized = false
}

let axOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
if !AXIsProcessTrustedWithOptions(axOptions) {
    print("⚠️  需要「辅助功能」权限来监听鼠标点击，已弹出请求。")
    authorized = false
}

if !authorized {
    print("👉 请到「系统设置 > 隐私与安全性」里给你的终端 App 勾选上述权限，然后重新运行：")
    print("   swift colorpicker.swift")
    exit(0)
}

// MARK: - 监听全局左键点击
let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .leftMouseDown {
        let loc = event.location
        if let color = colorAt(loc) {
            let h = hex(color)
            copyToClipboard(h)
            print("\(h)   (x:\(Int(loc.x)) y:\(Int(loc.y)))   ✅ 已复制到剪贴板")
        }
    }
    return Unmanaged.passRetained(event)
}

let mask = (1 << CGEventType.leftMouseDown.rawValue)
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                  place: .headInsertEventTap,
                                  options: .listenOnly,
                                  eventsOfInterest: CGEventMask(mask),
                                  callback: callback,
                                  userInfo: nil) else {
    print("❌ 无法创建事件监听，请确认已授予「辅助功能」权限后重新运行。")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("🎨 取色器已启动！点击屏幕任意位置即可取色，按 Ctrl+C 退出。")
CFRunLoopRun()
