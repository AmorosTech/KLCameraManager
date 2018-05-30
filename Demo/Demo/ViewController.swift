//
//  ViewController.swift
//  Demo
//
//  Created by Klaus on 2018/5/12.
//  Copyright © 2018年 KlausLiu. All rights reserved.
//

import UIKit
import KLCameraManager

class ViewController: UIViewController {
    
    var cameraManager = KLCameraManager(cameraPosition: .back)

    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var toggleBtn: UIButton!
    @IBOutlet weak var capturedImageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        previewView.layoutIfNeeded()
        
        cameraManager.previewView = previewView
        cameraManager.startCamera()
    }
    
    @IBAction func toggleDevice(_ sender: Any) {
        var flip: UIViewAnimationOptions = .transitionFlipFromRight
        if cameraManager.cameraPosition == .front {
            flip = .transitionFlipFromLeft
        }
        UIView.transition(with: previewView,
                          duration: 0.25,
                          options: flip,
                          animations: {}) { (_) in }
        cameraManager.toggleCamera()
    }
    
    @IBAction func capture(_ sender: Any) {
        cameraManager.captureImage { [weak self] img in
            self?.capturedImageView.image = img
        }
    }
    
    @IBAction func toggleFlash(_ sender: UIButton) {
        switch cameraManager.flashMode {
        case .off:
            cameraManager.flashMode = .on
            sender.setTitle("灯光(开)", for: .normal)
        case .on:
            cameraManager.flashMode = .auto
            sender.setTitle("灯光(自动)", for: .normal)
        case .auto:
            cameraManager.flashMode = .off
            sender.setTitle("灯光(关)", for: .normal)
        }
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    /*override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }*/

    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

}

