import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import LittleBeaconCore
import Vision

enum CameraPermissionState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum ViewingDistanceMonitorError: LocalizedError {
    case permissionDenied
    case noCamera
    case cameraBusy
    case captureAlreadyRunning
    case cannotConfigureCamera
    case notEnoughFaceSamples
    case cameraChanged

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "摄像头权限没有开启，请到“系统设置 → 隐私与安全性 → 摄像头”中允许小灯塔。"
        case .noCamera:
            "没有找到可用的内置摄像头。"
        case .cameraBusy:
            "摄像头正在被其他应用使用，这次先不检查。"
        case .captureAlreadyRunning:
            "摄像头正在检查中，请稍等一下。"
        case .cannotConfigureCamera:
            "无法启动摄像头，请稍后再试。"
        case .notEnoughFaceSamples:
            "没有稳定看到一张正对屏幕的脸，请调整光线和坐姿后再试。"
        case .cameraChanged:
            "当前摄像头和上次校准时不同，需要重新校准。"
        }
    }
}

/// Owns the complete camera/Vision implementation behind two operations: calibrate and check.
///
/// No preview, image, pixel buffer, or facial feature leaves this module. The only retained
/// values are normalized face-box widths gathered during the current four-second capture.
final class ViewingDistanceMonitor:
    NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    private struct CaptureBatch {
        let cameraUniqueID: String
        let normalizedFaceWidths: [Double]
        let sawMultipleFaces: Bool
    }

    private struct ActiveCapture {
        let continuation: CheckedContinuation<CaptureBatch, Error>
        let cameraUniqueID: String
        let acceptFramesAfter: Date
        var normalizedFaceWidths: [Double]
        var sawMultipleFaces: Bool
    }

    private let sessionQueue = DispatchQueue(label: "app.littlebeacon.viewing-distance.session")
    private let videoQueue = DispatchQueue(label: "app.littlebeacon.viewing-distance.video")
    private var activeCapture: ActiveCapture?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var lastProcessedPresentationSeconds = -Double.infinity

    static var permissionState: CameraPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    static func requestPermission() async -> CameraPermissionState {
        if permissionState != .notDetermined {
            return permissionState
        }
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                continuation.resume(returning: allowed)
            }
        }
        return granted ? .authorized : .denied
    }

    func calibrate(referenceDistanceCentimeters: Int) async throws -> ViewingDistanceCalibration {
        let batch = try await captureFaceWidths()
        guard !batch.sawMultipleFaces else {
            throw ViewingDistanceMonitorError.notEnoughFaceSamples
        }
        guard let calibration = ViewingDistanceJudge.makeCalibration(
            cameraUniqueID: batch.cameraUniqueID,
            normalizedFaceWidths: batch.normalizedFaceWidths,
            referenceDistanceCentimeters: referenceDistanceCentimeters
        ) else {
            throw ViewingDistanceMonitorError.notEnoughFaceSamples
        }
        return calibration
    }

    func check(
        calibration: ViewingDistanceCalibration,
        policy: ViewingDistancePolicy,
        wasTooClose: Bool
    ) async throws -> ViewingDistanceAssessment {
        let batch = try await captureFaceWidths()
        guard !batch.sawMultipleFaces else { return .inconclusive }
        guard batch.cameraUniqueID == calibration.cameraUniqueID else {
            throw ViewingDistanceMonitorError.cameraChanged
        }
        return ViewingDistanceJudge.assess(
            cameraUniqueID: batch.cameraUniqueID,
            normalizedFaceWidths: batch.normalizedFaceWidths,
            calibration: calibration,
            policy: policy,
            wasTooClose: wasTooClose
        )
    }

    private func captureFaceWidths(duration: TimeInterval = 4) async throws -> CaptureBatch {
        guard Self.permissionState == .authorized else {
            throw ViewingDistanceMonitorError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ViewingDistanceMonitorError.cannotConfigureCamera)
                    return
                }
                self.beginCapture(duration: duration, continuation: continuation)
            }
        }
    }

    private func beginCapture(
        duration: TimeInterval,
        continuation: CheckedContinuation<CaptureBatch, Error>
    ) {
        guard activeCapture == nil else {
            continuation.resume(throwing: ViewingDistanceMonitorError.captureAlreadyRunning)
            return
        }
        guard let camera = Self.preferredCamera() else {
            continuation.resume(throwing: ViewingDistanceMonitorError.noCamera)
            return
        }
        guard !camera.isInUseByAnotherApplication else {
            continuation.resume(throwing: ViewingDistanceMonitorError.cameraBusy)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_32BGRA),
            ]
            output.setSampleBufferDelegate(self, queue: videoQueue)

            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .low
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                output.setSampleBufferDelegate(nil, queue: nil)
                continuation.resume(throwing: ViewingDistanceMonitorError.cannotConfigureCamera)
                return
            }
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()

            lastProcessedPresentationSeconds = -Double.infinity
            activeCapture = ActiveCapture(
                continuation: continuation,
                cameraUniqueID: camera.uniqueID,
                acceptFramesAfter: Date().addingTimeInterval(0.75),
                normalizedFaceWidths: [],
                sawMultipleFaces: false
            )
            captureSession = session
            videoOutput = output
            session.startRunning()

            sessionQueue.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.finishCapture()
            }
        } catch {
            continuation.resume(throwing: error)
        }
    }

    private func finishCapture() {
        guard let capture = activeCapture else { return }
        captureSession?.stopRunning()
        videoOutput?.setSampleBufferDelegate(nil, queue: nil)
        captureSession = nil
        videoOutput = nil
        activeCapture = nil
        capture.continuation.resume(returning: CaptureBatch(
            cameraUniqueID: capture.cameraUniqueID,
            normalizedFaceWidths: capture.normalizedFaceWidths,
            sawMultipleFaces: capture.sawMultipleFaces
        ))
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let presentationSeconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard presentationSeconds.isFinite,
              presentationSeconds - lastProcessedPresentationSeconds >= 0.3 else {
            return
        }
        lastProcessedPresentationSeconds = presentationSeconds

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: .up,
            options: [:]
        )
        do {
            try handler.perform([request])
            guard let faces = request.results else { return }
            if faces.count > 1 {
                sessionQueue.async { [weak self] in
                    guard let self, var capture = self.activeCapture,
                          Date() >= capture.acceptFramesAfter else {
                        return
                    }
                    capture.sawMultipleFaces = true
                    self.activeCapture = capture
                }
                return
            }
            guard faces.count == 1,
                  let face = faces.first,
                  face.confidence >= 0.7 else {
                return
            }
            let width = Double(face.boundingBox.width)
            sessionQueue.async { [weak self] in
                guard let self, var capture = self.activeCapture,
                      Date() >= capture.acceptFramesAfter else {
                    return
                }
                capture.normalizedFaceWidths.append(width)
                self.activeCapture = capture
            }
        } catch {
            // A dropped or unreadable frame makes this capture less conclusive; it is never
            // converted into a too-close result.
        }
    }

    private static func preferredCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .unspecified
        ) ?? AVCaptureDevice.default(for: .video)
    }
}
