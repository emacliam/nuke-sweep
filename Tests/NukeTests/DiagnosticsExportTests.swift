import XCTest
@testable import Nuke

@MainActor
final class DiagnosticsExportTests: XCTestCase {
    func testFailureReportOmitsReceiptPathsAndErrorText() throws {
        let item = ReceiptItem(originalPath: "/private/customer/file", trashPath: nil, size: 80,
                               success: false, outcome: "Could not move customer file")
        let receipt = CleanupReceipt(date: .now, title: "Cleanup", items: [item],
                                     freeBefore: nil, freeAfter: nil, undo: "Restore instructions")
        let report = try XCTUnwrap(FailureReport(receipt: receipt))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(report.json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["event", "date", "app_version", "app_build", "macos", "failed_items", "total_items"])
        XCTAssertEqual(fields["failed_items"] as? Int, 1)
        XCTAssertFalse(report.json.contains("customer"))
        let success = CleanupReceipt(date: .now, title: "Cleanup", items: [],
                                     freeBefore: nil, freeAfter: nil, undo: "")
        XCTAssertNil(FailureReport(receipt: success))
    }

    func testProviderSummaryOmitsSecretsAndBaseURLs() {
        var provider = AIProviderConfig.make(.openAICompatible, name: "OpenRouter")
        provider.baseURL = "https://openrouter.ai/api/v1"
        provider.model = "openai/gpt-4o-mini"
        let summary = DiagnosticsExporter.providerSummary(provider)
        XCTAssertEqual(summary["flavor"] as? String, "openAICompatible")
        XCTAssertEqual(summary["model"] as? String, "openai/gpt-4o-mini")
        XCTAssertNil(summary["baseURL"])
        XCTAssertNil(summary["keychainAccount"])
        XCTAssertNil(summary["key"])
    }

    func testExportOmitsAbsoluteSchedulePathsAndAPIKeys() throws {
        let suite = "nuke.tests.diagnostics." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let schedules = ScheduledScanStore(defaults: defaults)
        _ = schedules.add(URL(fileURLWithPath: "/Users/secret/work/demo"), frequency: .daily)
        let model = AppModel(restoring: false)
        let data = DiagnosticsExporter.json(model: model, features: model.features, ai: model.ai, scheduled: schedules)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("demo"))
        XCTAssertFalse(text.contains("/Users/secret"))
        XCTAssertFalse(text.contains("apiKey"))
        XCTAssertFalse(text.contains("keychain"))
    }
}
