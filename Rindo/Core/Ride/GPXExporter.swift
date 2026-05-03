import Foundation

/// RideLog から GPX 1.1 XML を生成
enum GPXExporter {

    static func generate(from ride: RideLog) -> String {
        let track = ride.decodedTrack
        let name = xmlEscape(ride.displayName)
        let iso = ISO8601DateFormatter()

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Rindo"
             xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(name)</name>
            <time>\(iso.string(from: ride.startedAt))</time>
          </metadata>
          <trk>
            <name>\(name)</name>
            <trkseg>

        """

        for point in track {
            guard point.count >= 4 else { continue }
            let lon = point[0]
            let lat = point[1]
            let ele = point[2]
            let epoch = point[3]
            let time = iso.string(from: Date(timeIntervalSince1970: epoch))

            gpx += "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\">\n"
            gpx += "        <ele>\(String(format: "%.1f", ele))</ele>\n"
            gpx += "        <time>\(time)</time>\n"

            if point.count >= 5 {
                let speed = point[4]
                gpx += "        <extensions><speed>\(String(format: "%.2f", speed))</speed></extensions>\n"
            }

            gpx += "      </trkpt>\n"
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        return gpx
    }

    /// GPX を一時ファイルに書き出してURLを返す
    static func writeToTempFile(from ride: RideLog) throws -> URL {
        let gpxString = generate(from: ride)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let filename = "Rindo_\(formatter.string(from: ride.startedAt)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try gpxString.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
