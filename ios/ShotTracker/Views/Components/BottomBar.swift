import SwiftUI

/// Bottom action row. No manual make/miss — shot logging is 100% automatic.
struct BottomBar: View {
    @ObservedObject var session: GameSession
    @Binding var showResetConfirm: Bool

    var body: some View {
        HStack(spacing: 12) {
            glassButton(systemName: "arrow.uturn.backward", label: "Undo") {
                session.undoLast()
            }
            .disabled(session.shots.isEmpty)
            .opacity(session.shots.isEmpty ? 0.4 : 1)

            glassButton(systemName: "scope", label: hoopLabel) {
                session.startHoopPlacement()
            }

            glassButton(systemName: "trash", label: "Reset") {
                showResetConfirm = true
            }
            .disabled(session.shots.isEmpty && session.ballTrail.isEmpty)
            .opacity(session.shots.isEmpty && session.ballTrail.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
    }

    private var hoopLabel: String {
        session.hoopPlaced ? "Re-aim" : "Place hoop"
    }

    @ViewBuilder
    private func glassButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
