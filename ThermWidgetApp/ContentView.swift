import SwiftUI
import UIKit
import WidgetKit

struct ContentView: View {
    @Binding var snapshot: ThermalSnapshot
    @Binding var unit: ThermTemperatureUnit
    @Binding var isLiveEnabled: Bool
    let onRefresh: () -> Void

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    var body: some View {
        NavigationView {
            List {
                overviewSection
                sensorBreakdownSections
            }
            .navigationTitle("硬件温度")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(unit == .celsius ? "°C" : "°F") {
                        unit = (unit == .celsius) ? .fahrenheit : .celsius
                        ThermDataStore.preferredUnit = unit
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    .font(.headline.monospacedDigit())
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isLiveEnabled.toggle()
                        if isLiveEnabled {
                            onRefresh()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isLiveEnabled ? Color.green : Color.gray)
                                .frame(width: 7, height: 7)
                            Text(isLiveEnabled ? "实时" : "暂停")
                                .font(.subheadline)
                        }
                    }
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                onRefresh()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var overviewSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(
                    title: "电池温度",
                    value: unit.format(snapshot.batteryCelsius),
                    accent: ThermDataStore.colorForBoardCelsius(snapshot.batteryCelsius),
                    subtitle: snapshot.isCharging ? "充电中" : (snapshot.externalConnected ? "已接电源" : "未接电")
                )
                MetricTile(
                    title: "机身表面",
                    value: unit.format(snapshot.skinCelsius),
                    accent: ThermDataStore.colorForBoardCelsius(snapshot.skinCelsius),
                    subtitle: "温控: \(snapshot.thermalLevelLabel)"
                )
                MetricTile(
                    title: "SoC 硅片结温",
                    value: unit.format(snapshot.socCelsius),
                    accent: ThermDataStore.colorForDieCelsius(snapshot.socCelsius),
                    subtitle: "核心峰值: \(unit.format(snapshot.socMaxCelsius))"
                )
                MetricTile(
                    title: "电源板 / 闪存",
                    value: unit.format(snapshot.powerCelsius),
                    accent: ThermDataStore.colorForBoardCelsius(snapshot.powerCelsius),
                    subtitle: "NAND: \(unit.format(snapshot.nandCelsius))"
                )
            }
            .padding(.vertical, 4)

            HStack {
                Text(isLiveEnabled ? "前台每秒实时刷新" : "实时刷新已暂停")
                    .font(.caption)
                    .foregroundColor(isLiveEnabled ? .green : .secondary)
                Spacer()
                Text("\(Self.timeFormatter.string(from: snapshot.timestamp)) · \(snapshot.sensors.count) 路")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("核心概览（只读）")
        } footer: {
            Text("App 在前台时每秒自动刷新，退回桌面时自动将最新数据同步到小组件。注：SoC/PMU 硅片结温通常比机身表面高 25–50°C。")
        }
    }

    @ViewBuilder
    private var sensorBreakdownSections: some View {
        if snapshot.sensors.isEmpty {
            Section("传感器明细") {
                Text("未读取到 HID 温度传感器，请确认通过 TrollStore Lite 安装且保留完整权限。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } else {
            ForEach(SensorCategory.allCases) { category in
                let items = snapshot.sensors.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.rawValue) {
                        ForEach(items) { item in
                            HStack {
                                Text(item.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(unit.format(item.celsius))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundColor(ThermDataStore.colorForSensor(item))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let accent: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundColor(accent)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}
