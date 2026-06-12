import SwiftUI

/// A pill-style tag. `filled` = active/selected. `trailingSystemImage` adds
/// an icon (e.g. xmark to remove). The whole chip is the tap target.
struct TagChip: View {
    let name: String
    var filled: Bool = false
    var trailingSystemImage: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        let content = HStack(spacing: 4) {
            Text(name)
                .font(.caption.weight(.medium))
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(filled ? Color.white : Color.accentColor)
        .background(
            filled ? Color.accentColor : Color.accentColor.opacity(0.15),
            in: Capsule()
        )

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}
