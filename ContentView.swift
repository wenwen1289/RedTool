import SwiftUI
import PhotosUI
import UserNotifications

struct ContentView: View {
    @State private var whitelistRaw: String =
        UserDefaults.standard.string(forKey: "whitelist_raw")
            ?? AppGroup.loadWhitelistRaw()
            ?? "[\"彩云滚滚lai:wmn525545100:600\"]"
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
                            set: { whitelistRaw = $0; AppGroup.saveWhitelist($0) }))
                            .frame(minHeight: 80)
                            .font(.system(size: 13))
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
                    let live = AppGroup.loadMatches()
                    if !live.isEmpty { results = live }
                    logs = AppLog.load()
                }
                AppLog.append("I", "App 已打开，白名单已同步到共享存储")
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
                                Text("暂无日志。开始广播后这里会实时显示识别过程；"
                                    + "若无「广播已开始」日志，说明广播未真正启动或 App Group 权限缺失。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(logs) { entry in
                                Text("\(Self.fmt(entry.ts)) \(entry.level)/\(entry.msg)")
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
