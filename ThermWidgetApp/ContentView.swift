import SwiftUI
import UIKit
import WidgetKit

struct ContentView: View {
    @Binding var snapshot: ThermalSnapshot
    @Binding var unit: ThermTemperatureUnit
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onRefresh) {
                        Label("刷新", systemImage: "arrow.clockwise")
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
                    accent: ThermDataStore.colorForCelsius(snapshot.batteryCelsius),
                    subtitle: snapshot.isCharging ? "充电中" : (snapshot.externalConnected ? "已接电源" : "未接电")
                )
                MetricTile(
                    title: "SoC 核心",
                    value: unit.format(snapshot.socCelsius),
                    accent: ThermDataStore.colorForCelsius(snapshot.socCelsius),
                    subtitle: "温控: \(snapshot.thermalLevelLabel)"
                )
                MetricTile(
                    title: "电源 / 充电区",
                    value: unit.format(snapshot.powerCelsius),
                    accent: ThermDataStore.colorForCelsius(snapshot.powerCelsius),
                    subtitle: "NAND: \(unit.format(snapshot.nandCelsius))"
                )
                MetricTile(
                    title: "多传感器均值",
                    value: unit.format(snapshot.deviceAvgCelsius),
                    accent: ThermDataStore.colorForCelsius(snapshot.deviceAvgCelsius),
                    subtitle: "最高: \(unit.format(snapshot.maxCelsius))"
                )
            }
            .padding(.vertical, 4)

            HStack {
                Text("已同步小组件 · 更新时间 \(Self.timeFormatter.string(from: snapshot.timestamp))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(snapshot.sensors.count) 路")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("核心概览（只读）")
        } footer: {
            Text("点击桌面小组件进入此页时已自动重读传感器并刷新小组件；按 Home 键返回桌面即可看到最新数据。")
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
                                    .foregroundColor(ThermDataStore.colorForCelsius(item.celsius))
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
