import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift render-icon.swift input.svg output.iconset\n", stderr)
    exit(1)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let image = NSImage(contentsOf: input), image.isValid else {
    fputs("Cannot decode SVG icon.\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

for size in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let pixels = size * multiplier
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        context.clear(rect)
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        graphics.imageInterpolation = .high
        NSGraphicsContext.current = graphics
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { exit(1) }
        let corners = [0, pixels - 1, (pixels - 1) * pixels, pixels * pixels - 1]
        guard corners.allSatisfy({ bytes[$0 * 4 + 3] == 0 }),
              bytes[((pixels / 2) * pixels + pixels / 2) * 4 + 3] > 0 else {
            fputs("Icon must have transparent corners and a visible center.\n", stderr)
            exit(1)
        }
        let suffix = multiplier == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        guard let bitmap = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else { exit(1) }
    }
}
