import AppKit
import ClassicToolbox

/// Converts a 1-bit QuickDraw bitmap to a grayscale CGImage (black on white).
func makeCGImage(_ bm: BitMap) -> CGImage? {
    let w = bm.width, h = bm.height
    guard w > 0, h > 0 else { return nil }
    var gray = [UInt8](repeating: 255, count: w * h)
    bm.pixels.withUnsafeBufferPointer { src in
        for i in 0..<(w * h) where src[i] != 0 { gray[i] = 0 }
    }
    guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

/// The app icon (see `appIconPixels`), for the Dock when running outside an app bundle.
func makeIconImage(icon: BitMap, size: Int = 512) -> NSImage {
    let rgba = appIconPixels(icon: icon, size: size)
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                     space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
}
