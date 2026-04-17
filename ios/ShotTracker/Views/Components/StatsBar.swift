import SwiftUI

struct StatsBar: View {
    @ObservedObject var session: GameSession

    var body: some View {
        HStack(spacing: 0) {
            stat(title: "MAKES", value: "\(session.makes)", tint: .green)
            divider
            stat(title: "MISSES", value: "\(session.misses)", tint: .red)
            divider
            stat(title: "FG%", value: pctString, tint: .white)
            divider
            streakCell
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: 26)
    }

    @ViewBuilder
    private func stat(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var pctString: String {
        guard session.totalAttempts > 0 else { return "—" }
        return "\(Int((session.fieldGoalPct * 100).rounded()))%"
    }

    private var streakCell: some View {
        VStack(spacing: 2) {
            Text(streakText)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(session.streak > 0 ? .green : (session.streak < 0 ? .red : .white))
                .monospacedDigit()
            Text("STREAK")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var streakText: String {
        let s = session.streak
        if s == 0 { return "—" }
        return s > 0 ? "\(s)" : "\(abs(s))"
    }
}
