import Foundation
import ServiceManagement

/// macOS 13+ 统一登录项 API（替代老的 `SMLoginItemSetEnabled`）。
/// 以当前 `.app` 的身份注册/注销为登录项；注册后会被写入用户的
/// 系统设置 > 通用 > 登录项与扩展，用户也能在那里手动关掉。
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[MacosMonitor] LoginItem toggle failed: \(error.localizedDescription)")
        }
    }
}
