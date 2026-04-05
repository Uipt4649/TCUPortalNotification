import SwiftUI

struct NotificationCard: View {
    let notice: NoticeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TypeTag(type: notice.type)
                Text(notice.course)
                    .font(.caption)
                    .foregroundStyle(PortalSectionStyle.color(for: notice.course))
                Spacer()
                if notice.isUnread {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }

            Text(notice.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(notice.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(notice.dateLabel, systemImage: "clock")
                if !notice.sender.isEmpty {
                    Label(notice.sender, systemImage: "person")
                }
                if !notice.readAtLabel.isEmpty {
                    Label("既読 \(notice.readAtLabel)", systemImage: "checkmark.circle")
                }
                PortalOpenButton(url: notice.portalURL)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notice.isUnread ? notice.type.color.opacity(0.08) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(notice.type.color.opacity(0.18), lineWidth: 1)
        )
    }
}

struct PortalOpenButton: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "safari.fill")
                Text("ポータルで開く")
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.25), Color.cyan.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule().stroke(Color.blue.opacity(0.45), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct TypeTag: View {
    let type: NoticeType

    var body: some View {
        Text(type.label)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(type.color)
            .clipShape(Capsule())
    }
}

struct FilterChip: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? color.opacity(0.18) : Color(.secondarySystemBackground))
                .overlay(
                    Capsule()
                        .stroke(isSelected ? color.opacity(0.8) : Color.clear, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
