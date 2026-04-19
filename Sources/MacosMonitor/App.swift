import AppKit

@main
enum MacosMonitorApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory = 不显示 Dock 图标，只在菜单栏出现
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()   // ⌘C / ⌘V / ⌘X / ⌘A 等标准编辑快捷键（菜单栏 App 没默认 menu bar，得手动挂）
        controller = StatusBarController()
    }

    /// LSUIElement App 的 `NSApp.mainMenu` 默认是空的，导致 TextField 不响应 ⌘V 等快捷键。
    /// 把标准 Edit 菜单挂上去，即便菜单栏不显示，keyboard equivalents 也会被系统注册并转发。
    private func installEditMenu() {
        let main = NSMenu()

        // App 菜单（必须有，否则 system 不会 bootstrap 菜单链）
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu().with {
            $0.addItem(NSMenuItem(title: "Quit MacosMonitor",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q"))
        }
        main.addItem(appItem)

        // Edit 菜单
        let editItem = NSMenuItem()
        editItem.submenu = NSMenu(title: "Edit").with {
            $0.addItem(NSMenuItem(title: "Cut",    action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
            $0.addItem(NSMenuItem(title: "Copy",   action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
            $0.addItem(NSMenuItem(title: "Paste",  action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
            $0.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
            $0.addItem(.separator())
            $0.addItem(NSMenuItem(title: "Undo",   action: Selector(("undo:")),             keyEquivalent: "z"))
            $0.addItem(NSMenuItem(title: "Redo",   action: Selector(("redo:")),             keyEquivalent: "Z"))
        }
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}

private extension NSMenu {
    func with(_ configure: (NSMenu) -> Void) -> NSMenu { configure(self); return self }
}
