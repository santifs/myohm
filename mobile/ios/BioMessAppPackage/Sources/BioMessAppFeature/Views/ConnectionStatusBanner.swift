import SwiftUI

/// Banner showing BLE connection status with visual feedback
struct ConnectionStatusBanner: View {
    let connectionState: BLEConnectionState
    let deviceName: String?

    init(connectionState: BLEConnectionState, deviceName: String? = nil) {
        self.connectionState = connectionState
        self.deviceName = deviceName
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .symbolEffect(.pulse, options: .repeating, value: connectionState == .connecting)
                .foregroundStyle(foregroundColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.subheadline.bold())
                    .foregroundStyle(foregroundColor)

                if connectionState == .connected, let name = deviceName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(foregroundColor.opacity(0.8))
                }
            }

            Spacer()

            // Status indicator dot
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse, options: .repeating, value: connectionState == .connecting)
        }
        .padding()
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: shadowColor, radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.3), value: connectionState)
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch connectionState {
        case .disconnected:
            return "antenna.radiowaves.left.and.right.slash"
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .connected:
            return "checkmark.circle.fill"
        }
    }

    private var statusText: String {
        switch connectionState {
        case .disconnected:
            return "Sin Conexión"
        case .connecting:
            return "Conectando..."
        case .connected:
            return "Conectado"
        }
    }

    private var backgroundColor: Color {
        switch connectionState {
        case .disconnected:
            return Color.red.opacity(0.12)
        case .connecting:
            return Color.orange.opacity(0.12)
        case .connected:
            return Color.green.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch connectionState {
        case .disconnected:
            return Color.red
        case .connecting:
            return Color.orange
        case .connected:
            return Color.green
        }
    }

    private var dotColor: Color {
        switch connectionState {
        case .disconnected:
            return Color.red
        case .connecting:
            return Color.orange
        case .connected:
            return Color.green
        }
    }

    private var shadowColor: Color {
        switch connectionState {
        case .disconnected:
            return Color.red.opacity(0.2)
        case .connecting:
            return Color.orange.opacity(0.2)
        case .connected:
            return Color.green.opacity(0.2)
        }
    }
}

// MARK: - BLE Connection State

enum BLEConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}

// MARK: - Previews

#Preview("Disconnected") {
    VStack(spacing: 20) {
        ConnectionStatusBanner(
            connectionState: .disconnected
        )

        ConnectionStatusBanner(
            connectionState: .connecting
        )

        ConnectionStatusBanner(
            connectionState: .connected,
            deviceName: "BioMess Device"
        )
    }
    .padding()
}
