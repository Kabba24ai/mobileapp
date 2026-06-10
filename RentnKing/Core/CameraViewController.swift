//
//  CameraViewController.swift
//  RentnKing
//
//  Created by DEEPAK JAIN on 07/04/26.
//

import UIKit
import AVFoundation

protocol CameraViewControllerDelegate: AnyObject {
    func didCaptureImage(_ image: UIImage)
    func didCancel()
}

final class CameraViewController: UIViewController {

    // MARK: - Public
    var strTitle = ""
    weak var delegate: CameraViewControllerDelegate?

    // MARK: - Camera Properties
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // MARK: - UI
    private let overlayView = OverlayView()
    private let captureButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let lblTitle = UILabel()

    // MARK: - Config
    private var cutoutRect: CGRect = .zero

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupCamera()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        previewLayer.frame = view.bounds

        // Define licence frame
        let width = view.frame.width - 60
        let height: CGFloat = width * 0.6
        let x: CGFloat = 30
        let y: CGFloat = (view.frame.height - height) / 2

        cutoutRect = CGRect(x: x, y: y, width: width, height: height)

        overlayView.frame = view.bounds
        overlayView.cutoutRect = cutoutRect
        overlayView.setNeedsDisplay()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkCameraPermission()
    }
    

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }
    
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {

        case .authorized:
            // Already allowed
            setupAndStartSession()

        case .notDetermined:
            // Ask permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupAndStartSession()
                    } else {
                        self.showPermissionAlert()
                    }
                }
            }

        case .denied, .restricted:
            // Already denied
            showPermissionAlert()

        @unknown default:
            break
        }
    }
    
    private func setupAndStartSession() {
        if previewLayer == nil {
            setupCamera()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    private func showPermissionAlert() {
        let alert = UIAlertController(
            title: "Camera Permission Required",
            message: "Please enable camera access in Settings to scan your licence.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            self.delegate?.didCancel()
            self.dismiss(animated: true)
        }))

        alert.addAction(UIAlertAction(title: "Open Settings", style: .default, handler: { _ in
            if let url = URL(string: UIApplication.openSettingsURLString),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }))

        present(alert, animated: true)
    }
}

// MARK: - Setup
private extension CameraViewController {
    
    func setupCamera() {
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // 🔥 Preview Layer
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)

        // ✅ FIX 1: Preview orientation
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        // ✅ FIX 2: Photo output orientation
        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }


    func setupUI() {
        // Overlay
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)

        // Capture Button
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 40
        captureButton.clipsToBounds = true
        captureButton.layer.borderWidth = 8
        captureButton.layer.borderColor = UIColor.darkGray.cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)

        captureButton.frame = CGRect(
            x: (view.frame.width - 80) / 2,
            y: view.frame.height - (GlobalMainConstants.appDelegate?.window?.safeAreaInsets.bottom ?? 0) - 100,
            width: 80,
            height: 80
        )

        view.addSubview(captureButton)

        // Close Button
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.layer.cornerRadius = 22
        closeButton.clipsToBounds = true
        closeButton.backgroundColor = .darkGray
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        closeButton.frame = CGRect(x: 22, y: (GlobalMainConstants.appDelegate?.window?.safeAreaInsets.top ?? 0) + 22, width: 44, height: 44)
        view.addSubview(closeButton)
        
        lblTitle.configureLable(textAlignment: .center, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 22, text: self.strTitle)
        lblTitle.frame = CGRect(x: 60, y: (GlobalMainConstants.appDelegate?.window?.safeAreaInsets.top ?? 0) + 30, width: (UIScreen.main.bounds.width - 120), height: 25)
        view.addSubview(lblTitle)

    }
}

// MARK: - Actions
private extension CameraViewController {

    @objc func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc func closeTapped() {
        delegate?.didCancel()
        dismiss(animated: true)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraViewController: AVCapturePhotoCaptureDelegate {

    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        guard let data = photo.fileDataRepresentation(),
              var image = UIImage(data: data) else { return }

        // 🔥 Force correct orientation
        if image.imageOrientation != .up {
            image = fixOrientation(image)
        }
        
        let cropped = cropImageAccurate(image, overlayRect: cutoutRect)

        if let finalImage = cropped {
            delegate?.didCaptureImage(finalImage)
        }

        dismiss(animated: true)
    }
    
    func fixOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? image
    }
    
}

// MARK: - Crop Logic
private extension CameraViewController {
    
    func cropImageAccurate(_ image: UIImage, overlayRect: CGRect) -> UIImage? {

        guard let previewLayer = self.previewLayer,
              let cgImage = image.cgImage else { return nil }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // 1. Get visible preview frame (what user actually sees)
        let previewBounds = previewLayer.bounds

        let imageAspect = imageWidth / imageHeight
        let previewAspect = previewBounds.width / previewBounds.height

        var scale: CGFloat = 0
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0

        if imageAspect > previewAspect {
            // Image is wider → cropped left/right
            scale = previewBounds.height / imageHeight
            let scaledWidth = imageWidth * scale
            xOffset = (scaledWidth - previewBounds.width) / 2 / scale
        } else {
            // Image is taller → cropped top/bottom
            scale = previewBounds.width / imageWidth
            let scaledHeight = imageHeight * scale
            yOffset = (scaledHeight - previewBounds.height) / 2 / scale
        }
        
        // 🔥 Convert overlay → image space (NO magic numbers)
        let cropX = (overlayRect.origin.x / previewBounds.width) * imageWidth + xOffset
        let cropY = (overlayRect.origin.y / previewBounds.height) * imageHeight + yOffset
        var cropWidth = (overlayRect.width / previewBounds.width) * imageWidth
        let cropHeight = (overlayRect.height / previewBounds.height) * imageHeight

        //let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        let safeRect = CGRect(
            x: max(0, cropX),
            y: max(0, cropY),
            width: min(cropWidth, imageWidth - cropX),
            height: min(cropHeight, imageHeight - cropY)
        )
        
        let widthCorrectionRatio: CGFloat = 0.68
        let finalWidth = safeRect.size.width * widthCorrectionRatio
        
        let finalRect = CGRect(
            x: safeRect.origin.x.rounded(.up) - 50,
            y: safeRect.origin.y.rounded(.down),
            width: finalWidth.rounded(.down),
            height: safeRect.size.height.rounded(.down)
        )
        
//        var finalRect = CGRect(
//            x: safeRect.origin.x.rounded(.up) - 50,
//            y: safeRect.origin.y.rounded(.down),
//            width: 1500.0,// safeRect.size.width.rounded(.down),
//            height: safeRect.size.height.rounded(.down)
//        )
        
        print("IMAGE SIZE:", imageWidth, imageHeight)
        print("CROP RECT:", finalRect)
        
        guard let croppedCG = cgImage.cropping(to: finalRect) else {
            print("❌ CROPPING FAILED")
            return nil
        }

        print("✅ CROPPING SUCCESS")

        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: .up)

    }
    
}

//////////////////////////////////////////////////////////////
// MARK: - Overlay View
//////////////////////////////////////////////////////////////

final class OverlayView: UIView {

    var cutoutRect: CGRect = .zero

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Background
        context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        context.fill(rect)

        // Clear cutout
        context.setBlendMode(.clear)
        let path = UIBezierPath(roundedRect: cutoutRect, cornerRadius: 12)
        context.addPath(path.cgPath)
        context.fillPath()

        context.setBlendMode(.normal)

        // Border
        let border = CAShapeLayer()
        border.path = UIBezierPath(roundedRect: cutoutRect, cornerRadius: 12).cgPath
        border.strokeColor = UIColor.white.cgColor
        border.lineWidth = 2
        border.fillColor = UIColor.clear.cgColor

        layer.sublayers?.removeAll(where: { $0 is CAShapeLayer })
        layer.addSublayer(border)
    }

}
