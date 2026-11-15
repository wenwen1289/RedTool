import SwiftUI
import ReplayKit

/// 系统屏幕共享选择器（把「开始直播」流程交给系统弹窗）
struct BroadcastPickerButton: UIViewRepresentable {
    var preferredExtensionBundleID: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.showsMicrophoneButton = false
        picker.preferredExtension = preferredExtensionBundleID
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
