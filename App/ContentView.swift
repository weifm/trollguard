import SwiftUI
import CallKit

struct ContentView: View {
    /// 主页面计数（onAppear 刷新）
    @State private var blacklistCount = 0
    @State private var prefixCount = 0
    @State private var regionPlaceCount = 0
    @State private var categoryCounts: [String: Int] = [:]
    @State private var keywordCount = 0

    @State private var blockingEnabled = RuleStore.blockingEnabled
    @State private var blockForeignSMS = RuleStore.blockForeignSMS
    @State private var silenceUnknown = false
    @State private var silenceMessage = ""
    @State private var reloadMessage = ""
    @State private var reloadOK: Bool?

    var body: some View {
        TabView {
            rulesPage.tabItem { Label("拦截规则", systemImage: "shield.lefthalf.filled") }
            lookupPage.tabItem { Label("归属地查询", systemImage: "magnifyingglass") }
            aboutPage.tabItem { Label("说明", systemImage: "info.circle") }
        }
        .accentColor(.red)
        .onAppear(perform: refreshCounts)
    }

    private func refreshCounts() {
        blockingEnabled = RuleStore.blockingEnabled
        blacklistCount = RuleStore.blacklistNumbers.count
        prefixCount = RuleStore.allCallPrefixes.count
        keywordCount = RuleStore.smsKeywords.count
        categoryCounts = Dictionary(uniqueKeysWithValues: RuleStore.categories.map {
            ($0.key, RuleStore.categoryNumbers($0.key).count)
        })
        regionPlaceCount = PhoneLocation.shared.cityPlacesCount
        blockForeignSMS = RuleStore.blockForeignSMS
    }

    private func builtinBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { RuleStore.isBuiltinEnabled(key) },
                set: { RuleStore.setBuiltin(key, $0) })
    }

    // MARK: - 拦截规则主页（对照 MIUI 骚扰拦截规则页）

    private var rulesPage: some View {
        NavigationView {
            List {
                Section("拦截规则") {
                    NavigationLink("拦截所有来电") {
                        NoteView(title: "拦截所有来电",
                                 text: "iOS 的 CallKit 黑名单必须逐个添加具体号码，无法枚举全部号码段，因此「拦截所有来电」无法像安卓那样一键实现。\n\n替代方案：开启系统「勿扰模式 / 专注模式」并选择仅允许收藏联系人来电，可实现同等效果。")
                    }
                    Toggle("拦截陌生号码来电", isOn: $silenceUnknown)
                        .onChange(of: silenceUnknown) { on in
                            let r = SettingsHelper.setSilenceUnknownCallers(on)
                            silenceMessage = on ? r.message : "已尝试关闭（若无效请手动到系统设置关闭）"
                        }
                    if !silenceMessage.isEmpty {
                        Text(silenceMessage).font(.footnote).foregroundColor(.secondary)
                    }
                    Button {
                        SettingsHelper.openPhoneSettings()
                    } label: {
                        Label("去系统设置开启（推荐首次使用）", systemImage: "gear")
                    }
                    NavigationLink("拦截未知号码与空号码来电") {
                        NoteView(title: "拦截未知号码与空号码来电",
                                 text: "系统「静音未知来电」已一并覆盖：所有不在通讯录里的号码（含无来电显示的空号）都会被静音。通讯录中的联系人不受影响，相当于自动白名单。")
                    }
                    NavigationLink("拦截海外来电") {
                        NoteView(title: "拦截海外来电",
                                 text: "「静音未知来电」会一并静音海外陌生号码（海外来电几乎不可能在你的通讯录里）。\n\n如需精确拦截海外号码，可在「按开头号码拦截」中添加国际区号（如 1、44、852 等）——注意：短信过滤对任意长度前缀都有效；来电拦截要求前缀 ≥10 位数字，短前缀仅对短信生效。")
                    }
                    NavigationLink("按归属地拦截（\(regionPlaceCount) 个归属地）") {
                        RegionBlockView()
                    }
                    NavigationLink("按开头号码拦截（\(prefixCount) 条）") {
                        PrefixBlockView()
                    }
                    NavigationLink("重复来电不拦截") {
                        NoteView(title: "重复来电不拦截",
                                 text: "iOS 系统无对应机制，无法实现。\n\n替代：iOS 15 的「静音未知来电」对陌生号码一律静音，重复来电也不会响铃，实际影响有限。")
                    }
                }

                Section("骚扰电话分类拦截") {
                    Text("每类可导入号码清单（网上号码库 / 标记平台导出的 CSV、粘贴文本均可），导入后点进分类开启开关即加入来电黑名单。")
                        .font(.footnote).foregroundColor(.secondary)
                    ForEach(RuleStore.categories, id: \.key) { cat in
                        NavigationLink("\(cat.name)（\(categoryCounts[cat.key] ?? 0) 个号码）") {
                            NumberLibraryView(mode: .category(key: cat.key, name: cat.name))
                        }
                    }
                }

                Section("内置规则库（作用于短信过滤）") {
                    ForEach(RuleStore.builtinLibraries, id: \.key) { lib in
                        Toggle(isOn: builtinBinding(lib.key)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lib.name)
                                Text(lib.desc).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    Toggle("拦截境外短信（非 +86 号码）", isOn: $blockForeignSMS)
                        .onChange(of: blockForeignSMS) { RuleStore.blockForeignSMS = $0 }
                    Text("上述规则基于公开号段分配（106 短信端口、400/95 企业号、虚拟运营商 170/171 等），对短信过滤完全生效。来电拦截受 CallKit 逐号限制，短号段无法生效。")
                        .font(.footnote).foregroundColor(.secondary)
                }

                Section("号码库源") {
                    NavigationLink("号码库订阅导入（URL 一键拉取）") {
                        SubscribeView()
                    }
                    Text("支持挂载任意公开号码库：纯文本 / CSV / JSON 自动识别，可按国家码过滤后导入分类库。")
                        .font(.footnote).foregroundColor(.secondary)
                }

                Section("名单管理") {
                    NavigationLink("黑名单（\(blacklistCount) 个号码）") {
                        NumberLibraryView(mode: .blacklist)
                    }
                    NavigationLink("白名单") {
                        NoteView(title: "白名单",
                                 text: "开启「拦截陌生号码来电」后，通讯录联系人自动放行，即白名单。\n\n如需放行特定号码：把它加进通讯录，或关闭对应分类开关。")
                    }
                }

                Section("短信拦截") {
                    NavigationLink("短信关键词（\(keywordCount) 条）") {
                        KeywordListView()
                    }
                    Text("发件人地区码 / 开头号码规则同样适用于短信过滤（任意长度前缀均有效，例如地区码 86 可匹配全部国内手机号短信）。命中后短信进入「过滤信息」。")
                        .font(.footnote).foregroundColor(.secondary)
                }

                Section("生效") {
                    Toggle("启用拦截", isOn: $blockingEnabled)
                        .onChange(of: blockingEnabled) { RuleStore.blockingEnabled = $0 }
                    Button {
                        reloadDatabase()
                    } label: {
                        Label("更新拦截数据库", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if let ok = reloadOK {
                        Text(reloadMessage).font(.footnote)
                            .foregroundColor(ok ? .green : .red)
                    }
                    Text("修改号码 / 前缀 / 分类库 / 关键词后，请点「更新拦截数据库」。")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("骚扰拦截")
            .onAppear(perform: refreshCounts)
        }
        .navigationViewStyle(.stack)
    }

    private func reloadDatabase() {
        CXCallDirectoryManager.sharedInstance.reloadExtension(
            withIdentifier: "com.troll.trollguard.calldirectory"
        ) { error in
            DispatchQueue.main.async {
                if let error = error {
                    reloadOK = false
                    reloadMessage = "更新失败：\(error.localizedDescription)\n请先在 设置 → 电话 → 来电阻止与身份识别 中启用本应用。"
                } else {
                    reloadOK = true
                    reloadMessage = "拦截数据库已更新 ✓（黑名单 \(RuleStore.allBlockNumbers.count) 条 + 有效前缀 \(RuleStore.effectiveCallPrefixes.count) 条）"
                }
            }
        }
    }

    // MARK: - 归属地查询

    private var lookupPage: some View {
        LookupView()
    }

    // MARK: - 说明

    private var aboutPage: some View {
        NoteView(title: "关于",
                 text: """
                 TrollGuard 巨魔版骚扰拦截（iPhone 6s Plus / iOS 15.8 适用）

                 功能对照：
                 • 黑名单 / 分类号码库 → CallKit 逐号拦截，完全可用
                 • 按开头号码拦截来电 → 前缀 ≥10 位可用（CallKit 限制）
                 • 按开头号码 / 地区拦截短信 → 任意前缀可用
                 • 拦截陌生 / 未知 / 海外来电 → 系统「静音未知来电」
                 • 按归属地拦截来电 → iOS 平台限制，仅提供归属地查询与号码库管理
                 • 拦截所有来电 / 重复来电不拦截 → iOS 无对应机制

                 通话自动录音请配合开源 TrollRecorder（GitHub: Lessica/TrollRecorder）。
                 微信 / QQ 语音通话录音需越狱注入，iOS 无法实现；替代：屏幕录制 + 扬声器。

                 归属地数据：ls0f/phone 号段库（约 50 万号段，离线内置）。
                 录音与拦截仅用于合法用途，录音前请告知对方。
                 """)
    }
}

// MARK: - 归属地查询页

struct LookupView: View {
    @State private var input = ""
    @State private var result: PhoneLocationInfo?
    @State private var notFound = false

    var body: some View {
        List {
            Section {
                TextField("输入手机号（前 7 位即可）", text: $input)
                    .keyboardType(.numberPad)
                Button("查询归属地") { query() }
                    .disabled(input.isEmpty)
            }
            if let info = result {
                Section("查询结果") {
                    row("号码", info.prefix + " 号段")
                    row("省份", info.province)
                    row("城市", info.city)
                    row("运营商", info.carrier)
                    row("区号", info.areaCode)
                    row("邮编", info.zipCode)
                }
            } else if notFound {
                Section {
                    Text("未查到该号段（可能是新号段或非手机号）。").foregroundColor(.secondary)
                }
            }
            Section("数据库") {
                let pl = PhoneLocation.shared
                if pl.isLoaded {
                    Text("内置号段库已加载：\(pl.totalSegments) 个号段，覆盖 \(pl.provinceCount) 个省份、\(pl.cityPlacesCount) 个省市。")
                        .font(.footnote).foregroundColor(.secondary)
                } else {
                    Text("号段库未加载（资源缺失）。").foregroundColor(.red)
                }
            }
        }
        .navigationTitle("归属地查询")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary) }
    }

    private func query() {
        result = PhoneLocation.shared.lookup(input)
        notFound = (result == nil)
    }
}

// MARK: - 通用说明页

struct NoteView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.title2).bold()
                Text(text).font(.body)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
