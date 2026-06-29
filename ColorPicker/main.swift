import Cocoa
import ScreenCaptureKit

// MARK: - 参数

let gridCount = 15                       // 放大镜显示 15x15 个像素
let pixelScale: CGFloat = 8              // 每个像素放大成 8pt
let loupeSize = CGFloat(gridCount) * pixelScale   // 放大区边长 = 120（约原来的一半）
let labelHeight: CGFloat = 26            // 底部 HEX 文本条高度

func hexString(_ color: NSColor) -> String {
    let c = color.usingColorSpace(.sRGB) ?? color
    let r = Int(round(c.redComponent * 255))
    let g = Int(round(c.greenComponent * 255))
    let b = Int(round(c.blueComponent * 255))
    return String(format: "#%02X%02X%02X", r, g, b)
}

// 菜单栏小图标：透明底色轮 + 白色中心（与 App 图标同款，去掉深色方底，小尺寸更清爽）
func menuBarIcon() -> NSImage {
    let s: CGFloat = 18
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let cx = s / 2, cy = s / 2
        let outerR = s * 0.46, innerR = s * 0.27
        let segs = 180
        for i in 0..<segs {
            let a0 = CGFloat(i) / CGFloat(segs) * 2 * .pi
            let a1 = CGFloat(i + 1) / CGFloat(segs) * 2 * .pi + 0.02
            ctx.setFillColor(NSColor(calibratedHue: CGFloat(i) / CGFloat(segs),
                                     saturation: 0.95, brightness: 1, alpha: 1).cgColor)
            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: outerR, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: innerR, startAngle: a1, endAngle: a0, clockwise: true)
            ctx.closePath(); ctx.fillPath()
        }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
        let d = s * 0.14
        ctx.setFillColor(NSColor(calibratedWhite: 0.25, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
        return true
    }
    img.isTemplate = false   // 保留彩色（不做成单色模板）
    return img
}

// 主显示器在 Cocoa 坐标里的高度（用于把「左上原点」的全局坐标换成「左下原点」）
func primaryHeight() -> CGFloat {
    return NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
        ?? NSScreen.main?.frame.height ?? 1080
}

// 临时调试日志
let debugLogPath = "/tmp/qushe_debug.log"
func dbg(_ s: String) {
    let line = s + "\n"
    if let h = FileHandle(forWritingAtPath: debugLogPath) {
        h.seekToEndOfFile()
        if let d = line.data(using: .utf8) { h.write(d) }
        h.closeFile()
    } else {
        try? line.write(toFile: debugLogPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - 放大镜视图

final class LoupeView: NSView {
    var image: NSImage?
    var centerColor: NSColor = .black
    var hexText: String = "移动鼠标取色"

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        let ringW: CGFloat = 3

        // —— 圆形放大镜主体 ——
        let circleFrame = NSRect(x: ringW, y: labelHeight + ringW,
                                 width: loupeSize - ringW * 2,
                                 height: loupeSize - ringW * 2)
        let circle = NSBezierPath(ovalIn: circleFrame)

        // 深色底
        NSColor(white: 0.11, alpha: 0.98).setFill()
        circle.fill()

        // 圆内绘制：放大画面（最近邻，像素清晰）+ 细网格 + 中心格
        ctx.saveGraphicsState()
        circle.addClip()
        if let image = image {
            ctx.imageInterpolation = .none
            image.draw(in: circleFrame, from: .zero, operation: .copy, fraction: 1.0)
        }
        let step = circleFrame.width / CGFloat(gridCount)
        NSColor(white: 1, alpha: 0.07).setStroke()
        let grid = NSBezierPath()
        for i in 0...gridCount {
            let x = circleFrame.minX + CGFloat(i) * step
            grid.move(to: NSPoint(x: x, y: circleFrame.minY))
            grid.line(to: NSPoint(x: x, y: circleFrame.maxY))
            let y = circleFrame.minY + CGFloat(i) * step
            grid.move(to: NSPoint(x: circleFrame.minX, y: y))
            grid.line(to: NSPoint(x: circleFrame.maxX, y: y))
        }
        grid.lineWidth = 1
        grid.stroke()

        // 中心像素：黑描边 + 白描边双层，任何底色上都清晰可见
        let center = gridCount / 2
        let box = NSRect(x: circleFrame.minX + CGFloat(center) * step,
                         y: circleFrame.minY + CGFloat(center) * step,
                         width: step, height: step).insetBy(dx: -1.5, dy: -1.5)
        NSColor.black.withAlphaComponent(0.7).setStroke()
        let outerBox = NSBezierPath(rect: box); outerBox.lineWidth = 3; outerBox.stroke()
        NSColor.white.setStroke()
        let innerBox = NSBezierPath(rect: box); innerBox.lineWidth = 1.5; innerBox.stroke()
        ctx.restoreGraphicsState()

        // —— 外环：用当前取到的颜色描边（随取随变）+ 一道白色细环提亮 ——
        centerColor.setStroke()
        let ring = NSBezierPath(ovalIn: circleFrame.insetBy(dx: -ringW / 2, dy: -ringW / 2))
        ring.lineWidth = ringW
        ring.stroke()
        NSColor(white: 1, alpha: 0.85).setStroke()
        let innerRing = NSBezierPath(ovalIn: circleFrame.insetBy(dx: 0.5, dy: 0.5))
        innerRing.lineWidth = 1
        innerRing.stroke()

        // —— 底部 HEX 胶囊（按内容宽度居中）——
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        ]
        let str = NSAttributedString(string: hexText, attributes: attrs)
        let tSize = str.size()
        let dot: CGFloat = 11, padH: CGFloat = 9, gap: CGFloat = 6
        let chipH = labelHeight - 4
        let chipW = padH + dot + gap + tSize.width + padH
        let chip = NSRect(x: (loupeSize - chipW) / 2, y: 1, width: chipW, height: chipH)
        let chipPath = NSBezierPath(roundedRect: chip, xRadius: chipH / 2, yRadius: chipH / 2)
        NSColor(white: 0.11, alpha: 0.98).setFill()
        chipPath.fill()
        NSColor(white: 1, alpha: 0.15).setStroke()
        chipPath.lineWidth = 1
        chipPath.stroke()

        // 圆形小色块
        let sw = NSRect(x: chip.minX + padH, y: chip.midY - dot / 2, width: dot, height: dot)
        centerColor.setFill()
        NSBezierPath(ovalIn: sw).fill()
        NSColor(white: 1, alpha: 0.35).setStroke()
        let swRing = NSBezierPath(ovalIn: sw); swRing.lineWidth = 1; swRing.stroke()

        // HEX 文本
        str.draw(at: NSPoint(x: sw.maxX + gap, y: chip.midY - tSize.height / 2))
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var tap: CFMachPort?
    var loupeWindow: NSWindow!
    var loupeView: LoupeView!
    var timer: Timer?

    var lastColor: NSColor = .black
    var active = true
    var menuOpen = false    // 菜单栏下拉菜单是否展开（展开时藏起放大镜，别盖住菜单）
    var swallowUp = false   // 取色点击时，连带吞掉对应的鼠标抬起事件

    // ScreenCaptureKit 缓存
    var filter: SCContentFilter?
    var capturing = false
    var preparing = false
    var frameCount = 0
    var scale: CGFloat = 2.0
    var dispW = 0   // 主显示器宽（points）
    var dispH = 0   // 主显示器高（points）

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? "".write(toFile: debugLogPath, atomically: true, encoding: .utf8)
        dbg("LAUNCH preflightScreen=\(CGPreflightScreenCaptureAccess()) axTrusted=\(AXIsProcessTrusted())")
        setupStatusItem()
        requestPermissions()
        setupLoupeWindow()
        startTimer()          // 无条件启动：窗口始终跟随鼠标
        setupTap()
        Task { await prepareCapture() }
    }

    // MARK: 菜单栏

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuBarIcon()
        statusItem.button?.imagePosition = .imageLeft   // 取色后右侧显示 HEX

        let menu = NSMenu()
        let tip = NSMenuItem(title: "取色：⌘Command+点击 或 按 ⌃⌥C（都不会触发下面的按钮）", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        menu.addItem(tip)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "暂停 / 继续放大镜", action: #selector(toggleActive), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "打开「辅助功能」权限设置…", action: #selector(openAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开「屏幕录制」权限设置…", action: #selector(openScreenRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出取色器", action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self    // 菜单打开时隐藏放大镜，避免盖住菜单项
        statusItem.menu = menu
    }

    // MARK: 权限

    func requestPermissions() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: 放大镜窗口

    func setupLoupeWindow() {
        scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let rect = NSRect(x: 0, y: 0, width: loupeSize, height: loupeSize + labelHeight)
        let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .screenSaver
        w.ignoresMouseEvents = true
        w.hasShadow = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        loupeView = LoupeView(frame: rect)
        w.contentView = loupeView
        w.orderFrontRegardless()
        loupeWindow = w
    }

    func prepareCapture() async {
        // 只查询、不弹窗。没授权时绝不调用 SCK，避免反复触发系统权限弹窗
        guard CGPreflightScreenCaptureAccess() else { dbg("PREPARE skip: no screen permission"); return }
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { dbg("PREPARE: no display"); return }
            let f = SCContentFilter(display: display, excludingWindows: [])
            await MainActor.run {
                self.filter = f
                self.dispW = display.width
                self.dispH = display.height
                self.scale = NSScreen.main?.backingScaleFactor ?? 2.0
                dbg("PREPARE_OK dispW=\(display.width) dispH=\(display.height) scale=\(self.scale)")
            }
        } catch {
            dbg("PREPARE_ERR \(error)")
        }
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        guard active, !menuOpen else { return }
        guard let loc = CGEvent(source: nil)?.location else { return }

        // 始终跟随鼠标（不依赖是否有权限）
        let cocoaY = primaryHeight() - loc.y
        let mousePoint = NSPoint(x: loc.x, y: cocoaY)
        let scr = NSScreen.screens.first(where: { NSMouseInRect(mousePoint, $0.frame, false) }) ?? NSScreen.main
        positionWindow(mouseTopLeftX: loc.x, mouseCocoaY: cocoaY, screen: scr)

        // 还没拿到屏幕录制权限：显示提示并定时自动重试
        guard let filter = filter else {
            if loupeView.hexText != "需屏幕录制权限" {
                loupeView.hexText = "需屏幕录制权限"
                loupeView.image = nil
                loupeView.needsDisplay = true
            }
            retryPrepareIfNeeded()
            return
        }
        guard !capturing else { return }
        capturing = true

        // 只截鼠标周围的一小块，绝不截整屏！
        // 整屏 30fps 物理像素截图会瞬间打满 GPU/WindowServer，配合活动事件拦截会让整机卡死。
        let s = scale
        let regionPts: CGFloat = 40                   // 鼠标周围 40×40 点的小窗口，足够放大 15×15 像素
        var ox = loc.x - regionPts / 2
        var oy = loc.y - regionPts / 2
        ox = max(0, min(ox, CGFloat(dispW) - regionPts))
        oy = max(0, min(oy, CGFloat(dispH) - regionPts))
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = CGRect(x: ox, y: oy, width: regionPts, height: regionPts)  // 只采这一小块
        cfg.width = Int(regionPts * s)
        cfg.height = Int(regionPts * s)
        cfg.showsCursor = false
        let mx = loc.x, my = loc.y

        Task {
            do {
                let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                let half = gridCount / 2
                // 鼠标像素在这一小块截图里的位置（小块左上角对应 ox,oy）
                var x = Int((mx - ox) * s) - half
                var y = Int((my - oy) * s) - half
                x = max(0, min(x, full.width - gridCount))
                y = max(0, min(y, full.height - gridCount))
                if let crop = full.cropping(to: CGRect(x: x, y: y, width: gridCount, height: gridCount)) {
                    await MainActor.run { self.updateLoupe(with: crop) }
                } else {
                    dbg("CROP_NIL full=\(full.width)x\(full.height) x=\(x) y=\(y)")
                }
            } catch {
                dbg("CAP_ERR \(error)")
                await MainActor.run { self.filter = nil }   // 权限异常，退回重试
            }
            await MainActor.run { self.capturing = false }
        }
    }

    func retryPrepareIfNeeded() {
        if preparing { return }
        frameCount += 1
        if frameCount % 45 != 0 { return }   // 约每 1.5 秒重试一次
        preparing = true
        Task {
            await prepareCapture()
            await MainActor.run { self.preparing = false }
        }
    }

    func positionWindow(mouseTopLeftX x0: CGFloat, mouseCocoaY y0: CGFloat, screen: NSScreen?) {
        let wf = loupeWindow.frame
        let offset: CGFloat = 24
        var x = x0 + offset
        var y = y0 - offset - wf.height
        if let vf = screen?.visibleFrame {
            if x + wf.width > vf.maxX { x = x0 - offset - wf.width }
            if x < vf.minX { x = vf.minX + 4 }
            if y < vf.minY { y = y0 + offset }
            if y + wf.height > vf.maxY { y = vf.maxY - wf.height - 4 }
        }
        loupeWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func updateLoupe(with cg: CGImage) {
        loupeView.image = NSImage(cgImage: cg, size: NSSize(width: gridCount, height: gridCount))
        let rep = NSBitmapImageRep(cgImage: cg)
        if let c = rep.colorAt(x: gridCount / 2, y: gridCount / 2)?.usingColorSpace(.sRGB) {
            lastColor = c
            loupeView.centerColor = c
            loupeView.hexText = hexString(c)
        }
        loupeView.needsDisplay = true
        if frameCount < 5 { frameCount += 1; dbg("UPDATE img=\(cg.width)x\(cg.height) hex=\(loupeView.hexText)") }
    }

    // MARK: 取色

    func handleClick() {
        guard active else { return }
        let h = hexString(lastColor)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(h, forType: .string)
        statusItem.button?.title = h
        dbg("CLICK hex=\(h)")
    }

    // MARK: 菜单动作

    @objc func toggleActive() {
        active.toggle()
        if active {
            loupeWindow.orderFrontRegardless()
        } else {
            loupeWindow.orderOut(nil)
        }
    }

    @objc func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openScreenRecording() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 菜单开关时隐藏 / 恢复放大镜

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        loupeWindow.orderOut(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        if active { loupeWindow.orderFrontRegardless() }
    }
}

// MARK: - 全局点击回调（C 函数指针，靠 userInfo 取回 self）

let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()

    // tap 被系统超时禁用时重新启用
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = delegate.tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    // 方式一：Command + 左键点击。吞掉整个点击（按下 + 抬起），下面的控件收不到，不会被触发
    if type == .leftMouseDown, event.flags.contains(.maskCommand) {
        delegate.swallowUp = true
        DispatchQueue.main.async { delegate.handleClick() }
        return nil
    }
    if type == .leftMouseUp, delegate.swallowUp {
        delegate.swallowUp = false
        return nil
    }

    // 方式二：⌃⌥C 热键取色。完全不发送鼠标事件，绝不触发任何按钮
    if type == .keyDown {
        let kc = event.getIntegerValueField(.keyboardEventKeycode)
        if kc == 8, event.flags.contains(.maskControl), event.flags.contains(.maskAlternate) {
            DispatchQueue.main.async { delegate.handleClick() }
            return nil
        }
    }

    // 其余事件照常放行，不影响正常使用
    return Unmanaged.passUnretained(event)
}

extension AppDelegate {
    func setupTap() {
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
                 | (1 << CGEventType.leftMouseUp.rawValue)
                 | (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                        place: .headInsertEventTap,
                                        options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask),
                                        callback: tapCallback,
                                        userInfo: selfPtr) else {
            statusItem.button?.title = "⚠️"
            return
        }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }
}

// MARK: - 启动

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
