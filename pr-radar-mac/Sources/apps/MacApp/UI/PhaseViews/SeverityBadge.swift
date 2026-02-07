import SwiftUI

struct SeverityBadge: View {

    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch score {
        case 1...4: .green
        case 5...7: .orange
        case 8...10: .red
        default: .gray
        }
    }
}
