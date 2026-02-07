import SwiftUI

struct PhaseSummaryBar: View {

    let items: [Item]

    struct Item {
        let label: String
        let value: String
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Text(item.label)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .bold()
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
