import UIKit

/// ナビゲーション用矢印画像をコード生成
/// 鋭利な三角形、底辺が内側にカーブ、紺色(#1925B2) + 白縁
enum ArrowImage {
    static let size: CGFloat = 32
    static let fillColor = UIColor(red: 0x19/255, green: 0x25/255, blue: 0xB2/255, alpha: 1) // #1925B2
    static let strokeColor = UIColor.white
    static let strokeWidth: CGFloat = 2

    /// 上向き矢印の UIImage を生成（@3x 相当のスケール）
    static func generate(scale: CGFloat = 3) -> UIImage {
        let pixelSize = size * scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize))

        let image = renderer.image { context in
            let ctx = context.cgContext
            let w = pixelSize
            let h = pixelSize
            let margin = strokeWidth * scale

            // 横幅を 2/3 に絞って鋭角化
            let inset = w / 6
            // 頂点（上）
            let top = CGPoint(x: w / 2, y: margin)
            // 左下
            let bottomLeft = CGPoint(x: inset + margin, y: h - margin)
            // 右下
            let bottomRight = CGPoint(x: w - inset - margin, y: h - margin)
            // 底辺の内側カーブの制御点
            let curveControl = CGPoint(x: w / 2, y: h * 0.6)

            let path = UIBezierPath()
            // 左下から頂点へ
            path.move(to: bottomLeft)
            path.addLine(to: top)
            // 頂点から右下へ
            path.addLine(to: bottomRight)
            // 右下から左下へ（内側にへこむカーブ）
            path.addQuadCurve(to: bottomLeft, controlPoint: curveControl)
            path.close()

            // 白縁
            ctx.setLineWidth(strokeWidth * scale)
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.addPath(path.cgPath)
            ctx.strokePath()

            // 紺色塗りつぶし
            ctx.setFillColor(fillColor.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }

        return image.withRenderingMode(.alwaysOriginal)
    }
}
