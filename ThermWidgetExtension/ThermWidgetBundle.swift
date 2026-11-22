import SwiftUI
import UIKit
import WidgetKit

struct ThermTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: ThermalSnapshot
    let unit: ThermTemperatureUnit
}

struct ThermTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ThermTimelineEntry {
        ThermTimelineEntry(
            date: Date(),
            snapshot: ThermalSnapshot(
                timestamp: Date(),
                batteryCelsius: 31.4,
                socCelsius: 36.8,
                powerCelsius: 34.2,
                nandCelsius: 33.1,
                deviceAvgCelsius: 33.5,
                maxCelsius: 36.8,
                maxSensorName: "PMGR",
                isCharging: false,
                externalConnected: false,
                batteryCapacity: 88,
                thermalStateRaw: 0,
                thermalPressureRaw: 0,
                sensors: []
            ),
            unit: .celsius
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ThermTimelineEntry) -> Void) {
        let snap = context.isPreview ? placeholder(in: context).snapshot : ThermDataStore.loadCachedOrCapture()
        completion(ThermTimelineEntry(date: Date(), snapshot: snap, unit: ThermDataStore.preferredUnit))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThermTimelineEntry>) -> Void) {
        let snap = ThermDataStore.loadCachedOrCapture()
        let now = Date()
        let entry = ThermTimelineEntry(date: now, snapshot: snap, unit: ThermDataStore.preferredUnit)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct ThermDashboardWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ThermTimelineEntry

    private static let hmFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .accessoryRectangular:
                accessoryRectView
            case .accessoryInline:
                accessoryInlineView
            default:
                smallView
            }
        }
        .widgetURL(URL(string: "thermwidget://refresh"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("硬件温度")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.snapshot.thermalLevelLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(entry.snapshot.thermalLevelColor)
            }

            rowItem(label: "电池", temp: entry.snapshot.batteryCelsius)
            rowItem(label: "核心", temp: entry.snapshot.socCelsius)
            rowItem(label: "均温", temp: entry.snapshot.deviceAvgCelsius)

            Spacer(minLength: 0)
            HStack {
                Text("点按刷新")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(Self.hmFormatter.string(from: entry.snapshot.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .thermWidgetBackground()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("硬件温度", systemImage: "thermometer.medium")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("温控: \(entry.snapshot.thermalLevelLabel)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.snapshot.thermalLevelColor.opacity(0.15))
                    .foregroundColor(entry.snapshot.thermalLevelColor)
                    .cornerRadius(6)
                Text(Self.hmFormatter.string(from: entry.snapshot.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                cellCard(title: "电池", temp: entry.snapshot.batteryCelsius)
                cellCard(title: "SoC 核心", temp: entry.snapshot.socCelsius)
                cellCard(title: "电源区", temp: entry.snapshot.powerCelsius)
                cellCard(title: "机身均温", temp: entry.snapshot.deviceAvgCelsius)
            }

            HStack {
                Text("热点: \(entry.snapshot.maxSensorName ?? "--") \(entry.unit.format(entry.snapshot.maxCelsius))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("点按更新")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .thermWidgetBackground()
    }

    private var accessoryRectView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("电池 \(entry.unit.format(entry.snapshot.batteryCelsius)) · 核心 \(entry.unit.format(entry.snapshot.socCelsius))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            Text("均温 \(entry.unit.format(entry.snapshot.deviceAvgCelsius)) · \(entry.snapshot.thermalLevelLabel)")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text("更新 \(Self.hmFormatter.string(from: entry.snapshot.timestamp))")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessoryInlineView: some View {
        Text("电 \(entry.unit.format(entry.snapshot.batteryCelsius)) 核 \(entry.unit.format(entry.snapshot.socCelsius))")
    }

    private func rowItem(label: String, temp: Double?) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(entry.unit.format(temp))
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundColor(ThermDataStore.colorForCelsius(temp))
        }
    }

    private func cellCard(title: String, temp: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(entry.unit.format(temp))
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundColor(ThermDataStore.colorForCelsius(temp))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct ThermDashboardWidget: Widget {
    let kind = "ThermDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ThermTimelineProvider()) { entry in
            ThermDashboardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("硬件温度监控")
        .description("只读显示电池、SoC核心、电源区与机身均温，点一下立即刷新。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct ThermWidgetBundle: WidgetBundle {
    var body: some Widget {
        ThermDashboardWidget()
    }
}

private extension View {
    @ViewBuilder
    func thermWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(Color(UIColor.systemBackground), for: .widget)
        } else {
            background(Color(UIColor.systemBackground))
        }
    }
}
