import Foundation

enum MarketChartBridgeError: Error, Equatable, Sendable {
    case invalidVersion
    case oversizedPayload
    case invalidNumber
    case invalidMessage
    case invalidConfiguration
}

enum MarketChartPane: Int, Codable, CaseIterable, Sendable {
    case main = 0
    case volume = 1
    case rsi = 2
    case macd = 3
}

enum MarketChartSeriesType: String, Codable, Sendable {
    case candlestick
    case line
    case histogram
}

struct MarketChartConfiguration: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let provider: String
    let symbol: String
    let rawMIC: String
    let freshness: String
    let selectedRange: String
    let darkAppearance: Bool
}

struct MarketChartCandle: Codable, Equatable, Sendable {
    let time: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double?
}

struct MarketChartLinePoint: Codable, Equatable, Sendable {
    let time: String
    let value: Double
}

struct MarketChartLineSeries: Codable, Equatable, Sendable {
    let identifier: String
    let title: String
    let pane: MarketChartPane
    let type: MarketChartSeriesType
    let color: String
    let points: [MarketChartLinePoint]
}

struct MarketChartRenderSeriesSummary: Codable, Equatable, Sendable {
    let identifier: String
    let type: MarketChartSeriesType
    let pane: MarketChartPane
    let pointCount: Int
}

struct MarketChartRenderSummary: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let version: Int
    let series: [MarketChartRenderSeriesSummary]
}

struct MarketChartPayload: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumBars = 10_000
    static let maximumLineCount = 16
    static let maximumPointsPerLine = 10_000
    static let maximumEncodedBytes = 6 * 1_024 * 1_024
    static let maximumIdentifierLength = 64
    static let maximumTitleLength = 80
    static let maximumProviderLength = 96

    let configuration: MarketChartConfiguration
    let candles: [MarketChartCandle]
    let lines: [MarketChartLineSeries]

    init(
        configuration: MarketChartConfiguration,
        bars: [MarketOHLCVBar],
        indicators: MarketIndicatorSnapshot,
        enabledIndicators: Set<MarketIndicatorKind>
    ) throws {
        guard configuration.schemaVersion == Self.schemaVersion else { throw MarketChartBridgeError.invalidVersion }
        guard bars.count <= Self.maximumBars else { throw MarketChartBridgeError.oversizedPayload }
        try Self.validate(configuration)
        self.configuration = configuration
        candles = try bars.map { bar in
            MarketChartCandle(
                time: bar.sessionDate.description,
                open: try Self.finiteDouble(bar.open.decimal),
                high: try Self.finiteDouble(bar.high.decimal),
                low: try Self.finiteDouble(bar.low.decimal),
                close: try Self.finiteDouble(bar.close.decimal),
                volume: try bar.volume.map { try Self.finiteDouble($0.decimal) }
            )
        }
        var lines: [MarketChartLineSeries] = []
        func append(_ kind: MarketIndicatorKind, title: String, pane: MarketChartPane, color: String, points: [MarketIndicatorPoint]) throws {
            guard enabledIndicators.contains(kind) else { return }
            lines.append(.init(identifier: kind.rawValue, title: title, pane: pane, type: .line, color: color, points: try points.map { .init(time: $0.sessionDate.description, value: try Self.finiteDouble($0.value)) }))
        }
        try append(.sma20, title: "SMA 20", pane: .main, color: "#7C3AED", points: indicators.sma20)
        try append(.sma50, title: "SMA 50", pane: .main, color: "#2563EB", points: indicators.sma50)
        try append(.ema12, title: "EMA 12", pane: .main, color: "#D97706", points: indicators.ema12)
        try append(.ema26, title: "EMA 26", pane: .main, color: "#0891B2", points: indicators.ema26)
        try append(.rsi14, title: "RSI 14", pane: .rsi, color: "#9333EA", points: indicators.rsi14)
        if enabledIndicators.contains(.macd) {
            lines.append(.init(identifier: "macd", title: "MACD", pane: .macd, type: .line, color: "#2563EB", points: try indicators.macd.map { .init(time: $0.sessionDate.description, value: try Self.finiteDouble($0.macd)) }))
            lines.append(.init(identifier: "macd-signal", title: "MACD Signal", pane: .macd, type: .line, color: "#D97706", points: try indicators.macd.compactMap { point in try point.signal.map { .init(time: point.sessionDate.description, value: try Self.finiteDouble($0)) } }))
            lines.append(.init(identifier: "macd-histogram", title: "MACD Histogram", pane: .macd, type: .histogram, color: "#64748B", points: try indicators.macd.compactMap { point in try point.histogram.map { .init(time: point.sessionDate.description, value: try Self.finiteDouble($0)) } }))
        }
        if enabledIndicators.contains(.bollinger20) {
            for (identifier, title, color, value) in [
                ("bollinger-middle", "Bollinger Middle", "#64748B", { (point: MarketBollingerPoint) in point.middle }),
                ("bollinger-upper", "Bollinger Upper", "#16A34A", { (point: MarketBollingerPoint) in point.upper }),
                ("bollinger-lower", "Bollinger Lower", "#DC2626", { (point: MarketBollingerPoint) in point.lower })
            ] {
                lines.append(.init(identifier: identifier, title: title, pane: .main, type: .line, color: color, points: try indicators.bollinger20.map { .init(time: $0.sessionDate.description, value: try Self.finiteDouble(value($0))) }))
            }
        }
        self.lines = lines
        try Self.validate(self)
    }

    func withDarkAppearance(_ value: Bool) -> MarketChartPayload {
        .init(configuration: .init(schemaVersion: configuration.schemaVersion, provider: configuration.provider, symbol: configuration.symbol, rawMIC: configuration.rawMIC, freshness: configuration.freshness, selectedRange: configuration.selectedRange, darkAppearance: value), candles: candles, lines: lines)
    }

    private init(configuration: MarketChartConfiguration, candles: [MarketChartCandle], lines: [MarketChartLineSeries]) {
        self.configuration = configuration
        self.candles = candles
        self.lines = lines
    }

    init(validating configuration: MarketChartConfiguration, candles: [MarketChartCandle], lines: [MarketChartLineSeries]) throws {
        self.configuration = configuration
        self.candles = candles
        self.lines = lines
        try Self.validate(self)
    }

    static func encodedObject(_ payload: MarketChartPayload) throws -> Any {
        try validate(payload)
        let data = try JSONEncoder().encode(payload)
        guard data.count <= maximumEncodedBytes else { throw MarketChartBridgeError.oversizedPayload }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func encodedByteCount(_ payload: MarketChartPayload) throws -> Int {
        try validate(payload)
        let data = try JSONEncoder().encode(payload)
        guard data.count <= maximumEncodedBytes else { throw MarketChartBridgeError.oversizedPayload }
        return data.count
    }

    static func finiteDouble(_ value: Decimal) throws -> Double {
        let number = NSDecimalNumber(decimal: value)
        guard number != .notANumber, number.doubleValue.isFinite else { throw MarketChartBridgeError.invalidNumber }
        return number.doubleValue
    }

    private static func validate(_ configuration: MarketChartConfiguration) throws {
        guard configuration.provider.count <= maximumProviderLength,
              configuration.symbol.count <= maximumIdentifierLength,
              configuration.rawMIC.count == 4,
              configuration.rawMIC.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              configuration.freshness.count <= 32,
              configuration.selectedRange.count <= 8 else { throw MarketChartBridgeError.invalidConfiguration }
    }

    private static func validate(_ payload: MarketChartPayload) throws {
        guard payload.configuration.schemaVersion == schemaVersion else { throw MarketChartBridgeError.invalidVersion }
        try validate(payload.configuration)
        guard payload.candles.count <= maximumBars, payload.lines.count <= maximumLineCount else { throw MarketChartBridgeError.oversizedPayload }
        for candle in payload.candles {
            guard validDate(candle.time), [candle.open, candle.high, candle.low, candle.close].allSatisfy(\.isFinite), candle.volume?.isFinite != false else { throw MarketChartBridgeError.invalidNumber }
        }
        for line in payload.lines {
            guard !line.identifier.isEmpty, line.identifier.count <= maximumIdentifierLength, line.title.count <= maximumTitleLength,
                  validColor(line.color), line.points.count <= maximumPointsPerLine else { throw MarketChartBridgeError.oversizedPayload }
            guard line.points.allSatisfy({ validDate($0.time) && $0.value.isFinite }) else { throw MarketChartBridgeError.invalidNumber }
        }
    }

    private static func validDate(_ value: String) -> Bool { value.count == 10 && (try? CivilDate(canonical: value)) != nil }
    private static func validColor(_ value: String) -> Bool {
        value.count == 7 && value.first == "#" && value.dropFirst().allSatisfy(\.isHexDigit)
    }
}

enum MarketChartInboundMessage: Equatable, Sendable {
    case ready
    case visibleRange(start: CivilDate, end: CivilDate)
    case crosshair(sessionDate: CivilDate?)
    case renderSummary(MarketChartRenderSummary)
    case rendererError(category: String)

    static func decode(_ body: Any) throws -> MarketChartInboundMessage {
        guard let dictionary = body as? [String: Any], let version = dictionary["version"] as? Int,
              version == MarketChartPayload.schemaVersion, let type = dictionary["type"] as? String, type.count <= 32 else { throw MarketChartBridgeError.invalidMessage }
        switch type {
        case "ready": return .ready
        case "visibleRange":
            guard let startText = dictionary["start"] as? String, startText.count == 10,
                  let endText = dictionary["end"] as? String, endText.count == 10,
                  let start = try? CivilDate(canonical: startText), let end = try? CivilDate(canonical: endText), start <= end else { throw MarketChartBridgeError.invalidMessage }
            return .visibleRange(start: start, end: end)
        case "crosshair":
            guard let text = dictionary["date"] as? String else { return .crosshair(sessionDate: nil) }
            guard text.count == 10, let date = try? CivilDate(canonical: text) else { throw MarketChartBridgeError.invalidMessage }
            return .crosshair(sessionDate: date)
        case "renderSummary":
            guard let items = dictionary["series"] as? [[String: Any]], items.count <= MarketChartPayload.maximumLineCount + 2 else { throw MarketChartBridgeError.invalidMessage }
            let series = try items.map { item -> MarketChartRenderSeriesSummary in
                guard let identifier = item["identifier"] as? String, identifier.count <= MarketChartPayload.maximumIdentifierLength,
                      let typeText = item["seriesType"] as? String, let type = MarketChartSeriesType(rawValue: typeText),
                      let paneValue = item["pane"] as? Int, let pane = MarketChartPane(rawValue: paneValue),
                      let count = item["pointCount"] as? Int, (0...MarketChartPayload.maximumPointsPerLine).contains(count) else { throw MarketChartBridgeError.invalidMessage }
                return .init(identifier: identifier, type: type, pane: pane, pointCount: count)
            }
            return .renderSummary(.init(version: version, series: series))
        case "rendererError":
            guard let category = dictionary["category"] as? String, ["invalidPayload", "rendererFailure", "unsupportedVersion"].contains(category) else { throw MarketChartBridgeError.invalidMessage }
            return .rendererError(category: category)
        default: throw MarketChartBridgeError.invalidMessage
        }
    }
}
