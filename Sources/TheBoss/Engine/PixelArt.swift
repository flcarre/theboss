import AppKit
import SpriteKit

struct RGBA: Hashable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(_ hex: UInt32, alpha: UInt8 = 255) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
        a = alpha
    }

    static let clear = RGBA(0, alpha: 0)

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

struct PixelCanvas {
    let width: Int
    let height: Int
    private(set) var pixels: [RGBA]

    init(width: Int, height: Int, fill: RGBA = .clear) {
        self.width = width
        self.height = height
        pixels = Array(repeating: fill, count: width * height)
    }

    mutating func set(_ x: Int, _ y: Int, _ color: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[y * width + x] = color
    }

    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBA) {
        for yy in y..<(y + h) { for xx in x..<(x + w) { set(xx, yy, color) } }
    }

    var cgImage: CGImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for pixel in pixels {
            let alpha = UInt16(pixel.a)
            bytes.append(UInt8(UInt16(pixel.r) * alpha / 255))
            bytes.append(UInt8(UInt16(pixel.g) * alpha / 255))
            bytes.append(UInt8(UInt16(pixel.b) * alpha / 255))
            bytes.append(pixel.a)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    var texture: SKTexture {
        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .nearest
        return texture
    }
}

struct WallStyle {
    var trim: UInt32
    var trimLight: UInt32
    var paper: UInt32
    var paperStripe: UInt32
    var rail: UInt32
    var railLight: UInt32
    var railShadow: UInt32
    var panel: UInt32
    var panelLine: UInt32
    var panelLight: UInt32
    var base: UInt32
    var baseDark: UInt32

    static let office = WallStyle(trim: 0x2B2547, trimLight: 0x4E4580, paper: 0xEADFC8, paperStripe: 0xDCCDAE,
                                  rail: 0xC9832A, railLight: 0xF5B942, railShadow: 0x9A6420,
                                  panel: 0x9A6420, panelLine: 0x6A4218, panelLight: 0xC9832A,
                                  base: 0x6A4218, baseDark: 0x3A2410)
    static let openSpace = WallStyle(trim: 0x2B2547, trimLight: 0x4E4580, paper: 0xD9DEEA, paperStripe: 0xC7CEDF,
                                     rail: 0x7A6FB0, railLight: 0xB9B0D6, railShadow: 0x4E4580,
                                     panel: 0x4E4580, panelLine: 0x3A3260, panelLight: 0x7A6FB0,
                                     base: 0x3A3260, baseDark: 0x1E1A33)
}

enum PixelArt {
    static let outline = RGBA(0x2A1840)

    static func missing() -> CGImage {
        var canvas = PixelCanvas(width: 16, height: 16)
        for y in 0..<16 { for x in 0..<16 { canvas.set(x, y, (x / 4 + y / 4) % 2 == 0 ? RGBA(0xFF00FF) : RGBA(0x000000)) } }
        return canvas.cgImage
    }

    static func wall(_ style: WallStyle, width: Int = 64, height: Int = 128) -> SKTexture {
        var c = PixelCanvas(width: width, height: height)
        c.rect(0, 0, width, 8, RGBA(style.trim))
        c.rect(0, 7, width, 1, RGBA(style.trimLight))
        c.rect(0, 8, width, 76, RGBA(style.paper))
        for x in stride(from: 6, to: width, by: 16) {
            c.rect(x, 8, 2, 76, RGBA(style.paperStripe))
        }
        for y in stride(from: 16, to: 82, by: 12) {
            for x in stride(from: (y / 12) % 2 == 0 ? 14 : 2, to: width, by: 16) { c.set(x, y, RGBA(style.paperStripe)) }
        }
        c.rect(0, 84, width, 1, RGBA(style.railLight))
        c.rect(0, 85, width, 2, RGBA(style.rail))
        c.rect(0, 87, width, 1, RGBA(style.railShadow))
        c.rect(0, 88, width, 32, RGBA(style.panel))
        for x in stride(from: 0, to: width, by: 32) {
            c.rect(x + 3, 91, 26, 1, RGBA(style.panelLight))
            c.rect(x + 3, 91, 1, 25, RGBA(style.panelLight))
            c.rect(x + 3, 116, 26, 1, RGBA(style.panelLine))
            c.rect(x + 28, 91, 1, 26, RGBA(style.panelLine))
        }
        c.rect(0, 120, width, 6, RGBA(style.base))
        c.rect(0, 126, width, 2, RGBA(style.baseDark))
        return c.texture
    }

    static func shadow(width: Int, height: Int) -> SKTexture {
        var c = PixelCanvas(width: width, height: height)
        let rx = Double(width) / 2, ry = Double(height) / 2
        for y in 0..<height {
            for x in 0..<width {
                let dx = (Double(x) + 0.5 - rx) / rx, dy = (Double(y) + 0.5 - ry) / ry
                if dx * dx + dy * dy <= 1 { c.set(x, y, RGBA(0x1E1A33, alpha: 90)) }
            }
        }
        return c.texture
    }

    static func edge(width: Int, height: Int) -> SKTexture {
        var c = PixelCanvas(width: width, height: height, fill: RGBA(0x2B2547))
        c.rect(0, 0, width, 1, RGBA(0x4E4580))
        return c.texture
    }

    static func glow(width: Int, height: Int, color: UInt32) -> SKTexture {
        var c = PixelCanvas(width: width, height: height)
        let rx = Double(width) / 2, ry = Double(height) / 2
        for y in 0..<height {
            for x in 0..<width {
                let dx = (Double(x) + 0.5 - rx) / rx, dy = (Double(y) + 0.5 - ry) / ry
                let d = dx * dx + dy * dy
                if d <= 1 { c.set(x, y, RGBA(color, alpha: d < 0.35 ? 70 : d < 0.7 ? 45 : 22)) }
            }
        }
        return c.texture
    }

    static func doormat() -> SKTexture {
        var c = PixelCanvas(width: 64, height: 40, fill: RGBA(0x5C4033))
        c.rect(0, 0, 64, 1, outline)
        c.rect(0, 39, 64, 1, outline)
        c.rect(0, 0, 1, 40, outline)
        c.rect(63, 0, 1, 40, outline)
        for y in stride(from: 4, to: 36, by: 4) { c.rect(4, y, 56, 1, RGBA(0x7A5A45)) }
        c.rect(3, 3, 58, 1, RGBA(0xC9832A))
        c.rect(3, 36, 58, 1, RGBA(0x3A2410))
        return c.texture
    }

    static func statusLight(_ color: UInt32) -> SKTexture {
        var c = PixelCanvas(width: 10, height: 10)
        let shape = ["..XXXXXX..", ".XooooooX.", "XoohhoooOX", "XohhooooOX", "XoooooooOX", "XoooooooOX", "XooooooOOX", "XooooOOOOX", ".XOOOOOOX.", "..XXXXXX.."]
        for (y, row) in shape.enumerated() {
            for (x, ch) in row.enumerated() {
                switch ch {
                case "X": c.set(x, y, outline)
                case "o": c.set(x, y, RGBA(color))
                case "O": c.set(x, y, RGBA(shade(color, 0.7)))
                case "h": c.set(x, y, RGBA(0xFFF6EC))
                default: break
                }
            }
        }
        return c.texture
    }

    static func shade(_ hex: UInt32, _ factor: Double) -> UInt32 {
        let r = UInt32(Double((hex >> 16) & 0xFF) * factor)
        let g = UInt32(Double((hex >> 8) & 0xFF) * factor)
        let b = UInt32(Double(hex & 0xFF) * factor)
        return (r << 16) | (g << 8) | b
    }
}
