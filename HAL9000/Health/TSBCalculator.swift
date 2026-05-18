import Foundation

struct TSBPoint: Equatable {
    let date: Date
    let ctl: Double
    let atl: Double
    let tsb: Double
}

struct TSBResult: Equatable {
    let current: TSBPoint
    let history: [TSBPoint]
}

enum TSBState: Equatable {
    case fresh
    case neutral
    case fatigued
    case highRisk
    case noData

    var title: String {
        switch self {
        case .fresh: return "体能充沛"
        case .neutral: return "状态稳定"
        case .fatigued: return "疲劳积累"
        case .highRisk: return "负荷高风险"
        case .noData: return "数据不足"
        }
    }

    var guidance: String {
        switch self {
        case .fresh: return "Form 偏高，适合比赛或质量训练"
        case .neutral: return "Fitness 与 Fatigue 匹配，可以正常训练"
        case .fatigued: return "疲劳正在积累，建议控制强度"
        case .highRisk: return "短期压力过高，优先恢复"
        case .noData: return "需要更多跑步记录建立趋势"
        }
    }
}

struct TSBCalculator {
    let ctlTimeConstant: Double = 42
    let atlTimeConstant: Double = 7

    func calculate(dailyTSS: [(date: Date, tss: Double)]) -> TSBResult {
        let sorted = dailyTSS.sorted { $0.date < $1.date }
        guard let first = sorted.first else {
            let empty = TSBPoint(date: Date(), ctl: 0, atl: 0, tsb: 0)
            return TSBResult(current: empty, history: [])
        }

        var ctl = first.tss
        var atl = first.tss
        var history: [TSBPoint] = []

        for day in sorted {
            let previousCTL = ctl
            let previousATL = atl
            ctl = previousCTL + (day.tss - previousCTL) / ctlTimeConstant
            atl = previousATL + (day.tss - previousATL) / atlTimeConstant
            history.append(TSBPoint(date: day.date, ctl: ctl, atl: atl, tsb: previousCTL - previousATL))
        }

        return TSBResult(current: history.last ?? TSBPoint(date: first.date, ctl: ctl, atl: atl, tsb: 0), history: history)
    }

    func state(for tsb: Double, hasEnoughData: Bool) -> TSBState {
        guard hasEnoughData else { return .noData }
        if tsb > 10 { return .fresh }
        if tsb >= -10 { return .neutral }
        if tsb >= -30 { return .fatigued }
        return .highRisk
    }
}
