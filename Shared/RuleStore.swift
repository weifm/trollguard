import Foundation

/// 跨进程（主 App 与两个扩展）共享的拦截规则存储（App Group UserDefaults）。
enum RuleStore {
    static let appGroup = "group.com.troll.trollguard"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: - 存储键

    private static let kBlockEnabled   = "blockingEnabled"
    private static let kRegionCodes    = "blockedRegionCodes"    // 地区码（短信过滤用，来电需 ≥10 位）
    private static let kNumberPrefix   = "blockedNumberPrefixes" // 开头号码前缀
    private static let kSmsKeywords    = "smsKeywords"
    private static let kBlacklist      = "blacklistNumbers"      // 手动黑名单（完整号码）
    private static let kCatPrefix      = "category_"             // category_<key>_numbers / _enabled

    // MARK: - 骚扰电话分类（对应 MIUI 的分类拦截）

    static let categories: [(key: String, name: String)] = [
        ("harassment", "骚扰电话"),
        ("fraud",      "疑似诈骗"),
        ("risk",       "高风险电话"),
        ("ads",        "广告推销"),
        ("realestate", "房产中介"),
        ("insurance",  "保险理财"),
    ]

    // MARK: - 内置规则库（真实公开号段，短信层完全生效）

    struct BuiltinLibrary {
        let key: String
        let name: String
        let desc: String
        let prefixes: [String]
        let callEffective: Bool   // 是否对来电也有效（>=10 位前缀才可能）
    }

    static let builtinLibraries: [BuiltinLibrary] = [
        BuiltinLibrary(key: "port1069", name: "1069 营销短信端口",
                       desc: "1069 是商业营销短信主要通道，命中即过滤。注意：部分验证码也走 1069。",
                       prefixes: ["1069"], callEffective: false),
        BuiltinLibrary(key: "port106", name: "全部 106 短信端口",
                       desc: "覆盖所有 106 开头的短信端口（营销 / 通知 / 验证码）。过滤更彻底，但会误伤验证码短信。",
                       prefixes: ["106"], callEffective: false),
        BuiltinLibrary(key: "enterprise", name: "企业外呼 400 / 95 / 96",
                       desc: "400 企业号、95/96 特服号（银行、保险、催收外呼高发）。",
                       prefixes: ["400", "95", "96"], callEffective: false),
        BuiltinLibrary(key: "virtualisp", name: "虚拟运营商号段",
                       desc: "170/171/162/165/167/192 等移动转售号段（工信部公开分配），推销外呼高发。",
                       prefixes: ["170", "171", "162", "165", "167", "192"], callEffective: false),
        BuiltinLibrary(key: "intlprefix", name: "国际区号（境外短信）",
                       desc: "1/44/852/853/886/81/82/65/60/66/84/91 等国际区号，用于短信层拦截境外号码。",
                       prefixes: ["1", "44", "852", "853", "886", "81", "82", "65", "60", "66", "84", "91"],
                       callEffective: false),
    ]

    private static let kBuiltinKeys = "enabledBuiltinKeys"
    private static let kBlockForeignSMS = "blockForeignSMS"

    static var enabledBuiltinKeys: [String] {
        get { defaults.stringArray(forKey: kBuiltinKeys) ?? [] }
        set { defaults.set(newValue, forKey: kBuiltinKeys) }
    }

    static func setBuiltin(_ key: String, _ on: Bool) {
        var keys = enabledBuiltinKeys
        if on {
            if !keys.contains(key) { keys.append(key) }
        } else {
            keys.removeAll { $0 == key }
        }
        enabledBuiltinKeys = keys
    }

    static func isBuiltinEnabled(_ key: String) -> Bool {
        enabledBuiltinKeys.contains(key)
    }

    /// 内置库启用的前缀（仅用于短信层）
    static var builtinPrefixes: [String] {
        builtinLibraries.filter { isBuiltinEnabled($0.key) }.flatMap { $0.prefixes }
    }

    /// 拦截境外（非 +86）短信
    static var blockForeignSMS: Bool {
        get { defaults.object(forKey: kBlockForeignSMS) as? Bool ?? false }
        set { defaults.set(newValue, forKey: kBlockForeignSMS) }
    }

    // MARK: - 总开关

    static var blockingEnabled: Bool {
        get { defaults.object(forKey: kBlockEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: kBlockEnabled) }
    }

    // MARK: - 地区码 / 前缀

    static var regionCodes: [String] {
        get { defaults.stringArray(forKey: kRegionCodes) ?? [] }
        set { defaults.set(newValue.sorted(), forKey: kRegionCodes) }
    }

    static var numberPrefixes: [String] {
        get { defaults.stringArray(forKey: kNumberPrefix) ?? [] }
        set { defaults.set(newValue.sorted(), forKey: kNumberPrefix) }
    }

    /// 所有前缀（地区码 + 号码前缀，去重，仅数字）。
    static var allCallPrefixes: [String] {
        var set = Set<String>()
        for code in regionCodes { let d = digitsOnly(code); if !d.isEmpty { set.insert(d) } }
        for p in numberPrefixes { let d = digitsOnly(p);  if !d.isEmpty { set.insert(d) } }
        set.remove("")
        return Array(set).sorted()
    }

    /// 短信过滤用的前缀：任意长度都有效（扩展逐条比对发件人，无枚举问题）。
    /// 例如填地区码 86 → 拦截所有国内号码短信；填 1 → 拦所有以 1 开头的号码。
    /// 同时包含内置规则库启用的前缀。
    static var smsPrefixes: [String] {
        Array(Set(allCallPrefixes + builtinPrefixes)).sorted()
    }

    /// CallKit 来电黑名单可用的前缀：单前缀展开 ≤10 万个号码才有效（即 ≥10 位数字）。
    static var effectiveCallPrefixes: [String] {
        allCallPrefixes.filter { $0.count >= 10 }
    }

    // MARK: - 短信关键词

    static var smsKeywords: [String] {
        get { defaults.stringArray(forKey: kSmsKeywords) ?? [] }
        set { defaults.set(newValue.sorted(), forKey: kSmsKeywords) }
    }

    // MARK: - 手动黑名单（完整号码，CallKit 逐号拦截，天然可用）

    static var blacklistNumbers: [String] {
        get { defaults.stringArray(forKey: kBlacklist) ?? [] }
        set { defaults.set(Array(Set(newValue.map(digitsOnly))).filter { !$0.isEmpty }.sorted(), forKey: kBlacklist) }
    }

    // MARK: - 分类号码库

    static func categoryEnabled(_ key: String) -> Bool {
        defaults.object(forKey: kCatPrefix + key + "_enabled") as? Bool ?? false
    }

    static func setCategoryEnabled(_ key: String, _ on: Bool) {
        defaults.set(on, forKey: kCatPrefix + key + "_enabled")
    }

    static func categoryNumbers(_ key: String) -> [String] {
        defaults.stringArray(forKey: kCatPrefix + key + "_numbers") ?? []
    }

    static func setCategoryNumbers(_ key: String, _ raw: [String]) {
        let nums = Array(Set(raw.map(digitsOnly))).filter { !$0.isEmpty }.sorted()
        defaults.set(nums, forKey: kCatPrefix + key + "_numbers")
    }

    /// 合并所有启用中的号码来源（手动黑名单 + 启用的分类库），升序去重。
    /// CallKit 要求升序添加，这里直接返回升序结果。
    static var allBlockNumbers: [String] {
        var set = Set(blacklistNumbers)
        for (key, _) in categories where categoryEnabled(key) {
            set.formUnion(categoryNumbers(key))
        }
        return set.sorted()
    }

    /// 解析粘贴文本中的号码（换行 / 逗号 / 分号 / 空格分隔，自动去 +86、0086、横线等）。
    static func parseNumbers(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，;；\n\r \t")
        return text.components(separatedBy: separators)
            .map(digitsOnly)
            .filter { $0.count >= 5 } // 过滤误粘贴的短数字
    }

    // MARK: - 工具

    static func digitsOnly(_ s: String) -> String {
        var d = s.filter { $0.isNumber }
        while d.hasPrefix("00") { d.removeFirst(2) }
        if d.hasPrefix("86"), d.count > 11 { d.removeFirst(2) } // +86 手机号去掉国码
        return d
    }

    /// 规则指纹（供扩展增量重建使用）
    static var fingerprint: String {
        let nums = allBlockNumbers.joined(separator: ",")
        let pres = allCallPrefixes.joined(separator: ",")
        let kws  = smsKeywords.joined(separator: ",")
        let cats = categories.map { "\($0.key)=\(categoryEnabled($0.key) ? 1 : 0)" }.joined(separator: ";")
        return "\(blockingEnabled)-\(nums)-\(pres)-\(kws)-\(cats)"
    }
}
