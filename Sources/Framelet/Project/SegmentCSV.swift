import Foundation

enum SegmentCSV {
    static let header = ["Start", "End", "Name"]

    private struct Draft {
        var start: Double
        var end: Double?
        var name: String
    }

    static func encode(_ segments: [Segment]) -> String {
        let rows = [header] + segments.map {
            [
                String(format: "%.3f", $0.sourceStart),
                String(format: "%.3f", $0.sourceEnd),
                $0.name
            ]
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func decode(_ text: String, duration: Double?) throws -> [Segment] {
        let rows = parseRows(text)
            .filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

        guard !rows.isEmpty else { return [] }

        let dataRows: ArraySlice<[String]>
        if isHeader(rows[0]) {
            dataRows = rows.dropFirst()
        } else {
            dataRows = rows[...]
        }

        let drafts = try dataRows.enumerated().compactMap { offset, row -> Draft? in
            guard let startText = row.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !startText.isEmpty else { return nil }
            let endText = row.count > 1 ? row[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let name = row.count > 2 && !row[2].isEmpty ? row[2] : "Segment \(offset + 1)"

            guard let start = parseTime(startText) else {
                throw MediaError.invalidSegmentCSV("Invalid segment start: \(startText)")
            }

            let parsedEnd = endText.isEmpty ? nil : parseTime(endText)
            if !endText.isEmpty, parsedEnd == nil {
                throw MediaError.invalidSegmentCSV("Invalid segment end: \(endText)")
            }

            return Draft(start: max(0, start), end: parsedEnd, name: name)
        }

        return try drafts.enumerated().map { index, draft in
            let fallbackEnd = drafts[safe: index + 1]?.start ?? duration
            guard let rawEnd = draft.end ?? fallbackEnd else {
                throw MediaError.invalidSegmentCSV("Marker rows need either a following marker or an open media duration.")
            }
            let end = min(max(rawEnd, draft.start), duration ?? rawEnd)
            guard end > draft.start else {
                throw MediaError.invalidSegmentCSV("Segment end must be after start: \(draft.name)")
            }

            return Segment(
                name: draft.name,
                sourceStart: draft.start,
                sourceEnd: end
            )
        }
    }

    private static func isHeader(_ row: [String]) -> Bool {
        row.first?.caseInsensitiveCompare("Start") == .orderedSame
            && (row.count < 2 || row[1].caseInsensitiveCompare("End") == .orderedSame)
            && (row.count < 3 || row[2].caseInsensitiveCompare("Name") == .orderedSame)
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)

            if character == "\"" {
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !inQuotes {
                if character == "\r", next < text.endIndex, text[next] == "\n" {
                    index = next
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }

            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private static func parseTime(_ text: String) -> Double? {
        if let seconds = Double(text) {
            return seconds
        }

        let parts = text.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let secondsText = parts.last ?? ""
        guard let seconds = Double(secondsText) else { return nil }
        let minutesIndex = parts.count - 2
        guard let minutes = Double(parts[minutesIndex]) else { return nil }
        let hours = parts.count == 3 ? Double(parts[0]) ?? .nan : 0
        guard hours.isFinite else { return nil }

        return hours * 3600 + minutes * 60 + seconds
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
