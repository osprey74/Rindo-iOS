import SwiftUI

/// iPhone Duo などの折りたたみ端末で、半開き時に画面を分割する折り目（ReservedRegion の division）を扱う
enum FoldLayout {
    /// GeometryProxy のローカル座標系で、現在有効な折り目の矩形を返す（折り目がなければ nil）
    static func activeFold(in proxy: GeometryProxy) -> CGRect? {
        #if DEBUG
        if let simulated = simulatedFold(in: proxy.size) {
            return simulated
        }
        #endif
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                .first(where: \.isActive)?
                .frame
        }
        return nil
    }

    /// 縦方向の折り目（左右に分割）か
    static func isVertical(_ fold: CGRect) -> Bool {
        fold.height > fold.width
    }

    #if DEBUG
    /// 起動引数 `-debugSimulatedFold vertical|horizontal` で、ビュー中央に擬似的な折り目を置く
    /// （シミュレータのスクリーンショットでは半開きを再現できないため、レイアウト検証用）
    /// 実機の折り目は内側ディスプレイの長辺を二分するため、vertical は横長、horizontal は縦長の画面でのみ有効にする
    private static func simulatedFold(in size: CGSize) -> CGRect? {
        let thickness: CGFloat = 32
        switch UserDefaults.standard.string(forKey: "debugSimulatedFold") {
        case "vertical" where size.width > size.height:
            return CGRect(x: (size.width - thickness) / 2, y: 0, width: thickness, height: size.height)
        case "horizontal" where size.height > size.width:
            return CGRect(x: 0, y: (size.height - thickness) / 2, width: size.width, height: thickness)
        default:
            return nil
        }
    }
    #endif
}
