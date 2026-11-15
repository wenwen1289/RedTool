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
                                // 系统屏幕共享选择器
                                BroadcastPickerButton(
                                    preferredExtensionBundleID: broadcastExtensionBundleID)
                                    .frame(width: 44, height: 44)
                                Text("点击图标 → 选「红薯tool」→ 开始广播\n在小红书滚动，命中白名单会发通知")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Button("允许通知提醒") {
                                UNUserNotificationCenter.current()
                                    .requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
                }
                .padding()
            }
            .navigationTitle("红薯tool")
            .onAppear {
                // 每秒从 App Group 读扩展写入的实时结果
                liveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    let live = AppGroup.loadMatches()
                    if !live.isEmpty { results = live }
                }
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
                case .failure(let err):
                    statusText = "读取失败: \(err.localizedDescription)"
                default:
                    statusText = "未获取到图片"
                }
            }
        }
    }
}
