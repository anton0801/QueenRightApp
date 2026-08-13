//
//  CameraPreview.swift
//  QueenRight
//
//  A thin AVFoundation still-capture surface for Frame Capture (§5.3).
//  Camera permission is requested HERE, in context, and never in onboarding (§11.13).
//  If permission is refused, or there is no camera at all, the caller falls back to the
//  estimate-by-eye slider and nothing else breaks.
//

import SwiftUI
import AVFoundation

@MainActor
final class CameraController: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle
        case unavailable       // simulator, or no camera hardware
        case denied
        case running
    }

    @Published private(set) var status: Status = .idle
    @Published var captured: UIImage?

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var configured = false

    /// Ask for the camera at the moment the user needs it, not before.
    func start() async {
        guard AVCaptureDevice.default(for: .video) != nil else {
            status = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { status = .denied; return }
        default:
            status = .denied
            return
        }

        guard configure() else {
            status = .unavailable
            return
        }

        let session = self.session
        await Task.detached(priority: .userInitiated) {
            if !session.isRunning { session.startRunning() }
        }.value
        status = .running
    }

    func stop() {
        let session = self.session
        Task.detached(priority: .utility) {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() -> Bool {
        guard !configured else { return true }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
        return true
    }

    func capturePhoto() {
        guard status == .running else { return }
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        Task { @MainActor [weak self] in
            self?.captured = image
        }
    }
}

/// The live viewfinder.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Safe: `layerClass` above guarantees the type.
            guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                return AVCaptureVideoPreviewLayer()
            }
            return layer
        }
    }
}
