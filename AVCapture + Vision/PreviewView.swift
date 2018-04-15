//
//  PreviewView.swift
//  AVCapture + Vision
//
//  Created by Andrew Finke on 9/26/17.
//  Copyright © 2018 Andrew Finke. All rights reserved.
//

import UIKit
import AVFoundation

class PreviewView: UIView {

    // MARK: - Properties

    var didTap: (() -> Void)?

	var videoPreviewLayer: AVCaptureVideoPreviewLayer {
		return layer as! AVCaptureVideoPreviewLayer
	}
	
	var session: AVCaptureSession? {
		get {
			return videoPreviewLayer.session
		}
		set {
			videoPreviewLayer.session = newValue
            videoPreviewLayer.videoGravity = .resizeAspectFill
		}
	}

	// MARK: - UIView
	
    override class var layerClass: AnyClass {
		return AVCaptureVideoPreviewLayer.self
	}

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        didTap?()
    }
}
