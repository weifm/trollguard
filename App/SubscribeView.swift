import SwiftUI

/// 号码库源订阅：从任意公开号码库 URL 拉取并导入到分类号码库。
///
/// 支持格式（自动识别）：
/// • 纯文本：每行一个号码，如 +8613800138000 / 13800138000
/// • CSV：自动从每行里挑出最像手机号的那一段
/// • JSON：["13800138000", ...] / [{ "number": "+8613800138000" }, ...] / { "numbers": [...] }
struct SubscribeView: View {
    @State private var urlText = "https://malwareworld.com/data/suspiciousPhones.txt"
    @State private var categoryKey = "ads"
    @State private var onlyChina = true
    @State private var chinaCode = "86"
    @State private var loading = false
    @State private var message = ""
    @State private var lastCount = 0

    private let presets: [(name: String, url: String, note: String)] = [
        ("MalwareWorld 全球垃圾电话库（约 9 万条，含各洲）",
         "https://malwareworld.com/data/suspiciousPhones.txt",
         "纯文本每行一个 E.164 号码。中国号码极少，建议关闭「仅保留中国」。"),
        ("OpenCallShield 协作库",
         "https://raw.githubusercontent.com/jhonsu01/OpenCallShield/main/spam_numbers.json",
         "JSON，含 reports 与 tag 字段。"),
        ("CallShield 号码库",
         "https://raw.githubusercontent.com/SysAdminDoc/CallShield/master/data/spam_numbers_approved.json",
         "JSON，整理过的号码列表。"),
    ]

    var body: some View {
        List {
            Section {
                Text("中文骚扰号码库没有公开可下载的官方源（12321 不开放导出、运营商库不公开）。这里提供订阅机制：把任何公开库的 URL 填进来即可一键导入，格式自动识别。国内号码建议自己从标记平台导出 CSV 后走「粘贴导入」。")
                    .font(.footnote).foregroundColor(.secondary)
            }

            Section("号码库地址") {
                TextField("https://…", text: $urlText)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Picker("导入到分类", selection: $categoryKey) {
                    ForEach(RuleStore.categories, id: \.key) { cat in
                        Text(cat.name).tag(cat.key)
                    }
                }
                Toggle("仅保留指定国家码号码", isOn: $onlyChina)
                if onlyChina {
                    HStack {
                        Text("国家码")
                        TextField("86", text: $chinaCode).keyboardType(.numberPad).frame(width: 60)
                    }
                }
            }

            Section("推荐源") {
                ForEach(presets, id: \.url) { p in
                    Button {
                        urlText = p.url
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name).font(.subheadline).foregroundColor(.primary)
                            Text(p.note).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("导入") {
                Button {
                    download()
                } label: {
                    HStack {
                        Label("下载并导入", systemImage: "arrow.down.circle")
                        if loading { Spacer(); ProgressView() }
                    }
                }
                .disabled(loading || urlText.isEmpty)
                if !message.isEmpty {
                    Text(message).font(.footnote)
                        .foregroundColor(lastCount > 0 ? .green : .secondary)
                }
            }
        }
        .navigationTitle("号码库订阅")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 下载与解析

    private func download() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            message = "URL 格式不正确"
            return
        }
        loading = true
        message = ""
        lastCount = 0

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                loading = false
                if let error = error {
                    message = "下载失败：\(error.localizedDescription)"
                    return
                }
                guard let data = data, !data.isEmpty else {
                    message = "下载内容为空"
                    return
                }
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                let numbers = Self.extractNumbers(from: text,
                                                  countryCode: onlyChina ? RuleStore.digitsOnly(chinaCode) : nil)
                guard !numbers.isEmpty else {
                    message = "未解析到符合条件的号码（若为境外库，请关闭「仅保留指定国家码」）"
                    return
                }
                let existing = RuleStore.categoryNumbers(categoryKey)
                let merged = Array(Set(existing).union(numbers)).sorted()
                RuleStore.setCategoryNumbers(categoryKey, merged)
                lastCount = merged.count - existing.count
                let name = RuleStore.categories.first { $0.key == categoryKey }?.name ?? categoryKey
                message = "成功解析 \(numbers.count) 个号码，新增 \(lastCount) 个到「\(name)」，当前共 \(merged.count) 个。记得到主页面点「更新拦截数据库」。"
            }
        }.resume()
    }

    /// 从任意文本中抽取号码。countryCode 非空时只保留该国家码的号码并去掉国家码。
    static func extractNumbers(from text: String, countryCode: String?) -> [String] {
        var candidates: [String] = []

        // 1) 先试 JSON
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            candidates += flattenJSON(obj)
        }

        // 2) 文本/CSV 逐行挑数字段
        if candidates.isEmpty {
            for line in text.components(separatedBy: .newlines) {
                let fields = line.components(separatedBy: CharacterSet(charactersIn: ",;\t\" "))
                for f in fields {
                    let d = f.filter { $0.isNumber || $0 == "+" }
                    if d.filter({ $0.isNumber }).count >= 7 { candidates.append(d) }
                }
            }
        }

        var result = Set<String>()
        for raw in candidates {
            var d = raw.filter { $0.isNumber }
            if let cc = countryCode, !cc.isEmpty {
                if d.hasPrefix(cc) {
                    d.removeFirst(cc.count)
                } else {
                    continue
                }
            } else {
                // 未指定国家码：去掉常见国际码前缀
                while d.hasPrefix("00") { d.removeFirst(2) }
                if d.hasPrefix("86"), d.count > 11 { d.removeFirst(2) }
            }
            if d.count >= 5 && d.count <= 15 { result.insert(d) }
        }
        return Array(result)
    }

    /// 递归展平 JSON，收集所有像号码的字符串
    private static func flattenJSON(_ obj: Any) -> [String] {
        var out: [String] = []
        func walk(_ v: Any) {
            if let s = v as? String {
                if s.filter({ $0.isNumber }).count >= 7 { out.append(s) }
            } else if let arr = v as? [Any] {
                arr.forEach(walk)
            } else if let dict = v as? [String: Any] {
                for (k, val) in dict {
                    let kl = k.lowercased()
                    if kl.contains("number") || kl.contains("phone") || kl.contains("num") || kl.contains("tel") {
                        walk(val)
                    } else if val is [Any] || val is [String: Any] {
                        walk(val)
                    }
                }
            }
        }
        walk(obj)
        return out
    }
}
