//
//  KLCameraManager.swift
//  KLCameraManager
//
//  Created by Klaus on 2018/5/10.
//  Copyright © 2018年 KlausLiu. All rights reserved.
//

import UIKit
import AVFoundation

// MARK: Tap
extension KLCameraManager {
    @objc private func onTap(_ tapGestureRecognizer: UITapGestureRecognizer) {
        guard let previewView = previewView else { return }
        let point = tapGestureRecognizer.location(in: previewView)
        autoFocus(point: point)
        
        focusEffectHiddenTimer?.invalidate()
        focusEffectHiddenTimer = nil
        
        focusEffectView.transform = CGAffineTransform.identity
        
        if let sv = previewView.superview {
            focusEffectView.center = sv.convert(point, from: sv)
            focusEffectView.isHidden = false
            
            UIView.animate(withDuration: 0.3, animations: {
                self.focusEffectView.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            }) { (finished) in
                let timer = Timer.scheduledTimer(timeInterval: 0.5,
                                                 target: self,
                                                 selector: #selector(KLCameraManager.abcc),
                                                 userInfo: nil,
                                                 repeats: false)
                RunLoop.current.add(timer, forMode: .commonModes)
                self.focusEffectHiddenTimer = timer
            }
        }
    }
    @objc private func abcc() {
        self.focusEffectView.isHidden = true
        focusEffectHiddenTimer = nil
    }
}
// MARK: Pinch
extension KLCameraManager: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPinchGestureRecognizer {
            beginGestureScale = effectiveScale
        }
        return true
    }
    
    @objc private func onPinch(_ pinchGestureRecognizer: UIPinchGestureRecognizer) {
        guard let previewLayer = previewLayer,
            let device = device else { return }
        
        effectiveScale = beginGestureScale * pinchGestureRecognizer.scale
        
        var minAvailableVideoZoomFactor: CGFloat = 1.0
        if #available(iOS 11.0, *) {
            minAvailableVideoZoomFactor = device.minAvailableVideoZoomFactor
        }
        if effectiveScale < minAvailableVideoZoomFactor {
            effectiveScale = minAvailableVideoZoomFactor
        }
        
        // max 10 times
        var maxAvailableVideoZoomFactor: CGFloat = 10.0
        if #available(iOS 11.0, *) {
            maxAvailableVideoZoomFactor = device.maxAvailableVideoZoomFactor
        } else if let connection = imageOutput?.connection(with: .video) {
            maxAvailableVideoZoomFactor = connection.videoMaxScaleAndCropFactor
        }
        if maxAvailableVideoZoomFactor > 10 {
            maxAvailableVideoZoomFactor = 10
        }
        
        if effectiveScale > maxAvailableVideoZoomFactor {
            effectiveScale = maxAvailableVideoZoomFactor
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.025)
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: effectiveScale,
                                                          y: effectiveScale))
        CATransaction.commit()
    }
}

public class KLCameraManager: NSObject {
    
    public var previewView: UIView? {
        didSet {
            guard let pv = previewView else { return }
            pv.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                           action: #selector(KLCameraManager.onTap(_:))))
            let pinch = UIPinchGestureRecognizer(target: self,
                                                 action: #selector(KLCameraManager.onPinch(_:)))
            pinch.delegate = self
            pv.addGestureRecognizer(pinch)
            
            focusEffectView.removeFromSuperview()
            pv.superview?.addSubview(focusEffectView)
            focusEffectView.isHidden = true
        }
    }
    
    /// Current pinch scale.
    private var beginGestureScale: CGFloat = 1
    /// Used to image output.
    private var effectiveScale: CGFloat = 1
    
    /// Camera device position. Default is `back`.
    public private(set) var cameraPosition: AVCaptureDevice.Position = .back
    
    /// Flash Mode. Default Value is off
    public var flashMode: AVCaptureDevice.FlashMode = .off {
        didSet {
            guard let device = device else { return }
            guard device.hasFlash && device.isFlashModeSupported(flashMode) else { return }
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } catch (_) { }
        }
    }
    
    /// Torch Mode. Default Value is off
    public var torchMode: AVCaptureDevice.TorchMode = .off {
        didSet {
            guard let device = device else { return }
            guard device.hasTorch && device.isTorchModeSupported(torchMode) else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = torchMode
                device.unlockForConfiguration()
            } catch (_) { }
        }
    }
    
    
    private var sessionQueue: DispatchQueue = DispatchQueue(label: "com.klaus.camera.session_queue")
    
    /// 捕获设备，通常是前置摄像头，后置摄像头，麦克风（音频输入）
    private var device: AVCaptureDevice?
    
    /// AVCaptureDeviceInput 代表输入设备，他使用AVCaptureDevice 来初始化
    private var input: AVCaptureDeviceInput?
    
    /// 输出图片
    private var imageOutput: AVCaptureStillImageOutput?
    
    /// session：由他把输入输出结合在一起，并开始启动捕获设备（摄像头）
    private var session: AVCaptureSession?
    
    /// 图像预览层，实时显示捕获的图像
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    /// Focus effect
    private var focusEffectView: FocusEffectView
    private var focusEffectHiddenTimer: Timer?
    
    public init(cameraPosition: AVCaptureDevice.Position = .back) {
        
        self.cameraPosition = cameraPosition
        
        focusEffectView = FocusEffectView(sideLength: 80)
        focusEffectView.isUserInteractionEnabled = false
        
        super.init()
        
        let ncd = NotificationCenter.default
        ncd.addObserver(self,
                        selector: #selector(KLCameraManager.willChangeStatusBarOrientation(_:)),
                        name: NSNotification.Name.UIApplicationWillChangeStatusBarOrientation,
                        object: nil)
        ncd.addObserver(self,
                        selector: #selector(KLCameraManager.didEnterBackground),
                        name: NSNotification.Name.UIApplicationDidEnterBackground,
                        object: nil)
        ncd.addObserver(self,
                        selector: #selector(KLCameraManager.willEnterForeground),
                        name: NSNotification.Name.UIApplicationWillEnterForeground,
                        object: nil)
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension KLCameraManager {

    /// Start camera device.
    public func startCamera() {
        #if targetEnvironment(simulator)
        return
        #endif
        cameraDistrict()
        
        guard let session = session else { return }
        
        sessionQueue.async {
            session.startRunning()
        }
    }
    
    /// Toggle camera.
    /// front => back || back => front
    public func toggleCamera() {
        switch cameraPosition {
        case .front:
            cameraPosition = .back
        default:
            cameraPosition = .front
        }
        effectiveScale = 1.0
        beginGestureScale = effectiveScale
        startCamera()
    }
    
    /// Stop camera device.
    public func finishCamera() {
        session?.stopRunning()
        session = nil
    }
    
    /// Capture the current image.
    ///
    /// - Parameter callback:
    public func captureImage(_ callback: @escaping (UIImage?) -> Void) {
        guard let connection = imageOutput?.connection(with: .video) else {
            callback(nil)
            return
        }
        refreshVideoOrientation(appOrientation: UIApplication.shared.statusBarOrientation)
        /// 设置缩放比例
        connection.videoScaleAndCropFactor = effectiveScale
        imageOutput?.captureStillImageAsynchronously(from: connection) { [weak self] (buffer, error) in
            guard let `self` = self,
                let buf = buffer else {
                    DispatchQueue.main.async {
                        callback(nil)
                    }
                    return
            }
            
            guard let imgData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buf) else { return }
            var image = UIImage(data: imgData)
            if let img = image {
                image = self.correctOrientation(img)
            }
            DispatchQueue.main.async {
                callback(image)
            }
        }
    }
}

extension KLCameraManager {
    
    public func autoFocus(point: CGPoint) -> Void {
        #if targetEnvironment(simulator)
        return
        #endif
        guard let previewLayer = previewLayer,
            let input = input,
            let device = device else { return }
        
        let newPoint = convertToPointOfInterest(viewCoordinates: point,
                                                previewLayer: previewLayer,
                                                ports: input.ports)
        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = newPoint
                device.focusMode = .autoFocus
                device.unlockForConfiguration()
            } catch(_) {}
        }
    }
    
}

extension KLCameraManager {
    
    private func cameraDistrict() {
        // 初始化摄像头
        if let device = camera(position: cameraPosition),
            let input = try? AVCaptureDeviceInput(device: device) {
            self.device = device
            self.input = input
            
            let imageOutput = AVCaptureStillImageOutput()
            self.imageOutput = imageOutput
            
            let session = AVCaptureSession()
            self.session = session
            
            session.beginConfiguration()
            session.sessionPreset = .high
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            imageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
            if session.canAddOutput(imageOutput) {
                session.addOutput(imageOutput)
            }
            
            session.commitConfiguration()
            if let previewView = previewView {
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                self.previewLayer = previewLayer
                previewLayer.frame = previewView.bounds
                previewLayer.videoGravity = .resizeAspectFill
                previewView.layer.addSublayer(previewLayer)
            }
            refreshVideoOrientation(appOrientation: UIApplication.shared.statusBarOrientation)
        }
    }
    
    private func camera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(for: .video)
        for device in devices {
            if device.position == position {
                return device
            }
        }
        return nil
    }
    
    @objc private func willChangeStatusBarOrientation(_ notification: NSNotification) {
        if let newOrientationInt = notification.userInfo?[UIApplicationStatusBarOrientationUserInfoKey] as? Int,
            let newOrientation = UIInterfaceOrientation(rawValue: newOrientationInt) {
            refreshVideoOrientation(appOrientation: newOrientation)
        }
    }
    private func refreshVideoOrientation(appOrientation: UIInterfaceOrientation) {
        imageOutput?.connection(with: .video)?.isVideoMirrored = cameraPosition == .front
        imageOutput?.connection(with: .video)?.videoOrientation = avOrientation(appOrientation: appOrientation)
        previewLayer?.connection?.videoOrientation = avOrientation(appOrientation: appOrientation)
    }
    @objc private func willEnterForeground() {
        self.startCamera()
    }
    @objc private func didEnterBackground() {
        self.finishCamera()
    }
    
    private func avOrientation(appOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch appOrientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
    
    /// Correct Image Orientation
    ///
    /// - Parameter aImage:
    /// - Returns:
    private func correctOrientation(_ aImage:UIImage) -> UIImage {
        if aImage.imageOrientation == .up { return aImage }
        
        var transform = CGAffineTransform.identity
        switch (aImage.imageOrientation) {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: aImage.size.width, y: aImage.size.height)
            transform = transform.rotated(by: .pi)
            break
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: aImage.size.width, y: 0)
            transform = transform.rotated(by: .pi / 2.0)
            break
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: aImage.size.height)
            transform = transform.rotated(by: 0 - (.pi / 2.0))
            break
        default:
            break
        }
        
        switch (aImage.imageOrientation) {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: aImage.size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
            break
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: aImage.size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
            break
        default:
            break
        }
        guard let cgImage = aImage.cgImage,
            let colorSpace = cgImage.colorSpace,
            let ctx = CGContext(data: nil,
                                width: Int(aImage.size.width),
                                height: Int(aImage.size.height),
                                bitsPerComponent: cgImage.bitsPerComponent,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: cgImage.bitmapInfo.rawValue) else {
                                    return aImage
        }
        ctx.concatenate(transform)
        switch (aImage.imageOrientation) {
        case .left, .leftMirrored, .right, .rightMirrored:
            ctx.draw(cgImage, in: CGRect(origin: .zero,
                                         size: CGSize(width: aImage.size.height,
                                                      height: aImage.size.width)))
            break
        default:
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: aImage.size))
            break
        }
        guard let cgimg = ctx.makeImage() else { return aImage }
        let img = UIImage(cgImage: cgimg)
        return img
    }
    
    /// 转换坐标
    ///
    /// - Parameters:
    ///   - viewCoordinates:
    ///   - previewLayer:
    ///   - ports:
    /// - Returns:
    private func convertToPointOfInterest(viewCoordinates: CGPoint,
                                          previewLayer:AVCaptureVideoPreviewLayer,
                                          ports:[AVCaptureInput.Port]) -> CGPoint {
        let frameSize = previewLayer.frame.size
        if previewLayer.videoGravity == .resize {
            return CGPoint(x: viewCoordinates.y / frameSize.height,
                           y: 1 - (viewCoordinates.x / frameSize.width))
        }
        
        var pointOfInterest = CGPoint(x: 0.5, y: 0.5)
        
        var cleanAperture: CGRect = .zero
        for port in ports {
            if port.mediaType == .video {
                guard let des = port.formatDescription else { continue }
                
                cleanAperture = CMVideoFormatDescriptionGetCleanAperture(des, true)
                let apertureSize = cleanAperture.size
                let point = viewCoordinates
                
                let apertureRatio = apertureSize.height / apertureSize.width
                let  viewRatio = frameSize.width / frameSize.height
                var xc: CGFloat = 0.5
                var yc: CGFloat = 0.5
                
                if previewLayer.videoGravity == .resizeAspect {
                    if viewRatio > apertureRatio {
                        let y2 = frameSize.height
                        let x2 = frameSize.height * apertureRatio
                        let x1 = frameSize.width
                        let blackBar = (x1 - x2) / 2
                        if (point.x >= blackBar && point.x <= blackBar + x2) {
                            xc = point.y / y2
                            yc = 1 - ((point.x - blackBar) / x2)
                        }
                    } else {
                        let y2 = frameSize.width / apertureRatio
                        let y1 = frameSize.height
                        let x2 = frameSize.width
                        let blackBar = (y1 - y2) / 2
                        if (point.y >= blackBar && point.y <= blackBar + y2) {
                            xc = ((point.y - blackBar) / y2)
                            yc = 1 - (point.x / x2)
                        }
                    }
                } else if previewLayer.videoGravity == .resizeAspectFill {
                    if (viewRatio > apertureRatio) {
                        let y2 = apertureSize.width * (frameSize.width / apertureSize.height)
                        xc = (point.y + ((y2 - frameSize.height) / 2)) / y2
                        yc = (frameSize.width - point.x) / frameSize.width
                    } else {
                        let x2 = apertureSize.height * (frameSize.height / apertureSize.width)
                        yc = 1 - ((point.x + ((x2 - frameSize.width) / 2)) / x2)
                        xc = point.y / frameSize.height
                    }
                }
                
                pointOfInterest = CGPoint(x: xc, y: yc)
                break
            }
        }
        return pointOfInterest
    }
}

private class FocusEffectView: UIView {
    init(sideLength: CGFloat) {
        super.init(frame: CGRect(origin: .zero,
                                 size: CGSize(width: sideLength + lineWidth,
                                              height: sideLength + lineWidth)))
        backgroundColor = .clear
    }
    
    private let lineWidth: CGFloat = 1
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        ctx.setStrokeColor(UIColor(red: 250.0/256,
                                   green: 200.0/256,
                                   blue: 50.0/256,
                                   alpha: 1.0).cgColor)
        ctx.setLineWidth(lineWidth)
        
        ctx.addLines(between: [
            CGPoint(x: lineWidth/2, y: lineWidth/2),
            CGPoint(x: frame.size.width - lineWidth/2, y: lineWidth/2),
            CGPoint(x: frame.size.width - lineWidth/2, y: frame.size.height - lineWidth/2),
            CGPoint(x: lineWidth/2, y: frame.size.height - lineWidth/2),
            CGPoint(x: lineWidth/2, y: lineWidth/2),
            ])
        
        let segmentLength: CGFloat = 1/10
        ctx.move(to: CGPoint(x: frame.size.width/2,
                             y: lineWidth/2))
        ctx.addLine(to: CGPoint(x: frame.size.width/2,
                                y: lineWidth/2 + (frame.size.height * segmentLength)))
        
        ctx.move(to: CGPoint(x: frame.size.width - lineWidth/2,
                             y: frame.size.height/2))
        ctx.addLine(to: CGPoint(x: frame.size.width - lineWidth/2 - (frame.size.width * segmentLength),
                                y: frame.size.height/2))
        
        ctx.move(to: CGPoint(x: frame.size.width/2,
                             y: frame.size.height - lineWidth/2))
        ctx.addLine(to: CGPoint(x: frame.size.width/2,
                                y: frame.size.height - lineWidth/2 - (frame.size.height * segmentLength)))
        
        ctx.move(to: CGPoint(x: lineWidth/2,
                             y: frame.size.height/2))
        ctx.addLine(to: CGPoint(x: lineWidth/2 + (frame.size.width * segmentLength),
                                y: frame.size.height/2))
        
        ctx.strokePath()
    }
}
