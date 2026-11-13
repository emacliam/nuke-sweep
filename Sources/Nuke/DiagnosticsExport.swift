import Foundation

/// User-triggered local support bundle. It intentionally contains no API keys,
/// absolute folder paths, file contents or provider base URLs.
@MainActor enum DiagnosticsExporter {
    static func make(model: AppModel, features: FeatureModel, ai: AISettings, scheduled: ScheduledScanStore) -> [String: Any] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let resources = model.resources
        return [
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "app": ["version": version, "build": build],
            "system": [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "processors": resources.processors,
                "physical_memory_bytes": resources.physicalMemory,
                "disk_total_bytes": resources.totalDisk,
                "disk_free_bytes": resources.freeDisk
            ],
            "activity": [
                "saved_scans": features.scans.count,
                "receipts": features.receipts.count,
                "scopes": features.developerScopes.count,
                "measured_caches": model.caches.count,
                "listening_ports": model.listeningPorts.count,
                "scheduled_scans": scheduled.scans.count,
                "hang_reports": hangReportCount()
            ],
            "ai": [
                "enabled": ai.enabled,
                "offline_only": ai.offlineOnly,
                "providers": ai.providers.map(providerSummary)
            ],
            "schedules": scheduled.scans.map { schedule in
                ["name": schedule.name, "frequency": schedule.frequency.rawValue, "enabled": schedule.enabled]
            }
        ]
    }

    static func json(model: AppModel, features: FeatureModel, ai: AISettings, scheduled: ScheduledScanStore) -> Data {
        (try? JSONSerialization.data(withJSONObject: make(model: model, features: features, ai: ai, scheduled: scheduled), options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    static func providerSummary(_ provider: AIProviderConfig) -> [String: Any] {
        ["name": provider.name, "flavor": provider.flavor.rawValue, "local": provider.isLocal, "model": provider.model]
    }

    private static func hangReportCount() -> Int {
        let directory = HangWatchdog.directory
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.filter { $0.hasPrefix("Hang-") }.count ?? 0
    }
}
