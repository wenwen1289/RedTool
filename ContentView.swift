import SwiftUI
import PhotosUI
import UserNotifications

struct ContentView: View {
    @State private var whitelistRaw: String = {
        if let saved = UserDefaults.standard.string(forKey: "whitelist_raw"), !saved.isEmpty {
            return saved
        }
        let shared = AppGroup.loadWhitelistRaw()
        return shared.isEmpty ? "[\"彩云滚滚lai:wmn525545100:600\"]" : shared
    }()
    @AppStorage("show_over") private var showOver: Bool = true

    @State private var results: [MatchResult] = []
    @State private var analyzing = false
    @State private var statusText = "两种方式：选截图识别，或开启实时识别（通知提醒）"
    @State private var pickedItem: PhotosPickerItem?
    @State private var liveTimer: Timer?
    @State private var logs: [AppLog.Entry] = []

    /// Broadcast 扩展的 Bundle ID（按你的工程实际填写）
    private let broadcastExtensionBundleID =
        Bundle.main.bundleIdentifier! + ".BroadcastExtension"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("白名单（自动保存）") {
                        TextEditor(text: Binding(
                            get: { whitelistRaw },
                            set: { whitelistRaw = $0; AppGroup.saveWhitelist($0)
                                AppGroup.copyWhitelistToPasteboard($0) }))
                            .frame(minHeight: 80)
                            .font(.system(size: 13))
                    }

                    if !AppGroup.groupAvailable {
                        Text("⚠️ 检测到 App Group 权限缺失（免费签名常见）。"
                            + "实时识别将通过【系统剪贴板】传递白名单，"
                            + "命中结果以【通知】形式提醒；"
                            + "App 内实时表格/日志将不显示，请使用截图识别查看结果。")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }

                    // ===== 实时识别（屏幕广播 + 通知提醒） =====
                    GroupBox("实时识别（推荐）") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                BroadcastPickerButton(
                                    preferredExtensionBundleID: broadcastExtensionBundleID)
                                    .frame(width: 44, height: 44)
                                Text("点击图标 → 选「RedTool」→ 开始广播\n在小红书滚动，命中白名单会发通知")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Button("允许通知提醒") {
                                requestNotificationAuth()
                            }
                            .font(.footnote)
                        }
                    }

                    // ===== 截图识别 =====
                    GroupBox("截图识别") {
                        HStack {
                            PhotosPicker(selection: $pickedItem, matching: .images) {
                                Label("选择截图", systemImage: "photo.on.rectangle")
                            }
                            if analyzing { ProgressView().padding(.leading, 6) }
                        }
                    }

                    Text(statusText).font(.footnote).foregroundStyle(.secondary)

                    if !results.isEmpty { resultTables }

                    // ===== 实时日志面板（与安卓版一致，5 分钟自动清理） =====
                    logPanel
                }
                .padding()
            }
            .navigationTitle("红薯tool")
            .onAppear {
                // 每秒从 App Group 读扩展写入的实时结果与日志
                liveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    if AppGroup.groupAvailable {
                        let live = AppGroup.loadMatches()
                        if !live.isEmpty { results = live }
                    }
                    logs = AppLog.load()
                }
                // 白名单写入剪贴板（免费签名时扩展的兜底来源）
                AppGroup.copyWhitelistToPasteboard(whitelistRaw)
                AppLog.append("I", "App 已打开，白名单已写入剪贴板兜底通道")
            }
            .onDisappear { liveTimer?.invalidate() }
            .onChange(of: pickedItem) { newItem in
                guard let item = newItem else { return }
                analyze(item: item)
            }
        }
    }

    /// 达标 / 阈值外 两个表格（达标标题绿色，格式与 Android 版一致）
    private var resultTables: some View {
        let below = results.filter { !$0.overThreshold }
        let over = results.filter { $0.overThreshold }
        let showOverSection = showOver && !over.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            Text("达标 \(below.count) · 阈值外 \(over.count)")
                .font(.subheadline).bold()

            Text("达标（点赞数<阈值）")
                .font(.caption).bold().foregroundColor(.green)
            ForEach(below) { m in rowView(m) }
            if below.isEmpty {
                Text("无达标匹配").font(.caption).foregroundStyle(.secondary)
            }

            if showOverSection {
                Text("阈值外（点赞数≥阈值）共 \(over.count) 条")
                    .font(.caption).bold().foregroundColor(.orange)
                ForEach(over) { m in rowView(m) }
            }

            Toggle("显示阈值外结果（点赞数≥阈值的白名单匹配）", isOn: $showOver)
                .font(.footnote)
        }
    }

    /// 日志面板：实时显示扩展识别过程，5 分钟自动清理
    private var logPanel: some View {
        GroupBox("运行日志（5分钟自动清理）共 \(logs.count) 条") {
            VStack(spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if logs.isEmpty {
                                Text(AppGroup.groupAvailable
                                    ? "暂无日志。开始广播后这里会实时显示识别过程。"
                                    : "App Group 权限缺失（免费签名）：扩展日志无法传回本面板，"
                                    + "实时识别改走剪贴板通道，命中结果以通知提醒。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(logs) { entry in
                                Text(logLine(entry))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(color(for: entry.level))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: 180)
                    .onChange(of: logs) { _ in
                        if let last = logs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                Button("清空日志") {
                    AppLog.clear()
                    logs = []
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func color(for level: String) -> Color {
        switch level {
        case "E": return .red
        case "W": return .orange
        default: return .primary
        }
    }

    /// 单条匹配记录（格式与 Android 版一致）
    private func rowView(_ m: MatchResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(m.displayName) \(m.likeCount)赞（\(m.overThreshold ? "超阈值" : "未超阈值")）")
                .font(.callout).bold()
            Text("白名单: \(m.entry.name) · id: \(m.entry.id) · 阈值: \(m.entry.threshold)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    /// 日志行文本（拆开表达式，避免类型检查超时）
    private func logLine(_ entry: AppLog.Entry) -> String {
        Self.fmt.string(from: entry.ts) + " " + entry.level + "/" + entry.msg
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func requestNotificationAuth() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    AppLog.append("E", "通知权限申请失败: \(error.localizedDescription)")
                } else {
                    AppLog.append("I", "通知权限: \(granted ? "已授权" : "被拒绝(请到 设置-通知 开启)")")
                }
            }
        }
    }

    private func analyze(item: PhotosPickerItem) {
        analyzing = true
        statusText = "识别中…"
        item.loadTransferable(type: Data.self) { result in
            DispatchQueue.main.async {
                defer { analyzing = false }
                switch result {
                case .success(let data?):
                    guard let img = UIImage(data: data) else {
                        statusText = "截图读取失败"; return
                    }
                    let list = WhitelistStore.parse(whitelistRaw)
                    guard !list.isEmpty else {
                        statusText = "白名单为空或格式错误"; return
                    }
                    let matched = ScreenshotAnalyzer.analyze(image: img, whitelist: list)
                    results = matched
                    statusText = matched.isEmpty
                        ? "截图内未识别到匹配内容"
                        : "识别完成：达标 \(matched.filter { !$0.overThreshold }.count) 条，阈值外 \(matched.filter { $0.overThreshold }.count) 条"
                    AppLog.append("I", "截图识别完成: 命中 \(matched.count) 条")
                case .failure(let err):
                    statusText = "读取失败: \(err.localizedDescription)"
                default:
                    statusText = "未获取到图片"
                }
            }
        }
    }
}
