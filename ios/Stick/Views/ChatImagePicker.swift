import SwiftUI
import UIKit

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    /// nil = 自动（真机用相机，模拟器用相册）；指定值则强制使用
    var sourceType: UIImagePickerController.SourceType? = nil
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if let forced = sourceType {
            // 强制指定类型，但模拟器上相机不可用时 fallback 到相册
            if forced == .camera && !UIImagePickerController.isSourceTypeAvailable(.camera) {
                picker.sourceType = .photoLibrary
            } else {
                picker.sourceType = forced
            }
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - UIKit 收键盘手势（不阻挡子视图交互）

/// 透明背景 UIView，接收点击事件用于收起键盘
/// cancelsTouchesInView = false 保证点击不会阻挡下层 TextField/Button 的交互
private struct DismissingKeyboardView: UIViewRepresentable {
    let onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap)
    }

    class Coordinator {
        let onTap: () -> Void
        init(_ onTap: @escaping () -> Void) { self.onTap = onTap }
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            if sender.state == .ended {
                onTap()
            }
        }
    }
}
