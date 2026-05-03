import CoreLocation
import Foundation

/// Valhalla encoded polyline デコーダ（precision 6）
enum PolylineDecoder {
    static func decode(_ encoded: String, precision: Double = 1e6) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0

        while index < bytes.count {
            lat += decodeValue(bytes: bytes, index: &index)
            lon += decodeValue(bytes: bytes, index: &index)
            coordinates.append(CLLocationCoordinate2D(
                latitude: Double(lat) / precision,
                longitude: Double(lon) / precision
            ))
        }
        return coordinates
    }

    private static func decodeValue(bytes: [UInt8], index: inout Int) -> Int {
        var result = 0
        var shift = 0
        while index < bytes.count {
            let byte = Int(bytes[index]) - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20 { break }
        }
        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }
}
