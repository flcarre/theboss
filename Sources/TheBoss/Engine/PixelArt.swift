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

enum ProceduralArt {
    nonisolated(unsafe) private static var cache: [String: SKTexture] = [:]
    nonisolated(unsafe) private static var images: [String: NSImage] = [:]

    static func cached(_ key: String, _ make: () -> PixelCanvas) -> SKTexture {
        if let texture = cache[key] { return texture }
        let texture = make().texture
        cache[key] = texture
        return texture
    }

    static func image(_ key: String, scale: Int = 1, _ make: () -> PixelCanvas) -> NSImage {
        if let image = images[key] { return image }
        let canvas = make()
        let image = NSImage(cgImage: canvas.cgImage, size: NSSize(width: canvas.width * scale, height: canvas.height * scale))
        images[key] = image
        return image
    }

    static func noise(_ x: Int, _ y: Int, _ seed: Int) -> Int {
        var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ seed &* 2147483647)
        h = (h ^ (h >> 13)) &* 1274126177
        return Int(h ^ (h >> 16)) & 0xFFFF
    }

    static func parquet(variant: Int) -> SKTexture {
        cached("parquet\(variant)") {
            var c = PixelCanvas(width: 64, height: 64)
            let shades: [UInt32] = [0xB9783F, 0xA9693A, 0xC5864A, 0xAE7041]
            for row in 0..<4 {
                let y0 = row * 16
                let offset = ((row + variant) % 2) * 32 + (variant * 11 + row * 7) % 16
                for x in 0..<64 {
                    let plank = ((x + offset) / 48)
                    let base = shades[(plank + row + variant) % shades.count]
                    for y in y0..<(y0 + 16) {
                        var color = RGBA(base)
                        let n = noise(x + variant * 64, y, 7) % 100
                        if n < 7 { color = RGBA(PixelArt.shade(base, 0.86)) }
                        if (y - y0) == 5 || (y - y0) == 11, noise(x / 6, y, plank) % 3 == 0 { color = RGBA(PixelArt.shade(base, 0.9)) }
                        c.set(x, y, color)
                    }
                    if (x + offset) % 48 == 0 {
                        for y in y0..<(y0 + 16) { c.set(x, y, RGBA(0x5A3420)) }
                    }
                }
                for x in 0..<64 { c.set(x, y0 + 15, RGBA(0x6B3F25)) }
                for x in 0..<64 where noise(x, y0, 3) % 5 != 0 { c.set(x, y0, RGBA(0xD3965A)) }
            }
            return c
        }
    }

    static func carpet(variant: Int) -> SKTexture {
        cached("carpet\(variant)") {
            var c = PixelCanvas(width: 64, height: 64)
            for y in 0..<64 {
                for x in 0..<64 {
                    let tile = ((x / 32) + (y / 32) + variant) % 2
                    let base: UInt32 = tile == 0 ? 0x5B6B8C : 0x55647F
                    let n = noise(x + variant * 64, y, 11) % 100
                    var color = base
                    if n < 18 { color = PixelArt.shade(base, 0.88) }
                    if n > 92 { color = 0x6E7FA3 }
                    if tile == 0, (x + y) % 8 == 0 { color = PixelArt.shade(base, 0.92) }
                    if x % 32 == 0 || y % 32 == 0 { color = 0x46536C }
                    c.set(x, y, RGBA(color))
                }
            }
            return c
        }
    }

    static let bubbleShape = [
        "..XXXXXXXXXXXXXXXXXX..",
        ".XWWWWWWWWWWWWWWWWWWX.",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XWWWWWWWWWWWWWWWWWWWWX",
        "XSWWWWWWWWWWWWWWWWWWSX",
        ".XSSSSSWWWWWSSSSSSSSX.",
        "..XXXXXXSWWSXXXXXXXX..",
        ".......XSWSX..........",
        "........XSX...........",
        ".........X............",
    ]

    static func bubble(_ glyph: [String], color: UInt32) -> PixelCanvas {
        var c = PixelCanvas(width: 22, height: 18)
        for (y, row) in bubbleShape.enumerated() {
            for (x, ch) in row.enumerated() {
                switch ch {
                case "X": c.set(x, y, PixelArt.outline)
                case "W": c.set(x, y, RGBA(0xFFF6EC))
                case "S": c.set(x, y, RGBA(0xD9CFC2))
                default: break
                }
            }
        }
        let originX = (22 - (glyph.first?.count ?? 0)) / 2
        for (y, row) in glyph.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" { c.set(originX + x, 2 + y, RGBA(color)) }
            for (x, ch) in row.enumerated() where ch == "o" { c.set(originX + x, 2 + y, RGBA(PixelArt.shade(color, 0.7))) }
        }
        return c
    }

    static var exclamation: SKTexture {
        cached("bubble!") {
            bubble(["..##..", ".####.", ".####.", ".####.", "..##..", "..##..", "..oo..", "......", "..##..", "..oo.."], color: 0xF0532E)
        }
    }

    static var sleeping: SKTexture {
        cached("bubbleZ") {
            bubble(["......#####", ".........#.", "........#..", ".......####", "####.......", "..#........", ".#.........", "####......."], color: 0x4F7BD9)
        }
    }

    static func sparkle(frame: Int) -> SKTexture {
        cached("sparkle\(frame)") {
            var c = PixelCanvas(width: 48, height: 48)
            let radius = 4 + frame * 4
            let colors: [UInt32] = [0xFFF6EC, 0xF5B942, 0x7FD8FF]
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4 + Double(frame) * 0.3
                let x = 24 + Int(Double(radius) * cos(angle)), y = 24 + Int(Double(radius) * sin(angle))
                let color = RGBA(colors[(i + frame) % colors.count], alpha: frame > 4 ? 140 : 255)
                c.rect(x - 1, y, 3, 1, color)
                c.rect(x, y - 1, 1, 3, color)
            }
            return c
        }
    }

    static func smoke(frame: Int) -> SKTexture {
        cached("smoke\(frame)") {
            var c = PixelCanvas(width: 48, height: 48)
            let radius = Double(6 + frame * 3)
            for y in 0..<48 {
                for x in 0..<48 {
                    for puff in 0..<3 {
                        let cx = 24.0 + Double(puff - 1) * radius * 0.7, cy = 30.0 - Double(frame * 2) - Double(puff % 2) * 4
                        let d = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)).squareRoot()
                        if d < radius * 0.55 {
                            let alpha = UInt8(max(0, 200 - frame * 32))
                            c.set(x, y, RGBA(d < radius * 0.35 ? 0xE9E4F7 : 0xB9B0D6, alpha: alpha))
                        }
                    }
                }
            }
            return c
        }
    }

    static var sweat: SKTexture {
        cached("sweat") {
            glyph(["...X...", "..XwX..", ".Xw#oX.", "Xw##ooX", "X####oX", "X###ooX", ".XoooX.", "..XXX.."], color: 0x7FC8F0, size: 9)
        }
    }

    static func crack(frame: Int) -> SKTexture {
        cached("crack\(frame)") {
            var c = PixelCanvas(width: 56, height: 56)
            let reach = 8 + frame * 7
            let colors: [UInt32] = [0xFFF6EC, 0xF5B942, 0xF0532E]
            for i in 0..<10 {
                let angle = Double(i) * .pi / 5 + 0.2
                for r in stride(from: max(2, reach - 10), to: reach, by: 1) {
                    let x = 28 + Int(Double(r) * cos(angle)), y = 28 + Int(Double(r) * sin(angle))
                    c.set(x, y, RGBA(colors[(i + frame) % colors.count], alpha: frame > 3 ? 120 : 255))
                }
            }
            if frame < 3 { c.rect(25, 25, 6, 6, RGBA(0xFFF6EC)) }
            return c
        }
    }

    static func glyph(_ rows: [String], color: UInt32, size: Int = 16) -> PixelCanvas {
        var c = PixelCanvas(width: size, height: size)
        let ox = (size - (rows.first?.count ?? 0)) / 2, oy = (size - rows.count) / 2
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                switch ch {
                case "#": c.set(ox + x, oy + y, RGBA(color))
                case "X": c.set(ox + x, oy + y, PixelArt.outline)
                case "o": c.set(ox + x, oy + y, RGBA(PixelArt.shade(color, 0.7)))
                case "w": c.set(ox + x, oy + y, RGBA(0xFFF6EC))
                default: break
                }
            }
        }
        return c
    }

    static var closeIcon: NSImage {
        image("close", scale: 2) {
            glyph(["XX......XX", "X#X....X#X", ".X#X..X#X.", "..X#XX#X..", "...X##X...", "...X##X...", "..X#XX#X..", ".X#X..X#X.", "X#X....X#X", "XX......XX"], color: 0xF0532E)
        }
    }

    static var backIcon: NSImage {
        image("back", scale: 2) {
            glyph(["....XX......", "...X#X......", "..X##XXXXXX.", ".X########X.", "X#########oX", ".X###oooooX.", "..X#oXXXXX..", "...XoX......", "....XX......"], color: 0xF5B942)
        }
    }

    static var searchIcon: NSImage {
        image("search", scale: 2) {
            glyph(["..XXXX....", ".XwwwwX...", "Xww##wwX..", "Xw#..#wX..", "Xw#..#wX..", ".Xw##wX...", "..XXXXoX..", "......XoX.", ".......XoX", "........XX"], color: 0x7FB3E0)
        }
    }

    static var bellIcon: NSImage {
        image("bell", scale: 2) {
            glyph(["....XX....", "...X##X...", "..X####X..", ".X######X.", ".X######X.", ".X######X.", "X########X", "XooooooooX", ".XXXXXXXX.", "....XX...."], color: 0xF5B942)
        }
    }
}
