import SwiftUI

struct LocationPopover: View {
    let location: SavedLocation
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(location.category.emoji)
                .font(.title)

            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                Text(location.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = location.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}
