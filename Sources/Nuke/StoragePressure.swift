import SwiftUI
import NukeMetrics

/// The judgement lives in `NukeMetrics` so the Cleanup page, the menu-bar popover
/// and the desktop widget cannot disagree about it. Only the palette is local.
extension StoragePressure {
    var tint: Color {
        switch self {
        case .comfortable: return Theme.green
        case .tight: return Theme.warning
        case .low: return Theme.error
        case .unavailable: return Theme.secondary
        }
    }

    var label: LocalizedStringKey { LocalizedStringKey(title) }
}
