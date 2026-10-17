// Prints a QR code's module grid as rows of 0/1 (1 = dark), quiet zone trimmed.
// Uses CoreImage, so no third-party QR library is needed.
//
// Usage: swift qr_matrix.swift <text> [L|M|Q|H]
import CoreImage

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: qr_matrix.swift <text> [L|M|Q|H]") }

let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(Data(args[1].utf8), forKey: "inputMessage")
filter.setValue(args.count > 2 ? args[2] : "M", forKey: "inputCorrectionLevel")
let image = filter.outputImage!  // one pixel per module

let w = Int(image.extent.width), h = Int(image.extent.height)
var pixels = [UInt8](repeating: 0, count: w * h * 4)
CIContext().render(image, toBitmap: &pixels, rowBytes: w * 4, bounds: image.extent,
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
let rows = (0..<h).map { y in (0..<w).map { x in pixels[(y * w + x) * 4] < 128 ? "1" : "0" }.joined() }

// CoreImage adds its own margin; trim to the dark modules' bounding box.
let dark = rows.indices.filter { rows[$0].contains("1") }
let cols = (0..<w).filter { x in rows.contains { $0[$0.index($0.startIndex, offsetBy: x)] == "1" } }
for y in dark.first!...dark.last! {
    let r = rows[y]
    print(r[r.index(r.startIndex, offsetBy: cols.first!)...r.index(r.startIndex, offsetBy: cols.last!)])
}
