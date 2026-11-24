import SwiftUI

/// Banner showing auto-measurement status: connected (real-time), disconnected (storing to flash), syncing
/// Used in AutoMeasurementMonitorView to show persistent status during automatic measurements
struct AutoMeasurementStatusBanner: View {
    let state: AutoMeasurementBannerState
    let onAction: (() -> Void)?

    init(
        state: AutoMeasurementBannerState,
        onAction: (() -> Void)? = nil
    ) {
        self.state = state
        self.onAction = onAction
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: state.iconName)
                .font(.title3)
                .foregroundStyle(state.iconColor)
                .symbolEffect(.pulse, options: .repeating, value: state.isAnimated)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.textColor)

                if let subtitle = state.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(state.textColor.opacity(0.8))
                }
            }

            Spacer()

            // Action button or progress indicator
            if state.showsProgressIndicator {
                ProgressView()
                    .tint(state.textColor)
            } else if let action = onAction, state.showsActionButton {
                Button(action: action) {
                    Text(state.actionButtonTitle ?? "")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(state.actionButtonColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(state.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}

// MARK: - Auto-Measurement Banner State

enum AutoMeasurementBannerState: Equatable {
    case connected(nextMeasurement: String)
    case disconnected(pendingCount: Int)
    case syncing(progress: Double, current: Int, total: Int)
    case syncError(message: String)
    case syncComplete(count: Int)

    var iconName: String {
        switch self {
        case .connected:
            return "antenna.radiowaves.left.and.right"
        case .disconnected:
            return "internaldrive.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .syncError:
            return "exclamationmark.triangle.fill"
        case .syncComplete:
            return "checkmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .orange
        case .syncing:
            return .blue
        case .syncError:
            return .red
        case .syncComplete:
            return .green
        }
    }

    var backgroundColor: Color {
        switch self {
        case .connected:
            return Color.green.opacity(0.15)
        case .disconnected:
            return Color.orange.opacity(0.15)
        case .syncing:
            return Color.blue.opacity(0.15)
        case .syncError:
            return Color.red.opacity(0.15)
        case .syncComplete:
            return Color.green.opacity(0.15)
        }
    }

    var textColor: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .orange
        case .syncing:
            return .blue
        case .syncError:
            return .red
        case .syncComplete:
            return .green
        }
    }

    var title: String {
        switch self {
        case .connected:
            return "En tiempo real"
        case .disconnected:
            return "Guardando en flash"
        case .syncing:
            return "Sincronizando..."
        case .syncError:
            return "Error de sincronización"
        case .syncComplete:
            return "Sincronización completa"
        }
    }

    var subtitle: String? {
        switch self {
        case .connected(let nextMeasurement):
            return "Próxima medición: \(nextMeasurement)"
        case .disconnected(let count):
            if count == 0 {
                return "Dispositivo desconectado"
            } else if count == 1 {
                return "1 medición pendiente"
            } else {
                return "\(count) mediciones pendientes"
            }
        case .syncing(let progress, let current, let total):
            let percentage = Int(progress * 100)
            return "Descargando \(current)/\(total) (\(percentage)%)"
        case .syncError(let message):
            return message
        case .syncComplete(let count):
            if count == 1 {
                return "1 medición descargada"
            } else {
                return "\(count) mediciones descargadas"
            }
        }
    }

    var isAnimated: Bool {
        switch self {
        case .syncing:
            return true
        default:
            return false
        }
    }

    var showsProgressIndicator: Bool {
        switch self {
        case .syncing:
            return true
        default:
            return false
        }
    }

    var showsActionButton: Bool {
        switch self {
        case .syncError:
            return true
        default:
            return false
        }
    }

    var actionButtonTitle: String? {
        switch self {
        case .syncError:
            return "Reintentar"
        default:
            return nil
        }
    }

    var actionButtonColor: Color {
        switch self {
        case .syncError:
            return .red
        default:
            return .blue
        }
    }
}

// MARK: - Previews

#Preview("All States") {
    VStack(spacing: 20) {
        AutoMeasurementStatusBanner(
            state: .connected(nextMeasurement: "2:34")
        )

        AutoMeasurementStatusBanner(
            state: .disconnected(pendingCount: 0)
        )

        AutoMeasurementStatusBanner(
            state: .disconnected(pendingCount: 5)
        )

        AutoMeasurementStatusBanner(
            state: .syncing(progress: 0.65, current: 13, total: 20)
        )

        AutoMeasurementStatusBanner(
            state: .syncError(message: "Tiempo de espera agotado")
        ) {
            print("Retry tapped")
        }

        AutoMeasurementStatusBanner(
            state: .syncComplete(count: 15)
        )
    }
    .padding()
}
