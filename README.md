# 红薯tool iOS 版（实时屏幕广播识别 + 通知提醒）

## 方案说明

- 旁白（VoiceOver）是面向用户的读屏功能，系统未提供 API 让 App 读取旁白
  在其他 App 中朗读的内容，因此不能用于识别小红书页面。
- 采用 **ReplayKit 屏幕广播（Broadcast Upload Extension）**：
  用户在 App 内点击系统「屏幕共享」图标 → 选择「红薯tool」→ 开始广播，
  系统把整屏实时帧送入扩展 → 每 2 秒 OCR 一帧 → 白名单匹配（完全/前缀匹配）→
  命中「达标」结果时**发本地通知**，打开 App 可看实时双表格。
- 另保留**截图识别**：选相册截图 → 立即出结果（不需要广播权限）。

## Xcode 工程创建步骤

1. File > New > Project > iOS App（SwiftUI），Product Name 填 RedBookTool，
   删除模板的 ContentView.swift 与 App 入口文件，把 iosProject 目录下
   7 个 .swift 文件全部拖入（勾选 Copy items if needed）。最低部署版本 iOS 16.0。
2. Info.plist 添加相册权限：
   NSPhotoLibraryUsageDescription = 用于选取小红书截图并识别白名单博主
3. File > New > Target > Broadcast Upload Extension：
   - Name 填 BroadcastExtension，语言 Swift，不勾选 UI Extension。
   - 用本目录的 SampleHandler.swift **替换**扩展自动生成的同名文件。
   - 把 AppGroup.swift、WhitelistStore.swift、ScreenshotAnalyzer.swift 同时加入
     App 和 扩展两个 target 的成员（Build Phases > Compile Sources 勾选）。
4. 给 **App 和 扩展两个 target** 都添加 capability「App Groups」，
   Group 名固定为：group.com.wenwen1289.RedTool（与 AppGroup.swift 中一致；
   免费签名请保持此默认命名格式，自定义名容易被拒）。
5. ContentView.swift 中 broadcastExtensionBundleID 默认为
   主 App BundleID + ".BroadcastExtension"，如扩展命名不同请对应修改。
6. 真机运行：点 App 内「允许通知提醒」→ 点系统广播图标 → 开始广播 →
   切到小红书滚动 → 命中白名单（点赞数<阈值）会收到系统通知。

## 白名单格式（与 Android 版一致）

["博主名称:博主id:点赞阈值", "饺子配抹茶咂咂嘴:jiaozi550501319:600"]

## 与 Android 版功能对应

| Android 版 | iOS 版 |
|---|---|
| 悬浮窗实时识别 | 屏幕广播实时识别 + 通知提醒 |
| 达标/阈值外两个表格 | 相同（达标标题绿色） |
| 条目格式：名称+点赞数+(超阈值) | 相同 |
| 阈值外显示开关 | 相同 |
| 临时关闭/长期关闭 | 不需要（无悬浮窗，广播可随时停止） |
| 白名单自动保存 | 相同（App Group 双向同步） |

## 已知限制

- iOS 广播会显示系统"红色状态条"提示正在录屏，无法隐藏。
- 扩展内发通知在部分 iOS 版本可能受限；即使通知未弹出，
  结果仍会写入 App Group，回到 App 即可看到实时表格。

## 日志面板（v1.1 新增）

- App 底部新增「运行日志」面板，与安卓版一致：实时显示扩展识别过程
  （广播开始/结束、OCR行数、白名单命中详情、通知发送结果、权限状态）。
- 日志由主 App 与广播扩展共同写入 App Group，5 分钟自动清理，最多保留 500 条。
- 排查指引：
  - 无「广播已开始」日志 → 广播未真正启动，或免费签名未带 App Group 权限
  - 「白名单为空」→ App Group 未同步，实时识别不可用（截图识别不受影响）
  - 「通知权限: 被拒绝」→ 到 设置-通知-红薯tool 开启允许
