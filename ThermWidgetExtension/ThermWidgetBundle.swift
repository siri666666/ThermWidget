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
                batteryCelsius: 33.4,
                skinCelsius: 38.2,
                socCelsius: 62.5,
                socMaxCelsius: 68.0,
                powerCelsius: 44.1,
                nandCelsius: 42.0,
                maxCelsius: 68.0,
                maxSensorName: "PMGR SOC Die Temp Sensor0",
                isCharging: false,
                externalConnected: false,
                batteryCapacity: 80,
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

            rowItem(label: "电池", temp: entry.snapshot.batteryCelsius, isDie: false)
            rowItem(label: "机身", temp: entry.snapshot.skinCelsius, isDie: false)
            rowItem(label: "核心", temp: entry.snapshot.socCelsius, isDie: true)

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
                cellCard(title: "电池", temp: entry.snapshot.batteryCelsius, isDie: false)
                cellCard(title: "机身表面", temp: entry.snapshot.skinCelsius, isDie: false)
                cellCard(title: "SoC 结温", temp: entry.snapshot.socCelsius, isDie: true)
                cellCard(title: "闪存", temp: entry.snapshot.nandCelsius ?? entry.snapshot.powerCelsius, isDie: false)
            }

            HStack {
                Text("核心峰值: \(entry.unit.format(entry.snapshot.socMaxCelsius)) · 电源板: \(entry.unit.format(entry.snapshot.powerCelsius))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("点按进实时")
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
            Text("电池 \(entry.unit.format(entry.snapshot.batteryCelsius)) · 机身 \(entry.unit.format(entry.snapshot.skinCelsius))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            Text("结温 \(entry.unit.format(entry.snapshot.socCelsius)) · \(entry.snapshot.thermalLevelLabel)")
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
        Text("电 \(entry.unit.format(entry.snapshot.batteryCelsius)) 机 \(entry.unit.format(entry.snapshot.skinCelsius))")
    }

    private func rowItem(label: String, temp: Double?, isDie: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(entry.unit.format(temp))
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundColor(isDie ? ThermDataStore.colorForDieCelsius(temp) : ThermDataStore.colorForBoardCelsius(temp))
        }
    }

    private func cellCard(title: String, temp: Double?, isDie: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(entry.unit.format(temp))
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundColor(isDie ? ThermDataStore.colorForDieCelsius(temp) : ThermDataStore.colorForBoardCelsius(temp))
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
        .description("只读显示电池、机身表面、SoC结温与闪存温度，点一下进实时并刷新。")
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
