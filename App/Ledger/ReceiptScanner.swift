#if os(iOS)
import SwiftUI
import VisionKit

/// The camera's document scanner, which finds a receipt's edges and flattens it, for
/// `ReceiptReader`. Each page it scans comes back as image data to be read and let go: nothing
/// is saved to Photos or kept, by the user's choice.
struct ReceiptScanner: UIViewControllerRepresentable {
    /// Not in the Simulator, or on a device without a camera.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    let scanned: ([Data]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(scanner: self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let scanner: ReceiptScanner

        init(scanner: ReceiptScanner) {
            self.scanner = scanner
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9) }
            scanner.dismiss()
            scanner.scanned(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            scanner.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            scanner.dismiss()
        }
    }
}
#endif
