import Foundation

enum FilePersistence {
    private static let queue = DispatchQueue(label: "local.nuke.persistence", qos: .utility)
    static func save<T: Encodable & Sendable>(_ value: T, name: String, failure: @escaping @Sendable (String) -> Void) {
        queue.async { do { try LocalStore.save(value, name: name) } catch { failure(error.localizedDescription) } }
    }
    static func flush() { queue.sync {} }
}
