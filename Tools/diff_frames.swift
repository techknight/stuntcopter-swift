// Overlays an emulator screenshot (512×342) of the original with a port frame
// (503×310 PBM, placed at the window origin 4,30) and writes a color diff:
// black = both, red = original only, blue = port only.
//
//   swift Tools/diff_frames.swift <original.png> <port.pbm> <out.png> [top] [bottom] [scale] [x y]
// Optional top/bottom restrict the comparison (and the output) to the port frame's rows;
// x y give where the port frame sits on the 512×342 screen (default: the game window, 4 30).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let W = img.width, H = img.height
var orig = [UInt8](repeating: 0, count: W * H)
CGContext(data: &orig, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))

let pbm = [UInt8](try Data(contentsOf: URL(fileURLWithPath: a[2])))
var p = 3, fields: [Int] = []
while fields.count < 2 {
    var s = ""
    while pbm[p] == 0x20 || pbm[p] == 0x0A { p += 1 }
    while pbm[p] != 0x20 && pbm[p] != 0x0A { s.append(Character(UnicodeScalar(pbm[p]))); p += 1 }
    fields.append(Int(s)!)
}
p += 1
let (pw, ph) = (fields[0], fields[1])
let rowBytes = (pw + 7) / 8
func port(_ x: Int, _ y: Int) -> Bool { (pbm[p + y * rowBytes + x / 8] >> (7 - UInt8(x % 8))) & 1 == 1 }

let top = a.count > 4 ? Int(a[4])! : 0, bottom = a.count > 5 ? Int(a[5])! : ph
let (ox, oy) = a.count > 8 ? (Int(a[7])!, Int(a[8])!) : (4, 30)
var rgba = [UInt8](repeating: 255, count: pw * ph * 4)
var diffs = 0
for y in top..<bottom {
    for x in 0..<pw {
        let o = orig[(y + oy) * W + (x + ox)] < 128, q = port(x, y)
        let i = (y * pw + x) * 4
        switch (o, q) {
        case (true, true): rgba[i] = 0; rgba[i + 1] = 0; rgba[i + 2] = 0
        case (true, false): rgba[i] = 230; rgba[i + 1] = 0; rgba[i + 2] = 0; diffs += 1
        case (false, true): rgba[i] = 0; rgba[i + 1] = 90; rgba[i + 2] = 255; diffs += 1
        default: break
        }
    }
}
print("differing pixels in rows \(top)..<\(bottom): \(diffs)")
let k = a.count > 6 ? Int(a[6])! : 1
let (ow, oh) = (pw * k, (bottom - top) * k)
var out = [UInt8](repeating: 255, count: ow * oh * 4)
for y in 0..<oh {
    for x in 0..<ow {
        let si = ((top + y / k) * pw + x / k) * 4, di = (y * ow + x) * 4
        out[di] = rgba[si]; out[di + 1] = rgba[si + 1]; out[di + 2] = rgba[si + 2]
    }
}
let cg = CGImage(width: ow, height: oh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ow * 4,
                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                 provider: CGDataProvider(data: Data(out) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[3]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil)
CGImageDestinationFinalize(dest)
