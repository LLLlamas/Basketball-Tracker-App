import SwiftUI

/// Toast-style overlay that pops in after each detected shot and fades out.
/// Driven by `GameSession.lastEvent`; uses the event's UUID to retrigger animations.
struct ShotEventOverlay: View {
    @ObservedObject var session: GameSession
    @State private var visible = false
    @State private var currentId: UUID?

    var body: some View {
        VStack {
            if let event = session.lastEvent, visible {
                HStack(spacing: 10) {
                    Image(systemName: event.made ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(event.made ? .green : .red)
                    Text(event.message)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(event.made ? Color.green : Color.red, lineWidth: 1.2))
                .shadow(color: (event.made ? Color.green : Color.red).opacity(0.35), radius: 12)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: visible)
        .onChange(of: session.lastEvent?.id) { _, newId in
            guard let newId, newId != currentId else { return }
            currentId = newId
            visible = true
            Task {
                try? await Task.sleep(for: .milliseconds(1600))
                if currentId == newId { visible = false }
            }
        }
    }
}
