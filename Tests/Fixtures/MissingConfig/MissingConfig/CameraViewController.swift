import AVFoundation
import UIKit

final class CameraViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            print("Camera access: \(granted)")
        }
    }
}
