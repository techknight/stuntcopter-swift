// Measures StuntCopter's loop rate in a running emulator by tracking the hay
// wagon, which moves exactly 1 pixel per animation loop at WALK speed.
//
//   swift Tools/measure_wagon.swift <frames.tsv>
//
// frames.tsv lines: "<unix time> <path to window screenshot>". Screenshots are of the
// emulator window; the Mac screen is located by its white menu bar.
import CoreGraphics
import Foundation
import ImageIO

struct Gray {
    let w: Int, h: Int, px: [UInt8]
    init?(_ path: String) {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        w = img.width; h = img.height
        var buf = [UInt8](repeating: 0, count: w * h)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        px = buf
    }
    subscript(x: Int, y: Int) -> UInt8 { px[y * w + x] }
}

let lines = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).split(separator: "\n")
var samples: [(t: Double, x: Double)] = []
var geometry: (left: Double, top: Double, scale: Double)?

for line in lines {
    let parts = line.split(separator: " ", maxSplits: 1)
    guard parts.count == 2, let t = Double(parts[0]), let g = Gray(String(parts[1])) else { continue }
    if geometry == nil {
        // Screen top: first bright row below the toolbar at the horizontal center.
        var top = g.h / 8
        while top < g.h && g[g.w / 2, top] < 200 { top += 1 }
        // Screen width: extent of the bright menu bar, a few pixels below its top.
        let row = top + 12
        var l = 0, r = g.w - 1
        while l < g.w && g[l, row] < 200 { l += 1 }
        while r > 0 && g[r, row] < 200 { r -= 1 }
        let scale = Double(r - l + 1) / 512
        geometry = (Double(l), Double(top), scale)
        print(String(format: "screen at x=%d y=%d, %.3f capture px per Mac px", l, top, scale))
    }
    let (left, top, s) = geometry!
    // Wagon band: the wagon covers global y 261..<283 (window top 30 + local 231..<253); stay
    // below where a copter at its lowest could dangle the stuntman (down to global 266).
    let y0 = Int(top + 267 * s), y1 = Int(top + 281 * s)
    var sum = 0.0, n = 0.0
    for y in y0...y1 {
        for x in Int(left)..<Int(left + 512 * s) where g[x, y] < 100 {
            sum += Double(x); n += 1
        }
    }
    guard n > 0 else { continue }
    samples.append((t, ((sum / n) - left) / s))
}

// Fit a line through consecutive samples, skipping wraparounds (the wagon jumps left).
var segments: [[(t: Double, x: Double)]] = [[]]
for s in samples {
    if let last = segments[segments.count - 1].last, s.x < last.x - 20 { segments.append([]) }
    segments[segments.count - 1].append(s)
}
var num = 0.0, den = 0.0
for seg in segments where seg.count >= 3 {
    let mt = seg.map(\.t).reduce(0, +) / Double(seg.count)
    let mx = seg.map(\.x).reduce(0, +) / Double(seg.count)
    for s in seg {
        num += (s.t - mt) * (s.x - mx)
        den += (s.t - mt) * (s.t - mt)
    }
}
for s in samples { print(String(format: "t=%.2f  wagon centroid x=%.1f", s.t - samples[0].t, s.x)) }
if den > 0 { print(String(format: "wagon speed: %.2f px/s  →  %.2f loops/s (attract mode)", num / den, num / den)) }
