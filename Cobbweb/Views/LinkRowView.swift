// LinkRowView.swift
import SwiftUI
import AppKit

struct LinkRowView: View {

    let link: SavedLink
    let onOpen: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            favicon
            textStack
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onOpen() }
            if link.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.accentColor)
                    .opacity(0.7)
            }
            copyButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(rowBackground)
        .onHover { isHovered = $0 }
        .contextMenu { contextMenuItems }
    }

    // MARK: - Favicon

    private var favicon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let icon = link.iconImage {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.secondary)
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture { onOpen() }
    }

    // MARK: - Text Stack

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(link.title ?? link.rawURL.absoluteString)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
            Text(link.host)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Copy Button

    private var copyButton: some View {
        Button { copyToClipboard() } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isCopied
                        ? Color.accentColor
                        : Color.primary.opacity(isHovered ? 0.45 : 0.15)
                )
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isCopied)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .opacity(isHovered || isCopied ? 1 : 0)
    }

    // MARK: - Row Background

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .padding(.horizontal, 4)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button { onOpen() } label: {
            Label("Open in Browser", systemImage: "safari")
        }
        Button { copyToClipboard() } label: {
            Label("Copy Link", systemImage: "doc.on.doc")
        }

        Divider()

        Button { onPin() } label: {
            Label(
                link.isPinned ? "Unpin" : "Pin to Top",
                systemImage: link.isPinned ? "pin.slash" : "pin"
            )
        }

        Divider()

        Button(role: .destructive) { onDelete() } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    // MARK: - Copy

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link.rawURL.absoluteString, forType: .string)
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { isCopied = false }
        }
    }
}
