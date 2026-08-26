import Foundation

enum MarketChartBridgeError: Error, Equatable, Sendable {
    case invalidVersion
    case oversizedPayload
    case invalidNumber
    case invalidMessage
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
    let pane: Int
    let color: String
    let points: [MarketChartLinePoint]
}

struct MarketChartPayload: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumBars = 10_000

    let configuration: MarketChartConfiguration
    let candles: [MarketChartCandle]
    let lines: [MarketChartLineSeries]

    init(
        configuration: MarketChartConfiguration,
        bars: [MarketOHLCVBar],
        indicators: MarketIndicatorSnapshot,
        enabledIndicators: Set<MarketIndicatorKind>
    ) throws {
        guard configuration.schemaVersion == Self.schemaVersion else {
            throw MarketChartBridgeError.invalidVersion
        }
        guard bars.count <= Self.maximumBars else { throw MarketChartBridgeError.oversizedPayload }
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
        func append(
            _ kind: MarketIndicatorKind,
            title: String,
            pane: Int,
            color: String,
            points: [MarketIndicatorPoint]
        ) throws {
            guard enabledIndicators.contains(kind) else { return }
            lines.append(.init(
                identifier: kind.rawValue,
                title: title,
                pane: pane,
                color: color,
                points: try points.map { .init(time: $0.sessionDate.description, value: try Self.finiteDouble($0.value)) }
            ))
        }
        try append(.sma20, title: "SMA 20", pane: 0, color: "#7C3AED", points: indicators.sma20)
        try append(.sma50, title: "SMA 50", pane: 0, color: "#2563EB", points: indicators.sma50)
        try append(.ema12, title: "EMA 12", pane: 0, color: "#D97706", points: indicators.ema12)
        try append(.ema26, title: "EMA 26", pane: 0, color: "#0891B2", points: indicators.ema26)
        try append(.rsi14, title: "RSI 14", pane: 1, color: "#9333EA", points: indicators.rsi14)
        if enabledIndicators.contains(.macd) {
            lines.append(.init(
                identifier: "macd",
                title: "MACD",
                pane: 2,
                color: "#2563EB",
                points: try indicators.macd.map { .init(time: $0.sessionDate.description, value: try Self.finiteDouble($0.macd)) }
            ))
            lines.append(.init(
                identifier: "macd-signal",
                title: "MACD Signal",
                pane: 2,
                color: "#D97706",
                points: try indicators.macd.compactMap { point in
                    try point.signal.map { .init(time: point.sessionDate.description, value: try Self.finiteDouble($0)) }
                }
            ))
            lines.append(.init(
                identifier: "macd-histogram",
                title: "MACD Histogram",
                pane: 2,
                color: "#64748B",
                points: try indicators.macd.compactMap { point in
                    try point.histogram.map { .init(time: point.sessionDate.description, value: try Self.finiteDouble($0)) }
                }
            ))
        }
        if enabledIndicators.contains(.bollinger20) {
            for (identifier, title, color, value) in [
                ("bollinger-middle", "Bollinger Middle", "#64748B", { (point: MarketBollingerPoint) in point.middle }),
                ("bollinger-upper", "Bollinger Upper", "#16A34A", { (point: MarketBollingerPoint) in point.upper }),
                ("bollinger-lower", "Bollinger Lower", "#DC2626", { (point: MarketBollingerPoint) in point.lower })
            ] {
                lines.append(.init(
                    identifier: identifier,
                    title: title,
                    pane: 0,
                    color: color,
                    points: try indicators.bollinger20.map { .init(time: $0.sessionDate.description, value: try Self.finiteDouble(value($0))) }
                ))
            }
        }
        self.lines = lines
    }

    static func encodedObject(_ payload: MarketChartPayload) throws -> Any {
        let data = try JSONEncoder().encode(payload)
        return try JSONSerialization.jsonObject(with: data)
    }

    static func finiteDouble(_ value: Decimal) throws -> Double {
        let number = NSDecimalNumber(decimal: value)
        guard number != .notANumber else { throw MarketChartBridgeError.invalidNumber }
        let result = number.doubleValue
        guard result.isFinite else { throw MarketChartBridgeError.invalidNumber }
        return result
    }
}

enum MarketChartInboundMessage: Equatable, Sendable {
    case ready
    case visibleRange(start: String, end: String)
    case crosshair(sessionDate: String?)
    case rendererError(category: String)

    static func decode(_ body: Any) throws -> MarketChartInboundMessage {
        guard let dictionary = body as? [String: Any],
              let version = dictionary["version"] as? Int,
              version == MarketChartPayload.schemaVersion,
              let type = dictionary["type"] as? String else {
            throw MarketChartBridgeError.invalidMessage
        }
        switch type {
        case "ready": return .ready
        case "visibleRange":
            guard let start = dictionary["start"] as? String,
                  let end = dictionary["end"] as? String else { throw MarketChartBridgeError.invalidMessage }
            return .visibleRange(start: start, end: end)
        case "crosshair":
            return .crosshair(sessionDate: dictionary["date"] as? String)
        case "rendererError":
            guard let category = dictionary["category"] as? String,
                  ["invalidPayload", "rendererFailure", "unsupportedVersion"].contains(category) else {
                throw MarketChartBridgeError.invalidMessage
            }
            return .rendererError(category: category)
        default:
            throw MarketChartBridgeError.invalidMessage
        }
    }
}
