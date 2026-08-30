import SwiftUI
import UniformTypeIdentifiers

struct MusicFilePicker: UIViewControllerRepresentable {
    let onFilesPicked: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 强制解包 guard 化：UTType("public.mp3") 等可能为 nil，compactMap 兜底
        // （UTType.audio 恒非 nil，故 contentTypes 至少含一项，不会为空数组）
        let contentTypes: [UTType] = [UTType.audio, UTType("public.mp3"), UTType("org.xiph.flac")]
            .compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)

        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        picker.modalPresentationStyle = .formSheet

        // Store reference to prevent premature deallocation
        context.coordinator.picker = picker

        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIDocumentPickerViewController, coordinator: Coordinator) {
        // Clean up to prevent DocumentManager crash
        uiViewController.delegate = nil
        coordinator.picker = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFilesPicked: onFilesPicked)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFilesPicked: ([URL]) -> Void
        weak var picker: UIDocumentPickerViewController?

        init(onFilesPicked: @escaping ([URL]) -> Void) {
            self.onFilesPicked = onFilesPicked
            super.init()
        }

        deinit {
            // Ensure delegate is cleared on deallocation
            picker?.delegate = nil
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFilesPicked(urls)
            // Clean up delegate to prevent DocumentManager issues
            controller.delegate = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled, clean up delegate
            controller.delegate = nil
        }
    }
}
