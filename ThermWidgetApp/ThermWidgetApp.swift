import SwiftUI
import WidgetKit

@main
struct ThermWidgetApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: ThermalSnapshot = ThermDataStore.captureLiveSnapshotAndSave()
    @State private var unit: ThermTemperatureUnit = ThermDataStore.preferredUnit

    var body: some Scene {
        WindowGroup {
            ContentView(
                snapshot: $snapshot,
                unit: $unit,
                onRefresh: refreshAll
            )
            .onOpenURL { _ in
                refreshAll()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    refreshAll()
                }
            }
        }
    }

    private func refreshAll() {
        snapshot = ThermDataStore.captureLiveSnapshotAndSave()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
