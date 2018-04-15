//
//  CameraViewController.swift
//  AVCapture + Vision
//
//  Created by Andrew Finke on 9/26/17.
//  Copyright © 2018 Andrew Finke. All rights reserved.
//

import UIKit
import Vision
import AVFoundation

class CameraViewController: UIViewController {

    // MARK: - Types

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    // MARK: - Interface

    @IBOutlet private weak var percentLabel: UILabel!
    @IBOutlet private weak var identityLabel: UILabel!
    @IBOutlet private weak var previewView: PreviewView!
    @IBOutlet private weak var visualEffectView: UIVisualEffectView!
    
    // MARK: - Formatters

    private let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.maximumIntegerDigits = 2
        return formatter
    }()

    // MARK: - Vision Properties

    let visionModel: VNCoreMLModel = {
        let mobileNetModel = MobileNet.init().model
        guard let visionModel = try? VNCoreMLModel(for: mobileNetModel) else {
            fatalError()
        }
        return visionModel
    }()

    lazy var visionRequest: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: visionModel) { request, _ in
            guard let results = request.results as? [VNClassificationObservation], let topResult = results.first else {
                return
            }
            DispatchQueue.main.async {
                if topResult.confidence > 0.3 {
                    self.currentObject = topResult.identifier.components(separatedBy: ",").first?.capitalized
                    self.currentConfidence = topResult.confidence
                } else if topResult.confidence < 0.2 {
                    self.currentObject = nil
                    self.currentConfidence = nil
                }

                if let object = self.currentObject,
                    let confidence = self.currentConfidence,
                    let confidenceString = self.percentFormatter.string(from: NSNumber(value: confidence)) {
                    self.speechString = "\(object). \(confidenceString) Confident"
                } else {
                    self.speechString = "Not Sure."
                }
            }
        }
        request.imageCropAndScaleOption = .centerCrop
        return request
    }()

    // MARK: - Detection Properties

    private var currentObject: String? {
        didSet {
            if let object = currentObject {
                identityLabel.text = object
            } else {
                identityLabel.text = "Not Sure"
            }
        }
    }

    private var currentConfidence: Float? {
        didSet {
            if let confidence = currentConfidence {
                percentLabel.text = self.percentFormatter.string(from: NSNumber(value: confidence))
            } else {
                percentLabel.text = "-"
            }
        }
    }

    private var speechString = "Not Sure" {
        didSet {
            previewView.accessibilityLabel = speechString
        }
    }

    // MARK: - AVFoundation Properties

    private let session = AVCaptureSession()
    private var setupResult: SessionSetupResult = .success
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], target: nil)

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        UIApplication.shared.isIdleTimerDisabled = true
        visualEffectView.accessibilityElementsHidden = true

        previewView.session = session
        previewView.didTap = {
            guard !UIAccessibilityIsVoiceOverRunning() else {
                return
            }
            let utterance = AVSpeechUtterance(string: self.speechString)
            utterance.rate = 0.55
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.speak(utterance)
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { [unowned self] granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
        default:
            setupResult = .notAuthorized
        }
        sessionQueue.async { [unowned self] in
            self.configureSession()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.session.startRunning()
            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    self.showAlert(title: "Not Authorized", message: "AVCam doesn't have permission to use the camera")
                }
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    self.showAlert(title: "Configuration Failed", message: "Unable to capture media")
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async { [unowned self] in
            if self.setupResult == .success {
                self.session.stopRunning()
            }
        }
        super.viewWillDisappear(animated)
    }

    override func prefersHomeIndicatorAutoHidden() -> Bool {
        return true
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
        alertController.addAction(okAction)

        let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .default, handler: { _ in
            guard let url = URL(string: UIApplicationOpenSettingsURLString) else { fatalError() }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        })
        alertController.addAction(settingsAction)

        present(alertController, animated: true, completion: nil)
    }

    private func configureSession() {
        if setupResult != .success {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) else {
                fatalError()
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            session.addOutput(videoOutput)

            let videoDeviceInput = try AVCaptureDeviceInput(device: captureDevice)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                let connection = videoOutput.connection(with: .video)
                connection?.videoOrientation = .portrait
            } else {
                print("Could not add video device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        }
        catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
    }

    
}
