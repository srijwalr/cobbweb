// MenuRowItem.swift
import SwiftUI

struct MenuRowItem: View {

    let title: String
    let icon: String
    var destructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(destructive ? Color.red.opacity(0.8) : Color.secondary)
                .frame(width: 16)

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(destructive ? Color.red : Color.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { action() }
    }
}
