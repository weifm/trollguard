import Foundation
import IdentityLookup

/// 短信过滤扩展（必须继承 ILMessageFilterExtension）。
///
/// 判定规则（命中任一即归入「过滤信息」）：
/// 1. 发件人命中黑名单 / 分类号码库中的号码
/// 2. 发件人号码命中地区码 / 开头号码前缀（任意长度前缀均有效）
/// 3. 正文包含任一关键词
class MessageFilterHandler: ILMessageFilterExtension {

    override func handle(_ queryRequest: ILMessageFilterQueryRequest,
                         context: ILMessageFilterExtensionContext,
                         completion: @escaping (ILMessageFilterQueryResponse) -> Void) {

        let response = ILMessageFilterQueryResponse()

        guard RuleStore.blockingEnabled else {
            response.action = .allow
            completion(response)
            return
        }

        let sender = queryRequest.sender ?? ""
        let body   = queryRequest.messageBody ?? ""

        response.action = isSpam(sender: sender, body: body) ? .junk : .allow
        completion(response)
    }

    private func isSpam(sender: String, body: String) -> Bool {
        let digits = RuleStore.digitsOnly(sender)

        // 0) 境外短信（发件人以 + 开头且不是 +86）
        if RuleStore.blockForeignSMS {
            let trimmed = sender.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("+") && !trimmed.hasPrefix("+86") {
                return true
            }
        }

        // 1) 发件人命中号码库（黑名单 / 分类库）
        if !digits.isEmpty, RuleStore.allBlockNumbers.contains(digits) {
            return true
        }

        // 2) 发件人命中地区码 / 开头号码前缀（短信无枚举限制，任意长度有效）
        if !digits.isEmpty {
            for prefix in RuleStore.smsPrefixes where digits.hasPrefix(prefix) {
                return true
            }
        }

        // 3) 正文关键词
        if !body.isEmpty {
            for keyword in RuleStore.smsKeywords
            where body.localizedCaseInsensitiveContains(keyword) {
                return true
            }
        }

        return false
    }
}
