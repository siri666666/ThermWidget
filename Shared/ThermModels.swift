import Foundation
import SwiftUI

enum SensorCategory: String, CaseIterable, Codable, Identifiable {
    case battery = "电池"
    case soc = "SoC 核心"
    case power = "电源 / 充电"
    case storageAndDisplay = "存储 / 屏幕"
    case peripheral = "相机 / 射频 / 其它"

    var id: String { rawValue }
}

struct ThermalSensorItem: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let celsius: Double
    let category: SensorCategory
}

struct ThermalSnapshot: Codable, Equatable {
    let timestamp: Date
    let batteryCelsius: Double?
    let socCelsius: Double?
    let powerCelsius: Double?
    let nandCelsius: Double?
    let deviceAvgCelsius: Double?
    let maxCelsius: Double?
    let maxSensorName: String?
    let isCharging: Bool
    let externalConnected: Bool
    let batteryCapacity: Int?
    let thermalStateRaw: Int
    let thermalPressureRaw: Int
    let sensors: [ThermalSensorItem]

    var thermalLevelLabel: String {
        switch thermalPressureRaw {
        case 0: return "正常"
        case 10: return "温热"
        case 20: return "较热降频"
        case 30: return "过热保护"
        case 40: return "极端休眠"
        default:
            switch thermalStateRaw {
            case 0: return "正常"
            case 1: return "温热"
            case 2: return "较热降频"
            case 3: return "过热保护"
            default: return "未知"
            }
        }
    }

    var thermalLevelColor: Color {
        let severity = max(
            thermalPressureRaw >= 0 ? thermalPressureRaw / 10 : 0,
            thermalStateRaw
        )
        switch severity {
        case 0: return .green
        case 1: return .orange
        default: return .red
        }
    }
}

enum ThermTemperatureUnit: String, Codable {
    case celsius
    case fahrenheit

    func format(_ celsius: Double?, decimals: Int = 1) -> String {
        guard let c = celsius else { return "--" }
        let value = (self == .celsius) ? c : (c * 9.0 / 5.0 + 32.0)
        let suffix = (self == .celsius) ? "°C" : "°F"
        return String(format: "%.\(decimals)f%@", value, suffix)
    }
}

enum ThermDataStore {
    static let appGroupID = "group.com.siri666666.thermwidget"
    private static let snapshotKey = "latest_thermal_snapshot_v1"
    private static let unitKey = "preferred_temperature_unit_v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var preferredUnit: ThermTemperatureUnit {
        get {
            guard let raw = defaults.string(forKey: unitKey),
                  let unit = ThermTemperatureUnit(rawValue: raw) else {
                return .celsius
            }
            return unit
        }
        set {
            defaults.set(newValue.rawValue, forKey: unitKey)
        }
    }

    static func classifySensor(name: String) -> SensorCategory {
        let lower = name.lowercased()
        if lower.contains("batt") || lower.contains("tg0") || lower.contains("tg1") || lower.contains("gas gauge") {
            return .battery
        }
        if lower.contains("pmgr") || lower.contains("soc") || lower.contains("cpu") || lower.contains("gpu") || lower.contains("ane") || lower.contains("tdie") {
            return .soc
        }
        if lower.contains("pmu") || lower.contains("charg") || lower.contains("tigris") || lower.contains("hydra") || lower.contains("tristar") || lower.contains("ldo") || lower.contains("buck") || lower.contains("wireless") {
            return .power
        }
        if lower.contains("nand") || lower.contains("display") || lower.contains("screen") || lower.contains("backlight") || lower.contains("panel") {
            return .storageAndDisplay
        }
        return .peripheral
    }

    static func captureLiveSnapshotAndSave() -> ThermalSnapshot {
        let raw = ThermalSensorBridge.readSnapshotDictionary()
        let snapshot = parseSnapshot(from: raw)
        save(snapshot)
        return snapshot
    }

    static func loadCachedOrCapture() -> ThermalSnapshot {
        // Capture directly first; if extension sandbox returns empty sensors, fall back to App Group cache.
        let live = parseSnapshot(from: ThermalSensorBridge.readSnapshotDictionary())
        if !live.sensors.isEmpty || live.batteryCelsius != nil {
            save(live)
            return live
        }
        if let data = defaults.data(forKey: snapshotKey),
           let cached = try? JSONDecoder().decode(ThermalSnapshot.self, from: data) {
            return cached
        }
        return live
    }

    static func save(_ snapshot: ThermalSnapshot) {
        if let encoded = try? JSONEncoder().encode(snapshot) {
            defaults.set(encoded, forKey: snapshotKey)
        }
    }

    static func parseSnapshot(from raw: [String: Any]) -> ThermalSnapshot {
        let timestampSeconds = (raw["timestamp"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
        let batteryDict = raw["battery"] as? [String: Any]
        let sensorDicts = raw["sensors"] as? [[String: Any]] ?? []

        var parsedSensors: [ThermalSensorItem] = []
        var nameCounts: [String: Int] = [:]
        for item in sensorDicts {
            guard let name = item["name"] as? String,
                  let celsius = (item["celsius"] as? NSNumber)?.doubleValue else {
                continue
            }
            let count = (nameCounts[name] ?? 0) + 1
            nameCounts[name] = count
            let uniqueID = count == 1 ? name : "\(name)#\(count)"
            parsedSensors.append(
                ThermalSensorItem(
                    id: uniqueID,
                    name: name,
                    celsius: celsius,
                    category: classifySensor(name: name)
                )
            )
        }

        parsedSensors.sort { lhs, rhs in
            if lhs.celsius != rhs.celsius {
                return lhs.celsius > rhs.celsius
            }
            return lhs.name < rhs.name
        }

        let rawBatteryC = (batteryDict?["temperatureC"] as? NSNumber)?.doubleValue
        let hidBatteryC = parsedSensors.first { $0.category == .battery }?.celsius
        let batteryC = rawBatteryC ?? hidBatteryC

        let socC = parsedSensors.first { $0.category == .soc }?.celsius
        let powerC = parsedSensors.first { $0.category == .power }?.celsius
        let nandC = parsedSensors.first { $0.name.lowercased().contains("nand") }?.celsius

        let validTemps = parsedSensors.map(\.celsius).filter { $0 > 5.0 && $0 < 105.0 }
        let avgC: Double? = validTemps.isEmpty ? batteryC : (validTemps.reduce(0.0, +) / Double(validTemps.count))
        let hottest = parsedSensors.first

        return ThermalSnapshot(
            timestamp: Date(timeIntervalSince1970: timestampSeconds),
            batteryCelsius: batteryC,
            socCelsius: socC,
            powerCelsius: powerC,
            nandCelsius: nandC,
            deviceAvgCelsius: avgC,
            maxCelsius: hottest?.celsius,
            maxSensorName: hottest?.name,
            isCharging: (batteryDict?["isCharging"] as? NSNumber)?.boolValue ?? false,
            externalConnected: (batteryDict?["externalConnected"] as? NSNumber)?.boolValue ?? false,
            batteryCapacity: (batteryDict?["capacity"] as? NSNumber)?.intValue,
            thermalStateRaw: (raw["thermalState"] as? NSNumber)?.intValue ?? 0,
            thermalPressureRaw: (raw["thermalPressure"] as? NSNumber)?.intValue ?? -1,
            sensors: parsedSensors
        )
    }

    static func colorForCelsius(_ celsius: Double?) -> Color {
        guard let c = celsius else { return .secondary }
        switch c {
        case ..<25: return .cyan
        case 25..<37: return .green
        case 37..<43: return .orange
        default: return .red
        }
    }
}
