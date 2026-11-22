import Combine
import SwiftUI
import UIKit
import WidgetKit

final class ThermalMonitorModel: ObservableObject {
    @Published var snapshot: ThermalSnapshot
    @Published var unit: ThermTemperatureUnit
    @Published var isLiveEnabled: Bool = true {
        didSet {
            if isLiveEnabled {
                startTimer()
                sample(reloadWidgets: false)
            } else {
                stopTimer()
            }
        }
    }

    private var timer: Timer?
    private var isSampling = false
    private var observers: [NSObjectProtocol] = []

    init() {
        self.snapshot = ThermDataStore.captureLiveSnapshotAndSave()
        self.unit = ThermDataStore.preferredUnit
        setupLifecycleObservers()
        startTimer()
    }

    deinit {
        timer?.invalidate()
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func setupLifecycleObservers() {
        let nc = NotificationCenter.default
        let activeObs = nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sample(reloadWidgets: true)
            if self.isLiveEnabled {
                self.startTimer()
            }
        }
        let resignObs = nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.stopTimer()
            ThermDataStore.save(self.snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
        observers = [activeObs, resignObs]
    }

    func startTimer() {
        stopTimer()
        guard isLiveEnabled else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample(reloadWidgets: false)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func toggleUnit() {
        unit = (unit == .celsius) ? .fahrenheit : .celsius
        ThermDataStore.preferredUnit = unit
        WidgetCenter.shared.reloadAllTimelines()
    }

    func sample(reloadWidgets: Bool) {
        guard !isSampling else { return }
        isSampling = true
        DispatchQueue.global(qos: .userInitiated).async {
            let latest = ThermDataStore.captureLiveSnapshotAndSave()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.snapshot = latest
                self.isSampling = false
                if reloadWidgets {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
}

@main
struct ThermWidgetApp: App {
    @StateObject private var model = ThermalMonitorModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onOpenURL { _ in
                    model.sample(reloadWidgets: true)
                    if model.isLiveEnabled {
                        model.startTimer()
                    }
                }
        }
    }
}
