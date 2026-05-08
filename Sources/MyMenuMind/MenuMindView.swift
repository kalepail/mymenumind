import AppKit
import MyMenuMindCore
import SwiftUI

struct MenuMindView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: SettingsStore
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()

            if showingSettings {
                SettingsPanel(
                    settings: settings,
                    onSave: {
                        viewModel.saveSettings()
                        withAnimation(.easeInOut(duration: 0.18)) { showingSettings = false }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.18)) { showingSettings = false }
                    }
                )
                .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .frame(width: 430, height: 620)
        .onAppear { viewModel.loadRecent() }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    searchBlock
                    itemsBlock
                    quickNoteBlock
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("m.")
                .font(.system(size: 22, weight: .bold, design: .serif).italic())
                .foregroundStyle(Theme.coral)
            Text("mymind")
                .font(Theme.Typography.wordmark())
                .foregroundStyle(Theme.ink)
                .tracking(-0.3)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showingSettings.toggle() }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .regular))
            }
            .buttonStyle(GhostIconButtonStyle())
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            InkSearchField(
                text: $viewModel.query,
                placeholder: "Search your mind…",
                onSubmit: { viewModel.search() },
                onClear: {
                    viewModel.query = ""
                    viewModel.search()
                }
            )
            shortcutsRow
        }
    }

    private var shortcutsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(searchShortcuts, id: \.example) { sc in
                    Button {
                        viewModel.query = sc.example
                        viewModel.search()
                    } label: {
                        Text(sc.example)
                    }
                    .buttonStyle(ChipButtonStyle())
                    .help(sc.label)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
        }
        .frame(height: 28)
    }

    private var searchShortcuts: [(label: String, example: String)] {
        [
            ("Filter by tag", "tag:reading"),
            ("Filter by type", "type:image"),
            ("Domain", "domain:nytimes.com"),
            ("Either term", "cats || dogs"),
            ("Exclude term", "shoes -red"),
            ("Object in images", "object:car"),
            ("Text in images", "text:car"),
            ("Action", "action:read && completed:false"),
            ("File format", "format:pdf"),
            ("Author", #"author:"jenny holzer""#),
        ]
    }

    private var itemsBlock: some View {
        let items = activeItems
        let isSearching = !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let title = isSearching ? "Search results." : "Recently saved."

        return VStack(alignment: .leading, spacing: 12) {
            SectionDivider(
                title: title,
                trailing: AnyView(
                    Button {
                        viewModel.loadRecent()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.inkFaded)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh recent items")
                )
            )

            if items.isEmpty {
                emptyState(isSearching: isSearching)
            } else {
                VStack(spacing: 1) {
                    ForEach(items) { item in
                        ItemRow(item: item, onOpen: { viewModel.open(item) })
                    }
                }
            }
        }
    }

    private func emptyState(isSearching: Bool) -> some View {
        VStack(spacing: 6) {
            Text(emptyHeadline(isSearching: isSearching))
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Theme.inkSoft)
            Text(emptySubline(isSearching: isSearching))
                .font(Theme.Typography.caption())
                .foregroundStyle(Theme.inkFaded)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func emptyHeadline(isSearching: Bool) -> String {
        if viewModel.isLoading { return "Looking…" }
        return isSearching ? "Nothing matched." : "Nothing here yet."
    }

    private func emptySubline(isSearching: Bool) -> String {
        if viewModel.isLoading { return "One moment." }
        return isSearching
            ? "Try a different phrase, or a tag like reading."
            : "Save something to your mind, it'll show up here."
    }

    private var activeItems: [MymindItem] {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? viewModel.recentItems
            : viewModel.searchResults
    }

    private var quickNoteBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionDivider(title: "A quick thought.")
            QuickNoteCard(
                text: $viewModel.quickNote,
                onSave: { viewModel.saveQuickNote() }
            )
        }
    }

    private var footer: some View {
        HStack {
            statusText
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, design: .serif).italic())
                    .foregroundStyle(Theme.inkFaded)
            }
            .buttonStyle(.plain)
            .help("Quit MyMenuMind")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack(alignment: .top) {
                Theme.paperSunken
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
            }
        )
    }

    @ViewBuilder
    private var statusText: some View {
        if let message = viewModel.message {
            let isPositive = message == "Note saved" || message == "Settings saved"
            HStack(spacing: 6) {
                Circle()
                    .fill(isPositive ? Theme.success : Theme.coral)
                    .frame(width: 5, height: 5)
                Text(message)
                    .font(.system(size: 11, design: .serif).italic())
                    .foregroundStyle(isPositive ? Theme.inkSoft : Theme.coral)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text("Quietly waiting.")
                .font(.system(size: 11, design: .serif).italic())
                .foregroundStyle(Theme.inkFaded)
        }
    }
}

private struct ItemRow: View {
    let item: MymindItem
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                kindGlyph
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(Theme.Typography.itemTitle())
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(secondaryLine)
                        .font(Theme.Typography.caption())
                        .foregroundStyle(Theme.inkFaded)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkFaded)
                    .opacity(hovering && item.preferredOpenURL != nil ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Theme.paperRaised : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(item.preferredOpenURL == nil)
        .opacity(item.preferredOpenURL == nil ? 0.55 : 1)
        .onHover { hovering = $0 }
    }

    private var displayTitle: String {
        let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private var secondaryLine: String {
        if let host = item.preferredOpenURL?.host?.replacingOccurrences(of: "www.", with: ""), !host.isEmpty {
            if let kind = item.kind, !kind.isEmpty {
                return "\(host) · \(kind)"
            }
            return host
        }
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            return subtitle
        }
        return item.kind ?? "note"
    }

    private var kindGlyph: some View {
        let symbol: String = {
            if item.rawAssetURL != nil { return "photo" }
            switch item.kind?.lowercased() {
            case "image", "photo": return "photo"
            case "video": return "play.rectangle"
            case "pdf": return "doc.richtext"
            case "note", "text": return "text.alignleft"
            case "tweet", "post": return "quote.bubble"
            case "audio": return "waveform"
            default:
                return item.preferredOpenURL != nil ? "link" : "doc.text"
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.paperSunken)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
        }
    }
}

private struct QuickNoteCard: View {
    @Binding var text: String
    let onSave: () -> Void

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What's on your mind?")
                        .font(Theme.Typography.serifPrompt(15))
                        .foregroundStyle(Theme.inkFaded)
                        .padding(.top, 10)
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .padding(6)
                    .frame(height: 92)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.paperRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )

            Button {
                onSave()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11, weight: .medium))
                    Text("Save to mymind")
                }
            }
            .buttonStyle(InkButtonStyle(prominent: true))
            .disabled(trimmed.isEmpty)
            .opacity(trimmed.isEmpty ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.15), value: trimmed.isEmpty)
        }
    }
}

private struct SettingsPanel: View {
    @ObservedObject var settings: SettingsStore
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(GhostIconButtonStyle())

                Text("Settings.")
                    .font(Theme.Typography.wordmark(22))
                    .foregroundStyle(Theme.ink)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    settingsGroup(
                        title: "Credentials",
                        caption: "Stored securely in your macOS Keychain."
                    ) {
                        InkField(label: "Access key ID", text: $settings.configuration.keyID)
                        InkField(label: "Access key secret", text: $settings.configuration.secret, secure: true)
                    }

                    settingsGroup(
                        title: "Connection",
                        caption: "Defaults work for most people."
                    ) {
                        InkField(label: "Base URL", text: $settings.configuration.baseURLString)
                        InkField(label: "User-Agent", text: $settings.configuration.userAgent)
                        InkField(label: "API Version", text: $settings.configuration.apiVersion)
                        InkField(label: "Object URL template", text: $settings.configuration.objectURLTemplate)
                    }

                    HStack {
                        Spacer()
                        Button {
                            onSave()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Save settings")
                            }
                        }
                        .buttonStyle(InkButtonStyle(prominent: true))
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(
        title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold).smallCaps())
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
                Text(caption)
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(Theme.inkFaded)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }
}
