import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreparedPhoto: Sendable, Equatable {
    let data: Data
    let contentType: String
    let filename: String
    /// Small JPEG for previews, so the compose screen never decodes full-size photos on the main thread.
    let thumbnail: Data
}

enum PhotoError: Error {
    case unreadable
}

/// Re-encodes a picked photo as a downscaled JPEG with no metadata. The server resizes
/// to 1200px anyway, so this mostly saves upload time; dropping EXIF also keeps GPS
/// location out of the uploaded file (it's a private journal).
enum PhotoPreparer {
    static let maxPixelSize = 2400
    static let thumbnailPixelSize = 240
    static let jpegQuality = 0.88

    static func prepare(_ data: Data) throws -> PreparedPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw PhotoError.unreadable }
        return PreparedPhoto(
            data: try jpeg(from: source, maxPixelSize: maxPixelSize, quality: jpegQuality),
            contentType: "image/jpeg",
            filename: "photo.jpg",
            thumbnail: try jpeg(from: source, maxPixelSize: thumbnailPixelSize, quality: 0.8)
        )
    }

    private static func jpeg(from source: CGImageSource, maxPixelSize: Int, quality: Double) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // bake in EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoError.unreadable
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoError.unreadable
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.unreadable }
        return output as Data
    }
}
