import SwiftUI

struct CountdownOverlayEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let seconds: Int

    var countdown: String {
        seconds < 60 ? "\(seconds)s" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct CountdownOverlayView: View {
    let entries: [CountdownOverlayEntry]
    var hiddenCount: Int = 0

    static let width: CGFloat = 140
    static let rowHeight: CGFloat = 92
    static let spacing: CGFloat = 6
    static let inset: CGFloat = 4
    static let summaryHeight: CGFloat = 18

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(entries) { entry in
                VStack(spacing: 2) {
                    Text("\(entry.title) cycle")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(entry.countdown)
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .contentTransition(.numericText(countsDown: true))
                        .foregroundStyle(TimeInterval(entry.seconds) <= TimerWarning.finalSecondsThreshold ? Color.orange : .white)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(width: Self.width, height: Self.rowHeight)
                .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.title) cycle, \(entry.seconds) seconds remaining")
            }
            if hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: Self.width, height: Self.summaryHeight)
                    .background(.black.opacity(0.48), in: Capsule())
                    .accessibilityLabel("\(hiddenCount) more timers ending soon")
            }
        }
        .padding(Self.inset)
        .fixedSize()
        .allowsHitTesting(false)
    }
}

#Preview {
    CountdownOverlayView(entries: [
        CountdownOverlayEntry(id: "preview", title: "5m", seconds: 10)
    ])
    .padding(30)
}
