import AppKit
import SpriteKit

enum Assets {
    static let root: URL = {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Assets"))
        }
        let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: ".")
        candidates.append(executableDir.appendingPathComponent("TheBoss_TheBoss.bundle/Assets"))
        candidates.append(executableDir.appendingPathComponent("TheBoss_TheBoss.bundle/Contents/Resources/Assets"))
        return candidates.first { fm.fileExists(atPath: $0.path) } ?? candidates[0]
    }()

    nonisolated(unsafe) private static var textures: [String: SKTexture] = [:]
    nonisolated(unsafe) private static var images: [String: NSImage] = [:]

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    static func image(_ path: String) -> NSImage? {
        if let cached = images[path] { return cached }
        guard let image = NSImage(contentsOf: url(path)) else { return nil }
        images[path] = image
        return image
    }

    static func texture(_ path: String) -> SKTexture {
        if let cached = textures[path] { return cached }
        let texture: SKTexture
        if let image = image(path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            texture = SKTexture(cgImage: cg)
        } else {
            texture = SKTexture(cgImage: PixelArt.missing())
        }
        texture.filteringMode = .nearest
        textures[path] = texture
        return texture
    }

    nonisolated(unsafe) private static var trimmedImages: [String: NSImage] = [:]

    static func trimmed(_ path: String) -> NSImage? {
        if let cached = trimmedImages[path] { return cached }
        guard let image = image(path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let box = opaqueBounds(cg), let cropped = cg.cropping(to: box) else { return image(path) }
        let result = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        trimmedImages[path] = result
        return result
    }

    static func opaqueBounds(_ cg: CGImage) -> CGRect? {
        guard let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let bytesPerPixel = cg.bitsPerPixel / 8
        let alphaOffset: Int
        switch cg.alphaInfo {
        case .first, .premultipliedFirst, .noneSkipFirst: alphaOffset = 0
        default: alphaOffset = bytesPerPixel - 1
        }
        var minX = cg.width, minY = cg.height, maxX = -1, maxY = -1
        for y in 0..<cg.height {
            for x in 0..<cg.width where bytes[y * cg.bytesPerRow + x * bytesPerPixel + alphaOffset] > 16 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let side = max(maxX - minX, maxY - minY) + 1
        let cx = (minX + maxX + 1) / 2, cy = (minY + maxY + 1) / 2
        return CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
    }

    nonisolated(unsafe) private static var paddings: [String: CGFloat] = [:]

    static func bottomPadding(_ path: String) -> CGFloat {
        if let cached = paddings[path] { return cached }
        guard let image = image(path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let bytesPerPixel = cg.bitsPerPixel / 8
        let alphaOffset: Int
        switch cg.alphaInfo {
        case .first, .premultipliedFirst, .noneSkipFirst: alphaOffset = 0
        default: alphaOffset = bytesPerPixel - 1
        }
        var padding = 0
        rows: for y in stride(from: cg.height - 1, through: 0, by: -1) {
            for x in 0..<cg.width where bytes[y * cg.bytesPerRow + x * bytesPerPixel + alphaOffset] > 0 {
                break rows
            }
            padding += 1
        }
        let value = CGFloat(padding)
        paddings[path] = value
        return value
    }

    static func frames(_ directory: String) -> [SKTexture] {
        let dir = url(directory)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.filter { $0.hasSuffix(".png") }
            .sorted { (Int($0.dropLast(4)) ?? 0) < (Int($1.dropLast(4)) ?? 0) }
            .map { texture("\(directory)/\($0)") }
    }
}

enum Facing: String, CaseIterable {
    case south, north, east, west

    var delta: (dx: Int, dy: Int) {
        switch self {
        case .south: (0, -1)
        case .north: (0, 1)
        case .east: (1, 0)
        case .west: (-1, 0)
        }
    }

    var opposite: Facing {
        switch self {
        case .south: .north
        case .north: .south
        case .east: .west
        case .west: .east
        }
    }
}
