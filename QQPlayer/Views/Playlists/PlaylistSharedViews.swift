import UIKit

extension UIImage {
    func squarePlaylistCover(targetSize: CGFloat = 1024) -> UIImage {
        guard size.width > 0, size.height > 0 else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let outputSize = CGSize(width: targetSize, height: targetSize)

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            let fillScale = max(targetSize / size.width, targetSize / size.height)
            let drawSize = CGSize(width: size.width * fillScale, height: size.height * fillScale)
            let drawOrigin = CGPoint(
                x: (targetSize - drawSize.width) / 2,
                y: (targetSize - drawSize.height) / 2
            )

            draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}
