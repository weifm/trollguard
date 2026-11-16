import Foundation
import UIKit

/// 系统级「静音未知来电」控制。
///
/// iOS 的「静音未知来电」（设置 → 电话 → 静音未知来电）可一键静音所有
/// 不在通讯录的来电——涵盖未知号码、空号码、海外陌生号码，是 iOS 上
/// 最接近 MIUI「拦截陌生/未知/海外来电」的系统机制。
///
/// 巨魔环境（platform-application + 无沙盒）下本应用尝试直接写系统偏好，
/// 并回读验证；若系统版本键名不同导致写不进去，则自动回退为跳转系统设置页。
enum SettingsHelper {

    /// 尝试直接写系统偏好并验证。返回 (是否成功, 说明)。
    @discardableResult
    static func setSilenceUnknownCallers(_ on: Bool) -> (ok: Bool, message: String) {
        let domains = ["com.apple.mobilephone", "com.apple.callservices"]
        var reports: [String] = []

        for domain in domains {
            let key = "SilenceUnknownCallers" as CFString
            CFPreferencesSetAppValue(key, on as CFBoolean, domain as CFString)
            CFPreferencesAppSynchronize(domain as CFString)
            let readBack = CFPreferencesCopyAppValue(key, domain as CFString)
            let ok = (readBack as? Bool) == on
            reports.append("\(domain): \(ok ? "✓" : "✗")")
            if ok { return (true, "已开启系统偏好（\(domain)）") }
        }

        // 直写失败 → 引导手动开启
        return (false, "系统偏好直写未生效（\(reports.joined(separator: "，"))），请点「去系统设置」手动开启。")
    }

    /// 尝试跳转「电话」设置页（巨魔的 opensensitiveurl 权限允许深层链接）。
    static func openPhoneSettings() {
        let urls = ["App-prefs:root=Phone", "prefs:root=Phone"]
        for s in urls {
            if let url = URL(string: s), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        // 兜底：打开本 App 设置页，用户可从上一步进系统设置
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
