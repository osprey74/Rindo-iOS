import CoreLocation
import Foundation

/// GPX 1.1 パーサー — <trk>/<trkseg>/<trkpt> と <rte>/<rtept> を解析
final class GPXParser: NSObject, XMLParserDelegate {

    struct Result: Sendable {
        let name: String
        let trackPoints: [TrackPoint]
    }

    struct TrackPoint: Sendable {
        let coordinate: CLLocationCoordinate2D
        let elevation: Double?
    }

    private var trackPoints: [TrackPoint] = []
    private var routeName: String = ""

    // パース状態
    private var currentElement = ""
    private var currentText = ""
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentElevation: Double?
    private var inTrack = false
    private var inRoute = false
    private var parsingName = false

    func parse(data: Data) throws -> Result {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw GPXError.parseFailed(parser.parserError?.localizedDescription ?? "不明なエラー")
        }
        guard !trackPoints.isEmpty else {
            throw GPXError.noPoints
        }
        let name = routeName.isEmpty ? "インポートルート" : routeName
        return Result(name: name, trackPoints: trackPoints)
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "trk":
            inTrack = true
        case "rte":
            inRoute = true
        case "trkpt", "rtept":
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentElevation = nil
        case "name":
            parsingName = (inTrack || inRoute) && routeName.isEmpty
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "ele":
            currentElevation = Double(text)
        case "name":
            if parsingName {
                routeName = text
                parsingName = false
            }
        case "trkpt", "rtept":
            if let lat = currentLat, let lon = currentLon {
                trackPoints.append(TrackPoint(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    elevation: currentElevation
                ))
            }
            currentLat = nil
            currentLon = nil
            currentElevation = nil
        case "trk":
            inTrack = false
        case "rte":
            inRoute = false
        default:
            break
        }
    }

    enum GPXError: LocalizedError {
        case parseFailed(String)
        case noPoints

        var errorDescription: String? {
            switch self {
            case .parseFailed(let msg): "GPX 解析失敗: \(msg)"
            case .noPoints: "GPX にルートポイントが含まれていません"
            }
        }
    }
}
