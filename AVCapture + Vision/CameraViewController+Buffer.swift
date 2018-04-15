//
//  CameraViewController+Buffer.swift
//  AVCapture + Vision
//
//  Created by Andrew Finke on 4/14/18.
//  Copyright © 2018 Apple, Inc. All rights reserved.
//

import AVFoundation
import Vision

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

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
