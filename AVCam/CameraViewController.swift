/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 View controller for camera interface.
 */

import UIKit
import Vision
import AVFoundation

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Types

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    // MARK: - Properties

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

    @IBOutlet private weak var percentLabel: UILabel!
    @IBOutlet private weak var identityLabel: UILabel!
    @IBOutlet private weak var previewView: PreviewView!

    private let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.maximumIntegerDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    private let speechPercentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.maximumIntegerDigits = 2
        return formatter
    }()

    private var isSessionRunning = false
    private let session = AVCaptureSession()
    private var setupResult: SessionSetupResult = .success
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], target: nil)

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        previewView.session = session
        previewView.didTap = {
            let string: String
            if let object = self.currentObject,
                let confidence = self.currentConfidence,
                let confidenceString = self.speechPercentFormatter.string(from: NSNumber(value: confidence)) {
                string = "\(object) \(confidenceString) Confident"
            } else {
                string = "Not Sure"
            }

            let utterance = AVSpeechUtterance(string: string)
            utterance.rate = 0.65
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.speak(utterance)
        }

        /*
         Check video authorization status. Video access is required and audio
         access is optional. If audio access is denied, audio is not recorded
         during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break

        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { [unowned self] granted in
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
                self.isSessionRunning = self.session.isRunning

            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("AVCam doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .`default`, handler: { action in
                        UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))

                    self.present(alertController, animated: true, completion: nil)
                }

            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))

                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async { [unowned self] in
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }

        super.viewWillDisappear(animated)
    }

    // MARK: - Session Management

    // Call this on the session queue.
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

    // MARK: - Vision

    let visionModel: VNCoreMLModel = {
        let mobileNetModel = MobileNet.init().model
        return try! VNCoreMLModel(for: mobileNetModel)
    }()

    lazy var visionRequest: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: self.visionModel) { request, _ in
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
            }
        }
        request.imageCropAndScaleOption = .centerCrop
        return request
    }()

    var currentFrame = 0
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        currentFrame += 1

        // Updates so fast you can't read the confidence so skipping frames for readability.
        guard currentFrame % 3 == 0 else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([self.visionRequest])
            } catch {
                print(error)
            }
        }
    }

}

