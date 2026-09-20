import Foundation
import Vision
import ImageIO

struct ReceiptReading: Sendable {
    var merchant: String
    var amount: Int?
    var date: Date?
    var text: String
}

enum ReceiptScanner {
    static func scan(_ imageData: Data) async throws -> ReceiptReading {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            guard !lines.isEmpty else { throw ImportError.message("No readable text was found. Try a clear, well-lit receipt photo.") }
            return parse(lines: lines)
        }.value
    }

    static func parse(lines: [String]) -> ReceiptReading {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let merchant = lines.prefix(5).first { $0.rangeOfCharacter(from: .letters) != nil } ?? "Receipt"
        var candidates: [(score: Int, amount: Int)] = []
        let pattern = #"(?:\$\s*)?\d{1,3}(?:,\d{3})*\.\d{2}|(?:\$\s*)?\d+\.\d{2}"#
        let regex = try? NSRegularExpression(pattern: pattern)
        func amounts(_ line: String) -> [Int] {
            let nsLine = line as NSString
            return (regex?.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) ?? []).compactMap {
                Money.parse(nsLine.substring(with: $0.range).replacingOccurrences(of: " ", with: ""))
            }.filter { $0 > 0 }
        }
        for (index, line) in lines.enumerated() {
            let label = line.lowercased().replacingOccurrences(of: " ", with: "")
            guard !["subtotal", "sub-total", "tax", "change", "cash", "tender", "saving", "discount"].contains(where: label.contains) else { continue }
            let isTotal = label.contains("total") || label.contains("amountdue") || label.contains("balancedue")
            guard isTotal else { continue }
            let values = amounts(line)
            if let amount = values.last { candidates.append((label.contains("grand") ? 3 : 2, amount)) }
            else if index + 1 < lines.count, let amount = amounts(lines[index + 1]).last { candidates.append((1, amount)) }
        }
        let amount = candidates.sorted { $0.score == $1.score ? $0.amount > $1.amount : $0.score > $1.score }.first?.amount
        let text = lines.joined(separator: "\n")
        return ReceiptReading(merchant: merchant, amount: amount, date: date(in: text), text: text)
    }

    /// The date the shop printed, not the first thing on the receipt that looks like one.
    ///
    /// A detector run over the whole receipt takes the earliest match, and an item line will happily
    /// supply one — "GROUND BEEF 80/20" reads as a date, and it appears sixteen lines above the real
    /// one. So a match that spells out a year wins, and a date in the future is discarded: a receipt
    /// is always for something already bought.
    static func date(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let nsText = text as NSString
        let matches = detector?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let dated = matches.compactMap { match -> (date: Date, hasYear: Bool)? in
            guard let date = match.date, date < tomorrow else { return nil }
            let matched = nsText.substring(with: match.range)
            let hasYear = matched.range(of: #"\d{4}"#, options: .regularExpression) != nil
            return (date, hasYear)
        }
        return dated.first(where: \.hasYear)?.date ?? dated.first?.date
    }
}
