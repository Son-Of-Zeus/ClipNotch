import AppKit
import XCTest
@testable import ClipNotch

final class PasteDeliveryTests: XCTestCase {
    func testImagePastePreservesImageWithoutText() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.setColor(.red, atX: 0, y: 0)
        let formats: [(NSBitmapImageRep.FileType, NSPasteboard.PasteboardType)] = [
            (.png, .png),
            (.jpeg, NSPasteboard.PasteboardType("public.jpeg")),
            (.tiff, .tiff)
        ]

        for (format, type) in formats {
            let data = try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
            pasteboard.clearContents()
            pasteboard.setString("Previous clipboard text", forType: .string)

            PasteDelivery.writeToPasteboard(
                .image(data: data, pasteboardType: type.rawValue),
                to: pasteboard
            )

            XCTAssertEqual(pasteboard.data(forType: type), data, type.rawValue)
            XCTAssertNil(pasteboard.string(forType: .string), type.rawValue)
            XCTAssertNotNil(NSImage(pasteboard: pasteboard), type.rawValue)
        }
    }
}
