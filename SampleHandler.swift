import ReplayKit
import UserNotifications

/// Broadcast Upload Extension 入口：
/// 用户在系统屏幕共享中选中本 App 后，系统把整屏实时帧送进来。
/// 每 2 秒对一帧做 OCR → 白名单匹配 → 结果写 App Group → 发本地通知。
/// 全过程写入共享日志（App 内日志面板可见，5 分钟自动清理）。
class SampleHandler: RPBroadcastSampleHandler {

    private var lastAnalyze = Date.distantPast
    private var notified = Set<String>()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        notified.removeAll()
        AppLog.append("I", "===== 广播已开始，每 2 秒识别一帧 =====")

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    AppLog.append("E", "通知权限申请失败: \(error.localizedDescription)")
                } else {
                    AppLog.append("I", "通知权限: \(granted ? "已授权" : "被拒绝(通知将不显示)")")
                }
            }
        }

        let whitelist = WhitelistStore.parse(AppGroup.loadWhitelistRaw())
        if whitelist.isEmpty {
            AppLog.append("W", "白名单为空！App Group 未同步，实时识别不可用"
                + "（免费签名可能未带 App Group 权限，截图识别不受影响）")
        } else {
            AppLog.append("I", "白名单已加载 \(whitelist.count) 条")
        }
    }

    override func broadcastFinished() {
        AppLog.append("I", "===== 广播已结束 =====")
        AppGroup.saveMatches([])
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAnalyze) >= 2 else { return }   // 限频 0.5fps
        lastAnalyze = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            AppLog.append("W", "本帧图像获取失败")
            return
        }

        let lines = ScreenshotAnalyzer.recognizeText(pixelBuffer: pixelBuffer)

        let whitelist = WhitelistStore.parse(AppGroup.loadWhitelistRaw())
        guard !whitelist.isEmpty else {
            AppLog.append("W", "跳过识别: 白名单为空(App Group 未同步)")
            return
        }

        let matches = ScreenshotAnalyzer.analyze(lines: lines, whitelist: whitelist)
        AppGroup.saveMatches(matches)   // 主 App 打开时可直接看到实时表格

        let below = matches.filter { !$0.overThreshold }
        let over = matches.filter { $0.overThreshold }
        if matches.isEmpty {
            AppLog.append("I", "识别: OCR行数\(lines.count), 本帧无白名单命中")
        } else {
            AppLog.append("I", "识别: OCR行数\(lines.count), 命中达标\(below.count)条/阈值外\(over.count)条")
            for m in below {
                AppLog.append("I", "【达标】\(m.displayName) \(m.likeCount)赞 < 阈值\(m.entry.threshold)")
            }
            for m in over {
                AppLog.append("I", "【阈值外】\(m.displayName) \(m.likeCount)赞 ≥ 阈值\(m.entry.threshold)")
            }
        }

        // 命中「达标」（点赞数<阈值）的新结果 → 本地通知
        let fresh = below.filter {
            notified.insert("\($0.displayName)|\($0.entry.id)").inserted
        }
        if fresh.isEmpty {
            if !below.isEmpty { AppLog.append("I", "通知: 命中结果已通知过，跳过") }
        } else {
            postNotification(fresh)
        }
    }

    private func postNotification(_ matches: [MatchResult]) {
        let content = UNMutableNotificationContent()
        content.title = "发现白名单博主（达标 \(matches.count) 条）"
        content.body = matches.prefix(5).map {
            "\($0.displayName) \($0.likeCount)赞（阈值\($0.entry.threshold)）"
        }.joined(separator: "\n")
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            DispatchQueue.main.async {
                if let error = error {
                    AppLog.append("E", "通知发送失败: \(error.localizedDescription)")
                } else {
                    AppLog.append("I", "通知已发出: "
                        + matches.prefix(3).map { $0.displayName }.joined(separator: "、"))
                }
            }
        }
    }
}
