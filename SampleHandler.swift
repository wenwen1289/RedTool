import ReplayKit
import UserNotifications

/// Broadcast Upload Extension 入口：
/// 用户在系统屏幕共享中选中本 App 后，系统把整屏实时帧送进来。
/// 每 2 秒对一帧做 OCR → 白名单匹配 → 结果写 App Group → 发本地通知。
class SampleHandler: RPBroadcastSampleHandler {

    private var lastAnalyze = Date.distantPast
    private var notified = Set<String>()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        notified.removeAll()
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    override func broadcastFinished() {
        AppGroup.saveMatches([])
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAnalyze) >= 2 else { return }   // 限频 0.5fps
        lastAnalyze = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let lines = ScreenshotAnalyzer.recognizeText(pixelBuffer: pixelBuffer)

        let whitelist = WhitelistStore.parse(AppGroup.loadWhitelistRaw())
        guard !whitelist.isEmpty else { return }

        let matches = ScreenshotAnalyzer.analyze(lines: lines, whitelist: whitelist)
        AppGroup.saveMatches(matches)   // 主 App 打开时可直接看到实时表格

        // 命中「达标」（点赞数<阈值）的新结果 → 本地通知
        let fresh = matches.filter { !$0.overThreshold }.filter {
            notified.insert("\($0.displayName)|\($0.entry.id)").inserted
        }
        postNotification(fresh)
    }

    private func postNotification(_ matches: [MatchResult]) {
        guard !matches.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "发现白名单博主（达标 \(matches.count) 条）"
        content.body = matches.prefix(5).map {
            "\($0.displayName) \($0.likeCount)赞（阈值\($0.entry.threshold)）"
        }.joined(separator: "\n")
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                NSLog("[红薯tool] 通知发送失败: \(error.localizedDescription)")
            }
        }
    }
}
