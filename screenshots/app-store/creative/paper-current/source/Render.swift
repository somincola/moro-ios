import CoreGraphics
import Foundation
import ImageIO
import Metal

/// Writes top-down RGBX frames to stdout. Diagnostics go to stderr so the stream can feed FFmpeg.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 8, let width = Int(args[3]), let height = Int(args[4]),
      let count = Int(args[5]), let start = Int(args[6]), let end = Int(args[7]),
      width > 0, height > 0, count > 1, start >= 0, start < end, end <= count else {
    fail("Usage: render SOURCE_DIR header width height loopFrames startFrame endFrame")
}
let directory = URL(fileURLWithPath: args[1])
guard args[2] == "header", let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else { fail("A Metal device is required.") }
let shader = try String(contentsOf: directory.appendingPathComponent("Motion.metal"), encoding: .utf8)
let library = try device.makeLibrary(source: shader, options: nil)
guard let kernel = library.makeFunction(name: "exposeFrame") else { fail("Missing film kernel.") }
let pipeline = try device.makeComputePipelineState(function: kernel)

func loadTexture(_ name: String) -> MTLTexture {
    let url = directory.appendingPathComponent(name)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("Missing image: " + url.path) }
    let w = image.width, h = image.height
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: true
    )
    descriptor.storageMode = .shared
    descriptor.usage = [.shaderRead]
    guard let texture = device.makeTexture(descriptor: descriptor),
          let space = CGColorSpace(name: CGColorSpace.sRGB) else { fail("Could not allocate texture.") }
    var pixels = Data(count: w * h * 4)
    pixels.withUnsafeMutableBytes { bytes in
        guard let address = bytes.baseAddress,
              let context = CGContext(data: address, width: w, height: h, bitsPerComponent: 8,
                  bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue) else { fail("Could not decode " + name) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: address, bytesPerRow: w * 4)
    }
    guard let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else { fail("Texture preparation failed.") }
    blit.generateMipmaps(for: texture)
    blit.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    return texture
}

let textures = ["folded-paper.png", "ink.png"].map(loadTexture)
let byteCount = width * height * 4
guard let frame = device.makeBuffer(length: byteCount, options: .storageModeShared) else { fail("Could not allocate frame.") }
var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
for index in start..<end {
    try autoreleasepool {
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { fail("Could not create render command.") }
        var phase = Float(index) / Float(count)
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(frame, offset: 0, index: 0)
        encoder.setBytes(&size, length: MemoryLayout.size(ofValue: size), index: 1)
        encoder.setBytes(&phase, length: MemoryLayout.size(ofValue: phase), index: 2)
        for (index, texture) in textures.enumerated() { encoder.setTexture(texture, index: index) }
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { fail(error.localizedDescription) }
        try FileHandle.standardOutput.write(contentsOf: Data(bytesNoCopy: frame.contents(), count: byteCount, deallocator: .none))
    }
}
