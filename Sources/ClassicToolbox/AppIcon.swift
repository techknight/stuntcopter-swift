/// Renders StuntCopter's 'ICN#' as a modern app icon, returning `size`×`size` RGBA
/// pixels (premultiplied, 8 bits per channel).
///
/// The icon is drawn the way the System 6 Finder showed it in a window: black bits
/// on white. The ICN#'s second half is not a real silhouette mask (Blehm drew
/// something else there), so it's ignored. The artwork is scaled up by whole pixels
/// and centered on a white rounded-square plate laid out on Apple's icon grid
/// (a 1024-pixel canvas holding an 824-pixel plate), at the largest whole-pixel scale
/// that keeps every black pixel inside the plate's rounded corners. At 16 and 32
/// pixels the plate fills the canvas and the 1× artwork is clipped to its corners.
public func appIconPixels(icon: BitMap, size: Int) -> [UInt8] {
    let inset = size >= 64 ? Int((Double(size) * 100 / 1024).rounded()) : 0
    let plate = size - 2 * inset
    let radius = Double(plate) * 0.225

    // Artwork: full 32×32 at an integer scale if it fits, else the 16×16 reduction
    // System 7 made from an ICN#: CopyBits shrinking it, i.e. every other pixel.
    var art = icon
    if plate < 32 {
        let small = BitMap(bounds: Rect(top: 0, left: 0, bottom: 16, right: 16))
        for y in 0..<16 {
            for x in 0..<16 { small.pixels[y * 16 + x] = icon.pixel(2 * x, 2 * y) }
        }
        art = small
    }
    // Is a point (in canvas coordinates) inside the rounded plate?
    func insidePlate(_ x: Double, _ y: Double) -> Bool {
        let p = Double(plate), px = x - Double(inset), py = y - Double(inset)
        guard px >= 0, py >= 0, px <= p, py <= p else { return false }
        let cx = min(max(px, radius), p - radius), cy = min(max(py, radius), p - radius)
        return (px - cx) * (px - cx) + (py - cy) * (py - cy) <= radius * radius
    }

    // The largest whole-pixel scale at which every black pixel lies inside the plate.
    // At 16 and 32 px nothing smaller than 1× is possible, so the artwork is clipped.
    var k = max(1, plate / art.width)
    while k > 1 {
        let o = Double((size - art.width * k) / 2), kk = Double(k)
        let fits = (0..<art.height).allSatisfy { ay in
            (0..<art.width).allSatisfy { ax in
                art.pixel(ax, ay) == 0 || [(0.0, 0.0), (1, 0), (0, 1), (1, 1)].allSatisfy { dx, dy in
                    insidePlate(o + (Double(ax) + dx) * kk, o + (Double(ay) + dy) * kk)
                }
            }
        }
        if fits { break }
        k -= 1
    }
    let artOrigin = (size - art.width * k) / 2

    // Coverage of the rounded plate at a point, supersampled 4×4 for smooth corners.
    func plateCoverage(_ px: Int, _ py: Int) -> Double {
        var hits = 0
        for sy in 0..<4 {
            for sx in 0..<4 {
                let x = Double(px - inset) + (Double(sx) + 0.5) / 4
                let y = Double(py - inset) + (Double(sy) + 0.5) / 4
                let p = Double(plate)
                guard x >= 0, y >= 0, x < p, y < p else { continue }
                let cx = min(max(x, radius), p - radius), cy = min(max(y, radius), p - radius)
                if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius { hits += 1 }
            }
        }
        return Double(hits) / 16
    }

    var rgba = [UInt8](repeating: 0, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let ax = x - artOrigin, ay = y - artOrigin
            let black = ax >= 0 && ay >= 0 && ax < art.width * k && ay < art.height * k
                && art.pixel(ax / k, ay / k) != 0
            let i = (y * size + x) * 4
            // Everything, artwork included, is clipped to the plate (Apple's icon shape).
            let a = UInt8((plateCoverage(x, y) * 255).rounded())
            let v: UInt8 = black ? 0 : a   // premultiplied black or white
            rgba[i] = v; rgba[i + 1] = v; rgba[i + 2] = v; rgba[i + 3] = a
        }
    }
    return rgba
}
