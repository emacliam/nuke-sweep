import Foundation

/// Leftovers that can be proven rather than guessed.
/// Ideas from Major Tom (MIT, Copyright (c) 2026 Tom Jordan).
enum XcodeLeftovers {
    /// A DerivedData folder records its project in info.plist (`WorkspacePath`).
    /// When that project is gone, nothing will ever use the folder again.
    static func projectGone(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard let range = path.range(of: "/Library/Developer/Xcode/DerivedData/") else { return false }
        let container = path[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        guard !container.isEmpty, container != "ModuleCache.noindex" else { return false }
        let plist = URL(fileURLWithPath: String(path[..<range.upperBound]) + container + "/info.plist")
        guard let data = try? Data(contentsOf: plist),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let workspace = values["WorkspacePath"] as? String else { return false }
        return !FileManager.default.fileExists(atPath: workspace)
    }
}

/// JetBrains keeps one cache folder per product version (IntelliJIdea2024.1,
/// IntelliJIdea2025.2, ...). Folders older than the newest of their product
/// belong to versions you have moved on from.
enum JetBrainsLeftovers {
    static func olderVersion(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard let range = path.range(of: "/Library/Caches/JetBrains/") else { return false }
        let name = path[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        guard let split = name.firstIndex(where: \.isNumber) else { return false }
        let product = String(name[..<split]), version = String(name[split...])
        let parent = String(path[..<range.upperBound])
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
        return siblings.contains { other in
            guard other.hasPrefix(product), let index = other.firstIndex(where: \.isNumber), String(other[..<index]) == product else { return false }
            return String(other[index...]).compare(version, options: .numeric) == .orderedDescending
        }
    }
}

/// Android system images and the emulators (AVDs) that use them.
enum AndroidImages {
    struct Image: Identifiable, Sendable {
        var id: String { path }
        let path: String
        /// sdkmanager package name, e.g. system-images;android-34;google_apis;arm64-v8a
        let package: String
        let size: Int64
        let users: [String]
    }

    static var sdk: URL {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["ANDROID_HOME"] ?? environment["ANDROID_SDK_ROOT"], value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk")
    }

    static func inspect(token: ScanCancellation) -> [Image] {
        let root = sdk.appendingPathComponent("system-images")
        let fm = FileManager.default
        // Which image each AVD boots: image.sysdir.1=system-images/android-34/google_apis/arm64-v8a/
        var users: [String: [String]] = [:]
        let avds = fm.homeDirectoryForCurrentUser.appendingPathComponent(".android/avd")
        for avd in (try? fm.contentsOfDirectory(atPath: avds.path)) ?? [] where avd.hasSuffix(".avd") {
            guard let config = try? String(contentsOfFile: avds.appendingPathComponent(avd + "/config.ini").path, encoding: .utf8) else { continue }
            for line in config.split(separator: "\n") where line.hasPrefix("image.sysdir.1") {
                let value = line.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                let key = value.split(separator: "/").filter { !$0.isEmpty }.joined(separator: "/")
                users[key, default: []].append(String(avd.dropLast(4)))
            }
        }
        var images: [Image] = []
        for api in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            for tag in (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(api).path)) ?? [] {
                for abi in (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(api + "/" + tag).path)) ?? [] where !token.cancelled {
                    let url = root.appendingPathComponent(api + "/" + tag + "/" + abi)
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                    let size = DiskScanner.scan(url, cancellation: token, deadline: Date().addingTimeInterval(10)).allocated
                    images.append(Image(path: url.path, package: "system-images;\(api);\(tag);\(abi)", size: size,
                                        users: users["system-images/\(api)/\(tag)/\(abi)"] ?? []))
                }
            }
        }
        return images.sorted { $0.size > $1.size }
    }
}
