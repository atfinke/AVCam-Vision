/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Application preview view.
*/

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
