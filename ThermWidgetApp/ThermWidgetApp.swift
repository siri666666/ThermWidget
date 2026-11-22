import Combine
import SwiftUI
import WidgetKit

@main
struct ThermWidgetApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: ThermalSnapshot = ThermDataStore.captureLiveSnapshotAndSave()
    @State private var unit: ThermTemperatureUnit = ThermDataStore.preferredUnit
    @State private var isLiveEnabled: Bool = true
    @State private var isSampling: Bool = false

    private let liveTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            ContentView(
                snapshot: $snapshot,
                unit: $unit,
                isLiveEnabled: $isLiveEnabled,
                onRefresh: { sample(reloadWidgets: true) }
            )
            .onOpenURL { _ in
                sample(reloadWidgets: true)
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    sample(reloadWidgets: true)
                case .inactive, .background:
                    ThermDataStore.save(snapshot)
                    WidgetCenter.shared.reloadAllTimelines()
                @unknown default:
                    break
                }
            }
            .onReceive(liveTimer) { _ in
                guard scenePhase == .active, isLiveEnabled else { return }
                sample(reloadWidgets: false)
            }
        }
    }

    private func sample(reloadWidgets: Bool) {
        guard !isSampling else { return }
        isSampling = true
        DispatchQueue.global(qos: .userInitiated).async {
            let latest = ThermDataStore.captureLiveSnapshotAndSave()
            DispatchQueue.main.async {
                self.snapshot = latest
                self.isSampling = false
                if reloadWidgets {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
}
