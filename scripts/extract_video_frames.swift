import AppKit
import AVFoundation
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: swift extract_video_frames.swift <video> <output-dir>\n", stderr)
    exit(1)
}

let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let asset = AVAsset(url: videoURL)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true

let duration = try await asset.load(.duration)
let totalSeconds = CMTimeGetSeconds(duration)
let sampleCount = 6

for index in 0..<sampleCount {
    let seconds = totalSeconds * Double(index) / Double(max(sampleCount - 1, 1))
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    let image = try generator.copyCGImage(at: time, actualTime: nil)
    let bitmap = NSBitmapImageRep(cgImage: image)
    let data = bitmap.representation(using: .png, properties: [:])!
    let frameURL = outputURL.appendingPathComponent(String(format: "frame-%02d.png", index))
    try data.write(to: frameURL)
    print(frameURL.path)
}
