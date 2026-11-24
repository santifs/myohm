// SPDX-License-Identifier: Apache-2.0
import SwiftUI
// The original cloud-status slot now accurately indicates device-local storage.
struct SyncStatusIndicator: View {
    enum Style { case compact, standard, expanded }
    var style: Style = .compact
    var body: some View { Label("Local", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary) }
}
struct FloatingSyncButton: View { var body: some View { EmptyView() } }
