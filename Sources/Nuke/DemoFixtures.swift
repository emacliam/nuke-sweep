import Foundation

/// Deterministic, in-memory fixtures for screenshot/QA runs only.
/// Enabled with `--demo-fixtures`; never persisted.
@MainActor enum DemoFixtures {
    static let rootPath = "/Users/demo/projects/web"

    static func apply(to model: AppModel) {
        model.activities = activities
        model.features.historyLoading = false
        model.features.scans = scans
        model.features.developerScopes = []
        model.processes = processes
        model.processError = nil
        model.listeningPorts = ports
        model.portsUpdated = date("2026-11-03T10:00:00Z")
        model.portsError = nil
        model.caches = cacheMeasurements
        model.cacheScanning = false
        model.cacheOutcome = "Measured demo fixtures"
        model.dockerContext = "desktop-linux"
        model.dockerReachable = true
        model.dockerUpdated = date("2026-11-03T09:30:00Z")
        model.dockerError = nil
        model.docker = [
            DockerUsage(type: "Images", total: "14", active: "6", size: "4.2GB", reclaimable: "1.1GB"),
            DockerUsage(type: "Containers", total: "5", active: "2", size: "640MB", reclaimable: "310MB"),
            DockerUsage(type: "Build cache", total: "128", active: "0", size: "2.8GB", reclaimable: "2.8GB")
        ]
        model.dockerVolumes = [
            DockerVolume(name: "demo-postgres", driver: "local", mountpoint: "/var/lib/docker/volumes/demo-postgres/_data", scope: "local"),
            DockerVolume(name: "demo-cache", driver: "local", mountpoint: "/var/lib/docker/volumes/demo-cache/_data", scope: "local")
        ]
        model.dockerVolumeError = nil
    }

    static var activities: [Activity] {
        [
            Activity(date: date("2026-11-02T10:15:00Z"), title: "Cleanup", detail: "Moved 2 reviewed build folders to Trash."),
            Activity(date: date("2026-10-30T16:40:00Z"), title: "Quit requested", detail: "Demo dev server · PID 4242"),
            Activity(date: date("2026-10-27T09:05:00Z"), title: "Saved scope", detail: "Example project · node_modules excluded")
        ]
    }

    static var scans: [StoredScan] {
        [
            StoredScan(date: date("2026-11-01T09:00:00Z"), root: rootPath,
                       sizes: ["dist": 910_000_000, "node_modules": 1_820_000_000, "src": 13_000_000],
                       categories: ["Build output": 910_000_000, "Installed dependencies": 1_820_000_000, "Source": 13_000_000]),
            StoredScan(date: date("2026-10-20T09:00:00Z"), root: rootPath,
                       sizes: ["dist": 420_000_000, "node_modules": 1_800_000_000, "src": 12_000_000],
                       categories: ["Build output": 420_000_000, "Installed dependencies": 1_800_000_000, "Source": 12_000_000])
        ]
    }

    static var processes: [ProcessRow] {
        [
            ProcessRow(pid: 4242, cpu: 12.5, memory: 310_000_000, command: "/usr/local/bin/node /Users/demo/projects/web/dev-server.js", started: "10:00", owner: 501),
            ProcessRow(pid: 5151, cpu: 4.1, memory: 180_000_000, command: "/usr/bin/python3 /Users/demo/projects/api/server.py", started: "09:45", owner: 501),
            ProcessRow(pid: 6161, cpu: 0.3, memory: 90_000_000, command: "/usr/bin/git status", started: "09:30", owner: 501)
        ]
    }

    static var ports: [ListeningPort] {
        [
            ListeningPort(pid: 4242, process: "node", address: "127.0.0.1:5173", port: 5173),
            ListeningPort(pid: 5151, process: "python3", address: "127.0.0.1:8000", port: 8000)
        ]
    }

    static var cacheMeasurements: [CacheMeasurement] {
        Array(CacheRule.all.prefix(4)).enumerated().map { index, rule in
            let size = Int64(index + 1) * 260_000_000
            let item = DiskItem(url: URL(fileURLWithPath: "/Users/demo/Library/Caches/" + rule.id), size: size, allocated: size, directory: true, symlink: false, modified: date("2026-10-30T09:00:00Z"), identity: nil, incomplete: false)
            return CacheMeasurement(rule: rule, item: item, skipped: 0)
        }
    }

    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: 1_790_000_000)
    }
}
