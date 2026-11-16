import SwiftUI

// MARK: - 按开头号码拦截（地区码 + 号码前缀）

struct PrefixBlockView: View {
    @State private var newRegion = ""
    @State private var newPrefix = ""

    var body: some View {
        List {
            Section {
                Text("规则说明：地区码与号码前缀同时用于「短信过滤」（任意长度有效）和「来电拦截」（前缀 ≥10 位数字才有效——CallKit 黑名单必须逐号添加，短前缀对应的号码数超过 10 万无法枚举）。")
                    .font(.footnote).foregroundColor(.secondary)
            }

            Section("地区码（国家 / 地区）") {
                HStack {
                    TextField("如 86、852、1", text: $newRegion)
                        .keyboardType(.numberPad)
                    Button("添加") { add(&RuleStore.regionCodes, newRegion); newRegion = "" }
                        .disabled(newRegion.isEmpty)
                }
                ForEach(RuleStore.regionCodes, id: \.self) { code in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("+\(code)")
                        caption(for: code)
                    }
                }
                .onDelete { RuleStore.regionCodes = RuleStore.regionCodes.removed(at: $0) }
            }

            Section("开头号码") {
                HStack {
                    TextField("如 170、9527、400", text: $newPrefix)
                        .keyboardType(.numbersAndPunctuation)
                    Button("添加") { add(&RuleStore.numberPrefixes, newPrefix); newPrefix = "" }
                        .disabled(newPrefix.isEmpty)
                }
                ForEach(RuleStore.numberPrefixes, id: \.self) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(p) 开头")
                        caption(for: p)
                    }
                }
                .onDelete { RuleStore.numberPrefixes = RuleStore.numberPrefixes.removed(at: $0) }
            }
        }
        .navigationTitle("按开头号码拦截")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add(_ list: inout [String], _ raw: String) {
        let d = RuleStore.digitsOnly(raw)
        guard !d.isEmpty, !list.contains(d) else { return }
        list.append(d)
        list.sort()
    }

    @ViewBuilder
    private func caption(for prefix: String) -> some View {
        let digits = RuleStore.digitsOnly(prefix)
        let count = digits.isEmpty || digits.count > 15
            ? Int.max
            : Int(pow(10.0, Double(15 - digits.count)))
        if count <= 100_000 {
            Text("来电 + 短信均生效（约拦截 \(count) 个号码）")
                .font(.caption2).foregroundColor(.secondary)
        } else {
            Text("⚠️ 仅短信生效：来电拦截需前缀 ≥10 位（该前缀对应 \(count > 100_000_000 ? "10 亿+" : "\(count)") 个号码，CallKit 无法枚举）")
                .font(.caption2).foregroundColor(.orange)
        }
    }
}

extension Array where Element == String {
    func removed(at offsets: IndexSet) -> [String] {
        var copy = self
        copy.remove(atOffsets: offsets)
        return copy
    }
}

// MARK: - 按归属地拦截

struct RegionBlockView: View {
    private let pl = PhoneLocation.shared

    var body: some View {
        List {
            Section("内置归属地号码库") {
                if pl.isLoaded {
                    Text("已加载 \(pl.totalSegments) 个号段，覆盖 \(pl.provinceCount) 个省份、\(pl.cityPlacesCount) 个省市归属地（离线查询，无需网络）。")
                        .font(.footnote)
                } else {
                    Text("号段库未加载。").foregroundColor(.red)
                }
            }

            Section("为什么 iOS 上不能像安卓那样按省份一键拦截") {
                Text("MIUI 可以按归属地拦截，是因为安卓系统把来电事件交给系统进程逐条判断。iOS 的 CallKit 黑名单只能逐个添加具体号码：拦截「北京」全部号码需要添加上百亿条，物理上不可行。这是苹果平台级限制，与巨魔权限无关。")
                    .font(.footnote).foregroundColor(.secondary)
                Text("iOS 上的等效做法：① 开启「拦截陌生号码来电」（归属地外的陌生号基本全被静音）；② 把骚扰高发号码导入分类号码库逐号拦截；③ 短信不受此限制——在「按开头号码拦截」里加地区码即可按地区拦短信。")
                    .font(.footnote).foregroundColor(.secondary)
            }

            Section("各归属地号段数量") {
                let list = pl.provincesByCount()
                if list.isEmpty {
                    Text("无数据").foregroundColor(.secondary)
                }
                ForEach(list, id: \.name) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text("\(item.count) 个号段")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("按归属地拦截")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 号码库编辑（黑名单 / 分类库）

struct NumberLibraryView: View {
    enum Mode {
        case blacklist
        case category(key: String, name: String)
    }

    let mode: Mode

    @State private var enabled = false
    @State private var pasteText = ""
    @State private var numbers: [String] = []
    @State private var importMessage = ""
    @State private var confirmClear = false

    private var title: String {
        switch mode {
        case .blacklist: return "黑名单"
        case .category(_, let name): return name
        }
    }

    var body: some View {
        List {
            if case .category(let key, _) = mode {
                Section("启用") {
                    Toggle("启用该分类拦截", isOn: $enabled)
                        .onChange(of: enabled) { RuleStore.setCategoryEnabled(key, $0) }
                }
            }

            Section {
                TextEditor(text: $pasteText)
                    .frame(minHeight: 120)
                    .font(.system(.footnote, design: .monospaced))
                Button("导入粘贴的号码") { importNumbers() }
                    .disabled(pasteText.isEmpty)
                Button("从剪贴板导入") { pasteText = UIPasteboard.general.string ?? ""; importNumbers() }
                if !importMessage.isEmpty {
                    Text(importMessage).font(.footnote).foregroundColor(.green)
                }
                Text("支持批量粘贴：换行 / 逗号 / 空格分隔均可，自动去 +86、0086、横线。来源示例：网上公开的骚扰号码库 CSV、运营商标记导出、Excel 复制一列。")
                    .font(.footnote).foregroundColor(.secondary)
            }

            Section("已存号码（\(numbers.count)）") {
                if numbers.isEmpty {
                    Text("暂无号码").foregroundColor(.secondary)
                }
                ForEach(numbers, id: \.self) { n in
                    Text(n).font(.system(.footnote, design: .monospaced))
                }
                .onDelete { delete(offsets: $0) }
                Button("清空全部", role: .destructive) { confirmClear = true }
                    .disabled(numbers.isEmpty)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .alert("确认清空全部 \(numbers.count) 个号码？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                numbers = []
                save()
            }
        }
    }

    private func load() {
        switch mode {
        case .blacklist:
            numbers = RuleStore.blacklistNumbers
        case .category(let key, _):
            numbers = RuleStore.categoryNumbers(key)
            enabled = RuleStore.categoryEnabled(key)
        }
    }

    private func save() {
        switch mode {
        case .blacklist:
            RuleStore.blacklistNumbers = numbers
        case .category(let key, _):
            RuleStore.setCategoryNumbers(key, numbers)
        }
    }

    private func importNumbers() {
        let parsed = RuleStore.parseNumbers(from: pasteText)
        let before = numbers.count
        numbers = Array(Set(numbers).union(parsed)).sorted()
        save()
        importMessage = "本次识别 \(parsed.count) 个号码，新增 \(numbers.count - before) 个。"
        pasteText = ""
    }

    private func delete(offsets: IndexSet) {
        numbers.remove(atOffsets: offsets)
        save()
    }
}

// MARK: - 短信关键词

struct KeywordListView: View {
    @State private var newKeyword = ""

    var body: some View {
        List {
            Section("命中即归入「过滤信息」") {
                HStack {
                    TextField("如 贷款、退保、刷单", text: $newKeyword)
                    Button("添加") {
                        let k = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty else { return }
                        var list = RuleStore.smsKeywords
                        if !list.contains(k) { list.append(k); RuleStore.smsKeywords = list }
                        newKeyword = ""
                    }
                    .disabled(newKeyword.isEmpty)
                }
                ForEach(RuleStore.smsKeywords, id: \.self) { k in
                    Text(k)
                }
                .onDelete { RuleStore.smsKeywords = RuleStore.smsKeywords.removed(at: $0) }
            }
        }
        .navigationTitle("短信关键词")
        .navigationBarTitleDisplayMode(.inline)
    }
}
