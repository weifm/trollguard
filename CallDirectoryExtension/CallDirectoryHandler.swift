import Foundation
import CallKit

/// CallKit 来电拦截扩展入口（必须继承 CXCallDirectoryProvider）。
///
/// 数据来源合并：
/// 1. 号码库条目：手动黑名单 + 启用的分类号码库（逐号拦截，完全精确）
/// 2. 有效前缀：≥10 位数字的前缀展开为号码区间（单前缀 ≤10 万号码）
/// 全部合并去重后按升序注入（CallKit 要求条目严格升序）。
class CallDirectoryHandler: CXCallDirectoryProvider {

    /// 单个前缀最多展开的号码数。
    static let maxEntriesPerPrefix = 100_000
    /// 全库条目总数上限（防止 reload 超时）。
    static let maxTotalEntries = 600_000

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        context.removeAllBlockingEntries()

        guard RuleStore.blockingEnabled else {
            context.completeRequest()
            return
        }

        var entries = Set<Int64>()

        // 1) 号码库（黑名单 + 启用的分类）
        for number in RuleStore.allBlockNumbers {
            guard number.count <= 15, let n = Int64(number) else { continue }
            entries.insert(n)
        }

        // 2) 有效前缀（≥10 位）展开为区间
        for prefix in RuleStore.effectiveCallPrefixes {
            guard prefix.count <= 15 else { continue }
            let zeroPad = 15 - prefix.count
            let startStr = prefix + String(repeating: "0", count: zeroPad)
            let endStr   = prefix + String(repeating: "9", count: zeroPad)
            guard let start = Int64(startStr), let end = Int64(endStr), start <= end else { continue }
            guard end - start + 1 <= Int64(Self.maxEntriesPerPrefix) else { continue }
            var n = start
            while n <= end {
                entries.insert(n)
                n += 1
            }
        }

        // 3) 升序注入（CallKit 要求）
        let sorted = entries.sorted()
        for n in sorted.prefix(Self.maxTotalEntries) {
            context.addBlockingEntry(withNextSequentialPhoneNumber: n)
        }

        context.completeRequest()
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        // 加载失败可在此记录
    }
}
